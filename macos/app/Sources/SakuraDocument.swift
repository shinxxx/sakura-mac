// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge

/// 一个文件（第 26 步：窗口框架）。
///
/// 用 AppKit 的 NSDocument 管理多窗口：打开、新建、同一文件不重复打开、关闭时询问保存、
/// 「最近使用的文件」、Finder 的「打开方式」都交给 NSDocumentController。
/// 内容本身在核心库的文档（EditorDocument）里，读写也用核心库（编码识别、BOM、换行符与原版相同）。
///
/// 原版是一个编辑窗口一个进程（CNormalProcess），Mac 版所有窗口在同一个进程里。
@objc(SakuraDocument)
final class SakuraDocument: NSDocument {
    private(set) var editor: EditorDocument

    override init() {
        // 核心库在 App 启动时（applicationWillFinishLaunching）已经启动
        guard let editor = EditorDocument() else {
            fatalError("Sakura core is not started")
        }
        self.editor = editor
        super.init()
    }

    // 原版没有自动保存到原文件和版本浏览，保存只在用户操作时进行
    override class var autosavesInPlace: Bool { false }
    override class var preservesVersions: Bool { false }

    // MARK: - 读写

    override func read(from url: URL, ofType typeName: String) throws {
        guard let editor = EditorDocument() else {
            throw CocoaError(.fileReadUnknown, userInfo: [NSURLErrorKey: url])
        }
        switch editor.open(path: url.path) {
        case .success, .lostSome:
            self.editor = editor
        case .failed:
            throw CocoaError(FileManager.default.fileExists(atPath: url.path) ? .fileReadNoPermission : .fileReadNoSuchFile,
                             userInfo: [NSURLErrorKey: url])
        default:
            throw CocoaError(.fileReadUnknown, userInfo: [NSURLErrorKey: url])
        }
    }

    /// 保存：直接用核心库写到目标文件（与原版相同，不经过临时文件），沿用打开时的编码和 BOM。
    /// 编码、换行符的选择在第 30 步加到保存对话框里。
    override func writeSafely(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType) throws {
        switch editor.save(to: url.path) {
        case .success, .lostSome:
            return
        default:
            throw CocoaError(.fileWriteUnknown, userInfo: [NSURLErrorKey: url])
        }
    }

    override func data(ofType typeName: String) throws -> Data {
        // writeSafely 已经覆盖了全部保存，这里不会被调用
        throw CocoaError(.featureUnsupported)
    }

    // 任何文件都能打开和保存，不强制扩展名
    override func fileNameExtension(forType typeName: String, saveOperation: NSDocument.SaveOperationType) -> String? {
        nil
    }

    override func prepareSavePanel(_ savePanel: NSSavePanel) -> Bool {
        savePanel.allowsOtherFileTypes = true
        savePanel.isExtensionHidden = false
        return true
    }

    // MARK: - 状态

    /// 是否修改过以核心库为准：撤销回到保存时的状态就不算修改（与原版的「(更新)」相同）
    override var isDocumentEdited: Bool { editor.isModified }

    /// 无题的文档与原版一样显示「(無題)」
    override var displayName: String! {
        get { fileURL == nil ? "(無題)" : super.displayName }
        set { super.displayName = newValue }
    }

    // MARK: - 窗口

    override func makeWindowControllers() {
        addWindowController(EditorWindowController(document: editor))
    }

    /// 内容变化后，让窗口的标题（「(更新)」）和关闭按钮的标记跟上
    func contentDidChange() {
        for controller in windowControllers {
            controller.synchronizeWindowTitleWithDocumentName()
            controller.window?.isDocumentEdited = isDocumentEdited
        }
    }
}

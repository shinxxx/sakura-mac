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
/// 打开、保存对话框里可以选编码、BOM、换行符（第 30 步，FileDialogAccessory）。
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

    /// 保存时用的编码、BOM、换行符（第 30 步）
    struct SaveSettings: Equatable {
        var encoding: EditorEncoding
        var bom: Bool
        /// .none 是不转换（「変換なし」）
        var eol: EditorEol
    }

    /// 打开对话框里指定的编码（文件路径 → 编码，SakuraDocumentController 设置）。没有指定时自动识别
    static var requestedEncodings: [String: EditorEncoding] = [:]

    static func encodingKey(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    /// 打开时有的字符不能用这个编码表示（窗口显示后告诉用户，原版 CCodeChecker::OnFinalLoad）
    private(set) var lostSomeOnLoad = false
    /// 保存对话框追加的部分（prepareSavePanel 里建立）
    private var saveAccessory: FileDialogAccessory?
    /// 下一次写出用的设置（保存前的检查之后决定）。没有时沿用现在的编码和 BOM，不转换换行符
    var nextSaveSettings: SaveSettings?

    override func read(from url: URL, ofType typeName: String) throws {
        guard let editor = EditorDocument() else {
            throw CocoaError(.fileReadUnknown, userInfo: [NSURLErrorKey: url])
        }
        let encoding = Self.requestedEncodings[Self.encodingKey(url)] ?? ECEncodingAutoDetect
        switch editor.open(path: url.path, encoding: encoding) {
        case .success:
            self.editor = editor
            lostSomeOnLoad = false
        case .lostSome:
            self.editor = editor
            lostSomeOnLoad = true
        case .failed:
            throw CocoaError(FileManager.default.fileExists(atPath: url.path) ? .fileReadNoPermission : .fileReadNoSuchFile,
                             userInfo: [NSURLErrorKey: url])
        default:
            throw CocoaError(.fileReadUnknown, userInfo: [NSURLErrorKey: url])
        }
    }

    /// 现在的编码和 BOM，不转换换行符（上書き保存）
    var currentSaveSettings: SaveSettings {
        SaveSettings(encoding: editor.encoding, bom: editor.hasBOM, eol: EditorEol.none)
    }

    /// 保存对话框里选的设置。上書き保存（对话框没有出来）时是现在的设置
    private func saveSettings(for saveOperation: NSDocument.SaveOperationType) -> SaveSettings {
        if let accessory = saveAccessory, saveOperation != .saveOperation || fileURL == nil {
            return SaveSettings(encoding: accessory.encoding, bom: accessory.bom, eol: accessory.eol)
        }
        return currentSaveSettings
    }

    /// 保存（对话框关闭后、或者上書き保存时）。先做原版的保存前检查（CCodeChecker::OnCheckSave），用户同意后再写出
    override func save(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType,
                       completionHandler: @escaping (Error?) -> Void) {
        let settings = saveSettings(for: saveOperation)
        saveAccessory = nil
        confirmSave(settings) { [self] confirmed in
            guard let confirmed else {
                completionHandler(CocoaError(.userCancelled))
                return
            }
            nextSaveSettings = confirmed
            super.save(to: url, ofType: typeName, for: saveOperation) { [self] error in
                nextSaveSettings = nil
                completionHandler(error)
            }
        }
    }

    /// 写出：直接用核心库写到目标文件（与原版相同，不经过临时文件）
    override func writeSafely(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType) throws {
        let settings = nextSaveSettings ?? currentSaveSettings
        let result = editor.save(to: url.path, encoding: settings.encoding, bom: settings.bom, eol: settings.eol)
        if settings.eol != EditorEol.none {
            // 换行符统一了：画面重新排版
            for case let controller as EditorWindowController in windowControllers {
                controller.textView.contentDidChange()
            }
        }
        switch result {
        case .success:
            return
        case .lostSome:
            // 原版 CCodeChecker::OnFinalSave
            DispatchQueue.main.async { [self] in
                showMessage(NSLocalizedString("一部の文字情報が、セーブ時の変換により失われました", comment: "STR_CODECHECKER_LOSESOME_SAVE"))
            }
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

    /// 保存对话框下面加「文字コードセット」「BOM」「改行コード」（原版 CDlgOpenFile::DoModalSaveDlg）
    override func prepareSavePanel(_ savePanel: NSSavePanel) -> Bool {
        savePanel.allowsOtherFileTypes = true
        savePanel.isExtensionHidden = false
        let accessory = FileDialogAccessory(mode: .save, encoding: editor.encoding, bom: editor.hasBOM)
        savePanel.accessoryView = accessory.view
        saveAccessory = accessory
        return true
    }

    // MARK: - 保存前的检查（原版 CCodeChecker::OnCheckSave）

    /// 换行符混在时问是否统一，有字符会丢失时问是否继续。completion 的参数是决定的设置，中止时是 nil
    func confirmSave(_ settings: SaveSettings, completion: @escaping (SaveSettings?) -> Void) {
        let check = editor.checkSave(encoding: settings.encoding, eol: settings.eol)
        var settings = settings
        let checkCharacters = { [self] in
            guard check.lostSome else {
                completion(settings)
                return
            }
            askLostCharacters(check, encoding: settings.encoding) { [self] response in
                switch response {
                case .alertFirstButtonReturn:	// はい：続行
                    completion(settings)
                case .alertSecondButtonReturn:	// いいえ：中断
                    completion(nil)
                default:						// キャンセル：該当位置に移動して中断
                    moveCaret(to: EditorPosition(line: check.lostLine, column: max(0, check.lostColumn)))
                    completion(nil)
                }
            }
        }
        guard check.eolMixed else {
            checkCharacters()
            return
        }
        let newLineEol = editor.newLineEol
        let alert = Self.yesNoCancelAlert(
            message: NSLocalizedString("改行コードが混在しています。", comment: "STR_CODECHECKER_EOL_UNIFY"),
            information: String(format: NSLocalizedString("現在の入力改行コード %@ に統一しますか？", comment: "STR_CODECHECKER_EOL_UNIFY"),
                                Self.eolName(newLineEol)))
        present(alert) { response in
            switch response {
            case .alertFirstButtonReturn:	// はい：統一
                settings.eol = newLineEol
            case .alertSecondButtonReturn:	// いいえ：続行
                break
            default:						// キャンセル：中断
                completion(nil)
                return
            }
            checkCharacters()
        }
    }

    private func askLostCharacters(_ check: EditorSaveCheck, encoding: EditorEncoding,
                                   completion: @escaping (NSApplication.ModalResponse) -> Void) {
        let place: String
        if check.lostColumn < 0 {
            place = String(format: NSLocalizedString("最初の場所 %ld行 文字[%@]", comment: "STR_CODECHECKER_CONFORM_LOSESOME"),
                           check.lostLine + 1, NSLocalizedString("不明", comment: "STR_ERR_CSHAREDATA22"))
        } else {
            place = String(format: NSLocalizedString("最初の場所 %ld行 %ld桁 文字[%@]%@", comment: "STR_CODECHECKER_CONFORM_LOSESOME"),
                           check.lostLine + 1, check.lostColumn + 1, check.lostCharacter, check.lostCharCode)
        }
        let alert = Self.yesNoCancelAlert(
            message: String(format: NSLocalizedString("文字エンコード %@ で保存しようとしていますが、文字コード変換により一部の文字情報が失われます。",
                                                      comment: "STR_CODECHECKER_CONFORM_LOSESOME"),
                            EditorCore.name(ofEncoding: encoding)),
            information: NSLocalizedString("保存処理を続行しますか？", comment: "STR_CODECHECKER_CONFORM_LOSESOME") + "\n" + place + "\n"
                + NSLocalizedString("キャンセル=該当位置に移動", comment: "STR_CODECHECKER_CONFORM_LOSESOME"))
        present(alert, completion: completion)
    }

    /// 原版的 MB_YESNOCANCEL | MB_ICONWARNING
    private static func yesNoCancelAlert(message: String, information: String) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = information
        alert.addButton(withTitle: NSLocalizedString("はい", comment: "メッセージボックス"))
        alert.addButton(withTitle: NSLocalizedString("いいえ", comment: "メッセージボックス"))
        let cancel = alert.addButton(withTitle: NSLocalizedString("キャンセル", comment: "メッセージボックス"))
        cancel.keyEquivalent = "\u{1b}"
        return alert
    }

    /// 换行符的名字（原版 CEol::GetName：IDS_EOLTYPENAME_*）
    static func eolName(_ eol: EditorEol) -> String {
        switch eol {
        case .crlf: return "CRLF"
        case .lf: return "LF"
        case .cr: return "CR"
        case .nel: return "NEL"
        case .lineSeparator: return "LS"
        case .paragraphSeparator: return "PS"
        default: return NSLocalizedString("改行無", comment: "IDS_EOLTYPENAME_0")
        }
    }

    /// 有窗口时作为窗口的表单显示，没有时作为对话框
    private func present(_ alert: NSAlert, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        if let window = windowControllers.first?.window, window.isVisible {
            alert.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(alert.runModal())
        }
    }

    private func showMessage(_ text: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = text
        present(alert) { _ in }
    }

    private func moveCaret(to position: EditorPosition) {
        for case let controller as EditorWindowController in windowControllers {
            controller.textView.setCaret(position)
            controller.window?.makeFirstResponder(controller.textView)
        }
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

    override func showWindows() {
        super.showWindows()
        if lostSomeOnLoad {
            lostSomeOnLoad = false
            showMessage(NSLocalizedString("一部の文字情報が、ロード時の変換により失われました", comment: "STR_CODECHECKER_LOSESOME_ROAD"))
        }
    }

    /// 内容变化后，让窗口的标题（「(更新)」）和关闭按钮的标记跟上
    func contentDidChange() {
        for controller in windowControllers {
            controller.synchronizeWindowTitleWithDocumentName()
            controller.window?.isDocumentEdited = isDocumentEdited
        }
    }
}

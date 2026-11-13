// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge

/// 编辑窗口（原版的 CEditWnd）。
///
/// 一个文件一个窗口，由 SakuraDocument（NSDocument）管理（第 26 步）。
/// 文本区域是自绘的 EditorTextView（第 25 步）。
/// 窗口之间可以合并成标签：macOS 自带的窗口标签，与原版的「タブまとめ表示」相当。
final class EditorWindowController: NSWindowController {
    /// 同一个标识的窗口可以合并成标签
    static let tabbingIdentifier = "SakuraEditorWindow"

    let editorDocument: EditorDocument
    let textView: EditorTextView

    init(document: EditorDocument) {
        editorDocument = document
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        // 按系统设置（「打开文稿时首选标签页」）决定新窗口是否作为标签打开。
        // 原版对应的设置（共通設定 > タブバー）在第 39 步接上
        window.tabbingIdentifier = Self.tabbingIdentifier
        window.tabbingMode = .automatic
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        textView = EditorTextView(document: document)
        scrollView.documentView = textView
        window.contentView = scrollView
        window.initialFirstResponder = textView
        super.init(window: window)
        // 新窗口错开一点，不完全重叠（原版也是层叠显示）
        shouldCascadeWindows = true
        textView.onChange = { [weak self] in
            (self?.document as? SakuraDocument)?.contentDidChange()
        }
        textView.contentDidChange()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// 标题与原版相同：文件名（无题时是「(無題)」），修改过时加「(更新)」；副标题显示编码
    override func windowTitle(forDocumentDisplayName displayName: String) -> String {
        if #available(macOS 11.0, *), let window {
            if editorDocument.path.isEmpty {
                window.subtitle = ""
            } else {
                var encoding = EditorCore.name(ofEncoding: editorDocument.encoding)
                if editorDocument.hasBOM { encoding += " BOM" }
                window.subtitle = encoding
            }
        }
        return displayName + (editorDocument.isModified ? " (更新)" : "")
    }
}

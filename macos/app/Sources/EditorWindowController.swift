// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge

/// 编辑窗口。
///
/// 通过桥接层持有一个文档（EditorDocument，第 24 步），文本区域是自绘的 EditorTextView（第 25 步）。
final class EditorWindowController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?
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
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        textView = EditorTextView(document: document)
        scrollView.documentView = textView
        window.contentView = scrollView
        window.cascadeTopLeft(from: NSPoint(x: 120, y: 120))
        super.init(window: window)
        window.delegate = self
        window.initialFirstResponder = textView
        textView.onChange = { [weak self] in self?.updateTitle() }
        updateTitle()
        textView.contentDidChange()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// 标题与原版相同：文件名（无题时是「(無題)」），修改过时加「(更新)」；副标题显示编码
    private func updateTitle() {
        guard let window else { return }
        let modified = editorDocument.isModified ? " (更新)" : ""
        window.isDocumentEdited = editorDocument.isModified
        guard !editorDocument.path.isEmpty else {
            window.title = "(無題)" + modified
            return
        }
        window.title = (editorDocument.path as NSString).lastPathComponent + modified
        window.representedFilename = editorDocument.path
        if #available(macOS 11.0, *) {
            var encoding = EditorCore.name(ofEncoding: editorDocument.encoding)
            if editorDocument.hasBOM { encoding += " BOM" }
            window.subtitle = encoding
        }
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}

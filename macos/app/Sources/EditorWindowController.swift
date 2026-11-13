// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge

/// 编辑窗口。
///
/// 第 24 步起通过桥接层持有一个文档（EditorDocument），文本区域只读显示它的内容。
/// 文本区域目前是简单的占位视图；阶段 2 会换成移植自原版的自绘文本视图
/// （Core Text 绘制 + NSTextInputClient 输入法支持）。
final class EditorWindowController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?
    let editorDocument: EditorDocument?

    init(document: EditorDocument? = EditorDocument()) {
        self.editorDocument = document
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        let view = PlaceholderEditorView(document: document)
        scrollView.documentView = view
        window.contentView = scrollView
        window.cascadeTopLeft(from: NSPoint(x: 120, y: 120))
        super.init(window: window)
        window.delegate = self
        updateTitle()
        view.updateSize(minimum: scrollView.contentSize)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// 标题与原版相同显示文件名（无题时是「(無題)」）；副标题显示编码
    private func updateTitle() {
        guard let window else { return }
        guard let document = editorDocument, !document.path.isEmpty else {
            window.title = "(無題)"
            return
        }
        window.title = (document.path as NSString).lastPathComponent
        window.representedFilename = document.path
        if #available(macOS 11.0, *) {
            var encoding = EditorCore.name(ofEncoding: document.encoding)
            if document.hasBOM { encoding += " BOM" }
            window.subtitle = encoding
        }
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}

/// 占位视图：白底，左侧是行号区域，逐行显示文档的内容，最后显示 [EOF]。
final class PlaceholderEditorView: NSView {
    private let document: EditorDocument?
    private let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    private let gutterWidth: CGFloat = 48
    private let margin: CGFloat = 6

    init(document: EditorDocument?) {
        self.document = document
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool { true }

    private var lineHeight: CGFloat { ceil(font.ascender - font.descender + font.leading) + 2 }
    private var lineCount: Int { document?.lineCount ?? 0 }

    /// 按行数决定视图的高度（宽度按最长的行粗略估计）
    func updateSize(minimum: NSSize) {
        var width: CGFloat = 0
        let charWidth = ("M" as NSString).size(withAttributes: [.font: font]).width
        for i in 0..<lineCount {
            width = max(width, CGFloat((document?.line(at: i) as NSString?)?.length ?? 0) * charWidth)
        }
        let height = CGFloat(lineCount + 1) * lineHeight + margin * 2
        setFrameSize(NSSize(width: max(minimum.width, gutterWidth + 8 + width + margin),
                            height: max(minimum.height, height)))
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        dirtyRect.fill()

        let gutter = NSRect(x: 0, y: dirtyRect.minY, width: gutterWidth, height: dirtyRect.height)
        NSColor.windowBackgroundColor.setFill()
        gutter.fill()

        let numberAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.textColor,
        ]

        // 只画看得见的行
        let first = max(0, Int((dirtyRect.minY - margin) / lineHeight))
        let last = min(lineCount, Int((dirtyRect.maxY - margin) / lineHeight) + 1)
        if first < last, let document {
            for i in first..<last {
                let y = margin + CGFloat(i) * lineHeight
                let number = "\(i + 1)" as NSString
                let numberWidth = number.size(withAttributes: numberAttributes).width
                number.draw(at: NSPoint(x: gutterWidth - 8 - numberWidth, y: y), withAttributes: numberAttributes)
                (document.line(at: i) as NSString).draw(at: NSPoint(x: gutterWidth + 8, y: y), withAttributes: textAttributes)
            }
        }
        // [EOF]：最后一行有换行符时在下一行，否则接在最后一行的后面（与原版相同）
        var eofLine = lineCount
        var eofX = gutterWidth + 8
        if let document, lineCount > 0, document.eol(ofLine: lineCount - 1) == EditorEol.none {
            eofLine = lineCount - 1
            eofX += (document.line(at: eofLine) as NSString).size(withAttributes: textAttributes).width
        }
        if lineCount == 0 {
            ("1" as NSString).draw(at: NSPoint(x: gutterWidth - 20, y: margin), withAttributes: numberAttributes)
        }
        ("[EOF]" as NSString).draw(at: NSPoint(x: eofX, y: margin + CGFloat(eofLine) * lineHeight), withAttributes: numberAttributes)
    }
}

// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import CoreText
import EditorBridge

/// 自绘的文本视图（第 25 步：输入法原型）。
///
/// 目的是尽早确认“自己画文字的视图”能接好日文、中文输入法（NSTextInputClient）。
/// 文字用 Core Text 逐行绘制，不用 NSTextView。只有光标，没有选择范围、自动换行、语法颜色；
/// 这些在第 27～30 步移植原版的 CEditView 时加入，输入法的部分沿用这里的做法。
///
/// 未确定文字（marked text）不放进文档，只在画面上插在光标的位置显示，确定时才写进文档。
/// 这样输入中的变化不进撤销记录，与原版相同（原版在确定时才收到文字）。
///
/// NSTextInputClient 用的位置是“虚拟文字”里的 UTF-16 下标：文档全文在光标的位置插入未确定文字。
/// 没有未确定文字时就是文档全文的下标。
final class EditorTextView: NSView, NSTextInputClient, NSMenuItemValidation {
    let document: EditorDocument
    /// 内容变化时调用（窗口用来更新标题的「(更新)」）
    var onChange: (() -> Void)?

    /// 光标（逻辑位置：行号和行内的 UTF-16 下标）
    private(set) var caret = EditorPosition(line: 0, column: 0)
    /// 上下移动时想保持的横向位置
    private var preferredX: CGFloat?

    private var markedText = NSAttributedString()
    /// 未确定文字里输入法选中的部分（正在转换的文节），相对于未确定文字的开头
    private var markedSelection = NSRange(location: 0, length: 0)

    let font: NSFont
    let gutterWidth: CGFloat = 48
    let textLeft: CGFloat = 8
    let topMargin: CGFloat = 6
    let lineHeight: CGFloat

    init(document: EditorDocument, font: NSFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)) {
        self.document = document
        self.font = font
        lineHeight = ceil(font.ascender - font.descender + font.leading) + 4
        super.init(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { true }

    // MARK: - 位置的换算

    private var lineCount: Int { document.lineCount }

    private func lineText(_ line: Int) -> NSString {
        line < lineCount ? document.line(at: line) as NSString : ""
    }

    private func lineLengthWithEol(_ line: Int) -> Int {
        (document.line(at: line, withEol: true) as NSString).length
    }

    /// 逻辑位置 → 文档全文的下标
    func offset(of position: EditorPosition) -> Int {
        var offset = 0
        for i in 0..<min(position.line, lineCount) {
            offset += lineLengthWithEol(i)
        }
        return offset + position.column
    }

    /// 文档全文的下标 → 逻辑位置（落在换行符中间时取换行符之前）
    func position(ofOffset offset: Int) -> EditorPosition {
        var rest = max(0, offset)
        for i in 0..<lineCount {
            let body = lineText(i).length
            if rest <= body { return EditorPosition(line: i, column: rest) }
            let whole = lineLengthWithEol(i)
            if rest < whole { return EditorPosition(line: i, column: body) }
            rest -= whole
        }
        return document.endPosition
    }

    private var markedStart: Int { offset(of: caret) }
    private var markedLength: Int { markedText.length }

    /// 虚拟文字的下标 → 文档全文的下标（未确定文字里的位置都算在光标处）
    private func documentOffset(fromVirtual v: Int) -> Int {
        guard hasMarkedText() else { return v }
        let start = markedStart
        if v <= start { return v }
        if v < start + markedLength { return start }
        return v - markedLength
    }

    /// 虚拟文字的下标 → 画面上的行和该行显示文字里的下标
    private func displayPosition(ofVirtual v: Int) -> (line: Int, column: Int) {
        guard hasMarkedText() else {
            let p = position(ofOffset: v)
            return (p.line, p.column)
        }
        let start = markedStart
        if v >= start && v <= start + markedLength {
            return (caret.line, caret.column + v - start)
        }
        let p = position(ofOffset: documentOffset(fromVirtual: v))
        if v > start && p.line == caret.line && p.column >= caret.column {
            return (p.line, p.column + markedLength)
        }
        return (p.line, p.column)
    }

    // MARK: - 排版（一行一个 CTLine）

    /// 画面上显示的一行：光标所在行插入未确定文字
    private func displayText(_ line: Int) -> NSString {
        let text = lineText(line)
        guard hasMarkedText(), line == caret.line else { return text }
        let column = min(caret.column, text.length)
        return text.replacingCharacters(in: NSRange(location: column, length: 0), with: markedText.string) as NSString
    }

    private func ctLine(_ line: Int) -> CTLine {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ]
        return CTLineCreateWithAttributedString(NSAttributedString(string: displayText(line) as String, attributes: attributes))
    }

    private func xOffset(_ ctLine: CTLine, _ column: Int) -> CGFloat {
        CTLineGetOffsetForStringIndex(ctLine, column, nil)
    }

    private func lineTop(_ line: Int) -> CGFloat {
        topMargin + CGFloat(line) * lineHeight
    }

    private var textOriginX: CGFloat { gutterWidth + textLeft }

    /// 画面上显示的行数（最后一行有换行符时，下面还有一个空行可以放光标）
    private var displayLineCount: Int { max(lineCount, document.endPosition.line + 1) }

    /// 视图坐标里的一点 → 逻辑位置
    func position(at point: NSPoint) -> EditorPosition {
        let line = min(max(0, Int((point.y - topMargin) / lineHeight)), displayLineCount - 1)
        let text = lineText(line)
        let index = CTLineGetStringIndexForPosition(ctLine(line), CGPoint(x: point.x - textOriginX, y: 0))
        let column = index == kCFNotFound ? text.length : min(max(0, index), text.length)
        return EditorPosition(line: line, column: column)
    }

    /// 光标在视图坐标里的矩形（有未确定文字时在输入法选中的位置）
    var caretRect: NSRect {
        let column = caret.column + (hasMarkedText() ? markedSelection.location : 0)
        let x = textOriginX + xOffset(ctLine(caret.line), column)
        return NSRect(x: x, y: lineTop(caret.line), width: 2, height: lineHeight)
    }

    // MARK: - 绘制

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        NSColor.textBackgroundColor.setFill()
        dirtyRect.fill()
        NSColor.windowBackgroundColor.setFill()
        NSRect(x: 0, y: dirtyRect.minY, width: gutterWidth, height: dirtyRect.height).fill()

        let numberAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let first = max(0, Int((dirtyRect.minY - topMargin) / lineHeight))
        let last = min(displayLineCount, Int((dirtyRect.maxY - topMargin) / lineHeight) + 1)
        if first < last {
            for line in first..<last {
                let top = lineTop(line)
                let number = "\(line + 1)" as NSString
                let numberWidth = number.size(withAttributes: numberAttributes).width
                number.draw(at: NSPoint(x: gutterWidth - 8 - numberWidth, y: top + 2), withAttributes: numberAttributes)

                let ct = ctLine(line)
                let baseline = top + 2 + font.ascender
                // 视图是上下翻转的，Core Text 的文字要再翻回来
                context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
                context.setFillColor(NSColor.textColor.cgColor)
                context.textPosition = CGPoint(x: textOriginX, y: baseline)
                CTLineDraw(ct, context)
                if hasMarkedText() && line == caret.line {
                    drawMarkedUnderlines(ct, baseline: baseline)
                }
            }
        }
        drawEOF(numberAttributes)
        if window?.firstResponder === self {
            NSColor.textColor.setFill()
            caretRect.fill()
        }
    }

    /// 未确定文字的下划线：文节分开画，正在转换的文节用粗线
    private func drawMarkedUnderlines(_ ct: CTLine, baseline: CGFloat) {
        let start = caret.column
        for segment in markedSegments() {
            let x0 = textOriginX + xOffset(ct, start + segment.location)
            let x1 = textOriginX + xOffset(ct, start + NSMaxRange(segment))
            let selected = markedSelection.length > 0 && NSIntersectionRange(segment, markedSelection).length > 0
            let thickness: CGFloat = selected ? 2 : 1
            NSColor.textColor.setFill()
            NSRect(x: x0 + 1, y: baseline + 3, width: max(0, x1 - x0 - 2), height: thickness).fill()
        }
    }

    /// 输入法给的文节（NSMarkedClauseSegment）。没有时整个未确定文字算一个文节
    func markedSegments() -> [NSRange] {
        var segments: [NSRange] = []
        let whole = NSRange(location: 0, length: markedText.length)
        markedText.enumerateAttribute(.markedClauseSegment, in: whole) { _, range, _ in
            segments.append(range)
        }
        return segments.isEmpty ? [whole] : segments
    }

    /// [EOF]：最后一行有换行符时在下一行，否则接在最后一行的后面（与原版相同）
    private func drawEOF(_ attributes: [NSAttributedString.Key: Any]) {
        let end = document.endPosition
        let x = textOriginX + xOffset(ctLine(end.line), end.column + (hasMarkedText() && caret.line == end.line ? markedLength : 0))
        ("[EOF]" as NSString).draw(at: NSPoint(x: x + 4, y: lineTop(end.line) + 2), withAttributes: attributes)
    }

    /// 按内容决定视图的大小，并让光标可见
    func contentDidChange() {
        var width: CGFloat = 0
        for line in 0..<displayLineCount {
            width = max(width, CGFloat(CTLineGetTypographicBounds(ctLine(line), nil, nil, nil)))
        }
        let visible = enclosingScrollView?.contentSize ?? frame.size
        let size = NSSize(width: max(visible.width, textOriginX + width + 80),
                          height: max(visible.height, topMargin * 2 + CGFloat(displayLineCount + 1) * lineHeight))
        if frame.size != size { setFrameSize(size) }
        scrollToVisible(caretRect.insetBy(dx: -8, dy: 0))
        needsDisplay = true
        inputContext?.invalidateCharacterCoordinates()
    }

    private func textChanged() {
        preferredX = nil
        contentDidChange()
        onChange?()
    }

    func setCaret(_ position: EditorPosition, keepPreferredX: Bool = false) {
        let line = min(max(0, position.line), displayLineCount - 1)
        caret = EditorPosition(line: line, column: min(max(0, position.column), lineText(line).length))
        if !keepPreferredX { preferredX = nil }
        contentDidChange()
    }

    // MARK: - 键盘和鼠标

    override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        return true
    }

    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        return true
    }

    override func keyDown(with event: NSEvent) {
        // 先交给输入法；输入法不要的键变成 insertText(_:replacementRange:) 或 doCommand(by:)
        interpretKeyEvents([event])
    }

    override func mouseDown(with event: NSEvent) {
        if inputContext?.handleEvent(event) == true { return }
        window?.makeFirstResponder(self)
        if hasMarkedText() {
            unmarkText()
            inputContext?.discardMarkedText()
        }
        setCaret(position(at: convert(event.locationInWindow, from: nil)))
    }

    override func doCommand(by selector: Selector) {
        // 输入法和按键分配把方向键、Backspace 等变成选择子。这里只处理原型需要的几个
        if responds(to: selector) {
            perform(selector, with: nil)
        }
    }

    private func replace(_ range: EditorRange, with text: String) {
        var end = EditorPosition()
        guard document.replace(range, with: text, newEnd: &end) == .success else {
            NSSound.beep()
            return
        }
        caret = end
        textChanged()
    }

    override func insertNewline(_ sender: Any?) {
        replace(EditorRange(from: caret, to: caret), with: EditorCore.text(ofEol: document.newLineEol))
    }

    override func insertTab(_ sender: Any?) {
        replace(EditorRange(from: caret, to: caret), with: "\t")
    }

    override func deleteBackward(_ sender: Any?) {
        let start: EditorPosition
        if caret.column > 0 {
            let text = lineText(caret.line)
            start = EditorPosition(line: caret.line, column: text.rangeOfComposedCharacterSequence(at: caret.column - 1).location)
        } else if caret.line > 0 {
            start = EditorPosition(line: caret.line - 1, column: lineText(caret.line - 1).length)
        } else {
            return
        }
        replace(EditorRange(from: start, to: caret), with: "")
    }

    override func deleteForward(_ sender: Any?) {
        let text = lineText(caret.line)
        let end: EditorPosition
        if caret.column < text.length {
            end = EditorPosition(line: caret.line, column: NSMaxRange(text.rangeOfComposedCharacterSequence(at: caret.column)))
        } else if caret.line + 1 < displayLineCount {
            end = EditorPosition(line: caret.line + 1, column: 0)
        } else {
            return
        }
        replace(EditorRange(from: caret, to: end), with: "")
    }

    override func moveLeft(_ sender: Any?) {
        if caret.column > 0 {
            let text = lineText(caret.line)
            setCaret(EditorPosition(line: caret.line, column: text.rangeOfComposedCharacterSequence(at: caret.column - 1).location))
        } else if caret.line > 0 {
            setCaret(EditorPosition(line: caret.line - 1, column: lineText(caret.line - 1).length))
        }
    }

    override func moveRight(_ sender: Any?) {
        let text = lineText(caret.line)
        if caret.column < text.length {
            setCaret(EditorPosition(line: caret.line, column: NSMaxRange(text.rangeOfComposedCharacterSequence(at: caret.column))))
        } else if caret.line + 1 < displayLineCount {
            setCaret(EditorPosition(line: caret.line + 1, column: 0))
        }
    }

    private func moveVertically(_ delta: Int) {
        let target = caret.line + delta
        guard target >= 0 && target < displayLineCount else { return }
        let x = preferredX ?? xOffset(ctLine(caret.line), caret.column)
        preferredX = x
        let index = CTLineGetStringIndexForPosition(ctLine(target), CGPoint(x: x, y: 0))
        setCaret(EditorPosition(line: target, column: index == kCFNotFound ? 0 : index), keepPreferredX: true)
    }

    override func moveUp(_ sender: Any?) { moveVertically(-1) }
    override func moveDown(_ sender: Any?) { moveVertically(1) }

    override func moveToBeginningOfLine(_ sender: Any?) {
        setCaret(EditorPosition(line: caret.line, column: 0))
    }

    override func moveToEndOfLine(_ sender: Any?) {
        setCaret(EditorPosition(line: caret.line, column: lineText(caret.line).length))
    }

    override func moveToBeginningOfDocument(_ sender: Any?) {
        setCaret(EditorPosition(line: 0, column: 0))
    }

    override func moveToEndOfDocument(_ sender: Any?) {
        setCaret(document.endPosition)
    }

    override func moveToLeftEndOfLine(_ sender: Any?) { moveToBeginningOfLine(sender) }
    override func moveToRightEndOfLine(_ sender: Any?) { moveToEndOfLine(sender) }

    // 編集 > 元に戻す / やり直し（F_UNDO / F_REDO）
    @objc func undo(_ sender: Any?) {
        guard !hasMarkedText(), document.canUndo else { return }
        if document.undo() == .success { afterUndoRedo() }
    }

    @objc func redo(_ sender: Any?) {
        guard !hasMarkedText(), document.canRedo else { return }
        if document.redo() == .success { afterUndoRedo() }
    }

    private func afterUndoRedo() {
        // 第 30 步移植原版的撤销后光标位置之前，先把光标放到范围内
        let end = document.endPosition
        if caret.line > end.line || (caret.line == end.line && caret.column > end.column) {
            caret = end
        } else {
            caret = EditorPosition(line: caret.line, column: min(caret.column, lineText(caret.line).length))
        }
        textChanged()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(undo(_:)): return !hasMarkedText() && document.canUndo
        case #selector(redo(_:)): return !hasMarkedText() && document.canRedo
        default: return true
        }
    }

    // MARK: - NSTextInputClient

    private static func plainString(_ string: Any) -> String {
        if let attributed = string as? NSAttributedString { return attributed.string }
        return string as? String ?? ""
    }

    func insertText(_ string: Any, replacementRange: NSRange) {
        let text = Self.plainString(string)
        var range = EditorRange(from: caret, to: caret)
        if replacementRange.location != NSNotFound {
            let from = position(ofOffset: documentOffset(fromVirtual: replacementRange.location))
            let to = position(ofOffset: documentOffset(fromVirtual: NSMaxRange(replacementRange)))
            range = EditorRange(from: from, to: to)
        }
        clearMarkedText()
        replace(range, with: text)
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        // 重新转换等：输入法要求把文档里的一段换成未确定文字
        if replacementRange.location != NSNotFound {
            let from = position(ofOffset: documentOffset(fromVirtual: replacementRange.location))
            let to = position(ofOffset: documentOffset(fromVirtual: NSMaxRange(replacementRange)))
            if replacementRange.length > 0 {
                clearMarkedText()
                replace(EditorRange(from: from, to: to), with: "")
            }
            caret = from
        }
        let attributed: NSAttributedString
        if let string = string as? NSAttributedString {
            attributed = string
        } else {
            attributed = NSAttributedString(string: Self.plainString(string))
        }
        // 未确定文字里的换行不显示成换行（换成空格，长度不变，下标和输入法的一致）
        let mutable = NSMutableAttributedString(attributedString: attributed)
        let chars = mutable.mutableString
        for i in 0..<chars.length where chars.character(at: i) == 0x0A || chars.character(at: i) == 0x0D {
            chars.replaceCharacters(in: NSRange(location: i, length: 1), with: " ")
        }
        markedText = mutable
        let length = markedText.length
        let location = min(max(0, selectedRange.location), length)
        markedSelection = NSRange(location: location, length: min(selectedRange.length, length - location))
        contentDidChange()
    }

    private func clearMarkedText() {
        markedText = NSAttributedString()
        markedSelection = NSRange(location: 0, length: 0)
    }

    /// 输入法要求确定：未确定文字照原样写进文档
    func unmarkText() {
        guard hasMarkedText() else { return }
        let text = markedText.string
        clearMarkedText()
        replace(EditorRange(from: caret, to: caret), with: text)
    }

    func selectedRange() -> NSRange {
        if hasMarkedText() {
            return NSRange(location: markedStart + markedSelection.location, length: markedSelection.length)
        }
        return NSRange(location: offset(of: caret), length: 0)
    }

    func markedRange() -> NSRange {
        hasMarkedText() ? NSRange(location: markedStart, length: markedLength) : NSRange(location: NSNotFound, length: 0)
    }

    func hasMarkedText() -> Bool {
        markedText.length > 0
    }

    /// 虚拟文字（文档全文 + 未确定文字）
    private func virtualText() -> NSString {
        let text = document.text as NSString
        guard hasMarkedText() else { return text }
        return text.replacingCharacters(in: NSRange(location: min(markedStart, text.length), length: 0), with: markedText.string) as NSString
    }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        let text = virtualText()
        guard range.location != NSNotFound, range.location <= text.length else { return nil }
        let actual = NSRange(location: range.location, length: min(range.length, text.length - range.location))
        actualRange?.pointee = actual
        return NSAttributedString(string: text.substring(with: actual), attributes: [.font: font])
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        [.underlineStyle, .underlineColor, .markedClauseSegment]
    }

    /// 输入法问一段文字在屏幕上的位置（候选窗口放在它下面）。跨行时只回答第一行的部分
    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        let location = range.location == NSNotFound ? selectedRange().location : range.location
        let start = displayPosition(ofVirtual: location)
        let lineLength = displayText(start.line).length
        let endColumn = min(start.column + max(0, range.length), lineLength)
        actualRange?.pointee = NSRange(location: location, length: max(0, endColumn - start.column))

        let ct = ctLine(start.line)
        let x0 = textOriginX + xOffset(ct, start.column)
        let x1 = textOriginX + xOffset(ct, endColumn)
        let rect = NSRect(x: x0, y: lineTop(start.line), width: max(0, x1 - x0), height: lineHeight)
        guard let window else { return .zero }
        return window.convertToScreen(convert(rect, to: nil))
    }

    /// 屏幕上的一点 → 虚拟文字的下标
    func characterIndex(for point: NSPoint) -> Int {
        guard let window else { return NSNotFound }
        let local = convert(window.convertPoint(fromScreen: point), from: nil)
        let line = min(max(0, Int((local.y - topMargin) / lineHeight)), displayLineCount - 1)
        let index = CTLineGetStringIndexForPosition(ctLine(line), CGPoint(x: local.x - textOriginX, y: 0))
        let column = index == kCFNotFound ? 0 : min(max(0, index), displayText(line).length)
        // 显示行里的下标 → 虚拟文字的下标
        var lineStart = offset(of: EditorPosition(line: line, column: 0))
        if hasMarkedText() && line > caret.line { lineStart += markedLength }
        return lineStart + column
    }

    func windowLevel() -> Int {
        window?.level.rawValue ?? NSWindow.Level.normal.rawValue
    }
}

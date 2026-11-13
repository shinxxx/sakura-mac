// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import CoreText
import EditorBridge

/// 自绘的文本视图（原版的 CEditView）。
///
/// - 第 25 步：输入法（NSTextInputClient）。
/// - 第 27 步：按核心库的排版（原版的 CLayoutMgr）显示：自动换行、TAB 的展开、
///   TAB・全角空白・改行・折り返し・EOF 的记号、行号。字符放在核心库算出的位置上
///   （与原版用 ExtTextOut 的文字间隔数组逐字放置相同），所以换行位置、TAB 位置与原版一致。
///
/// 颜色暂时用系统的颜色，按类型别设置的颜色、字体在第 28 步。
///
/// 未确定文字（marked text）不放进文档，只在画面上插在光标的位置显示，确定时才写进文档。
/// 这样输入中的变化不进撤销记录，与原版相同（原版在确定时才收到文字）。
/// 未确定文字显示在光标所在的排版行里，后面的文字往右让开（不重新换行）。
///
/// NSTextInputClient 用的位置是“虚拟文字”里的 UTF-16 下标：文档全文在光标的位置插入未确定文字。
/// 没有未确定文字时就是文档全文的下标。
final class EditorTextView: NSView, NSTextInputClient, NSMenuItemValidation {
    /// 排版和绘制用的字体（第 27 步。按设置选择字体在第 28 步）。
    /// 排版（核心库）和绘制必须用同一个字体，App 启动时用它调用 EditorCore.setLayoutFont
    static let fontName = "Menlo"
    static let fontSize = 13

    let document: EditorDocument
    /// 内容变化时调用（窗口用来更新标题的「(更新)」）
    var onChange: (() -> Void)?

    /// 光标（逻辑位置：行号和行内的 UTF-16 下标）
    private(set) var caret = EditorPosition(line: 0, column: 0)
    /// 光标正好在折り返し的位置时，显示在上一排版行的末尾（End 键、点在行末的右边）。
    /// 原版的光标用排版位置记录，所以能区分这两个位置
    private var caretAtLineEnd = false
    /// 上下移动时想保持的横向位置（视图坐标）
    private var preferredX: CGFloat?

    private var markedText = NSAttributedString() {
        didSet {
            markedLine = CTLineCreateWithAttributedString(NSAttributedString(string: markedText.string, attributes: [.font: font]))
            markedWidth = markedText.length > 0 ? CGFloat(CTLineGetTypographicBounds(markedLine, nil, nil, nil)) : 0
        }
    }
    /// 未确定文字（一行，不换行）和它的宽度
    private var markedLine: CTLine = CTLineCreateWithAttributedString(NSAttributedString())
    private var markedWidth: CGFloat = 0
    /// 未确定文字里输入法选中的部分（正在转换的文节），相对于未确定文字的开头
    private var markedSelection = NSRange(location: 0, length: 0)

    let font: NSFont
    /// 显示设置（类型别设置）。内容变化时重新取得（折り返し方法可能变了）
    private(set) var settings: EditorViewSettings
    let topMargin: CGFloat = 2
    /// 行的高度：文字的高度 + 行間（原版 CTextMetrics 的 GetHankakuDy）
    let lineHeight: CGFloat
    /// 文字的高度（原版的 GetHankakuHeight）
    private let charHeight: CGFloat
    private let ascent: CGFloat
    private var markColor: NSColor { .tertiaryLabelColor }

    init(document: EditorDocument, font: NSFont? = nil) {
        self.document = document
        self.font = font
            ?? NSFont(name: Self.fontName, size: CGFloat(Self.fontSize))
            ?? NSFont.monospacedSystemFont(ofSize: CGFloat(Self.fontSize), weight: .regular)
        settings = document.viewSettings
        ascent = ceil(self.font.ascender)
        charHeight = ceil(self.font.ascender - self.font.descender)
        lineHeight = charHeight + CGFloat(max(0, settings.lineSpacing))
        super.init(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { true }

    // MARK: - 逻辑位置的换算

    private var lineCount: Int { document.lineCount }

    private func lineText(_ line: Int) -> NSString {
        line < lineCount ? document.line(at: line) as NSString : ""
    }

    private func lineLengthWithEol(_ line: Int) -> Int {
        (document.line(at: line, withEol: true) as NSString).length
    }

    private static func same(_ a: EditorPosition, _ b: EditorPosition) -> Bool {
        a.line == b.line && a.column == b.column
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

    // MARK: - 排版行（核心库的排版，第 27 步）

    /// 画面上的一行：一个排版行，或者文档末尾的空行（最后一行以换行结束时放光标和 [EOF] 的行）
    private struct Row {
        let start: EditorPosition       //!< 在逻辑行里的开始位置
        let text: NSString              //!< 这一段的文字（不含换行符）
        let eol: EditorEol              //!< 带的换行符（逻辑行的最后一段）
        let xs: [CGFloat]               //!< 每个字符的左端（相对文字区域的左端），最后多一个
        let isLayoutLine: Bool          //!< false：文档末尾的空行
    }

    private var rowCache: [Int: Row] = [:]

    /// 画面上的行数
    var displayLineCount: Int {
        let count = document.layoutLineCount
        if count == 0 { return 1 }
        return document.layoutLine(at: count - 1).eol != .none ? count + 1 : count
    }

    private func row(_ index: Int) -> Row {
        if let cached = rowCache[index] { return cached }
        let row: Row
        if index >= 0 && index < document.layoutLineCount {
            let layout = document.layoutLine(at: index)
            let text = lineText(layout.start.line)
            let length = max(0, min(layout.length, text.length - layout.start.column))
            row = Row(start: layout.start,
                      text: text.substring(with: NSRange(location: layout.start.column, length: length)) as NSString,
                      eol: layout.eol,
                      xs: document.charPositions(ofLayoutLine: index).map { CGFloat($0.intValue) },
                      isLayoutLine: true)
        } else {
            row = Row(start: document.endPosition, text: "", eol: .none, xs: [0], isLayoutLine: false)
        }
        rowCache[index] = row
        return row
    }

    /// 这一行之后接着同一逻辑行的下一段（折り返した行）
    private func isWrapped(_ index: Int) -> Bool {
        let r = row(index)
        return r.isLayoutLine && r.eol == .none && index + 1 < document.layoutLineCount
    }

    /// 逻辑位置 → 画面上的行和行内下标。preferLineEnd 时，折り返し的位置算上一行的末尾
    private func rowAndIndex(of position: EditorPosition, preferLineEnd: Bool = false) -> (row: Int, index: Int) {
        let layout = document.layoutPosition(of: position)
        var r = min(max(0, layout.line), displayLineCount - 1)
        if preferLineEnd && r > 0 && isWrapped(r - 1) && Self.same(row(r).start, position) {
            r -= 1
            return (r, row(r).text.length)
        }
        let current = row(r)
        let index = position.line == current.start.line ? position.column - current.start.column : 0
        return (r, min(max(0, index), current.text.length))
    }

    /// 光标所在的行和行内下标
    private var caretRowAndIndex: (row: Int, index: Int) {
        rowAndIndex(of: caret, preferLineEnd: caretAtLineEnd)
    }

    /// 画面上的行和行内下标 → 逻辑位置
    private func position(row r: Int, index: Int) -> EditorPosition {
        let current = row(r)
        if !current.isLayoutLine { return current.start }
        return EditorPosition(line: current.start.line, column: current.start.column + min(max(0, index), current.text.length))
    }

    // MARK: - 坐标

    /// 一个半角字的宽度（核心库的排版单位）
    private var charWidth: CGFloat { CGFloat(max(1, document.charWidth)) }

    /// 行号的位数（原版 CTextArea::DetectWidthOfLineNumberArea_calculate）
    private var lineNumberDigits: Int {
        let count = settings.lineNumberPerLogicalLine ? lineCount : document.layoutLineCount
        return max(settings.lineNumberMinDigits, String(max(1, count)).count)
    }

    /// 行号区域的宽度：位数 + 前面的空白 1 字 + 右边的间隔 1 字（原版的 m_nViewAlignLeftCols）。
    /// 不显示行号时 8 点（与原版相同）
    var gutterWidth: CGFloat {
        settings.showLineNumbers ? charWidth * CGFloat(lineNumberDigits + 2) : 8
    }

    private var textOriginX: CGFloat { gutterWidth }

    private func lineTop(_ row: Int) -> CGFloat {
        topMargin + CGFloat(row) * lineHeight
    }

    private func rowIndex(atY y: CGFloat) -> Int {
        min(max(0, Int(floor((y - topMargin) / lineHeight))), displayLineCount - 1)
    }

    /// 行内下标的横向位置（视图坐标）。光标所在的行里，光标之后的文字让开未确定文字的宽度
    private func displayX(row r: Int, index: Int) -> CGFloat {
        let xs = row(r).xs
        var x = textOriginX + xs[min(max(0, index), xs.count - 1)]
        if hasMarkedText() {
            let c = caretRowAndIndex
            if r == c.row && index >= c.index { x += markedWidth }
        }
        return x
    }

    /// 横向位置 → 行内下标（最近的字符边界，不落在补充平面字符的中间）
    private func index(row r: Int, x: CGFloat) -> Int {
        let current = row(r)
        let length = current.text.length
        var result = length
        for i in 0..<length {
            let left = displayX(row: r, index: i)
            let right = displayX(row: r, index: i + 1)
            if x < right {
                result = (x - left) > (right - left) / 2 ? i + 1 : i
                break
            }
        }
        if result < length {
            result = current.text.rangeOfComposedCharacterSequence(at: result).location
        }
        return result
    }

    /// 视图坐标里的一点 → 逻辑位置。行末的右边是那一行的末尾（折り返した行也一样）
    func position(at point: NSPoint) -> EditorPosition {
        let r = rowIndex(atY: point.y)
        return position(row: r, index: index(row: r, x: point.x))
    }

    /// 光标在视图坐标里的矩形（有未确定文字时在输入法选中的位置）
    var caretRect: NSRect {
        let c = caretRowAndIndex
        var x = displayX(row: c.row, index: c.index)
        if hasMarkedText() {
            x = textOriginX + row(c.row).xs[c.index] + CTLineGetOffsetForStringIndex(markedLine, markedSelection.location, nil)
        }
        return NSRect(x: x, y: lineTop(c.row), width: 2, height: lineHeight)
    }

    // MARK: - 绘制

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        NSColor.textBackgroundColor.setFill()
        dirtyRect.fill()
        if settings.showLineNumbers {
            NSColor.windowBackgroundColor.setFill()
            NSRect(x: 0, y: dirtyRect.minY, width: gutterWidth, height: dirtyRect.height).fill()
            // 行番号区切り（縦線）：原版的默认值
            NSColor.separatorColor.setFill()
            NSRect(x: gutterWidth - 2, y: dirtyRect.minY, width: 1, height: dirtyRect.height).fill()
        }

        let first = rowIndex(atY: dirtyRect.minY)
        let last = min(displayLineCount, Int((dirtyRect.maxY - topMargin) / lineHeight) + 1)
        if first < last {
            for r in first..<last {
                drawRow(r, context: context)
            }
        }
        if window?.firstResponder === self {
            NSColor.textColor.setFill()
            caretRect.fill()
        }
    }

    private func drawRow(_ r: Int, context: CGContext) {
        let current = row(r)
        let top = lineTop(r)
        let baseline = top + ascent
        let markAttributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: markColor]

        // 行号（原版 CTextDrawer::DispLineNumber）：按逻辑行数时，折り返した行不显示行号。EOF 的空行没有行号
        if settings.showLineNumbers && current.isLayoutLine {
            let number: String
            if settings.lineNumberPerLogicalLine {
                number = current.start.column == 0 ? String(current.start.line + 1) : ""
            } else {
                number = String(r + 1)
            }
            let columns = lineNumberDigits + 2
            let x = CGFloat(columns - number.count - 1) * charWidth
            (number as NSString).draw(at: NSPoint(x: x, y: top),
                                      withAttributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor])
        }

        drawGlyphs(current, row: r, baseline: baseline, context: context)

        // 空白、TAB 的记号
        for i in 0..<current.text.length {
            let c = current.text.character(at: i)
            let x = displayX(row: r, index: i)
            let width = displayX(row: r, index: i + 1) - x
            switch c {
            case 0x09 where settings.showTab:
                drawTab(x: x, width: width, top: top, attributes: markAttributes)
            case 0x3000 where settings.showFullWidthSpace:
                drawFullWidthSpace(x: x, width: width, top: top)
            case 0x20 where settings.showSpace:
                drawHalfWidthSpace(x: x, width: width, top: top, attributes: markAttributes)
            default:
                break
            }
        }

        // 行末：改行記号、折り返し記号、[EOF]（原版 CEditView::DrawLayoutLine）
        let endX = displayX(row: r, index: current.text.length)
        if current.eol != .none {
            if settings.showEol {
                drawEol(current.eol, rect: NSRect(x: endX + 1, y: top, width: charWidth, height: charHeight))
            }
        } else if isWrapped(r) {
            if settings.showWrapMark {
                ("<" as NSString).draw(at: NSPoint(x: endX, y: top), withAttributes: markAttributes)
            }
        } else if settings.showEof {
            ("[EOF]" as NSString).draw(at: NSPoint(x: endX, y: top), withAttributes: markAttributes)
        }

        // 未确定文字
        if hasMarkedText() && r == caretRowAndIndex.row {
            let x = textOriginX + current.xs[caretRowAndIndex.index]
            context.saveGState()
            context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)	// 视图是上下翻转的，Core Text 的文字要再翻回来
            context.setFillColor(NSColor.textColor.cgColor)
            context.textPosition = CGPoint(x: x, y: baseline)
            CTLineDraw(markedLine, context)
            context.restoreGState()
            drawMarkedUnderlines(x: x, baseline: baseline)
        }
    }

    /// 文字：Core Text 选字形（没有的字由系统换成其他字体），位置用核心库的排版结果
    private func drawGlyphs(_ current: Row, row r: Int, baseline: CGFloat, context: CGContext) {
        guard current.text.length > 0 else { return }
        let attributed = NSAttributedString(string: current.text as String, attributes: [.font: font])
        let line = CTLineCreateWithAttributedString(attributed)
        guard let runs = CTLineGetGlyphRuns(line) as? [CTRun] else { return }
        context.saveGState()
        // 视图是上下翻转的：以基线为原点再翻回来，字形才是正的
        context.translateBy(x: 0, y: baseline)
        context.scaleBy(x: 1, y: -1)
        context.textMatrix = .identity
        context.setFillColor(NSColor.textColor.cgColor)
        for run in runs {
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { continue }
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var indices = [CFIndex](repeating: 0, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
            CTRunGetStringIndices(run, CFRange(location: 0, length: 0), &indices)
            // 这一段的字体（这个字体里没有的字，Core Text 换成了其他字体）
            let attributes = CTRunGetAttributes(run) as NSDictionary
            let runFont: CTFont = attributes[kCTFontAttributeName as String].map { $0 as! CTFont } ?? (font as CTFont)
            var drawn: [CGGlyph] = []
            var positions: [CGPoint] = []
            for k in 0..<count {
                let index = indices[k]
                let c = current.text.character(at: index)
                // TAB、全角空白（显示记号时）不画字形
                if c == 0x09 || (c == 0x3000 && settings.showFullWidthSpace) { continue }
                drawn.append(glyphs[k])
                positions.append(CGPoint(x: displayX(row: r, index: index), y: 0))
            }
            if !drawn.isEmpty {
                CTFontDrawGlyphs(runFont, drawn, positions, drawn.count, context)
            }
        }
        context.restoreGState()
    }

    /// TAB 記号（原版 CFigure_Tab）
    private func drawTab(x: CGFloat, width: CGFloat, top: CGFloat, attributes: [NSAttributedString.Key: Any]) {
        switch settings.tabMark {
        case .string:
            // 文字指定：一个字占一桁，只画 TAB 宽度里放得下的部分
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath.clip(NSRect(x: x, y: top, width: width, height: lineHeight))
            let string = settings.tabString as NSString
            for i in 0..<string.length {
                let cx = x + CGFloat(i) * charWidth
                if cx >= x + width { break }
                let c = string.substring(with: NSRange(location: i, length: 1))
                if c != " " { (c as NSString).draw(at: NSPoint(x: cx, y: top), withAttributes: attributes) }
            }
            NSGraphicsContext.restoreGraphicsState()
        case .shortArrow:
            drawTabArrow(x: x, width: charWidth, top: top)
        case .longArrow:
            drawTabArrow(x: x, width: width, top: top)
        @unknown default:
            break
        }
    }

    /// 原版 _DrawTabArrow：横线和箭头
    private func drawTabArrow(x: CGFloat, width: CGFloat, top: CGFloat) {
        let sx = x + width - 2
        let sy = top + floor(charHeight / 2) + 0.5
        let sa = floor(charHeight / 4)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: x, y: sy))
        path.line(to: NSPoint(x: sx, y: sy))
        path.line(to: NSPoint(x: sx - sa, y: sy + sa))
        path.move(to: NSPoint(x: sx, y: sy))
        path.line(to: NSPoint(x: sx - sa, y: sy - sa))
        strokeMark(path)
    }

    /// 日本語空白（原版 CFigure_ZenSpace）：「□」
    private func drawFullWidthSpace(x: CGFloat, width: CGFloat, top: CGFloat) {
        let rect = NSRect(x: x + 1.5, y: top + 1.5,
                          width: max(1, width - CGFloat(settings.columnSpacing) - 3), height: max(1, charHeight - 3))
        strokeMark(NSBezierPath(rect: rect))
    }

    /// 半角空白（原版 CFigure_HanSpace）：「o」的下半部分
    private func drawHalfWidthSpace(x: CGFloat, width: CGFloat, top: CGFloat, attributes: [NSAttributedString.Key: Any]) {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath.clip(NSRect(x: x, y: top + floor(charHeight / 2), width: width, height: lineHeight))
        ("o" as NSString).draw(at: NSPoint(x: x, y: top), withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
    }

    /// 改行記号（原版 _DrawEOL）。换行符的种类不同，形状不同
    private func drawEol(_ eol: EditorEol, rect: NSRect) {
        let path = NSBezierPath()
        let w = rect.width, h = rect.height
        let q = floor(h / 4)
        switch eol {
        case .crlf:     // 向下再向左的箭头
            let sx = rect.minX, sy = rect.minY + floor(h / 2) + 0.5
            path.move(to: NSPoint(x: sx + w, y: sy - q))
            path.line(to: NSPoint(x: sx + w, y: sy))
            path.line(to: NSPoint(x: sx, y: sy))
            path.move(to: NSPoint(x: sx + q, y: sy + q))
            path.line(to: NSPoint(x: sx, y: sy))
            path.line(to: NSPoint(x: sx + q, y: sy - q))
        case .cr:       // 向左的箭头
            let sx = rect.minX, sy = rect.minY + floor(h / 2) + 0.5
            path.move(to: NSPoint(x: sx + w, y: sy))
            path.line(to: NSPoint(x: sx, y: sy))
            path.line(to: NSPoint(x: sx + q, y: sy + q))
            path.move(to: NSPoint(x: sx, y: sy))
            path.line(to: NSPoint(x: sx + q, y: sy - q))
        case .lf:       // 向下的箭头
            let sx = rect.minX + floor(w / 2) + 0.5, sy = rect.minY + floor(h * 3 / 4)
            path.move(to: NSPoint(x: sx, y: rect.minY + q + 1))
            path.line(to: NSPoint(x: sx, y: sy))
            path.line(to: NSPoint(x: sx - q, y: sy - q))
            path.move(to: NSPoint(x: sx, y: sy))
            path.line(to: NSPoint(x: sx + q, y: sy - q))
        case .nel, .lineSeparator, .paragraphSeparator:   // 向左下的箭头（不拐弯）
            let sx = rect.minX + 0.5, sy = rect.minY + floor(h * 3 / 4) + 0.5
            let n = min(w, floor(h / 2))
            path.move(to: NSPoint(x: sx + n, y: sy - n))
            path.line(to: NSPoint(x: sx, y: sy))
            path.move(to: NSPoint(x: sx + n, y: sy))
            path.line(to: NSPoint(x: sx, y: sy))
            path.line(to: NSPoint(x: sx, y: sy - n))
        default:
            return
        }
        strokeMark(path)
    }

    private func strokeMark(_ path: NSBezierPath) {
        path.lineWidth = 1
        markColor.setStroke()
        path.stroke()
    }

    /// 未确定文字的下划线：文节分开画，正在转换的文节用粗线
    private func drawMarkedUnderlines(x: CGFloat, baseline: CGFloat) {
        let line = markedLine
        for segment in markedSegments() {
            let x0 = x + CTLineGetOffsetForStringIndex(line, segment.location, nil)
            let x1 = x + CTLineGetOffsetForStringIndex(line, NSMaxRange(segment), nil)
            let selected = markedSelection.length > 0 && NSIntersectionRange(segment, markedSelection).length > 0
            let thickness: CGFloat = selected ? 2 : 1
            NSColor.textColor.setFill()
            NSRect(x: x0 + 1, y: baseline + 2, width: max(0, x1 - x0 - 2), height: thickness).fill()
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

    // MARK: - 内容的变化

    /// 内容、光标、排版变化后：重新取得排版，决定视图的大小，让光标可见
    func contentDidChange() {
        rowCache.removeAll()
        settings = document.viewSettings
        let visible = enclosingScrollView?.contentSize ?? frame.size
        // 文字部分的宽度 + 行末的记号（改行記号 1 桁 + 4 点，[EOF] 5 桁）
        let textWidth = CGFloat(document.layoutWidth) + charWidth * 6 + markedWidth
        let width = settings.wrapMethod == .windowWidth ? visible.width : max(visible.width, textOriginX + textWidth)
        let size = NSSize(width: width,
                          height: max(visible.height, topMargin * 2 + CGFloat(displayLineCount + 1) * lineHeight))
        if frame.size != size { setFrameSize(size) }
        scrollToVisible(caretRect.insetBy(dx: -8, dy: 0))
        needsDisplay = true
        inputContext?.invalidateCharacterCoordinates()
    }

    private func textChanged() {
        preferredX = nil
        caretAtLineEnd = false
        contentDidChange()
        onChange?()
    }

    func setCaret(_ position: EditorPosition, keepPreferredX: Bool = false, atLineEnd: Bool = false) {
        let end = document.endPosition
        var line = min(max(0, position.line), end.line)
        var column = max(0, position.column)
        if line == end.line && line >= lineCount {
            column = 0
        } else {
            column = min(column, lineText(line).length)
        }
        if line < 0 { line = 0 }
        caret = EditorPosition(line: line, column: column)
        caretAtLineEnd = atLineEnd
        if !keepPreferredX { preferredX = nil }
        contentDidChange()
    }

    // MARK: - 折り返し方法（第 27 步：設定 > 折り返し方法。原版 F_TMPWRAPNOWRAP 等）

    /// 折り返さない
    @objc func wrapNone(_ sender: Any?) {
        applyWrap(.none)
    }

    /// 指定桁で折り返す（类型别设置的桁数）
    @objc func wrapSettingWidth(_ sender: Any?) {
        applyWrap(.settingWidth)
    }

    /// 右端で折り返す
    @objc func wrapWindowWidth(_ sender: Any?) {
        applyWrap(.windowWidth)
    }

    private func applyWrap(_ method: EditorWrapMethod) {
        let columns: Int
        switch method {
        case .settingWidth: columns = settings.typeWrapColumns
        case .windowWidth: columns = windowWrapColumns
        default: columns = 0
        }
        if document.setWrap(method, columns: columns) {
            contentDidChange()
        }
    }

    /// 「右端で折り返す」的桁数：看得见的宽度减去行号的宽度
    private var windowWrapColumns: Int {
        let visible = enclosingScrollView?.contentSize.width ?? frame.width
        return document.wrapColumns(forWidth: Int(max(0, visible - textOriginX)))
    }

    /// 窗口的大小变了：「右端で折り返す」时让折り返し桁数跟着变（原版 CEditWnd::WrapWindowWidth）
    @objc private func visibleSizeDidChange(_ notification: Notification) {
        if settings.wrapMethod == .windowWidth && document.setWrap(.windowWidth, columns: windowWrapColumns) {
            contentDidChange()
        } else {
            needsDisplay = true
        }
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        NotificationCenter.default.removeObserver(self, name: NSView.frameDidChangeNotification, object: nil)
        if let clipView = enclosingScrollView?.contentView {
            clipView.postsFrameChangedNotifications = true
            NotificationCenter.default.addObserver(self, selector: #selector(visibleSizeDidChange(_:)),
                                                   name: NSView.frameDidChangeNotification, object: clipView)
        }
        // 类型别设置是「右端で折り返す」时，按现在的宽度排版
        if settings.wrapMethod == .windowWidth {
            _ = document.setWrap(.windowWidth, columns: windowWrapColumns)
            contentDidChange()
        }
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
        let point = convert(event.locationInWindow, from: nil)
        let r = rowIndex(atY: point.y)
        let i = index(row: r, x: point.x)
        // 点在折り返した行的右边时，光标在这一行的末尾（不是下一行的开头）
        setCaret(position(row: r, index: i), atLineEnd: isWrapped(r) && i == row(r).text.length)
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
        } else if caret.line < document.endPosition.line {
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
        } else if caret.line < document.endPosition.line {
            setCaret(EditorPosition(line: caret.line + 1, column: 0))
        }
    }

    /// 上下移动：按排版行移动（折り返した行里也一行一行地移动）。横向位置尽量保持
    private func moveVertically(_ delta: Int) {
        let current = caretRowAndIndex
        let target = current.row + delta
        guard target >= 0 && target < displayLineCount else { return }
        let x = preferredX ?? displayX(row: current.row, index: current.index)
        preferredX = x
        let i = index(row: target, x: x)
        setCaret(position(row: target, index: i), keepPreferredX: true, atLineEnd: isWrapped(target) && i == row(target).text.length)
    }

    override func moveUp(_ sender: Any?) { moveVertically(-1) }
    override func moveDown(_ sender: Any?) { moveVertically(1) }

    /// 行首、行末是排版行的开头、末尾（与原版相同，折り返した行里就在这一段里）
    override func moveToBeginningOfLine(_ sender: Any?) {
        setCaret(position(row: caretRowAndIndex.row, index: 0))
    }

    override func moveToEndOfLine(_ sender: Any?) {
        let r = caretRowAndIndex.row
        setCaret(position(row: r, index: row(r).text.length), atLineEnd: isWrapped(r))
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
        // 折り返し方法：现在的方法打勾（原版 IsFuncChecked）
        case #selector(wrapNone(_:)):
            menuItem.state = settings.wrapMethod == .none ? .on : .off
            return !hasMarkedText()
        case #selector(wrapSettingWidth(_:)):
            menuItem.state = settings.wrapMethod == .settingWidth ? .on : .off
            return !hasMarkedText()
        case #selector(wrapWindowWidth(_:)):
            menuItem.state = settings.wrapMethod == .windowWidth ? .on : .off
            return !hasMarkedText()
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

    /// 虚拟文字的下标 → 画面上的行和横向位置（视图坐标）。
    /// preferLineEnd 时，折り返し的位置算上一行的末尾（范围的终点用）
    private func displayPoint(ofVirtual v: Int, preferLineEnd: Bool = false) -> (row: Int, x: CGFloat) {
        if hasMarkedText() {
            let start = markedStart
            if v >= start && v <= start + markedLength {
                let c = caretRowAndIndex
                return (c.row, textOriginX + row(c.row).xs[c.index] + CTLineGetOffsetForStringIndex(markedLine, v - start, nil))
            }
        }
        let p = position(ofOffset: documentOffset(fromVirtual: v))
        let ri = Self.same(p, caret) ? caretRowAndIndex : rowAndIndex(of: p, preferLineEnd: preferLineEnd)
        return (ri.row, displayX(row: ri.row, index: ri.index))
    }

    /// 输入法问一段文字在屏幕上的位置（候选窗口放在它下面）。跨行时只回答第一行的部分
    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        let location = range.location == NSNotFound ? selectedRange().location : range.location
        let start = displayPoint(ofVirtual: location)
        // 终点：同一行里能到的最远的位置
        var endLocation = location
        var endX = start.x
        let limit = min(location + max(0, range.length), virtualLength)
        if location < limit {
            for v in (location + 1)...limit {
                let p = displayPoint(ofVirtual: v, preferLineEnd: true)
                if p.row != start.row { break }
                endLocation = v
                endX = p.x
            }
        }
        actualRange?.pointee = NSRange(location: location, length: endLocation - location)
        let rect = NSRect(x: start.x, y: lineTop(start.row), width: max(0, endX - start.x), height: lineHeight)
        guard let window else { return .zero }
        return window.convertToScreen(convert(rect, to: nil))
    }

    /// 虚拟文字的长度
    private var virtualLength: Int {
        (document.text as NSString).length + markedLength
    }

    /// 屏幕上的一点 → 虚拟文字的下标
    func characterIndex(for point: NSPoint) -> Int {
        guard let window else { return NSNotFound }
        let local = convert(window.convertPoint(fromScreen: point), from: nil)
        let r = rowIndex(atY: local.y)
        if hasMarkedText() {
            // 未确定文字的上面
            let c = caretRowAndIndex
            let x0 = textOriginX + row(c.row).xs[c.index]
            if r == c.row && local.x >= x0 && local.x < x0 + markedWidth {
                let index = CTLineGetStringIndexForPosition(markedLine, CGPoint(x: local.x - x0, y: 0))
                return markedStart + min(max(0, index == kCFNotFound ? 0 : index), markedLength)
            }
        }
        let p = position(row: r, index: index(row: r, x: local.x))
        let documentOffset = offset(of: p)
        // 光标之后的文字：虚拟文字里在未确定文字的后面
        if hasMarkedText() && (p.line > caret.line || (p.line == caret.line && p.column > caret.column)) {
            return documentOffset + markedLength
        }
        return documentOffset
    }

    func windowLevel() -> Int {
        window?.level.rawValue ?? NSWindow.Level.normal.rawValue
    }
}

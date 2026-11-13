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
/// - 第 28 步：按类型别设置的颜色绘制（与原版相同，深色模式下编辑区也用设置的颜色），
///   光标（闪烁、输入法打开时的颜色）、カーソル行アンダーライン、选择范围（普通和矩形）、字体的选择。
///
/// 未确定文字（marked text）不放进文档，只在画面上插在光标的位置显示，确定时才写进文档。
/// 这样输入中的变化不进撤销记录，与原版相同（原版在确定时才收到文字）。
/// 未确定文字显示在光标所在的排版行里，后面的文字往右让开（不重新换行）。
///
/// NSTextInputClient 用的位置是“虚拟文字”里的 UTF-16 下标：文档全文在光标的位置插入未确定文字。
/// 没有未确定文字时就是文档全文的下标。
final class EditorTextView: NSView, NSTextInputClient, NSMenuItemValidation, NSFontChanging {
    /// 默认的字体（第 27 步）。原版的默认是「ＭＳ ゴシック」10 点（13 像素），
    /// Mac 版用系统自带的等宽字体 Menlo 13 点（日文由系统换成其他字体显示，宽度按全角 2 桁排）
    static let defaultFontName = "Menlo"
    static let defaultFontSize = 13

    /// 现在的字体（第 28 步：設定 > フォント設定）。排版（核心库）和绘制必须用同一个字体。
    /// 共通设置窗口（第 39 步）之前，暂时存在 UserDefaults 里
    static var fontName: String {
        UserDefaults.standard.string(forKey: fontNameKey) ?? defaultFontName
    }
    static var fontSize: Int {
        let size = UserDefaults.standard.integer(forKey: fontSizeKey)
        return size > 0 ? size : defaultFontSize
    }
    private static let fontNameKey = "EditorFontName"
    private static let fontSizeKey = "EditorFontSize"

    /// 现在的字体
    static var currentFont: NSFont {
        NSFont(name: fontName, size: CGFloat(fontSize))
            ?? NSFont(name: defaultFontName, size: CGFloat(defaultFontSize))
            ?? NSFont.monospacedSystemFont(ofSize: CGFloat(defaultFontSize), weight: .regular)
    }

    /// 字体改变后通知所有编辑视图（各自重新排版）
    static let fontDidChangeNotification = Notification.Name("EditorFontDidChange")

    /// 改变字体：保存，告诉核心库，所有窗口重新排版（原版 CEditWnd::OnChangeSetting）
    static func setFont(_ font: NSFont) {
        let size = max(6, min(72, Int(font.pointSize.rounded())))
        UserDefaults.standard.set(font.fontName, forKey: fontNameKey)
        UserDefaults.standard.set(size, forKey: fontSizeKey)
        EditorCore.setLayoutFont(name: font.fontName, size: size)
        NotificationCenter.default.post(name: fontDidChangeNotification, object: nil)
    }

    /// 键盘的设置：关掉「按住字母键弹出重音字符」（ApplePressAndHoldEnabled），按住键时连续输入（原版相同）。
    /// 放在注册域里：用户在终端里明确设置过时，按用户的设置
    static func registerInputDefaults() {
        UserDefaults.standard.register(defaults: ["ApplePressAndHoldEnabled": false])
    }

    /// 测试用：回到默认的字体
    static func resetFont() {
        UserDefaults.standard.removeObject(forKey: fontNameKey)
        UserDefaults.standard.removeObject(forKey: fontSizeKey)
        EditorCore.setLayoutFont(name: defaultFontName, size: defaultFontSize)
    }

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

    private(set) var font: NSFont
    private var boldFont: NSFont
    /// 显示设置（类型别设置）。内容变化时重新取得（折り返し方法可能变了）
    private(set) var settings: EditorViewSettings
    let topMargin: CGFloat = 2
    /// 行的高度：文字的高度 + 行間（原版 CTextMetrics 的 GetHankakuDy）
    private(set) var lineHeight: CGFloat = 0
    /// 文字的高度（原版的 GetHankakuHeight）
    private var charHeight: CGFloat = 0
    private var ascent: CGFloat = 0

    /// 类型别设置的颜色（第 28 步）。下标是 EditorColorIndex 的数值
    private var colors: [EditorColorSetting] = []

    /// 选择的起点（逻辑位置）。nil 时没有选择。普通选择是起点到光标之间（原版 CViewSelect）
    private(set) var selectionAnchor: EditorPosition?
    /// 矩形选择（原版 Alt+拖动，Mac 版 Option+拖动）
    private(set) var isBoxSelection = false
    /// 矩形选择的起点和终点：画面上的行和横向位置（文字区域里的点，按桁对齐）
    private var boxAnchor = BoxPoint(row: 0, x: 0)
    private var boxEnd = BoxPoint(row: 0, x: 0)
    struct BoxPoint: Equatable {
        var row: Int
        var x: CGFloat
    }

    /// 光标的闪烁
    private var caretBlinkTimer: Timer?
    private var caretBlinkOn = true

    init(document: EditorDocument, font: NSFont? = nil) {
        self.document = document
        self.font = font ?? Self.currentFont
        boldFont = NSFontManager.shared.convert(self.font, toHaveTrait: .boldFontMask)
        settings = document.viewSettings
        super.init(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        updateFontMetrics()
        reloadColors()
        NotificationCenter.default.addObserver(self, selector: #selector(fontDidChange(_:)),
                                               name: Self.fontDidChangeNotification, object: nil)
        // 输入法打开、关闭时，光标的颜色跟着变
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardInputSourceDidChange(_:)),
                                               name: NSTextInputContext.keyboardSelectionDidChangeNotification, object: nil)
    }

    deinit {
        caretBlinkTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    private func updateFontMetrics() {
        ascent = ceil(font.ascender)
        charHeight = ceil(font.ascender - font.descender)
        lineHeight = charHeight + CGFloat(max(0, settings.lineSpacing))
    }

    /// 字体变了（設定 > フォント設定）：重新排版，重新计算行高
    @objc private func fontDidChange(_ notification: Notification) {
        font = Self.currentFont
        boldFont = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        document.relayout()
        settings = document.viewSettings
        updateFontMetrics()
        clearSelection()
        if settings.wrapMethod == .windowWidth {
            _ = document.setWrap(.windowWidth, columns: windowWrapColumns)
        }
        let markedString = markedText
        markedText = markedString	// 未确定文字也用新的字体
        contentDidChange()
    }

    @objc private func keyboardInputSourceDidChange(_ notification: Notification) {
        needsDisplay = true
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

    // MARK: - 颜色（第 28 步）

    /// 重新取得类型别设置的颜色
    private func reloadColors() {
        colors = (0...EditorColorIndex.select.rawValue).map {
            document.color(for: EditorColorIndex(rawValue: $0) ?? .text)
        }
    }

    func color(_ index: EditorColorIndex) -> EditorColorSetting {
        index.rawValue < colors.count ? colors[index.rawValue] : document.color(for: index)
    }

    /// 0xRRGGBB → NSColor（原版的 COLORREF 是 sRGB）
    static func nsColor(_ rgb: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
                green: CGFloat((rgb >> 8) & 0xFF) / 255,
                blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }

    /// 文字的背景色（原版的 m_crBack）
    private var textBack: UInt32 { color(.text).back }

    /// 原版 MakeColor2：a 占 alpha/256，b 占其余
    static func mix(_ a: UInt32, _ b: UInt32, alpha: UInt32 = 255 * 30 / 100) -> UInt32 {
        func channel(_ shift: UInt32) -> UInt32 {
            (((a >> shift) & 0xFF) * alpha + ((b >> shift) & 0xFF) * (256 - alpha)) / 256
        }
        return (channel(16) << 16) | (channel(8) << 8) | channel(0)
    }

    /// 原版 CEditView::GetTextColorByColorInfo2：info（选择范围等）叠在 base 上时的文字色。
    /// 文字色和背景色相同时是「反転表示」（背景是文字的背景色时）或 30% 的半透明
    func overlayTextColor(_ info: EditorColorSetting, on base: UInt32) -> UInt32 {
        if info.text != info.back { return info.text }
        if info.back == textBack { return base ^ 0xFFFFFF }
        return Self.mix(info.text, base)
    }

    /// 原版 CEditView::GetBackColorByColorInfo2：叠在 base 上时的背景色
    func overlayBackColor(_ info: EditorColorSetting, on base: UInt32) -> UInt32 {
        if info.text != info.back { return info.back }
        if info.back == textBack { return base ^ 0xFFFFFF }
        return Self.mix(info.back, base)
    }

    /// 行的背景色（原版：カーソル行背景色 > 奇数行の背景色 > テキスト）
    func rowBackColor(_ r: Int) -> UInt32 {
        let caretLine = color(.caretLineBackground)
        if caretLine.display && r == caretRowAndIndex.row { return caretLine.back }
        let even = color(.evenLineBackground)
        if even.display && r % 2 == 1 { return even.back }
        return textBack
    }

    /// 记号等的背景色：与文字的背景色相同时用行的背景色（原版的「透過」）
    private func backColor(_ info: EditorColorSetting, rowBack: UInt32) -> UInt32 {
        info.back == textBack ? rowBack : info.back
    }

    // MARK: - 选择（第 28 步）

    private static func less(_ a: EditorPosition, _ b: EditorPosition) -> Bool {
        a.line < b.line || (a.line == b.line && a.column < b.column)
    }

    /// 普通的选择范围（从前到后）。没有选择或矩形选择时 nil
    var selection: EditorRange? {
        guard let anchor = selectionAnchor, !isBoxSelection, !Self.same(anchor, caret) else { return nil }
        return Self.less(anchor, caret) ? EditorRange(from: anchor, to: caret) : EditorRange(from: caret, to: anchor)
    }

    /// 矩形选择的范围：画面上的行（top...bottom）和横向位置（文字区域里的点，left..<right）
    var boxSelection: (top: Int, bottom: Int, left: CGFloat, right: CGFloat)? {
        guard isBoxSelection, boxAnchor != boxEnd else { return nil }
        return (min(boxAnchor.row, boxEnd.row), max(boxAnchor.row, boxEnd.row),
                min(boxAnchor.x, boxEnd.x), max(boxAnchor.x, boxEnd.x))
    }

    var hasSelection: Bool { selection != nil || boxSelection != nil }

    func clearSelection() {
        if selectionAnchor != nil || isBoxSelection { needsDisplay = true }
        selectionAnchor = nil
        isBoxSelection = false
    }

    /// 普通选择时，这一行里被选中的字符（行内下标）和是否选中了换行符
    private func selectedIndices(row r: Int) -> (range: Range<Int>, eol: Bool)? {
        guard let sel = selection else { return nil }
        let current = row(r)
        guard current.isLayoutLine else { return nil }
        let line = current.start.line
        if line < sel.from.line || line > sel.to.line { return nil }
        let rowStart = current.start.column
        let length = current.text.length
        let from = line == sel.from.line ? sel.from.column - rowStart : Int.min / 2
        let to = line == sel.to.line ? sel.to.column - rowStart : Int.max / 2
        let lo = min(max(0, from), length)
        let hi = max(lo, min(length, to))
        let eol = current.eol != .none && line < sel.to.line && from <= length
        if lo == hi && !eol { return nil }
        return (lo..<hi, eol)
    }

    /// 这一行的这个字符是否被选中
    private func isSelected(row r: Int, index i: Int, indices: (range: Range<Int>, eol: Bool)?) -> Bool {
        if let indices { return indices.range.contains(i) }
        if let box = boxSelection, r >= box.top && r <= box.bottom {
            let x = row(r).xs[min(i, row(r).xs.count - 1)]
            return x >= box.left && x < box.right
        }
        return false
    }

    // MARK: - 绘制

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        // 整体是文字的背景色。没有行的地方（[EOF] 的下面）行号区域也是这个颜色（原版 DispLineNumber）
        Self.nsColor(textBack).setFill()
        dirtyRect.fill()
        if !settings.showLineNumbers {
            // 不显示行号时左边 8 点的空白：行号的背景色（原版相同）
            let number = color(.lineNumber)
            Self.nsColor(backColor(number, rowBack: textBack)).setFill()
            NSRect(x: 0, y: dirtyRect.minY, width: gutterWidth, height: dirtyRect.height).fill()
        }

        let first = rowIndex(atY: dirtyRect.minY)
        let last = min(displayLineCount, Int((dirtyRect.maxY - topMargin) / lineHeight) + 1)
        if first < last {
            for r in first..<last {
                drawRow(r, context: context)
            }
        }

        // カーソル位置縦線（原版 CCaret::DrawCursorVLine。默认不显示）
        let columnLine = color(.cursorColumnLine)
        if columnLine.display && !hasMarkedText() {
            Self.nsColor(columnLine.text).setFill()
            NSRect(x: caretRect.minX, y: dirtyRect.minY, width: 1, height: dirtyRect.height).fill()
        }

        if window?.firstResponder === self && caretBlinkOn {
            Self.nsColor(caretColor).setFill()
            caretRect.fill()
        }
    }

    /// 光标的颜色：输入法打开时用「IMEキャレット」的颜色（原版 CCaret::ShowEditCaret）
    var caretColor: UInt32 {
        isInputMethodOn ? color(.caretIme).text : color(.caret).text
    }

    /// 输入法是否打开（日文、中文等的输入方式，罗马字输入的「英字」不算）
    private var isInputMethodOn: Bool {
        guard let source = inputContext?.selectedKeyboardInputSource else { return false }
        return source.contains(".inputmethod.") && !source.hasSuffix(".Roman")
    }

    private func drawRow(_ r: Int, context: CGContext) {
        let current = row(r)
        let top = lineTop(r)
        let baseline = top + ascent
        let rowBack = rowBackColor(r)
        let textArea = NSRect(x: textOriginX, y: top, width: max(0, bounds.width - textOriginX), height: lineHeight)
        if rowBack != textBack {
            Self.nsColor(rowBack).setFill()
            textArea.fill()
        }

        // 行号（原版 CTextDrawer::DispLineNumber）：按逻辑行数时，折り返した行不显示行号。EOF 的空行没有行号
        if settings.showLineNumbers && current.isLayoutLine {
            drawLineNumber(current, row: r, top: top, rowBack: rowBack)
        } else if settings.showLineNumbers && rowBack != textBack {
            Self.nsColor(rowBack).setFill()
            NSRect(x: 0, y: top, width: gutterWidth, height: lineHeight).fill()
        }

        // 选择范围的背景
        let indices = selectedIndices(row: r)
        let select = color(.select)
        let selectBack = Self.nsColor(overlayBackColor(select, on: rowBack))
        if select.display {
            selectBack.setFill()
            if let indices, !indices.range.isEmpty {
                let x0 = displayX(row: r, index: indices.range.lowerBound)
                let x1 = displayX(row: r, index: indices.range.upperBound)
                NSRect(x: x0, y: top, width: x1 - x0, height: lineHeight).fill()
            }
            if let box = boxSelection, r >= box.top && r <= box.bottom {
                // 矩形选择：没有文字的部分也涂（原版「テキストのない部分の矩形選択を作画」）
                NSRect(x: textOriginX + box.left, y: top, width: box.right - box.left, height: lineHeight).fill()
            }
        }

        drawGlyphs(current, row: r, baseline: baseline, rowBack: rowBack, indices: indices, context: context)

        // 空白、TAB 的记号
        for i in 0..<current.text.length {
            let c = current.text.character(at: i)
            let x = displayX(row: r, index: i)
            let width = displayX(row: r, index: i + 1) - x
            let selected = select.display && isSelected(row: r, index: i, indices: indices)
            switch c {
            case 0x09 where settings.showTab:
                drawTab(x: x, width: width, top: top, color: markColor(.tab, selected: selected, rowBack: rowBack))
            case 0x3000 where settings.showFullWidthSpace:
                drawFullWidthSpace(x: x, width: width, top: top, color: markColor(.fullWidthSpace, selected: selected, rowBack: rowBack))
            case 0x20 where settings.showSpace:
                drawHalfWidthSpace(x: x, width: width, top: top, color: markColor(.space, selected: selected, rowBack: rowBack))
            default:
                break
            }
        }

        // 行末：改行記号、折り返し記号、[EOF]（原版 CEditView::DrawLayoutLine）
        let endX = displayX(row: r, index: current.text.length)
        if current.eol != .none {
            let eolSelected = select.display && (indices?.eol ?? false)
            let eolRect = NSRect(x: endX, y: top, width: charWidth + 4, height: lineHeight)
            if eolSelected {
                selectBack.setFill()
                eolRect.fill()
            } else {
                let eolBack = backColor(color(.eol), rowBack: rowBack)
                if eolBack != rowBack {
                    Self.nsColor(eolBack).setFill()
                    eolRect.fill()
                }
            }
            if settings.showEol {
                drawEol(current.eol, rect: NSRect(x: endX + 1, y: top, width: charWidth, height: charHeight),
                        color: markColor(.eol, selected: eolSelected, rowBack: rowBack))
            }
        } else if isWrapped(r) {
            if settings.showWrapMark {
                drawMarkText("<", x: endX, top: top, info: color(.wrapMark), rowBack: rowBack)
            }
        } else if settings.showEof {
            drawMarkText("[EOF]", x: endX, top: top, info: color(.eof), rowBack: rowBack)
        }

        // カーソル行アンダーライン（原版 CCaretUnderLine）：选择中不画
        let underline = color(.caretLineUnderline)
        if underline.display && r == caretRowAndIndex.row && !hasSelection {
            Self.nsColor(underline.text).setFill()
            NSRect(x: textOriginX, y: top + lineHeight - 1, width: textArea.width, height: 1).fill()
        }

        // 未确定文字
        if hasMarkedText() && r == caretRowAndIndex.row {
            let x = textOriginX + current.xs[caretRowAndIndex.index]
            Self.nsColor(rowBack).setFill()
            NSRect(x: x, y: top, width: markedWidth, height: lineHeight).fill()
            context.saveGState()
            context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)	// 视图是上下翻转的，Core Text 的文字要再翻回来
            let line = CTLineCreateWithAttributedString(NSAttributedString(
                string: markedText.string,
                attributes: [.font: font, .foregroundColor: Self.nsColor(color(.text).text)]))
            context.textPosition = CGPoint(x: x, y: baseline)
            CTLineDraw(line, context)
            context.restoreGState()
            drawMarkedUnderlines(x: x, baseline: baseline)
        }
    }

    /// 行号（原版 CTextDrawer::DispLineNumber）。改过的行用「行番号（変更行）」的颜色、粗体
    private func drawLineNumber(_ current: Row, row r: Int, top: CGFloat, rowBack: UInt32) {
        var info = color(.lineNumber)
        let modified = color(.lineNumberModified)
        if modified.display && document.isLineModified(current.start.line) {
            info = modified
        }
        let fg = Self.nsColor(info.text)
        Self.nsColor(backColor(info, rowBack: rowBack)).setFill()
        NSRect(x: 0, y: top, width: gutterWidth, height: lineHeight).fill()
        let number: String
        if settings.lineNumberPerLogicalLine {
            number = current.start.column == 0 ? String(current.start.line + 1) : ""
        } else {
            number = String(r + 1)
        }
        let columns = lineNumberDigits + 2
        let x = CGFloat(columns - number.count - 1) * charWidth
        var attributes: [NSAttributedString.Key: Any] = [.font: info.bold ? boldFont : font, .foregroundColor: fg]
        if info.underline { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        (number as NSString).draw(at: NSPoint(x: x, y: top), withAttributes: attributes)
        // 行番号区切り（縦线，原版的默认值）：行号的文字色
        fg.setFill()
        NSRect(x: gutterWidth - 2, y: top, width: 1, height: lineHeight).fill()
    }

    /// 记号的颜色：选中时叠上选择范围的颜色
    private func markColor(_ index: EditorColorIndex, selected: Bool, rowBack: UInt32) -> NSColor {
        let info = color(index)
        if selected { return Self.nsColor(overlayTextColor(color(.select), on: info.text)) }
        return Self.nsColor(info.text)
    }

    /// 文字的记号（折り返し記号「<」、[EOF]）：记号的文字色和背景色
    private func drawMarkText(_ text: String, x: CGFloat, top: CGFloat, info: EditorColorSetting, rowBack: UInt32) {
        let back = backColor(info, rowBack: rowBack)
        let string = text as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: info.bold ? boldFont : font,
                                                         .foregroundColor: Self.nsColor(info.text)]
        if back != rowBack {
            Self.nsColor(back).setFill()
            NSRect(x: x, y: top, width: CGFloat(string.length) * charWidth, height: lineHeight).fill()
        }
        string.draw(at: NSPoint(x: x, y: top), withAttributes: attributes)
    }

    /// 文字：Core Text 选字形（没有的字由系统换成其他字体），位置用核心库的排版结果。
    /// 选中的字用选择范围的颜色
    private func drawGlyphs(_ current: Row, row r: Int, baseline: CGFloat, rowBack: UInt32,
                            indices: (range: Range<Int>, eol: Bool)?, context: CGContext) {
        guard current.text.length > 0 else { return }
        let text = color(.text)
        let select = color(.select)
        let normalColor = Self.nsColor(text.text).cgColor
        let selectedColor = Self.nsColor(overlayTextColor(select, on: text.text)).cgColor
        let attributed = NSAttributedString(string: current.text as String, attributes: [.font: text.bold ? boldFont : font])
        let line = CTLineCreateWithAttributedString(attributed)
        guard let runs = CTLineGetGlyphRuns(line) as? [CTRun] else { return }
        context.saveGState()
        // 视图是上下翻转的：以基线为原点再翻回来，字形才是正的
        context.translateBy(x: 0, y: baseline)
        context.scaleBy(x: 1, y: -1)
        context.textMatrix = .identity
        for run in runs {
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { continue }
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var indicesInRun = [CFIndex](repeating: 0, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
            CTRunGetStringIndices(run, CFRange(location: 0, length: 0), &indicesInRun)
            // 这一段的字体（这个字体里没有的字，Core Text 换成了其他字体）
            let attributes = CTRunGetAttributes(run) as NSDictionary
            let runFont: CTFont = attributes[kCTFontAttributeName as String].map { $0 as! CTFont } ?? (font as CTFont)
            var normal: ([CGGlyph], [CGPoint]) = ([], [])
            var selected: ([CGGlyph], [CGPoint]) = ([], [])
            for k in 0..<count {
                let index = indicesInRun[k]
                let c = current.text.character(at: index)
                // TAB、全角空白（显示记号时）不画字形
                if c == 0x09 || (c == 0x3000 && settings.showFullWidthSpace) { continue }
                let point = CGPoint(x: displayX(row: r, index: index), y: 0)
                if select.display && isSelected(row: r, index: index, indices: indices) {
                    selected.0.append(glyphs[k])
                    selected.1.append(point)
                } else {
                    normal.0.append(glyphs[k])
                    normal.1.append(point)
                }
            }
            for (group, cgColor) in [(normal, normalColor), (selected, selectedColor)] where !group.0.isEmpty {
                context.setFillColor(cgColor)
                CTFontDrawGlyphs(runFont, group.0, group.1, group.0.count, context)
            }
        }
        context.restoreGState()
    }

    /// TAB 記号（原版 CFigure_Tab）
    private func drawTab(x: CGFloat, width: CGFloat, top: CGFloat, color: NSColor) {
        switch settings.tabMark {
        case .string:
            // 文字指定：一个字占一桁，只画 TAB 宽度里放得下的部分
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath.clip(NSRect(x: x, y: top, width: width, height: lineHeight))
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            let string = settings.tabString as NSString
            for i in 0..<string.length {
                let cx = x + CGFloat(i) * charWidth
                if cx >= x + width { break }
                let c = string.substring(with: NSRange(location: i, length: 1))
                if c != " " { (c as NSString).draw(at: NSPoint(x: cx, y: top), withAttributes: attributes) }
            }
            NSGraphicsContext.restoreGraphicsState()
        case .shortArrow:
            drawTabArrow(x: x, width: charWidth, top: top, color: color)
        case .longArrow:
            drawTabArrow(x: x, width: width, top: top, color: color)
        @unknown default:
            break
        }
    }

    /// 原版 _DrawTabArrow：横线和箭头
    private func drawTabArrow(x: CGFloat, width: CGFloat, top: CGFloat, color: NSColor) {
        let sx = x + width - 2
        let sy = top + floor(charHeight / 2) + 0.5
        let sa = floor(charHeight / 4)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: x, y: sy))
        path.line(to: NSPoint(x: sx, y: sy))
        path.line(to: NSPoint(x: sx - sa, y: sy + sa))
        path.move(to: NSPoint(x: sx, y: sy))
        path.line(to: NSPoint(x: sx - sa, y: sy - sa))
        strokeMark(path, color: color)
    }

    /// 日本語空白（原版 CFigure_ZenSpace）：「□」
    private func drawFullWidthSpace(x: CGFloat, width: CGFloat, top: CGFloat, color: NSColor) {
        let rect = NSRect(x: x + 1.5, y: top + 1.5,
                          width: max(1, width - CGFloat(settings.columnSpacing) - 3), height: max(1, charHeight - 3))
        strokeMark(NSBezierPath(rect: rect), color: color)
    }

    /// 半角空白（原版 CFigure_HanSpace）：「o」的下半部分
    private func drawHalfWidthSpace(x: CGFloat, width: CGFloat, top: CGFloat, color: NSColor) {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath.clip(NSRect(x: x, y: top + floor(charHeight / 2), width: width, height: lineHeight))
        ("o" as NSString).draw(at: NSPoint(x: x, y: top), withAttributes: [.font: font, .foregroundColor: color])
        NSGraphicsContext.restoreGraphicsState()
    }

    /// 改行記号（原版 _DrawEOL）。换行符的种类不同，形状不同
    private func drawEol(_ eol: EditorEol, rect: NSRect, color: NSColor) {
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
        strokeMark(path, color: color)
    }

    private func strokeMark(_ path: NSBezierPath, color: NSColor) {
        path.lineWidth = 1
        color.setStroke()
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
            Self.nsColor(color(.text).text).setFill()
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
        reloadColors()
        // 滚动到头时露出的部分也是文字的背景色
        enclosingScrollView?.backgroundColor = Self.nsColor(textBack)
        restartCaretBlink()
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
        clearSelection()
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
        if !extendingSelection { clearSelection() }
        contentDidChange()
    }

    /// 选择范围扩展中（Shift+方向键等）：移动光标时不取消选择
    private var extendingSelection = false

    /// 移动光标并扩展选择范围（原版 Shift+移动：起点不动，光标移动）
    private func modifySelection(_ move: () -> Void) {
        let anchor = (isBoxSelection ? nil : selectionAnchor) ?? caret
        isBoxSelection = false
        extendingSelection = true
        move()
        extendingSelection = false
        selectionAnchor = anchor
        needsDisplay = true
    }

    // MARK: - 光标的闪烁

    /// 光标移动、输入后重新开始闪烁（先显示）
    private func restartCaretBlink() {
        caretBlinkOn = true
        caretBlinkTimer?.invalidate()
        caretBlinkTimer = nil
        guard window?.firstResponder === self else { return }
        let interval = max(0.2, UserDefaults.standard.double(forKey: "NSTextInsertionPointBlinkPeriodOn") / 1000)
        let timer = Timer(timeInterval: interval.isFinite && interval < 5 ? interval : 0.53, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.caretBlinkOn.toggle()
            self.setNeedsDisplay(self.caretRect.insetBy(dx: -1, dy: 0))
        }
        RunLoop.main.add(timer, forMode: .common)
        caretBlinkTimer = timer
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
            if isBoxSelection { clearSelection() }	// 矩形选择是排版上的位置，排版变了就取消
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
            if isBoxSelection { clearSelection() }
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
        DispatchQueue.main.async { [weak self] in self?.restartCaretBlink() }
        return true
    }

    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        caretBlinkTimer?.invalidate()
        caretBlinkTimer = nil
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
        let flags = event.modifierFlags
        if flags.contains(.option) {
            // 矩形选择（原版 Alt+拖动）
            clearSelection()
            moveCaret(to: point)
            isBoxSelection = true
            boxAnchor = boxPoint(at: point)
            boxEnd = boxAnchor
        } else if flags.contains(.shift) {
            // Shift+点击：从原来的起点（没有选择时是光标）选择到点击的位置
            modifySelection { moveCaret(to: point) }
        } else {
            moveCaret(to: point)
            selectionAnchor = caret		// 拖动时从这里开始选择
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        if inputContext?.handleEvent(event) == true { return }
        autoscroll(with: event)
        let point = convert(event.locationInWindow, from: nil)
        if isBoxSelection {
            extendingSelection = true
            moveCaret(to: point)
            extendingSelection = false
            boxEnd = boxPoint(at: point)
        } else {
            let anchor = selectionAnchor ?? caret
            extendingSelection = true
            moveCaret(to: point)
            extendingSelection = false
            selectionAnchor = anchor
        }
        needsDisplay = true
    }

    /// 视图坐标里的一点 → 光标。点在折り返した行的右边时，光标在这一行的末尾（不是下一行的开头）
    private func moveCaret(to point: NSPoint) {
        let r = rowIndex(atY: point.y)
        let i = index(row: r, x: point.x)
        setCaret(position(row: r, index: i), atLineEnd: isWrapped(r) && i == row(r).text.length)
    }

    /// 矩形选择的位置：行和按桁对齐的横向位置（原版的矩形选择也按桁）
    private func boxPoint(at point: NSPoint) -> BoxPoint {
        let column = max(0, ((point.x - textOriginX) / charWidth).rounded())
        return BoxPoint(row: rowIndex(atY: point.y), x: column * charWidth)
    }

    /// 编辑 > すべて選択（F_SELECTALL）
    override func selectAll(_ sender: Any?) {
        guard !hasMarkedText() else { return }
        setCaret(document.endPosition)
        selectionAnchor = EditorPosition(line: 0, column: 0)
        needsDisplay = true
    }

    /// Esc：取消选择（原版 F_CANCEL_MODE）
    override func cancelOperation(_ sender: Any?) {
        clearSelection()
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

    /// 输入的文字放到哪里：有选择时替换选择范围，否则插在光标处（矩形选择由 insertText 另外处理）
    private var insertionRange: EditorRange {
        if let selection { return selection }
        return EditorRange(from: caret, to: caret)
    }

    // MARK: - 基本编辑（第 29 步。原版 CViewCommander_Edit.cpp、CViewCommander_Clipboard.cpp）

    /// 剪贴板（测试时换成别的）
    var pasteboard: NSPasteboard = .general

    /// 矩形选择的复制（原版 Windows 剪贴板的 MSDEVColumnSelect 形式）。贴付时按矩形贴付
    static let columnSelectType = NSPasteboard.PasteboardType("jp.sakura-editor.MSDEVColumnSelect")
    /// 没有选择时复制的一行（原版的 MSDEVLineSelect 形式）。贴付时贴在行首（ラインモード貼り付け）
    static let lineSelectType = NSPasteboard.PasteboardType("jp.sakura-editor.MSDEVLineSelect")

    /// 矩形选择范围（核心库的形式）。宽度 0 的矩形（几行的同一位置）也算选择，输入时每行插入
    var boxRange: EditorBoxRange? {
        guard isBoxSelection, boxAnchor != boxEnd else { return nil }
        return EditorBoxRange(top: min(boxAnchor.row, boxEnd.row), bottom: max(boxAnchor.row, boxEnd.row),
                              left: Int(min(boxAnchor.x, boxEnd.x)), right: Int(max(boxAnchor.x, boxEnd.x)))
    }

    /// 设置普通的选择范围：from 是起点，光标在 to（原版 SetSelectArea。宏、测试用）
    func setSelection(from: EditorPosition, to: EditorPosition) {
        extendingSelection = true
        setCaret(to)
        extendingSelection = false
        isBoxSelection = false
        selectionAnchor = from
        needsDisplay = true
    }

    /// 设置矩形选择（编辑之后保留选择时）
    func setBoxSelection(_ box: EditorBoxRange) {
        selectionAnchor = nil
        isBoxSelection = true
        boxAnchor = BoxPoint(row: box.top, x: CGFloat(box.left))
        boxEnd = BoxPoint(row: box.bottom, x: CGFloat(box.right))
        needsDisplay = true
    }

    /// 排版位置 → 逻辑位置（光标用：不放在行末之后）
    private func logicPosition(row r: Int, x: Int) -> EditorPosition {
        if r >= document.layoutLineCount { return document.endPosition }
        let p = document.logicPosition(of: EditorLayoutPosition(line: r, x: x))
        return EditorPosition(line: p.line, column: min(p.column, lineText(p.line).length))
    }

    /// 光标的排版位置
    private var caretLayoutPosition: EditorLayoutPosition {
        let c = caretRowAndIndex
        return EditorLayoutPosition(line: c.row, x: Int(row(c.row).xs[min(c.index, row(c.row).xs.count - 1)]))
    }

    /// 几个编辑合成撤销的一步，之后光标放在 body 返回的位置
    private func edit(_ body: () -> EditorPosition) {
        document.beginEdit()
        let position = body()
        document.endEdit()
        caret = EditorPosition(line: position.line, column: min(position.column, lineText(position.line).length))
        textChanged()
    }

    private static func isLineDelimiter(_ c: unichar) -> Bool {
        c == 0x0D || c == 0x0A
    }

    /// 到第一个换行为止（原版 Command_INSTEXT 的矩形选择：改行までを抜き出す）
    private static func firstLine(_ text: String) -> String {
        let utf16 = Array(text.utf16)
        let end = utf16.firstIndex(where: isLineDelimiter) ?? utf16.count
        return String(utf16CodeUnits: utf16, count: end)
    }

    /// 写进剪贴板（原版 MySetClipboardData）
    private func setClipboard(_ text: String, column: Bool = false, line: Bool = false) {
        pasteboard.clearContents()
        var types: [NSPasteboard.PasteboardType] = [.string]
        if column { types.append(Self.columnSelectType) }
        if line { types.append(Self.lineSelectType) }
        pasteboard.declareTypes(types, owner: nil)
        pasteboard.setString(text, forType: .string)
        if column { pasteboard.setData(Data(), forType: Self.columnSelectType) }
        if line { pasteboard.setData(Data(), forType: Self.lineSelectType) }
    }

    /// 剪贴板里的文字
    private var clipboardText: String? {
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else { return nil }
        return text
    }

    /// 編集 > コピー（F_COPY）。没有选择时复制光标所在的一行（「選択なしでコピーを可能にする」）
    @objc func copy(_ sender: Any?) {
        guard !hasMarkedText() else { return }
        let settings = document.editSettings
        if let box = boxRange {
            setClipboard(document.boxText(box), column: true)
        } else if let selection {
            setClipboard(document.copyText(in: selection))
        } else {
            guard settings.copyWithoutSelection else { return }
            let text = document.copyText(ofLayoutLine: caretRowAndIndex.row)
            if !text.isEmpty { setClipboard(text, line: settings.lineModePaste) }
            return
        }
        if settings.clearSelectionAfterCopy { clearSelection() }	// コピーしたら選択解除
    }

    /// 編集 > 切り取り（F_CUT）。没有选择时切り取り光标所在的一行（原版 Command_CUT_LINE）
    @objc func cut(_ sender: Any?) {
        guard !hasMarkedText() else { return }
        let settings = document.editSettings
        if let box = boxRange {
            setClipboard(document.boxText(box), column: true)
            edit { document.deleteBox(box) }
        } else if let selection {
            setClipboard(document.copyText(in: selection))
            replace(selection, with: "")
        } else {
            guard settings.copyWithoutSelection else { return }
            let position = caretLayoutPosition
            let text = document.copyText(ofLayoutLine: position.line)
            guard !text.isEmpty else {
                NSSound.beep()
                return
            }
            setClipboard(text, line: settings.lineModePaste)
            edit { document.deleteLayoutLine(position.line, x: position.x) }
        }
    }

    /// 編集 > 貼り付け（F_PASTE）。矩形复制的文字按矩形贴付，一行复制的文字贴在行首
    @objc func paste(_ sender: Any?) {
        guard !hasMarkedText() else { return }
        guard var text = clipboardText else {
            NSSound.beep()
            return
        }
        let settings = document.editSettings
        let types = pasteboard.types ?? []
        // 矩形コピーのテキストは常に矩形貼り付け
        if settings.autoColumnPaste && types.contains(Self.columnSelectType) {
            pasteBoxText(text)
            return
        }
        // 行コピーのテキストで末尾が改行になっていなければ改行を追加する
        let linePaste = settings.lineModePaste && types.contains(Self.lineSelectType)
        if linePaste, let last = text.utf16.last, !Self.isLineDelimiter(last) {
            text += EditorCore.text(ofEol: document.newLineEol)
        }
        if settings.convertEolOnPaste {
            text = document.convertEolToNewLine(text)
        }
        insertClipboardText(text, linePaste: linePaste)
    }

    /// 編集 > 矩形貼り付け（F_PASTEBOX）：剪贴板的文字每行贴在同一横向位置
    @objc func pasteAsBox(_ sender: Any?) {
        guard !hasMarkedText() else { return }
        guard let text = clipboardText else {
            NSSound.beep()
            return
        }
        pasteBoxText(text)
    }

    /// 原版 Command_PASTEBOX：先删除选择范围，从光标的位置矩形贴付，光标留在开始的位置
    private func pasteBoxText(_ text: String) {
        var at = caretLayoutPosition
        let box = boxRange
        let selected = selection
        edit {
            if let box {
                let c = document.deleteBox(box)
                at = document.layoutPosition(of: c)
                // 矩形的左端在行末之后时，光标留在那个横向位置（原版 DeleteData）
                if c.column == lineText(c.line).length && box.left > at.x {
                    at = EditorLayoutPosition(line: at.line, x: box.left)
                }
            } else if let selected {
                document.delete(selected)
                at = document.layoutPosition(of: selected.from)
            }
            document.pasteBox(text, at: at)
            return logicPosition(row: at.line, x: at.x)
        }
    }

    /// 原版 Command_INSTEXT：矩形选择时每行插入第一行，普通选择时替换。
    /// ラインモード貼り付け时贴在光标所在排版行的行首，光标回到原来的位置
    private func insertClipboardText(_ text: String, linePaste: Bool) {
        if let box = boxRange {
            indentBox(box, text: Self.firstLine(text), kind: .none)
            return
        }
        let selected = selection
        let start = caret
        edit {
            var at = start
            if let selected {
                if !linePaste {
                    var end = EditorPosition()
                    document.replace(selected, with: text, newEnd: &end)
                    return end
                }
                // 行コピーの貼り付けでは選択範囲は削除（後で行頭に貼り付ける）
                document.delete(selected)
                at = selected.from
            }
            var end = EditorPosition()
            if linePaste {
                // 挿入ポイント（折り返し単位行頭）に貼り付けて、元の位置へカーソルを戻す
                let lineTop = position(row: rowAndIndex(of: at).row, index: 0)
                let delta = at.column - lineTop.column
                document.replace(EditorRange(from: lineTop, to: lineTop), with: text, newEnd: &end)
                return EditorPosition(line: end.line, column: end.column + delta)
            }
            document.replace(EditorRange(from: at, to: at), with: text, newEnd: &end)
            return end
        }
    }

    /// 矩形选择中的输入、TAB（原版 Command_INDENT）：每行插入，之后矩形往右移
    private func indentBox(_ box: EditorBoxRange, text: String, kind: EditorIndentKind) {
        var newCaret = caret
        var newBox = box
        edit {
            newBox = document.indentBox(box, text: text, kind: kind, caret: &newCaret)
            return newCaret
        }
        setBoxSelection(newBox)
    }

    /// 普通选择的多行范围：排版行 top～bottom（不包括 bottom）。终点在行首时不包括那一行（原版相同）
    private func selectedRows(_ selection: EditorRange) -> (top: Int, bottom: Int) {
        let from = document.layoutPosition(of: selection.from)
        let to = document.layoutPosition(of: selection.to)
        return (from.line, to.x > 0 ? to.line + 1 : to.line)
    }

    /// 缩进之后选择整行（原版：行頭から行頭まで、カーソルは終点）
    private func selectRows(top: Int, bottom: Int) {
        let anchor = logicPosition(row: top, x: 0)
        caret = logicPosition(row: bottom, x: 0)
        textChanged()
        selectionAnchor = anchor
        needsDisplay = true
    }

    /// Enter（原版 Command_WCHAR の改行）：选择范围删除后，插入输入用的换行符和オートインデント
    override func insertNewline(_ sender: Any?) {
        let box = boxRange
        let selected = selection
        let start = caret
        edit {
            var at = start
            if let box {
                at = document.deleteBox(box)
            } else if let selected {
                document.delete(selected)
                at = selected.from
            }
            let text = EditorCore.text(ofEol: document.newLineEol) + document.autoIndentText(at: at)
            var end = EditorPosition()
            document.replace(EditorRange(from: at, to: at), with: text, newEnd: &end)
            return end
        }
    }

    /// TAB（原版 F_INDENT_TAB）：多行选择时每行行首插入 TAB，矩形选择时每行插入，
    /// 否则与输入 TAB 相同（「スペースの挿入」时插入到下一个 TAB 位置的空白）
    override func insertTab(_ sender: Any?) {
        guard !hasMarkedText() else { return }
        if let box = boxRange {
            if box.left == box.right {
                // 宽度 0 时右端扩展到最大，不插入（原版 Command_INDENT ver1）
                setBoxSelection(document.indentBox(box, text: "\t", kind: .tab, caret: nil))
                return
            }
            indentBox(box, text: "\t", kind: .tab)
            return
        }
        if let selected = selection {
            let rows = selectedRows(selected)
            // 通常選択(複数行)：排版上不在同一行时
            if document.layoutPosition(of: selected.from).line != document.layoutPosition(of: selected.to).line {
                let bottom = document.indentLines(from: rows.top, to: rows.bottom, text: document.tabText(at: 0))
                selectRows(top: rows.top, bottom: bottom)
                return
            }
        }
        let selected = selection
        let start = caret
        edit {
            var at = start
            if let selected {
                document.delete(selected)
                at = selected.from
            }
            var end = EditorPosition()
            let x = document.layoutPosition(of: at).x
            document.replace(EditorRange(from: at, to: at), with: document.tabText(at: x), newEnd: &end)
            return end
        }
    }

    /// Shift+TAB（原版 F_UNINDENT_TAB）：选择范围的每行删除行首的一个 TAB（或 TAB 幅以内的空白）。
    /// 没有选择时与原版相同，当作 TAB 输入；矩形选择时不能执行
    override func insertBacktab(_ sender: Any?) {
        guard !hasMarkedText() else { return }
        if boxRange != nil {
            NSSound.beep()
            return
        }
        guard let selected = selection else {
            insertTab(sender)
            return
        }
        let rows = selectedRows(selected)
        let bottom = document.unindentLines(from: rows.top, to: rows.bottom, character: 0x09)
        selectRows(top: rows.top, bottom: bottom)
    }

    /// BackSpace（F_DELETE_BACK）：有选择时删除选择范围，否则删除光标前的一个字
    override func deleteBackward(_ sender: Any?) {
        if let box = boxRange {
            edit { document.deleteBox(box) }
            return
        }
        if let selection {
            replace(selection, with: "")
            return
        }
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

    /// Delete（F_DELETE）：有选择时删除选择范围，否则删除光标处的一个字（行末时与下一行连接）
    override func deleteForward(_ sender: Any?) {
        if let box = boxRange {
            edit { document.deleteBox(box) }
            return
        }
        if let selection {
            replace(selection, with: "")
            return
        }
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

    /// 編集 > 削除（F_DELETE）
    @objc func delete(_ sender: Any?) {
        guard !hasMarkedText() else { return }
        deleteForward(sender)
    }

    /// 編集 > カーソル前を削除（F_DELETE_BACK）
    @objc func deleteBack(_ sender: Any?) {
        guard !hasMarkedText() else { return }
        deleteBackward(sender)
    }

    /// 編集 > 高度な操作 > TABインデント（F_INDENT_TAB）
    @objc func indentTab(_ sender: Any?) { insertTab(sender) }

    /// 編集 > 高度な操作 > 逆TABインデント（F_UNINDENT_TAB）
    @objc func unindentTab(_ sender: Any?) { insertBacktab(sender) }

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

    // Shift+移动：扩展选择范围（原版 F_LEFT_SEL 等）
    override func moveLeftAndModifySelection(_ sender: Any?) { modifySelection { moveLeft(sender) } }
    override func moveRightAndModifySelection(_ sender: Any?) { modifySelection { moveRight(sender) } }
    override func moveUpAndModifySelection(_ sender: Any?) { modifySelection { moveUp(sender) } }
    override func moveDownAndModifySelection(_ sender: Any?) { modifySelection { moveDown(sender) } }
    override func moveToBeginningOfLineAndModifySelection(_ sender: Any?) { modifySelection { moveToBeginningOfLine(sender) } }
    override func moveToEndOfLineAndModifySelection(_ sender: Any?) { modifySelection { moveToEndOfLine(sender) } }
    override func moveToLeftEndOfLineAndModifySelection(_ sender: Any?) { modifySelection { moveToBeginningOfLine(sender) } }
    override func moveToRightEndOfLineAndModifySelection(_ sender: Any?) { modifySelection { moveToEndOfLine(sender) } }
    override func moveToBeginningOfDocumentAndModifySelection(_ sender: Any?) { modifySelection { moveToBeginningOfDocument(sender) } }
    override func moveToEndOfDocumentAndModifySelection(_ sender: Any?) { modifySelection { moveToEndOfDocument(sender) } }

    // MARK: - 字体（第 28 步：設定 > フォント設定。原版 F_FONT）

    /// 打开字体面板
    @objc func showFontPanel(_ sender: Any?) {
        let manager = NSFontManager.shared
        manager.target = self
        manager.setSelectedFont(font, isMultiple: false)
        manager.orderFrontFontPanel(sender)
    }

    func changeFont(_ sender: NSFontManager?) {
        guard let sender else { return }
        Self.setFont(sender.convert(font))
    }

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
        case #selector(selectAll(_:)): return !hasMarkedText()
        // 第 29 步（原版 IsFuncEnable：选择范围、「選択なしでコピーを可能にする」、剪贴板）
        case #selector(cut(_:)), #selector(copy(_:)):
            return !hasMarkedText() && (hasSelection || document.editSettings.copyWithoutSelection)
        case #selector(paste(_:)), #selector(pasteAsBox(_:)):
            return !hasMarkedText() && clipboardText != nil
        case #selector(delete(_:)), #selector(deleteBack(_:)), #selector(indentTab(_:)), #selector(unindentTab(_:)):
            return !hasMarkedText()
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
        // 矩形选择中的输入：每行的选择范围之前插入（原版 Command_WCHAR → Command_INDENT、Command_INSTEXT）
        if let box = boxRange, replacementRange.location == NSNotFound {
            clearMarkedText()
            indentBox(box, text: Self.firstLine(text), kind: .none)
            return
        }
        var range = hasMarkedText() ? EditorRange(from: caret, to: caret) : insertionRange
        if replacementRange.location != NSNotFound {
            let from = position(ofOffset: documentOffset(fromVirtual: replacementRange.location))
            let to = position(ofOffset: documentOffset(fromVirtual: NSMaxRange(replacementRange)))
            range = EditorRange(from: from, to: to)
        }
        clearMarkedText()
        replace(range, with: text)
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        // 开始输入时有选择范围：先删掉（与直接输入文字时相同）
        if !hasMarkedText() && replacementRange.location == NSNotFound {
            // 矩形选择时保留选择，确定后每行插入（insertText）
            if let selection {
                replace(selection, with: "")
            }
        }
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
        if let selection {
            let from = offset(of: selection.from)
            return NSRange(location: from, length: offset(of: selection.to) - from)
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

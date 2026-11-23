// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge

/// タイプ別設定 > カラー（计划第 40 步第 2 个 PR。原版 CPropTypesColor、CDlgSameColor、CDlgKeywordSelect）。
///
/// - 色指定的列表（原版是自己画的 ListBox）：左边的 ✓ 是「色分け/表示」，名字用太字・下線显示，右边是文字色・背景色的样本。
///   点 ✓ 切换表示、双击名字切换太字、右键名字切换下線、点样本选颜色（与原版的鼠标操作相同）。
/// - 值是 sakura.ini 的「C[TXT]=表示,太字,文字色,背景色,下線」（颜色是 6 位 16 进制的 BGR，与 Windows 的 COLORREF 相同）。

// MARK: - 一种颜色的值

/// sakura.ini の色設定 1 行（原版 ColorInfo の入出力：「%u,%u,%06x,%06x,%u」）
struct ColorSettingValue: Equatable {
    var display = false
    var bold = false
    /// 0x00BBGGRR（Windows の COLORREF）
    var text: UInt32 = 0
    var back: UInt32 = 0xFFFFFF
    var underline = false

    init(display: Bool = false, bold: Bool = false, text: UInt32 = 0, back: UInt32 = 0xFFFFFF, underline: Bool = false) {
        self.display = display
        self.bold = bold
        self.text = text
        self.back = back
        self.underline = underline
    }

    /// 読めない値は nil（原版も読み込まない）
    init?(ini: String) {
        let parts = ini.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 5, let d = UInt32(parts[0]), let b = UInt32(parts[1]),
              let t = UInt32(parts[2], radix: 16), let k = UInt32(parts[3], radix: 16), let u = UInt32(parts[4]) else { return nil }
        self.init(display: d != 0, bold: b != 0, text: t, back: k, underline: u != 0)
    }

    var ini: String {
        String(format: "%u,%u,%06x,%06x,%u", display ? 1 : 0, bold ? 1 : 0, text, back, underline ? 1 : 0)
    }

    static func color(_ bgr: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat(bgr & 0xFF) / 255, green: CGFloat((bgr >> 8) & 0xFF) / 255,
                blue: CGFloat((bgr >> 16) & 0xFF) / 255, alpha: 1)
    }

    static func bgr(_ color: NSColor) -> UInt32 {
        let c = color.usingColorSpace(.sRGB) ?? color
        let r = UInt32((c.redComponent * 255).rounded()), g = UInt32((c.greenComponent * 255).rounded())
        let b = UInt32((c.blueComponent * 255).rounded())
        return min(r, 255) | min(g, 255) << 8 | min(b, 255) << 16
    }
}

/// 色の見本（小さい角丸の四角）
final class ColorSwatchView: NSView {
    var color: NSColor { didSet { needsDisplay = true } }

    init(color: NSColor, frame: NSRect = NSRect(x: 0, y: 0, width: 14, height: 14)) {
        self.color = color
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 2, dy: 2)
        let path = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
        color.setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.stroke()
    }

    static func image(_ color: NSColor, size: NSSize = NSSize(width: 26, height: 12)) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
            color.setFill()
            path.fill()
            NSColor.separatorColor.setStroke()
            path.stroke()
            return true
        }
    }
}

// MARK: - 文字列エスケープ、縦線

/// 文字列エスケープ（原版 StringLitteralArr。値は EStringLiteralType）
let stringLiterals: NamedValues = [
    (0, NSLocalizedString("C/C++言語風 \\\"", comment: "STR_STRINGESC_CPP")),
    (1, NSLocalizedString("PL/SQL風    \"\"", comment: "STR_STRINGESC_PLSQL")),
    (2, NSLocalizedString("HTML/XML風  =\"\"", comment: "STR_STRINGESC_HTML")),
    (3, NSLocalizedString("C#風        @\"\"", comment: "STR_STRINGESC_CSHARP")),
    (4, NSLocalizedString("Python風    \"\"\"", comment: "STR_STRINGESC_PYTHON")),
]

/// 縦線桁指定（原版 CPropTypesColor の SetData / GetData）。値は m_nVertLineIdx：
/// 「桁」は正の数、「Step(Begin, End)」は -Begin、End、Step の 3 つ
enum VerticalLines {
    static let max = 200	// MAX_VERTLINES
    static let maxLineKetas = 10240

    /// 値 → 表示（「10,20(30,100)」の形）
    static func text(_ values: [Int]) -> String {
        var parts: [String] = []
        var i = 0
        while i < max && i < values.count && values[i] != 0 {
            let col = values[i]
            if col < 0 {
                if i < max - 2 && i + 2 < values.count {
                    let begin = -col, end = values[i + 1], step = values[i + 2]
                    i += 3
                    if end < begin || step <= 0 { continue }
                    parts.append("\(step)(\(begin),\(end))")
                    continue
                }
                i += 1
                continue
            }
            parts.append(String(col))
            i += 1
        }
        return parts.joined(separator: ",")
    }

    /// 表示 → 値（原版 GetData と同じ：読めないところで終わり。最後に 0 を置く）
    static func values(_ text: String) -> [Int] {
        let chars = Array(text.utf16)
        var offset = 0
        func at(_ i: Int) -> UInt16 { i < chars.count ? chars[i] : 0 }
        func number() -> Int {
            var value = 0
            while (0x30...0x39).contains(at(offset)) {
                value = value * 10 + Int(at(offset) - 0x30)
                offset += 1
            }
            return value
        }
        var result: [Int] = []
        while result.count < max {
            let value = number()
            if value <= 0 { break }
            if at(offset) == 0x28 {	// (
                offset += 1
                let begin = number()
                if begin <= 0 { break }
                if at(offset) == 0x2C {	// ,
                    offset += 1
                } else if at(offset) != 0x29 {
                    break
                }
                var end = number()
                if end <= 0 { end = maxLineKetas }
                if at(offset) != 0x29 { break }
                offset += 1
                guard result.count + 2 < max else { break }
                result += [-begin, end, value]
            } else {
                result.append(value)
            }
            if at(offset) != 0x2C { break }
            offset += 1
        }
        if result.count < max { result.append(0) }
        return result
    }
}

// MARK: - カラー のページ

final class TypeColorPage: CommonSettingsPageLogic {
    let typeIndex: Int
    /// 色の行（原版の色指定リスト）
    let items: [EditorColorItem]
    /// 各行の色（ページの中の値。GetData で sakura.ini の値に戻す）
    private(set) var colors: [ColorSettingValue] = []
    /// 強調キーワード 1～10 のセット（原版 m_nSet。-1 は指定なし）
    private(set) var keywordSets: [Int] = Array(repeating: -1, count: 10)
    /// 選んでいる行（原版 m_nCurrentColorType）
    private(set) var current = 0
    private weak var page: PropPage?

    private static let lineComments = [
        (edit: idc("EDIT_LINECOMMENT"), check: idc("CHECK_LCPOS"), pos: idc("EDIT_LINECOMMENTPOS"), label: idc("LABEL_LCPOS"), suffix: ""),
        (edit: idc("EDIT_LINECOMMENT2"), check: idc("CHECK_LCPOS2"), pos: idc("EDIT_LINECOMMENTPOS2"), label: idc("LABEL_LCPOS2"), suffix: "2"),
        (edit: idc("EDIT_LINECOMMENT3"), check: idc("CHECK_LCPOS3"), pos: idc("EDIT_LINECOMMENTPOS3"), label: idc("LABEL_LCPOS3"), suffix: "3"),
    ]
    private static let blockComments = [
        (from: idc("EDIT_BLOCKCOMMENT_FROM"), to: idc("EDIT_BLOCKCOMMENT_TO"), suffix: ""),
        (from: idc("EDIT_BLOCKCOMMENT_FROM2"), to: idc("EDIT_BLOCKCOMMENT_TO2"), suffix: "2"),
    ]

    init(typeIndex: Int) {
        self.typeIndex = typeIndex
        items = EditorCore.colorItems
    }

    var ranges: [String: ClosedRange<Int>] {
        Dictionary(uniqueKeysWithValues: Self.lineComments.map { ($0.pos, 1...1000) })
    }

    /// 「共通設定」（強調キーワードの編集）は第 3 个 PR
    var notYet: Set<String> { [idc("BUTTON_EDITKEYWORD")] }

    // MARK: SetData / GetData

    func setData(_ page: PropPage, _ values: CommonSettingsValues) {
        self.page = page
        for block in Self.blockComments {
            page.setText(block.from, values.string("szBlockCommentFrom" + block.suffix))
            page.setText(block.to, values.string("szBlockCommentTo" + block.suffix))
        }
        // 行コメント：桁指定のときは 0 以上、指定しないときは ~桁（表示は桁 + 1）
        for line in Self.lineComments {
            page.setText(line.edit, values.string("szLineComment" + line.suffix))
            let pos = values.int("nLineCommentColumn" + line.suffix)
            page.setChecked(line.check, pos >= 0)
            page.setInt(line.pos, (pos >= 0 ? pos : ~pos) + 1)
        }
        page.loadCombo(idc("COMBO_STRINGLITERAL"), stringLiterals, value: TypeInts.stringType.get(values))
        page.setChecked(idc("CHECK_STRINGLINEONLY"), values.bool("bStringLineOnly"))
        page.setChecked(idc("CHECK_STRINGENDLINE"), values.bool("bStringEndLine"))

        keywordSets = (0..<10).map { Self.keywordSet($0, values) }
        loadKeywordCombo(page)

        loadColors(values)
        if let list = page.list(idc("LIST_COLORS")) {
            list.cellView = { [weak self] row, column in self?.cell(row: row, column: column) }
            list.onSelect = { [weak self, weak page] in
                guard let self, let page, let row = page.list(idc("LIST_COLORS"))?.selectedRow, row >= 0 else { return }
                self.selectColor(row, page)
            }
            list.onClick = { [weak self, weak page] row, column in
                guard let self, let page else { return }
                self.clickedColor(row: row, column: column, page)
            }
            list.onDoubleClick = { [weak self, weak page] row, column in
                guard let self, let page, column == 1 else { return }
                self.toggle(row, \.bold, unless: self.items[row].noBold, page)
            }
            list.onRightClick = { [weak self, weak page] row, column in
                guard let self, let page, column == 1 else { return }
                self.selectColor(row, page)
                self.toggle(row, \.underline, unless: self.items[row].noUnderline, page)
            }
            setUpColorList(list)
        }
        selectColor(0, page)

        page.setText(idc("EDIT_VERTLINE"), VerticalLines.text(Self.verticalLines(values)))
    }

    func getData(_ page: PropPage, _ values: CommonSettingsValues) {
        for line in Self.lineComments {
            var enabled = page.isChecked(line.check)
            var pos = page.int(line.pos)
            if pos == 0 { enabled = false } else { pos -= 1 }
            values.set(page.text(line.edit), "szLineComment" + line.suffix)
            values.set(enabled ? pos : ~pos, "nLineCommentColumn" + line.suffix)
        }
        for block in Self.blockComments {
            values.set(page.text(block.from), "szBlockCommentFrom" + block.suffix)
            values.set(page.text(block.to), "szBlockCommentTo" + block.suffix)
        }
        TypeInts.stringType.set(page.comboValue(idc("COMBO_STRINGLITERAL"), stringLiterals), values)
        values.set(page.isChecked(idc("CHECK_STRINGLINEONLY")), "bStringLineOnly")
        values.set(page.isChecked(idc("CHECK_STRINGENDLINE")), "bStringEndLine")

        // 強調キーワード 1 はコンボボックス、2～10 は「2～10...」で選んだもの
        let combo = page.selectedIndex(idc("COMBO_SET"))
        keywordSets[0] = combo <= 0 ? -1 : combo - 1
        TypeInts.keywordSet1.set(keywordSets[0], values)
        TypeInts.keywordSet2.set(keywordSets[1], values)
        for i in 2..<10 { values.set(keywordSets[i], "nKeywordSelect\(i + 1)") }

        storeColors(values)

        // 縦線：値と最後の 0（最大 200 個のときは 0 なし）
        for (i, value) in VerticalLines.values(page.text(idc("EDIT_VERTLINE"))).enumerated() {
            values.set(value, "nVertLineIdx\(i + 1)")
        }
    }

    static func keywordSet(_ index: Int, _ values: CommonSettingsValues) -> Int {
        switch index {
        case 0: return TypeInts.keywordSet1.get(values)
        case 1: return TypeInts.keywordSet2.get(values)
        default: return Int(values.string("nKeywordSelect\(index + 1)")) ?? -1
        }
    }

    static func verticalLines(_ values: CommonSettingsValues) -> [Int] {
        var result: [Int] = []
        for i in 1...VerticalLines.max {
            let value = values.int("nVertLineIdx\(i)")
            result.append(value)
            if value == 0 { break }
        }
        return result
    }

    private func loadColors(_ values: CommonSettingsValues) {
        colors = items.map { ColorSettingValue(ini: values.string($0.key)) ?? ColorSettingValue() }
    }

    private func storeColors(_ values: CommonSettingsValues) {
        for (item, color) in zip(items, colors) where ColorSettingValue(ini: values.string(item.key)) != color {
            values.set(color.ini, item.key)
        }
    }

    // MARK: 強調キーワード

    /// セット名のコンボボックス（原版 SetDataKeyword：先頭は空白）
    private func loadKeywordCombo(_ page: PropPage) {
        let names = EditorCore.keywordSetNames
        page.setTaggedItems(idc("COMBO_SET"), [(-1, " ")] + names.enumerated().map { ($0.offset, $0.element) },
                            selectedValue: keywordSets[0])
    }

    /// キーワードセットの再配列（原版 RearrangeKeywordSet）：途中の「指定なし」を詰め、色の設定も一緒に動かす
    func rearrangeKeywordSets() {
        let keyword1 = items.firstIndex { $0.key == "C[KW1]" } ?? 0
        for i in 0..<keywordSets.count where keywordSets[i] == -1 {
            guard let j = (i..<keywordSets.count).first(where: { keywordSets[$0] != -1 }) else { break }
            keywordSets[i] = keywordSets[j]
            keywordSets[j] = -1
            colors.swapAt(keyword1 + i, keyword1 + j)
        }
    }

    // MARK: 色指定リスト

    private func setUpColorList(_ list: PropList) {
        let width = list.table.enclosingScrollView?.contentSize.width ?? 220
        list.setColumns(["", "", "", ""], widths: [18, width - 18 - 22 - 22 - 12, 22, 22])
        list.table.rowHeight = 18
        list.setRows(items.map { [$0.name] })
    }

    /// 0: ✓、1: 名前、2: 文字色、3: 背景色
    private func cell(row: Int, column: Int) -> NSView? {
        guard items.indices.contains(row), colors.indices.contains(row) else { return nil }
        let item = items[row], color = colors[row]
        switch column {
        case 0:
            let label = NSTextField(labelWithString: color.display ? "✓" : "")
            label.alignment = .center
            return label
        case 1:
            let label = NSTextField(labelWithString: item.name)
            var font = PropPage.font
            if color.bold { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
            label.font = font
            if color.underline {
                label.attributedStringValue = NSAttributedString(string: item.name, attributes: [
                    .font: font, .underlineStyle: NSUnderlineStyle.single.rawValue])
            }
            return label
        case 2:
            return item.noText ? NSView() : ColorSwatchView(color: ColorSettingValue.color(color.text))
        default:
            return item.noBack ? NSView() : ColorSwatchView(color: ColorSettingValue.color(color.back))
        }
    }

    /// 行を選んだ（原版 LBN_SELCHANGE）
    func selectColor(_ row: Int, _ page: PropPage) {
        guard items.indices.contains(row) else { return }
        current = row
        if let list = page.list(idc("LIST_COLORS")), list.selectedRow != row { list.select(row) }
        updateColorControls(page)
        enable(page)
    }

    private func updateColorControls(_ page: PropPage) {
        let color = colors[current]
        page.setChecked(idc("CHECK_DISP"), color.display)
        page.setChecked(idc("CHECK_BOLD"), color.bold)
        page.setChecked(idc("CHECK_UNDERLINE"), color.underline)
        for (id, bgr) in [(idc("BUTTON_TEXTCOLOR"), color.text), (idc("BUTTON_BACKCOLOR"), color.back)] {
            guard let button = page.control(id) as? NSButton else { continue }
            button.title = ""
            button.image = ColorSwatchView.image(ColorSettingValue.color(bgr))
            button.imagePosition = .imageOnly
        }
    }

    private func clickedColor(row: Int, column: Int, _ page: PropPage) {
        guard items.indices.contains(row) else { return }
        switch column {
        case 0: toggle(row, \.display, unless: items[row].forceDisplay, page)
        case 2: if !items[row].noText { chooseColor(row, \.text, page) }
        case 3: if !items[row].noBack { chooseColor(row, \.back, page) }
        default: break
        }
    }

    private func toggle(_ row: Int, _ key: WritableKeyPath<ColorSettingValue, Bool>, unless disabled: Bool, _ page: PropPage) {
        guard !disabled else { return }
        colors[row][keyPath: key].toggle()
        page.list(idc("LIST_COLORS"))?.reloadRow(row)
        if row == current { updateColorControls(page) }
    }

    private func chooseColor(_ row: Int, _ key: WritableKeyPath<ColorSettingValue, UInt32>, _ page: PropPage) {
        guard let chosen = TypeSettingsPages.chooseColor(ColorSettingValue.color(colors[row][keyPath: key]), page.view.window) else { return }
        colors[row][keyPath: key] = ColorSettingValue.bgr(chosen)
        page.list(idc("LIST_COLORS"))?.reloadRow(row)
        if row == current { updateColorControls(page) }
    }

    // MARK: 連動

    func enable(_ page: PropPage) {
        let item = items[current]
        page.setEnabled(idc("CHECK_DISP"), !item.forceDisplay)
        page.setEnabled(idc("CHECK_BOLD"), !item.noBold)
        page.setEnabled(idc("CHECK_UNDERLINE"), !item.noUnderline)
        for id in ["STATIC_MOZI", "BUTTON_TEXTCOLOR", "BUTTON_SAMETEXTCOLOR"] { page.setEnabled(idc(id), !item.noText) }
        for id in ["STATIC_HAIKEI", "BUTTON_BACKCOLOR", "BUTTON_SAMEBKCOLOR"] { page.setEnabled(idc(id), !item.noBack) }
        for line in Self.lineComments {
            page.setEnabled(line.pos, page.isChecked(line.check))
            page.setEnabled(line.label, page.isChecked(line.check))
        }
        page.setEnabled(idc("CHECK_STRINGENDLINE"), page.isChecked(idc("CHECK_STRINGLINEONLY")))
    }

    func changed(_ id: String, _ page: PropPage, _ values: CommonSettingsValues) {
        switch id {
        case idc("CHECK_DISP"): colors[current].display = page.isChecked(id)
        case idc("CHECK_BOLD"): colors[current].bold = page.isChecked(id)
        case idc("CHECK_UNDERLINE"): colors[current].underline = page.isChecked(id)
        default: return
        }
        page.list(idc("LIST_COLORS"))?.reloadRow(current)
    }

    func buttonPressed(_ id: String, _ page: PropPage, _ values: CommonSettingsValues, window: NSWindow?) {
        switch id {
        case idc("BUTTON_TEXTCOLOR"):
            chooseColor(current, \.text, page)
        case idc("BUTTON_BACKCOLOR"):
            chooseColor(current, \.back, page)
        case idc("BUTTON_SAMETEXTCOLOR"), idc("BUTTON_SAMEBKCOLOR"):
            let text = id == idc("BUTTON_SAMETEXTCOLOR")
            guard let dialog = SameColorDialog(items: items, colors: colors, text: text,
                                               color: text ? colors[current].text : colors[current].back) else { return }
            if TypeSettingsPages.runSameColorDialog(dialog, window) { colors = dialog.result }
            page.list(idc("LIST_COLORS"))?.table.reloadData()
            updateColorControls(page)
        case idc("BUTTON_KEYWORD_SELECT"):
            let combo = page.selectedIndex(idc("COMBO_SET"))
            keywordSets[0] = combo <= 0 ? -1 : combo - 1
            guard let dialog = KeywordSelectDialog(sets: keywordSets) else { return }
            if TypeSettingsPages.runKeywordSelectDialog(dialog, window) { keywordSets = dialog.sets }
            rearrangeKeywordSets()
            loadKeywordCombo(page)
            page.list(idc("LIST_COLORS"))?.table.reloadData()
            updateColorControls(page)
        case idc("BUTTON_IMPORT"):
            getData(page, values)
            guard TypeSettingsPages.importFile(.colors, typeIndex: typeIndex, values: values, extensions: ["col"], window: window) else { return }
            loadColors(values)
            page.list(idc("LIST_COLORS"))?.table.reloadData()
            updateColorControls(page)
        case idc("BUTTON_EXPORT"):
            getData(page, values)
            TypeSettingsPages.exportFile(.colors, typeIndex: typeIndex, values: values, extensions: ["col"], window: window)
        default:
            break
        }
    }
}

// MARK: - 文字色統一・背景色統一（原版 CDlgSameColor）

/// 選んだ色に、チェックした色を使っている項目をそろえる。テンプレートは IDD_SAMECOLOR
final class SameColorDialog: NSObject {
    let page: PropPage
    let title: String
    /// 文字色か背景色か
    let text: Bool
    /// そろえる色
    let color: UInt32
    private let items: [EditorColorItem]
    private let colors: [ColorSettingValue]
    /// 選べる色（そろえる色以外で、使われている色。重ならないように）と、チェック
    private(set) var candidates: [UInt32] = []
    private(set) var checked: [Bool] = []
    /// OK のあとの色
    private(set) var result: [ColorSettingValue]
    var onClose: ((Bool) -> Void)?

    init?(items: [EditorColorItem], colors: [ColorSettingValue], text: Bool, color: UInt32) {
        guard let definition = PropDialogs.load("TypeSettingsDialogs")?.dialog("IDD_SAMECOLOR") else { return nil }
        page = PropPage(definition: definition)
        title = text ? NSLocalizedString("文字色統一", comment: "STR_DLGSMCLR_BTN1") : NSLocalizedString("背景色統一", comment: "STR_DLGSMCLR_BTN2")
        self.text = text
        self.color = color
        self.items = items
        self.colors = colors
        result = colors
        super.init()
        for (item, value) in zip(items, colors) where !(text ? item.noText : item.noBack) {
            let c = text ? value.text : value.back
            if c != color && !candidates.contains(c) { candidates.append(c) }
        }
        checked = Array(repeating: false, count: candidates.count)
        page.setText(idc("STATIC_COLOR"), "")
        if let label = page.control(idc("STATIC_COLOR")) {
            let swatch = ColorSwatchView(color: ColorSettingValue.color(color), frame: label.frame)
            label.superview?.addSubview(swatch)
        }
        page.setUnavailable([idc("BUTTON_HELP")], reason: NSLocalizedString("この項目は今後のバージョンで対応します。", comment: "共通設定：以后的版本移植的项目"))
        if let list = page.list(idc("LIST_COLORS")) {
            list.setColumns(["", ""], widths: [20, 120])
            list.cellView = { [weak self] row, column in self?.cell(row: row, column: column) }
            list.onClick = { [weak self] row, column in if column == 0 { self?.toggle(row) } }
            list.onSelect = { [weak self] in self?.showItems() }
            list.setRows(candidates.map { [String(format: "%06x", $0)] })
            if !candidates.isEmpty { list.select(0) }
        }
        page.list(idc("LIST_ITEMINFO"))?.setColumns([""], widths: [160])
        showItems()
        page.onButton = { [weak self] id in self?.button(id) }
    }

    private func cell(row: Int, column: Int) -> NSView? {
        guard candidates.indices.contains(row) else { return nil }
        if column == 0 {
            let check = NSButton(checkboxWithTitle: "", target: self, action: #selector(checkClicked(_:)))
            check.tag = row
            check.state = checked[row] ? .on : .off
            return check
        }
        return ColorSwatchView(color: ColorSettingValue.color(candidates[row]))
    }

    @objc private func checkClicked(_ sender: NSButton) {
        toggle(sender.tag)
    }

    /// チェックを切り替える
    func toggle(_ row: Int) {
        guard checked.indices.contains(row) else { return }
        checked[row].toggle()
        page.list(idc("LIST_COLORS"))?.reloadRow(row)
    }

    /// 全チェック・全解除
    func checkAll(_ on: Bool) {
        checked = Array(repeating: on, count: candidates.count)
        page.list(idc("LIST_COLORS"))?.table.reloadData()
    }

    /// 選んだ色を使っている項目の名前（原版 OnSelChangeListColors）
    func showItems() {
        guard let list = page.list(idc("LIST_COLORS")) else { return }
        let row = list.selectedRow
        let names = candidates.indices.contains(row)
            ? zip(items, colors).filter { (text ? $0.1.text : $0.1.back) == candidates[row] && !(text ? $0.0.noText : $0.0.noBack) }.map { [$0.0.name] }
            : []
        page.list(idc("LIST_ITEMINFO"))?.setRows(names)
    }

    /// 選んだ色の項目の名前（テスト用）
    var itemNames: [String] { page.list(idc("LIST_ITEMINFO"))?.rows.map { $0.first ?? "" } ?? [] }

    /// OK：チェックした色を使っている項目をそろえる
    func ok() {
        result = colors
        for (candidate, on) in zip(candidates, checked) where on {
            for i in result.indices where !(text ? items[i].noText : items[i].noBack) {
                if text, result[i].text == candidate { result[i].text = color }
                if !text, result[i].back == candidate { result[i].back = color }
            }
        }
    }

    private func button(_ id: String) {
        switch id {
        case idc("BUTTON_SELALL"): checkAll(true)
        case idc("BUTTON_SELNOTING"): checkAll(false)
        case "IDOK":
            ok()
            onClose?(true)
        case "IDCANCEL":
            onClose?(false)
        default:
            break
        }
    }
}

// MARK: - 強調キーワードの設定（原版 CDlgKeywordSelect）

/// 強調キーワード 1～10 のセットを選ぶ。テンプレートは IDD_DIALOG_KEYWORD_SELECT
final class KeywordSelectDialog: NSObject {
    let page: PropPage
    let title: String
    private(set) var sets: [Int]
    var onClose: ((Bool) -> Void)?

    init?(sets: [Int]) {
        guard let definition = PropDialogs.load("TypeSettingsDialogs")?.dialog("IDD_DIALOG_KEYWORD_SELECT") else { return nil }
        page = PropPage(definition: definition)
        title = definition.name
        self.sets = sets
        super.init()
        let names = EditorCore.keywordSetNames
        for i in 0..<10 {
            page.setTaggedItems("IDC_COMBO\(i + 1)", [(-1, " ")] + names.enumerated().map { ($0.offset, $0.element) },
                                selectedValue: sets.indices.contains(i) ? sets[i] : -1)
        }
        page.onButton = { [weak self] id in
            guard let self else { return }
            if id == "IDOK" {
                self.getData()
                self.onClose?(true)
            } else if id == "IDCANCEL" {
                self.onClose?(false)
            }
        }
    }

    /// 原版 GetData
    func getData() {
        sets = (0..<10).map { page.selectedTag("IDC_COMBO\($0 + 1)") ?? -1 }
    }
}

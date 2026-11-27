// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge

/// 「印刷ページ設定」（第 47 步。原版 CDlgPrintSetting、IDD_PRINTSETTING）。
///
/// 布局照原版（Resources/PrintDialogs.json）。8 つのページ設定の写しを編集して、OK で全部書き戻す（原版 DoModal）。
/// ・ページ設定(1)：設定の切り替え（切り替える前の設定は覚えておく）、設定名変更(2)…（STR_DLGPRNST1・2、32 文字まで）
/// ・半角・全角フォント：Mac のフォントの一覧（並べ替え。原版 CBS_SORT の EnumFontFamilies）。
///   設定にある Windows のフォント（ＭＳ 明朝 等）も一覧に入れる（印刷は Mac のフォントに代えて描く。PrintCore.macFontFace）
/// ・数値の欄は範囲の外の値を範囲の端に直す（原版 DataCheckAndCorrect。フォント高は 2 桁になるまで直さない）
/// ・行あたりの文字数・縦方向の行数・フォントのポイント数をすぐ計算し、印字できる場所がないときは OK を押せない
/// ・ヘッダー・フッターのフォント：「フォント」で選ぶ（初めは半角フォントのフォント高）、「使用」を外すと指定なし。
///   フォントの名前と大きさはそのフォントで表示する（大きさはダイアログの文字）
final class PrintSettingDialog: NSObject {
    let page: PropPage
    let title: String
    /// 8 つのページ設定の写し（原版 m_PrintSettingArr）
    private(set) var settings: [PrintSetting]
    /// 選んでいる設定（原版 m_nCurrentPrintSetting）
    private(set) var currentIndex: Int
    /// 行番号の桁数（原版 m_nLineNumberColumns）
    let lineNumberColumns: Int
    /// フォントの一覧
    private(set) var fontNames: [String] = []
    private(set) var result = false
    var onClose: (() -> Void)?
    /// SetData の途中（欄の変化に反応しない）
    private var settingData = false

    /// 数値の欄（原版 sDataRange の順）
    static let fields: [(id: String, field: PrintSettingField)] = [
        ("IDC_EDIT_FONTHEIGHT", .fontHeight),
        ("IDC_EDIT_LINESPACE", .lineSpacing),
        ("IDC_EDIT_DANSUU", .columns),
        ("IDC_EDIT_DANSPACE", .columnSpace),
        ("IDC_EDIT_MARGINTY", .marginTop),
        ("IDC_EDIT_MARGINBY", .marginBottom),
        ("IDC_EDIT_MARGINLX", .marginLeft),
        ("IDC_EDIT_MARGINRX", .marginRight),
    ]
    static let headerIDs = ["IDC_EDIT_HEAD1", "IDC_EDIT_HEAD2", "IDC_EDIT_HEAD3"]
    static let footerIDs = ["IDC_EDIT_FOOT1", "IDC_EDIT_FOOT2", "IDC_EDIT_FOOT3"]
    static let checks: [(id: String, key: ReferenceWritableKeyPath<PrintSetting, Bool>)] = [
        ("IDC_CHECK_LINENUMBER", \.lineNumber),
        ("IDC_CHECK_WORDWRAP", \.wordWrap),
        ("IDC_CHECK_PS_KINSOKUHEAD", \.kinsokuHead),
        ("IDC_CHECK_PS_KINSOKUTAIL", \.kinsokuTail),
        ("IDC_CHECK_PS_KINSOKURET", \.kinsokuRet),
        ("IDC_CHECK_PS_KINSOKUKUTO", \.kinsokuKuto),
        ("IDC_CHECK_COLORPRINT", \.colorPrint),
    ]

    init?(currentIndex: Int, lineNumberColumns: Int) {
        guard let definition = PropDialogs.load("PrintDialogs")?.dialog("IDD_PRINTSETTING") else { return nil }
        page = PropPage(definition: definition)
        title = definition.name
        settings = (0 ..< PrintCore.settingCount).map { PrintCore.setting(at: $0) }
        self.currentIndex = max(0, min(currentIndex, PrintCore.settingCount - 1))
        self.lineNumberColumns = lineNumberColumns
        super.init()
        // 原版 OnInitDialog
        for (id, field) in Self.fields {
            let range = PrintCore.range(of: field)
            page.setRange(id, range.location ... range.location + range.length - 1)
        }
        page.setUnavailable(["IDC_BUTTON_HELP"], reason: L10n.tr("Mac 版にはまだヘルプがありません", comment: "help"))
        (page.control("IDOK") as? NSButton)?.keyEquivalent = "\r"
        page.onChange = { [weak self] id in self?.changed(id) }
        page.onButton = { [weak self] id in self?.buttonPressed(id) }
        for id in Self.headerIDs + Self.footerIDs {
            (page.control(id) as? NSTextField)?.delegate = self
        }
        setData()
    }

    // MARK: SetData・GetData

    /// 原版 SetData：一覧を作って、選んでいる設定を表示する
    private func setData() {
        // フォント一覧（Mac のフォント＋設定にあるフォント）
        var names = Set(NSFontManager.shared.availableFontFamilies)
        for setting in settings {
            names.insert(setting.fontHan)
            names.insert(setting.fontZen)
        }
        names.remove("")
        fontNames = names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        page.setItems("IDC_COMBO_FONT_HAN", fontNames, selected: 0)
        page.setItems("IDC_COMBO_FONT_ZEN", fontNames, selected: 0)
        // 用紙サイズ一覧
        page.setTaggedItems("IDC_COMBO_PAPER", PrintCore.papers.map { (value: $0.paperID, title: $0.name) }, selectedValue: nil)
        updateSettingNames()
        showCurrent()
    }

    /// 印刷設定名一覧
    private func updateSettingNames() {
        page.setTaggedItems("IDC_COMBO_SETTINGNAME", settings.enumerated().map { (value: $0.offset, title: $0.element.name) },
                            selectedValue: currentIndex)
    }

    /// 原版 OnChangeSettingType：選んでいる設定を欄に入れる
    private func showCurrent() {
        settingData = true
        defer { settingData = false }
        let s = settings[currentIndex]
        if let index = fontNames.firstIndex(of: s.fontHan) { page.select("IDC_COMBO_FONT_HAN", index) }
        if let index = fontNames.firstIndex(of: s.fontZen) { page.select("IDC_COMBO_FONT_ZEN", index) }
        for (id, field) in Self.fields {
            page.setInt(id, PrintCore.field(field, of: s))
        }
        page.setTaggedItems("IDC_COMBO_PAPER", PrintCore.papers.map { (value: $0.paperID, title: $0.name) }, selectedValue: s.paperSize,
                            selectIfMissing: nil)
        page.setChecked("IDC_RADIO_PORTRAIT", s.orientation != .landscape)
        page.setChecked("IDC_RADIO_LANDSCAPE", s.orientation == .landscape)
        for (id, key) in Self.checks {
            page.setChecked(id, s[keyPath: key])
        }
        for (index, id) in Self.headerIDs.enumerated() {
            page.setText(id, s.headers.indices.contains(index) ? s.headers[index] : "")
        }
        for (index, id) in Self.footerIDs.enumerated() {
            page.setText(id, s.footers.indices.contains(index) ? s.footers[index] : "")
        }
        showFont(header: true)
        showFont(header: false)
        calcPrintable()
    }

    /// 原版 GetData：欄の値を選んでいる設定に入れる。範囲の外の値は直して欄にも書き戻す
    private func getData() {
        let s = settings[currentIndex]
        if fontNames.indices.contains(page.selectedIndex("IDC_COMBO_FONT_HAN")) {
            s.fontHan = fontNames[page.selectedIndex("IDC_COMBO_FONT_HAN")]
        }
        if fontNames.indices.contains(page.selectedIndex("IDC_COMBO_FONT_ZEN")) {
            s.fontZen = fontNames[page.selectedIndex("IDC_COMBO_FONT_ZEN")]
        }
        let wasSetting = settingData
        settingData = true
        for (id, field) in Self.fields {
            let value = page.int(id)
            PrintCore.setField(field, value: value, in: s)
            let corrected = PrintCore.field(field, of: s)
            if corrected != value { page.setInt(id, corrected) }
        }
        settingData = wasSetting
        if let paper = page.selectedTag("IDC_COMBO_PAPER") { s.paperSize = paper }
        s.orientation = page.isChecked("IDC_RADIO_PORTRAIT") ? .portrait : .landscape
        for (id, key) in Self.checks {
            s[keyPath: key] = page.isChecked(id)
        }
        s.headers = Self.headerIDs.map { String(page.text($0).prefix(99)) }	// 原版 HEADER_MAX
        s.footers = Self.footerIDs.map { String(page.text($0).prefix(99)) }
        // 「使用」を外したフォントは指定なし
        if !page.isChecked("IDC_CHECK_USE_FONT_HEAD") { s.headerFont = PrintFontSetting() }
        if !page.isChecked("IDC_CHECK_USE_FONT_FOOT") { s.footerFont = PrintFontSetting() }
    }

    // MARK: 行数と桁数（原版 CalcPrintableLineAndColumn）

    /// 印字できる行数・桁数。印字できる場所があるとき true
    @discardableResult
    func calcPrintable() -> Bool {
        getData()
        let s = settings[currentIndex]
        var width = 0
        var height = 0
        guard PrintCore.paperSize(s.paperSize, orientation: s.orientation, width: &width, height: &height) else { return false }
        let columns = PrintCore.printableColumns(s, paperWidth: width, lineNumberColumns: s.lineNumber ? lineNumberColumns : 0)
        let lines = PrintCore.printableLines(s, paperHeight: height)
        page.setText("IDC_STATIC_ENABLECOLUMNS", String(columns))
        page.setText("IDC_STATIC_ENABLELINES", String(lines))
        page.setText("IDC_STATIC_FONTSIZE", PrintCore.fontSizeText(s.fontHeight))
        let ok = columns != 0 && lines != 0
        page.setEnabled("IDOK", ok)
        return ok
    }

    // MARK: ヘッダー・フッターのフォント（原版 SetFontName）

    private func showFont(header: Bool) {
        let s = settings[currentIndex]
        let font = header ? s.headerFont : s.footerFont
        let use = header ? "IDC_CHECK_USE_FONT_HEAD" : "IDC_CHECK_USE_FONT_FOOT"
        let label = header ? "IDC_STATIC_FONT_HEAD" : "IDC_STATIC_FONT_FOOT"
        let used = !font.faceName.isEmpty
        page.setChecked(use, used)
        page.setEnabled(use, used)
        page.setText(label, used ? PrintCore.fontLabel(font) : "")
        // サイズだけはダイアログの文字に合わせて、そのフォントで表示する
        if let field = page.control(label) as? NSTextField {
            field.font = used ? (Self.nsFont(font, size: PropPage.font.pointSize) ?? PropPage.font) : PropPage.font
        }
    }

    /// ヘッダー・フッターのフォント → NSFont
    static func nsFont(_ font: PrintFontSetting, size: CGFloat) -> NSFont? {
        let family = PrintCore.macFontFace(font.faceName)
        var traits: NSFontTraitMask = []
        if font.bold { traits.insert(.boldFontMask) }
        if font.italic { traits.insert(.italicFontMask) }
        return NSFontManager.shared.font(withFamily: family, traits: traits, weight: 5, size: size)
            ?? NSFont(name: family, size: size)
    }

    /// 「フォント」ボタン（原版 MySelectFont）。初めは半角フォントのフォント高
    private func chooseFont(header: Bool, window: NSWindow?) {
        let s = settings[currentIndex]
        let current = header ? s.headerFont : s.footerFont
        let initial: NSFont
        if current.faceName.isEmpty {
            // 1/10 mm → ポイント
            let size = max(1, CGFloat(s.fontHeight) * 72 / 254)
            initial = NSFontManager.shared.font(withFamily: PrintCore.macFontFace(s.fontHan), traits: [], weight: 5, size: size)
                ?? NSFont.systemFont(ofSize: size)
        } else {
            initial = Self.nsFont(current, size: CGFloat(current.pointSize) / 10) ?? NSFont.systemFont(ofSize: CGFloat(current.pointSize) / 10)
        }
        guard let chosen = CommonSettingsPages.chooseFont(initial, window) else { return }
        let font = PrintFontSetting()
        font.faceName = chosen.familyName ?? chosen.fontName
        font.pointSize = Int((chosen.pointSize * 10).rounded())
        let traits = NSFontManager.shared.traits(of: chosen)
        font.bold = traits.contains(.boldFontMask)
        font.italic = traits.contains(.italicFontMask)
        if header { s.headerFont = font } else { s.footerFont = font }
        showFont(header: header)
        calcPrintable()
    }

    // MARK: 操作（原版 OnBnClicked・OnCbnSelChange・OnEnChange）

    private func changed(_ id: String) {
        guard !settingData else { return }
        switch id {
        case "IDC_COMBO_SETTINGNAME":
            // 設定のタイプが変わった：今の設定を覚えてから切り替える
            getData()
            if let index = page.selectedTag(id) {
                currentIndex = index
                showCurrent()
            }
        case "IDC_EDIT_FONTHEIGHT":
            // 二桁以上の場合だけ（'12' と入れるとき '1' で 7 に直さない）
            if page.int(id) >= 10 { calcPrintable() }
        case "IDC_CHECK_USE_FONT_HEAD", "IDC_CHECK_USE_FONT_FOOT":
            let header = id == "IDC_CHECK_USE_FONT_HEAD"
            let s = settings[currentIndex]
            if header { s.headerFont = PrintFontSetting() } else { s.footerFont = PrintFontSetting() }
            showFont(header: header)
            calcPrintable()
        default:
            if Self.headerIDs.contains(id) || Self.footerIDs.contains(id) { return }	// フォーカスが移るときに計算する
            calcPrintable()
        }
    }

    private func buttonPressed(_ id: String) {
        switch id {
        case "IDC_BUTTON_EDITSETTINGNAME":
            editSettingName()
        case "IDC_BUTTON_FONT_HEAD":
            chooseFont(header: true, window: page.view.window)
        case "IDC_BUTTON_FONT_FOOT":
            chooseFont(header: false, window: page.view.window)
        case "IDOK":
            guard calcPrintable() else { return }
            getData()
            result = true
            onClose?()
        case "IDCANCEL":
            result = false
            onClose?()
        default:
            break
        }
    }

    /// 設定名変更（原版 CDlgInput1：STR_DLGPRNST1・STR_DLGPRNST2、32 文字まで。空は変えない）
    func editSettingName() {
        let s = settings[currentIndex]
        guard let name = CommonSettingsPages.input(L10n.tr("設定名の変更", comment: "STR_DLGPRNST1"),
                                                   L10n.tr("設定の名称を入力してください。", comment: "STR_DLGPRNST2"),
                                                   32, s.name), !name.isEmpty else { return }
        s.name = String(name.prefix(32))
        updateSettingNames()
    }

    // MARK: 結果（原版 CEditWnd::OnPrintPageSetting）

    /// 選んだ設定の番号
    var selectedIndex: Int { currentIndex }

    /// OK のあと：設定を書き戻し、設定の番号が変わったらタイプ別設定にも入れて他の窓に知らせる（PM_CHANGESETTING_TYPE）。
    /// 最後に印刷ページ設定が変わったことを知らせる（PM_PRINTSETTING）
    func apply(to document: EditorDocument) {
        for (index, setting) in settings.enumerated() where !setting.isEqual(to: PrintCore.setting(at: index)) {
            PrintCore.setSetting(setting, at: index)
        }
        if document.printSettingIndex != currentIndex, document.changePrintSettingIndex(currentIndex) {
            NotificationCenter.default.post(name: TypeSettingsWindowController.didChangeNotification, object: nil,
                                            userInfo: ["index": document.typeIndex])
        }
        NotificationCenter.default.post(name: PrintPreviewController.settingsDidChangeNotification, object: nil)
    }

    /// 原版 DoModal：閉じるまで待つ。OK で true
    func runModal(parent: NSWindow?) -> Bool {
        let panel = EscapePanel(contentRect: NSRect(origin: .zero, size: page.view.frame.size),
                                styleMask: [.titled], backing: .buffered, defer: false)
        panel.title = title
        panel.isReleasedWhenClosed = false
        panel.setAccessibilityIdentifier("PrintSettingDialog")
        panel.contentView = page.view
        panel.initialFirstResponder = page.control("IDC_COMBO_SETTINGNAME")
        panel.onCancel = { [weak self] in
            self?.result = false
            self?.onClose?()
        }
        if let parent {
            panel.setFrameOrigin(NSPoint(x: parent.frame.midX - panel.frame.width / 2, y: parent.frame.midY - panel.frame.height / 2))
        } else {
            panel.center()
        }
        onClose = { NSApp.stopModal() }
        _ = NSApp.runModal(for: panel)
        onClose = nil
        panel.orderOut(nil)
        return result
    }
}

extension PrintSettingDialog: NSTextFieldDelegate {
    /// ヘッダー・フッターの欄は、フォーカスが移るときに計算する（原版 OnEnKillFocus）
    func controlTextDidEndEditing(_ notification: Notification) {
        guard !settingData else { return }
        calcPrintable()
    }
}

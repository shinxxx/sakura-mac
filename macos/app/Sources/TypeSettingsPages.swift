// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge
import UniformTypeIdentifiers

/// タイプ別設定窗口的各页（计划第 40 步）：原版 CPropTypes*.cpp 的 SetData / GetData 的移植。
///
/// 值是 sakura.ini 的 [Types(N)] 的项目（原版 ShareData_IO_TypeConfig 的名字）。GetData 里的范围限制也照原版。
/// 第 1 个 PR：スクリーン、ウィンドウ、支援。第 2 个 PR：カラー（TypeSettingsColor.swift）、正規表現キーワード、キーワードヘルプ（TypeSettingsRegexKeyHelp.swift）。
enum TypeSettingsPages {
    /// 对话框 → 这页的处理。nil 是以后移植的页
    static func logic(for dialog: String, typeIndex: Int) -> CommonSettingsPageLogic? {
        switch dialog {
        case "IDD_PROP_SCREEN": return TypeScreenPage(typeIndex: typeIndex)
        case "IDD_PROP_COLOR": return TypeColorPage(typeIndex: typeIndex)
        case "IDD_PROP_REGEX": return TypeRegexPage(typeIndex: typeIndex)
        case "IDD_PROP_KEYHELP": return TypeKeyHelpPage(typeIndex: typeIndex)
        case "IDD_PROP_WINDOW": return TypeWindowPage()
        case "IDD_PROP_SUPPORT": return TypeSupportPage()
        default: return nil
        }
    }

    /// 选文件（原版 CDlgOpenFile::SelectFile）。测试可以换。选了时返回路径
    static var chooseFile: (_ initial: String, _ extensions: [String], _ window: NSWindow?) -> String? = { initial, extensions, _ in
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = extensions.compactMap { UTType(filenameExtension: $0) }
        panel.allowsOtherFileTypes = true
        if !initial.isEmpty {
            let url = URL(fileURLWithPath: initial)
            panel.directoryURL = url.deletingLastPathComponent()
            panel.nameFieldStringValue = url.lastPathComponent
        }
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        BookmarkStore.settingFiles.remember(url)	// 第 42 步：重启后も沙盒で読めるように
        return url.path
    }

    /// 编辑画面现在的字体（タイプ別フォントを使わないときのフォント。原版は共通設定のフォント m_sView.m_lf）。测试可以换
    static var editorFont: () -> NSFont = { EditorTextView.currentFont }

    /// 选颜色（原版 ChooseColor）。测试可以换。选了时返回颜色
    static var chooseColor: (_ color: NSColor, _ window: NSWindow?) -> NSColor? = { color, _ in
        ColorPicker.choose(color)
    }

    /// 文字色統一・背景色統一（原版 CDlgSameColor::DoModal）。测试可以换。OK 时 true
    static var runSameColorDialog: (_ dialog: SameColorDialog, _ window: NSWindow?) -> Bool = { dialog, window in
        PropModal.run(dialog.page, title: dialog.title, parent: window, identifier: "SameColorDialog") { close in dialog.onClose = close }
    }

    /// 強調キーワードの設定（原版 CDlgKeywordSelect::DoModal）。测试可以换。OK 时 true
    static var runKeywordSelectDialog: (_ dialog: KeywordSelectDialog, _ window: NSWindow?) -> Bool = { dialog, window in
        PropModal.run(dialog.page, title: dialog.title, parent: window, identifier: "KeywordSelectDialog") { close in dialog.onClose = close }
    }

    /// 「共通設定 - 強調キーワード」（原版 CPropKeyword::DlgProc_dialog）。测试可以换。OK 时 true
    static var runKeywordSettingsDialog: (_ dialog: KeywordSettingsDialog, _ window: NSWindow?) -> Bool = { dialog, window in
        PropModal.run(dialog.page, title: dialog.title, parent: window, identifier: "KeywordSettingsDialog") { close in dialog.onClose = close }
    }

    /// インポートするファイル（原版 CImpExpManager::ImportUI の「開く」）。测试可以换
    static var chooseImportFile: (_ extensions: [String], _ window: NSWindow?) -> String? = { extensions, _ in
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = extensions.compactMap { UTType(filenameExtension: $0) }
        panel.allowsOtherFileTypes = true
        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    /// エクスポートするファイル（原版 ExportUI の「名前を付けて保存」）。测试可以换
    static var chooseExportFile: (_ defaultName: String, _ extensions: [String], _ window: NSWindow?) -> String? = { name, extensions, _ in
        let panel = NSSavePanel()
        panel.allowedContentTypes = extensions.compactMap { UTType(filenameExtension: $0) }
        panel.allowsOtherFileTypes = true
        panel.nameFieldStringValue = name.isEmpty ? "" : name
        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    /// 原版 ErrorMessage / InfoMessage。测试可以换
    static var showMessage: (_ message: String) -> Void = { message in
        guard !message.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = CommonSettingsPages.appName
        alert.informativeText = message
        alert.runModal()
    }
}

/// 模板做的模态对话框（IDOK・IDCANCEL・关闭按钮で閉じる）
enum PropModal {
    /// setClose に「閉じる（OK か）」を渡すので、ダイアログの IDOK・IDCANCEL で呼んでもらう
    static func run(_ page: PropPage, title: String, parent: NSWindow?, identifier: String,
                    setClose: (@escaping (Bool) -> Void) -> Void) -> Bool {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: page.view.frame.size),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = title
        panel.isReleasedWhenClosed = false
        panel.setAccessibilityIdentifier(identifier)
        panel.contentView = page.view
        (page.control("IDOK") as? NSButton)?.keyEquivalent = "\r"
        (page.control("IDCANCEL") as? NSButton)?.keyEquivalent = "\u{1b}"
        if let parent {
            panel.setFrameOrigin(NSPoint(x: parent.frame.midX - panel.frame.width / 2, y: parent.frame.midY - panel.frame.height / 2))
        } else {
            panel.center()
        }
        var ok = false
        setClose { result in
            ok = result
            NSApp.stopModal()
        }
        let observer = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: panel, queue: nil) { _ in
            NSApp.stopModal()
        }
        _ = NSApp.runModal(for: panel)
        NotificationCenter.default.removeObserver(observer)
        panel.orderOut(nil)
        return ok
    }
}

/// 颜色面板（原版 ChooseColor 对话框的代替）。OK・キャンセル の按钮，关掉之前等着
final class ColorPicker: NSObject {
    private var color: NSColor

    private init(color: NSColor) {
        self.color = color
    }

    static func choose(_ color: NSColor) -> NSColor? {
        ColorPicker(color: color).run()
    }

    private func run() -> NSColor? {
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.color = color
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged(_:)))
        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 40))
        let ok = NSButton(title: "OK", target: self, action: #selector(okClicked(_:)))
        ok.keyEquivalent = "\r"
        ok.frame = NSRect(x: 120, y: 6, width: 90, height: 28)
        let cancel = NSButton(title: L10n.tr("キャンセル", comment: "色の選択"), target: self, action: #selector(cancelClicked(_:)))
        cancel.keyEquivalent = "\u{1b}"
        cancel.frame = NSRect(x: 22, y: 6, width: 90, height: 28)
        accessory.addSubview(cancel)
        accessory.addSubview(ok)
        let oldAccessory = panel.accessoryView
        panel.accessoryView = accessory
        let observer = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: panel, queue: nil) { _ in
            NSApp.stopModal(withCode: .cancel)
        }
        panel.makeKeyAndOrderFront(nil)
        let response = NSApp.runModal(for: panel)
        NotificationCenter.default.removeObserver(observer)
        panel.accessoryView = oldAccessory
        panel.setTarget(nil)
        panel.setAction(nil)
        panel.orderOut(nil)
        return response == .OK ? color : nil
    }

    @objc private func colorChanged(_ sender: NSColorPanel) {
        color = sender.color
    }

    @objc private func okClicked(_ sender: Any?) {
        color = NSColorPanel.shared.color
        NSApp.stopModal(withCode: .OK)
    }

    @objc private func cancelClicked(_ sender: Any?) {
        NSApp.stopModal(withCode: .cancel)
    }
}

// MARK: - nInts（原版 ShareData_IO_TypeInts：逗号分隔的 12 个数）

/// sakura.ini の nInts の何番目か
enum TypeInts: Int {
    case index = 0, maxLineKetas, columnSpace, tabSpace, keywordSet1, keywordSet2, stringType, lineNumIsCRLF,
         lineTermType, wordWrap, printSetting, tsvMode

    static func all(_ values: CommonSettingsValues) -> [Int] {
        let ints = values.string("nInts").split(separator: ",").map { Int($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
        return ints.count == 12 ? ints : Array(repeating: 0, count: 12)
    }

    func get(_ values: CommonSettingsValues) -> Int {
        Self.all(values)[rawValue]
    }

    func set(_ value: Int, _ values: CommonSettingsValues) {
        var ints = Self.all(values)
        ints[rawValue] = value
        values.set(ints.map(String.init).joined(separator: ","), "nInts")
    }
}

/// 原版 TYPE_NAME_ID の表
typealias NamedValues = [(value: Int, title: String)]

// MARK: - スクリーン（CPropTypesScreen.cpp）

/// 折り返し方法（原版 WrapMethodArr）
let wrapMethods: NamedValues = [
    (0, L10n.tr("折り返さない", comment: "STR_WRAP_METHOD_NO_WRAP")),
    (1, L10n.tr("指定桁で折り返す", comment: "STR_WRAP_METHOD_SPEC_WIDTH")),
    (2, L10n.tr("右端で折り返す", comment: "STR_WRAP_METHOD_WIN_WIDTH")),
]
/// TAB表示（原版 TabArrowArr）
let tabArrows: NamedValues = [
    (0, L10n.tr("文字指定", comment: "STR_TAB_SYMBOL_CHARA")),
    (1, L10n.tr("短い矢印", comment: "STR_TAB_SYMBOL_SHORT_ARROW")),
    (2, L10n.tr("長い矢印", comment: "STR_TAB_SYMBOL_LONG_ARROW")),
]
/// TSVモード（原版 TsvModeArr）
let tsvModes: NamedValues = [
    (0, L10n.tr("通常", comment: "STR_TSV_MODE_NONE")),
    (1, "TSV"),
    (2, "CSV"),
]
/// スマートインデント（原版 SmartIndentArr）
let smartIndents: NamedValues = [
    (0, L10n.tr("なし", comment: "STR_SMART_INDENT_NONE")),
    (1, "C/C++"),
]
/// 折り返し行インデント（原版 IndentTypeArr）
let wrapIndents: NamedValues = [
    (0, L10n.tr("なし", comment: "STR_WRAP_INDENT_NONE")),
    (1, "tx2x"),
    (2, L10n.tr("論理行先頭", comment: "STR_WRAP_INDENT_BOL")),
]
/// アウトライン解析方法・標準ルール（原版 OlmArr。値は EOutlineType）
let outlineMethods: NamedValues = [
    (1, "C/C++"),		// OUTLINE_C_CPP
    (0, "C"),			// OUTLINE_C
    (16, "C++"),		// OUTLINE_CPP
    (2, "PL/SQL"),		// OUTLINE_PLSQL
    (4, "Java"),		// OUTLINE_JAVA
    (5, "COBOL"),		// OUTLINE_COBOL
    (7, "Perl"),		// OUTLINE_PERL
    (6, L10n.tr("アセンブラ", comment: "STR_OUTLINE_ASM")),	// OUTLINE_ASM
    (8, "Visual Basic"),	// OUTLINE_VB
    (13, "Python"),		// OUTLINE_PYTHON
    (14, "Erlang"),		// OUTLINE_ERLANG
    (9, L10n.tr("WZ階層付テキスト", comment: "STR_OUTLINE_WZ")),	// OUTLINE_WZTXT
    (10, "HTML"),		// OUTLINE_HTML
    (15, "XML"),		// OUTLINE_XML
    (11, "TeX"),		// OUTLINE_TEX
    (3, L10n.tr("テキスト", comment: "STR_OUTLINE_TEXT")),	// OUTLINE_TEXT
]
/// アウトライン解析：ルールファイル（OUTLINE_FILE）
let outlineRuleFile = 12

struct TypeScreenPage: CommonSettingsPageLogic {
    /// 「基本」（Types(0)）は名前と拡張子を変えられない
    let typeIndex: Int

    static let minLineKetas = 10, maxLineKetas = 10240	// MINLINEKETAS、MAXLINEKETAS
    static let columnSpaceMax = 64, lineSpaceMax = 128, tabSpaceMax = 64	// COLUMNSPACE_MAX、LINESPACE_MAX、TABSPACE_MAX

    /// タイプ別フォント（sakura.ini の lf、nPointSize、lfFaceName）
    static let font = LogFontSetting(lf: "lf", pointSize: "nPointSize", faceName: "lfFaceName")

    private let checks: [(id: String, key: String)] = [
        (idc("CHECK_INS_SPACE"), "bInsSpace"),
        (idc("CHECK_INDENT"), "bAutoIndent"),
        (idc("CHECK_INDENT_WSPACE"), "bAutoIndent_ZENSPACE"),
        (idc("CHECK_RTRIM_PREVLINE"), "bRTrimPrevLine"),
        (idc("CHECK_KINSOKUHEAD"), "bKinsokuHead"),
        (idc("CHECK_KINSOKUTAIL"), "bKinsokuTail"),
        (idc("CHECK_KINSOKURET"), "bKinsokuRet"),
        (idc("CHECK_KINSOKUKUTO"), "bKinsokuKuto"),
        (idc("CHECK_KINSOKUHIDE"), "bKinsokuHide"),
    ]
    private let texts: [(id: String, key: String)] = [
        (idc("EDIT_INDENTCHARS"), "szIndentChars"),
        (idc("EDIT_KINSOKUHEAD"), "szKinsokuHead"),
        (idc("EDIT_KINSOKUTAIL"), "szKinsokuTail"),
        (idc("EDIT_KINSOKUKUTO"), "szKinsokuKuto"),
    ]

    var ranges: [String: ClosedRange<Int>] {
        [idc("EDIT_MAXLINELEN"): Self.minLineKetas...Self.maxLineKetas,
         idc("EDIT_CHARSPACE"): 0...Self.columnSpaceMax,
         idc("EDIT_LINESPACE"): -Self.lineSpaceMax...Self.lineSpaceMax,
         idc("EDIT_TABSPACE"): 1...Self.tabSpaceMax]
    }

    func setData(_ page: PropPage, _ values: CommonSettingsValues) {
        page.setText(idc("EDIT_TYPENAME"), values.string("szTypeName"))
        page.setText(idc("EDIT_TYPEEXTS"), values.string("szTypeExts"))

        // レイアウト
        page.loadCombo(idc("COMBO_WRAPMETHOD"), wrapMethods, value: values.int("nTextWrapMethod"))
        page.setInt(idc("EDIT_MAXLINELEN"), TypeInts.maxLineKetas.get(values))
        page.setInt(idc("EDIT_CHARSPACE"), TypeInts.columnSpace.get(values))
        page.setInt(idc("EDIT_LINESPACE"), values.int("nLineSpace"))
        page.setInt(idc("EDIT_TABSPACE"), TypeInts.tabSpace.get(values))
        page.setText(idc("EDIT_TABVIEWSTRING"), values.string("szTabViewString"))
        page.loadCombo(idc("CHECK_TAB_ARROW"), tabArrows, value: values.int("bTabArrow"))
        page.loadCombo(idc("COMBO_TSV_MODE"), tsvModes, value: TypeInts.tsvMode.get(values))

        // インデント
        page.loadChecks(checks, values)
        for (id, key) in texts { page.setText(id, values.string(key)) }
        page.loadCombo(idc("COMBO_SMARTINDENT"), smartIndents, value: values.int("nSmartIndent"))
        page.loadCombo(idc("COMBO_INDENTLAYOUT"), wrapIndents, value: values.int("nIndentLayout"))

        // アウトライン解析方法：ルールファイル名は使わなくても表示する
        let outline = values.int("nDefaultOutline")
        page.setText(idc("EDIT_OUTLINERULEFILE"), values.string("szOutlineRuleFilename"))
        if outline != outlineRuleFile {
            page.setChecked(idc("RADIO_OUTLINEDEFAULT"), true)
            page.setTaggedItems(idc("COMBO_OUTLINES"), outlineMethods, selectedValue: outline)
        } else {
            page.setChecked(idc("RADIO_OUTLINERULEFILE"), true)
            page.setTaggedItems(idc("COMBO_OUTLINES"), outlineMethods, selectedValue: nil, selectIfMissing: nil)
        }

        // フォント
        page.setChecked(idc("CHECK_USETYPEFONT"), values.bool("bUseTypeFont"))
        setFontLabel(page, values)

        // 英文ワードラップ
        page.setChecked(idc("CHECK_WORDWRAP"), TypeInts.wordWrap.get(values) != 0)
    }

    func getData(_ page: PropPage, _ values: CommonSettingsValues) {
        if typeIndex != 0 {
            values.set(page.text(idc("EDIT_TYPENAME")), "szTypeName")
            values.set(page.text(idc("EDIT_TYPEEXTS")), "szTypeExts")
        }

        // レイアウト
        values.set(page.comboValue(idc("COMBO_WRAPMETHOD"), wrapMethods), "nTextWrapMethod")
        TypeInts.maxLineKetas.set(clamp(page.int(idc("EDIT_MAXLINELEN")), Self.minLineKetas...Self.maxLineKetas), values)
        TypeInts.columnSpace.set(clamp(page.int(idc("EDIT_CHARSPACE")), 0...Self.columnSpaceMax), values)
        values.set(clamp(page.signedInt(idc("EDIT_LINESPACE")), -Self.lineSpaceMax...Self.lineSpaceMax), "nLineSpace")
        TypeInts.tabSpace.set(clamp(page.int(idc("EDIT_TABSPACE")), 1...Self.tabSpaceMax), values)
        values.set(Self.tabViewString(page.text(idc("EDIT_TABVIEWSTRING"))), "szTabViewString")
        values.set(page.comboValue(idc("CHECK_TAB_ARROW"), tabArrows), "bTabArrow")
        TypeInts.tsvMode.set(page.comboValue(idc("COMBO_TSV_MODE"), tsvModes), values)

        // インデント
        page.storeChecks(checks, values)
        for (id, key) in texts { values.set(page.text(id), key) }
        values.set(page.comboValue(idc("COMBO_SMARTINDENT"), smartIndents), "nSmartIndent")
        values.set(page.comboValue(idc("COMBO_INDENTLAYOUT"), wrapIndents), "nIndentLayout")

        // アウトライン解析方法
        if !page.isChecked(idc("RADIO_OUTLINERULEFILE")) {
            if let method = page.selectedTag(idc("COMBO_OUTLINES")) {
                values.set(method, "nDefaultOutline")
            }
        } else {
            values.set(outlineRuleFile, "nDefaultOutline")
        }
        values.set(page.text(idc("EDIT_OUTLINERULEFILE")), "szOutlineRuleFilename")

        // フォント
        values.set(page.isChecked(idc("CHECK_USETYPEFONT")), "bUseTypeFont")

        TypeInts.wordWrap.set(page.isChecked(idc("CHECK_WORDWRAP")) ? 1 : 0, values)
    }

    /// TAB表示文字列（原版 GetData）：「^」と空白 7 個の 8 文字に、入力した文字を先頭から入れる（TAB、改行、NUL まで）
    static func tabViewString(_ input: String) -> String {
        var result = Array("^       ".utf16)
        let typed = Array(input.utf16.prefix(8))
        for (i, unit) in typed.enumerated() {
            if unit == 0 || unit == 0x0d || unit == 0x0a || unit == 0x09 { break }	// WCODE::IsTabAvailableCode
            result[i] = unit
        }
        return String(utf16CodeUnits: result, count: result.count)
    }

    private func setFontLabel(_ page: PropPage, _ values: CommonSettingsValues) {
        if page.isChecked(idc("CHECK_USETYPEFONT")) {
            Self.font.setLabel(page, idc("STATIC_TYPEFONT"), values)
        } else {
            page.setText(idc("STATIC_TYPEFONT"), "")	// 原版 SetFontLabel(…, FALSE)
        }
    }

    func enable(_ page: PropPage) {
        // 「基本」は名前と拡張子を変えられない
        page.setEnabled(idc("EDIT_TYPENAME"), typeIndex != 0)
        page.setEnabled(idc("EDIT_TYPEEXTS"), typeIndex != 0)
        // 矢印表示のときは TAB 表示文字列を変えられない
        page.setEnabled(idc("EDIT_TABVIEWSTRING"), page.comboValue(idc("CHECK_TAB_ARROW"), tabArrows) == 0)
        // アウトライン解析：標準ルール／ルールファイル
        let ruleFile = page.isChecked(idc("RADIO_OUTLINERULEFILE"))
        page.setEnabled(idc("COMBO_OUTLINES"), !ruleFile)
        page.setEnabled(idc("EDIT_OUTLINERULEFILE"), ruleFile)
        page.setEnabled(idc("BUTTON_RULEFILE_REF"), ruleFile)
        // タイプ別フォントを使うときだけ「使用する」を外せる（外すと選べなくなる。フォントを選ぶと使う）
        page.setEnabled(idc("CHECK_USETYPEFONT"), page.isChecked(idc("CHECK_USETYPEFONT")))
        // ぶら下げを隠す：改行ぶら下げか句読点ぶら下げのとき
        page.setEnabled(idc("CHECK_KINSOKUHIDE"), page.isChecked(idc("CHECK_KINSOKURET")) || page.isChecked(idc("CHECK_KINSOKUKUTO")))
    }

    func changed(_ id: String, _ page: PropPage, _ values: CommonSettingsValues) {
        switch id {
        case idc("RADIO_OUTLINEDEFAULT"):
            // 原版：標準ルールを選ぶとリストの先頭を選ぶ
            page.setTaggedItems(idc("COMBO_OUTLINES"), outlineMethods, selectedValue: outlineMethods[0].value)
        case idc("CHECK_USETYPEFONT"):
            setFontLabel(page, values)
        default:
            break
        }
    }

    func buttonPressed(_ id: String, _ page: PropPage, _ values: CommonSettingsValues, window: NSWindow?) {
        switch id {
        case idc("BUTTON_RULEFILE_REF"):
            if let path = TypeSettingsPages.chooseFile(page.text(idc("EDIT_OUTLINERULEFILE")), ["rul", "rule", "txt"], window) {
                page.setText(idc("EDIT_OUTLINERULEFILE"), path)
            }
        case idc("BUTTON_TYPEFONT"):
            // タイプ別フォントを使っていればそのフォント、使っていなければ編集画面のフォントから選ぶ
            let initial = page.isChecked(idc("CHECK_USETYPEFONT")) ? Self.font.font(values) : TypeSettingsPages.editorFont()
            guard let chosen = CommonSettingsPages.chooseFont(initial, window) else { return }
            Self.font.set(chosen, values)
            page.setChecked(idc("CHECK_USETYPEFONT"), true)
            setFontLabel(page, values)
        default:
            break
        }
    }
}

// MARK: - ウィンドウ（CPropTypesWindow.cpp）

/// 起動時のIME：ON/OFF状態（原版 ImeSwitchArr）
let imeSwitches: NamedValues = [
    (0, L10n.tr("そのまま", comment: "STR_IME_SWITCH_DONTSET")),
    (1, L10n.tr("常にON", comment: "STR_IME_SWITCH_ON")),
    (2, L10n.tr("常にOFF", comment: "STR_IME_SWITCH_OFF")),
]
/// 起動時のIME：入力モード（原版 ImeStateArr）
let imeStates: NamedValues = [
    (0, L10n.tr("標準設定", comment: "STR_IME_STATE_DEF")),
    (1, L10n.tr("全角", comment: "STR_IME_STATE_FULL")),
    (2, L10n.tr("全角ひらがな", comment: "STR_IME_STATE_FULLHIRA")),
    (3, L10n.tr("全角カタカナ", comment: "STR_IME_STATE_FULLKATA")),
    (4, L10n.tr("無変換", comment: "STR_IME_STATE_NO")),
]
/// 改行コード（原版 aszEolStr、aeEolType）
let defaultEols: NamedValues = [
    (1, "CR+LF"), (2, "LF (UNIX)"), (3, "CR (Mac)"), (4, "NEL"), (5, "LS"), (6, "PS"),
]
/// 背景画像の表示位置（原版 STR_IMAGE_POS1～9。値は EBackgroundImagePos）
let backgroundImagePositions: NamedValues = [
    (0, L10n.tr("左上", comment: "STR_IMAGE_POS1")),
    (1, L10n.tr("右上", comment: "STR_IMAGE_POS2")),
    (2, L10n.tr("左下", comment: "STR_IMAGE_POS3")),
    (3, L10n.tr("右下", comment: "STR_IMAGE_POS4")),
    (4, L10n.tr("中央", comment: "STR_IMAGE_POS5")),
    (5, L10n.tr("中央上", comment: "STR_IMAGE_POS6")),
    (6, L10n.tr("中央下", comment: "STR_IMAGE_POS7")),
    (7, L10n.tr("中央左", comment: "STR_IMAGE_POS8")),
    (8, L10n.tr("中央右", comment: "STR_IMAGE_POS9")),
]

struct TypeWindowPage: CommonSettingsPageLogic {
    static let lineNumWidthRange = 2...11	// LINENUMWIDTH_MIN、LINENUMWIDTH_MAX

    private let checks: [(id: String, key: String)] = [
        (idc("CHECK_DOCICON"), "bUseDocumentIcon"),
        (idc("CHECK_PRIOR_CESU8"), "bPriorCesu8"),
        (idc("CHECK_BACKIMG_REP_X"), "bgImgRepeartX"),
        (idc("CHECK_BACKIMG_REP_Y"), "bgImgRepeartY"),
        (idc("CHECK_BACKIMG_SCR_X"), "bgImgScrollX"),
        (idc("CHECK_BACKIMG_SCR_Y"), "bgImgScrollY"),
    ]
    private static let lineTermButtons = [idc("RADIO_LINETERMTYPE0"), idc("RADIO_LINETERMTYPE1"), idc("RADIO_LINETERMTYPE2")]

    var ranges: [String: ClosedRange<Int>] {
        [idc("EDIT_LINENUMWIDTH"): Self.lineNumWidthRange, idc("EDIT_BACKIMG_TRANSPARENCY"): 0...255]
    }

    /// デフォルトの文字コードに選べる文字コード（原版 CCodeTypesForCombobox のうち CanDefault）
    static var defaultEncodings: NamedValues {
        EditorCore.encodingChoices.filter { EditorCore.canBeDefault($0.encoding) }.map { (Int($0.encoding), $0.name) }
    }

    /// 「CP」で追加するコードページ（原版 CCodePage::AddComboCodePages）
    static var codePages: NamedValues {
        EditorCore.codePageChoices.map { (Int($0.encoding), $0.name) }
    }

    func setData(_ page: PropPage, _ values: CommonSettingsValues) {
        page.loadChecks(checks, values)

        // 起動時のIME：下位 2 ビットが ON/OFF、その上が入力モード
        let ime = values.int("nImeState")
        page.loadCombo(idc("COMBO_IMESWITCH"), imeSwitches, value: ime & 3)
        page.loadCombo(idc("COMBO_IMESTATE"), imeStates, value: ime >> 2)

        // デフォルトの文字コード：一覧になければ「CP」をチェックしてコードページを足す
        let code = values.int("eDefaultCodetype")
        page.setChecked(idc("CHECK_CP"), false)
        if !page.setTaggedItems(idc("COMBO_DEFAULT_CODETYPE"), Self.defaultEncodings, selectedValue: code, selectIfMissing: nil) {
            page.setChecked(idc("CHECK_CP"), true)
            if !page.appendTaggedItems(idc("COMBO_DEFAULT_CODETYPE"), Self.codePages, selectedValue: code) {
                page.select(idc("COMBO_DEFAULT_CODETYPE"), 0)
            }
        }
        // BOM：付けられない文字コードなら付けない
        let canHaveBOM = EditorCore.canHaveBOM(EditorEncoding(code))
        page.setChecked(idc("CHECK_DEFAULT_BOM"), canHaveBOM && values.bool("bDefaultBom"))
        page.loadCombo(idc("COMBO_DEFAULT_EOLTYPE"), defaultEols, value: values.int("eDefaultEoltype"))

        // 行番号の表示：改行単位／折り返し単位
        page.setChecked(TypeInts.lineNumIsCRLF.get(values) != 0 ? idc("RADIO_LINENUM_CRLF") : idc("RADIO_LINENUM_LAYOUT"), true)
        page.setInt(idc("EDIT_LINENUMWIDTH"), values.int("nLineNumWidth"))

        // 背景画像
        page.setText(idc("EDIT_BACKIMG_PATH"), values.string("bgImgPath"))
        page.loadCombo(idc("COMBO_BACKIMG_POS"), backgroundImagePositions, value: values.int("bgImgPos"))
        page.setText(idc("EDIT_BACKIMG_OFFSET_X"), String(values.int("bgImgPosOffsetX")))
        page.setText(idc("EDIT_BACKIMG_OFFSET_Y"), String(values.int("bgImgPosOffsetY")))
        let transparency = 255 - clamp(values.int("bgImgOpacity"), 0...255)
        page.setSliderRange(idc("TRACKBAR_BACKIMG_TRANSPARENCY"), 0...255)
        page.setInt(idc("EDIT_BACKIMG_TRANSPARENCY"), transparency)
        page.setSliderValue(idc("TRACKBAR_BACKIMG_TRANSPARENCY"), transparency)

        // 行番号区切り：0 なし、1 縦線、2 任意
        let lineTerm = TypeInts.lineTermType.get(values)
        if Self.lineTermButtons.indices.contains(lineTerm) { page.setChecked(Self.lineTermButtons[lineTerm], true) }
        page.setText(idc("EDIT_LINETERMCHAR"), values.string("cLineTermChar"))
    }

    func getData(_ page: PropPage, _ values: CommonSettingsValues) {
        page.storeChecks(checks, values)

        values.set(page.comboValue(idc("COMBO_IMESTATE"), imeStates) << 2 | page.comboValue(idc("COMBO_IMESWITCH"), imeSwitches), "nImeState")

        if let code = page.selectedTag(idc("COMBO_DEFAULT_CODETYPE")) { values.set(code, "eDefaultCodetype") }
        values.set(page.isChecked(idc("CHECK_DEFAULT_BOM")), "bDefaultBom")
        values.set(page.comboValue(idc("COMBO_DEFAULT_EOLTYPE"), defaultEols), "eDefaultEoltype")

        TypeInts.lineNumIsCRLF.set(page.isChecked(idc("RADIO_LINENUM_LAYOUT")) ? 0 : 1, values)

        values.set(page.text(idc("EDIT_BACKIMG_PATH")), "bgImgPath")
        values.set(page.comboValue(idc("COMBO_BACKIMG_POS"), backgroundImagePositions), "bgImgPos")
        values.set(page.signedInt(idc("EDIT_BACKIMG_OFFSET_X")), "bgImgPosOffsetX")
        values.set(page.signedInt(idc("EDIT_BACKIMG_OFFSET_Y")), "bgImgPosOffsetY")
        values.set(255 - min(255, page.int(idc("EDIT_BACKIMG_TRANSPARENCY"))), "bgImgOpacity")

        if let lineTerm = Self.lineTermButtons.firstIndex(where: page.isChecked) {
            TypeInts.lineTermType.set(lineTerm, values)
        }
        // 行番号区切り文字：先頭の 1 文字（空なら「なし」）
        values.set(page.text(idc("EDIT_LINETERMCHAR")).utf16.first.map { String(utf16CodeUnits: [$0], count: 1) } ?? "", "cLineTermChar")

        values.set(clamp(page.int(idc("EDIT_LINENUMWIDTH")), Self.lineNumWidthRange), "nLineNumWidth")
    }

    func enable(_ page: PropPage) {
        // 行番号区切り：任意のときだけ文字を変えられる
        let any = page.isChecked(idc("RADIO_LINETERMTYPE2"))
        page.setEnabled(idc("LABEL_LINETERMCHAR"), any)
        page.setEnabled(idc("EDIT_LINETERMCHAR"), any)
        // CP：一度押したら戻せない（原版はチェックして無効にする）
        page.setEnabled(idc("CHECK_CP"), !page.isChecked(idc("CHECK_CP")))
        // BOM：付けられる文字コードのときだけ
        let code = page.selectedTag(idc("COMBO_DEFAULT_CODETYPE")) ?? 0
        page.setEnabled(idc("CHECK_DEFAULT_BOM"), EditorCore.canHaveBOM(EditorEncoding(code)))
    }

    func changed(_ id: String, _ page: PropPage, _ values: CommonSettingsValues) {
        switch id {
        case idc("COMBO_DEFAULT_CODETYPE"):
            // 文字コードを変えたら BOM はその文字コードの既定（原版 CBN_SELCHANGE）
            if let code = page.selectedTag(id) {
                page.setChecked(idc("CHECK_DEFAULT_BOM"), EditorCore.bomDefault(EditorEncoding(code)))
            }
        case idc("CHECK_CP"):
            // コードページを足す（選んでいる文字コードはそのまま）
            page.setChecked(id, true)
            page.appendTaggedItems(idc("COMBO_DEFAULT_CODETYPE"), Self.codePages, selectedValue: nil)
        case idc("EDIT_BACKIMG_TRANSPARENCY"):
            page.setSliderValue(idc("TRACKBAR_BACKIMG_TRANSPARENCY"), min(255, page.int(id)))
        case idc("TRACKBAR_BACKIMG_TRANSPARENCY"):
            page.setInt(idc("EDIT_BACKIMG_TRANSPARENCY"), page.sliderValue(id))
        default:
            break
        }
    }

    func buttonPressed(_ id: String, _ page: PropPage, _ values: CommonSettingsValues, window: NSWindow?) {
        if id == idc("BUTTON_BACKIMG_PATH_SEL"),
           let path = TypeSettingsPages.chooseFile(page.text(idc("EDIT_BACKIMG_PATH")), ["bmp", "jpg", "jpeg", "png"], window) {
            page.setText(idc("EDIT_BACKIMG_PATH"), path)
        }
    }
}

// MARK: - 支援（CPropTypesSupport.cpp）

struct TypeSupportPage: CommonSettingsPageLogic {
    private let checks: [(id: String, key: String)] = [
        (idc("CHECK_HOKANLOHICASE"), "bHokanLoHiCase"),
        (idc("CHECK_HOKANBYFILE"), "bUseHokanByFile"),
        (idc("CHECK_HOKANBYKEYWORD"), "bUseHokanByKeyword"),
        (idc("CHECK_TYPEHTMLHELPISSINGLE"), "bTypeHtmlHelpIsSingle"),
        (idc("CHECK_CHKENTERATEND"), "bChkEnterAtEnd"),
        (idc("CHECK_INDENTCPPSTR"), "bIndentCppStringIgnore"),
        (idc("CHECK_INDENTCPPCMT"), "bIndentCppCommentIgnore"),
        (idc("CHECK_INDENTCPPUNDO"), "bIndentCppUndoSep"),
        (idc("CHECK_DETECT_INDENTATION_STYLE_ON_FILE_LOAD"), "bDetectIndentationStyleOnFileLoad"),
    ]

    /// 補完種別（プラグインが追加する。DLL のプラグインは Mac 版にない）、外部ヘルプ・外部 HTML ヘルプ（Windows のヘルプ。偏离项 9）
    var unavailable: Set<String> {
        Set(["COMBO_HOKAN_TYPE", "EDIT_TYPEEXTHELP", "BUTTON_TYPEOPENHELP", "EDIT_TYPEEXTHTMLHELP",
             "BUTTON_TYPEOPENEXTHTMLHELP", "CHECK_TYPEHTMLHELPISSINGLE"].map(idc))
    }

    func setData(_ page: PropPage, _ values: CommonSettingsValues) {
        page.setText(idc("EDIT_HOKANFILE"), values.string("szHokanFile"))
        // 補完種別：プラグインがないので「なし」だけ（値は変えない）
        page.setItems(idc("COMBO_HOKAN_TYPE"), [L10n.tr("なし", comment: "STR_SMART_INDENT_NONE")], selected: 0)
        page.loadChecks(checks, values)
        page.setText(idc("EDIT_TYPEEXTHELP"), values.string("szExtHelp"))
        page.setText(idc("EDIT_TYPEEXTHTMLHELP"), values.string("szExtHtmlHelp"))
    }

    func getData(_ page: PropPage, _ values: CommonSettingsValues) {
        page.storeChecks(checks, values)
        values.set(page.text(idc("EDIT_HOKANFILE")), "szHokanFile")
    }

    func buttonPressed(_ id: String, _ page: PropPage, _ values: CommonSettingsValues, window: NSWindow?) {
        if id == idc("BUTTON_HOKANFILE_REF"),
           let path = TypeSettingsPages.chooseFile(page.text(idc("EDIT_HOKANFILE")), ["kwd"], window) {
            page.setText(idc("EDIT_HOKANFILE"), path)
        }
    }
}

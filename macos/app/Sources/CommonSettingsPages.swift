// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge

/// 共通設定窗口的各页（计划第 39 步）：原版 CPropCom*.cpp 的 SetData / GetData / Enable…Input 的移植。
///
/// 值是 sakura.ini 的「节/项目」（原版 CShareData_IO 的名字）。GetData 里的范围限制也照原版。
/// 这一步移植的页：全般、ウィンドウ（位置と大きさの設定 も）、タブバー、ステータスバー、編集、ファイル、
/// ファイル名表示（置換リスト も）、バックアップ、書式、検索、支援（タブバー・支援 的フォント も）。
/// 強調キーワード は第 40 步（KeywordSettingsPage.swift）、キー割り当て・メインメニュー・ツールバー・カスタムメニュー は第 41 步
/// （KeyBindPage.swift、MainMenuPage.swift、CustomMenuToolbarPages.swift）。以后的步骤：
/// マクロ（第 45 步，下の MacroPage）。プラグイン 是 DLL，Mac 版没有（偏离项 9）。
protocol CommonSettingsPageLogic {
    /// 数值框的范围（原版 SetUpDownRange）
    var ranges: [String: ClosedRange<Int>] { get }
    /// Mac 版做不到的项目（变灰，值不改）
    var unavailable: Set<String> { get }
    /// 以后的版本移植的项目（变灰）
    var notYet: Set<String> { get }
    /// 原版 SetData：值 → 控件
    func setData(_ page: PropPage, _ values: CommonSettingsValues)
    /// 原版 GetData：控件 → 值
    func getData(_ page: PropPage, _ values: CommonSettingsValues)
    /// 原版 Enable…Input：按控件的状态决定哪些可用。每次控件变化以后都调用
    func enable(_ page: PropPage)
    /// 控件变了（原版 WM_COMMAND 里 Enable 以外的处理）
    func changed(_ id: String, _ page: PropPage, _ values: CommonSettingsValues)
    /// 按钮
    func buttonPressed(_ id: String, _ page: PropPage, _ values: CommonSettingsValues, window: NSWindow?)
    /// 又显示了这一页（原版 PSN_SETACTIVE。第一次是 setData）
    func activate(_ page: PropPage, _ values: CommonSettingsValues)
}

extension CommonSettingsPageLogic {
    var ranges: [String: ClosedRange<Int>] { [:] }
    var unavailable: Set<String> { [] }
    var notYet: Set<String> { [] }
    func enable(_ page: PropPage) {}
    func changed(_ id: String, _ page: PropPage, _ values: CommonSettingsValues) {}
    func buttonPressed(_ id: String, _ page: PropPage, _ values: CommonSettingsValues, window: NSWindow?) {}
    func activate(_ page: PropPage, _ values: CommonSettingsValues) {}
}

enum CommonSettingsPages {
    /// 对话框 → 这页的处理。nil 是以后的步骤移植的页
    static func logic(for dialog: String) -> CommonSettingsPageLogic? {
        switch dialog {
        case "IDD_PROP_GENERAL": return GeneralPage()
        case "IDD_PROP_WIN": return WindowPage()
        case "IDD_PROP_TAB": return TabPage()
        case "IDD_PROP_STATUSBAR": return StatusbarPage()
        case "IDD_PROP_EDIT": return EditPage()
        case "IDD_PROP_FILE": return FilePage()
        case "IDD_PROP_FNAME": return FileNamePage()
        case "IDD_PROP_BACKUP": return BackupPage()
        case "IDD_PROP_FORMAT": return FormatPage()
        case "IDD_PROP_GREP": return GrepPage()
        case "IDD_PROP_HELPER": return HelperPage()
        case "IDD_PROP_KEYWORD": return KeywordSettingsPage()	// 第 40 步
        case "IDD_PROP_KEYBIND": return KeyBindPage()			// 第 41 步
        case "IDD_PROP_MAINMENU": return MainMenuPage()		// 第 41 步
        case "IDD_PROP_CUSTMENU": return CustomMenuPage()		// 第 41 步
        case "IDD_PROP_TOOLBAR": return ToolbarPage()			// 第 41 步
        case "IDD_PROP_MACRO": return MacroPage()				// 第 45 步
        default: return nil
        }
    }

    /// 确认（原版 MYMESSAGEBOX MB_OKCANCEL）。测试可以换
    static var confirm: (String) -> Bool = { message in
        let alert = NSAlert()
        alert.messageText = CommonSettingsPages.appName
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: NSLocalizedString("キャンセル", comment: "共通設定的确认"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// 文字の入力（原版 CDlgInput1：題名、説明、最大文字数、初期値）。测试可以换。キャンセルは nil
    static var input: (_ title: String, _ message: String, _ maxLength: Int, _ initial: String) -> String? = { title, message, maxLength, initial in
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: NSLocalizedString("キャンセル", comment: "共通設定的确认"))
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = initial
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return String(field.stringValue.prefix(maxLength))
    }

    /// 通知（原版 InfoMessage）。测试可以换
    static var inform: (String) -> Void = { message in
        let alert = NSAlert()
        alert.messageText = CommonSettingsPages.appName
        alert.informativeText = message
        alert.runModal()
    }

    /// 选文件夹（原版 SelectDir）。测试可以换。选了时返回路径
    static var chooseFolder: (_ title: String, _ initial: String) -> String? = { title, initial in
        let panel = NSOpenPanel()
        panel.message = title
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if !initial.isEmpty { panel.directoryURL = URL(fileURLWithPath: initial, isDirectory: true) }
        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    /// 选字体（原版 MySelectFont：ChooseFont）。测试可以换。选了时返回字体
    static var chooseFont: (_ font: NSFont, _ window: NSWindow?) -> NSFont? = { font, window in
        FontPicker.choose(font, window: window)
    }

    /// 「ウィンドウの位置と大きさ」を表示する（原版 CDlgWinSize::DoModal）。测试可以换
    static var runWinSizeDialog: (_ dialog: WinSizeDialog, _ window: NSWindow?) -> Void = { dialog, window in
        dialog.runModal(parent: window)
    }

    static var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "サクラエディタ"
    }
}

// MARK: - 共通的函数

func clamp(_ value: Int, _ range: ClosedRange<Int>) -> Int {
    min(max(value, range.lowerBound), range.upperBound)
}

extension PropPage {
    /// 复选框 ← bool 项目
    func loadChecks(_ pairs: [(id: String, key: String)], _ values: CommonSettingsValues, section: String? = nil) {
        for (id, key) in pairs { setChecked(id, values.bool(key, section: section)) }
    }

    /// 复选框 → bool 项目（Mac 版不能用的不改）
    func storeChecks(_ pairs: [(id: String, key: String)], _ values: CommonSettingsValues, section: String? = nil) {
        for (id, key) in pairs where !isUnavailable(id) { values.set(isChecked(id), key, section: section) }
    }

    /// 组合框 ← 值（原版：表里和值相同的项，没有时是第一项）
    func loadCombo(_ id: String, _ items: [(value: Int, title: String)], value: Int) {
        setItems(id, items.map { $0.title }, selected: items.firstIndex { $0.value == value } ?? 0)
    }

    /// 组合框 → 值
    func comboValue(_ id: String, _ items: [(value: Int, title: String)]) -> Int {
        let index = selectedIndex(id)
        return items.indices.contains(index) ? items[index].value : items[0].value
    }
}

/// 原版 ID 的简写
func idc(_ name: String) -> String { "IDC_" + name }

// MARK: - 全般（CPropComGeneral.cpp）

/// 组合起来用滚轮时（原版 SpecialScrollModeArr）
private let specialScrollModes: [(value: Int, title: String)] = [
    (0, NSLocalizedString("組み合わせなし", comment: "STR_SCROLL_WITH_NO_KEY")),
    (2, NSLocalizedString("マウス中ボタン", comment: "STR_SCROLL_WITH_MID_BTN")),			// MOUSEFUNCTION_CENTER
    (3, NSLocalizedString("マウスサイドボタン1", comment: "STR_SCROLL_WITH_SIDE_1_BTN")),	// MOUSEFUNCTION_LEFTSIDE
    (4, NSLocalizedString("マウスサイドボタン2", comment: "STR_SCROLL_WITH_SIDE_2_BTN")),	// MOUSEFUNCTION_RIGHTSIDE
    (17, NSLocalizedString("CONTROLキー", comment: "STR_SCROLL_WITH_CTRL_KEY")),			// VK_CONTROL
    (16, NSLocalizedString("SHIFTキー", comment: "STR_SCROLL_WITH_SHIFT_KEY")),			// VK_SHIFT
]

struct GeneralPage: CommonSettingsPageLogic {
    static let maxMRU = 36	// MAX_MRU、MAX_OPENFOLDER
    private let checks: [(id: String, key: String)] = [
        (idc("CHECK_FREECARET"), "bIsFreeCursorMode"),
        (idc("CHECK_STOPS_BOTH_ENDS_WHEN_SEARCH_WORD"), "bStopsBothEndsWhenSearchWord"),
        (idc("CHECK_STOPS_BOTH_ENDS_WHEN_SEARCH_PARAGRAPH"), "bStopsBothEndsWhenSearchParagraph"),
        (idc("CHECK_NOMOVE_ACTIVATE_BY_MOUSE"), "NoCaretMoveByActivation"),
        (idc("CHECK_CLOSEALLCONFIRM"), "bCloseAllConfirm"),
        (idc("CHECK_EXITCONFIRM"), "bExitConfirm"),
        (idc("CHECK_REPEATEDSCROLLSMOOTH"), "nRepeatedScroll_Smooth"),
        (idc("CHECK_MEMDC"), "bUseCompotibleBMP"),
        (idc("CHECK_USETRAYICON"), "bTaskTrayUse"),
        (idc("CHECK_STAYTASKTRAY"), "bTaskTrayStay"),
    ]

    var ranges: [String: ClosedRange<Int>] {
        [idc("EDIT_REPEATEDSCROLLLINENUM"): 1...10,
         idc("EDIT_MAX_MRU_FILE"): 0...Self.maxMRU,
         idc("EDIT_MAX_MRU_FOLDER"): 0...Self.maxMRU]
    }

    /// タスクトレイ（偏离项 7：Mac 版没有任务托盘、常驻）、画面キャッシュ（Windows 的绘制方式）
    var unavailable: Set<String> {
        [idc("CHECK_USETRAYICON"), idc("CHECK_STAYTASKTRAY"), idc("HOTKEY_TRAYMENU"),
         "左クリックメニューのショートカットキー(K)", idc("CHECK_MEMDC")]
    }

    func setData(_ page: PropPage, _ values: CommonSettingsValues) {
        page.setChecked(values.int("nCaretType") == 0 ? idc("RADIO_CARETTYPE0") : idc("RADIO_CARETTYPE1"), true)
        page.loadChecks(checks, values)
        page.setInt(idc("EDIT_REPEATEDSCROLLLINENUM"), values.int("nRepeatedScrollLineNum"))
        page.loadCombo(idc("COMBO_WHEEL_PAGESCROLL"), specialScrollModes, value: values.int("nPageScrollByWheel"))
        page.loadCombo(idc("COMBO_WHEEL_HSCROLL"), specialScrollModes, value: values.int("nHorizontalScrollByWheel"))
        page.setInt(idc("EDIT_MAX_MRU_FILE"), values.int("nMRUArrNum_MAX"))
        page.setInt(idc("EDIT_MAX_MRU_FOLDER"), values.int("nOPENFOLDERArrNum_MAX"))
    }

    func getData(_ page: PropPage, _ values: CommonSettingsValues) {
        if page.isChecked(idc("RADIO_CARETTYPE0")) { values.set(0, "nCaretType") }
        if page.isChecked(idc("RADIO_CARETTYPE1")) { values.set(1, "nCaretType") }
        page.storeChecks(checks, values)
        values.set(clamp(page.int(idc("EDIT_REPEATEDSCROLLLINENUM")), 1...10), "nRepeatedScrollLineNum")
        values.set(page.comboValue(idc("COMBO_WHEEL_PAGESCROLL"), specialScrollModes), "nPageScrollByWheel")
        values.set(page.comboValue(idc("COMBO_WHEEL_HSCROLL"), specialScrollModes), "nHorizontalScrollByWheel")
        values.set(clamp(page.int(idc("EDIT_MAX_MRU_FILE")), 0...Self.maxMRU), "nMRUArrNum_MAX")
        values.set(clamp(page.int(idc("EDIT_MAX_MRU_FOLDER")), 0...Self.maxMRU), "nOPENFOLDERArrNum_MAX")
    }

    func enable(_ page: PropPage) {
        page.setEnabled(idc("CHECK_STAYTASKTRAY"), page.isChecked(idc("CHECK_USETRAYICON")))
    }

    func buttonPressed(_ id: String, _ page: PropPage, _ values: CommonSettingsValues, window: NSWindow?) {
        switch id {
        case idc("BUTTON_CLEAR_MRU_FILE"):
            guard CommonSettingsPages.confirm(NSLocalizedString("最近使ったファイルの履歴を削除します。\nよろしいですか？", comment: "STR_PROPCOMGEN_FILE1")) else { return }
            EditorCore.clearRecentFiles()
            CommonSettingsPages.inform(NSLocalizedString("最近使ったファイルの履歴を削除しました。", comment: "STR_PROPCOMGEN_FILE2"))
        case idc("BUTTON_CLEAR_MRU_FOLDER"):
            guard CommonSettingsPages.confirm(NSLocalizedString("最近使ったフォルダーの履歴を削除します。\nよろしいですか？", comment: "STR_PROPCOMGEN_DIR1")) else { return }
            EditorCore.clearRecentFolders()
            CommonSettingsPages.inform(NSLocalizedString("最近使ったフォルダーの履歴を削除しました。", comment: "STR_PROPCOMGEN_DIR2"))
        default:
            break
        }
    }
}

// MARK: - ウィンドウ（CPropComWin.cpp）

struct WindowPage: CommonSettingsPageLogic {
    private let checks: [(id: String, key: String)] = [
        (idc("CHECK_DispTOOLBAR"), "bDispTOOLBAR"),
        (idc("CHECK_DispFUNCKEYWND"), "bDispFUNCKEYWND"),
        (idc("CHECK_DispSTATUSBAR"), "bDispSTATUSBAR"),
        (idc("CHECK_bScrollBarHorz"), "bScrollBarHorz"),
        (idc("CHECK_bMenuIcon"), "bMenuIcon"),
        (idc("CHECK_bDarkMode"), "bDarkMode"),
        (idc("CHECK_SplitterWndVScroll"), "bSplitterWndVScroll"),
        (idc("CHECK_SplitterWndHScroll"), "bSplitterWndHScroll"),
    ]
    private let ints: [(id: String, key: String, range: ClosedRange<Int>)] = [
        (idc("EDIT_FUNCKEYWND_GROUPNUM"), "nFUNCKEYWND_GroupNum", 1...12),
        (idc("EDIT_nRulerHeight"), "nRulerHeight", 2...32),	// IDC_SPIN_nRulerHeight_MIN、MAX
        (idc("EDIT_nRulerBottomSpace"), "nRulerBottomSpace", 0...32),
        (idc("EDIT_nLineNumberRightSpace"), "nLineNumberRightSpace", 0...32),
    ]

    var ranges: [String: ClosedRange<Int>] {
        Dictionary(uniqueKeysWithValues: ints.map { ($0.id, $0.range) })
    }

    /// 言語（语言 DLL。Mac 版的语言跟着系统，偏离项 9）
    var unavailable: Set<String> { [idc("COMBO_LANGUAGE")] }

    func setData(_ page: PropPage, _ values: CommonSettingsValues) {
        page.loadChecks(checks, values)
        page.setChecked(values.int("nFUNCKEYWND_Place") == 0 ? idc("RADIO_FUNCKEYWND_PLACE1") : idc("RADIO_FUNCKEYWND_PLACE2"), true)
        for item in ints { page.setInt(item.id, values.int(item.key)) }
        page.setText(idc("WINCAPTION_ACTIVE"), values.string("szWinCaptionActive"))
        page.setText(idc("WINCAPTION_INACTIVE"), values.string("szWinCaptionInactive"))
        page.setItems(idc("COMBO_LANGUAGE"), [NSLocalizedString("日本語", comment: "共通設定 > ウィンドウ > 言語")], selected: 0)
    }

    func getData(_ page: PropPage, _ values: CommonSettingsValues) {
        page.storeChecks(checks, values)
        if page.isChecked(idc("RADIO_FUNCKEYWND_PLACE1")) { values.set(0, "nFUNCKEYWND_Place") }
        if page.isChecked(idc("RADIO_FUNCKEYWND_PLACE2")) { values.set(1, "nFUNCKEYWND_Place") }
        for item in ints { values.set(clamp(page.int(item.id), item.range), item.key) }
        values.set(page.text(idc("WINCAPTION_ACTIVE")), "szWinCaptionActive")
        values.set(page.text(idc("WINCAPTION_INACTIVE")), "szWinCaptionInactive")
    }

    func buttonPressed(_ id: String, _ page: PropPage, _ values: CommonSettingsValues, window: NSWindow?) {
        guard id == idc("BUTTON_WINSIZE") else { return }
        // 位置と大きさの設定（原版 CDlgWinSize。rc.right/bottom が幅・高さ、rc.top/left が X・Y 座標）
        guard let dialog = WinSizeDialog(values: .init(
            saveSize: values.int("bSaveWindowSize"), savePosition: values.int("nSaveWindowPos"),
            sizeType: values.int("nWinSizeType"), width: values.int("nWinSizeCX"), height: values.int("nWinSizeCY"),
            x: values.int("nWinPosX"), y: values.int("nWinPosY"))) else {
            NSSound.beep()
            return
        }
        CommonSettingsPages.runWinSizeDialog(dialog, window)
        let result = dialog.values
        values.set(result.saveSize, "bSaveWindowSize")
        values.set(result.savePosition, "nSaveWindowPos")
        values.set(result.sizeType, "nWinSizeType")
        values.set(result.width, "nWinSizeCX")
        values.set(result.height, "nWinSizeCY")
        values.set(result.x, "nWinPosX")
        values.set(result.y, "nWinPosY")
    }

    func enable(_ page: PropPage) {
        let on = page.isChecked(idc("CHECK_DispFUNCKEYWND"))
        for id in ["EDIT_FUNCKEYWND_GROUPNUM", "RADIO_FUNCKEYWND_PLACE1", "RADIO_FUNCKEYWND_PLACE2"] {
            page.setEnabled(idc(id), on)
        }
    }
}

// MARK: - タブバー（CPropComTab.cpp）

struct TabPage: CommonSettingsPageLogic {
    private let checks: [(id: String, key: String)] = [
        (idc("CHECK_DispTabWnd"), "bDispTabWnd"),
        (idc("CHECK_SameTabWidth"), "bSameTabWidth"),
        (idc("CHECK_DispTabIcon"), "bDispTabIcon"),
        (idc("CHECK_SortTabList"), "bSortTabList"),
        (idc("CHECK_TAB_MULTILINE"), "bTabMultiLine"),
        (idc("CHECK_RetainEmptyWindow"), "bTab_RetainEmptyWin"),
        (idc("CHECK_CloseOneWin"), "bTab_CloseOneWin"),
        (idc("CHECK_ChgWndByWheel"), "bChgWndByWheel"),
        (idc("CHECK_OpenNewWin"), "bNewWindow"),
    ]
    /// 閉じるボタン（原版 DispTabCloseArr）
    private let closeButtons: [(value: Int, title: String)] = [
        (0, NSLocalizedString("なし", comment: "STR_PROPCOMTAB_DISP_NO")),
        (1, NSLocalizedString("常に表示", comment: "STR_PROPCOMTAB_DISP_ALLWAYS")),
        (2, NSLocalizedString("自動表示", comment: "STR_PROPCOMTAB_DISP_AUTO")),
    ]
    /// 表示位置（原版 TabPosArr。左右は原版でも無効）
    private let positions: [(value: Int, title: String)] = [
        (0, NSLocalizedString("上", comment: "STR_PROPCOMTAB_TAB_POS_TOP")),
        (1, NSLocalizedString("下", comment: "STR_PROPCOMTAB_TAB_POS_BOTTOM")),
    ]

    /// タブのフォント（sakura.ini の lfTabFont、lfTabFontPs、lfTabFaceName）
    static let font = LogFontSetting(lf: "lfTabFont", pointSize: "lfTabFontPs", faceName: "lfTabFaceName")

    func setData(_ page: PropPage, _ values: CommonSettingsValues) {
        page.loadChecks(checks, values)
        Self.font.setLabel(page, idc("STATIC_TABFONT"), values)
        // 「ウィンドウをまとめてグループ化する」は m_bDispTabWndMultiWin の反対
        page.setChecked(idc("CHECK_DispTabWndMultiWin"), !values.bool("bDispTabWndMultiWin"))
        page.setText(idc("TABWND_CAPTION"), values.string("szTabWndCaption"))
        page.loadCombo(idc("CHECK_DispTabClose"), closeButtons, value: values.int("bDispTabClose"))
        page.loadCombo(idc("COMBO_TAB_POSITION"), positions, value: values.int("eTabPosition"))
    }

    func getData(_ page: PropPage, _ values: CommonSettingsValues) {
        page.storeChecks(checks, values)
        values.set(!page.isChecked(idc("CHECK_DispTabWndMultiWin")), "bDispTabWndMultiWin")
        values.set(page.text(idc("TABWND_CAPTION")), "szTabWndCaption")
        values.set(page.comboValue(idc("CHECK_DispTabClose"), closeButtons), "bDispTabClose")
        values.set(page.comboValue(idc("COMBO_TAB_POSITION"), positions), "eTabPosition")
    }

    func buttonPressed(_ id: String, _ page: PropPage, _ values: CommonSettingsValues, window: NSWindow?) {
        if id == idc("BUTTON_TABFONT") {
            Self.font.choose(page, idc("STATIC_TABFONT"), values, window: window)
        }
    }

    func enable(_ page: PropPage) {
        let tabWnd = page.isChecked(idc("CHECK_DispTabWnd"))
        let multiWin = tabWnd && page.isChecked(idc("CHECK_DispTabWndMultiWin"))
        page.setEnabled(idc("CHECK_DispTabWndMultiWin"), tabWnd)
        for id in ["CHECK_RetainEmptyWindow", "CHECK_CloseOneWin", "CHECK_OpenNewWin"] {
            page.setEnabled(idc(id), multiWin)
        }
        for id in ["CHECK_DispTabIcon", "CHECK_SameTabWidth", "CHECK_DispTabClose", "TextTabClose", "TextTabCaption",
                   "BUTTON_TABFONT", "STATIC_TABFONT", "CHECK_SortTabList", "CHECK_TAB_MULTILINE", "TAB_POSITION",
                   "COMBO_TAB_POSITION", "TABWND_CAPTION", "CHECK_ChgWndByWheel"] {
            page.setEnabled(idc(id), tabWnd)
        }
    }
}

// MARK: - ステータスバー（CPropComStatusbar.cpp）

struct StatusbarPage: CommonSettingsPageLogic {
    private let checks: [(id: String, key: String)] = [
        (idc("CHECK_DISP_UNICODE_IN_SJIS"), "DispUnicodeInSjis"),
        (idc("CHECK_DISP_UNICODE_IN_JIS"), "DispUnicodeInJis"),
        (idc("CHECK_DISP_UNICODE_IN_EUC"), "DispUnicodeInEuc"),
        (idc("CHECK_DISP_UTF8_CODEPOINT"), "DispUtf8Codepoint"),
        (idc("CHECK_DISP_SP_CODEPOINT"), "DispSurrogatePairCodepoint"),
        (idc("CHECK_DISP_SELCOUNT_BY_BYTE"), "DispSelectCountByByte"),
        (idc("CHECK_DISP_COL_BY_CHAR"), "DispColByChar"),
    ]

    func setData(_ page: PropPage, _ values: CommonSettingsValues) {
        page.loadChecks(checks, values, section: "Statusbar")
    }

    func getData(_ page: PropPage, _ values: CommonSettingsValues) {
        page.storeChecks(checks, values, section: "Statusbar")
    }
}

// MARK: - 編集（CPropComEdit.cpp）

struct EditPage: CommonSettingsPageLogic {
    private let checks: [(id: String, key: String)] = [
        (idc("CHECK_DRAGDROP"), "bUseOLE_DragDrop"),
        (idc("CHECK_DROPSOURCE"), "bUseOLE_DropSource"),
        (idc("CHECK_ADDCRLFWHENCOPY"), "bAddCRLFWhenCopy"),
        (idc("CHECK_COPYnDISABLESELECTEDAREA"), "bCopyAndDisablSelection"),
        (idc("CHECK_bEnableNoSelectCopy"), "bEnableNoSelectCopy"),
        (idc("CHECK_bEnableLineModePaste"), "bEnableLineModePaste"),
        (idc("CHECK_bNotOverWriteCRLF"), "bNotOverWriteCRLF"),
        (idc("CHECK_bOverWriteFixMode"), "bOverWriteFixMode"),
        (idc("CHECK_bOverWriteBoxDelete"), "bOverWriteBoxDelete"),
        (idc("CHECK_bSelectClickedURL"), "bSelectClickedURL"),
        (idc("CHECK_CONVERTEOLPASTE"), "bConvertEOLPaste"),
        (idc("CHECK_ENABLEEXTEOL"), "bEnableExtEol"),
        (idc("CHECK_BOXSELECTLOCK"), "bBoxSelectLock"),
        (idc("CHECK_VISTA_STYLE_FILEDIALOG"), "bVistaStyleFileDialog"),
    ]
    /// ファイルダイアログの初期位置（OPENDIALOGDIR_CUR、MRU、SEL）
    private let dirRadios = [idc("RADIO_CURDIR"), idc("RADIO_MRUDIR"), idc("RADIO_SELDIR")]

    /// Vista スタイルのファイルダイアログ（Windows 的对话框的种类）
    var unavailable: Set<String> { [idc("CHECK_VISTA_STYLE_FILEDIALOG")] }

    func setData(_ page: PropPage, _ values: CommonSettingsValues) {
        page.loadChecks(checks, values)
        let dir = values.int("eOpenDialogDir")
        if dirRadios.indices.contains(dir) { page.setChecked(dirRadios[dir], true) }
        page.setText(idc("EDIT_FILEOPENDIR"), values.string("szOpenDialogSelDir"))
    }

    func getData(_ page: PropPage, _ values: CommonSettingsValues) {
        page.storeChecks(checks, values)
        for (value, id) in dirRadios.enumerated() where page.isChecked(id) { values.set(value, "eOpenDialogDir") }
        values.set(page.text(idc("EDIT_FILEOPENDIR")), "szOpenDialogSelDir")
    }

    func enable(_ page: PropPage) {
        // ドラッグ & ドロップ編集 のときだけ ドロップ元にする（原版 SetData、BN_CLICKED）
        page.setEnabled(idc("CHECK_DROPSOURCE"), page.isChecked(idc("CHECK_DRAGDROP")))
        let selDir = page.isChecked(idc("RADIO_SELDIR"))
        page.setEnabled(idc("EDIT_FILEOPENDIR"), selDir)
        page.setEnabled(idc("BUTTON_FILEOPENDIR"), selDir)
    }

    func buttonPressed(_ id: String, _ page: PropPage, _ values: CommonSettingsValues, window: NSWindow?) {
        guard id == idc("BUTTON_FILEOPENDIR") else { return }
        if let folder = CommonSettingsPages.chooseFolder(NSLocalizedString("フォルダーを選んでください", comment: "STR_PROPEDIT_SELECT_DIR"),
                                                         page.text(idc("EDIT_FILEOPENDIR"))) {
            page.setText(idc("EDIT_FILEOPENDIR"), folder)
        }
    }
}

// MARK: - ファイル（CPropComFile.cpp）

/// 排他制御（原版 ShareModeArr）
private let shareModes: [(value: Int, title: String)] = [
    (0, NSLocalizedString("しない", comment: "STR_EXCLU_NO_EXCLUSIVE")),
    (1, NSLocalizedString("上書きを禁止する", comment: "STR_EXCLU_DENY_WRITE")),
    (2, NSLocalizedString("読み書きを禁止する", comment: "STR_EXCLU_DENY_READWRITE")),
]

/// 自動保存（m_sBackup の bBackUpType2_Opt1 の BKUP_AUTO ビット、間隔は bBackUpType2_Opt3）
private let backupAutoBit = 64

/// 原版 CPropFile::GetData の数字の読み方：先頭から数字が続く所まで
private func leadingNumber(_ text: String) -> Int {
    var value = 0
    for ch in text {
        guard let digit = ch.wholeNumberValue, ch.isASCII else { break }
        value = min(value * 10 + digit, Int(Int32.max))
    }
    return value
}

struct FilePage: CommonSettingsPageLogic {
    private let checks: [(id: String, key: String)] = [
        (idc("CHECK_bCheckFileTimeStamp"), "bCheckFileTimeStamp"),
        (idc("CHECK_bUneditableIfUnwritable"), "bUneditableIfUnwritable"),
        (idc("CHECK_ENABLEUNMODIFIEDOVERWRITE"), "bEnableUnmodifiedOverwrite"),
        (idc("CHECK_bDropFileAndClose"), "bDropFileAndClose"),
        (idc("CHECK_RestoreCurPosition"), "m_bRestoreCurPosition"),
        (idc("CHECK_RestoreBookmarks"), "m_bRestoreBookmarks"),
        (idc("CHECK_AutoMIMEDecode"), "bAutoMIMEdecode"),
        (idc("CHECK_QueryIfCodeChange"), "bQueryIfCodeChange"),
        (idc("CHECK_AlertIfFileNotExist"), "bAlertIfFileNotExist"),
        (idc("CHECK_ALERT_IF_LARGEFILE"), "bAlertIfLargeFile"),
        (idc("CHECK_NoFilterSaveNew"), "bNoFilterSaveNew"),
        (idc("CHECK_NoFilterSaveFile"), "bNoFilterSaveFile"),
    ]

    var ranges: [String: ClosedRange<Int>] {
        [idc("EDIT_AUTOLOAD_DELAY"): 0...Int(Int16.max),
         idc("EDIT_nDropFileNumMax"): 1...99,
         idc("EDIT_AUTOBACKUP_INTERVAL"): 1...Int(Int16.max),
         idc("EDIT_ALERT_FILESIZE"): 1...2048]
    }

    /// 排他制御（macOS 没有 Windows 的共享模式。偏离项 9）
    var unavailable: Set<String> { [idc("COMBO_FILESHAREMODE"), "排他制御(H)"] }

    func setData(_ page: PropPage, _ values: CommonSettingsValues) {
        page.loadCombo(idc("COMBO_FILESHAREMODE"), shareModes, value: values.int("nFileShareMode"))
        page.loadChecks(checks, values)
        page.setInt(idc("EDIT_AUTOLOAD_DELAY"), values.int("nAutoloadDelay"))
        page.setInt(idc("EDIT_nDropFileNumMax"), values.int("nDropFileNumMax"))
        page.setChecked(idc("CHECK_AUTOSAVE"), values.int("bBackUpType2_Opt1") & backupAutoBit != 0)
        page.setInt(idc("EDIT_AUTOBACKUP_INTERVAL"), clamp(values.int("bBackUpType2_Opt3"), 1...35791))
        page.setInt(idc("EDIT_ALERT_FILESIZE"), values.int("nAlertFileSize"))
    }

    func getData(_ page: PropPage, _ values: CommonSettingsValues) {
        page.storeChecks(checks, values)
        values.set(page.int(idc("EDIT_AUTOLOAD_DELAY")), "nAutoloadDelay")
        values.set(clamp(page.int(idc("EDIT_nDropFileNumMax")), 1...99), "nDropFileNumMax")
        let opt1 = values.int("bBackUpType2_Opt1")
        values.set(page.isChecked(idc("CHECK_AUTOSAVE")) ? opt1 | backupAutoBit : opt1 & ~backupAutoBit, "bBackUpType2_Opt1")
        values.set(clamp(leadingNumber(page.text(idc("EDIT_AUTOBACKUP_INTERVAL"))), 1...35791), "bBackUpType2_Opt3")
        values.set(clamp(page.int(idc("EDIT_ALERT_FILESIZE")), 1...2048), "nAlertFileSize")
    }

    func enable(_ page: PropPage) {
        let dropMulti = !page.isChecked(idc("CHECK_bDropFileAndClose"))
        for id in ["LABEL_AUTOSAVE3", "LABEL_AUTOSAVE4", "EDIT_nDropFileNumMax"] { page.setEnabled(idc(id), dropMulti) }
        // 原版：排他制御「しない」のときだけ 更新の監視。Mac 版はファイルをロックしないので常に「しない」と同じ
        page.setEnabled(idc("CHECK_bCheckFileTimeStamp"), true)
        let watch = page.isChecked(idc("CHECK_bCheckFileTimeStamp"))
        for id in ["LABEL_AUTOLOAD_DELAY", "EDIT_AUTOLOAD_DELAY"] { page.setEnabled(idc(id), watch) }
        let autosave = page.isChecked(idc("CHECK_AUTOSAVE"))
        for id in ["EDIT_AUTOBACKUP_INTERVAL", "LABEL_AUTOSAVE", "LABEL_AUTOSAVE2"] { page.setEnabled(idc(id), autosave) }
        page.setEnabled(idc("EDIT_ALERT_FILESIZE"), page.isChecked(idc("CHECK_ALERT_IF_LARGEFILE")))
    }
}

// MARK: - ファイル名表示（CPropComFileName.cpp）

final class FileNamePage: CommonSettingsPageLogic {
    /// 置換リストの最大数（原版 MAX_TRANSFORM_FILENAME）
    static let maxCount = 16
    private let list = idc("LIST_FNAME")
    private let from = idc("EDIT_FNAME_FROM")
    private let to = idc("EDIT_FNAME_TO")
    /// 前回選択していた行（原版 m_nLastPos_FILENAME）
    private var lastPosition = -1

    func setData(_ page: PropPage, _ values: CommonSettingsValues) {
        page.setChecked(idc("CHECK_SHORTPATH"), values.bool("bShortPath", section: "Nickname"))
        page.setInt(idc("EDIT_SHORTMAXWIDTH"), values.int("nShortPathMaxWidth", section: "Nickname"))

        // ファイル名置換リスト（置換前が空の項目は表示しない）
        guard let listView = page.list(list) else { return }
        if listView.table.tableColumns.count < 2, let scroll = page.control(list) {
            let width = scroll.frame.width
            listView.setColumns([NSLocalizedString("置換前", comment: "STR_PROPCOMFNM_LIST1"),
                                 NSLocalizedString("置換後", comment: "STR_PROPCOMFNM_LIST2")],
                                widths: [(width * 60 / 100).rounded(), (width * 35 / 100).rounded()])
        }
        let count = min(max(0, values.int("ArrNum", section: "Nickname")), Self.maxCount)
        var rows: [[String]] = []
        for i in 0..<count {
            let source = values.string(Self.key("From", i), section: "Nickname")
            if source.isEmpty { continue }
            rows.append([source, values.string(Self.key("To", i), section: "Nickname")])
        }
        lastPosition = -1
        listView.setRows(rows)
        // 一番上を選択しておく
        if !rows.isEmpty {
            listView.select(0)
            selectionChanged(page)
        }
    }

    func getData(_ page: PropPage, _ values: CommonSettingsValues) {
        values.set(page.isChecked(idc("CHECK_SHORTPATH")), "bShortPath", section: "Nickname")
        values.set(page.int(idc("EDIT_SHORTMAXWIDTH")), "nShortPathMaxWidth", section: "Nickname")

        // ファイル名置換リスト（置換前が空の項目は捨てる）
        guard let rows = page.list(list)?.rows else { return }
        let entries = rows.filter { !($0.first ?? "").isEmpty }
        values.set(entries.count, "ArrNum", section: "Nickname")
        for (i, entry) in entries.enumerated() {
            values.set(entry[0], Self.key("From", i), section: "Nickname")
            values.set(entry.count > 1 ? entry[1] : "", Self.key("To", i), section: "Nickname")
        }
    }

    func changed(_ id: String, _ page: PropPage, _ values: CommonSettingsValues) {
        if id == list { selectionChanged(page) }
    }

    /// 原版 LVN_ITEMCHANGED：選択した項目をエディットへ
    private func selectionChanged(_ page: PropPage) {
        guard let listView = page.list(list) else { return }
        let index = listView.selectedRow
        if index == -1 {
            page.setText(from, "")
            page.setText(to, "")
        } else if index != lastPosition {
            page.setText(from, listView.rows[index][0])
            page.setText(to, listView.rows[index][1])
        }
        // 同じ行のときはコピーしない（原版：[更新] がうまく動作しないため）
        lastPosition = index
    }

    func buttonPressed(_ id: String, _ page: PropPage, _ values: CommonSettingsValues, window: NSWindow?) {
        guard let listView = page.list(list) else { return }
        let index = listView.selectedRow
        let count = listView.rows.count
        let source = page.text(from), target = page.text(to)
        switch id {
        case idc("BUTTON_FNAME_INS"):	// 挿入（選択中でなければ最後に追加）
            setItem(page, listView, index == -1 ? count : index, source, target, insert: true)
        case idc("BUTTON_FNAME_ADD"):	// 追加
            setItem(page, listView, count, source, target, insert: true)
        case idc("BUTTON_FNAME_UPD"):	// 更新
            if index != -1 {
                setItem(page, listView, index, source, target, insert: false)
            } else if count == 0 {
                // リストに項目がなければ、更新ボタンで項目を追加できる
                setItem(page, listView, 0, source, target, insert: true)
            }
        case idc("BUTTON_FNAME_DEL"):	// 削除
            guard index != -1 else { return }
            var rows = listView.rows
            rows.remove(at: index)
            listView.setRows(rows)
            listView.select(index)
        case idc("BUTTON_FNAME_TOP"):	// 先頭
            move(page, listView, index, 0)
        case idc("BUTTON_FNAME_UP"):	// 上へ
            move(page, listView, index, index - 1)
        case idc("BUTTON_FNAME_DOWN"):	// 下へ
            move(page, listView, index, index + 1)
        case idc("BUTTON_FNAME_LAST"):	// 最終
            move(page, listView, index, count - 1)
        default:
            break
        }
    }

    /// 原版 SetListViewItem_FILENAME：置換前が空なら何もしない。挿入はこれ以上追加できなければエラー
    @discardableResult
    private func setItem(_ page: PropPage, _ listView: PropList, _ index: Int, _ source: String, _ target: String, insert: Bool) -> Bool {
        guard !source.isEmpty, index >= 0 else { return false }
        var rows = listView.rows
        if insert && rows.count >= Self.maxCount {
            CommonSettingsPages.inform(NSLocalizedString("これ以上登録できません。", comment: "STR_PROPCOMFNM_ERR_REG"))
            return false
        }
        if insert {
            rows.insert([source, target], at: min(index, rows.count))
        } else {
            guard rows.indices.contains(index) else { return false }
            rows[index] = [source, target]
        }
        listView.setRows(rows)
        listView.select(index)
        return true
    }

    /// 原版 MoveListViewItem_FILENAME
    private func move(_ page: PropPage, _ listView: PropList, _ index: Int, _ index2: Int) {
        let count = listView.rows.count
        guard count > 0 else { return }
        let a = min(max(index, 0), count - 1), b = min(max(index2, 0), count - 1)
        guard a != b else { return }
        var rows = listView.rows
        let item = rows.remove(at: a)
        listView.setRows(rows)
        setItem(page, listView, b, item[0], item[1], insert: true)
    }

    private static func key(_ prefix: String, _ index: Int) -> String {
        prefix + (index < 10 ? "0\(index)" : "\(index)")
    }
}

// MARK: - バックアップ（CPropComBackup.cpp）

/// バックアップファイル名の日付（EBackupOptionFlag）
private let backupDateBits: [(id: String, bit: Int, format: String)] = [
    (idc("CHECK_BACKUP_YEAR"), 32, "%Y"),
    (idc("CHECK_BACKUP_MONTH"), 16, "%m"),
    (idc("CHECK_BACKUP_DAY"), 8, "%d"),
    (idc("CHECK_BACKUP_HOUR"), 4, "%H"),
    (idc("CHECK_BACKUP_MIN"), 2, "%M"),
    (idc("CHECK_BACKUP_SEC"), 1, "%S"),
]

struct BackupPage: CommonSettingsPageLogic {
    private let checks: [(id: String, key: String)] = [
        (idc("CHECK_BACKUP"), "bBackUp"),
        (idc("CHECK_BACKUPDIALOG"), "bBackUpDialog"),
        (idc("CHECK_BACKUPFOLDER"), "bBackUpFolder"),
        (idc("CHECK_BACKUP_FOLDER_RM"), "bBackUpFolderRM"),
        (idc("CHECK_BACKUP_DUSTBOX"), "bBackUpDustBox"),
        (idc("CHECK_BACKUP_ADVANCED"), "bBackUpPathAdvanced"),
    ]

    var ranges: [String: ClosedRange<Int>] { [idc("EDIT_BACKUP_3"): 1...99] }

    func setData(_ page: PropPage, _ values: CommonSettingsValues) {
        page.loadChecks(checks, values)
        // バックアップファイル名のタイプ 1=.bak 2=日付(現時刻) 3=.b?? 4=日付(前回) 5=.*.bak 6=.*.b??
        let type = values.int("nBackUpType")
        switch type {
        case 2: page.setChecked(idc("RADIO_BACKUP_DATETYPE1"), true)
        case 3, 6: page.setChecked(idc("RADIO_BACKUP_TYPE3"), true)
        case 4: page.setChecked(idc("RADIO_BACKUP_DATETYPE2"), true)
        default: page.setChecked(idc("RADIO_BACKUP_TYPE1"), true)
        }
        page.setChecked(idc("CHECK_BACKUP_RETAINEXT"), type == 5 || type == 6)
        let opt1 = values.int("bBackUpType2_Opt1")
        for item in backupDateBits { page.setChecked(item.id, opt1 & item.bit == item.bit) }
        page.setText(idc("EDIT_BACKUPFOLDER"), values.string("szBackUpFolder"))
        page.setText(idc("EDIT_BACKUPFILE"), values.string("szBackUpPathAdvanced"))
        page.setChecked(values.int("bBackUpType2_Opt4") == 4 ? idc("RADIO_BACKUP_DATETYPE2A") : idc("RADIO_BACKUP_DATETYPE1A"), true)
        page.setInt(idc("EDIT_BACKUP_3"), clamp(values.int("bBackUpType2_Opt2") & 0xffff, 1...99))
        updateBackupFile(page, values)
    }

    func getData(_ page: PropPage, _ values: CommonSettingsValues) {
        page.storeChecks(checks, values)
        let retainExt = page.isChecked(idc("CHECK_BACKUP_RETAINEXT"))
        if page.isChecked(idc("RADIO_BACKUP_TYPE1")) { values.set(retainExt ? 5 : 1, "nBackUpType") }
        if page.isChecked(idc("RADIO_BACKUP_DATETYPE1")) { values.set(2, "nBackUpType") }
        if page.isChecked(idc("RADIO_BACKUP_DATETYPE2")) { values.set(4, "nBackUpType") }
        if page.isChecked(idc("RADIO_BACKUP_TYPE3")) { values.set(retainExt ? 6 : 3, "nBackUpType") }
        var opt1 = values.int("bBackUpType2_Opt1")
        for item in backupDateBits { opt1 = page.isChecked(item.id) ? opt1 | item.bit : opt1 & ~item.bit }
        values.set(opt1, "bBackUpType2_Opt1")
        values.set(page.text(idc("EDIT_BACKUPFOLDER")), "szBackUpFolder")
        values.set(page.text(idc("EDIT_BACKUPFILE")), "szBackUpPathAdvanced")
        if page.isChecked(idc("RADIO_BACKUP_DATETYPE1A")) { values.set(2, "bBackUpType2_Opt4") }
        if page.isChecked(idc("RADIO_BACKUP_DATETYPE2A")) { values.set(4, "bBackUpType2_Opt4") }
        // 世代数は bBackUpType2_Opt2 の下位 16 ビット（上位は拡張子の文字）
        let opt2 = values.int("bBackUpType2_Opt2")
        values.set((opt2 & ~0xffff) | clamp(page.int(idc("EDIT_BACKUP_3")), 1...99), "bBackUpType2_Opt2")
    }

    func changed(_ id: String, _ page: PropPage, _ values: CommonSettingsValues) {
        // 原版：ボタンのクリックとフォルダー名の変更のとき 詳細設定のファイル名を更新
        guard page.control(id) is NSButton || page.control(id) is NSPopUpButton || id == idc("EDIT_BACKUPFOLDER") else { return }
        getData(page, values)
        updateBackupFile(page, values)
    }

    func buttonPressed(_ id: String, _ page: PropPage, _ values: CommonSettingsValues, window: NSWindow?) {
        guard id == idc("BUTTON_BACKUP_FOLDER_REF") else { return }
        if let folder = CommonSettingsPages.chooseFolder(NSLocalizedString("バックアップを作成するフォルダーを選んでください", comment: "STR_PROPCOMBK_SEL_FOLDER"),
                                                         page.text(idc("EDIT_BACKUPFOLDER"))) {
            page.setText(idc("EDIT_BACKUPFOLDER"), folder)
        }
        getData(page, values)
        updateBackupFile(page, values)
    }

    /// 原版 EnableBackupInput（ShowEnable：詳細設定のときは詳細設定の項目だけ表示）
    func enable(_ page: PropPage) {
        let backup = page.isChecked(idc("CHECK_BACKUP"))
        let advanced = page.isChecked(idc("CHECK_BACKUP_ADVANCED"))
        let type1 = page.isChecked(idc("RADIO_BACKUP_TYPE1"))
        let type3 = page.isChecked(idc("RADIO_BACKUP_TYPE3"))
        let date = page.isChecked(idc("RADIO_BACKUP_DATETYPE1")) || page.isChecked(idc("RADIO_BACKUP_DATETYPE2"))
        let folder = page.isChecked(idc("CHECK_BACKUPFOLDER"))
        func show(_ id: String, _ show: Bool, _ enable: Bool) { page.showEnable(idc(id), show: show, enable: enable) }

        show("CHECK_BACKUP_ADVANCED", true, backup)
        for id in ["RADIO_BACKUP_TYPE1", "RADIO_BACKUP_TYPE3", "RADIO_BACKUP_DATETYPE1", "RADIO_BACKUP_DATETYPE2"] {
            show(id, !advanced, backup)
        }
        show("LABEL_BACKUP_3", !advanced, backup && type3)
        show("EDIT_BACKUP_3", !advanced, backup && type3)
        show("CHECK_BACKUP_RETAINEXT", !advanced, backup && (type1 || type3))
        for item in backupDateBits { page.showEnable(item.id, show: !advanced, enable: backup && date) }

        // 詳細設定
        show("EDIT_BACKUPFILE", true, backup && advanced)
        show("LABEL_BACKUP_HELP2", advanced, backup)
        show("RADIO_BACKUP_DATETYPE1A", advanced, backup)
        show("RADIO_BACKUP_DATETYPE2A", advanced, backup)

        show("CHECK_BACKUPFOLDER", true, backup)
        show("LABEL_BACKUP_4", true, backup && folder)
        show("CHECK_BACKUP_FOLDER_RM", true, backup && folder)
        show("EDIT_BACKUPFOLDER", true, backup && folder)
        show("BUTTON_BACKUP_FOLDER_REF", true, backup && folder)
        show("CHECK_BACKUP_DUSTBOX", true, backup)
        show("CHECK_BACKUPDIALOG", true, backup)
    }

    /// 原版 UpdateBackupFile：詳細設定でないとき、詳細設定のファイル名を今の設定に合わせる
    func updateBackupFile(_ page: PropPage, _ values: CommonSettingsValues) {
        var temp = ""
        if values.bool("bBackUp") {
            if values.bool("bBackUpFolder") {
                temp = ""
            } else if values.bool("bBackUpDustBox") {
                temp = NSLocalizedString("(ゴミ箱)", comment: "STR_PROPCOMBK_DUSTBOX") + "\\"
            } else {
                temp = ".\\"
            }
            switch values.int("nBackUpType") {
            case 1: temp += "$0.bak"
            case 5: temp += "$0.*.bak"
            case 3: temp += "$0.b??"
            case 6: temp += "$0.*.b??"
            case 2, 4:
                temp += "$0_"
                let opt1 = values.int("bBackUpType2_Opt1")
                for item in backupDateBits where opt1 & item.bit == item.bit { temp += item.format }
                temp += ".*"
            default:
                break
            }
        }
        if !values.bool("bBackUpPathAdvanced") {
            values.set(temp, "szBackUpPathAdvanced")
            page.setText(idc("EDIT_BACKUPFILE"), temp)
        }
    }
}

// MARK: - 書式（CPropComFormat.cpp）

struct FormatPage: CommonSettingsPageLogic {
    func setData(_ page: PropPage, _ values: CommonSettingsValues) {
        page.setText(idc("EDIT_MIDASHIKIGOU"), values.string("szMidashiKigou"))
        page.setText(idc("EDIT_INYOUKIGOU"), values.string("szInyouKigou"))
        page.setChecked(values.int("nDateFormatType") == 0 ? idc("RADIO_DFORM_0") : idc("RADIO_DFORM_1"), true)
        page.setText(idc("EDIT_DFORM"), values.string("szDateFormat"))
        page.setChecked(values.int("nTimeFormatType") == 0 ? idc("RADIO_TFORM_0") : idc("RADIO_TFORM_1"), true)
        page.setText(idc("EDIT_TFORM"), values.string("szTimeFormat"))
        updateExamples(page, values)
    }

    func getData(_ page: PropPage, _ values: CommonSettingsValues) {
        values.set(page.text(idc("EDIT_MIDASHIKIGOU")), "szMidashiKigou")
        values.set(page.text(idc("EDIT_INYOUKIGOU")), "szInyouKigou")
        values.set(page.isChecked(idc("RADIO_DFORM_0")) ? 0 : 1, "nDateFormatType")
        values.set(page.text(idc("EDIT_DFORM")), "szDateFormat")
        values.set(page.isChecked(idc("RADIO_TFORM_0")) ? 0 : 1, "nTimeFormatType")
        values.set(page.text(idc("EDIT_TFORM")), "szTimeFormat")
    }

    func enable(_ page: PropPage) {
        let date = page.isChecked(idc("RADIO_DFORM_1"))
        page.setEnabled(idc("LABEL_DFORM"), date)
        page.setEnabled(idc("EDIT_DFORM"), date)
        let time = page.isChecked(idc("RADIO_TFORM_1"))
        page.setEnabled(idc("LABEL_TFORM"), time)
        page.setEnabled(idc("EDIT_TFORM"), time)
    }

    /// 原版 ChangeDateExample、ChangeTimeExample（書式やラジオボタンが変わったとき）
    func changed(_ id: String, _ page: PropPage, _ values: CommonSettingsValues) {
        updateExamples(page, values)
    }

    func updateExamples(_ page: PropPage, _ values: CommonSettingsValues) {
        getData(page, values)
        let now = Date()
        page.setText(idc("EDIT_DFORM_EX"), WindowsDateFormat.date(now, type: values.int("nDateFormatType"), format: values.string("szDateFormat")))
        page.setText(idc("EDIT_TFORM_EX"), WindowsDateFormat.time(now, type: values.int("nTimeFormatType"), format: values.string("szTimeFormat")))
    }
}

// MARK: - 検索（CPropComGrep.cpp）

/// タグファイルの検索（原版 TagJumpMode1Arr、TagJumpMode2Arr）
private let tagJumpModes: [(value: Int, title: String)] = [
    (0, NSLocalizedString("次のファイルを検索しない", comment: "STR_TAGJUMP_0")),
    (1, NSLocalizedString("ヒットしたら次のファイルを検索しない", comment: "STR_TAGJUMP_1")),
    (2, NSLocalizedString("完全一致でヒットしたら次のファイルを検索しない", comment: "STR_TAGJUMP_2")),
    (3, NSLocalizedString("次のファイルを検索する", comment: "STR_TAGJUMP_3")),
]

struct GrepPage: CommonSettingsPageLogic {
    private let checks: [(id: String, key: String)] = [
        (idc("CHECK_bCaretTextForSearch"), "bCaretTextForSearch"),
        (idc("CHECK_INHERIT_KEY_OTHER_VIEW"), "m_bInheritKeyOtherView"),
        (idc("CHECK_bGrepExitConfirm"), "bGrepExitConfirm"),
        (idc("CHECK_GREPREALTIME"), "bGrepRealTime"),
        (idc("CHECK_GTJW_RETURN"), "bGTJW_RETURN"),
        (idc("CHECK_GTJW_LDBLCLK"), "bGTJW_LDBLCLK"),
    ]
    private var tagJumpModes1: [(value: Int, title: String)] { tagJumpModes.filter { $0.value != 2 } }

    /// 正規表現ライブラリ（Mac 版は bregonig を組み込み。DLL は使えない。偏离项 9）
    var unavailable: Set<String> { [idc("EDIT_REGEXPLIB"), idc("LABEL_REGEXP")] }

    func setData(_ page: PropPage, _ values: CommonSettingsValues) {
        page.loadChecks(checks, values)
        page.setText(idc("EDIT_REGEXPLIB"), values.string("szRegexpLib"))
        page.setText(idc("LABEL_REGEXP_VER"), NSLocalizedString("組み込みの bregonig (Onigmo) を使用します", comment: "共通設定 > 検索 > 正規表現ライブラリ（Mac 版）"))
        page.loadCombo(idc("COMBO_TAGJUMP"), tagJumpModes1, value: values.int("nTagJumpMode"))
        page.loadCombo(idc("COMBO_KEYWORD_TAGJUMP"), tagJumpModes, value: values.int("nTagJumpModeKeyword"))
    }

    func getData(_ page: PropPage, _ values: CommonSettingsValues) {
        page.storeChecks(checks, values)
        values.set(page.comboValue(idc("COMBO_TAGJUMP"), tagJumpModes1), "nTagJumpMode")
        values.set(page.comboValue(idc("COMBO_KEYWORD_TAGJUMP"), tagJumpModes), "nTagJumpModeKeyword")
    }
}

// MARK: - 支援（CPropComHelper.cpp）

struct HelperPage: CommonSettingsPageLogic {
    private let checks: [(id: String, key: String)] = [
        (idc("CHECK_m_bHokanKey_RETURN"), "bHokanKey_RETURN"),
        (idc("CHECK_m_bHokanKey_TAB"), "bHokanKey_TAB"),
        (idc("CHECK_m_bHokanKey_RIGHT"), "bHokanKey_RIGHT"),
        (idc("CHECK_HTMLHELPISSINGLE"), "bHtmlHelpIsSingle"),
    ]

    /// 外部ヘルプ・外部 HTML ヘルプ（Windows のヘルプ）、migemo の DLL（Mac 版は組み込み。偏离项 9）。
    /// migemo の辞書は第 44 步（MIGEMO インクリメンタルサーチ）から使う：辞書は GPL なので附带せず、ユーザーが指定する
    var unavailable: Set<String> {
        Set(["EDIT_EXTHELP1", "BUTTON_OPENHELP1", "EDIT_EXTHTMLHELP", "BUTTON_OPENEXTHTMLHELP", "CHECK_HTMLHELPISSINGLE",
             "EDIT_MIGEMO_DLL", "BUTTON_OPENMDLL"].map(idc))
            .union(["DLL(M)"])
    }
    /// キーワードヘルプのフォント（sakura.ini の khlf、khps、khlfFaceName）
    static let font = LogFontSetting(lf: "khlf", pointSize: "khps", faceName: "khlfFaceName")

    func setData(_ page: PropPage, _ values: CommonSettingsValues) {
        page.loadChecks(checks, values)
        Self.font.setLabel(page, idc("STATIC_KEYWORDHELPFONT"), values)
        page.setText(idc("EDIT_EXTHELP1"), values.string("szExtHelp"))
        page.setText(idc("EDIT_EXTHTMLHELP"), values.string("szExtHtmlHelp"))
        page.setText(idc("EDIT_MIGEMO_DLL"), values.string("szMigemoDll"))
        page.setText(idc("EDIT_MIGEMO_DICT"), values.string("szMigemoDict"))
    }

    func getData(_ page: PropPage, _ values: CommonSettingsValues) {
        page.storeChecks(checks, values)
        values.set(page.text(idc("EDIT_MIGEMO_DICT")), "szMigemoDict")
    }

    func buttonPressed(_ id: String, _ page: PropPage, _ values: CommonSettingsValues, window: NSWindow?) {
        if id == idc("BUTTON_KEYWORDHELPFONT") {
            Self.font.choose(page, idc("STATIC_KEYWORDHELPFONT"), values, window: window)
        }
        if id == idc("BUTTON_OPENMDICT") {
            // 原版 IDC_BUTTON_OPENMDICT：相対パスは設定ファイルから。選んだフォルダーは可能なら相対パスにする（GetRelPath）。
            // 沙盒：選んだフォルダーは許可として覚える（Grep と同じ FolderAccess）
            let iniFolder = (EditorCore.settingsFilePath as NSString).deletingLastPathComponent
            let current = page.text(idc("EDIT_MIGEMO_DICT"))
            let initial = current.isEmpty || current.hasPrefix("/") ? current : (iniFolder as NSString).appendingPathComponent(current)
            if let folder = CommonSettingsPages.chooseFolder(NSLocalizedString("検索するフォルダーを選んでください", comment: "STR_PROPCOMHELP_MIGEMODIR"), initial) {
                FolderAccess.shared.remember(URL(fileURLWithPath: folder, isDirectory: true))
                let normalized = FolderAccess.normalized(folder)
                let relative = FolderAccess.contains(iniFolder, normalized) && normalized != FolderAccess.normalized(iniFolder)
                    ? String(normalized.dropFirst(FolderAccess.normalized(iniFolder).count + 1)) : normalized
                page.setText(idc("EDIT_MIGEMO_DICT"), relative)
            }
        }
    }
}

// MARK: - フォント（CPropCommon::SetFontLabel、MySelectFont）

/// sakura.ini のフォントの設定（原版 ShareData_IO_LogFont：LOGFONT の 13 個の数、ポイントサイズ（1/10 pt）、フォント名）
struct LogFontSetting {
    let lf: String
    let pointSize: String
    let faceName: String

    /// LOGFONT の数（lfHeight, lfWidth, lfEscapement, lfOrientation, lfWeight, lfItalic, lfUnderline, lfStrikeOut,
    /// lfCharSet, lfOutPrecision, lfClipPrecision, lfQuality, lfPitchAndFamily）
    func ints(_ values: CommonSettingsValues) -> [Int] {
        let ints = values.string(lf).split(separator: ",").map { Int($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
        return ints.count == 13 ? ints : [0, 0, 0, 0, 400, 0, 0, 0, 1, 0, 0, 0, 0]
    }

    /// 表示する文字（原版 SetFontLabel：「名前(9pt)」、小数があれば「名前(9.5pt)」）
    static func labelText(face: String, pointSize: Int) -> String {
        let points = Double(pointSize) / 10
        return pointSize % 10 != 0 ? String(format: "%@(%.1fpt)", face, points) : String(format: "%@(%.0fpt)", face, points)
    }

    /// 設定のフォント。そのフォントがなければシステムのフォント
    static func font(face: String, pointSize: Int, bold: Bool, italic: Bool) -> NSFont {
        let size = max(1, CGFloat(pointSize) / 10)
        var traits: NSFontTraitMask = []
        if bold { traits.insert(.boldFontMask) }
        if italic { traits.insert(.italicFontMask) }
        if let font = NSFontManager.shared.font(withFamily: face, traits: traits, weight: 5, size: size) {
            return font
        }
        if let font = NSFont(name: face, size: size) { return font }
        return NSFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
    }

    func font(_ values: CommonSettingsValues) -> NSFont {
        let lfInts = ints(values)
        return Self.font(face: values.string(faceName), pointSize: values.int(pointSize), bold: lfInts[4] >= 600, italic: lfInts[5] != 0)
    }

    /// ラベルにフォント名とサイズを、そのフォントで表示する（大きすぎるフォントは小さく表示）
    func setLabel(_ page: PropPage, _ id: String, _ values: CommonSettingsValues) {
        page.setText(id, Self.labelText(face: values.string(faceName), pointSize: values.int(pointSize)))
        guard let label = page.control(id) as? NSTextField else { return }
        let labelFont = self.font(values)
        let limit = min(16, max(PropPage.font.pointSize, label.frame.height - 4))
        label.font = labelFont.pointSize > limit ? NSFontManager.shared.convert(labelFont, toSize: limit) : labelFont
    }

    /// 「フォント」ボタン：フォントを選んで設定する（原版 MySelectFont のあと m_lf、m_nPointSize を変更）
    func choose(_ page: PropPage, _ labelID: String, _ values: CommonSettingsValues, window: NSWindow?) {
        guard let chosen = CommonSettingsPages.chooseFont(font(values), window) else { return }
        set(chosen, values)
        setLabel(page, labelID, values)
    }

    /// フォント → 設定の値。LOGFONT の高さ・太さ・斜体を変え、ほかの数はそのまま
    func set(_ font: NSFont, _ values: CommonSettingsValues) {
        let size = Int((font.pointSize * 10).rounded())
        let traits = NSFontManager.shared.traits(of: font)
        var lfInts = ints(values)
        lfInts[0] = -Int((Double(size) * 96 / 720).rounded())	// 原版 DpiPointsToPixels（96 DPI）
        lfInts[4] = traits.contains(.boldFontMask) ? 700 : 400	// FW_BOLD、FW_NORMAL
        lfInts[5] = traits.contains(.italicFontMask) ? 1 : 0
        values.set(lfInts.map(String.init).joined(separator: ","), lf)
        values.set(size, pointSize)
        values.set(font.familyName ?? font.fontName, faceName)
    }
}

/// 字体面板（原版の ChooseFont ダイアログの代わり）。OK・キャンセルのボタンを付けて、閉じるまで待つ
final class FontPicker: NSObject {
    private var font: NSFont

    private init(font: NSFont) {
        self.font = font
    }

    static func choose(_ font: NSFont, window: NSWindow?) -> NSFont? {
        FontPicker(font: font).run()
    }

    private func run() -> NSFont? {
        let manager = NSFontManager.shared
        let panel = manager.fontPanel(true)!
        let oldTarget = manager.target
        manager.target = self
        manager.setSelectedFont(font, isMultiple: false)

        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 40))
        let ok = NSButton(title: "OK", target: self, action: #selector(okClicked(_:)))
        ok.keyEquivalent = "\r"
        ok.frame = NSRect(x: 120, y: 6, width: 90, height: 28)
        let cancel = NSButton(title: NSLocalizedString("キャンセル", comment: "フォントの選択"), target: self, action: #selector(cancelClicked(_:)))
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
        panel.orderOut(nil)
        manager.target = oldTarget
        return response == .OK ? font : nil
    }

    /// 字体面板で選んだ（NSFontManager が target に送る）
    @objc func changeFont(_ sender: Any?) {
        font = NSFontManager.shared.convert(font)
    }

    @objc private func okClicked(_ sender: Any?) {
        NSApp.stopModal(withCode: .OK)
    }

    @objc private func cancelClicked(_ sender: Any?) {
        NSApp.stopModal(withCode: .cancel)
    }
}

// MARK: - マクロ（CPropComMacro.cpp。第 45 步）

/// 共通設定『マクロ』：登録マクロの一覧（番号、マクロ名、ファイル名、実行時に読み込み、自動実行）、マクロ用フォルダー、キャンセル確認待ち時間。
/// 一覧は原版と同じく 50 行いつも表示し、下の「名前」「File」「Id」で選んで［設定］で一覧に入れる。OK で [Macro] の Name[000]・File[000]・
/// ReloadWhenExecute[000]・nMacroOnOpened 等と [Folders] の szMACROFOLDER に書く。Python フォルダーは Mac 版にない（Python マクロは使えない）
final class MacroPage: CommonSettingsPageLogic {
    private let list = idc("MACROLIST")
    private let idCombo = idc("COMBO_MACROID")
    /// 前回選択していた行（原版 nLastPos_Macro）
    private var lastPosition = -1

    var unavailable: Set<String> { [idc("PYTHONDIR"), idc("PYTHONDIRREF")] }
    var ranges: [String: ClosedRange<Int>] { [idc("MACROCANCELTIMER"): 0...9999] }

    func setData(_ page: PropPage, _ values: CommonSettingsValues) {
        guard let listView = page.list(list) else { return }
        if listView.table.tableColumns.count < 5, let scroll = page.control(list) {
            // 原版 InitDialog：幅は 40:200:150:40:40 の割合。Mac 版は列の間隔とスクロールバーを引いた幅に全部の列が入るように（自動実行の列が隠れない）
            let spacing = listView.table.intercellSpacing.width * 5
            let width = scroll.frame.width - NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy) - spacing - 4
            listView.setColumns([NSLocalizedString("番号", comment: "STR_PROPCOMMACR_LIST1"),
                                 NSLocalizedString("マクロ名", comment: "STR_PROPCOMMACR_LIST2"),
                                 NSLocalizedString("ファイル名", comment: "STR_PROPCOMMACR_LIST3"),
                                 NSLocalizedString("実行時に読み込み", comment: "STR_PROPCOMMACR_LIST4"),
                                 NSLocalizedString("自動実行", comment: "STR_PROPCOMMACR_LIST5")],
                                widths: [40, 200, 150, 40, 40].map { (CGFloat($0) * width / 470).rounded(.down) })
        }
        let opened = values.int("nMacroOnOpened", section: "Macro")
        let typeChanged = values.int("nMacroOnTypeChanged", section: "Macro")
        let onSave = values.int("nMacroOnSave", section: "Macro")
        var rows: [[String]] = []
        for i in 0..<MacroCommands.maxCount {
            var auto = ""
            if i == opened { auto += "O" }
            if i == typeChanged { auto += "T" }
            if i == onSave { auto += "S" }
            rows.append([String(i), values.string(MacroCommands.key("Name", i), section: "Macro"),
                         values.string(MacroCommands.key("File", i), section: "Macro"),
                         values.bool(MacroCommands.key("ReloadWhenExecute", i), section: "Macro") ? "on" : "off", auto])
        }
        listView.setRows(rows)
        page.setItems(idCombo, (0..<MacroCommands.maxCount).map { String($0) }, selected: 0)
        page.setText(idc("MACRODIR"), values.string("szMACROFOLDER", section: "Folders"))
        page.setInt(idc("MACROCANCELTIMER"), values.int("nMacroCancelTimer", section: "Macro"))
        lastPosition = -1
        fillFiles(page)
    }

    func getData(_ page: PropPage, _ values: CommonSettingsValues) {
        guard let rows = page.list(list)?.rows else { return }
        var opened = -1, typeChanged = -1, onSave = -1
        for (i, row) in rows.enumerated() where i < MacroCommands.maxCount {
            values.set(row[1], MacroCommands.key("Name", i), section: "Macro")
            values.set(row[2], MacroCommands.key("File", i), section: "Macro")
            values.set(row[3] == "on", MacroCommands.key("ReloadWhenExecute", i), section: "Macro")
            if row[4].contains("O") { opened = i }
            if row[4].contains("T") { typeChanged = i }
            if row[4].contains("S") { onSave = i }
        }
        values.set(opened, "nMacroOnOpened", section: "Macro")
        values.set(typeChanged, "nMacroOnTypeChanged", section: "Macro")
        values.set(onSave, "nMacroOnSave", section: "Macro")
        // マクロフォルダーの最後に区切りがなければ付ける（原版 AddLastChar '\\'）
        var folder = page.text(idc("MACRODIR"))
        if !folder.isEmpty && !folder.hasSuffix("/") { folder += "/" }
        values.set(folder, "szMACROFOLDER", section: "Folders")
        values.set(Int(MacroHost.wtoi(page.text(idc("MACROCANCELTIMER")))), "nMacroCancelTimer", section: "Macro")
    }

    func changed(_ id: String, _ page: PropPage, _ values: CommonSettingsValues) {
        switch id {
        case list: selectionChanged(page)	// 原版 CheckListPosition_Macro
        case idc("MACRODIR"): fillFiles(page)
        default: break
        }
    }

    func buttonPressed(_ id: String, _ page: PropPage, _ values: CommonSettingsValues, window: NSWindow?) {
        switch id {
        case idc("MACRODIRREF"):	// マクロディレクトリ参照（原版 SelectBaseDir_Macro）
            let current = page.text(idc("MACRODIR"))
            let initial = current.hasPrefix("/") ? current
                : ((EditorCore.settingsFilePath as NSString).deletingLastPathComponent as NSString).appendingPathComponent(current)
            if let folder = CommonSettingsPages.chooseFolder(NSLocalizedString("Macroディレクトリの選択", comment: "STR_PROPCOMMACR_SEL_DIR"), initial) {
                page.setText(idc("MACRODIR"), folder.hasSuffix("/") ? folder : folder + "/")
                FolderAccess.shared.remember(URL(fileURLWithPath: folder, isDirectory: true))	// 沙盒：一覧を読めるように
                fillFiles(page)
            }
        case idc("MACRO_REG"):	// 設定（原版 SetMacro2List_Macro）
            setMacro(page)
        default:
            break
        }
    }

    /// 一覧の行を選んだ：下の入力欄へ（原版 CheckListPosition_Macro）
    private func selectionChanged(_ page: PropPage) {
        guard let listView = page.list(list) else { return }
        let current = listView.selectedRow
        guard current != -1, current != lastPosition else { return }
        lastPosition = current
        let row = listView.rows[current]
        page.select(idCombo, current)
        page.setText(idc("MACRONAME"), row[1])
        page.setText(idc("MACROPATH"), row[2])
        page.setChecked(idc("CHECK_RELOADWHENEXECUTE"), row[3] == "on")
        page.setChecked(idc("CHECK_MacroOnOpened"), row[4].contains("O"))
        page.setChecked(idc("CHECK_MacroOnTypeChanged"), row[4].contains("T"))
        page.setChecked(idc("CHECK_MacroOnSave"), row[4].contains("S"))
    }

    /// 下の入力欄を Id の行に入れる。自動実行は一つのマクロだけ（原版 SetMacro2List_Macro）
    private func setMacro(_ page: PropPage) {
        guard let listView = page.list(list) else { return }
        let index = page.selectedIndex(idCombo)
        var rows = listView.rows
        guard rows.indices.contains(index) else { return }
        rows[index][1] = String(page.text(idc("MACRONAME")).prefix(63))	// MACRONAME_MAX - 1
        rows[index][2] = page.text(idc("MACROPATH"))
        rows[index][3] = page.isChecked(idc("CHECK_RELOADWHENEXECUTE")) ? "on" : "off"
        func owner(_ c: Character) -> Int { rows.firstIndex { $0[4].contains(c) } ?? -1 }
        var opened = owner("O"), typeChanged = owner("T"), onSave = owner("S")
        func update(_ value: inout Int, _ id: String) {
            if page.isChecked(idc(id)) { value = index } else if value == index { value = -1 }
        }
        update(&opened, "CHECK_MacroOnOpened")
        update(&typeChanged, "CHECK_MacroOnTypeChanged")
        update(&onSave, "CHECK_MacroOnSave")
        for i in rows.indices {
            var auto = ""
            if i == opened { auto += "O" }
            if i == typeChanged { auto += "T" }
            if i == onSave { auto += "S" }
            rows[i][4] = auto
        }
        let selected = listView.selectedRow
        listView.setRows(rows)
        if selected != -1 { listView.select(selected) }
    }

    /// File の候補：マクロフォルダーのファイル（原版 OnFileDropdown_Macro。フォルダーは除く）
    private func fillFiles(_ page: PropPage) {
        var folder = page.text(idc("MACRODIR"))
        if !folder.hasPrefix("/") {
            folder = ((EditorCore.settingsFilePath as NSString).deletingLastPathComponent as NSString).appendingPathComponent(folder)
        }
        FolderAccess.shared.startAccess(path: folder)
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []).filter { name in
            var isDir: ObjCBool = false
            return !name.hasPrefix(".") && FileManager.default.fileExists(atPath: (folder as NSString).appendingPathComponent(name), isDirectory: &isDir) && !isDir.boolValue
        }.sorted()	// CBS_SORT
        page.setItems(idc("MACROPATH"), names, selected: -1)
    }
}

// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge

/// 共通設定窗口的各页（计划第 39 步）：原版 CPropCom*.cpp 的 SetData / GetData / Enable…Input 的移植。
///
/// 值是 sakura.ini 的「节/项目」（原版 CShareData_IO 的名字）。GetData 里的范围限制也照原版。
/// 这一步移植的页：全般、ウィンドウ、タブバー、ステータスバー、編集、ファイル、ファイル名表示（置換リスト以外）、
/// バックアップ、書式、検索、支援。
/// 以后的步骤：メインメニュー・ツールバー・キー割り当て・カスタムメニュー（第 41 步）、強調キーワード（第 40 步）、
/// マクロ（第 45 步）。プラグイン 是 DLL，Mac 版没有（偏离项 9）。
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
}

extension CommonSettingsPageLogic {
    var ranges: [String: ClosedRange<Int>] { [:] }
    var unavailable: Set<String> { [] }
    var notYet: Set<String> { [] }
    func enable(_ page: PropPage) {}
    func changed(_ id: String, _ page: PropPage, _ values: CommonSettingsValues) {}
    func buttonPressed(_ id: String, _ page: PropPage, _ values: CommonSettingsValues, window: NSWindow?) {}
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

    fileprivate static var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "サクラエディタ"
    }
}

// MARK: - 共通的函数

private func clamp(_ value: Int, _ range: ClosedRange<Int>) -> Int {
    min(max(value, range.lowerBound), range.upperBound)
}

extension PropPage {
    /// 复选框 ← bool 项目
    func loadChecks(_ pairs: [(id: String, key: String)], _ values: CommonSettingsValues, section: String = "Common") {
        for (id, key) in pairs { setChecked(id, values.bool(key, section: section)) }
    }

    /// 复选框 → bool 项目（Mac 版不能用的不改）
    func storeChecks(_ pairs: [(id: String, key: String)], _ values: CommonSettingsValues, section: String = "Common") {
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
private func idc(_ name: String) -> String { "IDC_" + name }

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
    /// 位置と大きさの設定（原版 CDlgWinSize）
    var notYet: Set<String> { [idc("BUTTON_WINSIZE")] }

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

    /// フォント（字体对话框在下一个 PR）
    var notYet: Set<String> { [idc("BUTTON_TABFONT")] }

    func setData(_ page: PropPage, _ values: CommonSettingsValues) {
        page.loadChecks(checks, values)
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

struct FileNamePage: CommonSettingsPageLogic {
    /// ファイル名の置換リスト（一覧の編集は次の PR）
    var notYet: Set<String> {
        Set(["LIST_FNAME", "EDIT_FNAME_FROM", "EDIT_FNAME_TO", "BUTTON_FNAME_INS", "BUTTON_FNAME_ADD", "BUTTON_FNAME_UPD",
             "BUTTON_FNAME_DEL", "BUTTON_FNAME_TOP", "BUTTON_FNAME_UP", "BUTTON_FNAME_DOWN", "BUTTON_FNAME_LAST"].map(idc))
            .union(["置換前(F)", "置換後(R)"])
    }

    func setData(_ page: PropPage, _ values: CommonSettingsValues) {
        page.setChecked(idc("CHECK_SHORTPATH"), values.bool("bShortPath", section: "Nickname"))
        page.setInt(idc("EDIT_SHORTMAXWIDTH"), values.int("nShortPathMaxWidth", section: "Nickname"))
    }

    func getData(_ page: PropPage, _ values: CommonSettingsValues) {
        values.set(page.isChecked(idc("CHECK_SHORTPATH")), "bShortPath", section: "Nickname")
        values.set(page.int(idc("EDIT_SHORTMAXWIDTH")), "nShortPathMaxWidth", section: "Nickname")
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

    /// 外部ヘルプ・外部 HTML ヘルプ（Windows のヘルプ）、migemo の DLL と辞書（Mac 版は組み込み。偏离项 9）
    var unavailable: Set<String> {
        Set(["EDIT_EXTHELP1", "BUTTON_OPENHELP1", "EDIT_EXTHTMLHELP", "BUTTON_OPENEXTHTMLHELP", "CHECK_HTMLHELPISSINGLE",
             "EDIT_MIGEMO_DLL", "BUTTON_OPENMDLL", "EDIT_MIGEMO_DICT", "BUTTON_OPENMDICT"].map(idc))
            .union(["DLL(M)", "辞書(I)"])
    }
    /// キーワードヘルプのフォント（字体对话框在下一个 PR）
    var notYet: Set<String> { [idc("BUTTON_KEYWORDHELPFONT")] }

    func setData(_ page: PropPage, _ values: CommonSettingsValues) {
        page.loadChecks(checks, values)
        page.setText(idc("EDIT_EXTHELP1"), values.string("szExtHelp"))
        page.setText(idc("EDIT_EXTHTMLHELP"), values.string("szExtHtmlHelp"))
        page.setText(idc("EDIT_MIGEMO_DLL"), values.string("szMigemoDll"))
        page.setText(idc("EDIT_MIGEMO_DICT"), values.string("szMigemoDict"))
    }

    func getData(_ page: PropPage, _ values: CommonSettingsValues) {
        page.storeChecks(checks, values)
    }
}

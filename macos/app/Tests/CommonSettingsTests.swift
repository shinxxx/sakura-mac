// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge
import XCTest

/// 共通設定窗口（计划第 39 步）。
///
/// - 页和控件与原版的对话框模板（IDD_PROP_*）相同
/// - 各页的 SetData / GetData / Enable…Input 与原版相同：值、范围限制、联动、bit 的组合（バックアップ）
/// - OK 时只写回改过的项并保存，キャンセル 什么也不改；Mac 版不能用的项目变灰
/// 值的读写大多用假的设置（FakeStore：没写过的项从核心库读），不改测试进程的设置。
final class CommonSettingsTests: XCTestCase {
    /// 假的设置：写的值留在这里
    final class FakeStore: CommonSettingsStore {
        var values: [String: String] = [:]
        var writes: [String] = []
        var saveCount = 0

        func value(section: String, key: String) -> String? {
            values["\(section)/\(key)"] ?? EditorCore.commonSetting(section: section, key: key)
        }

        func setValue(_ value: String, section: String, key: String) -> Bool {
            values["\(section)/\(key)"] = value
            writes.append("\(section)/\(key)")
            return true
        }

        func save() -> Bool {
            saveCount += 1
            return true
        }
    }

    private var store: FakeStore!

    override func setUp() {
        _ = TestCore.home
        _ = NSApplication.shared
        store = FakeStore()
    }

    private func open(_ pageName: String) throws -> (CommonSettingsWindowController, PropPage) {
        let probe = try XCTUnwrap(CommonSettingsWindowController(store: store))
        let index = try XCTUnwrap(probe.pageIndex(named: pageName))
        probe.cancel(nil)
        let controller = try XCTUnwrap(CommonSettingsWindowController(store: store, page: index))
        return (controller, controller.page(index))
    }

    /// 用户点了这个控件（复选框、单选按钮）
    private func click(_ page: PropPage, _ id: String, _ on: Bool = true) {
        page.setChecked(id, on)
        page.onChange?(id)
    }

    /// 用户在数值框、文字框里输入了
    private func type(_ page: PropPage, _ id: String, _ text: String) {
        page.setText(id, text)
        page.onChange?(id)
    }

    // MARK: - 布局

    func testPagesAndControlsMatchOriginalDialogs() throws {
        let controller = try XCTUnwrap(CommonSettingsWindowController(store: store))
        defer { controller.cancel(nil) }
        // 页的顺序与原版 CPropCommon（ID_PROPCOM_PAGENUM_*）相同
        XCTAssertEqual((0..<controller.pageCount).map(controller.pageName), [
            "全般", "ウィンドウ", "メインメニュー", "ツールバー", "タブバー", "ステータスバー", "編集", "ファイル",
            "ファイル名表示", "バックアップ", "書式", "検索", "キー割り当て", "カスタムメニュー", "強調キーワード",
            "支援", "マクロ", "プラグイン",
        ])
        for index in 0..<controller.pageCount {
            let definition = controller.dialogs.pages[index]
            let page = controller.page(index)
            // 对话框的大小按对话框单位换算（原版 293×240）
            XCTAssertEqual(page.view.frame.size, NSSize(width: PropPage.points(definition.size[0]), height: PropPage.points(definition.size[1])))
            // 有 ID 的控件都在，文字与原版相同
            for control in definition.controls where control.id != "IDC_STATIC" && control.kind != "icon" {
                let view = try XCTUnwrap(page.control(control.id), "\(definition.name) \(control.id)")
                if control.kind == "check" || control.kind == "radio" {
                    XCTAssertEqual((view as? NSButton)?.title, control.text, "\(definition.name) \(control.id)")
                }
            }
        }
        let general = controller.page(0)
        XCTAssertEqual((general.control("IDC_CHECK_FREECARET") as? NSButton)?.title, "フリーカーソル(F)")
        XCTAssertEqual(general.control("IDC_CHECK_FREECARET")?.frame,
                       NSRect(x: PropPage.points(8), y: PropPage.points(16), width: PropPage.points(120), height: PropPage.points(10)))
    }

    /// 設定 > 共通設定 的各功能打开那一页（原版 F_OPTION_*）
    func testCommandOpensItsPage() throws {
        for (code, name) in [(32000, "全般"), (32004, "バックアップ"), (32015, "タブバー"), (32016, "ステータスバー"),
                             (32014, "ファイル名表示"), (32018, "メインメニュー"), (32012, "支援")] {
            let page = try XCTUnwrap(CommonSettingsWindowController.pageOfCommand[code])
            let controller = try XCTUnwrap(CommonSettingsWindowController(store: store, page: page))
            XCTAssertEqual(controller.pageName(controller.currentIndex), name, "\(code)")
            controller.cancel(nil)
        }
        XCTAssertEqual(CommandTable.selector(for: 31112), #selector(NSApplication.showCommonSettings(_:)))
        XCTAssertEqual(CommandTable.selector(for: 32004), #selector(NSApplication.showCommonSettings(_:)))
    }

    // MARK: - OK / キャンセル

    func testOKWritesChangedItemsAndSaves() throws {
        store.values["Common/bIsFreeCursorMode"] = "0"
        store.values["Common/bExitConfirm"] = "1"
        let (controller, page) = try open("全般")
        XCTAssertFalse(page.isChecked("IDC_CHECK_FREECARET"))
        XCTAssertTrue(page.isChecked("IDC_CHECK_EXITCONFIRM"))
        click(page, "IDC_CHECK_FREECARET")
        controller.ok(nil)
        XCTAssertEqual(store.values["Common/bIsFreeCursorMode"], "1")
        XCTAssertEqual(store.writes, ["Common/bIsFreeCursorMode"], "改过的项才写")
        XCTAssertEqual(store.saveCount, 1)
    }

    func testOKWithoutChangesWritesNothing() throws {
        let (controller, _) = try open("全般")
        controller.ok(nil)
        XCTAssertEqual(store.writes, [])
        XCTAssertEqual(store.saveCount, 0)
    }

    func testCancelChangesNothing() throws {
        store.values["Common/bIsFreeCursorMode"] = "0"
        let (controller, page) = try open("全般")
        click(page, "IDC_CHECK_FREECARET")
        controller.cancel(nil)
        XCTAssertEqual(store.values["Common/bIsFreeCursorMode"], "0")
        XCTAssertEqual(store.writes, [])
        XCTAssertEqual(store.saveCount, 0)
    }

    /// 换页时取页的值（原版 PSN_KILLACTIVE），看过的页都写回
    func testValuesOfVisitedPagesAreKept() throws {
        store.values["Common/bIsFreeCursorMode"] = "0"
        store.values["Common/bAddCRLFWhenCopy"] = "0"
        let (controller, general) = try open("全般")
        click(general, "IDC_CHECK_FREECARET")
        let editIndex = try XCTUnwrap(controller.pageIndex(named: "編集"))
        controller.showPage(editIndex)
        click(controller.page(editIndex), "IDC_CHECK_ADDCRLFWHENCOPY")
        controller.ok(nil)
        XCTAssertEqual(store.values["Common/bIsFreeCursorMode"], "1")
        XCTAssertEqual(store.values["Common/bAddCRLFWhenCopy"], "1")
    }

    /// 真的核心库：OK 以后核心库的设置变了，编辑画面收到通知
    func testOKAppliesToCore() throws {
        let original = try XCTUnwrap(EditorCore.commonSetting(section: "Common", key: "bExitConfirm"))
        defer { XCTAssertTrue(EditorCore.setCommonSetting(original, section: "Common", key: "bExitConfirm")) }
        let controller = try XCTUnwrap(CommonSettingsWindowController(store: CoreCommonSettingsStore(), page: 0))
        let page = controller.page(0)
        click(page, "IDC_CHECK_EXITCONFIRM", original == "0")
        let notified = expectation(forNotification: EditorTextView.commonSettingsDidChangeNotification, object: nil)
        controller.ok(nil)
        wait(for: [notified], timeout: 1)
        XCTAssertEqual(EditorCore.commonSetting(section: "Common", key: "bExitConfirm"), original == "0" ? "1" : "0")
    }

    // MARK: - 各页

    /// 全般：范围限制（原版 GetData）、组合框的值、カーソル形状
    func testGeneralPage() throws {
        store.values["Common/nPageScrollByWheel"] = "17"	// VK_CONTROL
        store.values["Common/nCaretType"] = "1"
        let (controller, page) = try open("全般")
        XCTAssertTrue(page.isChecked("IDC_RADIO_CARETTYPE1"))
        XCTAssertFalse(page.isChecked("IDC_RADIO_CARETTYPE0"))
        XCTAssertEqual(page.selectedIndex("IDC_COMBO_WHEEL_PAGESCROLL"), 4)	// CONTROLキー
        let popup = try XCTUnwrap(page.control("IDC_COMBO_WHEEL_HSCROLL") as? NSPopUpButton)
        XCTAssertEqual(popup.itemTitles, ["組み合わせなし", "マウス中ボタン", "マウスサイドボタン1", "マウスサイドボタン2", "CONTROLキー", "SHIFTキー"])
        click(page, "IDC_RADIO_CARETTYPE0")
        XCTAssertFalse(page.isChecked("IDC_RADIO_CARETTYPE1"), "同じグループのラジオボタン")
        type(page, "IDC_EDIT_REPEATEDSCROLLLINENUM", "99")
        type(page, "IDC_EDIT_MAX_MRU_FILE", "abc")
        page.select("IDC_COMBO_WHEEL_HSCROLL", 5)
        controller.ok(nil)
        XCTAssertEqual(store.values["Common/nCaretType"], "0")
        XCTAssertEqual(store.values["Common/nRepeatedScrollLineNum"], "10")
        XCTAssertEqual(store.values["Common/nMRUArrNum_MAX"], "0")
        XCTAssertEqual(store.values["Common/nHorizontalScrollByWheel"], "16")	// VK_SHIFT
    }

    /// Mac 版做不到的项目变灰，值不改
    func testUnavailableItemsAreDisabled() throws {
        store.values["Common/bTaskTrayUse"] = "1"
        let (controller, general) = try open("全般")
        for id in ["IDC_CHECK_USETRAYICON", "IDC_CHECK_STAYTASKTRAY", "IDC_HOTKEY_TRAYMENU", "IDC_CHECK_MEMDC"] {
            XCTAssertFalse(general.isEnabled(id), id)
        }
        XCTAssertTrue(general.isEnabled("IDC_CHECK_FREECARET"))
        general.setChecked("IDC_CHECK_USETRAYICON", false)	// 变灰的也不写
        controller.ok(nil)
        XCTAssertFalse(store.writes.contains("Common/bTaskTrayUse"))

        let (helperController, helper) = try open("支援")
        defer { helperController.cancel(nil) }
        XCTAssertFalse(helper.isEnabled("IDC_EDIT_EXTHELP1"))
        XCTAssertFalse(helper.isEnabled("IDC_EDIT_MIGEMO_DLL"))
        XCTAssertTrue(helper.isEnabled("IDC_CHECK_m_bHokanKey_TAB"))

        // 以后的步骤的页：全部变灰，下边有说明
        let (keyController, keybind) = try open("キー割り当て")
        defer { keyController.cancel(nil) }
        for control in keybind.definition.controls where control.id != "IDC_STATIC" && control.kind != "icon" && control.kind != "group" {
            XCTAssertFalse(keybind.isEnabled(control.id), control.id)
        }
    }

    /// ウィンドウ：ファンクションキー表示 のときだけ 位置、グループボタン数
    func testWindowPage() throws {
        store.values["Common/bDispFUNCKEYWND"] = "0"
        store.values["Common/nFUNCKEYWND_Place"] = "1"
        let (controller, page) = try open("ウィンドウ")
        XCTAssertTrue(page.isChecked("IDC_RADIO_FUNCKEYWND_PLACE2"))
        XCTAssertFalse(page.isEnabled("IDC_EDIT_FUNCKEYWND_GROUPNUM"))
        XCTAssertFalse(page.isEnabled("IDC_RADIO_FUNCKEYWND_PLACE1"))
        click(page, "IDC_CHECK_DispFUNCKEYWND")
        XCTAssertTrue(page.isEnabled("IDC_EDIT_FUNCKEYWND_GROUPNUM"))
        XCTAssertTrue(page.isEnabled("IDC_RADIO_FUNCKEYWND_PLACE1"))
        type(page, "IDC_EDIT_FUNCKEYWND_GROUPNUM", "0")
        type(page, "IDC_EDIT_nRulerHeight", "1")
        type(page, "IDC_WINCAPTION_ACTIVE", "${w?$h$:アウトプット$:${I?$f$n$:$N$n$}$}${U?(更新)$}")
        controller.ok(nil)
        XCTAssertEqual(store.values["Common/bDispFUNCKEYWND"], "1")
        XCTAssertEqual(store.values["Common/nFUNCKEYWND_GroupNum"], "1")
        XCTAssertEqual(store.values["Common/nRulerHeight"], "2")	// IDC_SPIN_nRulerHeight_MIN
        XCTAssertEqual(store.values["Common/szWinCaptionActive"], "${w?$h$:アウトプット$:${I?$f$n$:$N$n$}$}${U?(更新)$}")
    }

    /// タブバー：「グループ化する」は m_bDispTabWndMultiWin の反対。タブバーを表示する のときだけ他の項目
    func testTabPage() throws {
        store.values["Common/bDispTabWnd"] = "0"
        store.values["Common/bDispTabWndMultiWin"] = "1"
        store.values["Common/bDispTabClose"] = "2"
        let (controller, page) = try open("タブバー")
        XCTAssertFalse(page.isChecked("IDC_CHECK_DispTabWndMultiWin"))
        XCTAssertEqual(page.selectedIndex("IDC_CHECK_DispTabClose"), 2)
        XCTAssertFalse(page.isEnabled("IDC_CHECK_DispTabWndMultiWin"))
        XCTAssertFalse(page.isEnabled("IDC_COMBO_TAB_POSITION"))
        XCTAssertFalse(page.isEnabled("IDC_CHECK_RetainEmptyWindow"))
        click(page, "IDC_CHECK_DispTabWnd")
        XCTAssertTrue(page.isEnabled("IDC_CHECK_DispTabWndMultiWin"))
        XCTAssertTrue(page.isEnabled("IDC_COMBO_TAB_POSITION"))
        XCTAssertFalse(page.isEnabled("IDC_CHECK_RetainEmptyWindow"), "グループ化しないとき")
        click(page, "IDC_CHECK_DispTabWndMultiWin")
        XCTAssertTrue(page.isEnabled("IDC_CHECK_RetainEmptyWindow"))
        page.select("IDC_COMBO_TAB_POSITION", 1)
        controller.ok(nil)
        XCTAssertEqual(store.values["Common/bDispTabWnd"], "1")
        XCTAssertEqual(store.values["Common/bDispTabWndMultiWin"], "0")
        XCTAssertEqual(store.values["Common/eTabPosition"], "1")
    }

    /// ステータスバー：[Statusbar] 节
    func testStatusbarPage() throws {
        store.values["Statusbar/DispColByChar"] = "0"
        let (controller, page) = try open("ステータスバー")
        click(page, "IDC_CHECK_DISP_COL_BY_CHAR")
        controller.ok(nil)
        XCTAssertEqual(store.values["Statusbar/DispColByChar"], "1")
    }

    /// 編集：ファイルダイアログの初期位置、指定フォルダー のときだけフォルダー名
    func testEditPage() throws {
        store.values["Common/eOpenDialogDir"] = "1"
        store.values["Common/bUseOLE_DragDrop"] = "1"
        let (controller, page) = try open("編集")
        XCTAssertTrue(page.isChecked("IDC_RADIO_MRUDIR"))
        XCTAssertFalse(page.isEnabled("IDC_EDIT_FILEOPENDIR"))
        XCTAssertTrue(page.isEnabled("IDC_CHECK_DROPSOURCE"))
        click(page, "IDC_CHECK_DRAGDROP", false)
        XCTAssertFalse(page.isEnabled("IDC_CHECK_DROPSOURCE"))
        click(page, "IDC_RADIO_SELDIR")
        XCTAssertTrue(page.isEnabled("IDC_EDIT_FILEOPENDIR"))
        XCTAssertFalse(page.isEnabled("IDC_CHECK_VISTA_STYLE_FILEDIALOG"))
        CommonSettingsPages.chooseFolder = { _, _ in "/Users/test/Documents" }
        defer { CommonSettingsPages.chooseFolder = { _, _ in nil } }
        page.onButton?("IDC_BUTTON_FILEOPENDIR")
        controller.ok(nil)
        XCTAssertEqual(store.values["Common/eOpenDialogDir"], "2")
        XCTAssertEqual(store.values["Common/szOpenDialogSelDir"], "/Users/test/Documents")
        XCTAssertEqual(store.values["Common/bUseOLE_DragDrop"], "0")
    }

    /// ファイル：自動保存 は bBackUpType2_Opt1 の BKUP_AUTO ビット（日付のビットは変えない）、間隔は Opt3
    func testFilePageAutoSaveBits() throws {
        store.values["Common/bBackUpType2_Opt1"] = String(32 | 8)
        store.values["Common/bBackUpType2_Opt3"] = "5"
        store.values["Common/bDropFileAndClose"] = "1"
        let (controller, page) = try open("ファイル")
        XCTAssertFalse(page.isChecked("IDC_CHECK_AUTOSAVE"))
        XCTAssertFalse(page.isEnabled("IDC_EDIT_AUTOBACKUP_INTERVAL"))
        XCTAssertFalse(page.isEnabled("IDC_EDIT_nDropFileNumMax"))
        XCTAssertFalse(page.isEnabled("IDC_COMBO_FILESHAREMODE"))
        click(page, "IDC_CHECK_AUTOSAVE")
        XCTAssertTrue(page.isEnabled("IDC_EDIT_AUTOBACKUP_INTERVAL"))
        type(page, "IDC_EDIT_AUTOBACKUP_INTERVAL", "30分")	// 原版：先頭の数字
        type(page, "IDC_EDIT_ALERT_FILESIZE", "9999")
        controller.ok(nil)
        XCTAssertEqual(store.values["Common/bBackUpType2_Opt1"], String(64 | 32 | 8))
        XCTAssertEqual(store.values["Common/bBackUpType2_Opt3"], "30")
        XCTAssertEqual(store.values["Common/nAlertFileSize"], "2048")
    }

    /// バックアップ：ファイル名のタイプ（nBackUpType 1～6）、日付のビット、世代数、詳細設定のファイル名（原版 UpdateBackupFile）
    func testBackupPage() throws {
        store.values["Common/bBackUp"] = "0"
        store.values["Common/nBackUpType"] = "6"	// .*.b??
        store.values["Common/bBackUpType2_Opt1"] = "64"	// 自動保存のビットだけ
        store.values["Common/bBackUpType2_Opt2"] = String((0x62 << 16) | 3)	// 拡張子の文字 'b'、3 世代
        store.values["Common/bBackUpPathAdvanced"] = "0"
        store.values["Common/bBackUpFolder"] = "0"
        store.values["Common/bBackUpDustBox"] = "0"
        let (controller, page) = try open("バックアップ")
        XCTAssertTrue(page.isChecked("IDC_RADIO_BACKUP_TYPE3"))
        XCTAssertTrue(page.isChecked("IDC_CHECK_BACKUP_RETAINEXT"))
        XCTAssertEqual(page.text("IDC_EDIT_BACKUP_3"), "3")
        XCTAssertFalse(page.isEnabled("IDC_RADIO_BACKUP_TYPE1"), "バックアップを作成しないとき")
        XCTAssertEqual(page.text("IDC_EDIT_BACKUPFILE"), "")

        click(page, "IDC_CHECK_BACKUP")
        XCTAssertTrue(page.isEnabled("IDC_RADIO_BACKUP_TYPE1"))
        XCTAssertTrue(page.isEnabled("IDC_EDIT_BACKUP_3"))
        XCTAssertFalse(page.isEnabled("IDC_CHECK_BACKUP_YEAR"))
        XCTAssertEqual(page.text("IDC_EDIT_BACKUPFILE"), ".\\$0.*.b??")

        click(page, "IDC_RADIO_BACKUP_DATETYPE1")
        XCTAssertFalse(page.isChecked("IDC_RADIO_BACKUP_TYPE3"))
        XCTAssertTrue(page.isEnabled("IDC_CHECK_BACKUP_YEAR"))
        XCTAssertFalse(page.isEnabled("IDC_EDIT_BACKUP_3"))
        click(page, "IDC_CHECK_BACKUP_YEAR")
        click(page, "IDC_CHECK_BACKUP_DAY")
        XCTAssertEqual(page.text("IDC_EDIT_BACKUPFILE"), ".\\$0_%Y%d.*")

        click(page, "IDC_CHECK_BACKUP_DUSTBOX")
        XCTAssertEqual(page.text("IDC_EDIT_BACKUPFILE"), "(ゴミ箱)\\$0_%Y%d.*")

        // 詳細設定：詳細設定の項目だけ表示
        XCTAssertFalse(page.isShown("IDC_RADIO_BACKUP_DATETYPE1A"))
        click(page, "IDC_CHECK_BACKUP_ADVANCED")
        XCTAssertTrue(page.isShown("IDC_RADIO_BACKUP_DATETYPE1A"))
        XCTAssertFalse(page.isShown("IDC_RADIO_BACKUP_DATETYPE1"))
        XCTAssertFalse(page.isShown("IDC_CHECK_BACKUP_YEAR"))
        XCTAssertTrue(page.isEnabled("IDC_EDIT_BACKUPFILE"))
        click(page, "IDC_RADIO_BACKUP_DATETYPE2A")
        type(page, "IDC_EDIT_BACKUPFILE", "$0.%Y%m%d.bak")

        controller.ok(nil)
        XCTAssertEqual(store.values["Common/bBackUp"], "1")
        XCTAssertEqual(store.values["Common/nBackUpType"], "2")
        XCTAssertEqual(store.values["Common/bBackUpType2_Opt1"], String(64 | 32 | 8))
        XCTAssertFalse(store.writes.contains("Common/bBackUpType2_Opt2"), "世代数は変えていない")
        XCTAssertEqual(store.values["Common/bBackUpPathAdvanced"], "1")
        XCTAssertEqual(store.values["Common/szBackUpPathAdvanced"], "$0.%Y%m%d.bak")
        XCTAssertEqual(store.values["Common/bBackUpType2_Opt4"], "4")
    }

    /// バックアップ：世代数は Opt2 の下位 16 ビット（上位の拡張子の文字は残す）
    func testBackupGenerationsKeepExtensionChar() throws {
        store.values["Common/bBackUp"] = "1"
        store.values["Common/nBackUpType"] = "3"
        store.values["Common/bBackUpType2_Opt2"] = String((0x62 << 16) | 3)
        let (controller, page) = try open("バックアップ")
        type(page, "IDC_EDIT_BACKUP_3", "150")
        controller.ok(nil)
        XCTAssertEqual(store.values["Common/bBackUpType2_Opt2"], String((0x62 << 16) | 99))
    }

    /// 書式：表示例（原版 ChangeDateExample）、カスタム のときだけ書式
    func testFormatPage() throws {
        store.values["Common/nDateFormatType"] = "0"
        store.values["Common/szDateFormat"] = "yyyy/MM/dd"
        let (controller, page) = try open("書式")
        XCTAssertFalse(page.isEnabled("IDC_EDIT_DFORM"))
        XCTAssertEqual(page.text("IDC_EDIT_DFORM_EX"), WindowsDateFormat.date(Date(), type: 0, format: ""))
        click(page, "IDC_RADIO_DFORM_1")
        XCTAssertTrue(page.isEnabled("IDC_EDIT_DFORM"))
        type(page, "IDC_EDIT_DFORM", "yyyy'年'M'月'")
        XCTAssertEqual(page.text("IDC_EDIT_DFORM_EX"), WindowsDateFormat.date(Date(), type: 1, format: "yyyy'年'M'月'"))
        type(page, "IDC_EDIT_INYOUKIGOU", "> ")
        controller.ok(nil)
        XCTAssertEqual(store.values["Common/nDateFormatType"], "1")
        XCTAssertEqual(store.values["Common/szDateFormat"], "yyyy'年'M'月'")
        XCTAssertEqual(store.values["Common/szInyouKigou"], "> ")
    }

    /// 検索：タグジャンプの組み合わせ（タグファイルの検索 には 2 がない）
    func testGrepPage() throws {
        store.values["Common/nTagJumpMode"] = "3"
        store.values["Common/nTagJumpModeKeyword"] = "2"
        let (controller, page) = try open("検索")
        XCTAssertEqual(page.selectedIndex("IDC_COMBO_TAGJUMP"), 2)
        XCTAssertEqual(page.selectedIndex("IDC_COMBO_KEYWORD_TAGJUMP"), 2)
        XCTAssertFalse(page.isEnabled("IDC_EDIT_REGEXPLIB"))
        page.select("IDC_COMBO_TAGJUMP", 1)
        controller.ok(nil)
        XCTAssertEqual(store.values["Common/nTagJumpMode"], "1")
        XCTAssertNil(store.writes.firstIndex(of: "Common/nTagJumpModeKeyword"))
    }

    /// ファイル名表示：[Nickname] 节
    func testFileNamePage() throws {
        store.values["Nickname/bShortPath"] = "1"
        store.values["Nickname/nShortPathMaxWidth"] = "60"
        let (controller, page) = try open("ファイル名表示")
        XCTAssertTrue(page.isChecked("IDC_CHECK_SHORTPATH"))
        XCTAssertEqual(page.text("IDC_EDIT_SHORTMAXWIDTH"), "60")
        type(page, "IDC_EDIT_SHORTMAXWIDTH", "80")
        controller.ok(nil)
        XCTAssertEqual(store.values["Nickname/nShortPathMaxWidth"], "80")
    }

    /// 全般「履歴をクリア」：确认以后删除（原版 CMRUFile::ClearAll）
    func testClearRecentFiles() throws {
        let (controller, page) = try open("全般")
        defer { controller.cancel(nil) }
        var messages: [String] = []
        CommonSettingsPages.inform = { messages.append($0) }
        CommonSettingsPages.confirm = { _ in false }
        defer {
            CommonSettingsPages.confirm = { _ in false }
            CommonSettingsPages.inform = { _ in }
        }
        page.onButton?("IDC_BUTTON_CLEAR_MRU_FILE")
        XCTAssertEqual(messages, [], "キャンセルしたとき")
        CommonSettingsPages.confirm = { _ in true }
        page.onButton?("IDC_BUTTON_CLEAR_MRU_FILE")
        XCTAssertEqual(messages, ["最近使ったファイルの履歴を削除しました。"])
        XCTAssertEqual(EditorCore.recentFiles.count, 0)
        page.onButton?("IDC_BUTTON_CLEAR_MRU_FOLDER")
        XCTAssertEqual(EditorCore.recentFolders.count, 0)
    }

    // MARK: - 日付・時刻の書式（Windows の GetDateFormat、GetTimeFormat と同じ）

    func testWindowsDateFormat() throws {
        let date = try XCTUnwrap(Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 1, day: 5, hour: 9, minute: 7, second: 3)))
        XCTAssertEqual(WindowsDateFormat.date(date, type: 1, format: "yyyy/MM/dd"), "2026/01/05")
        XCTAssertEqual(WindowsDateFormat.date(date, type: 1, format: "y yy yyyy M d"), "6 26 2026 1 5")
        XCTAssertEqual(WindowsDateFormat.date(date, type: 1, format: "ddd dddd"), "月 月曜日")
        XCTAssertEqual(WindowsDateFormat.date(date, type: 1, format: "yyyy'年'M'月'd'日'"), "2026年1月5日")
        XCTAssertEqual(WindowsDateFormat.date(date, type: 1, format: "'It''s' yy"), "It's 26")
        XCTAssertEqual(WindowsDateFormat.date(date, type: 0, format: ""), "2026年1月5日")
        XCTAssertEqual(WindowsDateFormat.time(date, type: 1, format: "HH:mm:ss"), "09:07:03")
        XCTAssertEqual(WindowsDateFormat.time(date, type: 1, format: "tt h:m:s"), "午前 9:7:3")
        XCTAssertEqual(WindowsDateFormat.time(date, type: 0, format: ""), "9:07:03")
        // 日付の書式の中の時刻の記号はそのまま（Windows と同じ）
        XCTAssertEqual(WindowsDateFormat.date(date, type: 1, format: "dd HH"), "05 HH")
    }
}

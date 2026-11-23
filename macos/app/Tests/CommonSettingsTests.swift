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

        func setValues(_ values: [String: String], section: String) -> Bool {
            for (key, value) in values.sorted(by: { $0.key < $1.key }) {
                self.values["\(section)/\(key)"] = value
                writes.append("\(section)/\(key)")
            }
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
        let (keyController, keybind) = try open("マクロ")
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
        type(page, "IDC_EDIT_INYOUKIGOU", "| ")
        controller.ok(nil)
        XCTAssertEqual(store.values["Common/nDateFormatType"], "1")
        XCTAssertEqual(store.values["Common/szDateFormat"], "yyyy'年'M'月'")
        XCTAssertEqual(store.values["Common/szInyouKigou"], "| ")
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

    /// ファイル名表示 的置換リスト（原版 CPropFileName：挿入・追加・更新・削除・先頭・上へ・下へ・最終）
    func testFileNameReplaceList() throws {
        store.values["Nickname/ArrNum"] = "2"
        store.values["Nickname/From00"] = "%USERPROFILE%\\"
        store.values["Nickname/To00"] = "~\\"
        store.values["Nickname/From01"] = "C:\\Work\\"
        store.values["Nickname/To01"] = "W:"
        let (controller, page) = try open("ファイル名表示")
        let list = try XCTUnwrap(page.list("IDC_LIST_FNAME"))
        let from = "IDC_EDIT_FNAME_FROM", to = "IDC_EDIT_FNAME_TO"
        func press(_ name: String) { page.onButton?("IDC_BUTTON_FNAME_" + name) }
        func sources() -> [String] { list.rows.map { $0[0] } }

        XCTAssertEqual(list.table.tableColumns.map(\.title), ["置換前", "置換後"])
        XCTAssertEqual(list.rows, [["%USERPROFILE%\\", "~\\"], ["C:\\Work\\", "W:"]])
        XCTAssertTrue(page.isEnabled("IDC_LIST_FNAME"))
        XCTAssertTrue(page.isEnabled("IDC_BUTTON_FNAME_ADD"))
        // 一番上を選択して、エディットに表示
        XCTAssertEqual(list.selectedRow, 0)
        XCTAssertEqual(page.text(from), "%USERPROFILE%\\")
        list.select(1)
        XCTAssertEqual(page.text(from), "C:\\Work\\")
        XCTAssertEqual(page.text(to), "W:")

        // 追加：最後に
        page.setText(from, "D:\\Data\\")
        page.setText(to, "D:")
        press("ADD")
        XCTAssertEqual(sources(), ["%USERPROFILE%\\", "C:\\Work\\", "D:\\Data\\"])
        XCTAssertEqual(list.selectedRow, 2)
        // 挿入：選択中の位置に
        page.setText(from, "E:\\")
        page.setText(to, "E:")
        press("INS")
        XCTAssertEqual(sources(), ["%USERPROFILE%\\", "C:\\Work\\", "E:\\", "D:\\Data\\"])
        XCTAssertEqual(list.selectedRow, 2)
        // 更新
        page.setText(to, "EE:")
        press("UPD")
        XCTAssertEqual(list.rows[2], ["E:\\", "EE:"])
        // 置換前が空なら何もしない
        page.setText(from, "")
        press("ADD")
        press("INS")
        XCTAssertEqual(list.rows.count, 4)

        // 先頭・下へ・最終・上へ
        press("TOP")
        XCTAssertEqual(sources(), ["E:\\", "%USERPROFILE%\\", "C:\\Work\\", "D:\\Data\\"])
        XCTAssertEqual(list.selectedRow, 0)
        XCTAssertEqual(page.text(from), "E:\\")
        press("DOWN")
        XCTAssertEqual(sources(), ["%USERPROFILE%\\", "E:\\", "C:\\Work\\", "D:\\Data\\"])
        press("LAST")
        XCTAssertEqual(sources(), ["%USERPROFILE%\\", "C:\\Work\\", "D:\\Data\\", "E:\\"])
        XCTAssertEqual(list.selectedRow, 3)
        press("UP")
        XCTAssertEqual(sources(), ["%USERPROFILE%\\", "C:\\Work\\", "E:\\", "D:\\Data\\"])
        XCTAssertEqual(list.selectedRow, 2)
        // 削除：同じ位置を選択
        press("DEL")
        XCTAssertEqual(sources(), ["%USERPROFILE%\\", "C:\\Work\\", "D:\\Data\\"])
        XCTAssertEqual(list.selectedRow, 2)

        // OK：ArrNum と From%02d、To%02d（変わった項目だけ）
        controller.ok(nil)
        XCTAssertEqual(store.values["Nickname/ArrNum"], "3")
        XCTAssertEqual(store.values["Nickname/From02"], "D:\\Data\\")
        XCTAssertEqual(store.values["Nickname/To02"], "D:")
        XCTAssertFalse(store.writes.contains("Nickname/From00"))
    }

    /// 置換リスト：空のときは [更新] でも追加できる。16 個より多くは登録できない
    func testFileNameReplaceListLimits() throws {
        store.values["Nickname/ArrNum"] = "0"
        let (controller, page) = try open("ファイル名表示")
        defer { controller.cancel(nil) }
        let list = try XCTUnwrap(page.list("IDC_LIST_FNAME"))
        XCTAssertEqual(list.selectedRow, -1)
        XCTAssertEqual(page.text("IDC_EDIT_FNAME_FROM"), "")
        page.setText("IDC_EDIT_FNAME_FROM", "A")
        page.onButton?("IDC_BUTTON_FNAME_UPD")
        XCTAssertEqual(list.rows, [["A", ""]])

        var messages: [String] = []
        CommonSettingsPages.inform = { messages.append($0) }
        defer { CommonSettingsPages.inform = { _ in } }
        for i in 1..<16 {
            page.setText("IDC_EDIT_FNAME_FROM", "F\(i)")
            page.onButton?("IDC_BUTTON_FNAME_ADD")
        }
        XCTAssertEqual(list.rows.count, 16)
        XCTAssertEqual(messages, [])
        page.onButton?("IDC_BUTTON_FNAME_ADD")
        XCTAssertEqual(list.rows.count, 16)
        XCTAssertEqual(messages, ["これ以上登録できません。"])
        // 更新は 16 個でもできる
        page.setText("IDC_EDIT_FNAME_FROM", "Z")
        page.onButton?("IDC_BUTTON_FNAME_UPD")
        XCTAssertEqual(list.rows.count, 16)
        XCTAssertEqual(list.rows[list.selectedRow][0], "Z")
    }

    /// タブバー・支援 のフォント（原版 MySelectFont、SetFontLabel）
    func testFonts() throws {
        store.values["Common/bDispTabWnd"] = "1"
        store.values["Common/lfTabFont"] = "-12,0,0,0,400,0,0,0,128,3,2,1,49"
        store.values["Common/lfTabFontPs"] = "90"
        store.values["Common/lfTabFaceName"] = "Helvetica"
        var shown: [NSFont] = []
        var chosen: NSFont?
        CommonSettingsPages.chooseFont = { font, _ in
            shown.append(font)
            return chosen
        }
        defer { CommonSettingsPages.chooseFont = { _, _ in nil } }

        let (controller, page) = try open("タブバー")
        XCTAssertEqual(page.text("IDC_STATIC_TABFONT"), "Helvetica(9pt)")
        XCTAssertTrue(page.isEnabled("IDC_BUTTON_TABFONT"))
        // キャンセル：変えない
        page.onButton?("IDC_BUTTON_TABFONT")
        XCTAssertEqual(shown.last?.familyName, "Helvetica")
        XCTAssertEqual(shown.last?.pointSize, 9)
        XCTAssertEqual(page.text("IDC_STATIC_TABFONT"), "Helvetica(9pt)")
        // 選んだ：高さ・太さ・ポイントサイズ・名前を変え、ほかの数はそのまま
        chosen = try XCTUnwrap(NSFont(name: "Helvetica-Bold", size: 10.5))
        page.onButton?("IDC_BUTTON_TABFONT")
        XCTAssertEqual(page.text("IDC_STATIC_TABFONT"), "Helvetica(10.5pt)")
        controller.ok(nil)
        XCTAssertEqual(store.values["Common/lfTabFont"], "-14,0,0,0,700,0,0,0,128,3,2,1,49")
        XCTAssertEqual(store.values["Common/lfTabFontPs"], "105")
        XCTAssertEqual(store.values["Common/lfTabFaceName"], "Helvetica")

        store.values["Common/khlf"] = "-16,0,0,0,700,0,0,0,1,0,0,0,0"
        store.values["Common/khps"] = "120"
        store.values["Common/khlfFaceName"] = "Courier"
        let (helperController, helper) = try open("支援")
        XCTAssertEqual(helper.text("IDC_STATIC_KEYWORDHELPFONT"), "Courier(12pt)")
        chosen = try XCTUnwrap(NSFont(name: "Helvetica-Oblique", size: 14))
        helper.onButton?("IDC_BUTTON_KEYWORDHELPFONT")
        XCTAssertEqual(NSFontManager.shared.traits(of: try XCTUnwrap(shown.last)).contains(.boldFontMask), true, "設定のフォントは太字")
        XCTAssertEqual(helper.text("IDC_STATIC_KEYWORDHELPFONT"), "Helvetica(14pt)")
        helperController.ok(nil)
        XCTAssertEqual(store.values["Common/khlf"], "-19,0,0,0,400,1,0,0,1,0,0,0,0")
        XCTAssertEqual(store.values["Common/khps"], "140")
        XCTAssertEqual(store.values["Common/khlfFaceName"], "Helvetica")
    }

    /// ウィンドウ「位置と大きさの設定」（原版 CDlgWinSize）
    func testWindowSizeDialog() throws {
        store.values["Common/bSaveWindowSize"] = "2"
        store.values["Common/nSaveWindowPos"] = "0"
        store.values["Common/nWinSizeType"] = "2"
        store.values["Common/nWinSizeCX"] = "800"
        store.values["Common/nWinSizeCY"] = "600"
        store.values["Common/nWinPosX"] = "-10"
        store.values["Common/nWinPosY"] = "20"
        var shown = false
        CommonSettingsPages.runWinSizeDialog = { [self] dialog, _ in
            shown = true
            let d = dialog.page
            XCTAssertEqual(dialog.title, "ウィンドウの位置と大きさ")
            XCTAssertTrue(d.isChecked("IDC_RADIO_WINSIZE_SET"))
            XCTAssertTrue(d.isChecked("IDC_RADIO_WINPOS_DEF"))
            XCTAssertEqual(d.selectedIndex("IDC_COMBO_WINTYPE"), 1, "最大化")
            XCTAssertEqual(d.text("IDC_EDIT_SX"), "800")
            XCTAssertEqual(d.text("IDC_EDIT_SY"), "600")
            XCTAssertEqual(d.text("IDC_EDIT_WX"), "-10")
            XCTAssertEqual(d.text("IDC_EDIT_WY"), "20")
            // 直接指定のときだけ数を変えられる
            XCTAssertTrue(d.isEnabled("IDC_EDIT_SX"))
            XCTAssertTrue(d.isEnabled("IDC_COMBO_WINTYPE"))
            XCTAssertFalse(d.isEnabled("IDC_EDIT_WX"))
            XCTAssertFalse(d.isEnabled("IDC_BUTTON_HELP"))
            click(d, "IDC_RADIO_WINPOS_SET")
            XCTAssertFalse(d.isChecked("IDC_RADIO_WINPOS_DEF"))
            XCTAssertTrue(d.isEnabled("IDC_EDIT_WX"))
            XCTAssertTrue(d.isEnabled("IDC_EDIT_WY"))
            click(d, "IDC_RADIO_WINSIZE_SAVE")
            XCTAssertFalse(d.isEnabled("IDC_EDIT_SX"))
            XCTAssertFalse(d.isEnabled("IDC_COMBO_WINTYPE"))
            type(d, "IDC_EDIT_WY", "-30")
            d.select("IDC_COMBO_WINTYPE", 2)	// (最小化)
            d.onButton?("IDOK")
        }
        defer { CommonSettingsPages.runWinSizeDialog = { _, _ in } }
        let (controller, page) = try open("ウィンドウ")
        XCTAssertTrue(page.isEnabled("IDC_BUTTON_WINSIZE"))
        page.onButton?("IDC_BUTTON_WINSIZE")
        XCTAssertTrue(shown)
        controller.ok(nil)
        XCTAssertEqual(store.values["Common/bSaveWindowSize"], "1")
        XCTAssertEqual(store.values["Common/nSaveWindowPos"], "2")
        XCTAssertEqual(store.values["Common/nWinSizeType"], "1", "SIZE_MINIMIZED")
        XCTAssertEqual(store.values["Common/nWinPosY"], "-30")
        XCTAssertFalse(store.writes.contains("Common/nWinPosX"))
        XCTAssertFalse(store.writes.contains("Common/nWinSizeCX"))
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

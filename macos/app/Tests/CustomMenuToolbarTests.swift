// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge
import XCTest

/// 共通設定 > カスタムメニュー・ツールバー（计划第 41 步第 3 个 PR。原版 CPropCustmenu、CPropToolBar）。
final class CustomMenuToolbarTests: XCTestCase {
    private var store: CommonSettingsTests.FakeStore!
    private var inputs: [String?] = []
    private var saved: ((String, String, Int, String) -> String?)!

    override func setUp() {
        _ = TestCore.home
        _ = NSApplication.shared
        store = CommonSettingsTests.FakeStore()
        saved = CommonSettingsPages.input
        CommonSettingsPages.input = { [unowned self] _, _, _, _ in self.inputs.isEmpty ? nil : self.inputs.removeFirst() }
    }

    override func tearDown() {
        CommonSettingsPages.input = saved
    }

    private func open(_ name: String) throws -> (CommonSettingsWindowController, PropPage) {
        let probe = try XCTUnwrap(CommonSettingsWindowController(store: store))
        let index = try XCTUnwrap(probe.pageIndex(named: name))
        probe.cancel(nil)
        let controller = try XCTUnwrap(CommonSettingsWindowController(store: store, page: index))
        return (controller, controller.page(index))
    }

    private func press(_ page: PropPage, _ id: String) { page.onButton?(id) }

    private func rows(_ page: PropPage, _ id: String) -> [String] {
        page.list(id)?.rows.map { $0[0] } ?? []
    }

    private func selectCategory(_ page: PropPage, _ name: String) throws {
        page.select("IDC_COMBO_FUNCKIND", try XCTUnwrap(page.itemTitles("IDC_COMBO_FUNCKIND").firstIndex(of: name)))
        page.onChange?("IDC_COMBO_FUNCKIND")
    }

    private func selectFunction(_ page: PropPage, _ name: String) throws {
        page.list("IDC_LIST_FUNC")?.select(try XCTUnwrap(rows(page, "IDC_LIST_FUNC").firstIndex(of: name), name))
    }

    // MARK: - カスタムメニュー

    /// 開いたとき：メニュー一覧（右クリックメニュー、メニュー1…、タブメニュー）、右クリックメニューの項目
    func testCustomMenuPageShowsMenus() throws {
        let (controller, page) = try open("カスタムメニュー")
        defer { controller.cancel(nil) }
        let menus = page.itemTitles("IDC_COMBO_MENU")
        XCTAssertEqual(menus.count, 25)
        XCTAssertEqual(menus.first, "右クリックメニュー")
        XCTAssertEqual(menus[1], "メニュー1")
        XCTAssertEqual(menus.last, "タブメニュー")
        XCTAssertFalse(rows(page, "IDC_LIST_RES").isEmpty, "右クリックメニューの初期値")
        XCTAssertTrue(rows(page, "IDC_LIST_RES").contains(CustomMenuPage.separatorLabel))
        XCTAssertEqual(page.list("IDC_LIST_RES")?.selectedRow, 0)
        XCTAssertEqual(page.itemTitles("IDC_COMBO_FUNCKIND").last, "特別機能")
    }

    /// 追加・挿入・区切線・↑↓・削除、アクセスキー、メニュー名の設定、サブメニュー。OK で [CustMenu] に書く
    func testEditCustomMenuAndOK() throws {
        let (controller, page) = try open("カスタムメニュー")
        let editor = try XCTUnwrap(controller.values.commandEditor)
        editor.setCustomMenu(5, codes: [], accessKeys: [])	// 空のメニューから
        editor.setCustomMenu(5, isSubmenu: false)
        page.select("IDC_COMBO_MENU", 5)
        page.onChange?("IDC_COMBO_MENU")
        XCTAssertEqual(rows(page, "IDC_LIST_RES"), [])
        XCTAssertFalse(page.isEnabled("IDC_BUTTON_DELETE"))
        try selectCategory(page, "ファイル操作系")
        try selectFunction(page, "新規作成")
        press(page, "IDC_BUTTON_ADD")
        XCTAssertEqual(rows(page, "IDC_LIST_RES"), ["新規作成"])
        XCTAssertEqual(page.list("IDC_LIST_FUNC")?.selectedRow, 1, "次の機能")
        press(page, "IDC_BUTTON_ADD")	// 新規ウインドウを開く
        page.list("IDC_LIST_RES")?.select(1)
        press(page, "IDC_BUTTON_INSERTSEPARATOR")
        XCTAssertEqual(rows(page, "IDC_LIST_RES"), ["新規作成", CustomMenuPage.separatorLabel, "新規ウインドウを開く"])
        try selectFunction(page, "上書き保存")
        page.list("IDC_LIST_RES")?.select(0)
        press(page, "IDC_BUTTON_INSERT")
        XCTAssertEqual(rows(page, "IDC_LIST_RES").first, "上書き保存")
        press(page, "IDC_BUTTON_DOWN")
        XCTAssertEqual(rows(page, "IDC_LIST_RES").prefix(2), ["新規作成", "上書き保存"])
        XCTAssertEqual(page.list("IDC_LIST_RES")?.selectedRow, 1)
        press(page, "IDC_BUTTON_UP")
        XCTAssertEqual(page.list("IDC_LIST_RES")?.selectedRow, 0)
        press(page, "IDC_BUTTON_DELETE")
        XCTAssertEqual(rows(page, "IDC_LIST_RES"), ["新規作成", CustomMenuPage.separatorLabel, "新規ウインドウを開く"])
        // アクセスキー（ダブルクリック）。区切線は設定しない
        inputs = ["N"]
        page.list("IDC_LIST_RES")?.onDoubleClick?(0, 0)
        XCTAssertEqual(rows(page, "IDC_LIST_RES").first, "新規作成(N)")
        inputs = ["X"]
        page.list("IDC_LIST_RES")?.onDoubleClick?(1, 0)
        XCTAssertEqual(inputs, ["X"], "区切線は聞かない")
        // メニュー名
        page.setText("IDC_EDIT_MENUNAME", "マイメニュー")
        press(page, "IDC_BUTTON_MENUNAME")
        XCTAssertEqual(page.itemTitles("IDC_COMBO_MENU")[5], "マイメニュー")
        page.setChecked("IDC_CHECK_SUBMENU", true)
        page.onChange?("IDC_CHECK_SUBMENU")
        controller.ok(nil)
        XCTAssertEqual(store.values["CustMenu/szCMN[05]"], "マイメニュー")
        XCTAssertEqual(store.values["CustMenu/bCMPOP[05]"] ?? EditorCore.commonSetting(section: "CustMenu", key: "bCMPOP[05]"), "1")
        XCTAssertEqual(store.values["CustMenu/nCMIN[05]"], "3")
        XCTAssertEqual(store.values["CustMenu/nCMIF[05][00]"], "30101")
        XCTAssertEqual(store.values["CustMenu/nCMIF[05][01]"], "0")
        XCTAssertNotNil(store.values["CustMenu/nCMIK[05][00]"])
    }

    /// カスタムメニュー の名前はキー割り当て の「機能」（カスタムメニュー）にも出る（同じ複製、原版 PSN_SETACTIVE）
    func testCustomMenuNameShowsInKeyBind() throws {
        let (controller, page) = try open("カスタムメニュー")
        defer { controller.cancel(nil) }
        page.select("IDC_COMBO_MENU", 2)
        page.onChange?("IDC_COMBO_MENU")
        page.setText("IDC_EDIT_MENUNAME", "テスト")
        press(page, "IDC_BUTTON_MENUNAME")
        let keyIndex = try XCTUnwrap(controller.pageIndex(named: "キー割り当て"))
        controller.showPage(keyIndex)
        let keyPage = controller.page(keyIndex)
        try selectCategory(keyPage, "カスタムメニュー")
        XCTAssertTrue(rows(keyPage, "IDC_LIST_FUNC").contains("テスト"))
    }

    /// 項目の上限（48）：区切線・挿入・追加 はできない
    func testCustomMenuFull() throws {
        let (controller, page) = try open("カスタムメニュー")
        defer { controller.cancel(nil) }
        page.select("IDC_COMBO_MENU", 3)
        page.onChange?("IDC_COMBO_MENU")
        for _ in 0..<48 { press(page, "IDC_BUTTON_INSERTSEPARATOR") }
        XCTAssertEqual(rows(page, "IDC_LIST_RES").count, 48)
        page.onChange?("IDC_LIST_RES")
        XCTAssertFalse(page.isEnabled("IDC_BUTTON_INSERTSEPARATOR"))
        press(page, "IDC_BUTTON_INSERTSEPARATOR")
        XCTAssertEqual(rows(page, "IDC_LIST_RES").count, 48)
    }

    // MARK: - ツールバー

    /// 開いたとき：今のボタン（アイコンと名前）、ボタンのある機能だけ、フラット
    func testToolbarPageShowsButtons() throws {
        let (controller, page) = try open("ツールバー")
        defer { controller.cancel(nil) }
        let editor = try XCTUnwrap(EditorCommandSettingsEditor())
        XCTAssertEqual(rows(page, "IDC_LIST_RES").count, editor.toolbarButtons.count)
        XCTAssertEqual(rows(page, "IDC_LIST_RES").first, "新規作成")
        XCTAssertTrue(rows(page, "IDC_LIST_RES").contains("───────────"), "区切")
        XCTAssertEqual(page.list("IDC_LIST_RES")?.selectedRow, 0)
        XCTAssertEqual(page.isChecked("IDC_CHECK_TOOLBARISFLAT"), editor.toolbarIsFlat)
        XCTAssertTrue(rows(page, "IDC_LIST_FUNC").contains("新規作成"))
        XCTAssertFalse(page.itemTitles("IDC_COMBO_FUNCKIND").contains("特別機能"))
        // アイコン：mytool.bmp（原版 IDB_MYTOOL）
        XCTAssertEqual(ToolbarIcons.shared.count, 480)	// MAX_TOOLBAR_ICON_COUNT
        let icon = try XCTUnwrap(ToolbarIcons.shared.image(editor.icon(ofToolbarButton: editor.toolbarButtons[0].intValue)))
        XCTAssertEqual(icon.size, NSSize(width: 16, height: 16))
        // 絵がある（左上の色だけが透明）
        let opaque = ToolbarIcons.shared.opaquePixelCount(editor.icon(ofToolbarButton: editor.toolbarButtons[0].intValue))
        XCTAssertGreaterThan(opaque, 20)
        XCTAssertLessThan(opaque, 256)
        XCTAssertNil(ToolbarIcons.shared.image(-1))
        let cell = try XCTUnwrap(page.list("IDC_LIST_RES")?.cellView?(0, 0) as? NSStackView)
        XCTAssertTrue(cell.views.first is NSImageView)
    }

    /// 区切・折返・挿入（前に挿入し、元の項目を選んだまま）・追加・↑↓・削除。OK で [Toolbar] に書く
    func testEditToolbarAndOK() throws {
        let (controller, page) = try open("ツールバー")
        let count = rows(page, "IDC_LIST_RES").count
        page.list("IDC_LIST_RES")?.select(0)
        press(page, "IDC_BUTTON_INSERTWRAP")
        XCTAssertEqual(rows(page, "IDC_LIST_RES").first, "――ツールバー折返――")
        XCTAssertEqual(page.list("IDC_LIST_RES")?.selectedRow, 0)
        press(page, "IDC_BUTTON_DELETE")
        XCTAssertEqual(rows(page, "IDC_LIST_RES").count, count)
        try selectCategory(page, "クリップボード系")
        try selectFunction(page, "コピー")
        page.list("IDC_LIST_RES")?.select(0)
        press(page, "IDC_BUTTON_INSERT")
        XCTAssertEqual(rows(page, "IDC_LIST_RES").first, "コピー")
        XCTAssertEqual(page.list("IDC_LIST_RES")?.selectedRow, 1, "元の項目を選んだまま")
        press(page, "IDC_BUTTON_ADD")
        XCTAssertEqual(page.list("IDC_LIST_RES")?.selectedRow, count + 1)
        press(page, "IDC_BUTTON_UP")
        XCTAssertEqual(page.list("IDC_LIST_RES")?.selectedRow, count)
        press(page, "IDC_BUTTON_INSERTSEPARATOR")
        let flat = page.isChecked("IDC_CHECK_TOOLBARISFLAT")
        page.setChecked("IDC_CHECK_TOOLBARISFLAT", !flat)
        controller.ok(nil)
        XCTAssertEqual(store.values["Toolbar/nToolBarButtonNum"], String(count + 3))
        let editor = try XCTUnwrap(EditorCommandSettingsEditor())
        XCTAssertEqual(store.values["Toolbar/nTBB[000]"], String(editor.toolbarButton(forFunction: 30602)))
        XCTAssertEqual(store.values["Toolbar/bToolBarIsFlat"], flat ? "0" : "1")
    }

    /// インポート・エクスポート（カスタムメニュー *.mnu）
    func testCustomMenuImportExport() throws {
        let savedFiles = (TypeSettingsPages.chooseImportFile, TypeSettingsPages.chooseExportFile, TypeSettingsPages.showMessage)
        defer { (TypeSettingsPages.chooseImportFile, TypeSettingsPages.chooseExportFile, TypeSettingsPages.showMessage) = savedFiles }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("CustMenuTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appendingPathComponent("menu.mnu").path
        var messages: [String] = []
        TypeSettingsPages.showMessage = { messages.append($0) }
        TypeSettingsPages.chooseExportFile = { _, extensions, _ in extensions == ["mnu"] ? path : nil }
        TypeSettingsPages.chooseImportFile = { extensions, _ in extensions == ["mnu"] ? path : nil }

        let (controller, page) = try open("カスタムメニュー")
        page.select("IDC_COMBO_MENU", 4)
        page.onChange?("IDC_COMBO_MENU")
        page.setText("IDC_EDIT_MENUNAME", "Exported")
        press(page, "IDC_BUTTON_MENUNAME")
        press(page, "IDC_BUTTON_EXPORT")
        XCTAssertEqual(messages.last, "ファイルをエクスポートしました。\n\n" + path)
        controller.cancel(nil)

        let (other, otherPage) = try open("カスタムメニュー")
        defer { other.cancel(nil) }
        XCTAssertEqual(otherPage.itemTitles("IDC_COMBO_MENU")[4], "メニュー4")
        press(otherPage, "IDC_BUTTON_IMPORT")
        XCTAssertEqual(otherPage.itemTitles("IDC_COMBO_MENU")[4], "Exported")
    }
}

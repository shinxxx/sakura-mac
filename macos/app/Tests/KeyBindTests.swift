// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge
import XCTest

/// 共通設定 > キー割り当て（计划第 41 步第 1 个 PR。原版 CPropKeybind）。
///
/// - 種別・機能・キー一覧、Shift / Ctrl / Alt でキー一覧の名前が変わる、キーに割り当てられている機能、機能に割り当てられているキー
/// - 割当・解除（ボタンの有効・無効も原版の WM_TIMER と同じ）、割り当てられているキーを選ぶとそのキーとチェックボックスを選ぶ
/// - OK で [KeyBind] に書く（真的核心库：按键马上用新的功能，菜单的快捷键也换）。キャンセル は何も変えない
/// - インポート・エクスポート（*.key）
final class KeyBindTests: XCTestCase {
    private var store: CommonSettingsTests.FakeStore!
    private static let copy = 30602		// F_COPY
    private static let selectAll = 30401	// F_SELECTALL
    private static let f12 = 0x7B

    override func setUp() {
        _ = TestCore.home
        _ = NSApplication.shared
        store = CommonSettingsTests.FakeStore()
    }

    private func open(store: CommonSettingsStore? = nil) throws -> (CommonSettingsWindowController, PropPage) {
        let store = store ?? self.store!
        let probe = try XCTUnwrap(CommonSettingsWindowController(store: store))
        let index = try XCTUnwrap(probe.pageIndex(named: "キー割り当て"))
        probe.cancel(nil)
        let controller = try XCTUnwrap(CommonSettingsWindowController(store: store, page: index))
        return (controller, controller.page(index))
    }

    private func click(_ page: PropPage, _ id: String, _ on: Bool = true) {
        page.setChecked(id, on)
        page.onChange?(id)
    }

    private func press(_ page: PropPage, _ id: String) {
        page.onButton?(id)
    }

    private func select(_ page: PropPage, _ list: String, _ row: Int) {
        page.list(list)?.select(row)	// 选择变了 → onChange
    }

    private func selectCategory(_ page: PropPage, _ index: Int) {
        page.select("IDC_COMBO_FUNCKIND", index)
        page.onChange?("IDC_COMBO_FUNCKIND")
    }

    private func rows(_ page: PropPage, _ list: String) -> [String] {
        page.list(list)?.rows.map { $0[0] } ?? []
    }

    private func keyRow(_ page: PropPage, _ name: String) throws -> Int {
        try XCTUnwrap(rows(page, "IDC_LIST_KEY").firstIndex(of: name), name)
    }

    /// 選んだ種別の中のこの機能の行
    private func functionRow(_ page: PropPage, _ name: String) throws -> Int {
        try XCTUnwrap(rows(page, "IDC_LIST_FUNC").firstIndex(of: name), name)
    }

    // MARK: -

    /// 開いたとき：種別の先頭、キー一覧の先頭を選び、そのキーの機能を表示（原版 WM_INITDIALOG）
    func testPageShowsCategoriesAndKeys() throws {
        let (controller, page) = try open()
        defer { controller.cancel(nil) }
        let editor = try XCTUnwrap(EditorCommandSettingsEditor())
        XCTAssertEqual(page.itemTitles("IDC_COMBO_FUNCKIND"), editor.functionCategories)
        XCTAssertEqual(page.itemTitles("IDC_COMBO_FUNCKIND").first, "ファイル操作系")
        XCTAssertEqual(page.itemTitles("IDC_COMBO_FUNCKIND").suffix(3), ["外部マクロ", "カスタムメニュー", "プラグイン"])
        XCTAssertEqual(page.selectedIndex("IDC_COMBO_FUNCKIND"), 0)
        XCTAssertEqual(rows(page, "IDC_LIST_FUNC"), editor.functionNames(inCategory: 0))
        XCTAssertEqual(rows(page, "IDC_LIST_KEY").count, editor.keyCount)
        XCTAssertEqual(rows(page, "IDC_LIST_KEY").first, "ダブルクリック")
        XCTAssertEqual(page.list("IDC_LIST_KEY")?.selectedRow, 0)
        XCTAssertEqual(page.text("IDC_EDIT_KEYSFUNC"), editor.name(ofFunction: editor.function(ofKey: 0, modifiers: 0)))
        // 機能を選んでいないので 割当 はできない、キーを選んでいるので 解除 はできる
        XCTAssertFalse(page.isEnabled("IDC_BUTTON_ASSIGN"))
        XCTAssertTrue(page.isEnabled("IDC_BUTTON_RELEASE"))
        XCTAssertTrue(page.isEnabled("IDC_BUTTON_IMPORT"))
        // プラグイン は Mac 版では空
        selectCategory(page, page.itemTitles("IDC_COMBO_FUNCKIND").count - 1)
        XCTAssertEqual(rows(page, "IDC_LIST_FUNC"), [])
    }

    /// Shift / Ctrl / Alt：キー一覧の名前に付き、キーの機能はその組み合わせのもの（原版 ChangeKeyList）
    func testModifierChecksChangeKeyList() throws {
        let (controller, page) = try open()
        defer { controller.cancel(nil) }
        let f8 = try keyRow(page, "F8")
        select(page, "IDC_LIST_KEY", f8)
        XCTAssertEqual(page.text("IDC_EDIT_KEYSFUNC"), "コピー")
        click(page, "IDC_CHECK_SHIFT")
        click(page, "IDC_CHECK_CTRL")
        XCTAssertEqual(rows(page, "IDC_LIST_KEY")[f8], "Shift+Ctrl+F8")
        XCTAssertEqual(page.list("IDC_LIST_KEY")?.selectedRow, f8, "選択はそのまま")
        click(page, "IDC_CHECK_ALT")
        XCTAssertEqual(rows(page, "IDC_LIST_KEY")[f8], "Shift+Ctrl+Alt+F8")
        XCTAssertEqual(page.text("IDC_EDIT_KEYSFUNC"), "未割当")
        click(page, "IDC_CHECK_SHIFT", false)
        click(page, "IDC_CHECK_CTRL", false)
        click(page, "IDC_CHECK_ALT", false)
        XCTAssertEqual(rows(page, "IDC_LIST_KEY")[f8], "F8")
    }

    /// 機能に割り当てられているキー。それを選ぶとそのキーとチェックボックスを選ぶ
    func testAssignedKeysSelectKey() throws {
        let (controller, page) = try open()
        defer { controller.cancel(nil) }
        let clip = try XCTUnwrap(page.itemTitles("IDC_COMBO_FUNCKIND").firstIndex(of: "クリップボード系"))
        selectCategory(page, clip)
        select(page, "IDC_LIST_FUNC", try functionRow(page, "コピー"))
        let assigned = rows(page, "IDC_LIST_ASSIGNEDKEYS")
        XCTAssertTrue(assigned.contains("F8"), "\(assigned)")
        let ctrlC = try XCTUnwrap(assigned.firstIndex(of: "Ctrl+C"))
        XCTAssertTrue(page.isEnabled("IDC_BUTTON_ASSIGN"))
        select(page, "IDC_LIST_ASSIGNEDKEYS", ctrlC)
        XCTAssertTrue(page.isChecked("IDC_CHECK_CTRL"))
        XCTAssertFalse(page.isChecked("IDC_CHECK_SHIFT"))
        let row = try XCTUnwrap(page.list("IDC_LIST_KEY")?.selectedRow)
        XCTAssertEqual(rows(page, "IDC_LIST_KEY")[row], "Ctrl+C")
        XCTAssertEqual(page.text("IDC_EDIT_KEYSFUNC"), "コピー")
    }

    /// 割当・解除。OK で変わった KeyBind[nnn] だけ書く。キャンセル は何も書かない
    func testAssignReleaseAndOK() throws {
        let (controller, page) = try open()
        let select = try XCTUnwrap(page.itemTitles("IDC_COMBO_FUNCKIND").firstIndex(of: "選択系"))
        selectCategory(page, select)
        self.select(page, "IDC_LIST_FUNC", try functionRow(page, "すべて選択"))
        let f12 = try keyRow(page, "F12")
        self.select(page, "IDC_LIST_KEY", f12)
        click(page, "IDC_CHECK_SHIFT")
        click(page, "IDC_CHECK_ALT")
        press(page, "IDC_BUTTON_ASSIGN")
        XCTAssertEqual(page.text("IDC_EDIT_KEYSFUNC"), "すべて選択")
        XCTAssertTrue(rows(page, "IDC_LIST_ASSIGNEDKEYS").contains("Shift+Alt+F12"))
        // F8 を解除
        click(page, "IDC_CHECK_SHIFT", false)
        click(page, "IDC_CHECK_ALT", false)
        let f8 = try keyRow(page, "F8")
        self.select(page, "IDC_LIST_KEY", f8)
        press(page, "IDC_BUTTON_RELEASE")
        XCTAssertEqual(page.text("IDC_EDIT_KEYSFUNC"), "未割当")
        controller.ok(nil)
        let f12Key = String(format: "KeyBind/KeyBind[%03d]", f12), f8Key = String(format: "KeyBind/KeyBind[%03d]", f8)
        XCTAssertEqual(Set(store.writes), [f12Key, f8Key])
        // 原版の書き方：キーコード,Shift なし…の 8 つ,キー名。Shift+Alt は 5 番目
        XCTAssertEqual(store.values[f12Key]?.split(separator: ",").map(String.init)[0], "007b")
        XCTAssertEqual(store.values[f12Key]?.split(separator: ",").map(String.init)[6], String(Self.selectAll))
        XCTAssertEqual(store.values[f8Key]?.split(separator: ",").map(String.init).prefix(2), ["0077", "0"])
        XCTAssertEqual(store.values[f8Key]?.split(separator: ",").last, "F8")

        // キャンセル
        let (other, otherPage) = try open()
        self.select(otherPage, "IDC_LIST_KEY", f8)
        press(otherPage, "IDC_BUTTON_RELEASE")
        store.writes.removeAll()
        other.cancel(nil)
        XCTAssertEqual(store.writes, [])
    }

    /// 真的核心库：OK 以后按键马上用新的功能，菜单的快捷键也重新设
    func testOKAppliesToCore() throws {
        let original = try XCTUnwrap(EditorCore.commonSetting(section: "KeyBind", key: "KeyBind[000]"))
        let (controller, page) = try open(store: CoreCommonSettingsStore())
        let f12 = try keyRow(page, "F12")
        let key = String(format: "KeyBind[%03d]", f12)
        let before = try XCTUnwrap(EditorCore.commonSetting(section: "KeyBind", key: key))
        defer {
            XCTAssertTrue(EditorCore.setCommonSettings([key: before], section: "KeyBind"))
            KeyCommands.reloadBindings()
        }
        let select = try XCTUnwrap(page.itemTitles("IDC_COMBO_FUNCKIND").firstIndex(of: "選択系"))
        selectCategory(page, select)
        self.select(page, "IDC_LIST_FUNC", try functionRow(page, "すべて選択"))
        self.select(page, "IDC_LIST_KEY", f12)
        click(page, "IDC_CHECK_CTRL")
        press(page, "IDC_BUTTON_ASSIGN")
        XCTAssertNotEqual(EditorCore.command(forKeyCode: Self.f12, modifiers: .ctrl), Self.selectAll, "OK まではそのまま")
        let notified = expectation(forNotification: MainMenuBuilder.keyBindingsDidChangeNotification, object: nil)
        controller.ok(nil)
        wait(for: [notified], timeout: 1)
        XCTAssertEqual(EditorCore.command(forKeyCode: Self.f12, modifiers: .ctrl), Self.selectAll)
        XCTAssertEqual(EditorCore.commonSetting(section: "KeyBind", key: "KeyBind[000]"), original)
        // 菜单的快捷键：すべて選択 は Ctrl+A（⌘A）が先
        XCTAssertNotNil(KeyCommands.menuKeyEquivalent(for: Self.selectAll, scheme: .windows))
    }

    /// 別のページで変えたカスタムメニュー名も、戻ってきたとき機能一覧に出る（原版 PSN_SETACTIVE。同じ複製）
    func testPagesShareOneCopy() throws {
        let (controller, page) = try open()
        defer { controller.cancel(nil) }
        let editor = try XCTUnwrap(controller.values.commandEditor)
        editor.setFunction(Self.selectAll, ofKey: 0, modifiers: 1)
        let other = try XCTUnwrap(controller.pageIndex(named: "全般"))
        let index = try XCTUnwrap(controller.pageIndex(named: "キー割り当て"))
        controller.showPage(other)
        controller.showPage(index)
        click(page, "IDC_CHECK_SHIFT")
        select(page, "IDC_LIST_KEY", 0)
        XCTAssertEqual(page.text("IDC_EDIT_KEYSFUNC"), "すべて選択")
    }

    /// インポート・エクスポート（*.key）：読み込んだ割り当てはページに出て、OK で書く
    func testImportExport() throws {
        let saved = (TypeSettingsPages.chooseImportFile, TypeSettingsPages.chooseExportFile, TypeSettingsPages.showMessage)
        defer { (TypeSettingsPages.chooseImportFile, TypeSettingsPages.chooseExportFile, TypeSettingsPages.showMessage) = saved }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("KeyBindTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appendingPathComponent("test.key").path
        var messages: [String] = []
        TypeSettingsPages.showMessage = { messages.append($0) }
        TypeSettingsPages.chooseExportFile = { _, extensions, _ in extensions == ["key"] ? path : nil }
        TypeSettingsPages.chooseImportFile = { extensions, _ in extensions == ["key"] ? path : nil }

        // 書き出すほう：F12 に すべて選択 を割り当ててエクスポート
        let (controller, page) = try open()
        let f12 = try keyRow(page, "F12")
        controller.values.commandEditor?.setFunction(Self.selectAll, ofKey: f12, modifiers: 0)
        press(page, "IDC_BUTTON_EXPORT")
        XCTAssertEqual(messages.last, "ファイルをエクスポートしました。\n\n" + path)
        controller.cancel(nil)
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) ?? ""
        XCTAssertTrue(text.contains("KEYBIND_VERSION"), text)

        // 読み込むほう
        let (other, otherPage) = try open()
        select(otherPage, "IDC_LIST_KEY", f12)
        XCTAssertNotEqual(otherPage.text("IDC_EDIT_KEYSFUNC"), "すべて選択")
        press(otherPage, "IDC_BUTTON_IMPORT")
        select(otherPage, "IDC_LIST_KEY", f12)
        XCTAssertEqual(otherPage.text("IDC_EDIT_KEYSFUNC"), "すべて選択")
        other.ok(nil)
        XCTAssertTrue(store.values[String(format: "KeyBind/KeyBind[%03d]", f12)]?.contains(",\(Self.selectAll),") ?? false)

        // 開けないファイル：原版のメッセージ
        TypeSettingsPages.chooseImportFile = { _, _ in folder.appendingPathComponent("none.key").path }
        let (third, thirdPage) = try open()
        defer { third.cancel(nil) }
        press(thirdPage, "IDC_BUTTON_IMPORT")
        XCTAssertTrue(messages.last?.hasPrefix("ファイルを開けませんでした。") ?? false, messages.last ?? "")
    }
}

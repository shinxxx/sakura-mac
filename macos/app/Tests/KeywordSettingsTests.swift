// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge
import XCTest

/// 共通設定 > 強調キーワード（计划第 40 步第 3 个 PR。原版 CPropKeyword）。
///
/// - セット・キーワードの追加・編集・削除・整理・インポート・エクスポート、英大文字小文字区別
/// - OK で [KeyWords] の値を書く。セットを削除するとそれを使うタイプ別設定の強調キーワードも直す
/// - タイプ別設定 > カラー の「共通設定...」から開く対話框
final class KeywordSettingsTests: XCTestCase {
    private var store: CommonSettingsTests.FakeStore!
    private var inputs: [String?] = []
    private var asked: [String] = []
    private var savedInput: ((String, String, Int, String) -> String?)!
    private var savedConfirm: ((String) -> Bool)!
    private var savedInform: ((String) -> Void)!

    override func setUp() {
        _ = TestCore.home
        _ = NSApplication.shared
        store = CommonSettingsTests.FakeStore()
        savedInput = CommonSettingsPages.input
        savedConfirm = CommonSettingsPages.confirm
        savedInform = CommonSettingsPages.inform
        CommonSettingsPages.input = { [unowned self] title, _, _, _ in
            self.asked.append(title)
            return self.inputs.isEmpty ? nil : self.inputs.removeFirst()
        }
        CommonSettingsPages.confirm = { [unowned self] message in self.asked.append(message); return true }
        CommonSettingsPages.inform = { [unowned self] message in self.asked.append(message) }
    }

    override func tearDown() {
        CommonSettingsPages.input = savedInput
        CommonSettingsPages.confirm = savedConfirm
        CommonSettingsPages.inform = savedInform
    }

    private func open() throws -> (CommonSettingsWindowController, PropPage) {
        let probe = try XCTUnwrap(CommonSettingsWindowController(store: store))
        let index = try XCTUnwrap(probe.pageIndex(named: "強調キーワード"))
        probe.cancel(nil)
        let controller = try XCTUnwrap(CommonSettingsWindowController(store: store, page: index))
        return (controller, controller.page(index))
    }

    private func click(_ page: PropPage, _ id: String, _ on: Bool = true) {
        page.setChecked(id, on)
        page.onChange?(id)
    }

    private func key(_ name: String) -> String { "KeyWords/\(name)" }

    // MARK: -

    /// セット名の一覧、選んだセットのキーワード（並べた順）、件数の表示。共通設定のページでは OK・キャンセル はない
    func testPageShowsSets() throws {
        let (controller, page) = try open()
        defer { controller.cancel(nil) }
        let names = EditorCore.keywordSetNames
        XCTAssertEqual(page.itemTitles("IDC_COMBO_SET"), names)
        XCTAssertFalse(page.isShown("IDOK"))
        XCTAssertNil(page.list("IDC_LIST_KEYWORD")?.table.headerView, "原版は列の見出しなし（LVS_NOCOLUMNHEADER）")
        let editor = EditorKeywordSetEditor()!
        let set = editor.currentSet
        XCTAssertEqual(page.selectedTag("IDC_COMBO_SET"), set)
        XCTAssertEqual(page.list("IDC_LIST_KEYWORD")?.rows.map { $0[0] }, editor.keywords(ofSet: set))
        XCTAssertTrue(page.text("IDC_STATIC_KEYWORD_COUNT").hasPrefix("(最大 63 文字, 登録数 \(editor.keywords(ofSet: set).count), 空き "))
        XCTAssertFalse(page.isEnabled("IDC_BUTTON_EDITKEYWORD"), "選んでいないときは編集できない")
        // 別のセットに換える
        (page.control("IDC_COMBO_SET") as? NSPopUpButton)?.selectItem(withTag: 1)
        page.onChange?("IDC_COMBO_SET")
        XCTAssertEqual(page.list("IDC_LIST_KEYWORD")?.rows.map { $0[0] }, editor.keywords(ofSet: 1))
    }

    /// セットの追加・名称変更、キーワードの追加・編集・削除、英大文字小文字区別。OK で [KeyWords] に書く
    func testEditSetsAndKeywords() throws {
        let (controller, page) = try open()
        let count = EditorCore.keywordSetNames.count
        inputs = ["MacSet"]
        page.onButton?("IDC_BUTTON_ADDSET")
        XCTAssertEqual(page.itemTitles("IDC_COMBO_SET").last, "MacSet")
        XCTAssertEqual(page.selectedTag("IDC_COMBO_SET"), count, "追加したセットを選ぶ")
        XCTAssertEqual(page.list("IDC_LIST_KEYWORD")?.rows.count, 0)
        inputs = ["zeta", "alpha", "alpha"]
        page.onButton?("IDC_BUTTON_ADDKEYWORD")
        page.onButton?("IDC_BUTTON_ADDKEYWORD")
        page.onButton?("IDC_BUTTON_ADDKEYWORD")	// 重複は登録しない
        let list = try XCTUnwrap(page.list("IDC_LIST_KEYWORD"))
        XCTAssertEqual(list.rows.map { $0[0] }, ["alpha", "zeta"])
        // 編集（ダブルクリック）
        list.select(1)
        page.onChange?("IDC_LIST_KEYWORD")
        XCTAssertTrue(page.isEnabled("IDC_BUTTON_EDITKEYWORD"))
        inputs = ["beta"]
        list.onDoubleClick?(1, 0)
        XCTAssertEqual(list.rows.map { $0[0] }, ["alpha", "beta"])
        // 空にすると削除
        list.select(0)
        inputs = [""]
        page.onButton?("IDC_BUTTON_EDITKEYWORD")
        XCTAssertEqual(list.rows.map { $0[0] }, ["beta"])
        inputs = ["Mac2"]
        page.onButton?("IDC_BUTTON_KEYSETRENAME")
        XCTAssertEqual(page.itemTitles("IDC_COMBO_SET").last, "Mac2")
        click(page, "IDC_CHECK_KEYWORDCASE")
        controller.ok(nil)
        let index = String(format: "%02d", count)
        XCTAssertEqual(store.values[key("nKeyWordSetNum")], String(count + 1))
        XCTAssertEqual(store.values[key("szSN[\(index)]")], "Mac2")
        XCTAssertEqual(store.values[key("nCASE[\(index)]")], "1")
        XCTAssertEqual(store.values[key("nKWN[\(index)]")], "1")
        XCTAssertEqual(store.values[key("szKW[\(index)]")], "beta\t")
        XCTAssertNil(store.values[key("szSN[00]")], "変えていないセットは書かない")
    }

    /// セットの削除：使っているタイプを示して確認、タイプの強調キーワードは「なし」、後ろのセットは 1 つ前
    func testDeleteSetAdjustsTypes() throws {
        let types = EditorCore.typeSettings
        let text = try XCTUnwrap(types.first { $0.name == "テキスト" }).index
        let section = "Types(\(text))"
        store.values["\(section)/nInts"] = "\(text),120,0,4,0,1,0,1,1,0,0,0"
        store.values["\(section)/nKeywordSelect3"] = "2"
        let (controller, page) = try open()
        (page.control("IDC_COMBO_SET") as? NSPopUpButton)?.selectItem(withTag: 0)
        page.onChange?("IDC_COMBO_SET")
        page.onButton?("IDC_BUTTON_DELSET")
        let message = try XCTUnwrap(asked.last)
        XCTAssertTrue(message.hasPrefix("「\(EditorCore.keywordSetNames[0])」のセットを削除します。"), message)
        XCTAssertTrue(message.contains("・テキスト("), message)
        XCTAssertEqual(page.itemTitles("IDC_COMBO_SET"), Array(EditorCore.keywordSetNames.dropFirst()))
        controller.ok(nil)
        XCTAssertEqual(store.values["\(section)/nInts"], "\(text),120,0,4,-1,0,0,1,1,0,0,0")
        XCTAssertEqual(store.values["\(section)/nKeywordSelect3"], "1")
        let last = String(format: "%02d", EditorCore.keywordSetNames.count - 1)
        XCTAssertEqual(store.values[key("szSN[\(last)]")], "", "なくなったセットの項目は空")
    }

    /// 整理（確認して重複を削除）、インポート・エクスポート（*.kwd）
    func testCleanImportExport() throws {
        let dir = TestCore.home.appendingPathComponent("keywords")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("a.kwd").path
        try "// test キーワード定義ファイル\n// CASE=True\n\nfoo\nbar\nfoo\n".write(toFile: path, atomically: true, encoding: .utf8)
        let saved = (TypeSettingsPages.chooseImportFile, TypeSettingsPages.chooseExportFile, TypeSettingsPages.showMessage)
        defer { (TypeSettingsPages.chooseImportFile, TypeSettingsPages.chooseExportFile, TypeSettingsPages.showMessage) = saved }
        var messages: [String] = []
        TypeSettingsPages.showMessage = { messages.append($0) }
        TypeSettingsPages.chooseImportFile = { extensions, _ in extensions == ["kwd"] ? path : nil }
        let exported = dir.appendingPathComponent("b.kwd").path
        var defaultName = ""
        TypeSettingsPages.chooseExportFile = { name, extensions, _ in defaultName = name; return extensions == ["kwd"] ? exported : nil }

        let (controller, page) = try open()
        defer { controller.cancel(nil) }
        inputs = ["Imp"]
        page.onButton?("IDC_BUTTON_ADDSET")
        page.onButton?("IDC_BUTTON_IMPORT")
        XCTAssertEqual(page.list("IDC_LIST_KEYWORD")?.rows.map { $0[0] }, ["bar", "foo"], "重複は登録しない")
        XCTAssertTrue(page.isChecked("IDC_CHECK_KEYWORDCASE"), "CASE=True")
        inputs = ["FOO"]
        page.onButton?("IDC_BUTTON_ADDKEYWORD")
        click(page, "IDC_CHECK_KEYWORDCASE", false)
        page.onButton?("IDC_BUTTON_KEYCLEAN")
        XCTAssertTrue(asked.last?.hasPrefix("現在の設定では強調キーワードとして表示できないキーワード") ?? false)
        XCTAssertEqual(page.list("IDC_LIST_KEYWORD")?.rows.count, 2, "大文字小文字を区別しないので FOO と foo は重複")
        page.onButton?("IDC_BUTTON_EXPORT")
        XCTAssertEqual(defaultName, "Imp")
        XCTAssertTrue(messages.last?.hasPrefix("ファイルをエクスポートしました。") ?? false, "\(messages)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: exported))
    }

    /// タイプ別設定 > カラー の「共通設定...」：その場で共通設定に書き、このタイプのセットの一覧も新しくなる
    func testOpenFromTypeColorPage() throws {
        let cpp = try XCTUnwrap(EditorCore.typeSettings.first { $0.name == "C/C++" }).index
        let typeStore = CommonSettingsTests.FakeStore()
        let controller = try XCTUnwrap(TypeSettingsWindowController(store: typeStore, typeIndex: cpp, page: 1))
        defer { controller.cancel(nil) }
        let page = controller.page(1)
        let saved = TypeSettingsPages.runKeywordSettingsDialog
        defer { TypeSettingsPages.runKeywordSettingsDialog = saved }
        var title = ""
        TypeSettingsPages.runKeywordSettingsDialog = { [unowned self] dialog, _ in
            title = dialog.title
            XCTAssertTrue(dialog.page.isShown("IDOK"), "独立ウィンドウには OK がある")
            self.inputs = ["FromType"]
            dialog.page.onButton?("IDC_BUTTON_ADDSET")
            return true
        }
        let before = EditorCore.keywordSetNames.count
        page.onButton?("IDC_BUTTON_EDITKEYWORD")
        XCTAssertEqual(title, "共通設定 - 強調キーワード")
        XCTAssertEqual(EditorCore.keywordSetNames.last, "FromType", "その場で共通設定に書く")
        XCTAssertEqual(page.itemTitles("IDC_COMBO_SET").last, "FromType")

        // 元に戻す
        TypeSettingsPages.runKeywordSettingsDialog = { dialog, _ in
            (dialog.page.control("IDC_COMBO_SET") as? NSPopUpButton)?.selectItem(withTag: before)
            dialog.page.onChange?("IDC_COMBO_SET")
            dialog.page.onButton?("IDC_BUTTON_DELSET")
            return true
        }
        page.onButton?("IDC_BUTTON_EDITKEYWORD")
        XCTAssertEqual(EditorCore.keywordSetNames.count, before)
    }
}

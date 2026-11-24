// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge
import XCTest

/// 共通設定 > メインメニュー（计划第 41 步第 2 个 PR。原版 CPropMainMenu）。
///
/// - ツリー：原版の MainMenu.ini と同じ階層・名前・アクセスキー（「ファイル(F)」）
/// - 削除・＋・---・上⇒・下⇒・>>・↑↓→←、ボタンの有効・無効、アクセスキー（ダブルクリック・文字キー）、名前の編集
/// - 検査（重複・未設定・『共通設定』が無い）、クリア・初期設定、インポート・エクスポート
/// - OK で [MainMenu] に書く（「共通設定」が無いと最後に追加）。真的核心库：菜单栏を作り直す通知
final class MainMenuSettingsTests: XCTestCase {
    private var store: CommonSettingsTests.FakeStore!
    private var inputs: [String?] = []
    private var asked: [String] = []
    private var saved: (input: ((String, String, Int, String) -> String?), confirm: ((String) -> Bool), inform: ((String) -> Void))!

    override func setUp() {
        _ = TestCore.home
        _ = NSApplication.shared
        store = CommonSettingsTests.FakeStore()
        saved = (CommonSettingsPages.input, CommonSettingsPages.confirm, CommonSettingsPages.inform)
        CommonSettingsPages.input = { [unowned self] title, _, _, _ in
            self.asked.append(title)
            return self.inputs.isEmpty ? nil : self.inputs.removeFirst()
        }
        CommonSettingsPages.confirm = { [unowned self] message in self.asked.append(message); return true }
        CommonSettingsPages.inform = { [unowned self] message in self.asked.append(message) }
    }

    override func tearDown() {
        (CommonSettingsPages.input, CommonSettingsPages.confirm, CommonSettingsPages.inform) = saved
    }

    private func open(store: CommonSettingsStore? = nil) throws -> (CommonSettingsWindowController, PropPage, PropTree) {
        let store = store ?? self.store!
        let probe = try XCTUnwrap(CommonSettingsWindowController(store: store))
        let index = try XCTUnwrap(probe.pageIndex(named: "メインメニュー"))
        probe.cancel(nil)
        let controller = try XCTUnwrap(CommonSettingsWindowController(store: store, page: index))
        let page = controller.page(index)
        return (controller, page, try XCTUnwrap(page.tree("IDC_TREE_RES")))
    }

    private func press(_ page: PropPage, _ id: String) {
        page.onButton?(id)
    }

    private func selectCategory(_ page: PropPage, _ name: String) throws {
        page.select("IDC_COMBO_FUNCKIND", try XCTUnwrap(page.itemTitles("IDC_COMBO_FUNCKIND").firstIndex(of: name)))
        page.onChange?("IDC_COMBO_FUNCKIND")
    }

    private func selectFunction(_ page: PropPage, _ name: String) throws {
        page.list("IDC_LIST_FUNC")?.select(try XCTUnwrap(page.list("IDC_LIST_FUNC")?.rows.firstIndex { $0[0] == name }, name))
    }

    private func node(_ tree: PropTree, _ path: String...) throws -> MainMenuPage.MenuNode {
        var nodes = tree.roots
        var found: PropTreeNode?
        for title in path {
            found = try XCTUnwrap(nodes.first { $0.title == title }, title)
            nodes = found?.children ?? []
        }
        return try XCTUnwrap(found as? MainMenuPage.MenuNode)
    }

    private func titles(_ nodes: [PropTreeNode]) -> [String] { nodes.map(\.title) }

    // MARK: -

    /// 開いたとき：原版の MainMenu.ini の階層、種別の最後は「特別機能」
    func testPageShowsTree() throws {
        let (controller, page, tree) = try open()
        defer { controller.cancel(nil) }
        XCTAssertEqual(titles(tree.roots).prefix(3), ["ファイル(F)", "編集(E)", "変換(C)"])
        let file = try node(tree, "ファイル(F)")
        XCTAssertTrue(file.isNode)
        XCTAssertEqual(file.children.first?.title, "新規作成(N)")
        XCTAssertTrue(titles(file.children).contains(MainMenuPage.separatorLabel))
        XCTAssertTrue(page.isChecked("IDC_CHECK_KEY_PARENTHESES"))
        XCTAssertEqual(page.itemTitles("IDC_COMBO_FUNCKIND").last, "特別機能")
        try selectCategory(page, "特別機能")
        XCTAssertTrue(page.list("IDC_LIST_FUNC")?.rows.map { $0[0] }.contains("最近使ったファイル") ?? false)
        // 何も選んでいない：削除・↑↓→← はできない、機能を選ぶと >> はできる
        XCTAssertFalse(page.isEnabled("IDC_BUTTON_DELETE"))
        XCTAssertFalse(page.isEnabled("IDC_BUTTON_ADD"))
        try selectFunction(page, "最近使ったファイル")
        page.onChange?("IDC_LIST_FUNC")
        XCTAssertTrue(page.isEnabled("IDC_BUTTON_ADD"))
        XCTAssertFalse(page.isEnabled("IDC_BUTTON_INSERT"))
        tree.select(file.children[1])
        XCTAssertTrue(page.isEnabled("IDC_BUTTON_UP"))
        XCTAssertTrue(page.isEnabled("IDC_BUTTON_LEFT"))
        XCTAssertTrue(page.isEnabled("IDC_BUTTON_INSERT"))
        tree.select(file)
        XCTAssertFalse(page.isEnabled("IDC_BUTTON_UP"), "最初の項目")
        XCTAssertFalse(page.isEnabled("IDC_BUTTON_LEFT"), "最上位")
    }

    /// ＋・---・上⇒・下⇒・>>（原版の挿入位置）、↑↓→←、削除
    func testEditTree() throws {
        let (controller, page, tree) = try open()
        defer { controller.cancel(nil) }
        try selectCategory(page, "ファイル操作系")
        let file = try node(tree, "ファイル(F)")
        let first = file.children[0]	// 新規作成

        // 下⇒：子菜单を選んでいるときは最初の下位項目、次の機能を選ぶ
        tree.select(file)
        try selectFunction(page, "開く...")
        press(page, "IDC_BUTTON_INSERT_A")
        XCTAssertEqual(file.children[0].title, "開く...")
        XCTAssertTrue(tree.selectedNode === file.children[0])
        XCTAssertEqual(page.list("IDC_LIST_FUNC")?.selectedRow, (page.list("IDC_LIST_FUNC")?.rows.firstIndex { $0[0] == "開く..." } ?? -2) + 1)
        // 上⇒：前に
        tree.select(first)
        try selectFunction(page, "上書き保存")
        press(page, "IDC_BUTTON_INSERT")
        let index = try XCTUnwrap(file.children.firstIndex { $0 === first })
        XCTAssertEqual(file.children[index - 1].title, "上書き保存")
        // ---：前に区切線
        tree.select(first)
        press(page, "IDC_BUTTON_INSERTSEPARATOR")
        XCTAssertEqual(file.children[index].title, MainMenuPage.separatorLabel)
        // ＋：命令を選んでいるときは次に、名前は「編集してください」
        tree.select(first)
        press(page, "IDC_BUTTON_INSERT_NODE")
        let newNode = try XCTUnwrap(tree.selectedNode as? MainMenuPage.MenuNode)
        XCTAssertEqual(newNode.title, "編集してください")
        XCTAssertTrue(newNode.isNode)
        XCTAssertTrue(newNode.parent === file)
        // >>：子菜单を選んでいるときは最後の下位項目
        try selectFunction(page, "閉じて(無題)")
        press(page, "IDC_BUTTON_ADD")
        XCTAssertEqual(titles(newNode.children), ["閉じて(無題)"])
        let closeItem = newNode.children[0]
        // ←：親の次に、→：前の子菜单の最後に
        tree.select(closeItem)
        press(page, "IDC_BUTTON_LEFT")
        XCTAssertTrue(closeItem.parent === file)
        XCTAssertTrue(file.children[(file.children.firstIndex { $0 === newNode } ?? -2) + 1] === closeItem)
        press(page, "IDC_BUTTON_RIGHT")
        XCTAssertTrue(closeItem.parent === newNode)
        // ↑↓
        tree.select(newNode)
        let before = try XCTUnwrap(file.children.firstIndex { $0 === newNode })
        press(page, "IDC_BUTTON_UP")
        XCTAssertTrue(file.children[before - 1] === newNode)
        press(page, "IDC_BUTTON_DOWN")
        XCTAssertTrue(file.children[before] === newNode)
        // 削除：下位項目があるときは確認、次の項目を選ぶ
        let next = file.children[before + 1]
        asked.removeAll()
        press(page, "IDC_BUTTON_DELETE")
        XCTAssertEqual(asked, ["選択している項目を下位項目ごと削除します。\nよろしいですか？"])
        XCTAssertFalse(file.children.contains { $0 === newNode })
        XCTAssertTrue(tree.selectedNode === next)
    }

    /// アクセスキー（ダブルクリックの入力、文字キー）、子菜单の名前（F2）、検査
    func testAccessKeysAndCheck() throws {
        let (controller, page, tree) = try open()
        defer { controller.cancel(nil) }
        // 原版の MainMenu.ini にもアクセスキーの無い項目があるので、小さいメニューで確かめる
        let file = MainMenuPage.MenuNode(code: 34052, name: "ファイル", accessKey: "F", isNode: true)
        for (code, name, key) in [(30101, "新規作成", "N"), (30102, "開く...", "O")] {
            let item = MainMenuPage.MenuNode(code: code, name: name, accessKey: key, isNode: false)
            item.parent = file
            file.children.append(item)
        }
        let settings = MainMenuPage.MenuNode(code: 34057, name: "設定", accessKey: "O", isNode: true)
        let option = MainMenuPage.MenuNode(code: 31112, name: "共通設定...", accessKey: "C", isNode: false)
        option.parent = settings
        settings.children = [option]
        tree.roots = [file, settings]
        tree.reload()
        let first = try XCTUnwrap(file.children[0] as? MainMenuPage.MenuNode)
        inputs = ["Z"]
        tree.onDoubleClick?(first)
        XCTAssertEqual(asked.last, "メニューアイテムのアクセスキー設定")
        XCTAssertEqual(first.title, "新規作成(Z)")
        tree.select(first)
        XCTAssertTrue(tree.outline.onCharacter?("Q") ?? false)
        XCTAssertEqual(first.title, "新規作成(Q)")
        // 名前の編集（子菜单だけ）：F_NODE になる
        tree.select(file)
        inputs = ["File"]
        tree.outline.onRename?()
        XCTAssertEqual(file.title, "File(F)")
        XCTAssertEqual(file.code, 0)

        // 検査：問題なし
        asked.removeAll()
        press(page, "IDC_BUTTON_CHECK")
        XCTAssertEqual(asked, ["問題ありませんでした。"])
        // 重複したアクセスキー：両方に「>」、最初のほうを選ぶ
        let second = try XCTUnwrap(file.children[1] as? MainMenuPage.MenuNode)
        tree.select(second)
        _ = tree.outline.onCharacter?("Q")
        press(page, "IDC_BUTTON_CHECK")
        XCTAssertEqual(asked.last, "重複したアクセスキーがあります。\n")
        XCTAssertTrue(first.title.hasPrefix(">"))
        XCTAssertTrue(second.title.hasPrefix(">"))
        XCTAssertTrue(tree.selectedNode === first)
        // 未設定、『共通設定』が無い
        _ = tree.outline.onCharacter?("Y")	// first を Y に
        second.accessKey = ""
        tree.roots.removeAll { $0 === settings }
        press(page, "IDC_BUTTON_CHECK")
        XCTAssertEqual(asked.last, "『共通設定』が有りません。\n未設定のアクセスキーがあります。\n")
    }

    /// OK：[MainMenu] に書く。クリアしても「共通設定」は自動で追加。初期設定で元に戻る
    func testClearInitializeAndOK() throws {
        let (controller, page, tree) = try open()
        press(page, "IDC_BUTTON_CLEAR")
        XCTAssertEqual(tree.roots.count, 0)
        try selectCategory(page, "ファイル操作系")
        try selectFunction(page, "新規作成")
        press(page, "IDC_BUTTON_ADD")
        page.setChecked("IDC_CHECK_KEY_PARENTHESES", false)
        controller.ok(nil)
        XCTAssertEqual(store.values["MainMenu/nMainMenuNum"], "3")	// 新規作成、auto_add、共通設定
        XCTAssertEqual(store.values["MainMenu/MM[000]"], "0,1,30101,,")
        XCTAssertEqual(store.values["MainMenu/MM[001]"], "0,0,0,,auto_add")
        XCTAssertEqual(store.values["MainMenu/MM[002]"], "1,1,31112,,")
        XCTAssertEqual(store.values["MainMenu/MM[003]"], "", "減った項目")
        XCTAssertEqual(store.values["MainMenu/bKeyParentheses"], "0")

        // 初期設定
        let (other, otherPage, otherTree) = try open()
        defer { other.cancel(nil) }
        otherTree.roots = []
        press(otherPage, "IDC_BUTTON_INITIALIZE")
        XCTAssertEqual(asked.last, "メニューの設定を初期状態に戻します。\nよろしいですか？")
        XCTAssertEqual(otherTree.roots.first?.title, "ファイル(F)")
    }

    /// 真的核心库：OK で MainMenu() が変わり、菜单栏を作り直す通知
    func testOKAppliesToCore() throws {
        let before = EditorCore.mainMenu.count
        let third = EditorCore.mainMenu[2].command
        let originalValues = try XCTUnwrap(EditorCommandSettingsEditor()).iniValues(section: "MainMenu")
        defer { XCTAssertTrue(EditorCore.setCommonSettings(originalValues, section: "MainMenu")) }
        let (controller, page, tree) = try open(store: CoreCommonSettingsStore())
        let file = try node(tree, "ファイル(F)")
        tree.select(file.children[0])
        press(page, "IDC_BUTTON_DELETE")
        let notified = expectation(forNotification: MainMenuBuilder.mainMenuDidChangeNotification, object: nil)
        controller.ok(nil)
        wait(for: [notified], timeout: 1)
        XCTAssertEqual(EditorCore.mainMenu.count, before - 1)
        XCTAssertEqual(EditorCore.mainMenu[1].command, third)
    }

    /// インポート・エクスポート（*.ini）
    func testImportExport() throws {
        let savedFiles = (TypeSettingsPages.chooseImportFile, TypeSettingsPages.chooseExportFile, TypeSettingsPages.showMessage)
        defer { (TypeSettingsPages.chooseImportFile, TypeSettingsPages.chooseExportFile, TypeSettingsPages.showMessage) = savedFiles }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MainMenuTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appendingPathComponent("menu.ini").path
        var messages: [String] = []
        TypeSettingsPages.showMessage = { messages.append($0) }
        TypeSettingsPages.chooseExportFile = { _, extensions, _ in extensions == ["ini"] ? path : nil }
        TypeSettingsPages.chooseImportFile = { extensions, _ in extensions == ["ini"] ? path : nil }

        let (controller, page, tree) = try open()
        press(page, "IDC_BUTTON_CLEAR")
        press(page, "IDC_BUTTON_EXPORT")	// GetData してから：共通設定 が追加されたもの
        XCTAssertEqual(messages.last, "ファイルをエクスポートしました。\n\n" + path)
        XCTAssertEqual(tree.roots.count, 0, "ツリーはそのまま")
        controller.cancel(nil)

        let (other, otherPage, otherTree) = try open()
        defer { other.cancel(nil) }
        press(otherPage, "IDC_BUTTON_IMPORT")
        XCTAssertEqual(titles(otherTree.roots), ["auto_add"])
        XCTAssertEqual(otherTree.roots[0].children.count, 1)
    }
}

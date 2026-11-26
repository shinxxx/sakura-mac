// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge
import XCTest

/// ファイルツリー（计划第 43 步）的窗口、设置对话框的测试。
///
/// 設定の読み込み・パスの展開・フォルダーの枚举・保存・インポート/エクスポートは核心库で测试（macos/core/tests/test-mac-filetree.cpp）。
/// ここで確かめる：アウトラインの窗口のファイルツリー（原版 CDlgFuncList の OUTLINE_FILETREE：項目、開くと中を読む、ファイルを開く、
/// 「設定」ボタン）、ファイルツリー設定（原版 CDlgFileTree：外観、項目の編集、OK の保存、読み込み、インポート・エクスポート）。
final class FileTreeTests: XCTestCase {
    private var documents: [SakuraDocument] = []
    private var directory: URL!
    private var savedSetting: FileTreeSetting!
    private var savedUseType = false
    private var savedCommon: [String: String] = [:]
    private var opened: [URL] = []
    private var informed: [String] = []
    private var confirmAnswer = true
    /// 差し替えた hook（終わったら戻す）
    private let savedOpen = EditorTextView.openForTagJump
    private let savedInform = CommonSettingsPages.inform
    private let savedConfirm = CommonSettingsPages.confirm
    private let savedInput = CommonSettingsPages.input
    private let savedShowMessage = TypeSettingsPages.showMessage
    private let savedImport = TypeSettingsPages.chooseImportFile
    private let savedExport = TypeSettingsPages.chooseExportFile
    private let savedChooseFiles = FileTreeDialogController.chooseFiles

    override func setUpWithError() throws {
        _ = TestCore.home
        _ = NSApplication.shared
        OutlineWindowController.hidesOnDeactivate = false
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("filetree-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        savedUseType = OutlineDockSettings.useType
        OutlineDockSettings.useType = false
        savedCommon = ["bAutoCloseDlgFuncList": EditorCore.commonSetting(section: "Common", key: "bAutoCloseDlgFuncList") ?? "0"]
        _ = EditorCore.setCommonSettings(["bAutoCloseDlgFuncList": "0"], section: "Common")
        savedSetting = FileTreeCore.load(typeIndex: 0, folder: directory.path)
        opened = []
        EditorTextView.openForTagJump = { [unowned self] url, completion in
            opened.append(url)
            completion(nil, nil)
        }
        informed = []
        CommonSettingsPages.inform = { [unowned self] in informed.append($0) }
        TypeSettingsPages.showMessage = { [unowned self] in informed.append($0) }
        confirmAnswer = true
        CommonSettingsPages.confirm = { [unowned self] _ in confirmAnswer }
    }

    override func tearDown() {
        for document in documents {
            document.editorWindowController?.textView.outlinePanel?.close()
            document.close()
        }
        documents = []
        var truncated: ObjCBool = false
        savedSetting.loadedIni = ""
        _ = FileTreeCore.save(savedSetting, typeIndex: 0, truncated: &truncated)
        OutlineDockSettings.useType = savedUseType
        _ = EditorCore.setCommonSettings(savedCommon, section: "Common")
        FileTreeDialogController.runModal = nil
        EditorTextView.openForTagJump = savedOpen
        CommonSettingsPages.inform = savedInform
        CommonSettingsPages.confirm = savedConfirm
        CommonSettingsPages.input = savedInput
        TypeSettingsPages.showMessage = savedShowMessage
        TypeSettingsPages.chooseImportFile = savedImport
        TypeSettingsPages.chooseExportFile = savedExport
        FileTreeDialogController.chooseFiles = savedChooseFiles
        try? FileManager.default.removeItem(at: directory)
    }

    private func path(_ name: String) -> String { directory.appendingPathComponent(name).path }

    private func write(_ name: String, _ text: String = "x") throws {
        let url = directory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func item(_ type: FileTreeItemType, path: String = "", label: String = "", depth: Int = 0, file: String = "*.*") -> FileTreeItem {
        let item = FileTreeItem()
        item.type = type
        item.path = path
        item.label = label
        item.depth = depth
        item.file = file
        return item
    }

    /// 共通設定の項目にする（各フォルダーの設定は読まない）
    private func setCommonItems(_ items: [FileTreeItem], project: Bool = false) {
        let setting = FileTreeCore.load(typeIndex: 0, folder: directory.path)
        setting.loadedIni = ""
        setting.project = project
        setting.defaultProjectIni = ""
        setting.items = items
        var truncated: ObjCBool = false
        XCTAssertEqual(FileTreeCore.save(setting, typeIndex: 0, truncated: &truncated), "")
    }

    /// このフォルダーのファイルを開いた窓口
    private func openView(_ name: String) throws -> EditorTextView {
        try write(name)
        let document = try SakuraDocument(contentsOf: directory.appendingPathComponent(name), ofType: "public.plain-text")
        document.makeWindowControllers()
        documents.append(document)
        return try XCTUnwrap(document.editorWindowController?.textView)
    }

    private func labels(_ outline: NSOutlineView) -> [String] {
        (0..<outline.numberOfRows).compactMap { (outline.item(atRow: $0) as? FileTreeNode)?.label }
    }

    private func node(_ outline: NSOutlineView, _ label: String) throws -> FileTreeNode {
        let row = try XCTUnwrap((0..<outline.numberOfRows).first { (outline.item(atRow: $0) as? FileTreeNode)?.label == label }, label)
        return try XCTUnwrap(outline.item(atRow: row) as? FileTreeNode)
    }

    private func dialog() throws -> FileTreeDialogController {
        try XCTUnwrap(FileTreeDialogController(typeIndex: 0, folder: directory.path))
    }

    // MARK: - アウトラインの窓口

    /// F_FILETREE：題名、ツリー、「設定」ボタン、順序は出さない。Grep の項目はフォルダー・ファイル（対象ファイルで絞る）
    func testOutlineFileTree() throws {
        try write("b.txt")
        try write("c.md")
        try write("Sub/s.txt")
        try FileManager.default.createDirectory(atPath: path("Empty"), withIntermediateDirectories: true)
        setCommonItems([item(.grep, path: ".", file: "*.txt"),
                        item(.folder, label: "G"),
                        item(.file, path: path("c.md"), label: "C", depth: 1)])
        let view = try openView("a.txt")
        view.showFileTree(nil)
        let panel = try XCTUnwrap(view.outlinePanel)
        XCTAssertEqual(panel.outlineType, .fileTree)
        XCTAssertEqual(panel.window?.title, "ファイルツリー")
        XCTAssertEqual(panel.page.control("IDC_BUTTON_SETTING")?.isHidden, false)
        XCTAssertEqual(panel.page.control("IDC_COMBO_nSortType")?.isHidden, true)
        XCTAssertEqual(panel.page.control("IDC_TREE_FL")?.isHidden, false)
        let outline = panel.treeView
        // 「.」は編集中のファイルのフォルダー（ラベルが空ならパス）
        XCTAssertEqual(labels(outline), [directory.path, "G"])
        let root = try node(outline, directory.path)
        outline.expandItem(root)
        XCTAssertEqual(labels(outline), [directory.path, "Empty", "Sub", "a.txt", "b.txt", "G"])
        // フォルダーの項目の下にファイルの項目
        outline.expandItem(try node(outline, "G"))
        XCTAssertEqual(labels(outline).suffix(2), ["G", "C"])
        // サブフォルダーは開くとき読む
        let sub = try node(outline, "Sub")
        XCTAssertNil(sub.children)
        outline.expandItem(sub)
        XCTAssertEqual(sub.children?.map(\.label), ["s.txt"])
        XCTAssertTrue(outline.isItemExpanded(sub))
        // 中が無いフォルダーは開かず [+] を消す（原版 SetTreeFileSub の count == 0）
        let empty = try node(outline, "Empty")
        XCTAssertTrue(outline.isExpandable(empty))
        outline.expandItem(empty)
        XCTAssertFalse(outline.isItemExpanded(empty))
        let deadline = Date().addingTimeInterval(3)
        while outline.isExpandable(empty) && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        XCTAssertFalse(outline.isExpandable(empty))
        // コピーは無い（原版 m_cmemClipText が空）
        panel.copyToPasteboard()
    }

    /// ファイルを開く（原版 OnJump の m_sJumpFile → TagJumpTimer）：Grep の中のファイル、ファイルの項目。フォルダーは開かない
    func testJumpToFile() throws {
        try write("b.txt")
        setCommonItems([item(.grep, path: "."), item(.file, path: "%%TEST%%/x.txt", label: "X")])
        let view = try openView("a.txt")
        view.showFileTree(nil)
        let panel = try XCTUnwrap(view.outlinePanel)
        let outline = panel.treeView
        outline.expandItem(try node(outline, directory.path))
        // フォルダーの行
        outline.selectRowIndexes(IndexSet(integer: outline.row(forItem: try node(outline, directory.path))), byExtendingSelection: false)
        panel.jump()
        XCTAssertEqual(opened, [])
        // ファイル
        outline.selectRowIndexes(IndexSet(integer: outline.row(forItem: try node(outline, "b.txt"))), byExtendingSelection: false)
        panel.jump()
        XCTAssertEqual(opened.map(\.path), [path("b.txt")])
        // ファイルの項目（%% は %）
        outline.selectRowIndexes(IndexSet(integer: outline.row(forItem: try node(outline, "X"))), byExtendingSelection: false)
        panel.jump()
        XCTAssertEqual(opened.last?.path, path("%TEST%/x.txt"))
    }

    /// 対象ファイルの書き方が正しくない（原版「<Wild Card Error>」）、「すべて展開」
    func testWildcardErrorAndExpandAll() throws {
        try write("Sub/Deep/d.txt")
        setCommonItems([item(.grep, path: ".", file: "*/x.txt"), item(.grep, path: ".", label: "OK")])
        let view = try openView("a.txt")
        view.showFileTree(nil)
        let panel = try XCTUnwrap(view.outlinePanel)
        let outline = panel.treeView
        outline.expandItem(try node(outline, directory.path))
        XCTAssertEqual(labels(outline), [directory.path, "<Wild Card Error>", "OK"])
        panel.menuExpandAll(nil)
        XCTAssertEqual(labels(outline), [directory.path, "<Wild Card Error>", "OK", "Sub", "Deep", "d.txt", "a.txt"])
    }

    /// 「設定」ボタン：OK なら読み直す（原版 HandleCommand( F_FILETREE, SHOW_RELOAD )）
    func testSettingButtonReloads() throws {
        setCommonItems([item(.grep, path: ".")])
        let view = try openView("a.txt")
        view.showFileTree(nil)
        let panel = try XCTUnwrap(view.outlinePanel)
        FileTreeDialogController.runModal = { dialog in
            dialog.page.setText("IDC_EDIT_LABEL", "New")
            dialog.press("IDC_BUTTON_UPDATE")
            dialog.press("IDOK")
            return true
        }
        panel.showFileTreeSettings()
        XCTAssertEqual(labels(panel.treeView), ["New"])
        // 再表示の種別はファイルツリーのまま（原版 GetOutlineTypeRedraw）
        panel.reload()
        XCTAssertEqual(try XCTUnwrap(view.outlinePanel).outlineType, .fileTree)
        XCTAssertEqual(OutlineWindowController.redrawType(.fileTree), .fileTree)
        XCTAssertEqual(OutlineWindowController.redrawType(.cpp), .default)
    }

    // MARK: - ファイルツリー設定（原版 CDlgFileTree）

    /// 原版の枠のまま Mac の文字を置いて切れない・重ならない（PropLayoutTests と同じ確かめ）
    func testDialogHasNoTruncatedText() throws {
        setCommonItems([item(.grep, path: ".")])
        let problems = PropLayoutTests.truncated(try dialog().page)
        XCTAssertEqual(problems, [], problems.joined(separator: "\n"))
    }

    /// 開いたとき（原版 SetDataInit・SetData・SetDataItem）と種類の切り替え（ChangeEnableItemType）
    func testDialogInitialValues() throws {
        setCommonItems([item(.grep, path: ".", file: "*.c"), item(.folder, label: ""), item(.file, path: "/x/y.txt", depth: 1)])
        let d = try dialog()
        let page = d.page
        XCTAssertEqual(d.title, "ファイルツリー設定")
        XCTAssertEqual(page.text("IDC_STATIC_SETTFING_FROM"), "設定: 共通設定")
        XCTAssertFalse(page.isChecked("IDC_CHECK_LOADINI"))
        XCTAssertTrue(page.isEnabled("IDC_BUTTON_LOAD"))
        let tree = try XCTUnwrap(d.tree)
        tree.expandAll(true)
        XCTAssertEqual(tree.visibleTitles, ["<カレントフォルダー>", "Folder", "/x/y.txt"])
        // 最初の項目を選んでいる
        XCTAssertTrue(page.isChecked("IDC_RADIO_GREP"))
        XCTAssertEqual(page.text("IDC_EDIT_PATH"), ".")
        XCTAssertEqual(page.text("IDC_EDIT_FILE"), "*.c")
        XCTAssertTrue(page.isChecked("IDC_CHECK_HIDDEN"))
        XCTAssertTrue(page.isEnabled("IDC_EDIT_FILE"))
        // ファイル：パスだけ
        page.setChecked("IDC_RADIO_FILE", true)
        d.page.onChange?("IDC_RADIO_FILE")
        XCTAssertTrue(page.isEnabled("IDC_EDIT_PATH"))
        XCTAssertFalse(page.isEnabled("IDC_EDIT_FILE"))
        XCTAssertFalse(page.isEnabled("IDC_CHECK_HIDDEN"))
        // フォルダー：ラベルだけ
        page.setChecked("IDC_RADIO_FOLDER", true)
        d.page.onChange?("IDC_RADIO_FOLDER")
        XCTAssertFalse(page.isEnabled("IDC_EDIT_PATH"))
        XCTAssertFalse(page.isEnabled("IDC_BUTTON_REF2"))
        XCTAssertTrue(page.isEnabled("IDC_EDIT_LABEL"))
        // 子のあるフォルダーを選んで、フォルダー以外にすると「更新」できない
        tree.select(tree.roots[1])
        XCTAssertTrue(page.isChecked("IDC_RADIO_FOLDER"))
        page.setChecked("IDC_RADIO_GREP", true)
        d.page.onChange?("IDC_RADIO_GREP")
        XCTAssertFalse(page.isEnabled("IDC_BUTTON_UPDATE"))
        page.setChecked("IDC_RADIO_FOLDER", true)
        d.page.onChange?("IDC_RADIO_FOLDER")
        XCTAssertTrue(page.isEnabled("IDC_BUTTON_UPDATE"))
    }

    /// 項目の編集（原版 IDC_BUTTON_INSERT・INSERT_A・ADD・UPDATE・DELETE・UP・DOWN・RIGHT・LEFT）と OK の保存（GetData）
    func testDialogEditing() throws {
        setCommonItems([item(.grep, path: "A"), item(.folder, label: "F"), item(.grep, path: "B", depth: 1)])
        let d = try dialog()
        let page = d.page
        let tree = try XCTUnwrap(d.tree)
        func titles() -> [String] {
            tree.expandAll(true)
            return tree.visibleTitles
        }
        func set(_ type: String, path: String = "", label: String = "") {
            page.setChecked(type, true)
            page.onChange?(type)
            page.setText("IDC_EDIT_PATH", path)
            page.setText("IDC_EDIT_LABEL", label)
        }
        // A を選んで 上⇒：前に
        tree.select(tree.roots[0])
        set("IDC_RADIO_GREP", path: "P1")
        d.press("IDC_BUTTON_INSERT")
        XCTAssertEqual(titles(), ["P1", "A", "F", "B"])
        // P1 を選んで 下⇒：次に
        set("IDC_RADIO_FILE", path: "P2")
        d.press("IDC_BUTTON_INSERT_A")
        XCTAssertEqual(titles(), ["P1", "P2", "A", "F", "B"])
        // フォルダーを選んで 下⇒：最初の子、>>：最後の子
        tree.select(tree.roots[3])
        set("IDC_RADIO_GREP", path: "P3")
        d.press("IDC_BUTTON_INSERT_A")
        XCTAssertEqual(titles(), ["P1", "P2", "A", "F", "P3", "B"])
        tree.select(tree.roots[3])
        set("IDC_RADIO_GREP", path: "P4")
        d.press("IDC_BUTTON_ADD")
        XCTAssertEqual(titles(), ["P1", "P2", "A", "F", "P3", "B", "P4"])
        // フォルダー以外で >>：同じ階層の最後
        tree.select(tree.roots[0])
        set("IDC_RADIO_FOLDER", label: "F2")
        d.press("IDC_BUTTON_ADD")
        XCTAssertEqual(titles(), ["P1", "P2", "A", "F", "P3", "B", "P4", "F2"])
        // 更新：選んでいる項目を書き換える
        tree.select(tree.roots[1])
        set("IDC_RADIO_FILE", path: "P2", label: "Two")
        d.press("IDC_BUTTON_UPDATE")
        XCTAssertEqual(titles(), ["P1", "Two", "A", "F", "P3", "B", "P4", "F2"])
        // ↑↓：同じ階層で入れ替え
        d.press("IDC_BUTTON_UP")
        XCTAssertEqual(titles(), ["Two", "P1", "A", "F", "P3", "B", "P4", "F2"])
        d.press("IDC_BUTTON_UP")	// 最初なので何もしない
        d.press("IDC_BUTTON_DOWN")
        XCTAssertEqual(titles(), ["P1", "Two", "A", "F", "P3", "B", "P4", "F2"])
        // →：直前がフォルダーならその最後の子に。←：親の次に
        let f2 = tree.roots.last!
        let p4 = tree.roots[3].children.last!
        tree.select(p4)
        d.press("IDC_BUTTON_LEFT")
        XCTAssertEqual(titles(), ["P1", "Two", "A", "F", "P3", "B", "P4", "F2"])
        XCTAssertNil(p4.parent)
        tree.select(f2)
        d.press("IDC_BUTTON_RIGHT")	// 直前の P4 はフォルダーではない
        XCTAssertNil(f2.parent)
        tree.select(p4)
        d.press("IDC_BUTTON_RIGHT")
        XCTAssertTrue(p4.parent === tree.roots[3])
        // 削除：子があれば確かめる（キャンセルなら消さない）。次を選ぶ
        tree.select(tree.roots[3])
        confirmAnswer = false
        d.press("IDC_BUTTON_DELETE")
        XCTAssertEqual(tree.roots.count, 5)
        confirmAnswer = true
        d.press("IDC_BUTTON_DELETE")
        XCTAssertEqual(titles(), ["P1", "Two", "A", "F2"])
        XCTAssertEqual(page.text("IDC_EDIT_LABEL"), "F2")
        // OK：共通設定に保存（階層付き）
        page.setChecked("IDC_CHECK_LOADINI", true)
        page.setText("IDC_EDIT_DEFINI", "def.ini")
        d.press("IDOK")
        let saved = FileTreeCore.load(typeIndex: 0, folder: directory.path)
        XCTAssertTrue(saved.project)
        XCTAssertEqual(saved.defaultProjectIni, "def.ini")
        XCTAssertEqual(saved.items.map(\.path), ["P1", "P2", "A", ""])
        XCTAssertEqual(saved.items.map(\.type), [.grep, .file, .grep, .folder])
        XCTAssertEqual(saved.items.map(\.label), ["", "Two", "", "F2"])
    }

    /// 共通設定に保存するときは最大数（20）を超えたら追加できない（原版 ChangeEnableAddInsert）、超えた分は切り捨て
    func testDialogMaxCount() throws {
        setCommonItems((0..<20).map { item(.grep, path: "P\($0)") })
        let d = try dialog()
        XCTAssertTrue(d.page.isEnabled("IDC_BUTTON_ADD"))
        d.press("IDC_BUTTON_ADD")
        XCTAssertEqual(d.tree?.roots.count, 21)
        XCTAssertFalse(d.page.isEnabled("IDC_BUTTON_ADD"))
        XCTAssertFalse(d.page.isEnabled("IDC_BUTTON_INSERT"))
        XCTAssertFalse(d.page.isEnabled("IDC_BUTTON_INSERT_A"))
        d.press("IDC_BUTTON_DELETE")
        XCTAssertTrue(d.page.isEnabled("IDC_BUTTON_ADD"))
        d.press("IDC_BUTTON_ADD")
        d.press("IDOK")
        XCTAssertEqual(informed, ["最大数(20)を超えたため切り捨てました"])
        XCTAssertEqual(FileTreeCore.load(typeIndex: 0, folder: directory.path).items.count, 20)
    }

    /// 各フォルダーの設定ファイルを読んだとき：「設定: ファイル名」、読み込み は押せない、OK はそのファイルへ（20 個を超えてもよい）
    func testDialogProjectIni() throws {
        setCommonItems([item(.grep, path: ".")], project: true)
        let ini = path("_sakurafiletree.ini")
        XCTAssertEqual(FileTreeCore.exportItems([item(.grep, path: "<iniroot>/src")], path: ini), "")
        let d = try dialog()
        XCTAssertEqual(d.page.text("IDC_STATIC_SETTFING_FROM"), "設定: \(ini)")
        XCTAssertFalse(d.page.isEnabled("IDC_BUTTON_LOAD"))
        XCTAssertTrue(d.page.isChecked("IDC_CHECK_LOADINI"))
        XCTAssertEqual(d.tree?.visibleTitles, ["<iniroot>/src"])
        for _ in 0..<21 { d.press("IDC_BUTTON_ADD") }
        XCTAssertTrue(d.page.isEnabled("IDC_BUTTON_ADD"))
        d.press("IDOK")
        XCTAssertEqual(informed, [])
        XCTAssertEqual(FileTreeCore.importItems(path: ini)?.count, 22)
        // 共通設定の項目は変わらない
        let common = FileTreeCore.load(typeIndex: 0, folder: "/")
        XCTAssertEqual(common.items.map(\.path), ["."])
    }

    /// デフォルト設定ファイル名の「読み込み」、インポート・エクスポート（原版 CImpExpFileTree）
    func testDialogLoadImportExport() throws {
        setCommonItems([item(.grep, path: ".")])
        let ini = path("def.ini")
        XCTAssertEqual(FileTreeCore.exportItems([item(.file, path: "/d.txt", label: "D")], path: ini), "")
        let d = try dialog()
        d.page.setText("IDC_EDIT_DEFINI", ini)
        d.press("IDC_BUTTON_LOAD")
        XCTAssertEqual(d.page.text("IDC_STATIC_SETTFING_FROM"), "設定: 共通設定+ファイル")
        XCTAssertEqual(d.tree?.visibleTitles, ["D"])
        // エクスポート
        let out = path("out.ini")
        TypeSettingsPages.chooseExportFile = { _, extensions, _ in
            XCTAssertEqual(extensions, ["ini"])
            return out
        }
        d.press("IDC_BUTTON_EXPORT")
        XCTAssertEqual(informed.last, "ファイルをエクスポートしました。\n\n\(out)")
        XCTAssertEqual(FileTreeCore.importItems(path: out)?.map(\.label), ["D"])
        // インポート
        XCTAssertEqual(FileTreeCore.exportItems([item(.folder, label: "I1"), item(.grep, path: "/g", depth: 1)], path: path("in.ini")), "")
        TypeSettingsPages.chooseImportFile = { [unowned self] _, _ in path("in.ini") }
        d.press("IDC_BUTTON_IMPORT")
        d.tree?.expandAll(true)
        XCTAssertEqual(d.tree?.visibleTitles, ["I1", "/g"])
        // OK は読み込んだ設定ファイル（def.ini）へ
        d.press("IDOK")
        XCTAssertEqual(FileTreeCore.importItems(path: ini)?.map(\.path), ["", "/g"])
    }

    /// 「▼」：パスの変数（原版 IDC_BUTTON_PATH_MENU）、「パスの一括置換」、「ファイル挿入」
    func testPathMenuReplaceAndFileAdd() throws {
        setCommonItems([item(.grep, path: "/old/a"), item(.file, path: "/old/b.txt")])
        let d = try dialog()
        let menu = d.makePathMenu()
        XCTAssertEqual(menu.items.map(\.title), ["INIルート(I)", "マイ ドキュメント(Y)", "マイ ミュージック(M)", "マイ ビデオ(V)",
                                                 "デスクトップ(D)", "Temp(T)", "sakura(S)", "sakuraデータ(A)"])
        d.page.setText("IDC_EDIT_PATH", "")
        d.pathMenuChosen(menu.items[1])
        XCTAssertEqual(d.page.text("IDC_EDIT_PATH"), "%MYDOC%")
        // 一括置換
        var answers = ["/old", "/new"]
        CommonSettingsPages.input = { _, _, _, _ in answers.removeFirst() }
        d.press("IDC_BUTTON_REPLACE")
        XCTAssertEqual(d.tree?.visibleTitles, ["/new/a", "/new/b.txt"])
        XCTAssertEqual(d.page.text("IDC_EDIT_PATH"), "/new/a")
        // ファイル挿入：ラベルはファイル名、% は %%
        FileTreeDialogController.chooseFiles = { _ in ["/f/1%.txt", "/f/2.txt"] }
        d.tree?.select(d.tree?.roots[0])
        d.press("IDC_BUTTON_FILEADD")
        XCTAssertEqual(d.tree?.visibleTitles, ["/new/a", "/new/b.txt", "1%.txt", "2.txt"])
        d.press("IDOK")
        let items = FileTreeCore.load(typeIndex: 0, folder: directory.path).items
        XCTAssertEqual(items.map(\.path), ["/new/a", "/new/b.txt", "/f/1%%.txt", "/f/2.txt"])
        XCTAssertEqual(items.map(\.type), [.grep, .file, .file, .file])
    }
}

// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge
import XCTest

/// アウトライン解析（计划第 42 步）的窗口和命令的测试。
///
/// 解析的结果本身在核心库里测试（macos/core/tests/test-mac-outline.cpp，与 Windows 版比较），
/// 这里确认窗口（原版 CDlgFuncList）：布局、ツリー・リスト的显示、選択とキャレット、ジャンプ、
/// 順序・並べ替え（タイプ別設定に記憶）、コピー、メニュー、位置と大きさの記憶、
/// 命令（F_OUTLINE、F_OUTLINE_TOGGLE、F_FUNCLIST_NEXT/PREV）。
final class OutlineTests: XCTestCase {
    private var window: NSWindow!
    private var view: EditorTextView!
    private var pasteboard: NSPasteboard!
    private var messages: [String?] = []
    private var saved: [String: String] = [:]
    private var directory: URL!

    /// テストで変える共通設定（終わったら戻す）
    private static let commonKeys = ["bAutoCloseDlgFuncList", "bFunclistSetFocusOnJump", "bMarkUpBlankLineEnable",
                                     "bRememberOutlineWindowPos", "xOutlineWindowPos", "yOutlineWindowPos",
                                     "widthOutlineWindow", "heightOutlineWindow"]

    override func setUpWithError() throws {
        _ = TestCore.home
        _ = NSApplication.shared
        OutlineWindowController.hidesOnDeactivate = false
        pasteboard = NSPasteboard(name: NSPasteboard.Name("jp.sakura-editor.tests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        OutlineWindowController.pasteboard = pasteboard
        messages = []
        EditorTextView.messageHandler = { [unowned self] in messages.append($0) }
        for key in Self.commonKeys {
            saved[key] = EditorCore.commonSetting(section: "Common", key: key) ?? ""
        }
        _ = EditorCore.setCommonSettings(["bAutoCloseDlgFuncList": "0", "bFunclistSetFocusOnJump": "0",
                                          "bRememberOutlineWindowPos": "0"], section: "Common")
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("outline-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let document = try XCTUnwrap(EditorDocument())
        window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 600, height: 400),
                          styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        view = EditorTextView(document: document)
        view.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        window.contentView = view
        window.makeFirstResponder(view)
    }

    override func tearDown() {
        view.outlinePanel?.close()
        EditorTextView.messageHandler = nil
        OutlineWindowController.pasteboard = .general
        _ = EditorCore.setCommonSettings(saved, section: "Common")
        pasteboard.releaseGlobally()
        window.close()
        window = nil
        view = nil
        try? FileManager.default.removeItem(at: directory)
    }

    /// ファイルを作って開く（拡張子でタイプ別設定が決まる）
    private func open(_ name: String, _ text: String) throws {
        let url = directory.appendingPathComponent(name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(view.document.open(path: url.path), .success)
        view.setCaret(EditorPosition(line: 0, column: 0))
    }

    /// 位置（行, 桁）
    private func lc(_ p: EditorPosition) -> [Int] { [p.line, p.column] }

    private var panel: OutlineWindowController {
        get throws { try XCTUnwrap(view.outlinePanel) }
    }

    /// 見えているツリーの項目（字下げ付き）
    private func visibleTree(_ panel: OutlineWindowController) -> [String] {
        let tree = panel.treeView
        return (0..<tree.numberOfRows).compactMap { row in
            guard let item = tree.item(atRow: row) as? OutlineTreeItem else { return nil }
            return String(repeating: "  ", count: tree.level(forRow: row)) + item.node.label
        }
    }

    private func selectedLabel(_ panel: OutlineWindowController) -> String? {
        (panel.treeView.item(atRow: panel.treeView.selectedRow) as? OutlineTreeItem)?.node.label
    }

    private func selectRow(label: String, in panel: OutlineWindowController) throws {
        let tree = panel.treeView
        let row = try XCTUnwrap((0..<tree.numberOfRows).first { (tree.item(atRow: $0) as? OutlineTreeItem)?.node.label == label },
                                "項目「\(label)」")
        tree.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    }

    private func press(_ id: String, in panel: OutlineWindowController) throws {
        let button = try XCTUnwrap(panel.page.control(id) as? NSButton, id)
        button.performClick(nil)
    }

    private static let cpp = """
    class Shape {
    public:
    \tvoid Draw();
    };

    void Shape::Draw()
    {
    }

    int main()
    {
    \treturn 0;
    }
    """

    private static let text = """
    ■第一章
    □節 A
    □節 B
    ■第二章
    □節 C
    """

    // MARK: - 布局（原版 IDD_FUNCLIST）

    func testLayoutFollowsTemplate() throws {
        try open("a.txt", Self.text)
        view.showOutline(nil)
        let panel = try panel
        // 控件与原版的模板相同
        let page = panel.page
        let expected: [(String, String)] = [
            ("IDC_BUTTON_COPY", "コピー(C)"), ("IDOK", "ジャンプ(J)"), ("IDCANCEL", "キャンセル(X)"), ("IDC_BUTTON_HELP", "ヘルプ(H)"),
            ("IDC_CHECK_bAutoCloseDlgFuncList", "自動的に閉じる(D)"), ("IDC_CHECK_bFunclistSetFocusOnJump", "フォーカスを移す(F)"),
            ("IDC_BUTTON_MENU", "▼"),
        ]
        for (id, title) in expected {
            XCTAssertEqual((page.control(id) as? NSButton)?.title, title, id)
        }
        // 1 行の文字が切れない、ボタンが重ならない（共通設定と同じ検査）
        XCTAssertEqual(PropLayoutTests.truncated(page), [])
        // 第 49 步：ヘルプ
        XCTAssertTrue(page.isEnabled("IDC_BUTTON_HELP"))
        // ツリーのときは順序がある、リストは隠れている
        XCTAssertFalse(page.control("IDC_TREE_FL")?.isHidden ?? true)
        XCTAssertTrue(page.control("IDC_LIST_FL")?.isHidden ?? false)
        XCTAssertFalse(page.control("IDC_COMBO_nSortType")?.isHidden ?? true)
        XCTAssertEqual(page.itemTitles("IDC_COMBO_nSortType"), ["デフォルト", "デフォルト(降順)", "アルファベット順", "アルファベット(降順)"])
        // ブックマーク一覧以外では「空行を無視する」は隠す
        XCTAssertTrue(page.control("IDC_CHECK_bMarkUpBlankLineEnable")?.isHidden ?? false)
        XCTAssertEqual(panel.window?.title, "テキスト トピックツリー")
    }

    /// 大きさを変えるとツリーが広がり、下のボタンは下に付いていく（原版 anchorList）
    func testResizeKeepsBottomControls() throws {
        try open("a.txt", Self.text)
        view.showOutline(nil)
        let panel = try panel
        let window = try XCTUnwrap(panel.window)
        let content = try XCTUnwrap(window.contentView)
        let tree = try XCTUnwrap(panel.page.control("IDC_TREE_FL"))
        let copy = try XCTUnwrap(panel.page.control("IDC_BUTTON_COPY"))
        let combo = try XCTUnwrap(panel.page.control("IDC_COMBO_nSortType"))
        let treeFrame = tree.frame, copyFrame = copy.frame, comboFrame = combo.frame
        let bottomGap = content.frame.height - copyFrame.maxY
        window.setContentSize(NSSize(width: content.frame.width + 100, height: content.frame.height + 80))
        XCTAssertEqual(tree.frame.width, treeFrame.width + 100, accuracy: 0.5)
        XCTAssertEqual(tree.frame.height, treeFrame.height + 80, accuracy: 0.5)
        XCTAssertEqual(content.frame.height - copy.frame.maxY, bottomGap, accuracy: 0.5, "コピーは下に付く")
        XCTAssertEqual(copy.frame.minX, copyFrame.minX, accuracy: 0.5)
        XCTAssertEqual(combo.frame, comboFrame, "順序は上に付く")
        // 最小・最大（原版 OnMinMaxInfo）
        XCTAssertGreaterThan(window.contentMinSize.width, 0)
        XCTAssertGreaterThan(window.contentMaxSize.width, window.contentMinSize.width)
    }

    // MARK: - ツリー

    func testTreeShowsResultAndFollowsCaret() throws {
        try open("a.txt", Self.text)
        view.setCaret(EditorPosition(line: 4, column: 0))	// □節 C
        view.showOutline(nil)
        let panel = try panel
        // 選ばれた項目（節 C）の親は開く。ほかは閉じたまま（原版 SetTree は展開しない）
        XCTAssertEqual(visibleTree(panel), ["■第一章", "■第二章", "  □節 C"])
        XCTAssertEqual(selectedLabel(panel), "□節 C")
        // キャレットが動くと選択も動く。閉じている項目は開かず、見えている親を選ぶ
        view.setCaret(EditorPosition(line: 1, column: 0))
        XCTAssertEqual(selectedLabel(panel), "■第一章")
        XCTAssertEqual(visibleTree(panel), ["■第一章", "■第二章", "  □節 C"])
        panel.treeView.expandItem(panel.treeView.item(atRow: 0))
        view.setCaret(EditorPosition(line: 2, column: 0))
        XCTAssertEqual(selectedLabel(panel), "□節 B")
        // 編集したら解析結果は古いので付いていかない（原版 NotifyDocModification）
        view.insertText("x", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertFalse(panel.isUpToDate)
        view.setCaret(EditorPosition(line: 0, column: 0))
        XCTAssertEqual(selectedLabel(panel), "□節 B")
    }

    func testCppTreeExpandsFirstLevel() throws {
        try open("a.cpp", Self.cpp)
        view.showOutline(nil)
        let panel = try panel
        XCTAssertEqual(panel.window?.title, "C++ メソッドツリー")
        XCTAssertEqual(visibleTree(panel), ["Shape クラス", "  Draw(宣言)", "  Draw", "グローバル", "  main"])
    }

    /// 長い見出しも切れない（列の幅は見えている項目が全部入る幅、狭いときは横にスクロール）
    func testTreeColumnFitsLongLabels() throws {
        let long = "■" + String(repeating: "とても長い見出し", count: 12)
        try open("a.txt", long + "\n□節\n")
        view.showOutline(nil)
        let panel = try panel
        let tree = panel.treeView
        let column = try XCTUnwrap(tree.outlineTableColumn)
        let needed = ceil((long as NSString).size(withAttributes: [.font: PropPage.font]).width)
        XCTAssertGreaterThan(column.width, needed)
        XCTAssertGreaterThan(tree.frame.width, tree.enclosingScrollView?.contentSize.width ?? .infinity, "横にスクロールできる")
    }

    func testJump() throws {
        try open("a.cpp", Self.cpp)
        view.showOutline(nil)
        let panel = try panel
        try selectRow(label: "main", in: panel)
        try press("IDOK", in: panel)
        XCTAssertEqual(lc(view.caret), [9, 0])
        XCTAssertTrue(panel.window?.isVisible ?? false, "自動的に閉じない")
        // グローバル（解析結果にない項目）はジャンプしない
        try selectRow(label: "グローバル", in: panel)
        try press("IDOK", in: panel)
        XCTAssertEqual(lc(view.caret), [9, 0])
        // スペースキー：ジャンプして、自動的に閉じない
        _ = EditorCore.setCommonSetting("1", section: "Common", key: "bAutoCloseDlgFuncList")
        try selectRow(label: "Draw", in: panel)
        let space = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                                   context: nil, characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49))
        panel.treeView.keyDown(with: space)
        XCTAssertEqual(lc(view.caret), [5, 0])
        XCTAssertTrue(panel.window?.isVisible ?? false)
        // 自動的に閉じる
        try selectRow(label: "main", in: panel)
        try press("IDOK", in: panel)
        XCTAssertEqual(lc(view.caret), [9, 0])
        XCTAssertFalse(panel.window?.isVisible ?? true, "ジャンプで閉じた")
    }

    /// 選択のロック中は選択しながらジャンプ（原版 PM_SETCARETPOS_KEEPSELECT）
    func testJumpKeepsSelectingLock() throws {
        try open("a.cpp", Self.cpp)
        view.selectingLock = true
        view.showOutline(nil)
        let panel = try panel
        try selectRow(label: "main", in: panel)
        try press("IDOK", in: panel)
        XCTAssertEqual(lc(view.caret), [9, 0])
        XCTAssertEqual(view.selection.map { lc($0.from) }, [0, 0])
        XCTAssertEqual(view.selection.map { lc($0.to) }, [9, 0])
    }

    func testCheckboxesSaveCommonSettings() throws {
        try open("a.txt", Self.text)
        view.showOutline(nil)
        let page = try panel.page
        XCTAssertTrue(page.isEnabled("IDC_CHECK_bFunclistSetFocusOnJump"))
        try press("IDC_CHECK_bAutoCloseDlgFuncList", in: panel)
        XCTAssertEqual(EditorCore.commonSetting(section: "Common", key: "bAutoCloseDlgFuncList"), "1")
        XCTAssertFalse(page.isEnabled("IDC_CHECK_bFunclistSetFocusOnJump"), "自動的に閉じるときはフォーカス移動は関係ない")
        try press("IDC_CHECK_bAutoCloseDlgFuncList", in: panel)
        try press("IDC_CHECK_bFunclistSetFocusOnJump", in: panel)
        XCTAssertEqual(EditorCore.commonSetting(section: "Common", key: "bFunclistSetFocusOnJump"), "1")
    }

    func testSortTreeIsSavedToTypeSettings() throws {
        try open("a.txt", Self.text)
        let section = "Types(\(view.document.typeIndex))"
        let before = EditorCore.commonSetting(section: section, key: "nOutlineSortType") ?? "0"
        defer { _ = EditorCore.setCommonSetting(before, section: section, key: "nOutlineSortType") }
        view.showOutline(nil)
        let panel = try panel
        panel.treeView.expandItem(nil, expandChildren: true)
        try selectRow(label: "□節 B", in: panel)
        panel.page.select("IDC_COMBO_nSortType", 1)	// デフォルト(降順)
        (panel.page.control("IDC_COMBO_nSortType") as? NSPopUpButton)?.sendAction(
            (panel.page.control("IDC_COMBO_nSortType") as? NSPopUpButton)?.action, to: (panel.page.control("IDC_COMBO_nSortType") as? NSPopUpButton)?.target)
        XCTAssertEqual(EditorCore.commonSetting(section: section, key: "nOutlineSortType"), "1")
        XCTAssertEqual(visibleTree(panel), ["■第二章", "  □節 C", "■第一章", "  □節 B", "  □節 A"], "開いている項目はそのまま")
        XCTAssertEqual(selectedLabel(panel), "□節 B", "選択はそのまま")
        // 次に開いたときも降順
        panel.close()
        view.showOutline(nil)
        XCTAssertEqual(try self.panel.result.sort, .defaultDesc)
        XCTAssertEqual(try self.panel.page.selectedIndex("IDC_COMBO_nSortType"), 1)
    }

    // MARK: - リスト

    func testListAndColumnSort() throws {
        try open("a.c", "int b(void)\n{\n}\nint a(void)\n{\n}\n")
        let section = "Types(\(view.document.typeIndex))"
        let before = (EditorCore.commonSetting(section: section, key: "nOutlineSortCol") ?? "0",
                      EditorCore.commonSetting(section: section, key: "bOutlineSortDesc") ?? "0")
        defer { _ = EditorCore.setCommonSettings(["nOutlineSortCol": before.0, "bOutlineSortDesc": before.1], section: section) }
        view.showOutline(nil)
        let panel = try panel
        XCTAssertEqual(panel.window?.title, "C 関数一覧")
        XCTAssertTrue(panel.page.control("IDC_TREE_FL")?.isHidden ?? false)
        XCTAssertFalse(panel.page.control("IDC_LIST_FL")?.isHidden ?? true)
        XCTAssertTrue(panel.page.control("IDC_COMBO_nSortType")?.isHidden ?? false, "リストに順序はない")
        let list = panel.listView
        XCTAssertEqual(list.tableColumns.map(\.title), ["行 *", "桁", "関数名", ""])
        XCTAssertEqual(list.numberOfRows, 2)
        XCTAssertEqual(list.selectedRow, 0, "キャレットの位置の項目")
        // 関数名で並べ替え、もう一度で降順。タイプ別設定に記憶
        panel.sortList(column: 2)
        XCTAssertEqual(list.tableColumns.map(\.title), ["行", "桁", "関数名 *", ""])
        XCTAssertEqual(panel.result.rows.map(\.name), ["a", "b"])
        XCTAssertEqual(list.selectedRow, 1, "選択した項目はそのまま")
        XCTAssertEqual(EditorCore.commonSetting(section: section, key: "nOutlineSortCol"), "2")
        panel.sortList(column: 2)
        XCTAssertEqual(panel.result.rows.map(\.name), ["b", "a"])
        XCTAssertEqual(EditorCore.commonSetting(section: section, key: "bOutlineSortDesc"), "1")
        // ジャンプ
        list.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        try press("IDOK", in: panel)
        XCTAssertEqual(lc(view.caret), [3, 0])
    }

    // MARK: - コピー、メニュー、キー

    func testCopy() throws {
        try open("a.txt", Self.text)
        view.showOutline(nil)
        let panel = try panel
        try press("IDC_BUTTON_COPY", in: panel)
        XCTAssertEqual(pasteboard.string(forType: .string), " ■第一章\r\n   □節 A\r\n   □節 B\r\n ■第二章\r\n   □節 C\r\n")
        // ⌘C（割り当てられた F_COPY：原版 Key2Command）
        pasteboard.clearContents()
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: 0,
                                                   context: nil, characters: "c", charactersIgnoringModifiers: "c", isARepeat: false, keyCode: 8))
        XCTAssertTrue(panel.handleKey(event))
        XCTAssertEqual(pasteboard.string(forType: .string)?.hasPrefix(" ■第一章"), true)
    }

    func testMenus() throws {
        try open("a.txt", Self.text)
        view.showOutline(nil)
        let panel = try panel
        let context = panel.makeMenu(dropDown: false)
        XCTAssertEqual(context.items.map(\.title), ["更新(U)", "コピー(C)", "", "すべて展開(E)", "すべて縮小(O)", "", "ウィンドウの位置(W)", "", "閉じる(X)"])
        let position = try XCTUnwrap(context.items[6].submenu)
        XCTAssertEqual(position.items.map(\.title), ["左ドッキング(L)", "右ドッキング(R)", "上ドッキング(T)", "下ドッキング(B)", "フローティング(F)",
                                                     "ドッキング禁止(I)", "", "ドッキング配置を同期(S)", "", "ドッキング配置を共通継承(C)",
                                                     "ドッキング配置をタイプ別継承(Y)", "", "継承情報を統一(U)"])
        XCTAssertEqual(position.items[4].state, .on, "フローティング")
        // ▼ はウィンドウの位置だけ
        let dropDown = panel.makeMenu(dropDown: true)
        XCTAssertEqual(dropDown.items.first?.title, "左ドッキング(L)")
        // すべて展開・すべて縮小
        panel.menuExpandAll(nil)
        XCTAssertEqual(visibleTree(panel).count, 5)
        panel.menuCollapseAll(nil)
        XCTAssertEqual(visibleTree(panel), ["■第一章", "■第二章"])
        // 閉じる
        panel.menuClose(nil)
        XCTAssertFalse(panel.window?.isVisible ?? true)
        XCTAssertNil(view.outlinePanel)
    }

    // MARK: - 命令

    /// F_OUTLINE：開いている同じ種別はアクティブにするだけ。更新・別の種別は再解析。F_OUTLINE_TOGGLE：同じ種別は閉じる
    func testOutlineCommands() throws {
        try open("a.txt", Self.text)
        view.showOutline(nil)
        let panel = try panel
        XCTAssertEqual(panel.result.items.count, 5)
        // 追加しても F_OUTLINE は再解析しない
        _ = view.document.insert("\n■第三章", at: view.document.endPosition)
        view.showOutline(nil)
        XCTAssertTrue(view.outlinePanel === panel)
        XCTAssertEqual(panel.result.items.count, 5)
        // 更新（右クリックメニュー）は再解析
        panel.menuUpdate(nil)
        XCTAssertEqual(panel.result.items.count, 6)
        XCTAssertTrue(panel.isUpToDate)
        // 別の種別（WZ階層付テキスト）は再解析
        view.outlineCommand(action: .normal, type: .wzText)
        XCTAssertEqual(panel.result.type, .wzText)
        XCTAssertEqual(panel.window?.title, "WZ階層付テキスト")
        // toggle：違う種別なので再解析
        view.toggleOutline(nil)
        XCTAssertEqual(panel.result.type, .text)
        XCTAssertTrue(panel.window?.isVisible ?? false)
        // toggle：同じ種別なので閉じる
        view.toggleOutline(nil)
        XCTAssertFalse(panel.window?.isVisible ?? true)
        // toggle：閉じているので開く
        view.toggleOutline(nil)
        XCTAssertTrue(view.outlinePanel?.window?.isVisible ?? false)
    }

    /// タイプ別設定の解析方法が変わったら再解析（原版 PM_CHANGESETTING_TYPE → SHOW_NORMAL）。変わらないときはそのまま
    func testTypeSettingChangeReanalyzes() throws {
        try open("a.txt", Self.text)
        let section = "Types(\(view.document.typeIndex))"
        let before = EditorCore.commonSetting(section: section, key: "nDefaultOutline") ?? "3"
        defer {
            _ = EditorCore.setCommonSetting(before, section: section, key: "nDefaultOutline")
            NotificationCenter.default.post(name: TypeSettingsWindowController.didChangeNotification, object: nil,
                                            userInfo: ["index": view.document.typeIndex])
        }
        view.showOutline(nil)
        let panel = try panel
        XCTAssertEqual(panel.result.type, .text)
        NotificationCenter.default.post(name: TypeSettingsWindowController.didChangeNotification, object: nil,
                                        userInfo: ["index": view.document.typeIndex])
        XCTAssertEqual(panel.result.type, .text)
        _ = EditorCore.setCommonSetting("9", section: section, key: "nDefaultOutline")	// WZ階層付テキスト
        NotificationCenter.default.post(name: TypeSettingsWindowController.didChangeNotification, object: nil,
                                        userInfo: ["index": view.document.typeIndex])
        XCTAssertEqual(panel.result.type, .wzText)
        XCTAssertEqual(panel.window?.title, "WZ階層付テキスト")
    }

    /// タイトルバーの右クリックでメニュー（原版 OnContextMenu：キャプション上なら DoMenu）。中の右クリックは普通に
    func testTitlebarRightClickMenu() throws {
        try open("a.txt", Self.text)
        view.showOutline(nil)
        let panel = try XCTUnwrap(self.panel.window as? OutlinePanel)
        var shown: [String] = []
        let saved = OutlinePanel.presentMenu
        defer { OutlinePanel.presentMenu = saved }
        OutlinePanel.presentMenu = { menu, _, _ in shown = menu.items.map(\.title) }
        let title = NSPoint(x: 100, y: panel.contentLayoutRect.maxY + 5)
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseDown, location: title, modifierFlags: [], timestamp: 0,
                                                     windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        panel.sendEvent(event)
        XCTAssertEqual(shown.first, "更新(U)")
        XCTAssertTrue(shown.contains("ウィンドウの位置(W)"))
    }

    /// ルールファイル：設定で選んだファイルは書签を残し（重启後も沙盒で読める）、解析はその権限で読む
    func testRuleFileBookmark() throws {
        let rule = directory.appendingPathComponent("rule.rul")
        // ルールファイルは BOM 付きの UTF-8（BOM がないと Shift_JIS）
        try (Data([0xEF, 0xBB, 0xBF]) + ";Title=規則\n■ /// 見出し\n".data(using: .utf8)!).write(to: rule)
        let saved = TypeSettingsPages.chooseFile
        defer { TypeSettingsPages.chooseFile = saved }
        XCTAssertTrue(BookmarkStore.settingFiles.remember(rule))
        XCTAssertTrue(BookmarkStore.settingFiles.hasBookmark(forPath: rule.path))
        // 「最近使ったファイル」の整理では消えない（別の書签）
        BookmarkStore.shared.pruneToRecentFiles()
        XCTAssertTrue(BookmarkStore.settingFiles.hasBookmark(forPath: rule.path))
        var ran = false
        XCTAssertEqual(BookmarkStore.settingFiles.withAccess(path: rule.path) { ran = true; return 1 }, 1)
        XCTAssertTrue(ran)
        // 解析
        try open("a.txt", Self.text)
        let section = "Types(\(view.document.typeIndex))"
        let before = ["nDefaultOutline", "szOutlineRuleFilename"].reduce(into: [String: String]()) {
            $0[$1] = EditorCore.commonSetting(section: section, key: $1) ?? ""
        }
        defer { _ = EditorCore.setCommonSettings(before, section: section) }
        _ = EditorCore.setCommonSettings(["nDefaultOutline": "12", "szOutlineRuleFilename": rule.path], section: section)
        _ = view.document.applyTypeSettingChange(view.document.typeIndex)
        let result = view.analyzeOutlineWithAccess(.ruleFile)
        XCTAssertEqual(result.title, "規則")
        XCTAssertEqual(result.items.count, 2)
    }

    func testCommandTable() {
        XCTAssertEqual(CommandTable.selector(for: 30930), #selector(EditorTextView.showOutline(_:)))
        XCTAssertEqual(CommandTable.selector(for: 30931), #selector(EditorTextView.toggleOutline(_:)))
        XCTAssertEqual(CommandTable.selector(for: 30988), #selector(EditorTextView.funcListNext(_:)))
        XCTAssertEqual(CommandTable.selector(for: 30989), #selector(EditorTextView.funcListPrev(_:)))
    }

    /// 次の関数リストマークへ／前の関数リストマークへ（アウトライン解析で付いた行）
    func testFuncListMarks() throws {
        try open("a.txt", "x\n■A\ny\n■B\nz\n")
        let settings = EditorCore.searchSettings
        let savedAll = settings.searchAll
        let savedNotify = settings.notifyNotFound
        defer {
            settings.searchAll = savedAll
            settings.notifyNotFound = savedNotify
            EditorCore.searchSettings = settings
        }
        settings.searchAll = false
        settings.notifyNotFound = true
        EditorCore.searchSettings = settings
        // 解析前はマークがない
        view.funcListNext(nil)
        XCTAssertEqual(messages, ["前方(↓) に関数が見つかりません。"])
        messages = []
        view.showOutline(nil)
        view.setCaret(EditorPosition(line: 0, column: 0))
        view.funcListNext(nil)
        XCTAssertEqual(lc(view.caret), [1, 0])
        view.funcListNext(nil)
        XCTAssertEqual(lc(view.caret), [3, 0])
        view.funcListNext(nil)
        XCTAssertEqual(lc(view.caret), [3, 0])
        XCTAssertEqual(messages, ["前方(↓) に関数が見つかりません。"])
        view.funcListPrev(nil)
        XCTAssertEqual(lc(view.caret), [1, 0])
        // 先頭（末尾）から再検索する
        settings.searchAll = true
        EditorCore.searchSettings = settings
        view.funcListPrev(nil)
        XCTAssertEqual(lc(view.caret), [3, 0])
    }

    // MARK: - 位置と大きさを記憶する（■）

    func testRememberWindowPosition() throws {
        try open("a.txt", Self.text)
        view.showOutline(nil)
        let panel = try panel
        let button = try XCTUnwrap(panel.page.control("IDC_BUTTON_WINSIZE") as? NSButton)
        XCTAssertEqual(button.title, "□")
        button.performClick(nil)
        XCTAssertEqual(button.title, "■")
        XCTAssertEqual(EditorCore.commonSetting(section: "Common", key: "bRememberOutlineWindowPos"), "1")
        let frame = NSRect(x: window.frame.minX + 30, y: window.frame.maxY - 50 - 300, width: 380, height: 300)
        panel.window?.setFrame(frame, display: false)
        panel.close()
        XCTAssertEqual(EditorCore.commonSetting(section: "Common", key: "xOutlineWindowPos"), "30")
        XCTAssertEqual(EditorCore.commonSetting(section: "Common", key: "yOutlineWindowPos"), "50")
        view.showOutline(nil)
        XCTAssertEqual(try self.panel.window?.frame, frame)
    }
}

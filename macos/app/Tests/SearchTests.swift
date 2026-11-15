// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge
import XCTest

/// 查找、置换、指定行へジャンプ（计划第 32 步）的测试。
///
/// 查找、置换本身在核心库里（macos/core/tests/test-mac-search.cpp 测试），
/// 这里确认视图的命令（原版 CViewCommander_Search.cpp）和对话框（CDlgFind、CDlgReplace）：
/// 选择范围和光标、找不到时的消息、检索标记、对话框的设置和历史。
/// 消息框用 EditorTextView.messageHandler 接住（不出模态的窗口）。
final class SearchTests: XCTestCase {
    private var window: NSWindow!
    private var view: EditorTextView!
    private var pasteboard: NSPasteboard!
    private var savedSettings: EditorSearchSettings!
    /// 显示的消息（nil 是蜂鸣）
    private var messages: [String?] = []

    override func setUpWithError() throws {
        _ = TestCore.home
        _ = NSApplication.shared
        savedSettings = EditorCore.searchSettings
        let settings = EditorCore.searchSettings
        settings.options = []
        settings.notifyNotFound = true
        settings.autoCloseFind = false
        settings.autoCloseReplace = false
        settings.searchAll = false
        settings.consecutiveAll = false
        settings.selectedArea = false
        settings.caretTextForSearch = true
        settings.inheritKeyOtherView = true
        settings.jumpLineNumIsCRLF = true
        EditorCore.searchSettings = settings
        messages = []
        SearchPanelBase.hidesOnDeactivate = false	// 测试时 App 不是活动的，对话框也要显示
        EditorTextView.messageHandler = { [unowned self] in messages.append($0) }

        let document = try XCTUnwrap(EditorDocument())
        window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 600, height: 400),
                          styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        view = EditorTextView(document: document)
        view.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        window.contentView = view
        window.makeFirstResponder(view)
        pasteboard = NSPasteboard(name: NSPasteboard.Name("jp.sakura-editor.tests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        view.pasteboard = pasteboard
    }

    override func tearDown() {
        view.findPanel?.close()
        view.replacePanel?.close()
        EditorTextView.messageHandler = nil
        EditorCore.searchSettings = savedSettings
        pasteboard.releaseGlobally()
        window.close()
        window = nil
        view = nil
    }

    private func load(_ text: String, caret: EditorPosition = EditorPosition(line: 0, column: 0)) {
        XCTAssertEqual(view.document.insert(text, at: EditorPosition(line: 0, column: 0)), .success)
        view.setCaret(caret)
    }

    private var text: String { view.document.text }

    private func pos(_ line: Int, _ column: Int) -> EditorPosition {
        EditorPosition(line: line, column: column)
    }

    /// 选择范围（from..to）和光标
    private func assertSelection(_ from: EditorPosition, _ to: EditorPosition, caret: EditorPosition,
                                 file: StaticString = #filePath, line: UInt = #line) {
        guard let selection = view.selection else {
            XCTFail("没有选择", file: file, line: line)
            return
        }
        XCTAssertEqual([selection.from.line, selection.from.column, selection.to.line, selection.to.column],
                       [from.line, from.column, to.line, to.column], "选择范围", file: file, line: line)
        XCTAssertEqual([view.caret.line, view.caret.column], [caret.line, caret.column], "光标", file: file, line: line)
    }

    private func assertCaret(_ line: Int, _ column: Int, file: StaticString = #filePath, line sourceLine: UInt = #line) {
        XCTAssertEqual([view.caret.line, view.caret.column], [line, column], "光标", file: file, line: sourceLine)
    }

    /// 对话框登记查找文字（原版 CDlgFind::GetData 的处理）
    private func setKey(_ key: String, options: EditorSearchOptions = []) {
        EditorCore.addSearchKey(key)
        view.setSearchKey(key, options: options)
    }

    private func setSettings(_ change: (EditorSearchSettings) -> Void) {
        let settings = EditorCore.searchSettings
        change(settings)
        EditorCore.searchSettings = settings
    }

    // MARK: - 次を検索・前を検索

    func testSearchNextSelectsMatchWithCaretAtStart() {
        load("abc abc\n")
        setKey("abc")
        view.searchNextCommand()
        assertSelection(pos(0, 0), pos(0, 3), caret: pos(0, 0))
        XCTAssertTrue(view.searchState.markOn, "查找后显示検索文字列的颜色")
        // 下一个：从选择的末尾开始
        view.searchNextCommand()
        assertSelection(pos(0, 4), pos(0, 7), caret: pos(0, 4))
        XCTAssertTrue(messages.isEmpty)
    }

    func testSearchNextNotFoundMessageOrBeep() {
        load("abc abc\n")
        setKey("abc")
        view.searchNextCommand()
        view.searchNextCommand()
        view.searchNextCommand()
        // 找不到：选择取消，光标在选择的末尾，显示消息
        XCTAssertNil(view.selection)
        assertCaret(0, 7)
        XCTAssertEqual(messages, ["前方(↓) に文字列 'abc' が１つも見つかりません。"])

        // 「見つからないときにメッセージを表示」关掉时蜂鸣
        messages = []
        setSettings { $0.notifyNotFound = false }
        view.searchNextCommand()
        XCTAssertEqual(messages.count, 1)
        XCTAssertNil(messages.first ?? "")
    }

    func testSearchNextWrapsWhenSearchAll() {
        load("abc abc\n", caret: pos(0, 5))
        setSettings { $0.searchAll = true }
        setKey("abc")
        view.searchNextCommand()
        assertSelection(pos(0, 0), pos(0, 3), caret: pos(0, 0))
        XCTAssertTrue(messages.isEmpty, "先頭から再検索したときはメッセージを出さない（ステータスバーだけ）")
    }

    func testSearchPrev() {
        load("abc abc\n", caret: pos(1, 0))
        setKey("abc")
        view.searchPrevCommand()
        assertSelection(pos(0, 4), pos(0, 7), caret: pos(0, 4))
        view.searchPrevCommand()
        assertSelection(pos(0, 0), pos(0, 3), caret: pos(0, 0))
        view.searchPrevCommand()
        XCTAssertEqual(messages, ["後方(↑) に文字列 'abc' が１つも見つかりません。"])
    }

    func testInvalidRegularExpression() {
        load("abc\n")
        setKey("a(", options: .regularExpression)
        view.searchNextCommand()
        XCTAssertEqual(messages.count, 1)
        XCTAssertTrue(messages.first??.hasPrefix("正規表現の構文に誤りがあります。") ?? false)
        XCTAssertFalse(view.searchState.markOn)
        XCTAssertNil(view.selection)
    }

    func testZeroLengthMatchAdvances() {
        load("ab\ncd\n")
        setKey("^", options: .regularExpression)
        view.searchNextCommand()
        assertCaret(0, 0)
        XCTAssertTrue(view.searchView.hasSelection, "长度 0 的匹配也算选择")
        view.searchNextCommand()
        assertCaret(1, 0)
    }

    func testOtherViewSearchKeyIsInherited() {
        load("abc xyz\n")
        setKey("abc")
        view.searchNextCommand()
        // 别的视图（对话框）登记了新的查找文字：次を検索で引き継ぐ（原版 ChangeCurRegexp）
        EditorCore.addSearchKey("xyz")
        view.searchNextCommand()
        assertSelection(pos(0, 4), pos(0, 7), caret: pos(0, 4))
        XCTAssertEqual(view.searchState.key, "xyz")
    }

    // MARK: - 対話框的初始文字

    func testCurrentTextForSearchDialog() {
        load("hello world\nsecond line\n", caret: pos(0, 7))
        XCTAssertEqual(view.currentTextForSearchDialog(), "world", "カーソル位置の単語")
        XCTAssertNil(view.selection, "单词不留下选择")
        view.setSelection(from: pos(0, 6), to: pos(1, 3))
        XCTAssertEqual(view.currentTextForSearchDialog(), "world", "选择的文字到第一个换行为止")
        // 光标位置没有单词：历史的第一个
        view.setCaret(pos(2, 0))
        EditorCore.addSearchKey("from history")
        XCTAssertEqual(view.currentTextForSearchDialog(), "from history")
    }

    // MARK: - 置換

    private func replaceOptions(_ target: EditorReplaceTarget = .selection, paste: Bool = false,
                                selectedArea: Bool = false) -> EditorReplaceOptions {
        EditorReplaceOptions(search: [], target: target, paste: paste, searchAll: false,
                             consecutiveAll: false, selectedArea: selectedArea)
    }

    func testReplaceOneByOne() {
        load("a-a\n")
        setKey("a")
        XCTAssertTrue(view.replaceCommand("bb", options: replaceOptions()))
        XCTAssertEqual(text, "bb-a\n")
        assertSelection(pos(0, 3), pos(0, 4), caret: pos(0, 3))
        XCTAssertTrue(messages.isEmpty)
        XCTAssertTrue(view.replaceCommand("bb", options: replaceOptions()))
        XCTAssertEqual(text, "bb-bb\n")
        XCTAssertEqual(messages, ["最後まで置換しました。"])
        XCTAssertEqual(view.document.undo(), .success)
        XCTAssertEqual(text, "bb-a\n", "置換は 1 回が撤销的一步")
    }

    func testReplaceNotFound() {
        load("abc\n")
        setKey("x")
        XCTAssertTrue(view.replaceCommand("y", options: replaceOptions()))
        XCTAssertEqual(text, "abc\n")
        XCTAssertEqual(messages, ["前方(↓) に文字列 'x' が１つも見つかりません。"])
    }

    func testReplaceWithClipboard() {
        load("a-a\n")
        setKey("a")
        // 剪贴板是空的
        XCTAssertFalse(view.replaceCommand("", options: replaceOptions(paste: true)))
        XCTAssertEqual(messages, ["クリップボードに有効なデータがありません！"])
        XCTAssertEqual(text, "a-a\n")
        pasteboard.clearContents()
        pasteboard.setString("$&!", forType: .string)
        XCTAssertTrue(view.replaceCommand("", options: replaceOptions(paste: true)))
        XCTAssertEqual(text, "$&!-a\n", "剪贴板的文字原样插入")
    }

    func testReplaceAllCountAndUndo() {
        load("a a\na\n")
        setKey("a")
        XCTAssertEqual(view.replaceAllCommand("xy", options: replaceOptions()), 3)
        XCTAssertEqual(text, "xy xy\nxy\n")
        XCTAssertNil(view.selection)
        XCTAssertEqual(view.document.undo(), .success)
        XCTAssertEqual(text, "a a\na\n", "すべて置換は撤销的一步")
    }

    func testReplaceAllInSelection() {
        load("a\na\na\n")
        view.setSelection(from: pos(1, 0), to: pos(2, 1))
        setKey("a")
        XCTAssertEqual(view.replaceAllCommand("b", options: replaceOptions(selectedArea: true)), 2)
        XCTAssertEqual(text, "a\nb\nb\n")
    }

    // MARK: - 検索マークの切替え

    func testToggleSearchMarkWithSelection() {
        load("foo bar foo\n")
        setKey("bar", options: [.regularExpression, .wholeWord])
        view.setSelection(from: pos(0, 0), to: pos(0, 3))
        view.toggleSearchMark(nil)
        XCTAssertEqual(view.searchState.key, "foo")
        XCTAssertFalse(view.searchState.options.contains(.regularExpression), "正規表現は使わない")
        XCTAssertFalse(view.searchState.options.contains(.wholeWord), "単語単位は使わない")
        XCTAssertTrue(view.searchState.markOn)
        XCTAssertEqual(EditorCore.searchKeyHistory.first, "foo", "履歴に登録")

        // 検索文字列の色：foo の 6 文字
        let colors = view.searchMarkColors(row: 0)
        XCTAssertEqual(colors.enumerated().filter { $0.element != nil }.map { $0.offset }, [0, 1, 2, 8, 9, 10])

        // 没有选择时：不显示
        view.setCaret(pos(0, 0))
        view.toggleSearchMark(nil)
        XCTAssertFalse(view.searchState.markOn)
        XCTAssertTrue(view.searchMarkColors(row: 0).isEmpty)
    }

    // MARK: - 指定行へジャンプ・検索開始位置へ戻る

    func testJump() {
        load("1\n2\n3\n4\n")
        view.jumpCommand(EditorJumpOptions(lineNumber: 3, lineNumIsCRLF: true, plsql: false, plsqlBlockFirstLine: 1))
        assertCaret(2, 0)
        view.jumpCommand(EditorJumpOptions(lineNumber: 0, lineNumIsCRLF: true, plsql: false, plsqlBlockFirstLine: 1))
        assertCaret(0, 0)
        XCTAssertTrue(messages.isEmpty)
    }

    func testJumpToSearchStart() {
        load("abc\nabc\n", caret: pos(1, 2))
        view.jumpToSearchStart(nil)
        XCTAssertEqual(messages.count, 1, "検索開始位置がないときは蜂鸣")
        XCTAssertNil(messages.first ?? "")

        // 对话框打开时的光标是検索開始位置
        view.setCaret(pos(0, 1))
        let panel = FindPanelController(view: view)
        panel.open(text: "abc")
        panel.searchNext(nil)
        assertSelection(pos(1, 0), pos(1, 3), caret: pos(1, 0))
        panel.close()
        view.setCaret(pos(0, 0))
        view.jumpToSearchStart(nil)
        assertCaret(0, 1)
    }

    // MARK: - 对话框

    func testFindPanel() {
        load("one two one\n")
        view.showFindPanel(nil)
        let panel = try! XCTUnwrap(view.findPanel)
        XCTAssertTrue(panel.window?.isVisible ?? false)
        XCTAssertEqual(panel.text, "one", "カーソル位置の単語")
        panel.searchNext(nil)
        assertSelection(pos(0, 0), pos(0, 3), caret: pos(0, 0))
        panel.searchNext(nil)
        assertSelection(pos(0, 8), pos(0, 11), caret: pos(0, 8))
        XCTAssertEqual(EditorCore.searchKeyHistory.first, "one")
        // 自動的に閉じる
        setSettings { $0.autoCloseFind = true }
        panel.open(text: "two")
        XCTAssertTrue(panel.window?.isVisible ?? false)
        panel.searchPrev(nil)
        XCTAssertFalse(panel.window?.isVisible ?? true, "検索ダイアログを自動的に閉じる")
        XCTAssertEqual(EditorCore.searchSettings.autoCloseFind, true)
    }

    func testFindPanelEmptyText() {
        load("abc\n")
        view.setCaret(pos(1, 0))
        let panel = FindPanelController(view: view)
        panel.open(text: "")
        panel.text = ""
        panel.activate(text: "")
        panel.searchNext(nil)
        XCTAssertEqual(messages, ["検索条件を指定してください。"])
        panel.close()
    }

    func testReplacePanelReplaceAll() {
        load("cat cat\n")
        EditorCore.addReplaceKey("dog")
        view.showReplacePanel(nil)
        let panel = try! XCTUnwrap(view.replacePanel)
        XCTAssertEqual(panel.text, "cat")
        XCTAssertEqual(panel.text2, "dog", "前回の置換後文字列を引き継ぐ")
        panel.replaceAll(nil)
        XCTAssertEqual(text, "dog dog\n")
        XCTAssertEqual(messages, ["2箇所を置換しました。"])
        XCTAssertEqual(panel.replaceCount, 2)
        XCTAssertEqual(EditorCore.replaceKeyHistory.first, "dog")
        XCTAssertTrue(panel.window?.isVisible ?? false, "自動的に閉じない設定のときは開いたまま")
    }

    func testReplacePanelReplaceOne() {
        load("cat cat\n")
        EditorCore.addReplaceKey("dog")
        view.showReplacePanel(nil)
        let panel = try! XCTUnwrap(view.replacePanel)
        panel.replace(nil)
        XCTAssertEqual(text, "dog cat\n")
        assertSelection(pos(0, 4), pos(0, 7), caret: pos(0, 4))
    }
}

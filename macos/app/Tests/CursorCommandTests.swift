// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge
import XCTest

/// 光标移动、选择、矩形选择的命令（计划第 34 步）的测试。
///
/// 按功能编号执行（CommandTable.perform，与菜单、快捷键相同的路径），确认光标和选择：
/// 単語の左端／右端、２行ごと、行頭（空白を飛ばす）、段落、変更行、ページ、ファイルの先頭／最後、
/// (範囲選択)／(矩形選択) 的各命令、範囲選択開始（选择的锁定）、単語選択、1行選択、移動履歴、画面的滚动。
/// 移到哪里的算法（単語、段落、変更行）由核心库的测试（test-mac-cursor.cpp）逐项确认。
final class CursorCommandTests: XCTestCase {
    private var window: NSWindow!
    private var scrollView: NSScrollView!
    private var view: EditorTextView!
    private var messages: [String?] = []

    override func setUpWithError() throws {
        _ = TestCore.home
        _ = NSApplication.shared
        let document = try XCTUnwrap(EditorDocument())
        window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 600, height: 400),
                          styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        scrollView.hasVerticalScroller = true
        view = EditorTextView(document: document)
        scrollView.documentView = view
        window.contentView = scrollView
        window.makeFirstResponder(view)
        view.contentDidChange()
        messages = []
        EditorTextView.messageHandler = { [weak self] in self?.messages.append($0) }
    }

    override func tearDown() {
        EditorTextView.messageHandler = nil
        window.close()
        window = nil
        view = nil
    }

    private func load(_ text: String, caret: EditorPosition = EditorPosition(line: 0, column: 0)) {
        XCTAssertEqual(view.document.insert(text, at: EditorPosition(line: 0, column: 0)), .success)
        view.contentDidChange()
        view.setCaret(caret)
    }

    private func run(_ code: Int, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(CommandTable.perform(code, from: view), "功能 \(code) 已移植", file: file, line: line)
    }

    private func pos(_ line: Int, _ column: Int) -> EditorPosition { EditorPosition(line: line, column: column) }

    private func assertCaret(_ line: Int, _ column: Int, file: StaticString = #filePath, line sourceLine: UInt = #line) {
        XCTAssertEqual(view.caret.line, line, "光标的行", file: file, line: sourceLine)
        XCTAssertEqual(view.caret.column, column, "光标的列", file: file, line: sourceLine)
    }

    private func assertSelection(_ from: EditorPosition, _ to: EditorPosition, file: StaticString = #filePath, line: UInt = #line) {
        guard let sel = view.selection else {
            XCTFail("没有选择", file: file, line: line)
            return
        }
        XCTAssertEqual([sel.from.line, sel.from.column, sel.to.line, sel.to.column], [from.line, from.column, to.line, to.column],
                       "选择范围", file: file, line: line)
    }

    // MARK: - 移動

    /// 単語の右端に移動、(範囲選択)単語の右端に移動、単語の左端に移動（选择先取消）
    func testWordMoves() {
        load("abc def ghi")
        run(30321)							// F_WORDRIGHT
        assertCaret(0, 4)
        run(30421)							// F_WORDRIGHT_SEL
        assertSelection(pos(0, 4), pos(0, 8))
        run(30320)							// F_WORDLEFT：取消选择，从光标开始移动
        XCTAssertFalse(view.hasSelection)
        assertCaret(0, 4)
        // 从行末：到下一行
        view.setCaret(pos(0, 11))
        XCTAssertEqual(view.document.insert("\njkl", at: pos(0, 11)), .success)
        view.setCaret(pos(0, 11))
        run(30321)
        assertCaret(1, 0)
    }

    /// カーソル上／下移動(２行ごと)：文档的开头、末尾停住
    func testTwoLineMoves() {
        load("1\n2\n3\n4\n5")
        run(30316)							// F_DOWN2
        assertCaret(2, 0)
        run(30316)
        run(30316)
        assertCaret(4, 0)
        view.setCaret(pos(1, 0))
        run(30315)							// F_UP2：从第 2 行到开头
        assertCaret(0, 0)
    }

    /// 行頭に移動：先到行头空白的后面，再按一次到行头
    func testLineTopSkipsIndent() {
        load("    abc", caret: pos(0, 7))
        run(30332)
        assertCaret(0, 4)
        run(30332)
        assertCaret(0, 0)
        run(30332)
        assertCaret(0, 4)
        run(30333)							// F_GOLINEEND
        assertCaret(0, 7)
    }

    /// 次の段落へ、前の段落へ
    func testParagraphs() {
        load("a\nb\n\nc\nd")
        run(30382)							// F_GONEXTPARAGRAPH
        assertCaret(3, 0)
        run(30383)							// F_GOPREVPARAGRAPH
        assertCaret(0, 0)
        run(30482)							// F_GONEXTPARAGRAPH_SEL
        assertSelection(pos(0, 0), pos(3, 0))
    }

    /// 次の変更行へ：新的文档全部是变更行，停在块的末尾（ぶら下がり[EOF]）。再找就找不到
    func testModifiedLines() {
        load("a\nb\nc")
        run(30393)							// F_MODIFYLINE_NEXT：块的末尾（ぶら下がり[EOF]）
        assertCaret(2, 1)
        run(30393)
        assertCaret(2, 1)
        XCTAssertEqual(messages.count, 1, "见不到时消息或蜂鸣（按「見つからないときにメッセージを表示」）")
        if let message = messages.first ?? nil {
            XCTAssertEqual(message, "前方(↓) に変更行が見つかりません。")
        }
    }

    /// (範囲選択)ファイルの最後／先頭
    func testFileTopEndWithSelection() {
        load("abc\ndef", caret: pos(0, 1))
        run(30451)							// F_GOFILEEND_SEL
        assertSelection(pos(0, 1), pos(1, 3))
        run(30350)							// F_GOFILETOP
        XCTAssertFalse(view.hasSelection)
        assertCaret(0, 0)
    }

    // MARK: - 矩形選択

    /// (矩形選択)カーソル右移動・下移動。「矩形選択移動で選択をロックする」（默认开）时普通的移动也继续矩形选择，Esc 取消
    func testBoxSelectionByKeys() throws {
        load("abcd\nefgh\nijkl", caret: pos(0, 1))
        let w = Int(view.charWidth)
        run(30514)							// F_RIGHT_BOX
        run(30512)							// F_DOWN_BOX
        var box = try XCTUnwrap(view.boxRange)
        XCTAssertEqual([box.top, box.bottom, box.left, box.right], [0, 1, w, 2 * w])
        run(30314)							// F_RIGHT：锁定中继续矩形选择
        box = try XCTUnwrap(view.boxRange)
        XCTAssertEqual([box.top, box.bottom, box.left, box.right], [0, 1, w, 3 * w])
        run(31099)							// F_CANCEL_MODE
        XCTAssertNil(view.boxRange)
        XCTAssertFalse(view.selectingLock)
    }

    /// 矩形範囲選択開始（Shift+F6）后用普通的移动扩展矩形
    func testBeginBoxSelection() throws {
        load("abcd\nefgh", caret: pos(0, 0))
        let w = Int(view.charWidth)
        run(30510)							// F_BEGIN_BOX
        run(30312)							// F_DOWN
        run(30314)							// F_RIGHT
        let box = try XCTUnwrap(view.boxRange)
        XCTAssertEqual([box.top, box.bottom, box.left, box.right], [0, 1, 0, w])
    }

    // MARK: - 選択

    /// 範囲選択開始（F6）：普通的移动扩展选择。再按一次解除锁定
    func testBeginSelectionLock() {
        load("abcdef")
        run(30410)							// F_BEGIN_SEL
        XCTAssertTrue(view.selectingLock)
        run(30314)
        run(30314)
        assertSelection(pos(0, 0), pos(0, 2))
        run(30410)							// 解除锁定（选择不变）
        XCTAssertFalse(view.selectingLock)
        assertSelection(pos(0, 0), pos(0, 2))
        run(30314)							// 普通的移动：取消选择
        XCTAssertFalse(view.hasSelection)
    }

    /// 現在位置の単語選択、1行選択
    func testSelectWordAndLine() {
        load("foo bar\nbaz", caret: pos(0, 5))
        run(30400)							// F_SELECTWORD
        assertSelection(pos(0, 4), pos(0, 7))
        assertCaret(0, 7)
        run(30403)							// F_SELECTLINE
        assertSelection(pos(0, 0), pos(1, 0))
        view.setCaret(pos(1, 1))
        run(30403)							// 最后一行（没有换行）到行末
        assertSelection(pos(1, 0), pos(1, 3))
    }

    // MARK: - 移動履歴

    func testJumpHistory() {
        load("1\n2\n3\n4\n5", caret: pos(2, 0))
        let prevItem = NSMenuItem(title: "", action: #selector(EditorTextView.jumpHistoryPrev(_:)), keyEquivalent: "")
        let nextItem = NSMenuItem(title: "", action: #selector(EditorTextView.jumpHistoryNext(_:)), keyEquivalent: "")
        XCTAssertFalse(view.validateMenuItem(prevItem), "没有履歴")
        run(30351)							// F_GOFILEEND：移动前的位置登记到履歴
        assertCaret(4, 1)
        XCTAssertTrue(view.validateMenuItem(prevItem))
        XCTAssertFalse(view.validateMenuItem(nextItem))
        run(30370)							// F_JUMPHIST_PREV
        assertCaret(2, 0)
        XCTAssertTrue(view.validateMenuItem(nextItem))
        run(30371)							// F_JUMPHIST_NEXT
        assertCaret(4, 1)
    }

    // MARK: - 画面

    /// １ページダウン／アップ：画面上的光标位置不变，翻一页
    func testPageMovesScroll() {
        load((1...200).map(String.init).joined(separator: "\n"))
        let rows = view.viewRowCount
        XCTAssertGreaterThan(rows, 5)
        run(30343)							// F_1PageDown
        XCTAssertEqual(view.caret.line, rows - 1)
        XCTAssertEqual(view.topVisibleRow, rows - 1, "画面也翻一页")
        run(30342)							// F_1PageUp
        XCTAssertEqual(view.caret.line, 0)
        XCTAssertEqual(view.topVisibleRow, 0)
        run(30341)							// F_HalfPageDown
        XCTAssertEqual(view.caret.line, rows / 2)
    }

    /// カーソル行をウィンドウ上部へ／中央へ、テキストを１行上へスクロール
    func testScrollCommands() {
        load((1...200).map(String.init).joined(separator: "\n"), caret: pos(100, 0))
        run(30361)							// F_CURLINETOP
        XCTAssertEqual(view.topVisibleRow, 100)
        run(30360)							// F_CURLINECENTER
        XCTAssertEqual(view.topVisibleRow, 100 - view.viewRowCount / 2)
        let top = view.topVisibleRow
        run(30381)							// F_WndScrollUp
        XCTAssertEqual(view.topVisibleRow, top + 1)
        XCTAssertEqual(view.caret.line, 100, "光标在画面里时不动")
        run(30386)							// F_WHEELDOWN：3 行
        XCTAssertEqual(view.topVisibleRow, top + 4)
    }

    // MARK: - 菜单

    /// 移动系的菜单项按功能编号执行（几个功能共用一个动作，用 tag 区分）
    func testMenuItemRunsCursorCommand() {
        load("abc def")
        let item = NSMenuItem(title: "", action: CommandTable.selector(for: 30321), keyEquivalent: "")
        item.tag = 30321
        XCTAssertTrue(view.validateMenuItem(item))
        view.perform(item.action, with: item)
        assertCaret(0, 4)
        XCTAssertNil(CommandTable.selector(for: 30384), "オートスクロール还没有移植")
    }
}

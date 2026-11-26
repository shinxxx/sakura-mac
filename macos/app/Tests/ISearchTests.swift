// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge
import XCTest

/// インクリメンタルサーチ（计划第 44 步，原版 view/CEditView_Cmdisrch.cpp）：
/// 文字の入力で検索、次の候補、Backspace で戻る、見つからないとき（次は先頭から）、正規表現、MIGEMO、
/// 他の機能・クリック・改行で抜ける、ステータスメッセージ、検索文字列の履歴と「次を検索」への引き継ぎ
final class ISearchTests: XCTestCase {
    private var window: NSWindow!
    private var view: EditorTextView!
    private var messages: [String?] = []
    private var savedSearch: EditorSearchSettings!
    private var savedDict = ""

    override func setUpWithError() throws {
        _ = TestCore.home
        _ = NSApplication.shared
        savedSearch = EditorCore.searchSettings
        savedDict = EditorCore.commonSetting(section: "Common", key: "szMigemoDict") ?? ""
        let document = try XCTUnwrap(EditorDocument())
        window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 600, height: 400),
                          styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
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
        view.isearchExit()
        EditorTextView.messageHandler = nil
        EditorCore.searchSettings = savedSearch
        _ = EditorCore.setCommonSetting(savedDict, section: "Common", key: "szMigemoDict")
        EditorCore.resetMigemo()
        window.close()
        window = nil
        view = nil
    }

    private func load(_ text: String) {
        XCTAssertEqual(view.document.insert(text, at: EditorPosition(line: 0, column: 0)), .success)
        view.contentDidChange()
        view.setCaret(pos(0, 0))
    }

    private func pos(_ line: Int, _ column: Int) -> EditorPosition { EditorPosition(line: line, column: column) }

    private func run(_ code: Int, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(CommandTable.perform(code, from: view), "功能 \(code) 已移植", file: file, line: line)
    }

    private func type(_ text: String) { view.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0)) }

    /// 選択範囲（[行, 桁, 行, 桁]）。選択していないときは nil
    private var selected: [Int]? {
        view.selection.map { [$0.from.line, $0.from.column, $0.to.line, $0.to.column] }
    }

    func testForwardTypingAndNext() {
        load("abc abd\nxab abc\n")
        run(30981)
        XCTAssertTrue(view.isearch.isActive)
        XCTAssertEqual(view.statusMessage.trimmingCharacters(in: .whitespaces), "I-Search:")
        type("a")
        XCTAssertEqual(selected, [0, 0, 0, 1])
        XCTAssertEqual([view.caret.line, view.caret.column], [0, 0], "カーソルは見つかった範囲の先頭")
        type("bd")
        XCTAssertEqual(selected, [0, 4, 0, 7], "abd")
        XCTAssertEqual(view.statusMessage.trimmingCharacters(in: .whitespaces), "I-Search: abd")
        // Backspace：1 文字前の状態（ab の位置）に戻る
        view.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
        XCTAssertEqual(selected, [0, 0, 0, 2])
        XCTAssertEqual(view.searchState.key, "ab")
        // 同じ機能でもう一度：次の候補
        run(30981)
        XCTAssertEqual(selected, [0, 4, 0, 6])
        run(30981)
        XCTAssertEqual(selected, [1, 1, 1, 3])
        // Backspace は「次」の前に戻る（検索文字列はそのまま）
        view.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
        XCTAssertEqual(selected, [0, 4, 0, 6])
        XCTAssertEqual(view.searchState.key, "ab")
    }

    /// 見つからない：「 (見つかりません)」、次の「次を検索」は先頭から
    func testNotFoundAndWrap() {
        load("ab x\nab\n")
        view.setCaret(pos(1, 0))
        run(30981)
        type("ab")
        XCTAssertEqual(selected, [1, 0, 1, 2])
        run(30981)
        XCTAssertTrue(view.statusMessage.contains("(見つかりません)"))
        XCTAssertEqual(selected, [1, 0, 1, 2], "見つからないときは動かない")
        run(30981)
        XCTAssertEqual(selected, [0, 0, 0, 2], "先頭から再検索")
        type("z")
        XCTAssertTrue(view.statusMessage.hasSuffix("abz (見つかりません) "))
    }

    func testBackward() {
        load("ab ab ab\n")
        view.setCaret(pos(0, 8))
        run(30982)
        XCTAssertEqual(view.statusMessage.trimmingCharacters(in: .whitespaces), "I-Search Backward:")
        type("ab")
        XCTAssertEqual(selected, [0, 6, 0, 8])
        run(30982)
        XCTAssertEqual(selected, [0, 3, 0, 5])
        // 方向を変える：前方へ
        run(30981)
        XCTAssertEqual(selected, [0, 6, 0, 8])
    }

    /// 正規表現インクリメンタルサーチ（大文字小文字は区別しない）。途中の不完全な正規表現は見つからないだけ
    func testRegexp() {
        load("x1 A2 b3\n")
        run(30983)
        XCTAssertTrue(view.statusMessage.contains("[RegExp] I-Search: "))
        type("[ab]")
        XCTAssertEqual(selected, [0, 3, 0, 4])
        type("\\d")
        XCTAssertEqual(selected, [0, 3, 0, 5])
        type("(")
        XCTAssertTrue(view.statusMessage.contains("(見つかりません)"))
        XCTAssertEqual(messages.count, 0, "エラーのダイアログは出さない")
    }

    /// 改行・他の機能・クリックで抜ける。抜けると検索文字列は履歴に入り、「次を検索」で使える
    func testExit() {
        load("foo bar foo\n")
        run(30981)
        type("foo")
        view.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        XCTAssertFalse(view.isearch.isActive)
        XCTAssertEqual(view.document.text, "foo bar foo\n", "改行は入力されない")
        XCTAssertEqual(view.statusMessage, "")
        XCTAssertEqual(EditorCore.searchKeyHistory.first, "foo")
        view.setCaret(pos(0, 1))
        view.searchNext(nil)
        XCTAssertEqual(selected, [0, 8, 0, 11], "次を検索は I-Search の文字列")
        // 他のキー割り当ての機能（Esc＝各種モードの取り消し）
        run(30981)
        XCTAssertTrue(view.isearch.isActive)
        XCTAssertTrue(view.isearchHandleKey(code: 31099) == false)
        XCTAssertFalse(view.isearch.isActive)
        // 矢印キー（Mac の編集キー）
        run(30981)
        view.doCommand(by: #selector(NSResponder.moveRight(_:)))
        XCTAssertFalse(view.isearch.isActive)
    }

    /// TAB・スペースは検索文字として（原版 F_INDENT_TAB → F_ISEARCH_ADD_CHAR）、Backspace の機能は 1 文字戻る
    func testTabAndSpaceKeys() {
        load("a\tb c\n")
        run(30981)
        type("a")
        XCTAssertTrue(view.isearchHandleKey(code: 30260))	// F_INDENT_TAB
        XCTAssertEqual(selected, [0, 0, 0, 2])
        type("b")
        XCTAssertTrue(view.isearchHandleKey(code: 30262))	// F_INDENT_SPACE
        XCTAssertEqual(view.searchState.key, "a\tb ")
        XCTAssertTrue(view.isearchHandleKey(code: 30222))	// F_DELETE_BACK
        XCTAssertEqual(view.searchState.key, "a\tb")
        XCTAssertEqual(view.document.text, "a\tb c\n")
    }

    /// メニューのチェック（原版 IsISearchEnabled）
    func testMenuCheck() {
        load("a\n")
        run(30982)
        let item = NSMenuItem(title: "", action: #selector(EditorTextView.isearchCommand(_:)), keyEquivalent: "")
        item.tag = 30982
        XCTAssertTrue(view.validateMenuItem(item))
        XCTAssertEqual(item.state, .on)
        item.tag = 30981
        _ = view.validateMenuItem(item)
        XCTAssertEqual(item.state, .off)
    }

    /// MIGEMO：辞書がないと「MIGEMOは使用できません。」。共通設定の辞書のフォルダーがあれば、ローマ字で日本語を探す
    func testMigemo() throws {
        load("今日はサクラエディタで\n")
        let missing = TestCore.home.appendingPathComponent("no-migemo-dict").path
        _ = EditorCore.setCommonSetting(missing, section: "Common", key: "szMigemoDict")
        EditorCore.resetMigemo()
        run(30985)
        XCTAssertFalse(view.isearch.isActive)
        XCTAssertEqual(view.statusMessage.trimmingCharacters(in: .whitespaces), "MIGEMOは使用できません。")
        XCTAssertEqual(messages, [nil], "蜂鸣")

        let dict = TestCore.home.appendingPathComponent("migemo-dict")
        try? FileManager.default.removeItem(at: dict)
        try FileManager.default.createDirectory(at: dict, withIntermediateDirectories: true)
        // 仓库里的测试用词典（externals/cmigemo-dict，与核心库测试相同。App 不附带）
        let zip = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../externals/cmigemo-dict/cmigemo-dict-utf-8.zip").standardizedFileURL
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", zip.path, dict.path]
        try unzip.run()
        unzip.waitUntilExit()
        XCTAssertTrue(FileManager.default.fileExists(atPath: dict.appendingPathComponent("utf-8/migemo-dict").path))
        _ = EditorCore.setCommonSetting(dict.path, section: "Common", key: "szMigemoDict")
        EditorCore.resetMigemo()
        run(30985)
        XCTAssertTrue(view.isearch.isActive)
        XCTAssertTrue(view.statusMessage.contains("[Migemo] I-Search: "))
        type("sakura")
        XCTAssertEqual(selected, [0, 3, 0, 6])
    }

    /// ステータスメッセージは編集画面の左下のラベル。I-Search 以外（▼先頭から再検索しました）は数秒で消える
    func testStatusMessageLabel() throws {
        load("a\n")
        view.sendStatusMessage("▼先頭から再検索しました")
        let label = try XCTUnwrap(view.statusLabel)
        XCTAssertFalse(label.isHidden)
        XCTAssertTrue(label.superview === view.enclosingScrollView)
        XCTAssertGreaterThanOrEqual(label.frame.minX, view.gutterWidth)
        XCTAssertLessThanOrEqual(label.frame.maxX, view.enclosingScrollView!.bounds.width)
        let fitting = label.fittingSize.width
        XCTAssertGreaterThanOrEqual(label.frame.width + 0.5, fitting, "文字が切れない")
        let hidden = expectation(description: "消える")
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) {
            if label.isHidden { hidden.fulfill() }
        }
        wait(for: [hidden], timeout: 6)
    }
}

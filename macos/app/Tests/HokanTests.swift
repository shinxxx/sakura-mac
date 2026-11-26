// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge
import XCTest

/// 入力補完（F_HOKAN）とキーワードヘルプ（F_TOGGLE_KEY_SEARCH・辞書 Tip）（计划第 44 步）。
/// 候補の探し方・辞書の検索は核心库的测试（test-mac-edit-support.cpp）で確認
final class HokanTests: XCTestCase {
    private var window: NSWindow!
    private var view: EditorTextView!
    private var messages: [String?] = []
    private var saved: [(section: String, key: String, value: String)] = []
    private var directory: URL!

    override func setUpWithError() throws {
        _ = TestCore.home
        _ = NSApplication.shared
        let document = try XCTUnwrap(EditorDocument())
        window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        view = EditorTextView(document: document)
        scrollView.documentView = view
        window.contentView = scrollView
        window.makeFirstResponder(view)
        view.contentDidChange()
        messages = []
        EditorTextView.messageHandler = { [weak self] in self?.messages.append($0) }
        directory = TestCore.home.appendingPathComponent("hokan-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        view.hokanHide()
        EditorTextView.messageHandler = nil
        EditorTextView.useCaretKeyWord = false
        for s in saved.reversed() { _ = EditorCore.setCommonSetting(s.value, section: s.section, key: s.key) }
        saved = []
        _ = view.document.applyTypeSettingChange(view.document.typeIndex)
        window.close()
        window = nil
        view = nil
        try? FileManager.default.removeItem(at: directory)
    }

    /// 設定を変える（終わったら戻す）
    private func set(_ section: String, _ key: String, _ value: String) {
        saved.append((section, key, EditorCore.commonSetting(section: section, key: key) ?? ""))
        _ = EditorCore.setCommonSetting(value, section: section, key: key)
    }

    private func setType(_ values: [String: String]) {
        let section = "Types(\(view.document.typeIndex))"
        for (key, value) in values { set(section, key, value) }
        _ = view.document.applyTypeSettingChange(view.document.typeIndex)
        view.typeSettingsReloaded()
    }

    private func load(_ text: String, caret: EditorPosition) {
        XCTAssertEqual(view.document.insert(text, at: EditorPosition(line: 0, column: 0)), .success)
        view.contentDidChange()
        view.setCaret(caret)
    }

    private func key(_ code: Int) -> NSEvent {
        let s = String(utf16CodeUnits: [unichar(code)], count: 1)
        return NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                context: nil, characters: s, charactersIgnoringModifiers: s, isARepeat: false, keyCode: 0)!
    }

    private var line0: String { view.document.line(at: 0) }

    // MARK: - 入力補完

    /// 補完対象がない：蜂鸣とステータスメッセージ
    func testNoWord() {
        setType(["bUseHokanByFile": "1", "szHokanFile": "", "bUseHokanByKeyword": "0"])
        load("abc ", caret: EditorPosition(line: 0, column: 4))
        CommandTable.perform(31430, from: view)
        XCTAssertEqual(messages, [nil])
        XCTAssertEqual(view.statusMessage.trimmingCharacters(in: .whitespaces), "補完対象がありません")
        XCTAssertFalse(view.hokanActive)
    }

    /// 候補が 1 つ：窓口を出さずにすぐ決める
    func testSingleCandidateIsDecided() {
        setType(["bUseHokanByFile": "1", "szHokanFile": "", "bUseHokanByKeyword": "0", "bHokanLoHiCase": "0"])
        load("unique_name\nuni", caret: EditorPosition(line: 1, column: 3))
        CommandTable.perform(31430, from: view)
        XCTAssertEqual(view.document.line(at: 1), "unique_name")
        XCTAssertFalse(view.hokanActive)
    }

    /// 候補が複数：並べた一覧、↑↓ で選んで Return で決める（Return が決定キーのとき）。入力で絞り込み、Backspace で広がる
    func testListAndDecide() throws {
        setType(["bUseHokanByFile": "1", "szHokanFile": "", "bUseHokanByKeyword": "0", "bHokanLoHiCase": "0"])
        set("Common", "bHokanKey_RETURN", "1")
        set("Common", "bHokanKey_TAB", "0")
        load("print_r printf println\npr", caret: EditorPosition(line: 1, column: 2))
        CommandTable.perform(31430, from: view)
        XCTAssertTrue(view.hokanActive)
        let hokan = try XCTUnwrap(view.hokanWindow)
        XCTAssertTrue(hokan.isVisible)
        XCTAssertEqual(hokan.words, ["print_r", "printf", "println"])
        XCTAssertEqual(hokan.selectedWord, "print_r")
        XCTAssertTrue(view.hokanHandleKey(key(NSDownArrowFunctionKey)))
        XCTAssertEqual(hokan.selectedWord, "printf")
        XCTAssertFalse(view.hokanHandleKey(key(NSTabCharacter)), "Tab は決定キーではない")
        // 入力で絞り込む
        view.insertText("intl", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(hokan.words, ["println"])
        view.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
        XCTAssertEqual(hokan.words, ["print_r", "printf", "println"])
        XCTAssertTrue(view.hokanHandleKey(key(NSEndFunctionKey)))
        XCTAssertTrue(view.hokanHandleKey(key(NSCarriageReturnCharacter)))
        XCTAssertEqual(view.document.line(at: 1), "println")
        XCTAssertFalse(view.hokanActive)
        XCTAssertFalse(hokan.isVisible)
        XCTAssertTrue(view.document.canUndo)
    }

    /// 補完ファイル（タイプ別設定『支援』）、英大文字小文字の同一視。単語の区切りの入力・ほかの機能で閉じる
    func testHokanFileAndClose() throws {
        let file = directory.appendingPathComponent("words.kwd")
        try "Alpha\nalphabet\nbeta\n".write(to: file, atomically: true, encoding: .utf8)
        setType(["bUseHokanByFile": "0", "szHokanFile": file.path, "bUseHokanByKeyword": "0", "bHokanLoHiCase": "1"])
        load("al", caret: EditorPosition(line: 0, column: 2))
        CommandTable.perform(31430, from: view)
        let hokan = try XCTUnwrap(view.hokanWindow)
        XCTAssertEqual(hokan.words, ["Alpha", "alphabet"])
        view.insertText(" ", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertFalse(view.hokanActive, "単語でなくなった")
        CommandTable.perform(31430, from: view)
        XCTAssertFalse(view.hokanActive, "空白の後ろには単語がない")
        view.setCaret(EditorPosition(line: 0, column: 2))
        CommandTable.perform(31430, from: view)
        XCTAssertTrue(view.hokanActive)
        view.hokanPreprocess(code: 30902)	// 次を検索：ほかの機能
        XCTAssertFalse(view.hokanActive)
        CommandTable.perform(31430, from: view)
        view.doCommand(by: #selector(NSResponder.moveLeft(_:)))
        XCTAssertFalse(view.hokanActive, "編集キーでも閉じる")
    }

    // MARK: - キーワードヘルプ

    private func makeDictionary() throws -> URL {
        let dict = directory.appendingPathComponent("help.khp")
        try "printf /// print formatted\\noutput\nstrlen /// length\n".write(to: dict, atomically: true, encoding: .utf8)
        setType(["bUseKeyWordHelp": "1", "KDct[00]": "1,help,\(dict.path)", "bUseKeyHelpAllSearch": "0",
                 "bUseKeyHelpKeyDisp": "0", "bUseKeyHelpPrefix": "0"])
        return dict
    }

    /// 選択範囲の単語、なければ（キーワードヘルプ自動表示が ON のとき）キャレット位置の単語を辞書で探して Tip に出す
    func testKeywordTip() throws {
        _ = try makeDictionary()
        load("call printf here", caret: EditorPosition(line: 0, column: 6))
        XCTAssertTrue(view.document.usesKeywordHelp)
        XCTAssertNil(view.keywordHelpKey(), "自動表示が OFF：キャレットの単語は使わない")
        CommandTable.perform(31431, from: view)
        XCTAssertTrue(EditorTextView.useCaretKeyWord)
        XCTAssertEqual(view.keywordHelpKey(), "printf")
        let item = NSMenuItem(title: "", action: #selector(EditorTextView.toggleKeySearch(_:)), keyEquivalent: "")
        _ = view.validateMenuItem(item)
        XCTAssertEqual(item.state, .on)
        XCTAssertTrue(view.showKeywordTip("printf", at: NSPoint(x: 300, y: 300)))
        let tip = try XCTUnwrap(view.keywordTip)
        XCTAssertTrue(tip.isVisible)
        XCTAssertEqual(tip.label.stringValue, "print formatted\noutput")
        XCTAssertGreaterThanOrEqual(tip.label.frame.width + 0.5, tip.label.sizeThatFits(NSSize(width: 480, height: 1000)).width, "文字が切れない")
        view.restartKeywordTipTimer()
        XCTAssertFalse(tip.isVisible, "キー・マウスで消える")
        XCTAssertFalse(view.showKeywordTip("nothing", at: .zero))
        // 選択範囲が優先
        view.setSelection(from: EditorPosition(line: 0, column: 12), to: EditorPosition(line: 0, column: 16))
        XCTAssertEqual(view.keywordHelpKey(), "here")
    }

    /// 補完ウィンドウで選んでいる単語のキーワードヘルプを右に出す（原版 CHokanMgr::ShowTip）
    func testHokanShowsTip() throws {
        _ = try makeDictionary()
        setType(["bUseHokanByFile": "1", "szHokanFile": "", "bUseHokanByKeyword": "0", "bHokanLoHiCase": "0"])
        load("printf print_x\npr", caret: EditorPosition(line: 1, column: 2))
        CommandTable.perform(31430, from: view)
        let hokan = try XCTUnwrap(view.hokanWindow)
        XCTAssertEqual(hokan.selectedWord, "print_x")
        XCTAssertTrue(view.hokanHandleKey(key(NSDownArrowFunctionKey)))
        let tip = try XCTUnwrap(view.keywordTip)
        XCTAssertTrue(tip.isVisible)
        XCTAssertEqual(tip.label.stringValue, "print formatted\noutput")
        XCTAssertEqual(tip.frame.minX, hokan.panel.frame.maxX, accuracy: 1, "補完ウィンドウの右")
    }
}

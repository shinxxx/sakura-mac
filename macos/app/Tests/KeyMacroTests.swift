// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge
import XCTest

/// キーマクロ（第 45 步）：記録（入力・キー・キー割り当て・ダイアログ）→ RecKey.mac → 実行（一つの取り消し単位）、
/// 保存・読み込み（ファイルの選択は差し替え）、読み込みエラーのメッセージ、記録する引数（原版 AddLParam）、
/// MacroHost の命令・関数（原版 HandleCommand・HandleFunction）。
/// キーマクロの文法と保存の形式は核心库的测试（test-mac-macro.cpp）で確かめる
final class KeyMacroTests: XCTestCase {
    private var window: NSWindow!
    private var view: EditorTextView!
    private var errors: [(String, String)] = []
    private var messages: [String?] = []
    private var savedSearch: EditorSearchSettings!
    private var tempDir: URL!
    private var savedChooseSave: ((String, NSWindow?) -> URL?)!
    private var savedChooseOpen: ((String, NSWindow?) -> URL?)!

    override func setUpWithError() throws {
        _ = TestCore.home
        _ = NSApplication.shared
        savedSearch = EditorCore.searchSettings
        let document = try XCTUnwrap(EditorDocument())
        window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 600, height: 400),
                          styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        view = EditorTextView(document: document)
        view.pasteboard = NSPasteboard(name: NSPasteboard.Name("SakuraKeyMacroTests"))
        scrollView.documentView = view
        window.contentView = scrollView
        window.makeFirstResponder(view)
        view.contentDidChange()
        errors = []
        messages = []
        MacroHost.showError = { [weak self] in self?.errors.append(($0, $1)) }
        EditorTextView.messageHandler = { [weak self] in self?.messages.append($0) }
        savedChooseSave = EditorTextView.chooseKeyMacroSaveURL
        savedChooseOpen = EditorTextView.chooseKeyMacroOpenURL
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("KeyMacroTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: KeyMacroRecorder.macroFolder, withIntermediateDirectories: true)
        KeyMacroRecorder.shared.keyMacroFileName = ""
        KeyMacroRecorder.shared.calls = []
    }

    override func tearDown() {
        if KeyMacroRecorder.shared.isRecording { KeyMacroRecorder.shared.stop() }
        KeyMacroRecorder.shared.keyMacroFileName = ""
        EditorTextView.chooseKeyMacroSaveURL = savedChooseSave
        EditorTextView.chooseKeyMacroOpenURL = savedChooseOpen
        EditorTextView.messageHandler = nil
        EditorCore.searchSettings = savedSearch
        try? FileManager.default.removeItem(at: tempDir)
        try? FileManager.default.removeItem(atPath: KeyMacroRecorder.recordFilePath)
        window.close()
        window = nil
        view = nil
    }

    private func load(_ text: String) {
        XCTAssertEqual(view.document.insert(text, at: EditorPosition(line: 0, column: 0)), .success)
        view.contentDidChange()
        view.setCaret(pos(0, 0))
    }

    private func clearText() {
        view.clearSelection()
        view.document.delete(EditorRange(from: pos(0, 0), to: view.document.endPosition))
        view.contentDidChange()
        view.setCaret(pos(0, 0))
    }

    private func pos(_ line: Int, _ column: Int) -> EditorPosition { EditorPosition(line: line, column: column) }
    private func str(_ p: EditorPosition) -> String { "\(p.line):\(p.column)" }

    private func type(_ text: String) {
        view.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    /// 記録した行（名前と引数）
    private var recorded: [String] {
        KeyMacroRecorder.shared.calls.map { call in
            let name = MacroCore.function(code: call.code)?.name ?? "?"
            return name + "(" + call.args.map { $0.isString ? "'\($0.text)'" : $0.text }.joined(separator: ", ") + ")"
        }
    }

    // MARK: - 記録 → RecKey.mac → 実行

    func testRecordStopExecReproducesEdits() throws {
        view.recKeyMacro(nil)
        XCTAssertTrue(KeyMacroRecorder.shared.isRecording(in: window))
        type("ab")											// Char(97) Char(98)
        view.doCommand(by: #selector(NSResponder.insertNewline(_:)))	// Char(13)
        type("c")
        XCTAssertTrue(CommandTable.perform(30313, from: view))	// F_LEFT（キー割り当て）
        view.doCommand(by: #selector(NSResponder.moveLeft(_:)))	// F_LEFT（矢印キー）
        type("X")
        view.doCommand(by: #selector(NSResponder.deleteForward(_:)))	// F_DELETE
        XCTAssertEqual("abXc", view.document.text)	// 二つ目の ← で前の行の末尾、Delete で改行を削除
        view.recKeyMacro(nil)
        XCTAssertFalse(KeyMacroRecorder.shared.isRecording)
        XCTAssertEqual(["Char(97)", "Char(98)", "Char(13)", "Char(99)", "Left(0)", "Left(0)", "Char(88)", "Delete(0)"], recorded)

        // マクロ用フォルダーの RecKey.mac（原版と同じ形式）
        let path = KeyMacroRecorder.recordFilePath
        XCTAssertEqual(path, KeyMacroRecorder.shared.keyMacroFileName)
        let saved = try String(contentsOfFile: path, encoding: .utf8)
        XCTAssertTrue(saved.hasPrefix("//キーボードマクロのファイル\r\nChar(97);\t// "), saved)
        XCTAssertTrue(saved.contains("Left(0);\t// "), saved)
        XCTAssertTrue(errors.isEmpty)

        // 実行すると同じ編集になり、一回の「元に戻す」で全部戻る
        let before = view.document.text
        view.execKeyMacro(nil)
        XCTAssertEqual("abXabXcc", view.document.text)	// カーソル（X の後）から同じ操作
        view.undo(nil)
        XCTAssertEqual(before, view.document.text)
        XCTAssertTrue(errors.isEmpty, "\(errors)")
    }

    func testOtherWindowDoesNotRecord() throws {
        let other = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false
        defer { other.close() }
        KeyMacroRecorder.shared.start(in: other)
        type("a")
        XCTAssertTrue(recorded.isEmpty)
        // 記録中は記録しているウィンドウでしか記録開始／終了・実行できない（原版 IsFuncEnable）
        let item = NSMenuItem(title: "", action: #selector(EditorTextView.recKeyMacro(_:)), keyEquivalent: "")
        item.tag = MacroHost.Code.recKeyMacro
        XCTAssertEqual(false, view.validateKeyMacroMenuItem(item))
        XCTAssertEqual("キーマクロの記録終了", item.title)
        // 記録中のウィンドウを閉じたら記録をやめる（保存しない）
        other.close()
        XCTAssertFalse(KeyMacroRecorder.shared.isRecording)
    }

    func testMenuTitlesAndEnabled() {
        func item(_ code: Int, _ action: Selector) -> NSMenuItem {
            let item = NSMenuItem(title: "x", action: action, keyEquivalent: "")
            item.tag = code
            return item
        }
        let rec = item(31250, #selector(EditorTextView.recKeyMacro(_:)))
        let save = item(31251, #selector(EditorTextView.saveKeyMacro(_:)))
        let loadItem = item(31252, #selector(EditorTextView.loadKeyMacro(_:)))
        let exec = item(31253, #selector(EditorTextView.execKeyMacro(_:)))
        XCTAssertTrue(view.validateMenuItem(rec))
        XCTAssertEqual("キーマクロの記録開始", rec.title)
        XCTAssertFalse(view.validateMenuItem(exec), "ファイル名がないときは実行できない")
        XCTAssertEqual("キーマクロの実行", exec.title)
        view.recKeyMacro(nil)
        for i in [rec, save, loadItem, exec] { XCTAssertTrue(view.validateMenuItem(i)) }
        XCTAssertEqual(["キーマクロの記録終了", "キーマクロの記録終了&保存", "キーマクロの記録終了&読み込み", "キーマクロの記録終了&実行"],
                       [rec, save, loadItem, exec].map(\.title))
        view.recKeyMacro(nil)
        XCTAssertTrue(view.validateMenuItem(exec))
        XCTAssertTrue(view.validateMenuItem(save))
        XCTAssertEqual("キーマクロの保存", save.title)
        // CommandTable と既定のメニュー（ツール）にある
        for code in 31250...31253 { XCTAssertNotNil(CommandTable.selector(for: code)) }
    }

    func testDefaultMainMenuHasKeyMacroItems() {
        // 既定のメインメニュー（原版 MainMenu.ini）のツールにある。MainMenuBuilder.build() は NSApp.windowsMenu を変えるので呼ばない
        let commands = Set(EditorCore.mainMenu.filter { $0.type == .command }.map(\.command))
        for code in 31250...31253 { XCTAssertTrue(commands.contains(code), "\(code)") }
    }

    // MARK: - 保存・読み込み・実行

    func testSaveLoadExecWithPanels() throws {
        load("hello\n")
        view.recKeyMacro(nil)
        XCTAssertTrue(CommandTable.perform(30451, from: view))	// F_GOFILEEND_SEL（すべて選択の代わり）
        view.macroInsertText("")	// 記録しない（マクロの中からの操作）
        type("Z")
        let saveURL = tempDir.appendingPathComponent("mine.mac")
        EditorTextView.chooseKeyMacroSaveURL = { folder, _ in
            XCTAssertEqual(KeyMacroRecorder.macroFolder, folder)
            return saveURL
        }
        view.saveKeyMacro(nil)	// 記録をやめて保存（RecKey.mac には保存しない）
        XCTAssertFalse(KeyMacroRecorder.shared.isRecording)
        XCTAssertFalse(FileManager.default.fileExists(atPath: KeyMacroRecorder.recordFilePath))
        let text = try String(contentsOf: saveURL, encoding: .utf8)
        XCTAssertTrue(text.contains("GoFileEnd_Sel(0);"), text)
        XCTAssertTrue(text.contains("Char(90);"), text)

        // 読み込みはファイル名を覚えるだけ。実行の直前に読む（読み込んだ後にファイルを変えると変えた内容で実行）
        EditorTextView.chooseKeyMacroOpenURL = { _, _ in saveURL }
        view.loadKeyMacro(nil)
        XCTAssertEqual(saveURL.path, KeyMacroRecorder.shared.keyMacroFileName)
        try "InsText('1\\t2');\r\nAddTail('-end');\r\n".write(to: saveURL, atomically: true, encoding: .utf8)
        clearText()
        load("ab")
        view.execKeyMacro(nil)
        XCTAssertEqual("1\t2ab-end", view.document.text)
        XCTAssertEqual("0:9", str(view.caret))
        XCTAssertTrue(errors.isEmpty, "\(errors)")

        // キャンセル
        EditorTextView.chooseKeyMacroOpenURL = { _, _ in nil }
        view.loadKeyMacro(nil)
        XCTAssertEqual(saveURL.path, KeyMacroRecorder.shared.keyMacroFileName)
    }

    func testExecParseErrorShowsOriginalMessages() throws {
        let url = tempDir.appendingPathComponent("bad.mac")
        try "Down();\r\nNoSuch(1);\r\nUp();\r\n".write(to: url, atomically: true, encoding: .utf8)
        KeyMacroRecorder.shared.keyMacroFileName = url.path
        load("a\nb\n")
        view.execKeyMacro(nil)
        XCTAssertEqual(2, errors.count)
        XCTAssertEqual("Macro読み込みエラー", errors.first?.0)
        XCTAssertEqual("Line 2: NoSuchは存在しない関数です．\n", errors.first?.1)
        XCTAssertEqual(AboutPanel.appName, errors.last?.0)
        XCTAssertEqual("ファイルを開けませんでした。\n\n" + url.path, errors.last?.1)
        XCTAssertEqual("0:0", str(view.caret), "一行目の Down() も実行しない")

        // ないファイル
        errors = []
        KeyMacroRecorder.shared.keyMacroFileName = tempDir.appendingPathComponent("none.mac").path
        view.execKeyMacro(nil)
        XCTAssertEqual(["ファイルを開けませんでした。\n\n" + KeyMacroRecorder.shared.keyMacroFileName], errors.map(\.1))
    }

    // MARK: - 記録する引数（原版 AddLParam）

    func testRecordedArgsOfSearchReplaceJump() {
        load("foo bar foo\n2\n3\n")
        let s = EditorCore.searchSettings
        s.notifyNotFound = true
        s.searchAll = true
        s.autoCloseFind = false
        s.selectedArea = false
        s.consecutiveAll = true
        EditorCore.searchSettings = s
        view.recKeyMacro(nil)
        view.setSearchKey("foo", options: [.matchCase, .wholeWord])
        view.recordKeyMacro(MacroHost.Code.searchNext)
        view.recordKeyMacro(MacroHost.Code.searchPrev)
        view.recordKeyMacro(MacroHost.Code.bookmarkPattern)
        let options = EditorReplaceOptions(search: [.matchCase, .wholeWord], target: .insertAfter, paste: true,
                                           searchAll: true, consecutiveAll: true, selectedArea: false)
        view.recordKeyMacro(MacroHost.Code.replaceAll, replace: ("X", options))
        view.recordKeyMacro(MacroHost.Code.jump, jump: EditorJumpOptions(lineNumber: 3, lineNumIsCRLF: true, plsql: false, plsqlBlockFirstLine: 1))
        view.recKeyMacro(nil)
        XCTAssertEqual(["SearchNext('foo', 43)", "SearchPrev('foo', 43)", "BookmarkPattern('foo', 43)",
                        "ReplaceAll('foo', 'X', 1643)", "Jump(3, 1)"], recorded)
    }

    func testRecordedArgsOfBoxAndPageCommands() {
        load("abc\ndef\n")
        view.recKeyMacro(nil)
        XCTAssertTrue(CommandTable.perform(30512, from: view))	// F_DOWN_BOX
        XCTAssertTrue(CommandTable.perform(30343, from: view))	// F_1PageDown
        view.recKeyMacro(nil)
        let lock = view.document.editSettings.boxSelectLock ? 1 : 2
        XCTAssertEqual(["Down_BoxSel(\(lock))", "PageDown(\(view.viewRowCount - 1))"], recorded)
    }

    func testIMEAndSurrogateRecording() {
        view.recKeyMacro(nil)
        view.recordKeyMacro(typed: "あい", fromInputMethod: true)
        view.recordKeyMacro(typed: "😀", fromInputMethod: false)
        view.recKeyMacro(nil)
        XCTAssertEqual(["CharIme(12354)", "CharIme(12356)", "InsText('😀')"], recorded)
        KeyMacroRecorder.shared.calls.forEach { MacroHost.execute($0, view: view) }
        XCTAssertEqual("あい😀", view.document.text)
    }

    // MARK: - MacroHost の命令

    private func run(_ source: String) -> Bool {
        let r = MacroCore.parseKeyMacro(source)
        XCTAssertEqual(.success, r.result, r.errorMessage)
        view.runKeyMacro(r.calls)
        return errors.isEmpty
    }

    func testCommandsInsertMoveAndEol() {
        load("line1\nline2\nline3\n")
        XCTAssertTrue(run("Down(0);\r\nGoLineEnd(0);\r\nChar(9);\r\nInsText('x');\r\nCharIme(12354);"))
        XCTAssertEqual("line2\tx\u{3042}", view.document.line(at: 1))
        XCTAssertTrue(run("MoveCursor(3, 2, 0);\r\nInsText('_');"))
        XCTAssertEqual("l_ine3", view.document.line(at: 2))
        XCTAssertTrue(run("MoveCursor(1, 1, 0);\r\nMoveCursor(1, 3, 1);"))
        XCTAssertEqual(.int(1), MacroHost.handleFunction(MacroHost.Code.isTextSelected, [], view: view))
        XCTAssertEqual(.string("li"), MacroHost.handleFunction(MacroHost.Code.getSelected, [], view: view))
        XCTAssertEqual(.int(1), MacroHost.handleFunction(MacroHost.Code.getSelLineFrom, [], view: view))
        XCTAssertEqual(.int(3), MacroHost.handleFunction(MacroHost.Code.getSelColumnTo, [], view: view))
        XCTAssertTrue(run("ChgmodEOL(3);"))	// LF
        XCTAssertEqual(.lf, view.document.newLineEol)
        XCTAssertEqual(.int(2), MacroHost.handleFunction(MacroHost.Code.getLineCode, [], view: view))
        XCTAssertTrue(run("ChgmodEOL(2);"))	// 2 は何もしない（原版）
        XCTAssertEqual(.lf, view.document.newLineEol)
        // 一つの取り消し単位
        let before = view.document.text
        XCTAssertTrue(run("GoFileEnd(0);\r\nInsText('A');\r\nInsText('B');\r\nChar(13);"))
        XCTAssertNotEqual(before, view.document.text)
        view.undo(nil)
        XCTAssertEqual(before, view.document.text)
    }

    func testCommandArgumentErrorsStopMacro() {
        load("abc")
        XCTAssertFalse(run("InsText();\r\nInsText('z');"))
        XCTAssertEqual("Macro実行エラー", errors.first?.0)
        XCTAssertEqual("引数(文字列)が指定されていません．", errors.first?.1)
        XCTAssertEqual("abc", view.document.text, "エラーのあとは実行しない")
        errors = []
        XCTAssertFalse(run("Char();"))
        XCTAssertEqual("挿入すべき文字コードが指定されていません．", errors.first?.1)
        errors = []
        XCTAssertFalse(run("Jump();"))
        XCTAssertEqual("ジャンプ先行番号が指定されていません．", errors.first?.1)
        errors = []
        XCTAssertFalse(run("Replace('a');"))
        XCTAssertEqual("置換先パターンが指定されていません．", errors.first?.1)
        errors = []
        XCTAssertFalse(run("MoveCursor(1);"))
        XCTAssertEqual("数値を指定してください．", errors.first?.1)
    }

    func testSearchReplaceJumpCommands() {
        load("foo Foo foo\nbar\nbaz\n")
        XCTAssertTrue(run("SearchNext('Foo', 2);"))	// 英大文字と小文字を区別する
        XCTAssertEqual(.string("Foo"), MacroHost.handleFunction(MacroHost.Code.getSelected, [], view: view))
        XCTAssertEqual("0:4", view.selection.map { str($0.from) })
        XCTAssertEqual("Foo", view.searchState.key)
        XCTAssertEqual("Foo", EditorCore.searchKeyHistory.first)
        XCTAssertTrue(run("SearchNext('ba.', 4);"))	// 正規表現
        XCTAssertEqual("1:0", view.selection.map { str($0.from) })
        // 0x800：履歴に登録しない、0x1000：検索条件を元に戻す
        XCTAssertTrue(run("SearchPrev('foo', 4096);"))
        XCTAssertEqual("ba.", view.searchState.key)
        XCTAssertEqual("ba.", EditorCore.searchKeyHistory.first)
        XCTAssertTrue(run("ReplaceAll('ba(.)', 'X$1', 4);"))
        XCTAssertEqual("foo Foo foo\nXr\nXz\n", view.document.text)
        view.setCaret(pos(0, 0))
        XCTAssertTrue(run("Replace('foo', 'q', 2);"))	// 置換して次を選ぶ
        XCTAssertEqual("q Foo foo\nXr\nXz\n", view.document.text)
        XCTAssertTrue(run("Jump(3, 1);"))
        XCTAssertEqual(2, view.caret.line)
        XCTAssertTrue(run("BookmarkPattern('X', 0);"))
        XCTAssertTrue(view.document.isBookmarked(1))
        XCTAssertFalse(view.document.isBookmarked(0))
        // 見つからない（0x08 メッセージを出す）
        messages = []
        XCTAssertTrue(run("SearchNext('nothing', 8);"))
        XCTAssertEqual(1, messages.count)
    }

    func testUnportedCommandIsIgnored() {
        load("abc")
        XCTAssertTrue(run("SetFontSize(10, 0, 0);\r\nInsText('z');"))
        XCTAssertEqual("zabc", view.document.text)
        XCTAssertTrue(MacroHost.handleCommand(99999, [], view: view))
    }

    // MARK: - MacroHost の関数

    func testFunctions() {
        load("first\nsecond\n")
        let doc = view.document
        func call(_ code: Int, _ args: [MacroValue] = []) -> MacroValue? { MacroHost.handleFunction(code, args, view: view) }
        XCTAssertEqual(.string("first\n"), call(MacroHost.Code.getLineStr, [.int(1)]).map { MacroValue.string($0.text.replacingOccurrences(of: "\r\n", with: "\n")) })
        XCTAssertEqual(.string("first"), call(MacroHost.Code.getLineStr, [.int(0)]).map { MacroValue.string($0.text.trimmingCharacters(in: .newlines)) })
        XCTAssertEqual(.string(""), call(MacroHost.Code.getLineStr, [.int(100)]))
        XCTAssertNil(call(MacroHost.Code.getLineStr, [.int(-1)]))
        XCTAssertEqual(.int(doc.lineCount), call(MacroHost.Code.getLineCount, [.int(0)]))
        XCTAssertNil(call(MacroHost.Code.getLineCount, [.int(1)]))
        XCTAssertEqual(.int(0), call(MacroHost.Code.isTextSelected))
        XCTAssertEqual(.string(""), call(MacroHost.Code.getSelected))
        XCTAssertEqual(.int(doc.insertMode ? 1 : 0), call(MacroHost.Code.isInsMode))
        XCTAssertEqual(.int(1), call(MacroHost.Code.isPossibleUndo))
        XCTAssertEqual(.int(0), call(MacroHost.Code.isPossibleRedo))
        XCTAssertEqual(.int(doc.encoding), call(MacroHost.Code.getCharCode))
        XCTAssertGreaterThan(call(MacroHost.Code.compareVersion, [.string("2.4.2"), .string("2.4.1")])?.intValue ?? 0, 0)
        XCTAssertEqual(.int(0), call(MacroHost.Code.compareVersion, [.string("2.4.1"), .string("2.4.1")]))
        XCTAssertEqual(.int(2), call(MacroHost.Code.layoutToLogicLineNum, [.int(2)]))
        XCTAssertEqual(.int(3), call(MacroHost.Code.lineColumnToIndex, [.int(1), .int(3)]))
        XCTAssertEqual(.int(2), call(MacroHost.Code.logicToLayoutLineNum, [.int(2), .int(1)]))
        XCTAssertEqual(.int(4), call(MacroHost.Code.lineIndexToColumn, [.int(1), .int(4)]))
        // ExpandParameter（$x $y はカーソルの桁・行）
        view.setCaret(pos(1, 2))
        XCTAssertEqual(.string("3:2"), call(MacroHost.Code.expandParameter, [.string("$x:$y")]))
        XCTAssertNil(call(MacroHost.Code.expandParameter))
        // Cookie
        XCTAssertEqual(.int(0), call(MacroHost.Code.setCookie, [.string("document"), .string("k"), .string("v")]))
        XCTAssertEqual(.string("v"), call(MacroHost.Code.getCookie, [.string("document"), .string("k")]))
        XCTAssertEqual(.string("d"), call(MacroHost.Code.getCookieDefault, [.string("window"), .string("none"), .string("d")]))
        XCTAssertEqual(.int(1), call(MacroHost.Code.setCookie, [.string("bad"), .string("k"), .string("v")]))
        XCTAssertEqual(.int(0), call(MacroHost.Code.deleteCookie, [.string("document"), .string("k")]))
        XCTAssertEqual(.string(""), call(MacroHost.Code.getCookieNames, [.string("document")]))
        // クリップボード
        XCTAssertEqual(.int(1), call(MacroHost.Code.setClipboard, [.int(0), .string("clip")]))
        XCTAssertEqual(.string("clip"), call(MacroHost.Code.getClipboard))
        XCTAssertTrue(MacroHost.handleCommand(MacroHost.Code.clipboardEmpty, [], view: view))
        XCTAssertEqual(.string(""), call(MacroHost.Code.getClipboard))
        // 再描画スイッチ・選択ロック・ビュー
        XCTAssertEqual(.int(1), call(MacroHost.Code.setDrawSwitch, [.int(0)]))
        XCTAssertEqual(.int(0), call(MacroHost.Code.getDrawSwitch))
        XCTAssertEqual(.int(0), call(MacroHost.Code.isTextSelectingLock))
        XCTAssertEqual(.int(view.viewRowCount), call(MacroHost.Code.getViewLines))
        XCTAssertEqual(.int(1), call(MacroHost.Code.getViewTop))
        XCTAssertEqual(.string(""), call(MacroHost.Code.getFilename))
        XCTAssertNil(call(40999))
    }

    func testMessageBoxFunctions() {
        var shown: [(String, Int)] = []
        let saved = MacroHost.messageBox
        defer { MacroHost.messageBox = saved }
        MacroHost.messageBox = { message, type in
            shown.append((message, type))
            return type & 0x0F == 4 ? 7 : 1
        }
        XCTAssertEqual(.int(7), MacroHost.handleFunction(MacroHost.Code.yesNoBox, [.string("q?")], view: view))
        XCTAssertEqual(.int(1), MacroHost.handleFunction(MacroHost.Code.infoMsg, [.string("i")], view: view))
        XCTAssertTrue(run("ErrorMsg('e');\r\nMessageBox('m', 1);"))
        XCTAssertEqual(["q?:36", "i:64", "e:16", "m:1"], shown.map { "\($0.0):\($0.1)" })
    }
}

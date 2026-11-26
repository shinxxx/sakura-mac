// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge
import XCTest

/// JScript マクロ（第 45 步）：原版のヘルプのサンプル（help/macro/source/sample の JScript の部分、Tests/MacroSamples/）と
/// tools/macro/CopyDirPath.js を実行して結果を確かめる。WScript.Shell の Popup・エラーのメッセージは差し替える。
/// ほかに：大文字小文字を区別しない名前・Editor.、エラーの行番号、ActiveXObject、ExecExternalMacro、登録マクロ、自動実行、キャンセル、記録しないこと
final class JSMacroTests: XCTestCase {
    private var window: NSWindow!
    private var view: EditorTextView!
    private var errors: [(String, String)] = []
    private var popups: [(text: String, title: String)] = []
    private var savedPopup: ((String, Int, String, Int) -> Int)!
    private var savedSettings: [String: String] = [:]
    private var tempDir: URL!

    override func setUpWithError() throws {
        _ = TestCore.home
        _ = NSApplication.shared
        let document = try XCTUnwrap(EditorDocument())
        window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        view = EditorTextView(document: document)
        view.pasteboard = NSPasteboard(name: NSPasteboard.Name("SakuraJSMacroTests"))
        scrollView.documentView = view
        window.contentView = scrollView
        window.makeFirstResponder(view)
        view.contentDidChange()
        errors = []
        popups = []
        MacroHost.showError = { [weak self] in self?.errors.append(($0, $1)) }
        savedPopup = JSMacroRunner.popup
        JSMacroRunner.popup = { [weak self] text, _, title, _ in
            self?.popups.append((text, title))
            return 1
        }
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("JSMacroTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        MacroCommands.forgetLoaded()
    }

    override func tearDown() {
        JSMacroRunner.popup = savedPopup
        JSMacroRunner.cancelPanelDidShow = nil
        var bySection: [String: [String: String]] = [:]
        for (key, value) in savedSettings {
            let parts = key.split(separator: "/", maxSplits: 1).map(String.init)
            bySection[parts[0], default: [:]][parts[1]] = value
        }
        for (section, values) in bySection { EditorCore.setCommonSettings(values, section: section) }
        savedSettings = [:]
        MacroCommands.forgetLoaded()
        try? FileManager.default.removeItem(at: tempDir)
        window.close()
        window = nil
        view = nil
    }

    /// 共通設定を一時的に変える（tearDown で戻す）。[Macro] の Name・File は一緒に読むので一度に書く
    private func setSettings(_ section: String, _ values: [String: String]) {
        for key in values.keys {
            let k = section + "/" + key
            if savedSettings[k] == nil { savedSettings[k] = EditorCore.commonSetting(section: section, key: key) ?? "" }
        }
        XCTAssertTrue(EditorCore.setCommonSettings(values, section: section), "\(values)")
    }

    private func setSetting(_ section: String, _ key: String, _ value: String) {
        setSettings(section, [key: value])
    }

    private func load(_ text: String) {
        XCTAssertEqual(view.document.insert(text, at: EditorPosition(line: 0, column: 0)), .success)
        view.contentDidChange()
        view.setCaret(EditorPosition(line: 0, column: 0))
    }

    private var text: String { view.document.text.replacingOccurrences(of: "\r\n", with: "\n") }

    private func samplePath(_ name: String) throws -> String {
        try XCTUnwrap(Bundle(for: Self.self).path(forResource: name, ofType: "js", inDirectory: "MacroSamples"), name)
    }

    /// ヘルプのサンプルを実行する（名前を指定してマクロ実行と同じ道）
    private func runSample(_ name: String) throws {
        view.execExternalMacro(path: try samplePath(name), type: nil)
        XCTAssertTrue(errors.isEmpty, "\(name): \(errors)")
    }

    @discardableResult
    private func runJS(_ source: String) -> Bool {
        JSMacroRunner(view: view, source: source, path: tempDir.appendingPathComponent("t.js").path).run()
    }

    // MARK: - ヘルプのサンプル

    func testSampleChar() throws {
        try runSample("SampleChar")
        // Unicode 版：Char は UTF-16 の一文字。CharIme(33440) は U+82A0
        XCTAssertEqual("\u{82}\u{A0}\u{82A0}あ", text)
    }

    func testSampleExpandParameter() throws {
        try runSample("SampleExpandParameter")
        XCTAssertEqual(1, popups.count)
        XCTAssertEqual("ファイル情報", popups.first?.title)
        XCTAssertTrue(popups.first?.text.hasPrefix("現在開いているファイルのタイムスタンプは\n") == true, popups.first?.text ?? "")
        XCTAssertTrue(popups.first?.text.hasSuffix("編集可能なファイルです。") == true, popups.first?.text ?? "")
    }

    func testSampleGetCharCode() throws {
        try runSample("SampleGetCharCode")
        let names = [0: "SJIS", 1: "JIS", 2: "EUC", 3: "Unicode", 4: "UTF-8", 5: "UTF-7", 6: "UnicodeBE"]
        let expected = names[view.document.encoding].map { $0 + "で開いています" } ?? "不明"
        XCTAssertEqual([expected], popups.map(\.text))
        XCTAssertEqual("現在の文字コード", popups.first?.title)
    }

    func testSampleGetFilename() throws {
        let url = tempDir.appendingPathComponent("a.txt")
        try "x\n".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(.success, view.document.open(path: url.path))
        view.contentDidChange()
        try runSample("SampleGetFilename")
        XCTAssertEqual(["ファイル名は\"\(url.path)\"です"], popups.map(\.text))
    }

    func testSampleGetLineCode() throws {
        try runSample("SampleGetLineCode")
        let names: [EditorEol: String] = [.crlf: "CRLF", .cr: "CR", .lf: "LF"]
        XCTAssertEqual([names[view.document.newLineEol] ?? "不明"], popups.map(\.text))
    }

    func testSampleGetLineCount() throws {
        // GetLineStr は改行も返すので、空行は ["\r\n"] == 0（Number は空白を捨てて 0）で数える。「0」だけの行も 0 と等しい
        load("abc\n\n0\n 0\n")
        try runSample("SampleGetLineCount")
        XCTAssertEqual(["3"], popups.map(\.text))
    }

    func testSampleGetLineStr() throws {
        load("first\nsecond\nlast")
        view.setCaret(EditorPosition(line: 1, column: 0))
        try runSample("SampleGetLineStr")
        let eol = EditorCore.text(ofEol: view.document.eol(ofLine: 0))
        XCTAssertEqual(["先頭行の内容は\nfirst\(eol)\n\n現在キャレット行の内容は\nsecond\(eol)\n\n最終行の内容は\nlast"], popups.map(\.text))
    }

    func testSampleGetSelectedString() throws {
        load("hello world")
        view.setSelection(from: EditorPosition(line: 0, column: 6), to: EditorPosition(line: 0, column: 11))
        try runSample("SampleGetSelectedString")
        XCTAssertEqual(["world"], popups.map(\.text))
        XCTAssertEqual("選択中の文字列", popups.first?.title)
    }

    func testSampleGetSelectxxx() throws {
        load("say hello now")
        view.setCaret(EditorPosition(line: 0, column: 5))
        try runSample("SampleGetSelectxxx")
        XCTAssertEqual(["5byte"], popups.map(\.text))
    }

    func testSampleIsInsMode() throws {
        try runSample("SampleIsInsMode")
        XCTAssertEqual([view.document.insertMode ? "挿入モードです" : "上書モードです"], popups.map(\.text))
    }

    func testSampleIsPossibleUndo() throws {
        view.insertText("abc", replacementRange: NSRange(location: NSNotFound, length: 0))
        view.insertText("def", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(view.document.canUndo)
        try runSample("SampleIsPossibleUndo")
        XCTAssertEqual("", text)
        XCTAssertFalse(view.document.canUndo)
    }

    func testSampleIsTextSelected() throws {
        load("abc def")
        try runSample("SampleIsTextSelected")
        view.setSelection(from: EditorPosition(line: 0, column: 0), to: EditorPosition(line: 0, column: 3))
        try runSample("SampleIsTextSelected")
        XCTAssertEqual(["選択されたテキストはありません。", "選択中の文字列は\n\nabc"], popups.map(\.text))
    }

    func testCopyDirPath() throws {
        let url = tempDir.appendingPathComponent("b.txt")
        try "x".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(.success, view.document.open(path: url.path))
        view.contentDidChange()
        view.execExternalMacro(path: try XCTUnwrap(Bundle(for: Self.self).path(forResource: "CopyDirPath", ofType: "js", inDirectory: "MacroSamples")), type: nil)
        XCTAssertTrue(errors.isEmpty, "\(errors)")
        XCTAssertEqual(tempDir.path, view.clipboardText)
    }

    // MARK: - 名前・引数・戻り値

    func testNamesAreCaseInsensitiveAndEditorObject() {
        load("abc")
        XCTAssertTrue(runJS("insText('1'); Editor.InsText('2'); editor_dummy = typeof NoSuchName; INSTEXT(String(GetLineCount(0)));\nEditor.GoFileEnd(); Editor.AddTail(typeof Editor.NoSuch);"), "\(errors)")
        XCTAssertEqual("121abcundefined", text)
        XCTAssertTrue(errors.isEmpty, "\(errors)")
        // 括弧なし（前処理で () を足す）、var で宣言した名前は変えない
        XCTAssertTrue(runJS("var n = IsTextSelected; GoFileTop; var Left = 'L'; InsText(n + Left);"))
        XCTAssertEqual("0L121abcundefined", text)
    }

    func testArgumentConversion() {
        // 命令の引数は文字列に（数値は整数、真偽は True/False）、関数の戻り値は数値・文字列
        XCTAssertTrue(runJS("InsText(12); InsText(1.5); InsText(true); InsText(null); var t = typeof GetLineCount(0) + typeof GetLineStr(1); InsText(t);"))
        XCTAssertEqual("121.5Truenumberstring", text)
        // 関数が失敗すると例外（原版 E_FAIL）
        XCTAssertFalse(runJS("var x = 1;\nGetLineCount(5);"))
        XCTAssertEqual("JScript 実行時エラー", errors.first?.0)
        XCTAssertEqual("[Line 2] エラーを特定できません", errors.first?.1)
    }

    func testScriptErrors() {
        XCTAssertFalse(runJS("InsText('a');\nvar x = ;"))
        XCTAssertEqual("JScript コンパイル エラー", errors.first?.0)
        XCTAssertTrue(errors.first?.1.hasPrefix("[Line 2] ") == true, "\(errors)")
        XCTAssertEqual("", text, "文法の誤りがあれば何もしない")
        errors = []
        XCTAssertFalse(runJS("InsText('a');\n\nfoo();\nInsText('b');"))
        XCTAssertEqual("JScript 実行時エラー", errors.first?.0)
        XCTAssertTrue(errors.first?.1.hasPrefix("[Line 3] ") == true, "\(errors)")
        XCTAssertEqual("a", text, "誤りの前までは実行する")
        // 一回の元に戻すで全部戻る
        view.undo(nil)
        XCTAssertEqual("", text)
    }

    func testActiveXObject() {
        XCTAssertTrue(runJS("var s = new ActiveXObject('WScript.Shell'); var r = s.Popup('hi', 0, 'T', 0); InsText(String(r));"))
        XCTAssertEqual("1", text)
        XCTAssertEqual(["hi"], popups.map(\.text))
        XCTAssertFalse(runJS("var fso = new ActiveXObject('Scripting.FileSystemObject');"))
        XCTAssertEqual("[Line 1] オートメーション サーバーはオブジェクトを作成できません", errors.first?.1)
    }

    // MARK: - 名前を指定してマクロ実行・登録マクロ・自動実行

    func testExecExternalMacroKinds() throws {
        let js = tempDir.appendingPathComponent("m.js")
        try "\u{FEFF}InsText('js');".write(to: js, atomically: true, encoding: .utf8)
        let mac = tempDir.appendingPathComponent("m.mac")
        try "InsText('mac');".write(to: mac, atomically: true, encoding: .utf8)
        let vbs = tempDir.appendingPathComponent("m.vbs")
        try "InsText \"x\"".write(to: vbs, atomically: true, encoding: .utf8)
        EditorTextView.chooseMacroFile = { _, _ in js }
        defer { EditorTextView.chooseMacroFile = { _, _ in nil } }
        view.execExternalMacro(nil)
        view.execExternalMacro(path: mac.path, type: nil)
        XCTAssertEqual("jsmac", text)
        view.execExternalMacro(path: vbs.path, type: nil)
        XCTAssertEqual(1, errors.count)
        XCTAssertTrue(errors.first?.1.hasPrefix("このマクロ（.vbs）は Mac 版では実行できません。") == true, "\(errors)")
        errors = []
        view.execExternalMacro(path: tempDir.appendingPathComponent("none.js").path, type: nil)
        XCTAssertEqual(["マクロの読み込みに失敗しました。\n\n" + tempDir.appendingPathComponent("none.js").path], errors.map(\.1))
        errors = []
        // マクロの中から（コードと言語）
        XCTAssertTrue(runJS("ExecExternalMacro(\"InsText('+');\", 'js'); ExecExternalMacro('InsText(\\'*\\');', 'mac');"))
        XCTAssertEqual("jsmac+*", text)
        XCTAssertTrue(errors.isEmpty, "\(errors)")
    }

    func testUserMacroAndReload() throws {
        let file = tempDir.appendingPathComponent("u.js")
        try "InsText('1');".write(to: file, atomically: true, encoding: .utf8)
        setSettings("Macro", ["Name[007]": "ユーザー", "File[007]": file.path, "ReloadWhenExecute[007]": "0"])
        XCTAssertEqual(MacroEntry(name: "ユーザー", file: file.path, reloadWhenExecute: false), MacroCommands.entry(7))
        XCTAssertTrue(CommandTable.perform(31607, from: view))
        // 読んだものを覚えている（ファイルを変えても前のまま）
        try "InsText('2');".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertTrue(CommandTable.perform(31607, from: view))
        XCTAssertEqual("11", text)
        // 実行するたびに読み込みなおす
        setSetting("Macro", "ReloadWhenExecute[007]", "1")
        XCTAssertTrue(CommandTable.perform(31607, from: view))
        XCTAssertEqual("112", text)
        // メニュー（名前がなければファイル名）
        let menu = NSMenu()
        UserMacroMenu.shared.menuNeedsUpdate(menu)
        XCTAssertTrue(menu.items.contains { $0.title == "ユーザー" && $0.tag == 31607 })
        // 登録マクロのファイルがない
        setSettings("Macro", ["Name[008]": "", "File[008]": tempDir.appendingPathComponent("none.js").path])
        XCTAssertTrue(CommandTable.perform(31608, from: view))
        XCTAssertEqual(["マクロ 8 (\(tempDir.appendingPathComponent("none.js").path)) の実行に失敗しました。"], errors.map(\.1))
    }

    func testAutoMacroAndSaveFilename() throws {
        let file = tempDir.appendingPathComponent("auto.js")
        try "InsText(GetSaveFilename() + '|');".write(to: file, atomically: true, encoding: .utf8)
        setSettings("Macro", ["Name[009]": "", "File[009]": file.path, "ReloadWhenExecute[009]": "1", "nMacroOnSave": "9"])
        MacroCommands.runAuto("nMacroOnSave", view: view, savePath: "/tmp/saved.txt")
        XCTAssertEqual("/tmp/saved.txt|", text)
        MacroCommands.runAuto("nMacroOnOpened", view: view)	// 設定がなければ何もしない
        XCTAssertEqual("/tmp/saved.txt|", text)
    }

    // MARK: - キャンセル・記録

    func testCancelLongRunningMacro() {
        setSetting("Macro", "nMacroCancelTimer", "1")
        var shown = false
        JSMacroRunner.cancelPanelDidShow = { runner in
            shown = true
            runner.cancel()
        }
        XCTAssertFalse(runJS("var i = 0;\nwhile (true) { GetLineCount(0); i++; }"))
        XCTAssertTrue(shown)
        XCTAssertEqual("[Line 2] マクロの実行を中断しました。", errors.first?.1)
    }

    func testMacroCommandsAreNotRecorded() {
        view.recKeyMacro(nil)
        defer { if KeyMacroRecorder.shared.isRecording { KeyMacroRecorder.shared.stop() } }
        XCTAssertTrue(runJS("InsText('a'); Down();"))
        view.execExternalMacro(path: "InsText('b');", type: "js")
        XCTAssertEqual([MacroHost.Code.execExtMacro], KeyMacroRecorder.shared.calls.map(\.code))
        KeyMacroRecorder.shared.stop()
    }

    // MARK: - そのほかの命令・関数

    func testWrapTypeQuoteAndDialogs() {
        let savedQuote = EditorCore.commonSetting(section: "Common", key: "szInyouKigou") ?? "> "
        defer { EditorCore.setCommonSetting(savedQuote, section: "Common", key: "szInyouKigou") }
        XCTAssertTrue(runJS("var old = ChangeWrapColumn(40); InsText(String(ChangeWrapColumn(0)));"))
        XCTAssertEqual("40", text)
        XCTAssertEqual(.settingWidth, view.document.viewSettings.wrapMethod)
        XCTAssertTrue(runJS("TextWrapMethod(0);"))
        XCTAssertEqual(.none, view.document.viewSettings.wrapMethod)
        XCTAssertTrue(runJS("SetMsgQuoteStr('# ');"))
        XCTAssertEqual("# ", EditorCore.commonSetting(section: "Common", key: "szInyouKigou"))
        let typeBefore = view.document.typeIndex
        XCTAssertTrue(runJS("ChangeType(2);"))
        XCTAssertEqual(1, view.document.typeIndex)
        _ = view.document.changeTypeTemporarily(typeBefore)
        // ファイル・フォルダーのダイアログ（差し替え）
        let savedFile = MacroHost.fileDialog
        let savedFolder = CommonSettingsPages.chooseFolder
        defer {
            MacroHost.fileDialog = savedFile
            CommonSettingsPages.chooseFolder = savedFolder
        }
        MacroHost.fileDialog = { save, initial in save ? "/s/" + initial : nil }
        CommonSettingsPages.chooseFolder = { message, initial in message + initial }
        XCTAssertTrue(runJS("InsText('|' + FileSaveDialog('a.txt', '*.txt') + '|' + FileOpenDialog() + '|' + FolderDialog('m', '/d'));"))
        XCTAssertTrue(text.hasSuffix("|/s/a.txt||m/d"), text)
    }
}

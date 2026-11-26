// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge
import XCTest

/// Grep・Grep置換・タグジャンプ（计划第 43 步）的对话框、结果的窗口、命令的测试。
///
/// 检索本身（结果的格式、与 Windows 版相同）在核心库里测试（macos/core/tests/test-mac-grep.cpp）。
/// 这里确认：对话框（原版 CDlgGrep・CDlgGrepReplace：初始值、控件的联动、OK 的检查和条件、历史、共通設定）、
/// 结果的窗口（原版 Command_GREP：哪个窗口、Grep モード、标题、没有修改、光标、検索文字列の色）、
/// 「Grep実行中」、タグジャンプ（Enter・双击・タグジャンプバック・閉じてタグジャンプ）、文件夹的授权。
final class GrepTests: XCTestCase {
    private var documents: [SakuraDocument] = []
    private var directory: URL!
    private var messages: [String] = []
    private var saved: [String: String] = [:]
    private var opened: [URL] = []

    private static let commonKeys = ["bGrepSubFolder", "nGrepCharSet", "bGrepOutputLine", "nGrepOutputStyle", "bGrepOutputFileOnly",
                                     "bGrepOutputBaseFolder", "bGrepSeparateFolder", "bGrepExceptFileRegexp", "bGrepDefaultFolder",
                                     "bGrepBackup", "bGrepRealTime", "bGTJW_RETURN", "bGTJW_LDBLCLK", "bGrepExitConfirm",
                                     "bSearchRegularExp", "bSearchLoHiCase", "bSearchWordOnly", "bCaretTextForSearch"]

    override func setUpWithError() throws {
        _ = TestCore.home
        _ = NSApplication.shared
        for key in Self.commonKeys {
            saved[key] = EditorCore.commonSetting(section: "Common", key: key) ?? ""
        }
        _ = EditorCore.setCommonSettings(["bGrepRealTime": "0", "bGrepDefaultFolder": "0", "nGrepCharSet": "99"], section: "Common")
        messages = []
        GrepDialogController.showMessage = { [unowned self] text, _ in messages.append(text) }
        EditorTextView.messageHandler = { [unowned self] in messages.append($0 ?? "") }
        GrepRunner.showsRunningPanel = false
        EditorTextView.makeGrepDocument = { [unowned self] in makeDocument() }
        EditorTextView.openDocuments = { [unowned self] in documents }
        opened = []
        EditorTextView.openForTagJump = { [unowned self] url, completion in
            opened.append(url)
            let document = try? SakuraDocument(contentsOf: url, ofType: "public.plain-text")
            document?.makeWindowControllers()
            if let document { documents.append(document) }
            completion(document, nil)
        }
        // 検索するフォルダー：核心库のテストと同じ見本（data/grep/tree）
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("grep-tests-\(UUID().uuidString)")
        let tree = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "tree", withExtension: nil))
        try FileManager.default.copyItem(at: tree, to: directory)
    }

    override func tearDown() {
        for document in documents { document.close() }
        documents = []
        _ = EditorCore.setCommonSettings(saved, section: "Common")
        GrepDialogController.runModal = nil
        GrepRunner.showsRunningPanel = true
        EditorTextView.messageHandler = nil
        TagJumpStack.entries = []
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeDocument() -> SakuraDocument {
        let document = SakuraDocument()
        document.makeWindowControllers()
        documents.append(document)
        return document
    }

    private func view(_ document: SakuraDocument) throws -> EditorTextView {
        try XCTUnwrap(document.editorWindowController?.textView)
    }

    private func path(_ name: String) -> String { directory.appendingPathComponent(name).path }

    /// 対話框（表示しない）
    private func dialog(_ view: EditorTextView, replace: Bool = false) throws -> GrepDialogController {
        try XCTUnwrap(GrepDialogController(replace: replace, state: replace ? view.grepReplaceDialogState : view.grepDialogState,
                                           currentFilePath: view.sakuraDocument?.fileURL?.path ?? "",
                                           sourceToken: GrepCore.sourceToken(view.grepSourceID)))
    }

    /// Grep が終わるまで待つ
    private func waitGrep(_ view: EditorTextView, timeout: TimeInterval = 10) {
        let deadline = Date().addingTimeInterval(timeout)
        while !GrepRunner.running.isEmpty && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        XCTAssertTrue(GrepRunner.running.isEmpty, "Grep が終わらない")
    }

    /// 対話框で条件を入れて OK（原版の操作の順）
    private func runGrep(_ view: EditorTextView, key: String, file: String = "*.txt", folder: String? = nil,
                         setUp: ((GrepDialogController) -> Void)? = nil) throws {
        GrepDialogController.runModal = { [unowned self] dialog in
            dialog.page.setText("IDC_COMBO_TEXT", key)
            dialog.page.setText("IDC_COMBO_FILE", file)
            dialog.page.setText("IDC_COMBO_FOLDER", folder ?? directory.path)
            dialog.page.setText("IDC_COMBO_EXCLUDE_FILE", "")
            dialog.page.setText("IDC_COMBO_EXCLUDE_FOLDER", "")
            setUp?(dialog)
            dialog.press("IDOK")
            return dialog.isAccepted
        }
        view.showGrepDialog(nil)
        waitGrep(view)
    }

    // MARK: - 対話框

    /// 原版の枠のまま Mac の文字を置いて切れない・重ならない（PropLayoutTests と同じ確かめ）
    func testDialogsHaveNoTruncatedText() throws {
        let view = try view(makeDocument())
        var problems: [String] = []
        for replace in [false, true] {
            problems += PropLayoutTests.truncated(try dialog(view, replace: replace).page).map { "\(replace ? "IDD_GREP_REPLACE" : "IDD_GREP"): \($0)" }
        }
        let runner = GrepRunner(view: view, options: GrepOptions(), sources: [])
        let window = try XCTUnwrap(view.window)
        let panel = try XCTUnwrap(GrepRunningPanel(runner: runner, parent: window))
        panel.update(hitCount: 12345, file: "a.txt", folder: directory.path)
        problems += PropLayoutTests.truncated(panel.page).map { "IDD_GREPRUNNING: \($0)" }
        XCTAssertEqual(problems, [], problems.joined(separator: "\n"))
    }

    /// 開いたとき（原版 DoModal・OnInitDialog・SetData）：除外の初期値、共通設定の値、文字コード、正規表現のバージョン
    func testDialogInitialValues() throws {
        _ = EditorCore.setCommonSettings(["bGrepSubFolder": "1", "nGrepCharSet": "4", "bGrepOutputLine": "1", "nGrepOutputStyle": "3",
                                          "bGrepOutputFileOnly": "1", "bGrepExceptFileRegexp": "1"], section: "Common")
        let view = try view(makeDocument())
        let d = try dialog(view)
        XCTAssertEqual(d.window.title, "Grep")
        XCTAssertEqual(d.page.text("IDC_COMBO_EXCLUDE_FILE"), GrepCore.history(.excludeFile).first)	// 履歴の最初（無ければ初期値）
        XCTAssertTrue(d.page.isChecked("IDC_CHK_SUBFOLDER"))
        XCTAssertEqual(d.page.selectedTag("IDC_COMBO_CHARSET"), ECEncodingUTF8)
        XCTAssertTrue(d.page.isChecked("IDC_RADIO_OUTPUTLINE"))
        XCTAssertTrue(d.page.isChecked("IDC_RADIO_OUTPUTSTYLE3"))
        XCTAssertFalse(d.page.isEnabled("IDC_CHECK_BASE_PATH"))	// 結果のみ：ベースフォルダー・フォルダー毎は使えない
        XCTAssertFalse(d.page.isEnabled("IDC_CHECK_SEP_FOLDER"))
        XCTAssertTrue(d.page.isChecked("IDC_CHECK_FILE_ONLY"))
        XCTAssertTrue(d.page.isChecked("IDC_CHK_EXCLUDE_FILE_REGEXP"))
        XCTAssertEqual(d.page.text("IDC_STATIC_JRE32VER"), EditorCore.regexpVersion)
        XCTAssertTrue(d.page.isUnavailable("IDC_BUTTON_HELP"))
        // 一覧にない文字コード（コードページ）は CP にチェックして加える
        _ = EditorCore.setCommonSettings(["nGrepCharSet": "1252"], section: "Common")
        let cp = try dialog(view)
        XCTAssertTrue(cp.page.isChecked("IDC_CHECK_CP"))
        XCTAssertFalse(cp.page.isEnabled("IDC_CHECK_CP"))
        XCTAssertEqual(cp.page.selectedTag("IDC_COMBO_CHARSET"), 1252)
    }

    /// カレントフォルダーが初期値・現フォルダー・上階層へ・正規表現と単語単位・CP
    func testDialogControls() throws {
        let file = path("a.txt")
        let document = try SakuraDocument(contentsOf: URL(fileURLWithPath: file), ofType: "public.plain-text")
        document.makeWindowControllers()
        documents.append(document)
        let view = try view(document)
        _ = EditorCore.setCommonSettings(["bGrepDefaultFolder": "1"], section: "Common")
        let d = try dialog(view)
        XCTAssertEqual(d.page.text("IDC_COMBO_FOLDER"), directory.path)	// 編集中のファイルのフォルダー
        XCTAssertTrue(d.page.isChecked("IDC_CHK_DEFAULTFOLDER"))
        d.page.setText("IDC_COMBO_FOLDER", "/tmp")
        d.press("IDC_BUTTON_CURRENTFOLDER")
        XCTAssertEqual(d.page.text("IDC_COMBO_FOLDER"), directory.path)
        d.press("IDC_BUTTON_FOLDER_UP")
        XCTAssertEqual(d.page.text("IDC_COMBO_FOLDER"), directory.deletingLastPathComponent().path)

        (d.page.control("IDC_CHK_REGULAREXP") as? NSButton)?.performClick(nil)
        XCTAssertFalse(d.page.isEnabled("IDC_CHK_WORD"))
        (d.page.control("IDC_CHK_REGULAREXP") as? NSButton)?.performClick(nil)
        XCTAssertTrue(d.page.isEnabled("IDC_CHK_WORD"))

        let before = d.page.itemTitles("IDC_COMBO_CHARSET").count
        (d.page.control("IDC_CHECK_CP") as? NSButton)?.performClick(nil)
        XCTAssertGreaterThan(d.page.itemTitles("IDC_COMBO_CHARSET").count, before)
        XCTAssertFalse(d.page.isEnabled("IDC_CHECK_CP"))

        (d.page.control("IDC_RADIO_OUTPUTSTYLE3") as? NSButton)?.performClick(nil)
        XCTAssertFalse(d.page.isEnabled("IDC_CHECK_BASE_PATH"))
        (d.page.control("IDC_RADIO_OUTPUTSTYLE1") as? NSButton)?.performClick(nil)
        XCTAssertTrue(d.page.isEnabled("IDC_CHECK_BASE_PATH"))

        // 「...」：選んだフォルダー（; を含むなら引用符で囲む）
        let chosen = directory.appendingPathComponent("a;b")
        try FileManager.default.createDirectory(at: chosen, withIntermediateDirectories: true)
        let savedPanel = GrepDialogController.chooseFolderPanel
        GrepDialogController.chooseFolderPanel = { _, _ in chosen }
        defer { GrepDialogController.chooseFolderPanel = savedPanel }
        d.press("IDC_BUTTON_FOLDER")
        XCTAssertEqual(d.page.text("IDC_COMBO_FOLDER"), "\"\(chosen.path)\"")
    }

    /// OK：条件（除外を詰めた対象ファイル、絶対パスのフォルダー）、共通設定、履歴（原版 GetData・MakeGrepInfo）
    func testOKMakesOptions() throws {
        let view = try view(makeDocument())
        let d = try dialog(view)
        d.page.setText("IDC_COMBO_TEXT", "HIT")
        d.page.setText("IDC_COMBO_FILE", "*.txt")
        d.page.setText("IDC_COMBO_FOLDER", directory.path + "/Sub/..")
        d.page.setText("IDC_COMBO_EXCLUDE_FILE", "*.bak")
        d.page.setText("IDC_COMBO_EXCLUDE_FOLDER", "obj")
        d.page.setChecked("IDC_CHK_SUBFOLDER", true)
        d.page.setChecked("IDC_CHK_LOHICASE", true)
        d.page.setChecked("IDC_RADIO_OUTPUTSTYLE2", true)
        d.page.setChecked("IDC_RADIO_OUTPUTSTYLE1", false)
        d.page.setChecked("IDC_CHECK_BASE_PATH", true)
        d.press("IDOK")
        XCTAssertTrue(d.isAccepted)
        XCTAssertEqual(messages, [])
        let o = try XCTUnwrap(d.options)
        XCTAssertEqual(o.key, "HIT")
        XCTAssertEqual(o.files, "*.txt;#obj;!*.bak")
        XCTAssertEqual(o.folders, directory.path)
        XCTAssertTrue(o.subFolder)
        XCTAssertTrue(o.matchCase)
        XCTAssertEqual(o.outputStyle, 2)
        XCTAssertTrue(o.baseFolder)
        XCTAssertEqual(o.charSet, 99)
        XCTAssertFalse(o.replace)
        XCTAssertEqual(GrepDialogController.commonInt("nGrepOutputStyle"), 2)
        XCTAssertTrue(GrepDialogController.commonBool("bGrepSubFolder"))
        XCTAssertEqual(GrepCore.history(.folder).first, directory.path)
        XCTAssertEqual(GrepCore.history(.file).first, "*.txt")
        XCTAssertEqual(GrepCore.history(.excludeFolder).first, "obj")
        XCTAssertEqual(EditorCore.searchKeyHistory.first, "HIT")
        // 次に開いたときは記憶した値
        let again = try dialog(view)
        XCTAssertEqual(again.page.text("IDC_COMBO_TEXT"), "HIT")
        XCTAssertEqual(again.page.text("IDC_COMBO_FOLDER"), directory.path)
    }

    /// OK の確かめ：メッセージは原版と同じで、対話框は閉じない
    func testOKErrors() throws {
        let view = try view(makeDocument())
        let cases: [(String, String, String)] = [
            ("*.txt", "", "検索対象フォルダーを指定してください。"),
            ("*.txt", directory.appendingPathComponent("none").path, "検索対象フォルダーが正しくありません。"),
            ("\"a", directory.path, "対象ファイル・除外ファイル・除外フォルダーの指定は、引用符で正しく囲んでください。"),
            ("*/a.txt", directory.path, "ファイル指定のフォルダー部分にはワイルドカードは使えません。"),
            ("/x/*.txt", directory.path, "ファイル指定にはフルパスは使えません"),
            (":HWND:1", directory.path, "対象ファイルに:HWND:は入力できません"),
        ]
        for (file, folder, message) in cases {
            messages = []
            let d = try dialog(view)
            d.page.setText("IDC_COMBO_FILE", file)
            d.page.setText("IDC_COMBO_FOLDER", folder)
            d.press("IDOK")
            XCTAssertFalse(d.isAccepted, file)
            XCTAssertEqual(messages, [message], file)
        }
        // 正規表現の誤り
        messages = []
        let d = try dialog(view)
        d.page.setText("IDC_COMBO_TEXT", "(")
        d.page.setText("IDC_COMBO_FOLDER", directory.path)
        d.page.setChecked("IDC_CHK_REGULAREXP", true)
        d.press("IDOK")
        XCTAssertFalse(d.isAccepted)
        XCTAssertEqual(messages.count, 1)
    }

    /// 編集中のテキストから検索：対象・フォルダーは「(現在のドキュメント)」で触れない。OK の条件は :HWND: の番号
    func testFromThisText() throws {
        let view = try view(makeDocument())
        let d = try dialog(view)
        d.page.setText("IDC_COMBO_FILE", "*.c")
        (d.page.control("IDC_CHK_FROMTHISTEXT") as? NSButton)?.performClick(nil)
        XCTAssertEqual(d.page.text("IDC_COMBO_FILE"), "(現在のドキュメント)")
        XCTAssertEqual(d.page.text("IDC_COMBO_FOLDER"), "(現在のドキュメント)")
        for id in ["IDC_COMBO_FILE", "IDC_COMBO_FOLDER", "IDC_BUTTON_FOLDER", "IDC_CHK_SUBFOLDER", "IDC_COMBO_EXCLUDE_FILE",
                   "IDC_COMBO_EXCLUDE_FOLDER", "IDC_BUTTON_FOLDER_UP", "IDC_BUTTON_CURRENTFOLDER"] {
            XCTAssertFalse(d.page.isEnabled(id), id)
        }
        d.press("IDOK")
        let o = try XCTUnwrap(d.options)
        XCTAssertEqual(o.files, GrepCore.sourceToken(view.grepSourceID))
        XCTAssertEqual(o.folders, "")
        // 外すと元の値に戻る
        let d2 = try dialog(view)
        (d2.page.control("IDC_CHK_FROMTHISTEXT") as? NSButton)?.performClick(nil)
        XCTAssertEqual(d2.page.text("IDC_COMBO_FILE"), "*.c")
        // Grep置換 では使えない
        XCTAssertFalse(try dialog(view, replace: true).page.isEnabled("IDC_CHK_FROMTHISTEXT"))
    }

    // MARK: - 結果の窓口

    /// 空の無題の窓口なら、その窓口に結果を出す。Grep の窓口になり、タイトルは条件、変更なし、カーソルは結果の前、検索文字列の色
    func testGrepIntoEmptyWindow() throws {
        let document = makeDocument()
        let view = try view(document)
        try runGrep(view, key: "HIT")
        XCTAssertEqual(documents.count, 1)
        XCTAssertTrue(document.isGrepMode)
        XCTAssertEqual(document.displayName, "HIT")
        XCTAssertFalse(view.document.isModified)
        XCTAssertEqual(view.document.typeIndex, GrepCore.outputTypeIndex)
        let text = view.document.text
        XCTAssertTrue(text.contains("□検索条件  \"HIT\""), text)
        XCTAssertTrue(text.contains("\(directory.path)/a.txt(1,1)"), text)
        XCTAssertTrue(text.contains("個が検索されました。"), text)
        XCTAssertEqual(view.caret.line, 0)
        XCTAssertEqual(view.searchState.key, "HIT")
        XCTAssertTrue(view.searchState.markOn)
        // 保存の確認：「Grepモードで保存確認する」に従う（原版 OnFileClose）
        _ = EditorCore.setCommonSettings(["bGrepExitConfirm": "0"], section: "Common")
        XCTAssertFalse(document.isDocumentEdited)
        _ = EditorCore.setCommonSettings(["bGrepExitConfirm": "1"], section: "Common")
        XCTAssertTrue(document.isDocumentEdited)
    }

    /// 変更した窓口・ファイルの窓口なら新しい窓口に出す。Grep の窓口なら（実行中でなければ）その窓口に足す
    func testGrepIntoNewWindowAndGrepWindow() throws {
        let document = makeDocument()
        let view = try view(document)
        view.insertText("x", replacementRange: NSRange(location: NSNotFound, length: 0))
        try runGrep(view, key: "HIT")
        XCTAssertEqual(documents.count, 2)
        let grepView = try self.view(documents[1])
        XCTAssertEqual(view.document.text, "x")
        XCTAssertTrue(documents[1].isGrepMode)
        let first = grepView.document.text
        try runGrep(grepView, key: "テスト")
        XCTAssertEqual(documents.count, 2)
        XCTAssertTrue(grepView.document.text.hasPrefix(first))
        XCTAssertTrue(grepView.document.text.contains("□検索条件  \"テスト\""))
        XCTAssertEqual(documents[1].displayName, "テスト")
        XCTAssertEqual(grepView.caret.line, first.components(separatedBy: "\r\n").count - 1)	// 足す前の最後の行
    }

    /// 編集中のテキストから検索
    func testGrepThisText() throws {
        let document = makeDocument()
        let view = try view(document)
        view.document.insert("alpha HIT\r\nbeta\r\nHIT\r\n", at: EditorPosition(line: 0, column: 0))
        try runGrep(view, key: "HIT") { $0.page.setChecked("IDC_CHK_FROMTHISTEXT", true) }
        XCTAssertEqual(documents.count, 2, "\(messages)")
        let text = try self.view(documents[1]).document.text
        XCTAssertTrue(text.contains("](無題)(1,7)"), text)	// :HWND:[番号](無題)(1,7)
        XCTAssertTrue(text.contains("](無題)(3,1)"), text)
        XCTAssertTrue(text.contains("Window:[(無題)]"), text)
    }

    /// 実行中は閉じられない（原版 OnBeforeClose）。保存すると Grep の窓口でなくなる（原版 OnAfterSave）
    func testCloseWhileRunningAndSave() throws {
        let document = makeDocument()
        let view = try view(document)
        document.grepRunner = GrepRunner(view: view, options: GrepOptions(), sources: [])
        final class Delegate: NSObject {
            var answer: Bool?
            @objc func document(_ document: NSDocument?, shouldClose: Bool, contextInfo: UnsafeMutableRawPointer?) { answer = shouldClose }
        }
        let delegate = Delegate()
        document.canClose(withDelegate: delegate, shouldClose: #selector(Delegate.document(_:shouldClose:contextInfo:)), contextInfo: nil)
        XCTAssertEqual(delegate.answer, false)
        XCTAssertEqual(messages, ["Grepの処理中です。"])
        document.grepRunner = nil

        try runGrep(view, key: "HIT")
        XCTAssertTrue(document.isGrepMode)
        let url = directory.appendingPathComponent("result.grep")
        let done = expectation(description: "save")
        document.save(to: url, ofType: "public.plain-text", for: .saveAsOperation) { _ in done.fulfill() }
        wait(for: [done], timeout: 10)
        XCTAssertFalse(document.isGrepMode)
    }

    /// 「Grep実行中」：件数・ファイル・フォルダー、リアルタイム表示、キャンセルで中断
    func testRunningPanel() throws {
        let view = try view(makeDocument())
        let options = GrepOptions()
        options.key = "HIT"
        options.files = "*.txt"
        options.folders = directory.path
        options.subFolder = true
        let runner = GrepRunner(view: view, options: options, sources: [])
        let window = try XCTUnwrap(view.window)
        let panel = try XCTUnwrap(GrepRunningPanel(runner: runner, parent: window))
        XCTAssertEqual(panel.window.title, "Grep実行中")
        XCTAssertEqual(panel.page.text("IDC_STATIC_HITCOUNT"), "0")
        panel.update(hitCount: 3, file: "a.txt", folder: directory.path)
        XCTAssertEqual(panel.page.text("IDC_STATIC_HITCOUNT"), "3")
        XCTAssertEqual(panel.page.text("IDC_STATIC_CURFILE"), "a.txt")
        XCTAssertEqual(panel.page.text("IDC_STATIC_CURPATH"), directory.path)
        (panel.page.control("IDC_CHECK_REALTIMEVIEW") as? NSButton)?.performClick(nil)
        XCTAssertTrue(runner.session.realTimeView)
        // キャンセル：中断しました
        (panel.page.control("IDCANCEL") as? NSButton)?.performClick(nil)
        var result: GrepResult?
        runner.onFinish = { result = $0 }
        runner.start()
        waitGrep(view)
        XCTAssertEqual(result?.cancelled, true)
        XCTAssertTrue(view.document.text.contains("中断しました。"), view.document.text)
    }

    // MARK: - タグジャンプ

    /// 結果の行で Enter（エンターキーでタグジャンプ）：ファイルを開いて、その行・桁に移る。タグジャンプバックで戻る
    func testTagJumpByEnterAndBack() throws {
        _ = EditorCore.setCommonSettings(["bGTJW_RETURN": "1"], section: "Common")
        let document = makeDocument()
        let view = try view(document)
        try runGrep(view, key: "HIT")
        let lines = view.document.text.components(separatedBy: "\r\n")
        let line = try XCTUnwrap(lines.firstIndex { $0.hasPrefix("\(directory.path)/a.txt(3,5)") })
        view.setCaret(EditorPosition(line: line, column: 0))
        view.insertNewline(nil)
        XCTAssertEqual(opened.map(\.path), [path("a.txt")])
        let target = try self.view(try XCTUnwrap(documents.last))
        XCTAssertEqual(target.caret.line, 2)
        XCTAssertEqual(target.caret.column, 4)
        XCTAssertEqual(view.document.text.components(separatedBy: "\r\n").count, lines.count)	// 改行は入らない
        // タグジャンプバック
        view.setCaret(EditorPosition(line: 0, column: 0))
        target.tagJumpBack(nil)
        XCTAssertEqual(view.caret.line, line)
        // 「エンターキーでタグジャンプ」がオフなら改行
        _ = EditorCore.setCommonSettings(["bGTJW_RETURN": "0"], section: "Common")
        view.setCaret(EditorPosition(line: line, column: 0))
        let before = view.document.lineCount
        view.insertNewline(nil)
        XCTAssertEqual(view.document.lineCount, before + 1)
    }

    /// 結果の行をダブルクリック（ダブルクリックでタグジャンプ）
    func testTagJumpByDoubleClick() throws {
        _ = EditorCore.setCommonSettings(["bGTJW_LDBLCLK": "1"], section: "Common")
        let document = makeDocument()
        let view = try view(document)
        try runGrep(view, key: "HIT", file: "1.txt")
        let lines = view.document.text.components(separatedBy: "\r\n")
        let line = try XCTUnwrap(lines.firstIndex { $0.hasPrefix("\(directory.path)/1.txt(1,5)") })
        view.setCaret(EditorPosition(line: line, column: 0))
        let window = try XCTUnwrap(view.window)
        let point = view.convert(NSPoint(x: view.caretRect.midX + 20, y: view.caretRect.midY), to: nil)
        for count in 1...2 {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0,
                                                         windowNumber: window.windowNumber, context: nil, eventNumber: count,
                                                         clickCount: count, pressure: 1))
            view.mouseDown(with: event)
        }
        XCTAssertEqual(opened.map(\.path), [path("1.txt")])
        let target = try self.view(try XCTUnwrap(documents.last))
        XCTAssertEqual(target.caret.column, 4)
    }

    /// ファイル毎・ベースフォルダー・フォルダー毎の結果からも飛ぶ。閉じてタグジャンプは元の窓口を閉じる
    func testTagJumpOtherStylesAndClose() throws {
        let document = makeDocument()
        let view = try view(document)
        try runGrep(view, key: "HIT", file: "e.txt") {
            $0.page.setChecked("IDC_CHK_SUBFOLDER", true)
            $0.page.setChecked("IDC_RADIO_OUTPUTSTYLE1", false)
            $0.page.setChecked("IDC_RADIO_OUTPUTSTYLE2", true)
            $0.page.setChecked("IDC_CHECK_BASE_PATH", true)
            $0.page.setChecked("IDC_CHECK_SEP_FOLDER", true)
        }
        let lines = view.document.text.components(separatedBy: "\r\n")
        let line = try XCTUnwrap(lines.firstIndex { $0.hasPrefix("・(") })
        view.setCaret(EditorPosition(line: line, column: 0))
        XCTAssertTrue(view.tagJump(close: false))
        XCTAssertEqual(opened.map(\.path), [path("Sub/deep/e.txt")])
        XCTAssertEqual(try self.view(try XCTUnwrap(documents.last)).caret.column, 2)
        // 見出し・件数の行では飛べない
        view.setCaret(EditorPosition(line: 1, column: 0))
        XCTAssertFalse(view.tagJump(close: false))
    }

    /// 編集中のテキストから検索の結果：その窓口に戻る
    func testTagJumpToSourceWindow() throws {
        let source = makeDocument()
        let sourceView = try view(source)
        sourceView.document.insert("x\r\ny HIT\r\n", at: EditorPosition(line: 0, column: 0))
        try runGrep(sourceView, key: "HIT") { $0.page.setChecked("IDC_CHK_FROMTHISTEXT", true) }
        let grepView = try view(documents[1])
        let lines = grepView.document.text.components(separatedBy: "\r\n")
        let line = try XCTUnwrap(lines.firstIndex { $0.hasPrefix(":HWND:[") })
        grepView.setCaret(EditorPosition(line: line, column: 0))
        XCTAssertTrue(grepView.tagJump(close: false))
        XCTAssertEqual(opened, [])
        XCTAssertEqual(sourceView.caret.line, 1)
        XCTAssertEqual(sourceView.caret.column, 2)
    }

    // MARK: - Grep置換

    /// Grep置換：置換後・バックアップ・クリップボードの内容で置換（貼り付けられないときはチェックを外す）
    func testGrepReplace() throws {
        let view = try view(makeDocument())
        let d = try dialog(view, replace: true)
        XCTAssertEqual(d.window.title, "Grep置換")
        d.canPaste = { false }
        (d.page.control("IDC_CHK_PASTE") as? NSButton)?.performClick(nil)
        XCTAssertFalse(d.page.isChecked("IDC_CHK_PASTE"))
        XCTAssertEqual(messages, ["クリップボードに有効なデータがありません！"])
        // 置換前が空
        messages = []
        d.page.setText("IDC_COMBO_TEXT", "")
        d.press("IDOK")
        XCTAssertEqual(messages, ["置換条件を指定してください。"])

        GrepDialogController.runModal = { [unowned self] dialog in
            dialog.page.setText("IDC_COMBO_TEXT", "HIT")
            dialog.page.setText("IDC_COMBO_TEXT2", "REP")
            dialog.page.setText("IDC_COMBO_FILE", "1.txt")
            dialog.page.setText("IDC_COMBO_FOLDER", directory.path)
            dialog.page.setText("IDC_COMBO_EXCLUDE_FILE", "")
            dialog.page.setText("IDC_COMBO_EXCLUDE_FOLDER", "")
            dialog.page.setChecked("IDC_CHK_BACKUP", true)
            dialog.press("IDOK")
            return dialog.isAccepted
        }
        view.showGrepReplaceDialog(nil)
        waitGrep(view)
        XCTAssertEqual(try String(contentsOfFile: path("1.txt"), encoding: .utf8), "one REP\r\n")
        XCTAssertEqual(try String(contentsOfFile: path("1.txt.skrold"), encoding: .utf8), "one HIT\r\n")
        XCTAssertTrue(view.document.text.contains("個を置換しました。"))
        XCTAssertEqual(EditorCore.replaceKeyHistory.first, "REP")
        XCTAssertTrue(GrepDialogController.commonBool("bGrepBackup"))
    }

    /// クリップボードの内容で置換の文字（ラインモードの改行・改行コードの変換。原版 DoGrep）
    func testPasteText() throws {
        let view = try view(makeDocument())
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("jp.sakura-editor.tests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        view.pasteboard = pasteboard
        pasteboard.clearContents()
        XCTAssertNil(view.grepPasteText())
        pasteboard.setString("a\nb", forType: .string)
        XCTAssertEqual(view.grepPasteText(), "a\nb")	// 改行コードを変換しない（既定）
        let edit = view.document.editSettings
        XCTAssertFalse(edit.convertEolOnPaste)
    }

    // MARK: - フォルダーの権限

    /// 選んだフォルダーの書签を記憶し、その下のフォルダー・ファイルの権限を取り戻す
    func testFolderAccess() throws {
        let store = BookmarkStore(fileURL: directory.appendingPathComponent("folder-bookmarks.plist"))
        let access = FolderAccess(store: store)
        access.remember(directory)
        XCTAssertTrue(store.hasBookmark(forPath: directory.path))
        XCTAssertTrue(access.startAccess(path: directory.appendingPathComponent("Sub/deep").path))
        XCTAssertTrue(access.startAccess(file: path("a.txt")))
        XCTAssertTrue(FolderAccess.contains("/a/b", "/a/b/c"))
        XCTAssertFalse(FolderAccess.contains("/a/b", "/a/bc"))
        XCTAssertTrue(FolderAccess.contains("/", "/x"))
        // 再起動後（新しいインスタンス）も書签から
        let reloaded = FolderAccess(store: BookmarkStore(fileURL: store.fileURL))
        XCTAssertTrue(reloaded.store.hasBookmark(forPath: directory.path))
        // 読めないフォルダーは許可を求める（キャンセルなら false）
        var asked: [String] = []
        let saved = FolderAccess.choose
        FolderAccess.choose = { path, _, _ in asked.append(path); return nil }
        defer { FolderAccess.choose = saved }
        // 無いフォルダーは求めない（OK の確かめでメッセージ）
        XCTAssertTrue(reloaded.ensureAccess(paths: ["/nonexistent-\(UUID().uuidString)"], parent: nil))
        XCTAssertEqual(asked.count, 0)
    }
}

// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge
import XCTest

/// tags ファイルのタグジャンプ（计划第 44 步）：ダイレクトタグジャンプ（候補 1 つ・複数・なし）、
/// キーワードを指定してタグジャンプ（一覧の対話框）、タグジャンプ（F_TAGJUMP）でファイル名がない行。
/// tags の探し方は核心库的测试（test-mac-edit-support.cpp の TagJump*）で確認
final class TagJumpListTests: XCTestCase {
    private var documents: [SakuraDocument] = []
    private var opened: [URL] = []
    private var messages: [String?] = []
    private var directory: URL!
    private var savedOther: [String: String] = [:]

    override func setUpWithError() throws {
        _ = TestCore.home
        _ = NSApplication.shared
        for key in ["m_bTagJumpICase", "m_bTagJumpAnyWhere"] {
            savedOther[key] = EditorCore.commonSetting(section: "Other", key: key) ?? "0"
        }
        messages = []
        EditorTextView.messageHandler = { [unowned self] in messages.append($0) }
        EditorTextView.openDocuments = { [unowned self] in documents }
        opened = []
        EditorTextView.openForTagJump = { [unowned self] url, completion in
            opened.append(url)
            let document = try? SakuraDocument(contentsOf: url, ofType: "public.plain-text")
            document?.makeWindowControllers()
            if let document { documents.append(document) }
            completion(document, nil)
        }
        directory = TestCore.home.appendingPathComponent("tagjump-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("src"), withIntermediateDirectories: true)
        let header = "!_TAG_FILE_FORMAT\t2\t/extended format/\n!_TAG_FILE_SORTED\t1\t/sorted/\n"
        try (header + "Area\tsrc/area.c\t3;\"\tf\nShape\tsrc/shape.h\t2;\"\ts\nShape\tsrc/shape.cpp\t5;\"\tc\n")
            .write(to: directory.appendingPathComponent("tags"), atomically: true, encoding: .utf8)
        for (name, lines) in [("src/area.c", 5), ("src/shape.h", 5), ("src/shape.cpp", 8), ("src/main.c", 3)] {
            try (1...lines).map { "line \($0)" }.joined(separator: "\n").write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
    }

    override func tearDown() {
        for document in documents { document.close() }
        documents = []
        EditorTextView.messageHandler = nil
        TagJumpListDialogController.runModal = nil
        TagJumpStack.entries = []
        _ = EditorCore.setCommonSettings(savedOther, section: "Other")
        try? FileManager.default.removeItem(at: directory)
    }

    /// src/main.c を開いて text を入れ、カーソルを置く
    private func openMain(_ text: String, caret: EditorPosition) throws -> EditorTextView {
        let url = directory.appendingPathComponent("src/main.c")
        try text.write(to: url, atomically: true, encoding: .utf8)
        let document = try SakuraDocument(contentsOf: url, ofType: "public.plain-text")
        document.makeWindowControllers()
        documents.append(document)
        let view = try XCTUnwrap(document.editorWindowController?.textView)
        view.setCaret(caret)
        return view
    }

    private func caretOf(_ url: URL) throws -> EditorPosition {
        let document = try XCTUnwrap(documents.last { $0.fileURL?.standardizedFileURL == url.standardizedFileURL })
        return try XCTUnwrap(document.editorWindowController?.textView).caret
    }

    /// 候補が 1 つ：そのファイルのその行へ。タグジャンプバックで戻る
    func testDirectTagJumpSingle() throws {
        let view = try openMain("call Area here", caret: EditorPosition(line: 0, column: 6))
        XCTAssertTrue(CommandTable.perform(30944, from: view))
        let area = directory.appendingPathComponent("src/area.c")
        XCTAssertEqual(opened.map { $0.standardizedFileURL.path }, [area.standardizedFileURL.path])
        XCTAssertEqual(try caretOf(area).line, 2)
        try XCTUnwrap(documents.last?.editorWindowController?.textView).tagJumpBack(nil)
        XCTAssertEqual([view.caret.line, view.caret.column], [0, 6])
    }

    /// 候補が複数：一覧（ダイレクトタグジャンプは前・次のボタンなし、キーワード欄なし）。同じ名前のファイルが選ばれている
    func testDirectTagJumpList() throws {
        let view = try openMain("Shape", caret: EditorPosition(line: 0, column: 0))
        var shown: [[String]] = []
        TagJumpListDialogController.runModal = { dialog in
            let list = dialog.page.list("IDC_LIST_TAGJUMP")
            shown = list?.rows ?? []
            XCTAssertTrue(dialog.page.control("IDC_KEYWORD")?.isHidden ?? false)
            XCTAssertTrue(dialog.page.control("IDC_BUTTON_NEXTTAG")?.isHidden ?? false)
            XCTAssertEqual(dialog.page.text("IDC_STATIC_BASEDIR"), self.directory.appendingPathComponent("src").path + "/")
            list?.select(1)
            dialog.press("IDOK")
            return dialog.isAccepted
        }
        view.directTagJump(nil)
        XCTAssertEqual(shown, [["Shape", "1", "2", "struct", "src/shape.h", ""], ["Shape", "1", "5", "class", "src/shape.cpp", ""]])
        XCTAssertEqual(opened.last?.lastPathComponent, "shape.cpp")
        XCTAssertEqual(try caretOf(directory.appendingPathComponent("src/shape.cpp")).line, 4)
        // キャンセル：どこにも行かない
        opened = []
        TagJumpListDialogController.runModal = { dialog in
            dialog.press("IDCANCEL")
            return dialog.isAccepted
        }
        view.directTagJump(nil)
        XCTAssertEqual(opened, [])
    }

    /// 見つからない：「タグジャンプできません」と蜂鸣
    func testDirectTagJumpNotFound() throws {
        let view = try openMain("nothing", caret: EditorPosition(line: 0, column: 0))
        view.directTagJump(nil)
        XCTAssertEqual(view.statusMessage.trimmingCharacters(in: .whitespaces), "タグジャンプできません")
        XCTAssertEqual(opened, [])
    }

    /// タグジャンプ（F_TAGJUMP）：ファイル名のない行では tags で探す
    func testTagJumpFallsBackToTags() throws {
        let view = try openMain("Area", caret: EditorPosition(line: 0, column: 1))
        view.tagJump(nil)
        XCTAssertEqual(opened.last?.lastPathComponent, "area.c")
    }

    /// キーワードを指定してタグジャンプ：前方一致・大文字小文字の同一視・途中にマッチ、履歴、設定の保存
    func testTagJumpKeywordDialog() throws {
        let view = try openMain("x", caret: EditorPosition(line: 0, column: 0))
        _ = EditorCore.setCommonSettings(["m_bTagJumpICase": "0", "m_bTagJumpAnyWhere": "0"], section: "Other")
        TagJumpListDialogController.runModal = { dialog in
            XCTAssertFalse(dialog.page.control("IDC_KEYWORD")?.isHidden ?? true)
            dialog.page.setText("IDC_KEYWORD", "Sh")
            dialog.findNow()
            XCTAssertEqual(dialog.page.list("IDC_LIST_TAGJUMP")?.rows.map { $0[0] }, ["Shape", "Shape"])
            dialog.page.setText("IDC_KEYWORD", "sha")
            dialog.findNow()
            XCTAssertEqual(dialog.page.list("IDC_LIST_TAGJUMP")?.rows.map { $0[4] }, ["(候補は見つかりませんでした)"], "大小を区別")
            dialog.page.setChecked("IDC_CHECK_ICASE", true)
            dialog.findNow()
            XCTAssertEqual(dialog.page.list("IDC_LIST_TAGJUMP")?.rows.count, 2)
            dialog.page.setText("IDC_KEYWORD", "rea")
            dialog.page.setChecked("IDC_CHECK_ANYWHERE", true)
            dialog.findNow()
            XCTAssertEqual(dialog.page.list("IDC_LIST_TAGJUMP")?.rows.map { $0[0] }, ["Area"])
            dialog.press("IDOK")
            return dialog.isAccepted
        }
        CommandTable.perform(30946, from: view)
        XCTAssertEqual(opened.last?.lastPathComponent, "area.c")
        XCTAssertEqual(EditorCore.tagJumpKeywordHistory.first, "rea")
        XCTAssertEqual(EditorCore.commonSetting(section: "Other", key: "m_bTagJumpICase"), "1")
        XCTAssertEqual(EditorCore.commonSetting(section: "Other", key: "m_bTagJumpAnyWhere"), "1")
        // 次に開くと前回の設定と履歴
        TagJumpListDialogController.runModal = { dialog in
            XCTAssertTrue(dialog.page.isChecked("IDC_CHECK_ICASE"))
            XCTAssertEqual(dialog.page.text("IDC_KEYWORD"), "rea")
            dialog.press("IDCANCEL")
            return false
        }
        view.tagJumpKeyword(nil)
    }

    /// メニュー：無題では使えない（原版 IsFuncEnable）。タグファイルの作成 は Mac 版にない
    func testMenuValidation() throws {
        let view = try openMain("x", caret: EditorPosition(line: 0, column: 0))
        let item = NSMenuItem(title: "", action: #selector(EditorTextView.directTagJump(_:)), keyEquivalent: "")
        XCTAssertTrue(view.validateMenuItem(item))
        let untitled = SakuraDocument()
        untitled.makeWindowControllers()
        documents.append(untitled)
        XCTAssertFalse(try XCTUnwrap(untitled.editorWindowController?.textView).validateMenuItem(item))
        XCTAssertNil(CommandTable.selector(for: 30943), "F_TAGS_MAKE")
        XCTAssertNil(CommandTable.selector(for: 30942), "F_TAGJUMP_LIST は原版にも処理がない")
    }
}

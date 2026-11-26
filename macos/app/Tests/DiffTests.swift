// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge
import XCTest

/// DIFF差分表示・ファイル内容比較（计划第 44 步，原版 CDlgDiff、CDlgCompare、CViewCommander_Diff.cpp）。
/// 差分の計算は核心库的测试（test-mac-edit-support.cpp：GNU diff・Windows 官方版と同じ結果）で確認
final class DiffTests: XCTestCase {
    private var windows: [NSWindow] = []
    private var views: [EditorTextView] = []
    private var messages: [String?] = []
    private var savedSearch: EditorSearchSettings!
    private var savedTile = ""
    private var savedFlags = 0
    private var directory: URL!
    private var savedAll: (() -> [EditorTextView])!
    private var savedChooseFile: ((String, NSWindow?) -> String?)!

    override func setUpWithError() throws {
        _ = TestCore.home
        _ = NSApplication.shared
        savedSearch = EditorCore.searchSettings
        savedTile = EditorCore.commonSetting(section: "Common", key: "bCompareAndTileHorz") ?? "1"
        messages = []
        EditorTextView.messageHandler = { [weak self] in self?.messages.append($0) }
        savedAll = EditingDocument.all
        savedChooseFile = DiffDialogController.chooseFile
        EditingDocument.all = { [unowned self] in views }
        savedFlags = DiffDialogController.lastFlags
        DiffDialogController.lastFlags = 0
        directory = TestCore.home.appendingPathComponent("diff-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        EditorTextView.messageHandler = nil
        EditingDocument.all = savedAll
        DiffDialogController.chooseFile = savedChooseFile
        DiffDialogController.runModal = nil
        CompareDialogController.runModal = nil
        EditorCore.searchSettings = savedSearch
        DiffDialogController.lastFlags = savedFlags
        _ = EditorCore.setCommonSetting(savedTile, section: "Common", key: "bCompareAndTileHorz")
        for w in windows { w.close() }
        windows = []
        views = []
        try? FileManager.default.removeItem(at: directory)
    }

    /// 窓口と編集画面を作る。name があればそのファイルを作って開く
    @discardableResult
    private func makeView(_ text: String, name: String? = nil) throws -> EditorTextView {
        let document = try XCTUnwrap(EditorDocument())
        if let name {
            let url = directory.appendingPathComponent(name)
            try text.write(to: url, atomically: true, encoding: .utf8)
            XCTAssertEqual(document.open(path: url.path), .success)
        } else {
            XCTAssertEqual(document.insert(text, at: EditorPosition(line: 0, column: 0)), .success)
        }
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 600, height: 400), styleMask: [.titled, .resizable],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let view = EditorTextView(document: document)
        scrollView.documentView = view
        window.contentView = scrollView
        window.makeFirstResponder(view)
        view.contentDidChange()
        view.setCaret(EditorPosition(line: 0, column: 0))
        windows.append(window)
        views.append(view)
        return view
    }

    private func marks(_ view: EditorTextView) -> [Int] { (0..<view.document.lineCount).map { view.document.diffMark($0) } }

    // MARK: - ダイアログ

    /// 自分は上の欄、ほかの文書は一覧（名前の似ているものを選ぶ）。ほかがないときは外部ファイルだけ
    func testDialogListsOtherDocuments() throws {
        let view = try makeView("a\n", name: "main.c")
        try makeView("x\n", name: "other.txt")
        try makeView("y\n", name: "main.h")
        let dialog = try XCTUnwrap(DiffDialogController(view: view))
        XCTAssertTrue(dialog.page.text("IDC_STATIC_DIFF_SRC").hasSuffix("main.c  [UTF-8]"), dialog.page.text("IDC_STATIC_DIFF_SRC"))
        XCTAssertEqual(dialog.others.map { ($0.path as NSString).lastPathComponent }, ["other.txt", "main.h"])
        let list = try XCTUnwrap(dialog.page.list("IDC_LIST_DIFF_FILES"))
        XCTAssertTrue(list.rows[0][0].hasPrefix("2 "), "アクセスキーの番号：\(list.rows[0][0])")
        XCTAssertEqual(list.selectedRow, 1, "名前の似ている main.h")
        XCTAssertTrue(dialog.page.isChecked("IDC_RADIO_DIFF_DST2"))

        views = [view]
        let alone = try XCTUnwrap(DiffDialogController(view: view))
        XCTAssertTrue(alone.page.isChecked("IDC_RADIO_DIFF_DST1"))
        XCTAssertFalse(alone.page.isEnabled("IDC_RADIO_DIFF_DST2"))
        XCTAssertFalse(alone.page.isEnabled("IDC_LIST_DIFF_FILES"))
    }

    /// 選択肢は前回のもの（原版 m_nDiffFlgOpt）、「次の差分」の 2 つは共通設定
    func testDialogOptions() throws {
        let view = try makeView("a\n")
        try makeView("b\n")
        DiffDialogController.lastFlags = 0x01 | 0x08 | 0x20 | 0x40
        let dialog = try XCTUnwrap(DiffDialogController(view: view))
        XCTAssertTrue(dialog.page.isChecked("IDC_CHECK_DIFF_OPT_CASE"))
        XCTAssertFalse(dialog.page.isChecked("IDC_CHECK_DIFF_OPT_SPACE"))
        XCTAssertTrue(dialog.page.isChecked("IDC_CHECK_DIFF_OPT_BLINE"))
        XCTAssertTrue(dialog.page.isChecked("IDC_RADIO_DIFF_FILE2"), "編集中ファイルが旧ファイル")
        XCTAssertTrue(dialog.page.isChecked("IDC_CHECK_DIFF_EXEC_STATE"))
        dialog.page.setChecked("IDC_CHECK_DIFF_OPT_SPACE", true)
        dialog.page.setChecked("IDC_CHECK_DIFF_OPT_CASE", false)
        dialog.page.setChecked("IDC_CHECK_SEARCHALL", true)
        dialog.page.setChecked("IDC_CHECK_NOTIFYNOTFOUND", false)
        dialog.press("IDOK")
        XCTAssertTrue(dialog.isAccepted)
        XCTAssertEqual(dialog.flags, 0x02 | 0x08 | 0x20 | 0x40)
        XCTAssertEqual(DiffDialogController.lastFlags, dialog.flags)
        XCTAssertEqual(EditorCore.commonSetting(section: "Other", key: "nDiffFlgOpt"), String(dialog.flags), "sakura.ini の [Other]")
        XCTAssertTrue(EditorCore.searchSettings.searchAll)
        XCTAssertFalse(EditorCore.searchSettings.notifyNotFound)
    }

    /// 外部ファイルの名前を入れると「外部ファイルを指定」、一覧を選ぶと「他の編集中のファイル」。空の名前は OK できない
    func testDialogRadioFollowsInput() throws {
        let view = try makeView("a\n")
        try makeView("b\n")
        let dialog = try XCTUnwrap(DiffDialogController(view: view))
        dialog.page.setText("IDC_EDIT_DIFF_DST", "/tmp/x.txt")
        dialog.page.onChange?("IDC_EDIT_DIFF_DST")
        XCTAssertTrue(dialog.page.isChecked("IDC_RADIO_DIFF_DST1"))
        XCTAssertEqual(dialog.page.list("IDC_LIST_DIFF_FILES")?.selectedRow, -1)
        dialog.page.setChecked("IDC_RADIO_DIFF_DST2", true)
        dialog.page.onChange?("IDC_RADIO_DIFF_DST2")
        XCTAssertEqual(dialog.page.list("IDC_LIST_DIFF_FILES")?.selectedRow, 0, "前に選んでいたもの")
        // 参照
        DiffDialogController.chooseFile = { _, _ in "/tmp/chosen.txt" }
        dialog.press("IDC_BUTTON_DIFF_DST")
        XCTAssertEqual(dialog.page.text("IDC_EDIT_DIFF_DST"), "/tmp/chosen.txt")
        XCTAssertTrue(dialog.page.isChecked("IDC_RADIO_DIFF_DST1"))
        dialog.page.setText("IDC_EDIT_DIFF_DST", "")
        dialog.press("IDOK")
        XCTAssertFalse(dialog.isAccepted, "外部ファイルの名前が空")
    }

    // MARK: - 差分の表示

    /// 他の編集中の文書と比べて、この文書の行に印（追加・変更・削除）、行番号に「DIFF差分表示」の色
    func testDiffWithOpenDocument() throws {
        let view = try makeView("a\nX\nb\nc\n")
        try makeView("a\nb\nd\n")
        DiffDialogController.runModal = { dialog in
            dialog.page.list("IDC_LIST_DIFF_FILES")?.select(0)
            dialog.press("IDOK")
            return dialog.isAccepted
        }
        CommandTable.perform(30976, from: view)
        XCTAssertEqual(marks(view), [0, 1, 0, 2])
        XCTAssertEqual(view.lineNumberColor(line: 1).info.back, view.color(.diffAppend).back)
        XCTAssertEqual(view.lineNumberColor(line: 3).info.back, view.color(.diffChange).back)
        // 次・前の差分
        let settings = EditorCore.searchSettings
        settings.searchAll = false
        settings.notifyNotFound = true
        EditorCore.searchSettings = settings
        CommandTable.perform(30978, from: view)
        XCTAssertEqual(view.caret.line, 1)
        CommandTable.perform(30978, from: view)
        XCTAssertEqual(view.caret.line, 3)
        CommandTable.perform(30978, from: view)
        XCTAssertEqual(messages.last ?? nil, "前方(↓) に差分が見つかりません。")
        CommandTable.perform(30979, from: view)
        XCTAssertEqual(view.caret.line, 1)
        // メニュー：差分を表示していないと次・前・全解除は使えない
        let item = NSMenuItem(title: "", action: #selector(EditorTextView.diffNext(_:)), keyEquivalent: "")
        XCTAssertTrue(view.validateMenuItem(item))
        CommandTable.perform(30980, from: view)
        XCTAssertEqual(marks(view), [0, 0, 0, 0])
        XCTAssertFalse(view.validateMenuItem(item))
    }

    /// 外部ファイル：見つからないとき・バイナリのとき・差分がないときのメッセージ
    func testDiffWithFile() throws {
        let view = try makeView("a\nb\n")
        let file = directory.appendingPathComponent("old.txt")
        try "a\n".write(to: file, atomically: true, encoding: .utf8)
        var path = file.path
        var flags = 0
        DiffDialogController.runModal = { dialog in
            dialog.page.setText("IDC_EDIT_DIFF_DST", path)
            dialog.page.onChange?("IDC_EDIT_DIFF_DST")
            dialog.page.setChecked("IDC_CHECK_DIFF_EXEC_STATE", flags & 0x40 != 0)
            dialog.press("IDOK")
            return dialog.isAccepted
        }
        view.diffDialog(nil)
        XCTAssertEqual(marks(view), [0, 1])
        path = directory.appendingPathComponent("none.txt").path
        view.diffDialog(nil)
        XCTAssertEqual(messages.last ?? nil, "差分コマンド実行は失敗しました。\n\n比較するファイルが見つかりません。")
        XCTAssertEqual(marks(view), [0, 1], "印はそのまま")
        try Data([0x61, 0x00, 0x62]).write(to: file)
        path = file.path
        view.diffDialog(nil)
        XCTAssertEqual(messages.last ?? nil, "DIFF差分を行おうとしたファイルはバイナリファイルです。")
        try "a\nb\n".write(to: file, atomically: true, encoding: .utf8)
        flags = 0x40
        view.diffDialog(nil)
        XCTAssertEqual(messages.last ?? nil, "DIFF差分は見つかりませんでした。")
    }

    /// 行番号の左に DIFF の印を描く（行番号の文字色）
    func testDiffMarkDrawn() throws {
        let view = try makeView("a\nX\n")
        view.viewDiff("a\n", flags: 0)
        XCTAssertEqual(marks(view), [0, 1])
        let row = view.lineTop(1)
        let center = (row + view.lineHeight / 2).rounded(.down)
        XCTAssertEqual(pixel(view, NSPoint(x: 4, y: center)), view.color(.diffAppend).text, "＋ の縦線")
        XCTAssertEqual(pixel(view, NSPoint(x: 4, y: (view.lineTop(0) + view.lineHeight / 2).rounded(.down))),
                       view.color(.lineNumber).back, "印のない行")
    }

    // MARK: - ファイル内容比較

    /// カーソル位置から比べて、最初に異なる位置に両方のカーソル。同じときは「異なる箇所は見つかりませんでした。」
    func testCompare() throws {
        let view = try makeView("abc\ndef\n", name: "a.txt")
        let other = try makeView("abc\ndXf\n", name: "b.txt")
        _ = EditorCore.setCommonSetting("0", section: "Common", key: "bCompareAndTileHorz")
        CompareDialogController.runModal = { dialog in
            XCTAssertTrue(dialog.page.text("IDC_STATIC_COMPARESRC").hasSuffix("a.txt  [UTF-8]"))
            XCTAssertEqual(dialog.page.list("IDC_LIST_FILES")?.rows.count, 1)
            XCTAssertFalse(dialog.page.isChecked("IDC_CHECK_TILE_H"))
            dialog.press("IDOK")
            return dialog.isAccepted
        }
        XCTAssertTrue(CommandTable.perform(30950, from: view))
        XCTAssertEqual([view.caret.line, view.caret.column], [1, 1])
        XCTAssertEqual([other.caret.line, other.caret.column], [1, 1])
        XCTAssertEqual(messages.last ?? nil, "異なる箇所が見つかりました。")
        // 異なる箇所のあとから：同じ
        view.setCaret(EditorPosition(line: 1, column: 2))
        other.setCaret(EditorPosition(line: 1, column: 2))
        view.compareFiles(nil)
        XCTAssertEqual(messages.last ?? nil, "異なる箇所は見つかりませんでした。")
        // メニュー：窓口が 1 つのときは使えない
        let item = NSMenuItem(title: "", action: #selector(EditorTextView.compareFiles(_:)), keyEquivalent: "")
        XCTAssertTrue(view.validateMenuItem(item))
        views = [view]
        XCTAssertFalse(view.validateMenuItem(item))
    }

    /// 左右に並べて表示
    func testCompareTilesWindows() throws {
        let view = try makeView("a\n")
        let other = try makeView("b\n")
        CompareDialogController.runModal = { dialog in
            dialog.page.setChecked("IDC_CHECK_TILE_H", true)
            dialog.press("IDOK")
            return dialog.isAccepted
        }
        view.compareFiles(nil)
        let left = try XCTUnwrap(view.window), right = try XCTUnwrap(other.window)
        XCTAssertEqual(left.frame.minY, right.frame.minY, accuracy: 1)
        XCTAssertEqual(left.frame.maxX, right.frame.minX, accuracy: 1)
        XCTAssertEqual(EditorCore.commonSetting(section: "Common", key: "bCompareAndTileHorz"), "1")
    }

    /// 视图上一点画出来的颜色（0xRRGGBB）
    private func pixel(_ view: EditorTextView, _ point: NSPoint) -> UInt32 {
        let width = Int(view.bounds.width), height = Int(view.bounds.height)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return 0xDEAD
        }
        view.displayIgnoringOpacity(view.bounds, in: NSGraphicsContext(cgContext: context, flipped: false))
        guard let data = context.data else { return 0xDEAD }
        let x = min(max(0, Int(point.x)), width - 1), y = min(max(0, Int(point.y)), height - 1)
        let bytes = data.assumingMemoryBound(to: UInt8.self)
        let offset = y * context.bytesPerRow + x * 4
        return (UInt32(bytes[offset]) << 16) | (UInt32(bytes[offset + 1]) << 8) | UInt32(bytes[offset + 2])
    }
}

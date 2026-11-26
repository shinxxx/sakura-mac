// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge
import XCTest

/// ブックマーク（计划第 44 步）：設定・解除（選択範囲）、次・前（先頭から再検索・見つからないとき）、全解除、
/// パターンに一致する行をマーク（検索・置換ダイアログの「該当行マーク」）、ブックマークの一覧（アウトライン）、
/// 行番号の「ブックマーク」の色、「最近使ったファイル」からの復元。
/// 探す算法と保存の形式は核心库的测试（test-mac-edit-support.cpp，与 Windows 官方版对照）确认
final class BookmarkTests: XCTestCase {
    private var window: NSWindow!
    private var view: EditorTextView!
    private var messages: [String?] = []
    private var savedSearch: EditorSearchSettings!
    private var overrides: [TypeColorOverride] = []

    override func setUpWithError() throws {
        _ = TestCore.home
        _ = NSApplication.shared
        OutlineWindowController.hidesOnDeactivate = false
        savedSearch = EditorCore.searchSettings
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
        for o in overrides.reversed() { o.restore(view.document) }
        overrides = []
        view.outlinePanel?.close()
        view.findPanel?.close()
        view.replacePanel?.close()
        EditorTextView.messageHandler = nil
        EditorCore.searchSettings = savedSearch
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

    private var marked: [Int] { (0..<view.document.lineCount).filter { view.document.isBookmarked($0) } }

    private func setSearchAll(_ on: Bool) {
        let settings = EditorCore.searchSettings
        settings.searchAll = on
        settings.notifyNotFound = true
        EditorCore.searchSettings = settings
    }

    // MARK: - 設定・解除

    func testSetToggleAndReset() {
        load("a\nb\nc\nd\ne\n")
        view.setCaret(pos(1, 1))
        run(30970)
        XCTAssertEqual(marked, [1])
        run(30970)
        XCTAssertEqual(marked, [], "もう一度で解除")
        // 複数行の選択：選択の終わりの行（0 桁でも）まで反転
        view.setCaret(pos(1, 0))
        run(30970)
        view.setSelection(from: pos(1, 0), to: pos(3, 0))
        run(30970)
        XCTAssertEqual(marked, [2, 3])
        // 1 行の中の選択はカーソル行
        view.setSelection(from: pos(4, 0), to: pos(4, 1))
        run(30970)
        XCTAssertEqual(marked, [2, 3, 4])
        run(30973)	// 全解除
        XCTAssertEqual(marked, [])
    }

    /// 矩形選択も画面上の行の範囲
    func testSetWithBoxSelection() {
        load("abc\nabc\nabc\n")
        view.setBoxSelection(EditorBoxRange(top: 0, bottom: 2, left: 0, right: Int(view.charWidth)))
        run(30970)
        XCTAssertEqual(marked, [0, 1, 2])
    }

    // MARK: - 次・前

    func testNextPrev() {
        load("0\n1\n2\n3\n4\n5\n")
        view.document.setBookmark(true, line: 1)
        view.document.setBookmark(true, line: 4)
        setSearchAll(false)
        run(30971)
        XCTAssertEqual([view.caret.line, view.caret.column], [1, 0])
        run(30971)
        XCTAssertEqual(view.caret.line, 4)
        run(30971)
        XCTAssertEqual(view.caret.line, 4, "見つからない")
        XCTAssertEqual(messages.last ?? nil, "前方(↓) にブックマークが見つかりません。")
        run(30972)
        XCTAssertEqual(view.caret.line, 1)
        run(30972)
        XCTAssertEqual(messages.last ?? nil, "後方(↑) にブックマークが見つかりません。")
        // 先頭（末尾）から再検索する
        setSearchAll(true)
        messages = []
        run(30972)
        XCTAssertEqual(view.caret.line, 4)
        run(30971)
        XCTAssertEqual(view.caret.line, 1)
        XCTAssertEqual(messages.count, 0)
        // 見つからないときにメッセージを表示しない：蜂鸣
        let settings = EditorCore.searchSettings
        settings.notifyNotFound = false
        EditorCore.searchSettings = settings
        run(30973)
        run(30971)
        XCTAssertEqual(messages.count, 1)
        XCTAssertNil(messages.first ?? "")
    }

    /// 選択ロック中は選択を広げる
    func testNextKeepsSelectingLock() {
        load("0\n1\n2\n")
        view.document.setBookmark(true, line: 2)
        run(30410)	// F_BEGIN_SEL
        run(30971)
        let selection = view.selection
        XCTAssertEqual([selection?.from.line, selection?.to.line], [0, 2])
    }

    // MARK: - パターンに一致する行をマーク

    func testPatternUsesCurrentSearchKey() {
        load("ab\nxx\nAB\n")
        view.setSearchKey("ab", options: [.matchCase])
        run(30975)
        XCTAssertEqual(marked, [0])
        view.setSearchKey("(", options: [.regularExpression])
        run(30975)
        XCTAssertEqual(messages.count, 1, "正規表現の错误")
    }

    /// 検索ダイアログ・置換ダイアログの「該当行マーク」
    func testMarkButtonsInDialogs() throws {
        load("one\ntwo\none two\n")
        let find = FindPanelController(view: view)
        find.open(text: "one")
        let findMark = try XCTUnwrap(find.window?.contentView.flatMap { Self.control("findMark", in: $0) } as? NSButton)
        XCTAssertTrue(findMark.isEnabled)
        findMark.performClick(nil)
        XCTAssertEqual(marked, [0, 2])
        find.close()
        view.document.resetBookmarks()
        let replace = ReplacePanelController(view: view)
        replace.open(text: "two", selected: false)
        let replaceMark = try XCTUnwrap(replace.window?.contentView.flatMap { Self.control("replaceMark", in: $0) } as? NSButton)
        replaceMark.performClick(nil)
        XCTAssertEqual(marked, [1, 2])
        replace.close()
    }

    // MARK: - 一覧

    func testBookmarkViewInOutline() throws {
        load("first\nsecond\nthird\n")
        view.document.setBookmark(true, line: 0)
        view.document.setBookmark(true, line: 2)
        run(30974)
        let panel = try XCTUnwrap(view.outlinePanel)
        XCTAssertEqual(panel.outlineType, .bookmark)
        XCTAssertEqual(panel.result.rows.map(\.name), ["first", "third"])
        XCTAssertEqual(panel.result.rows.map(\.line), [1, 3])
    }

    // MARK: - 行番号の色

    /// ブックマークの行の行番号は「ブックマーク」の色（既定：背景 0080C0、文字 FFFBF0）
    func testLineNumberColor() {
        load("a\nb\n")
        view.document.setBookmark(true, line: 1)
        let mark = view.color(.mark)
        XCTAssertTrue(mark.display)
        XCTAssertEqual(view.lineNumberColor(line: 1).info.back, mark.back)
        XCTAssertEqual(view.lineNumberColor(line: 0).info.back, view.color(.lineNumber).back)
        XCTAssertEqual(pixel(at: NSPoint(x: 2, y: view.lineTop(1) + 1)), 0x0080C0)
        XCTAssertEqual(pixel(at: NSPoint(x: 2, y: view.lineTop(0) + 1)), view.color(.lineNumber).back)
    }

    /// 変更行のブックマーク：色・太字が「行番号」と同じところは「行番号（変更行）」のもの（原版 2013.12.30）
    func testModifiedLineInheritsToBookmark() {
        load("a\nb\n")
        overrides.append(TypeColorOverride(document: view.document, name: "MRK", value: "1,0,ff0000,f0fbff,0"))	// 文字は「行番号」と同じ青
        view.typeSettingsReloaded()
        view.document.setBookmark(true, line: 0)
        XCTAssertTrue(view.document.isLineModified(0))
        let info = view.lineNumberColor(line: 0).info
        XCTAssertTrue(info.bold, "変更行の太字")
        XCTAssertEqual(info.back, 0xFFFBF0, "背景は「ブックマーク」のもの（ini は BGR）")
    }

    /// 「ブックマーク」を表示しないときは行番号の左に縦線
    func testMarkBarWhenColorHidden() {
        load("a\nb\n")
        overrides.append(TypeColorOverride(document: view.document, name: "MRK", value: "0,0,f0fbff,c08000,0"))
        view.typeSettingsReloaded()
        view.document.setBookmark(true, line: 1)
        XCTAssertTrue(view.lineNumberColor(line: 1).markBar)
        XCTAssertEqual(pixel(at: NSPoint(x: 1, y: view.lineTop(1) + 2)), view.color(.lineNumber).text)
        XCTAssertNotEqual(pixel(at: NSPoint(x: 1, y: view.lineTop(0) + 2)), view.color(.lineNumber).text)
    }

    /// 行番号を表示しないときも左の余白をブックマークの色で塗る
    func testHiddenLineNumbersStillShowBookmark() {
        load("a\nb\n")
        overrides.append(TypeColorOverride(document: view.document, name: "LNO", value: "0,0,ff0000,efefef,0"))
        view.typeSettingsReloaded()
        XCTAssertFalse(view.document.viewSettings.showLineNumbers)
        view.document.setBookmark(true, line: 1)
        XCTAssertEqual(pixel(at: NSPoint(x: 3, y: view.lineTop(1) + 1)), 0x0080C0)
    }

    // MARK: - 最近使ったファイル

    /// 閉じるときに登録したブックマークを、次に開いたときに復元する
    func testRestoredFromRecentFiles() throws {
        let url = TestCore.home.appendingPathComponent("bookmark-recent.txt")
        try "1\n2\n3\n".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(view.document.open(path: url.path), .success)
        view.document.setBookmark(true, line: 2)
        view.document.addToRecent(caret: pos(0, 0), viewTopLine: 0)
        let other = try XCTUnwrap(EditorDocument())
        XCTAssertEqual(other.open(path: url.path), .success)
        XCTAssertTrue(other.isBookmarked(2))
        XCTAssertFalse(other.isBookmarked(1))
    }

    /// 识别名（accessibilityIdentifier）が id のコントロール
    private static func control(_ id: String, in view: NSView) -> NSView? {
        if view.accessibilityIdentifier() == id { return view }
        for sub in view.subviews {
            if let found = control(id, in: sub) { return found }
        }
        return nil
    }

    /// 视图上一点画出来的颜色（0xRRGGBB）
    private func pixel(at point: NSPoint) -> UInt32 {
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

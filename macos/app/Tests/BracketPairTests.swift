// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge
import XCTest

/// 文書のタイプの色の設定を一時的に変える（第 44 步的测试共用）。終わったら元に戻す
struct TypeColorOverride {
    let section: String
    let key: String
    let original: String?

    /// name は原版の色の名前（C[BRC] の BRC）
    init(document: EditorDocument, name: String, value: String) {
        section = "Types(\(document.typeIndex))"
        key = "C[\(name)]"
        original = EditorCore.commonSetting(section: section, key: key)
        _ = EditorCore.setCommonSetting(value, section: section, key: key)
        _ = document.applyTypeSettingChange(document.typeIndex)
    }

    func restore(_ document: EditorDocument) {
        if let original { _ = EditorCore.setCommonSetting(original, section: section, key: key) }
        _ = document.applyTypeSettingChange(document.typeIndex)
    }
}

/// 対括弧の検索（F_BRACKETPAIR）と対括弧の強調表示（计划第 44 步）。
/// 探す算法は核心库的测试（test-mac-edit-support.cpp，与 Windows 官方版对照）确认
final class BracketPairTests: XCTestCase {
    private var window: NSWindow!
    private var view: EditorTextView!
    private var override: TypeColorOverride?

    override func setUpWithError() throws {
        _ = TestCore.home
        _ = NSApplication.shared
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
    }

    override func tearDown() {
        override?.restore(view.document)
        override = nil
        window.close()
        window = nil
        view = nil
    }

    private func load(_ text: String, caret: EditorPosition = EditorPosition(line: 0, column: 0)) {
        XCTAssertEqual(view.document.insert(text, at: EditorPosition(line: 0, column: 0)), .success)
        view.contentDidChange()
        view.setCaret(caret)
    }

    private func pos(_ line: Int, _ column: Int) -> EditorPosition { EditorPosition(line: line, column: column) }

    private func assertCaret(_ line: Int, _ column: Int, file: StaticString = #filePath, line sourceLine: UInt = #line) {
        XCTAssertEqual([view.caret.line, view.caret.column], [line, column], "光标", file: file, line: sourceLine)
    }

    /// 「対括弧」の色を表示する（原版の既定は表示しない）。背景は緑、文字は赤、太字
    private func enableHighlight() {
        override = TypeColorOverride(document: view.document, name: "BRC", value: "1,1,0000ff,00ff00,0")
        view.typeSettingsReloaded()
    }

    /// 描いたあと（強調表示の位置は描くときに決まる。画面に出ていないウィンドウなのでビットマップに描く）の、この行で対括弧の色の文字
    private func highlighted(row: Int) -> [Int] {
        _ = pixel(at: .zero)
        let colors = view.charColors(row: row)
        return colors.indices.filter { colors[$0]?.back == view.color(.bracketPair).back && colors[$0]?.display == true }
    }

    // MARK: - 対括弧の検索

    func testBracketPairCommand() {
        load("f(a(b)c)d")
        view.setCaret(pos(0, 1))
        XCTAssertTrue(CommandTable.perform(30960, from: view))
        assertCaret(0, 7)
        CommandTable.perform(30960, from: view)
        assertCaret(0, 1)
        // ')' の後ろ：直前の文字の対括弧
        view.setCaret(pos(0, 8))
        CommandTable.perform(30960, from: view)
        assertCaret(0, 1)
        // 括弧がない：動かない
        view.setCaret(pos(0, 9))
        CommandTable.perform(30960, from: view)
        assertCaret(0, 9)
    }

    /// 複数行、選択ロック中は選択を広げる（原版 MoveCursorSelecting）
    func testBracketPairAcrossLinesAndSelectingLock() {
        load("{\n  x;\n}\n")
        CommandTable.perform(30960, from: view)
        assertCaret(2, 0)
        CommandTable.perform(30410, from: view)	// F_BEGIN_SEL 範囲選択開始
        CommandTable.perform(30960, from: view)
        assertCaret(0, 0)
        let selection = view.selection
        XCTAssertNotNil(selection)
        XCTAssertEqual([selection?.from.line, selection?.from.column, selection?.to.line, selection?.to.column], [0, 0, 2, 0])
    }

    /// メニューは「検索」にあって使える
    func testMenuItemEnabled() {
        let item = NSMenuItem(title: "対括弧の検索", action: CommandTable.selector(for: 30960), keyEquivalent: "")
        item.tag = 30960
        XCTAssertTrue(view.responds(to: item.action))
    }

    // MARK: - 強調表示

    /// 既定（「対括弧」を表示しない）では強調しない
    func testNoHighlightByDefault() {
        load("(a)")
        XCTAssertFalse(view.color(.bracketPair).display)
        XCTAssertEqual(highlighted(row: 0), [])
    }

    /// カーソル位置の括弧と対括弧の両方を「対括弧」の色で描く
    func testHighlightBothBrackets() {
        enableHighlight()
        load("x(a[b]c)y")
        view.setCaret(pos(0, 1))
        XCTAssertEqual(highlighted(row: 0), [1, 7])
        // 直前の文字が括弧
        view.setCaret(pos(0, 6))
        XCTAssertEqual(highlighted(row: 0), [3, 5])
        // 括弧でない
        view.setCaret(pos(0, 9))
        XCTAssertEqual(highlighted(row: 0), [])
        // 太字の設定が文字に使われる
        view.setCaret(pos(0, 1))
        XCTAssertEqual(highlighted(row: 0), [1, 7])
        XCTAssertEqual(view.charColors(row: 0).count, 9)
        XCTAssertEqual(view.charColors(row: 0).first { $0 != nil }??.bold, true)
    }

    /// 選択中、フォーカスがないときは描かない（原版 DrawBracketPair）。選択が終わればまた描く
    func testNoHighlightWhileSelectingOrUnfocused() {
        enableHighlight()
        load("(abc)")
        view.setCaret(pos(0, 0))
        XCTAssertEqual(highlighted(row: 0), [0, 4])
        view.setSelection(from: pos(0, 2), to: pos(0, 0))	// カーソルは選択の終わり（0 桁）
        XCTAssertEqual(highlighted(row: 0), [])
        view.clearSelection()
        XCTAssertEqual(highlighted(row: 0), [0, 4])
        window.makeFirstResponder(nil)
        XCTAssertEqual(highlighted(row: 0), [])
        window.makeFirstResponder(view)
        XCTAssertEqual(highlighted(row: 0), [0, 4])
    }

    /// 対括弧が表示領域の外のときは強調しない（原版 SetBracketPairPos：mode 2）
    func testNoHighlightOutsideVisibleArea() {
        enableHighlight()
        load("(\n" + String(repeating: "x\n", count: 100) + ")\n")
        view.setCaret(pos(0, 0))
        XCTAssertEqual(highlighted(row: 0), [])
        XCTAssertNil(view.bracketHighlight)
        // F_BRACKETPAIR は表示領域の外も探す
        CommandTable.perform(30960, from: view)
        assertCaret(101, 0)
        XCTAssertEqual(highlighted(row: 101), [], "カーソルが ')' に来ても '(' は画面の外")
    }

    /// 画面に描かれた色：背景が「対括弧」の背景色
    func testDrawnBackground() throws {
        enableHighlight()
        load("(abc)")
        view.setCaret(pos(0, 4))
        let x = view.displayX(row: 0, index: 0) + 1
        let y = view.lineTop(0) + 1
        XCTAssertEqual(pixel(at: NSPoint(x: x, y: y)), 0x00FF00)
        let x2 = view.displayX(row: 0, index: 2) + 1
        XCTAssertEqual(pixel(at: NSPoint(x: x2, y: y)), view.color(.text).back)
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

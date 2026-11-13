// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge
import XCTest

/// 基本编辑（计划第 29 步）的测试：剪贴板、矩形选择的编辑、TAB 缩进、改行的オートインデント。
///
/// 处理本身在核心库里（与原版 CViewCommander 相同，macos/core/tests/test-mac-edit.cpp 测试），
/// 这里确认视图的命令把选择范围、光标、剪贴板的形式正确地交给核心库，并且每个命令是撤销的一步。
/// 剪贴板用测试专用的，不碰运行者自己的剪贴板。
final class EditorEditTests: XCTestCase {
    private var window: NSWindow!
    private var view: EditorTextView!
    private var pasteboard: NSPasteboard!
    private let notFound = NSRange(location: NSNotFound, length: 0)

    override func setUpWithError() throws {
        _ = TestCore.home
        _ = NSApplication.shared
        let document = try XCTUnwrap(EditorDocument())
        window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 600, height: 400),
                          styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        view = EditorTextView(document: document)
        view.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        window.contentView = view
        window.makeFirstResponder(view)
        pasteboard = NSPasteboard(name: NSPasteboard.Name("jp.sakura-editor.tests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        view.pasteboard = pasteboard
    }

    override func tearDown() {
        pasteboard.releaseGlobally()
        window.close()
        window = nil
        view = nil
    }

    private func load(_ text: String, caret: EditorPosition = EditorPosition(line: 0, column: 0)) {
        XCTAssertEqual(view.document.insert(text, at: EditorPosition(line: 0, column: 0)), .success)
        view.setCaret(caret)
    }

    private var text: String { view.document.text }
    private var w: Int { view.document.charWidth }

    private func pos(_ line: Int, _ column: Int) -> EditorPosition {
        EditorPosition(line: line, column: column)
    }

    private func assertCaret(_ line: Int, _ column: Int, file: StaticString = #filePath, line sourceLine: UInt = #line) {
        XCTAssertEqual(view.caret.line, line, "光标的行", file: file, line: sourceLine)
        XCTAssertEqual(view.caret.column, column, "光标的列", file: file, line: sourceLine)
    }

    // MARK: - 剪贴板

    func testCopyAndPasteSelection() {
        load("abc\ndef\n")
        view.setSelection(from: pos(0, 1), to: pos(1, 2))
        view.copy(nil)
        XCTAssertEqual(pasteboard.string(forType: .string), "bc\nde")
        XCTAssertFalse(pasteboard.types?.contains(EditorTextView.columnSelectType) ?? true)
        XCTAssertNotNil(view.selection, "默认复制后不取消选择")

        // 贴付替换选择范围
        view.setSelection(from: pos(1, 0), to: pos(1, 3))
        view.paste(nil)
        XCTAssertEqual(text, "abc\nbc\nde\n")
        assertCaret(2, 2)
        XCTAssertNil(view.selection)
        XCTAssertEqual(view.document.undo(), .success)
        XCTAssertEqual(text, "abc\ndef\n", "贴付是撤销的一步")
    }

    func testCutSelection() {
        load("abc\ndef\n")
        view.setSelection(from: pos(0, 1), to: pos(1, 1))
        view.cut(nil)
        XCTAssertEqual(pasteboard.string(forType: .string), "bc\nd")
        XCTAssertEqual(text, "aef\n")
        assertCaret(0, 1)
    }

    /// 没有选择时复制、切り取り光标所在的一行（「選択なしでコピーを可能にする」），贴在行首（ラインモード貼り付け）
    func testLineCopyAndLineModePaste() {
        load("abc\ndef\n", caret: pos(1, 1))
        view.copy(nil)
        XCTAssertEqual(pasteboard.string(forType: .string), "def\n")
        XCTAssertTrue(pasteboard.types?.contains(EditorTextView.lineSelectType) ?? false)

        view.setCaret(pos(0, 2))
        view.paste(nil)
        XCTAssertEqual(text, "def\nabc\ndef\n", "贴在光标所在行的行首")
        assertCaret(1, 2)

        view.setCaret(pos(0, 1))
        view.cut(nil)
        XCTAssertEqual(text, "abc\ndef\n")
        XCTAssertEqual(pasteboard.string(forType: .string), "def\n")
        assertCaret(0, 1)
        XCTAssertEqual(view.document.undo(), .success)
        XCTAssertEqual(text, "def\nabc\ndef\n")
    }

    /// 矩形选择的复制：每行加 CRLF，带矩形的标记；贴付时自动按矩形贴付
    func testBoxCopyAndPaste() {
        load("abcd\nefgh\n")
        view.setBoxSelection(EditorBoxRange(top: 0, bottom: 1, left: w, right: 3 * w))
        view.copy(nil)
        XCTAssertEqual(pasteboard.string(forType: .string), "bc\r\nfg\r\n")
        XCTAssertTrue(pasteboard.types?.contains(EditorTextView.columnSelectType) ?? false)

        view.setCaret(pos(0, 4))
        view.paste(nil)
        XCTAssertEqual(text, "abcdbc\nefghfg\n")
        assertCaret(0, 4)
        XCTAssertEqual(view.document.undo(), .success)
        XCTAssertEqual(text, "abcd\nefgh\n")

        // 矩形貼り付け：普通的文字也按行贴在同一横向位置
        pasteboard.clearContents()
        pasteboard.setString("X\nY", forType: .string)
        view.setCaret(pos(0, 1))
        view.pasteAsBox(nil)
        XCTAssertEqual(text, "aXbcd\neYfgh\n")
    }

    func testBoxCutAndDelete() {
        load("abcd\nefgh\nij\n")
        view.setBoxSelection(EditorBoxRange(top: 0, bottom: 2, left: w, right: 3 * w))
        view.cut(nil)
        XCTAssertEqual(pasteboard.string(forType: .string), "bc\r\nfg\r\nj\r\n")
        XCTAssertEqual(text, "ad\neh\ni\n")
        assertCaret(0, 1)
        XCTAssertEqual(view.document.undo(), .success)
        XCTAssertEqual(text, "abcd\nefgh\nij\n", "矩形删除是撤销的一步")

        view.setBoxSelection(EditorBoxRange(top: 0, bottom: 1, left: 2 * w, right: 4 * w))
        view.deleteBackward(nil)
        XCTAssertEqual(text, "ab\nef\nij\n")
    }

    /// 矩形选择中输入：每行插入，矩形往右移（宽度 0 的矩形是几行的同一位置）
    func testTypingIntoBoxInsertsOnEveryLine() {
        load("abc\nd\nefg\n")
        view.setBoxSelection(EditorBoxRange(top: 0, bottom: 2, left: w, right: w))
        view.insertText("X", replacementRange: notFound)
        XCTAssertEqual(text, "aXbc\ndX\neXfg\n")
        view.insertText("Y", replacementRange: notFound)
        XCTAssertEqual(text, "aXYbc\ndXY\neXYfg\n", "矩形选择保留，继续输入")
        XCTAssertNotNil(view.boxRange)

        // 输入法确定的文字也一样
        view.setMarkedText("に", selectedRange: NSRange(location: 1, length: 0), replacementRange: notFound)
        XCTAssertNotNil(view.boxRange, "输入中保留矩形选择")
        view.insertText("日", replacementRange: notFound)
        XCTAssertEqual(text, "aXY日bc\ndXY日\neXY日fg\n")
    }

    // MARK: - TAB、改行

    func testTabIndentsSelectedLines() {
        load("a\nb\nc\n")
        view.setSelection(from: pos(0, 0), to: pos(2, 0))
        view.insertTab(nil)
        XCTAssertEqual(text, "\ta\n\tb\nc\n", "终点在行首时不包括那一行")
        XCTAssertEqual(view.selection?.from.line, 0)
        XCTAssertEqual(view.selection?.to.line, 2)
        view.insertBacktab(nil)
        XCTAssertEqual(text, "a\nb\nc\n")
        XCTAssertNotNil(view.selection)

        // 一行之内的选择：换成 TAB
        view.setSelection(from: pos(0, 0), to: pos(0, 1))
        view.insertTab(nil)
        XCTAssertEqual(text, "\t\nb\nc\n")
        assertCaret(0, 1)
    }

    func testTabInBoxSelection() {
        load("abcd\nefgh\n")
        view.setBoxSelection(EditorBoxRange(top: 0, bottom: 1, left: w, right: 2 * w))
        view.insertTab(nil)
        XCTAssertEqual(text, "a\tbcd\ne\tfgh\n")
        XCTAssertEqual(view.boxRange?.left, 4 * w, "矩形往右移到 TAB 之后")
    }

    func testNewlineKeepsIndent() {
        load("\tabc", caret: pos(0, 4))
        view.insertNewline(nil)
        let eol = EditorCore.text(ofEol: view.document.newLineEol)
        XCTAssertEqual(text, "\tabc" + eol + "\t", "オートインデント")
        assertCaret(1, 1)
    }

    // MARK: - 菜单

    func testMenuValidation() {
        load("abc")
        func enabled(_ action: Selector) -> Bool {
            view.validateMenuItem(NSMenuItem(title: "", action: action, keyEquivalent: ""))
        }
        XCTAssertFalse(enabled(#selector(EditorTextView.paste(_:))), "剪贴板是空的")
        XCTAssertFalse(enabled(#selector(EditorTextView.pasteAsBox(_:))))
        XCTAssertTrue(enabled(#selector(EditorTextView.copy(_:))), "没有选择也能复制一行")
        view.copy(nil)
        XCTAssertTrue(enabled(#selector(EditorTextView.paste(_:))))
        XCTAssertTrue(enabled(#selector(EditorTextView.delete(_:))))
    }
}

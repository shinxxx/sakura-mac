// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge
import XCTest

/// 自绘视图的输入法接口（NSTextInputClient）的测试（计划第 25 步）。
///
/// 真的输入法只能在 Mac 上用手试（见 macos/docs/phase2-ime.md 的确认步骤）。
/// 这里按输入法调用的顺序直接调用 NSTextInputClient 的方法，确认：
/// 未确定文字不进文档、确定后进文档并能撤销、候选窗口的位置跟着文字走、重新转换的范围替换。
final class EditorTextViewTests: XCTestCase {
    private var window: NSWindow!
    private var view: EditorTextView!
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
    }

    override func tearDown() {
        window.close()
        window = nil
        view = nil
    }

    private func load(_ text: String, caret: EditorPosition) {
        XCTAssertEqual(view.document.insert(text, at: EditorPosition(line: 0, column: 0)), .success)
        view.setCaret(caret)
    }

    private var text: String { view.document.text }

    // MARK: - 未确定文字

    /// 日文输入：「にほん」输入中不进文档，确定「日本」后才进文档
    func testMarkedTextStaysOutOfDocumentUntilCommitted() {
        load("abc", caret: EditorPosition(line: 0, column: 3))
        view.setMarkedText("にほん", selectedRange: NSRange(location: 3, length: 0), replacementRange: notFound)
        XCTAssertTrue(view.hasMarkedText())
        XCTAssertEqual(view.markedRange(), NSRange(location: 3, length: 3))
        XCTAssertEqual(view.selectedRange(), NSRange(location: 6, length: 0))
        XCTAssertEqual(text, "abc", "未确定文字不进文档")
        XCTAssertEqual(view.attributedSubstring(forProposedRange: NSRange(location: 0, length: 6), actualRange: nil)?.string, "abcにほん")

        // 转换：选中整个文节
        view.setMarkedText("日本", selectedRange: NSRange(location: 0, length: 2), replacementRange: notFound)
        XCTAssertEqual(view.markedRange(), NSRange(location: 3, length: 2))
        XCTAssertEqual(view.selectedRange(), NSRange(location: 3, length: 2))

        // 确定
        view.insertText("日本", replacementRange: notFound)
        XCTAssertFalse(view.hasMarkedText())
        XCTAssertEqual(view.markedRange().location, NSNotFound)
        XCTAssertEqual(text, "abc日本")
        XCTAssertEqual(view.caret.column, 5)
        XCTAssertEqual(view.selectedRange(), NSRange(location: 5, length: 0))

        // 撤销一次回到输入前（输入中的变化不进撤销记录）；再撤销一次是准备的「abc」
        XCTAssertEqual(view.document.undo(), .success)
        XCTAssertEqual(text, "abc")
        XCTAssertEqual(view.document.undo(), .success)
        XCTAssertEqual(text, "")
        XCTAssertFalse(view.document.canUndo)
    }

    /// 在行中间输入，后面的文字跟着让开；下标换算正确
    func testMarkedTextInMiddleOfMultilineText() {
        load("ab\ncd\nef", caret: EditorPosition(line: 1, column: 1))
        view.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0), replacementRange: notFound)
        XCTAssertEqual(view.markedRange(), NSRange(location: 4, length: 2))
        XCTAssertEqual(view.attributedSubstring(forProposedRange: NSRange(location: 0, length: 11), actualRange: nil)?.string, "ab\ncnid\nef")
        view.insertText("你", replacementRange: notFound)
        XCTAssertEqual(text, "ab\nc你d\nef")
        XCTAssertEqual(view.caret.line, 1)
        XCTAssertEqual(view.caret.column, 2)
    }

    /// 输入法要求确定（例如点了别处）时，未确定文字照原样写进文档
    func testUnmarkTextCommitsMarkedText() {
        load("", caret: EditorPosition(line: 0, column: 0))
        view.setMarkedText("zhong", selectedRange: NSRange(location: 5, length: 0), replacementRange: notFound)
        view.unmarkText()
        XCTAssertFalse(view.hasMarkedText())
        XCTAssertEqual(text, "zhong")
    }

    /// 把未确定文字删光（Backspace 到空）就是取消，文档不变
    func testEmptyMarkedTextCancels() {
        load("abc", caret: EditorPosition(line: 0, column: 1))
        view.setMarkedText("か", selectedRange: NSRange(location: 1, length: 0), replacementRange: notFound)
        view.setMarkedText("", selectedRange: NSRange(location: 0, length: 0), replacementRange: notFound)
        XCTAssertFalse(view.hasMarkedText())
        XCTAssertEqual(text, "abc")
    }

    /// 文节：输入法给的 NSMarkedClauseSegment 分开，正在转换的文节可以知道
    func testMarkedClauseSegments() {
        load("", caret: EditorPosition(line: 0, column: 0))
        let marked = NSMutableAttributedString(string: "今日は晴れ")
        marked.addAttribute(.markedClauseSegment, value: 0, range: NSRange(location: 0, length: 3))
        marked.addAttribute(.markedClauseSegment, value: 1, range: NSRange(location: 3, length: 2))
        view.setMarkedText(marked, selectedRange: NSRange(location: 3, length: 2), replacementRange: notFound)
        XCTAssertEqual(view.markedSegments(), [NSRange(location: 0, length: 3), NSRange(location: 3, length: 2)])
        XCTAssertEqual(view.selectedRange(), NSRange(location: 3, length: 2))
    }

    /// 重新转换：输入法把文档里已经确定的一段换回未确定文字
    func testReplacementRangeForReconversion() {
        load("私は東京へ", caret: EditorPosition(line: 0, column: 5))
        view.setMarkedText("とうきょう", selectedRange: NSRange(location: 0, length: 5), replacementRange: NSRange(location: 2, length: 2))
        XCTAssertEqual(text, "私はへ")
        XCTAssertEqual(view.markedRange(), NSRange(location: 2, length: 5))
        view.insertText("京都", replacementRange: notFound)
        XCTAssertEqual(text, "私は京都へ")
    }

    /// 确定时给了替换范围（中文输入法的联想、Mac 的文字替换等）
    func testInsertTextWithReplacementRange() {
        load("hello world", caret: EditorPosition(line: 0, column: 11))
        view.insertText("World", replacementRange: NSRange(location: 6, length: 5))
        XCTAssertEqual(text, "hello World")
        XCTAssertEqual(view.caret.column, 11)
    }

    // MARK: - 候选窗口的位置

    /// 输入法问未确定文字的位置：在窗口里，第一行的高度，越往后越靠右
    func testFirstRectFollowsMarkedText() {
        load("abc\nxyz", caret: EditorPosition(line: 0, column: 3))
        view.setMarkedText("にほんご", selectedRange: NSRange(location: 4, length: 0), replacementRange: notFound)
        var actual = NSRange()
        let first = view.firstRect(forCharacterRange: NSRange(location: 3, length: 1), actualRange: &actual)
        let third = view.firstRect(forCharacterRange: NSRange(location: 5, length: 1), actualRange: nil)
        XCTAssertEqual(actual, NSRange(location: 3, length: 1))
        XCTAssertGreaterThan(first.width, 0)
        XCTAssertEqual(first.height, view.lineHeight, accuracy: 0.5)
        XCTAssertGreaterThan(third.minX, first.maxX - 0.5)
        XCTAssertEqual(third.minY, first.minY, accuracy: 0.5)
        XCTAssertTrue(window.frame.contains(first), "\(first) 不在窗口 \(window.frame) 里")

        // 下一行在屏幕上更低（屏幕坐标 y 向上）
        let nextLine = view.firstRect(forCharacterRange: NSRange(location: 8, length: 1), actualRange: nil)
        XCTAssertLessThan(nextLine.minY, first.minY)
        XCTAssertEqual(nextLine.minX, view.firstRect(forCharacterRange: NSRange(location: 0, length: 1), actualRange: nil).minX, accuracy: 0.5)
    }

    /// 全角文字比半角宽（候选窗口不会对不上）
    func testFirstRectWidthOfFullwidthText() {
        load("", caret: EditorPosition(line: 0, column: 0))
        view.setMarkedText("aあ", selectedRange: NSRange(location: 2, length: 0), replacementRange: notFound)
        let half = view.firstRect(forCharacterRange: NSRange(location: 0, length: 1), actualRange: nil)
        let full = view.firstRect(forCharacterRange: NSRange(location: 1, length: 1), actualRange: nil)
        XCTAssertGreaterThan(full.width, half.width * 1.5)
    }

    /// 范围跨行时只回答第一行的部分（actualRange 告诉输入法实际的范围）
    func testFirstRectStopsAtLineEnd() {
        load("ab\ncd", caret: EditorPosition(line: 0, column: 0))
        var actual = NSRange()
        _ = view.firstRect(forCharacterRange: NSRange(location: 0, length: 5), actualRange: &actual)
        XCTAssertEqual(actual, NSRange(location: 0, length: 2))
    }

    /// 屏幕上的点 → 文字的下标，与 firstRect 对得上
    func testCharacterIndexForPoint() {
        load("abcdef\nghi", caret: EditorPosition(line: 0, column: 0))
        for index in [0, 2, 5, 8] {
            let rect = view.firstRect(forCharacterRange: NSRange(location: index, length: 1), actualRange: nil)
            XCTAssertEqual(view.characterIndex(for: NSPoint(x: rect.minX + 1, y: rect.midY)), index)
        }
    }

    // MARK: - 键盘命令

    func testCommands() {
        load("a🌸", caret: EditorPosition(line: 0, column: 3))
        view.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
        XCTAssertEqual(text, "a", "补充平面字符一次删除")
        view.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        XCTAssertEqual(view.caret.line, 1)
        XCTAssertEqual(view.caret.column, 0)
        view.insertText("b", replacementRange: notFound)
        let eol = EditorCore.text(ofEol: view.document.newLineEol)
        XCTAssertFalse(eol.isEmpty)
        XCTAssertEqual(text, "a" + eol + "b", "换行用文档的输入换行符")
        view.doCommand(by: #selector(NSResponder.moveUp(_:)))
        XCTAssertEqual(view.caret.line, 0)
        view.doCommand(by: #selector(NSResponder.moveToEndOfLine(_:)))
        XCTAssertEqual(view.caret.column, 1)
        view.doCommand(by: #selector(NSResponder.deleteForward(_:)))
        XCTAssertEqual(text, "ab")
        view.undo(nil)
        XCTAssertEqual(text, "a" + eol + "b")
    }
}

// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge
import XCTest

/// 排版和按排版显示的测试（计划第 27 步）。
///
/// 换行位置本身（禁则、TAB 等）在核心库的测试里按原版的规则确认（macos/core/tests/test-mac-layout.cpp）。
/// 这里确认 Mac 上的部分：
/// - 用 Core Text 测的文字宽度：等宽字体的半角一格、汉字两格（与原版的规则相同）
/// - 桥接层的排版接口
/// - 视图按排版行显示：折り返した行里的上下移动、行末（End）、点击、「右端で折り返す」随窗口宽度变化
final class EditorLayoutTests: XCTestCase {
    private var window: NSWindow!
    private var scrollView: NSScrollView!
    private var view: EditorTextView!
    private var document: EditorDocument { view.document }

    override func setUpWithError() throws {
        _ = TestCore.home
        _ = NSApplication.shared
        let document = try XCTUnwrap(EditorDocument())
        window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 600, height: 400),
                          styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        view = EditorTextView(document: document)
        scrollView.documentView = view
        window.contentView = scrollView
        window.makeFirstResponder(view)
        view.contentDidChange()
    }

    override func tearDown() {
        window.close()
        window = nil
        scrollView = nil
        view = nil
    }

    private func load(_ text: String, wrapColumns: Int = 10) {
        XCTAssertEqual(document.insert(text, at: EditorPosition(line: 0, column: 0)), .success)
        XCTAssertTrue(document.setWrap(.settingWidth, columns: wrapColumns) || document.viewSettings.wrapColumns == wrapColumns)
        view.setCaret(EditorPosition(line: 0, column: 0))
    }

    /// 排版行的文字
    private func rows() -> [String] {
        (0..<document.layoutLineCount).map { i in
            let l = document.layoutLine(at: i)
            return (document.line(at: l.start.line) as NSString).substring(with: NSRange(location: l.start.column, length: l.length))
        }
    }

    // MARK: - Core Text 的文字宽度

    /// 等宽字体（Menlo）：半角一格，汉字（由 Core Text 换成别的字体）两格
    func testCoreTextWidthsFollowOriginalRule() {
        let width = document.charWidth
        XCTAssertGreaterThanOrEqual(width, 7)
        XCTAssertLessThanOrEqual(width, 9)
        XCTAssertEqual(document.insert("aあ\tb", at: EditorPosition(line: 0, column: 0)), .success)
        _ = document.setWrap(.none, columns: 0)
        let xs = document.charPositions(ofLayoutLine: 0).map(\.intValue)
        // a | あ | TAB（到第 4 桁）| b
        XCTAssertEqual(xs, [0, width, 3 * width, 4 * width, 5 * width])
    }

    // MARK: - 桥接层

    func testBridgeLayoutLines() {
        load("0123456789ABCDEFGHIJKL\nxyz\n")
        XCTAssertEqual(rows(), ["0123456789", "ABCDEFGHIJ", "KL", "xyz"])
        XCTAssertEqual(document.layoutLine(at: 1).start.column, 10)
        XCTAssertEqual(document.layoutLine(at: 1).eol, .none)
        XCTAssertEqual(document.layoutLine(at: 2).eol, .lf)
        let p = document.layoutPosition(of: EditorPosition(line: 0, column: 12))
        XCTAssertEqual(p.line, 1)
        XCTAssertEqual(p.x, 2 * document.charWidth)
        let back = document.logicPosition(of: p)
        XCTAssertEqual(back.line, 0)
        XCTAssertEqual(back.column, 12)
        XCTAssertEqual(document.viewSettings.wrapMethod, .settingWidth)
        XCTAssertEqual(document.layoutWidth, 10 * document.charWidth)

        // 编辑后排版跟着变
        XCTAssertEqual(document.replace(EditorRange(from: EditorPosition(line: 0, column: 0), to: EditorPosition(line: 0, column: 10)), with: ""), .success)
        XCTAssertEqual(rows(), ["ABCDEFGHIJ", "KL", "xyz"])
        // 正好 10 桁的行：换行符到下一行（与原版相同）
        XCTAssertEqual(document.replace(EditorRange(from: EditorPosition(line: 0, column: 0), to: EditorPosition(line: 0, column: 2)), with: ""), .success)
        XCTAssertEqual(rows(), ["CDEFGHIJKL", "", "xyz"])
    }

    // MARK: - 视图

    func testViewShowsLayoutLines() {
        load("0123456789ABCDEFGHIJKL\nxyz\n")
        // 4 个排版行 + 最后的空行（[EOF] 的行）
        XCTAssertEqual(view.displayLineCount, 5)
    }

    /// 上下移动按排版行：折り返した行里也一行一行地移动
    func testMoveDownWithinWrappedLine() {
        load("0123456789ABCDEFGHIJKL\nxyz\n")
        view.setCaret(EditorPosition(line: 0, column: 3))
        let firstY = view.caretRect.minY
        view.doCommand(by: #selector(NSResponder.moveDown(_:)))
        XCTAssertEqual(view.caret.line, 0)
        XCTAssertEqual(view.caret.column, 13)
        XCTAssertEqual(view.caretRect.minY, firstY + view.lineHeight, accuracy: 0.5)
        view.doCommand(by: #selector(NSResponder.moveDown(_:)))
        XCTAssertEqual(view.caret.column, 22, "短的行到行末")
        view.doCommand(by: #selector(NSResponder.moveDown(_:)))
        XCTAssertEqual(view.caret.line, 1)
        XCTAssertEqual(view.caret.column, 3, "横向位置保持在第一行的第 3 桁")
    }

    /// 行末（End）：折り返した行里是这一行的末尾。光标留在同一行（不跳到下一行的开头）
    func testEndOfWrappedLineStaysOnSameRow() {
        load("0123456789ABCDEFGHIJKL\n")
        view.setCaret(EditorPosition(line: 0, column: 3))
        let y = view.caretRect.minY
        view.doCommand(by: #selector(NSResponder.moveToEndOfLine(_:)))
        XCTAssertEqual(view.caret.column, 10)
        XCTAssertEqual(view.caretRect.minY, y, accuracy: 0.5)
        // 行首：这一行的开头
        view.doCommand(by: #selector(NSResponder.moveToBeginningOfLine(_:)))
        XCTAssertEqual(view.caret.column, 0)
        // 在第 2 个排版行按行首
        view.doCommand(by: #selector(NSResponder.moveDown(_:)))
        view.doCommand(by: #selector(NSResponder.moveToBeginningOfLine(_:)))
        XCTAssertEqual(view.caret.column, 10)
        XCTAssertEqual(view.caretRect.minY, y + view.lineHeight, accuracy: 0.5)
    }

    /// 点击：排版行和字符的位置
    func testClickPositions() {
        load("0123456789ABCDEFGHIJKL\n")
        let w = CGFloat(document.charWidth)
        let rect = view.caretRect   // 第 0 行、第 0 字
        // 第 2 个排版行（"ABCDEFGHIJ"）的第 3 个字的左半
        let p = view.position(at: NSPoint(x: rect.minX + 3 * w + 1, y: rect.midY + view.lineHeight))
        XCTAssertEqual(p.line, 0)
        XCTAssertEqual(p.column, 13)
    }

    /// 输入法的候选窗口位置：折り返した行在下一行
    func testFirstRectOnWrappedLine() {
        load("0123456789ABCDEFGHIJKL\n")
        let first = view.firstRect(forCharacterRange: NSRange(location: 0, length: 1), actualRange: nil)
        let wrapped = view.firstRect(forCharacterRange: NSRange(location: 10, length: 1), actualRange: nil)
        XCTAssertEqual(wrapped.minX, first.minX, accuracy: 0.5)
        XCTAssertLessThan(wrapped.minY, first.minY)
        // 跨越折り返し的范围只回答第一行的部分
        var actual = NSRange()
        _ = view.firstRect(forCharacterRange: NSRange(location: 8, length: 4), actualRange: &actual)
        XCTAssertEqual(actual, NSRange(location: 8, length: 2))
    }

    /// 設定 > 折り返し方法
    func testWrapMethodMenu() {
        load("0123456789ABCDEFGHIJKL\n")
        view.wrapNone(nil)
        XCTAssertEqual(document.viewSettings.wrapMethod, .none)
        XCTAssertEqual(rows(), ["0123456789ABCDEFGHIJKL"])
        let item = NSMenuItem(title: "", action: #selector(EditorTextView.wrapNone(_:)), keyEquivalent: "")
        XCTAssertTrue(view.validateMenuItem(item))
        XCTAssertEqual(item.state, .on)

        // 指定桁で折り返す：类型别设置的桁数
        view.wrapSettingWidth(nil)
        XCTAssertEqual(document.viewSettings.wrapMethod, .settingWidth)
        XCTAssertEqual(document.viewSettings.wrapColumns, document.viewSettings.typeWrapColumns)
        XCTAssertEqual(item.state, .on)
        XCTAssertTrue(view.validateMenuItem(item))
        XCTAssertEqual(item.state, .off)
    }

    /// 右端で折り返す：窗口宽度变了，折り返し桁数跟着变
    func testWindowWidthWrapFollowsWindowSize() {
        load(String(repeating: "x", count: 200) + "\n")
        view.wrapWindowWidth(nil)
        let wide = document.viewSettings.wrapColumns
        XCTAssertEqual(document.viewSettings.wrapMethod, .windowWidth)
        XCTAssertGreaterThan(wide, 40)
        XCTAssertLessThanOrEqual(CGFloat(wide * document.charWidth), scrollView.contentSize.width)
        window.setContentSize(NSSize(width: 300, height: 400))
        let narrow = document.viewSettings.wrapColumns
        XCTAssertLessThan(narrow, wide)
        XCTAssertEqual(rows().first?.count, narrow)
    }
}

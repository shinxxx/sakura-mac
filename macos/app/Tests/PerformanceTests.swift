// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge
import XCTest

/// 大文件、超长行的性能（计划第 36 步）。
///
/// 文件与核心库的测试（test-mac-perf.cpp）、Windows 版的比较（macos/tools/perf）相同：
/// - large.txt：20 万行、约 17 MB
/// - long.txt：一行 200 万字
/// 确认 App 这边的操作（打开、画、跳到末尾、滚动、查找、输入法的一轮、打字）不随文件大小变慢。
/// 时间的上限按 Debug 构建、CI 的机器定得宽；以前每次输入法的调用都做整个文档的文字（O(N)），会超过上限。
/// 每个时间输出成「[PERF] 名字: N ms」。
final class PerformanceTests: XCTestCase {
    private static let largeLines = 200_000
    private static let longChars = 2_000_000

    private var dir: URL!
    private var window: NSWindow!
    private var view: EditorTextView!

    override func setUpWithError() throws {
        _ = TestCore.home
        _ = NSApplication.shared
        dir = TestCore.home.appendingPathComponent("perf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        window?.close()
        window = nil
        view = nil
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - 准备

    /// large.txt（与 make_perf_files.py 逐字节相同）
    private func makeLargeFile() throws -> URL {
        var data = Data()
        data.reserveCapacity(18_000_000)
        for i in 0..<Self.largeLines {
            let number = String(i)
            let line = String(repeating: "0", count: max(0, 7 - number.count)) + number
                + ": The quick brown fox ジャンプ over the lazy dog\tint x = \(i); // comment\r\n"
            data.append(contentsOf: Array(line.utf8))
        }
        data.append(contentsOf: Array("needle at the end\r\n".utf8))
        let url = dir.appendingPathComponent("large.txt")
        try data.write(to: url)
        return url
    }

    /// long.txt（与 make_perf_files.py 逐字节相同）
    private func makeLongFile() throws -> URL {
        let chunk = Array("abcdefghi ".utf8)
        var data = Data()
        data.reserveCapacity(Self.longChars + 6)
        for _ in 0..<(Self.longChars / chunk.count) { data.append(contentsOf: chunk) }
        data.append(contentsOf: Array("needle".utf8))
        let url = dir.appendingPathComponent("long.txt")
        try data.write(to: url)
        return url
    }

    /// 时间（毫秒）。超过上限时失败
    @discardableResult
    private func measure<T>(_ name: String, limit: Double, file: StaticString = #filePath, line: UInt = #line,
                            _ body: () throws -> T) rethrows -> T {
        let start = DispatchTime.now().uptimeNanoseconds
        let result = try body()
        let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        print(String(format: "[PERF] %@: %.0f ms (limit %.0f ms)", name, ms, limit))
        XCTAssertLessThan(ms, limit, "\(name) 太慢", file: file, line: line)
        return result
    }

    /// 打开文件，放进窗口（与 SakuraDocument 的窗口相同：滚动视图里的 EditorTextView）
    private func open(_ url: URL, name: String) throws {
        let document = try XCTUnwrap(EditorDocument())
        measure("\(name) 打开", limit: 15_000) {
            XCTAssertEqual(document.open(path: url.path), .success)
        }
        window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 800, height: 600),
                          styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        view = EditorTextView(document: document)
        scrollView.documentView = view
        window.contentView = scrollView
        window.makeFirstResponder(view)
        measure("\(name) 视图的准备", limit: 2_000) {
            view.contentDidChange()
        }
    }

    /// 画看得见的部分
    private func draw(_ name: String, limit: Double = 1_000, file: StaticString = #filePath, line: UInt = #line) throws {
        let rect = view.visibleRect
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: rect))
        measure("\(name)", limit: limit, file: file, line: line) {
            view.cacheDisplay(in: rect, to: rep)
        }
    }

    private func run(_ code: Int, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(CommandTable.perform(code, from: view), "功能 \(code) 已移植", file: file, line: line)
    }

    /// 输入法的一轮：未确定文字 → 问选择、文字、位置 → 确定（与输入法打一个词时的调用相同）
    private func imeRound(_ word: String) {
        let none = NSRange(location: NSNotFound, length: 0)
        var actual = NSRange()
        for i in 1...word.count {
            let marked = String(word.prefix(i))
            view.setMarkedText(marked, selectedRange: NSRange(location: marked.utf16.count, length: 0), replacementRange: none)
            let selected = view.selectedRange()
            let markedRange = view.markedRange()
            XCTAssertEqual(markedRange.length, marked.utf16.count)
            _ = view.attributedSubstring(forProposedRange: markedRange, actualRange: &actual)
            _ = view.attributedSubstring(forProposedRange: NSRange(location: max(0, selected.location - 10), length: 10),
                                         actualRange: &actual)
            _ = view.firstRect(forCharacterRange: selected, actualRange: &actual)
            _ = view.characterIndex(for: NSPoint(x: 300, y: 300))
        }
        view.insertText(word, replacementRange: none)
    }

    // MARK: - 大文件

    func testLargeFile() throws {
        let url = try makeLargeFile()
        try open(url, name: "大文件")
        let document = view.document
        XCTAssertEqual(document.lineCount, Self.largeLines + 1)
        try draw("大文件 画开头")

        // 跳到末尾、画
        measure("大文件 ファイルの最後に移動", limit: 1_000) { run(30351) }
        XCTAssertEqual(view.caret.line, Self.largeLines + 1, "最后的换行后面（[EOF] 的行）")
        try draw("大文件 画末尾")

        // 滚动：一页一页往上 100 次（每次画）
        measure("大文件 １ページアップ×100（画）", limit: 10_000) {
            for _ in 0..<100 {
                run(30342)
                if let rep = view.bitmapImageRepForCachingDisplay(in: view.visibleRect) {
                    view.cacheDisplay(in: view.visibleRect, to: rep)
                }
            }
        }

        // 查找：从开头找末尾的一行
        var range = EditorRange()
        let found = measure("大文件 查找（到末尾）", limit: 3_000) {
            document.find("needle", from: EditorPosition(line: 0, column: 0), backward: false, options: [], range: &range)
        }
        XCTAssertTrue(found)
        XCTAssertEqual(range.from.line, Self.largeLines)

        // 末尾的输入法、打字：与文件大小无关
        run(30351)
        measure("大文件 末尾的输入法一轮", limit: 1_000) { imeRound("にほんご") }
        measure("大文件 末尾打字×20", limit: 2_000) {
            for _ in 0..<20 { view.insertText("a", replacementRange: NSRange(location: NSNotFound, length: 0)) }
        }
        XCTAssertEqual(document.text(in: EditorRange(from: EditorPosition(line: Self.largeLines + 1, column: 0),
                                                     to: document.endPosition)),
                       "にほんご" + String(repeating: "a", count: 20))
        try draw("大文件 打字后画")

        // 开头的输入法也一样（位置换算不复制整个文档）
        run(30350)
        measure("大文件 开头的输入法一轮", limit: 1_000) { imeRound("にほんご") }
        XCTAssertEqual(document.textLength, document.offset(of: document.endPosition))
    }

    // MARK: - 超长行

    func testLongLine() throws {
        let url = try makeLongFile()
        try open(url, name: "超长行")
        let document = view.document
        XCTAssertEqual(document.lineCount, 1)
        try draw("超长行 画开头")

        measure("超长行 ファイルの最後に移動", limit: 1_000) { run(30351) }
        try draw("超长行 画末尾")

        // 一个逻辑行的折り返し行很多：一页一页往上（每次画）
        measure("超长行 １ページアップ×50（画）", limit: 10_000) {
            for _ in 0..<50 {
                run(30342)
                if let rep = view.bitmapImageRepForCachingDisplay(in: view.visibleRect) {
                    view.cacheDisplay(in: view.visibleRect, to: rep)
                }
            }
        }

        var range = EditorRange()
        let found = measure("超长行 查找（行末）", limit: 3_000) {
            document.find("needle", from: EditorPosition(line: 0, column: 0), backward: false, options: [], range: &range)
        }
        XCTAssertTrue(found)
        XCTAssertEqual(range.from.column, Self.longChars)

        run(30351)
        measure("超长行 行末的输入法一轮", limit: 2_000) { imeRound("にほんご") }
        measure("超长行 行末打字×20", limit: 4_000) {
            for _ in 0..<20 { view.insertText("a", replacementRange: NSRange(location: NSNotFound, length: 0)) }
        }
        XCTAssertEqual(document.textLength, Self.longChars + 6 + 4 + 20)
        try draw("超长行 打字后画", limit: 2_000)
    }
}

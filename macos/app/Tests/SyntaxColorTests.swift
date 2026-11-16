// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge
import XCTest

/// 语法颜色（计划第 33 步）的测试。
///
/// 色分け本身（注释、字符串、关键字等的判断）在核心库里（macos/core/tests/test-mac-syntax-color.cpp 测试），
/// 这里确认画面：每个字的颜色（検索文字列优先，其次是语法颜色）、编辑后重新取得、
/// 画出来的文字色和 URL 的下划线（把视图画到位图上取像素）。
final class SyntaxColorTests: XCTestCase {
    private var window: NSWindow!
    private var view: EditorTextView!
    private var document: EditorDocument { view.document }
    private var dir: URL!

    override func setUpWithError() throws {
        _ = TestCore.home
        _ = NSApplication.shared
        dir = TestCore.home.appendingPathComponent("syntax-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        window?.close()
        window = nil
        view = nil
        try? FileManager.default.removeItem(at: dir)
    }

    /// 文件名决定类型别设置（a.cpp 是 C/C++）
    private func open(_ name: String, _ text: String) throws {
        let url = dir.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        let document = try XCTUnwrap(EditorDocument())
        XCTAssertEqual(document.open(path: url.path), .success)
        window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 600, height: 400),
                          styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        view = EditorTextView(document: document)
        view.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        window.contentView = view
        window.makeFirstResponder(view)
        view.contentDidChange()
    }

    private func pos(_ line: Int, _ column: Int) -> EditorPosition { EditorPosition(line: line, column: column) }

    /// 一行每个字的颜色种类：「.」普通、「C」注释、「W」双引号、「S」单引号、「U」URL、「N」数字、「1」強調キーワード1、「F」検索文字列
    private func paint(row: Int) -> String {
        let colors = view.charColors(row: row)
        let length = view.lineText(row).length
        let table: [(EditorColorIndex, Character)] = [
            (.comment, "C"), (.doubleQuote, "W"), (.singleQuote, "S"), (.url, "U"), (.digit, "N"),
            (.keyword1, "1"), (.search, "F"),
        ]
        return String((0..<length).map { i -> Character in
            guard i < colors.count, let info = colors[i] else { return "." }
            for (index, ch) in table where same(view.color(index), info) { return ch }
            return "?"
        })
    }

    private func same(_ a: EditorColorSetting, _ b: EditorColorSetting) -> Bool {
        a.display == b.display && a.bold == b.bold && a.underline == b.underline && a.text == b.text && a.back == b.back
    }

    // MARK: - 每个字的颜色

    func testCharColorsFollowTypeSettings() throws {
        try open("a.cpp", "int x = 10; // c\n\"s\" 'c' http://example.com/\n")
        XCTAssertEqual(document.typeIndex, 2, "C/C++")
        XCTAssertEqual(paint(row: 0), "111.....NN..CCCC")
        XCTAssertEqual(paint(row: 1), "WWW.SSS.UUUUUUUUUUUUUUUUUUU")
        // 颜色的设置：原版的默认值
        XCTAssertEqual(view.color(.comment).text, 0x008000)
        XCTAssertTrue(view.color(.url).underline)
        XCTAssertEqual(view.color(.keyword1).text, 0x0000FF)
    }

    func testTextTypeHasNoStringColors() throws {
        try open("a.txt", "\"s\" 'c' 10 // x\n")
        XCTAssertEqual(paint(row: 0), "...............", "テキスト：引号、数字、注释都不着色")
    }

    func testEditingUpdatesFollowingLines() throws {
        try open("a.cpp", "x\ny */ z\n")
        XCTAssertEqual(paint(row: 1), "......")
        view.setCaret(pos(0, 0))
        view.insertText("/*", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(paint(row: 0), "CCC")
        XCTAssertEqual(paint(row: 1), "CCCC..", "下一行到 */ 为止也是注释")
        view.undo(nil)
        XCTAssertEqual(paint(row: 1), "......")
    }

    func testSearchMarkOverSyntaxColor() throws {
        // 検索文字列的颜色比语法颜色优先（原版 SColorStrategyInfo::DoChangeColor）
        try open("a.cpp", "int abc; // abc\n")
        view.setSelection(from: pos(0, 4), to: pos(0, 7))
        view.toggleSearchMark(nil)
        view.setCaret(pos(0, 0))
        XCTAssertEqual(paint(row: 0), "111.FFF..CCCFFF")
    }

    // MARK: - 画出来的颜色

    func testRenderedSyntaxColors() throws {
        defer {
            EditorTextView.resetFont()
            NotificationCenter.default.post(name: EditorTextView.fontDidChangeNotification, object: nil)
        }
        // 大的字体：笔画有完全覆盖的像素，能取到设置的颜色本身
        EditorTextView.setFont(try XCTUnwrap(NSFont(name: "Menlo", size: 28)))
        try open("a.cpp", "int lll; // lll\nhttp://a.b/-\nx\n")
        let image = try render(caretAt: pos(3, 0))	// 光标放在最后的空行（カーソル行アンダーライン是蓝色，不在测试的行上）

        XCTAssertTrue(image.cell(view: view, line: 0, column: 1).contains(0x0000FF), "強調キーワード1（int）：蓝")
        XCTAssertTrue(image.cell(view: view, line: 0, column: 4).contains(0x000000), "普通文字：黑")
        XCTAssertFalse(image.cell(view: view, line: 0, column: 4).contains(0x008000))
        XCTAssertTrue(image.cell(view: view, line: 0, column: 13).contains(0x008000), "注释：绿")
        XCTAssertFalse(image.cell(view: view, line: 0, column: 13).contains(0x000000))
        // URL：蓝色的下划线。「-」的格子里，基线以下只有下划线
        let dash = image.cell(view: view, line: 1, column: 11)
        XCTAssertTrue(dash.lowerHalfContains(0x0000FF), "URL 的下划线")
        let plain = image.cell(view: view, line: 2, column: 0)
        XCTAssertFalse(plain.lowerHalfContains(0x0000FF), "普通文字没有下划线")
    }

    // MARK: - 辅助

    /// 把视图画到 sRGB 的位图上
    private func render(caretAt caret: EditorPosition) throws -> Bitmap {
        view.setCaret(caret)
        let width = Int(view.bounds.width), height = Int(view.bounds.height)
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        view.displayIgnoringOpacity(view.bounds, in: NSGraphicsContext(cgContext: context, flipped: false))
        let data = try XCTUnwrap(context.data)
        let bytes = data.assumingMemoryBound(to: UInt8.self)
        var pixels = [UInt32](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let o = y * context.bytesPerRow + x * 4
                pixels[y * width + x] = (UInt32(bytes[o]) << 16) | (UInt32(bytes[o + 1]) << 8) | UInt32(bytes[o + 2])
            }
        }
        return Bitmap(width: width, height: height, pixels: pixels)
    }

    struct Bitmap {
        let width: Int
        let height: Int
        let pixels: [UInt32]

        /// 一个字的格子（位图的第 0 行是图的上端，与翻转的视图的 y 相同）
        func cell(view: EditorTextView, line: Int, column: Int) -> Cell {
            view.setCaret(EditorPosition(line: line, column: column))
            let left = view.caretRect
            view.setCaret(EditorPosition(line: line, column: column + 1))
            let right = view.caretRect
            let rect = NSRect(x: left.minX, y: left.minY, width: right.minX - left.minX, height: left.height)
            return Cell(bitmap: self, rect: rect)
        }
    }

    struct Cell {
        let bitmap: Bitmap
        let rect: NSRect

        private func contains(_ rgb: UInt32, rows: ClosedRange<Int>) -> Bool {
            let x0 = max(0, Int(rect.minX)), x1 = min(bitmap.width - 1, Int(rect.maxX) - 1)
            guard x0 <= x1 else { return false }
            for y in rows where y >= 0 && y < bitmap.height {
                for x in x0...x1 where Self.near(bitmap.pixels[y * bitmap.width + x], rgb) {
                    return true
                }
            }
            return false
        }

        /// 格子里有接近这个颜色的像素（各通道差 24 以内）
        func contains(_ rgb: UInt32) -> Bool {
            contains(rgb, rows: Int(rect.minY)...Int(rect.maxY) - 1)
        }

        /// 格子的下半部分（基线附近以下）有这个颜色
        func lowerHalfContains(_ rgb: UInt32) -> Bool {
            contains(rgb, rows: Int(rect.midY + rect.height / 4)...Int(rect.maxY) - 1)
        }

        static func near(_ a: UInt32, _ b: UInt32) -> Bool {
            [16, 8, 0].allSatisfy { (shift: UInt32) in abs(Int((a >> shift) & 0xFF) - Int((b >> shift) & 0xFF)) <= 24 }
        }
    }
}

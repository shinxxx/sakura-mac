// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge
import XCTest

/// 绘制、颜色、选择、字体的测试（计划第 28 步）。
///
/// - 颜色用类型别设置的值（原版的默认值：米色的背景、蓝色的行号等），与系统的深色模式无关
/// - 选择范围的颜色按原版的规则混合（文字色和背景色相同时 30% 半透明）
/// - 选择：Shift+方向键、拖动、Shift+点击、すべて選択、Option+拖动的矩形选择；有选择时输入替换选择范围
/// - 字体：改变后重新排版
final class EditorDrawingTests: XCTestCase {
    private var window: NSWindow!
    private var view: EditorTextView!
    private var document: EditorDocument { view.document }
    private let notFound = NSRange(location: NSNotFound, length: 0)

    override func setUpWithError() throws {
        _ = TestCore.home
        _ = NSApplication.shared
        let document = try XCTUnwrap(EditorDocument())
        window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 600, height: 400),
                          styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
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
        view = nil
    }

    private func load(_ text: String) {
        XCTAssertEqual(document.insert(text, at: EditorPosition(line: 0, column: 0)), .success)
        view.setCaret(EditorPosition(line: 0, column: 0))
    }

    private var text: String { document.text }

    // MARK: - 颜色

    /// 默认颜色与原版相同，深色模式下编辑区也不变（shin 选择的方案：照原版用设置里的颜色）
    func testDefaultColorsFromTypeSettings() {
        XCTAssertEqual(view.color(.text).back, 0xFFFBF0)
        XCTAssertEqual(view.color(.text).text, 0x000000)
        XCTAssertEqual(view.color(.lineNumber).text, 0x0000FF)
        XCTAssertTrue(view.color(.caretLineUnderline).display.boolValue)
        XCTAssertEqual(view.caretColor, 0x000000, "输入法关闭时是「キャレット」的颜色")
        let background = view.enclosingScrollView?.backgroundColor.usingColorSpace(.sRGB)
        XCTAssertEqual(background?.redComponent ?? 0, 1.0, accuracy: 0.01)
        XCTAssertEqual(background?.blueComponent ?? 0, 240.0 / 255, accuracy: 0.01)

        for name in [NSAppearance.Name.aqua, .darkAqua] {
            view.appearance = NSAppearance(named: name)
            assertColor(pixel(at: NSPoint(x: 300, y: 200)), 0xFFFBF0, "\(name.rawValue)：编辑区是设置的背景色")
        }
    }

    /// 选择范围的颜色：原版 GetTextColorByColorInfo2 / GetBackColorByColorInfo2（30% 混合）
    func testSelectionColorMixing() {
        let select = view.color(.select)
        XCTAssertEqual(select.text, select.back)
        XCTAssertEqual(view.overlayTextColor(select, on: 0x000000), 0x0E1F3A)
        XCTAssertEqual(view.overlayBackColor(select, on: 0xFFFBF0), 0xC1CFE3)
        // 文字色和背景色不同时，原样用
        var custom = select
        custom.text = 0xFFFFFF
        XCTAssertEqual(view.overlayTextColor(custom, on: 0x000000), 0xFFFFFF)
        XCTAssertEqual(view.overlayBackColor(custom, on: 0xFFFBF0), 0x316AC5)
    }

    /// 画出来的颜色：文字区域、行号区域、选择范围
    func testRenderedColors() {
        load("abcdef\nxyz\n")
        let w = CGFloat(document.charWidth)
        let caret = view.caretRect
        let y = caret.midY + view.lineHeight   // 第 2 行（光标不在这一行，没有アンダーライン）
        assertColor(pixel(at: NSPoint(x: caret.minX + 20 * w, y: y)), 0xFFFBF0, "文字区域：米色")
        assertColor(pixel(at: NSPoint(x: 2, y: y)), 0xEFEFEF, "行号区域：灰色")

        view.selectAll(nil)
        assertColor(pixel(at: NSPoint(x: caret.minX + w * 0.5, y: caret.minY + 1)), 0xC1CFE3, "选择范围的背景")
        assertColor(pixel(at: NSPoint(x: caret.minX + 20 * w, y: caret.minY + 1)), 0xFFFBF0, "行末之后不涂")
    }

    /// 改过的行：行号用「変更行」的设置（粗体）
    func testModifiedLines() {
        XCTAssertFalse(document.isLineModified(0))
        view.insertText("abc", replacementRange: notFound)
        XCTAssertTrue(document.isLineModified(0))
        XCTAssertTrue(view.color(.lineNumberModified).bold.boolValue)
        view.undo(nil)
        XCTAssertFalse(document.isLineModified(0))
    }

    // MARK: - 选择

    func testShiftArrowSelection() {
        load("abcdef\nxyz\n")
        view.doCommand(by: #selector(NSResponder.moveRightAndModifySelection(_:)))
        view.doCommand(by: #selector(NSResponder.moveRightAndModifySelection(_:)))
        view.doCommand(by: #selector(NSResponder.moveRightAndModifySelection(_:)))
        XCTAssertEqual(view.selection?.from.column, 0)
        XCTAssertEqual(view.selection?.to.column, 3)
        XCTAssertEqual(view.selectedRange(), NSRange(location: 0, length: 3), "输入法看到的选择范围")
        view.doCommand(by: #selector(NSResponder.moveDownAndModifySelection(_:)))
        XCTAssertEqual(view.selection?.to.line, 1)
        view.doCommand(by: #selector(NSResponder.moveUpAndModifySelection(_:)))
        view.doCommand(by: #selector(NSResponder.moveLeftAndModifySelection(_:)))
        XCTAssertEqual(view.selection?.to.column, 2)
        // 不按 Shift 移动：取消选择（与原版相同）
        view.doCommand(by: #selector(NSResponder.moveRight(_:)))
        XCTAssertNil(view.selection)
        XCTAssertEqual(view.caret.column, 3)
    }

    /// 有选择时输入、删除：替换选择范围
    func testTypingReplacesSelection() {
        load("abcdef\n")
        view.setCaret(EditorPosition(line: 0, column: 1))
        view.doCommand(by: #selector(NSResponder.moveToEndOfLineAndModifySelection(_:)))
        XCTAssertEqual(view.selection?.to.column, 6)
        view.insertText("X", replacementRange: notFound)
        XCTAssertEqual(document.line(at: 0), "aX")
        XCTAssertNil(view.selection)

        view.doCommand(by: #selector(NSResponder.moveToBeginningOfLineAndModifySelection(_:)))
        view.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
        XCTAssertEqual(document.line(at: 0), "")

        // 输入法开始输入时也先删掉选择范围
        view.insertText("hello", replacementRange: notFound)
        view.doCommand(by: #selector(NSResponder.moveToBeginningOfLineAndModifySelection(_:)))
        view.setMarkedText("か", selectedRange: NSRange(location: 1, length: 0), replacementRange: notFound)
        XCTAssertEqual(document.line(at: 0), "")
        view.unmarkText()
        XCTAssertEqual(document.line(at: 0), "か")
    }

    func testSelectAllAndCancel() {
        load("ab\ncd\n")
        view.selectAll(nil)
        XCTAssertEqual(view.selection?.from.line, 0)
        XCTAssertEqual(view.selection?.to.line, 2)
        let item = NSMenuItem(title: "", action: #selector(EditorTextView.selectAll(_:)), keyEquivalent: "a")
        XCTAssertTrue(view.validateMenuItem(item))
        view.cancelOperation(nil)
        XCTAssertNil(view.selection)
    }

    /// 鼠标：拖动选择、Shift+点击扩展、Option+拖动是矩形选择
    func testMouseSelection() {
        load("0123456789\nabcdefghij\nABCDEFGHIJ\n")
        let w = CGFloat(document.charWidth)
        let origin = view.caretRect
        func point(row: Int, column: Int) -> NSPoint {
            NSPoint(x: origin.minX + CGFloat(column) * w + 1, y: origin.midY + CGFloat(row) * view.lineHeight)
        }

        mouse(.leftMouseDown, at: point(row: 0, column: 2))
        mouse(.leftMouseDragged, at: point(row: 1, column: 4))
        mouse(.leftMouseUp, at: point(row: 1, column: 4))
        XCTAssertEqual(view.selection?.from.column, 2)
        XCTAssertEqual(view.selection?.to.line, 1)
        XCTAssertEqual(view.selection?.to.column, 4)

        mouse(.leftMouseDown, at: point(row: 2, column: 1), flags: .shift)
        XCTAssertEqual(view.selection?.from.column, 2, "起点不变")
        XCTAssertEqual(view.selection?.to.line, 2)

        mouse(.leftMouseDown, at: point(row: 0, column: 2), flags: .option)
        mouse(.leftMouseDragged, at: point(row: 2, column: 5), flags: .option)
        XCTAssertNil(view.selection)
        let box = view.boxSelection
        XCTAssertEqual(box?.top, 0)
        XCTAssertEqual(box?.bottom, 2)
        XCTAssertEqual(box?.left ?? -1, 2 * w, accuracy: 0.5)
        XCTAssertEqual(box?.right ?? -1, 5 * w, accuracy: 0.5)
        XCTAssertTrue(view.hasSelection)
        // 矩形选择的背景（第 2 行的第 3 字）
        let y = point(row: 1, column: 3)
        assertColor(pixel(at: NSPoint(x: y.x + w * 0.5 - 1, y: y.y - view.lineHeight / 2 + 1)), 0xC1CFE3)

        // 普通点击取消
        mouse(.leftMouseDown, at: point(row: 0, column: 0))
        XCTAssertFalse(view.hasSelection)
    }

    // MARK: - 字体

    func testChangeFontRelayouts() throws {
        defer {
            EditorTextView.resetFont()
            NotificationCenter.default.post(name: EditorTextView.fontDidChangeNotification, object: nil)
        }
        load("abc\n")
        let before = document.charWidth
        let font = try XCTUnwrap(NSFont(name: "Menlo", size: 20))
        EditorTextView.setFont(font)
        XCTAssertEqual(EditorTextView.fontSize, 20)
        XCTAssertEqual(view.font.pointSize, 20)
        XCTAssertGreaterThan(document.charWidth, before)
        XCTAssertGreaterThan(view.lineHeight, 20)
    }

    // MARK: - 辅助

    private func mouse(_ type: NSEvent.EventType, at point: NSPoint, flags: NSEvent.ModifierFlags = []) {
        let location = view.convert(point, to: nil)
        guard let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: flags, timestamp: 0,
                                             windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                                             clickCount: 1, pressure: 1) else {
            XCTFail("事件")
            return
        }
        switch type {
        case .leftMouseDown: view.mouseDown(with: event)
        case .leftMouseDragged: view.mouseDragged(with: event)
        default: view.mouseUp(with: event)
        }
    }

    /// 颜色相同（颜色空间的换算可能差 1、2）
    private func assertColor(_ actual: UInt32, _ expected: UInt32, _ message: String = "",
                             file: StaticString = #filePath, line: UInt = #line) {
        for shift: UInt32 in [16, 8, 0] {
            let a = Int((actual >> shift) & 0xFF), e = Int((expected >> shift) & 0xFF)
            if abs(a - e) > 3 {
                XCTFail(String(format: "%06X != %06X %@", actual, expected, message), file: file, line: line)
                return
            }
        }
    }

    /// 视图上一点画出来的颜色（0xRRGGBB，sRGB）
    private func pixel(at point: NSPoint) -> UInt32 {
        view.needsDisplay = true
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return 0xDEAD }
        view.cacheDisplay(in: view.bounds, to: rep)
        let scale = CGFloat(rep.pixelsWide) / view.bounds.width
        // NSBitmapImageRep 的 y 从上往下（视图是翻转的，坐标一致）
        guard let color = rep.colorAt(x: Int(point.x * scale), y: Int(point.y * scale))?.usingColorSpace(.sRGB) else {
            return 0xDEAD
        }
        func channel(_ v: CGFloat) -> UInt32 { UInt32((v * 255).rounded()) }
        return (channel(color.redComponent) << 16) | (channel(color.greenComponent) << 8) | channel(color.blueComponent)
    }
}

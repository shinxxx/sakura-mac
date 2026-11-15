// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import XCTest

/// 自动界面测试：真的启动 App，用键盘和菜单操作，确认已经完成的步骤的主要功能。
///
/// 每一步的细节由单元测试（Tests/、macos/core/tests）确认，这里只走一遍用户实际的操作，
/// 代替每一步都在 Mac 上手动确认。测试失败时把当时的画面截图附在结果里（macos/tools/run-tests.sh 会取出来）。
///
/// App 用 `-SakuraUITesting YES` 启动（Sources/UITesting.swift）：设置文件放在临时目录、用测试专用的剪贴板、
/// 编辑区只用英文输入，不碰用户自己的设置和剪贴板。
final class SakuraMacUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // 不恢复上次的窗口：每次从一个无题窗口开始
        app.launchArguments = ["-SakuraUITesting", "YES", "-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "启动后有编辑窗口")
        editor.click()
    }

    override func tearDown() {
        if let run = testRun, !run.hasSucceeded {
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = "失败时的画面"
            shot.lifetime = .keepAlways
            add(shot)
        }
        app.terminate()
        app = nil
    }

    private var editor: XCUIElement { app.textViews["editor"] }
    private var text: String { editor.value as? String ?? "" }

    /// 文字里的换行统一成 \n 再比较（无题文档的输入换行符按类型别设置，默认是 CRLF）
    private var normalizedText: String {
        text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }

    private func key(_ key: String, _ flags: XCUIElement.KeyModifierFlags = []) {
        editor.typeKey(key, modifierFlags: flags)
    }

    // MARK: - 第 9、26 步：启动、窗口

    func testLaunchOpensUntitledWindow() {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.exists)
        XCTAssertTrue(window.title.contains("(無題)"), "无题窗口的标题：\(window.title)")
        XCTAssertEqual(text, "")
    }

    // MARK: - 第 25、29 步：输入、改行、撤销

    func testTypingNewlineAutoIndentAndUndo() {
        editor.typeText("\tabc\n")
        XCTAssertEqual(normalizedText, "\tabc\n\t", "Enter 接着上一行的缩进（オートインデント）")
        editor.typeText("x")
        XCTAssertEqual(normalizedText, "\tabc\n\tx")
        key("z", .command)
        XCTAssertEqual(normalizedText, "\tabc\n\t", "Cmd+Z 撤销")
        key("z", [.command, .shift])
        XCTAssertEqual(normalizedText, "\tabc\n\tx", "Shift+Cmd+Z 重做")
        let window = app.windows.firstMatch
        XCTAssertTrue(window.title.contains("(更新)"), "修改后标题有「(更新)」：\(window.title)")
    }

    func testDeleteKeys() {
        editor.typeText("abcd")
        key(XCUIKeyboardKey.delete.rawValue)
        XCTAssertEqual(text, "abc", "Delete（⌫）删除光标前的字")
        key(XCUIKeyboardKey.leftArrow.rawValue)
        key(XCUIKeyboardKey.leftArrow.rawValue)
        key(XCUIKeyboardKey.forwardDelete.rawValue)
        XCTAssertEqual(text, "ac", "fn+Delete 删除光标处的字")
    }

    // MARK: - 第 28、29 步：选择、剪贴板

    func testSelectAllCopyAndPaste() {
        editor.typeText("one\ntwo")
        key("a", .command)
        key("c", .command)
        key(XCUIKeyboardKey.rightArrow.rawValue)
        key("v", .command)
        XCTAssertEqual(normalizedText, "one\ntwoone\ntwo")
        key("a", .command)
        key("x", .command)
        XCTAssertEqual(text, "", "Cmd+X 剪切全部")
        key("v", .command)
        XCTAssertEqual(normalizedText, "one\ntwoone\ntwo")
    }

    /// 没有选择时 Cmd+C 复制一行，贴在光标所在行的上面
    func testLineCopyWithoutSelection() {
        editor.typeText("a\nb")
        key(XCUIKeyboardKey.upArrow.rawValue)
        key("c", .command)
        key("v", .command)
        XCTAssertEqual(normalizedText, "a\na\nb")
    }

    func testShiftArrowSelectionIsReplacedByTyping() {
        editor.typeText("hello")
        key(XCUIKeyboardKey.leftArrow.rawValue, .shift)
        key(XCUIKeyboardKey.leftArrow.rawValue, .shift)
        editor.typeText("p!")
        XCTAssertEqual(text, "help!")
    }

    /// 选中几行按 TAB 每行缩进，Shift+TAB 取消
    func testTabIndentsSelectedLines() {
        editor.typeText("a\nb\n")
        key("a", .command)
        key(XCUIKeyboardKey.tab.rawValue)
        XCTAssertEqual(normalizedText, "\ta\n\tb\n")
        key(XCUIKeyboardKey.tab.rawValue, .shift)
        XCTAssertEqual(normalizedText, "a\nb\n")
    }

    // MARK: - 菜单

    /// 「編集」菜单有第 29 步加的项目，并且能从菜单执行
    func testEditMenu() {
        editor.typeText("xyz")
        let menu = app.menuBars.menuBarItems["編集"]
        menu.click()
        for title in ["元に戻す", "やり直し", "切り取り", "コピー", "貼り付け", "削除", "すべて選択", "矩形貼り付け", "カーソル前を削除"] {
            XCTAssertTrue(menu.menuItems[title].exists, "「編集」>「\(title)」")
        }
        menu.menuItems["すべて選択"].click()
        menu.click()
        menu.menuItems["削除"].click()
        XCTAssertEqual(text, "", "菜单的「削除」删除选择范围")
    }

    /// 「設定」>「折り返し方法」能从菜单选择（打勾的状态 XCUITest 读不出来，由单元测试确认）
    func testWrapMenu() {
        editor.typeText("abc")
        let menu = app.menuBars.menuBarItems["設定"]
        menu.click()
        let wrap = menu.menuItems["折り返し方法"]
        wrap.hover()
        for title in ["折り返さない", "指定桁で折り返す", "右端で折り返す"] {
            XCTAssertTrue(wrap.menuItems[title].waitForExistence(timeout: 3), "「折り返し方法」>「\(title)」")
        }
        wrap.menuItems["折り返さない"].click()
        XCTAssertEqual(text, "abc", "选择后文字不变")
    }
}

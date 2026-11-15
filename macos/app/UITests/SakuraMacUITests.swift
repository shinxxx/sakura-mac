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

    // MARK: - 第 31 步：重启后从「最近使ったファイル」打开

    /// 完成标志：重启 App 后最近文件仍能直接打开，光标回到上次的位置。
    /// 两次启动用同一个设置文件夹（-SakuraUITestingHome），结束时写出 sakura.ini
    func testReopenFromRecentFilesAfterRestart() {
        app.terminate()
        let home = "restart-\(UUID().uuidString)"
        let name = "recent-sample.txt"
        let base = ["-SakuraUITesting", "YES", "-ApplePersistenceIgnoreState", "YES", "-SakuraUITestingHome", home]
        let byTitle = NSPredicate(format: "title CONTAINS %@", name)

        // 1 回目：测试用的文件打开，光标移到第 3 行，Cmd+Q 结束
        let first = XCUIApplication()
        first.launchArguments = base + ["-SakuraUITestingOpenFile", name]
        first.launch()
        let firstWindow = first.windows.matching(byTitle).firstMatch
        XCTAssertTrue(firstWindow.waitForExistence(timeout: 10), "测试用的文件打开了")
        XCTAssertEqual(firstWindow.textViews["editor"].value as? String, "line1\nline2\nline3\nline4\n")
        first.typeKey(XCUIKeyboardKey.downArrow.rawValue, modifierFlags: [])
        first.typeKey(XCUIKeyboardKey.downArrow.rawValue, modifierFlags: [])
        first.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(first.wait(for: .notRunning, timeout: 10), "Cmd+Q 结束了")

        // 2 回目：ファイル > 最近使ったファイル 里有这个文件，选它打开
        app = XCUIApplication()
        app.launchArguments = base
        app.launch()
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "无题窗口")
        let fileMenu = app.menuBars.menuBarItems["ファイル"]
        fileMenu.click()
        let recent = fileMenu.menuItems["最近使ったファイル"]
        XCTAssertTrue(recent.waitForExistence(timeout: 3), "「ファイル」>「最近使ったファイル」")
        recent.hover()
        let item = recent.menuItems.matching(byTitle).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 3), "历史里有上次的文件")
        XCTAssertTrue(fileMenu.menuItems["最近使ったフォルダー"].exists, "「ファイル」>「最近使ったフォルダー」")
        item.click()

        let window = app.windows.matching(byTitle).firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10), "从历史打开了")
        // 光标在上次的位置（第 3 行的开头）：输入的字在 line3 前面
        app.typeText("X")
        XCTAssertEqual(window.textViews["editor"].value as? String, "line1\nline2\nXline3\nline4\n")
    }

    // MARK: - 第 31 步：沙盒外的文件，重启后从「最近使ったファイル」打开（只在自己的 Mac 上）

    /// 沙盒外的文件用「開く」对话框选了打开，退出再启动后从「最近使ったファイル」还能打开（安全书签有效）。
    ///
    /// 只在 macos/tools/run-tests.sh 里运行：要操作系统的文件对话框，GitHub 的机器上不稳定。
    /// 为界面测试编译的 App 被 Xcode 加了「整个磁盘可以读」的沙盒例外，测不出限制，
    /// 所以用 run-tests.sh 去掉例外重新签名的那一份（SAKURA_SANDBOX_APP 是它的位置）。
    /// 文件放在 ~/SakuraMacUITest（不放「文稿」：测试程序访问「文稿」时系统会弹出权限确认）
    func testSandboxedFileReopensFromRecentFilesAfterRestart() throws {
        guard let appPath = ProcessInfo.processInfo.environment["SAKURA_SANDBOX_APP"] else {
            throw XCTSkip("只在 macos/tools/run-tests.sh 里运行")
        }
        app.terminate()
        let appURL = URL(fileURLWithPath: appPath)

        // 沙盒外的文件（App 的容器以外）
        let realHome = URL(fileURLWithPath: NSHomeDirectoryForUser(NSUserName()) ?? NSHomeDirectory())
        let dir = realHome.appendingPathComponent("SakuraMacUITest")
        let name = "sandbox-\(UUID().uuidString.prefix(8)).txt"
        let file = dir.appendingPathComponent(name)
        let content = "outside\nsandbox\n"
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try content.write(to: file, atomically: true, encoding: .utf8)
        } catch {
            throw XCTSkip("测试程序写不了 \(dir.path)：\(error)")
        }
        defer { try? FileManager.default.removeItem(at: file) }

        let home = "sandbox-\(UUID().uuidString)"
        let base = ["-SakuraUITesting", "YES", "-ApplePersistenceIgnoreState", "YES", "-SakuraUITestingHome", home]
        let byTitle = NSPredicate(format: "title CONTAINS %@", name)

        // 1. App 在沙盒里：不经过对话框直接打开，应该被拒绝
        let check = XCUIApplication(url: appURL)
        check.launchArguments = base + ["-SakuraUITestingOpenPath", file.path]
        check.launch()
        let opened = check.windows.matching(byTitle).firstMatch.waitForExistence(timeout: 5)
        XCTAssertFalse(opened, "App 没有在沙盒里运行：不经过对话框也打开了沙盒外的文件（这个测试就没有意义了）")
        check.terminate()
        if opened { return }

        // 2. 用「開く」对话框选这个文件打开（Cmd+Shift+G 输入路径）
        let first = XCUIApplication(url: appURL)
        first.launchArguments = base
        first.launch()
        XCTAssertTrue(first.textViews["editor"].waitForExistence(timeout: 10), "无题窗口")
        first.typeKey("o", modifierFlags: .command)
        let panel = openPanel(of: first)
        XCTAssertTrue(panel.waitForExistence(timeout: 10), "出现了「開く」对话框")
        panel.typeKey("g", modifierFlags: [.command, .shift])
        sleep(1)
        panel.typeText(file.path + "\n")
        sleep(1)
        panel.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])
        let firstWindow = first.windows.matching(byTitle).firstMatch
        XCTAssertTrue(firstWindow.waitForExistence(timeout: 10), "从对话框打开了沙盒外的文件")
        XCTAssertEqual(firstWindow.textViews["editor"].value as? String, content)
        first.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(first.wait(for: .notRunning, timeout: 10), "Cmd+Q 结束了")

        // 3. 重启后从「最近使ったファイル」打开：用书签取回权限，能读
        app = XCUIApplication(url: appURL)
        app.launchArguments = base
        app.launch()
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "无题窗口")
        let fileMenu = app.menuBars.menuBarItems["ファイル"]
        fileMenu.click()
        let recent = fileMenu.menuItems["最近使ったファイル"]
        XCTAssertTrue(recent.waitForExistence(timeout: 3))
        recent.hover()
        let item = recent.menuItems.matching(byTitle).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 3), "历史里有这个文件")
        item.click()
        let window = app.windows.matching(byTitle).firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10), "重启后从历史打开了沙盒外的文件")
        XCTAssertEqual(window.textViews["editor"].value as? String, content)
    }

    /// 「開く」对话框。沙盒里的 App 的对话框由系统的另一个进程显示，在两边都找
    private func openPanel(of app: XCUIApplication) -> XCUIElement {
        let service = XCUIApplication(bundleIdentifier: "com.apple.appkit.xpc.openAndSavePanelService")
        for _ in 0..<20 {
            for candidate in [app.dialogs.firstMatch, app.sheets.firstMatch, service.windows.firstMatch] where candidate.exists {
                return candidate
            }
            usleep(500_000)
        }
        return app.dialogs.firstMatch
    }
}

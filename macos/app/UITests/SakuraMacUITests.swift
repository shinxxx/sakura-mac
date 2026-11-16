// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import Carbon
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
        // 第 34 步起「選択」子菜单里也有「すべて選択」（与原版相同）：点「編集」直接下面的那个
        menu.menus.firstMatch.children(matching: .menuItem)["すべて選択"].click()
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

    // MARK: - 第 32 步：検索・置換・指定行へジャンプ

    /// 「検索」菜单有第 32 步的项目
    func testSearchMenu() {
        let menu = app.menuBars.menuBarItems["検索"]
        menu.click()
        for title in ["検索...", "次を検索", "前を検索", "置換...", "検索マークの切替え", "検索開始位置へ戻る", "指定行へジャンプ..."] {
            XCTAssertTrue(menu.menuItems[title].exists, "「検索」>「\(title)」")
        }
        key(XCUIKeyboardKey.escape.rawValue)
    }

    /// 组合框的文字换成 text
    private func setComboText(_ combo: XCUIElement, _ text: String) {
        combo.click()
        combo.typeKey("a", modifierFlags: .command)
        combo.typeText(text)
    }

    /// 关掉还开着的对话框（「検索ダイアログを自動的に閉じる」关着时）
    private func closePanel(_ title: String, cancel: String) {
        let panel = app.windows[title]
        if panel.exists { panel.buttons[cancel].click() }
    }

    /// 消息框的 OK
    private func dismissMessage(containing part: String, file: StaticString = #filePath, line: UInt = #line) {
        let message = app.staticTexts.matching(NSPredicate(format: "value CONTAINS %@", part)).firstMatch
        XCTAssertTrue(message.waitForExistence(timeout: 5), "显示了消息「\(part)」", file: file, line: line)
        app.buttons["OK"].firstMatch.click()
    }

    /// 完成标志：検索ダイアログで下検索、次を検索（⌘G）、指定行へジャンプ（⌘J，第 34 步起与原版的 Ctrl+J 相同）
    func testFindNextAndJump() {
        editor.typeText("apple banana apple\nline2\nline3")
        key(XCUIKeyboardKey.upArrow.rawValue, .command)	// 文档的开头
        key("f", .command)
        let combo = app.comboBoxes["findText"]
        XCTAssertTrue(combo.waitForExistence(timeout: 5), "検索ダイアログが開いた")
        XCTAssertEqual(combo.value as? String, "apple", "カーソル位置の単語が検索文字列")
        app.buttons["findNext"].click()
        closePanel("検索", cancel: "findCancel")
        app.typeText("X")
        XCTAssertEqual(normalizedText, "X banana apple\nline2\nline3", "見つかった文字列が選択されている")

        key("g", .command)	// 次を検索
        app.typeText("Y")
        XCTAssertEqual(normalizedText, "X banana Y\nline2\nline3", "次を検索")

        key("j", .command)	// 指定行へジャンプ
        let line = app.textFields["jumpLine"]
        XCTAssertTrue(line.waitForExistence(timeout: 5), "指定行へジャンプが開いた")
        line.typeText("3\r")
        let closed = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: line)
        wait(for: [closed], timeout: 5)	// ジャンプで閉じる
        app.typeText("Z")
        XCTAssertEqual(normalizedText, "X banana Y\nline2\nZline3", "3 行目の先頭へジャンプ")
    }

    /// 見つからないときにメッセージを表示
    func testFindNotFoundMessage() {
        editor.typeText("abc")
        key("f", .command)
        let combo = app.comboBoxes["findText"]
        XCTAssertTrue(combo.waitForExistence(timeout: 5))
        setComboText(combo, "zzz")
        app.buttons["findNext"].click()
        dismissMessage(containing: "zzz")
        closePanel("検索", cancel: "findCancel")
        XCTAssertEqual(text, "abc")
    }

    /// 完成标志：置換ダイアログですべて置換
    func testReplaceAll() {
        editor.typeText("cat dog cat")
        key(XCUIKeyboardKey.upArrow.rawValue, .command)
        key("r", .command)	// 置換（第 34 步起与原版的 Ctrl+R 相同）
        let combo = app.comboBoxes["replaceText"]
        XCTAssertTrue(combo.waitForExistence(timeout: 5), "置換ダイアログが開いた")
        XCTAssertEqual(combo.value as? String, "cat")
        setComboText(app.comboBoxes["replaceText2"], "cow")
        app.buttons["replaceAll"].click()
        dismissMessage(containing: "2箇所を置換しました。")
        closePanel("置換", cancel: "replaceCancel")
        XCTAssertEqual(text, "cow dog cow")
        key("z", .command)
        XCTAssertEqual(text, "cat dog cat", "すべて置換は 1 回で元に戻る")
    }

    // MARK: - 第 34 步：菜单与快捷键

    /// 菜单栏按原版的 MainMenu.ini：顶层菜单的顺序、子菜单、还没有移植的功能变灰
    func testMenuBarFollowsOriginal() {
        let bar = app.menuBars.firstMatch
        for title in ["ファイル", "編集", "変換", "検索", "ツール", "設定", "ウィンドウ", "ヘルプ"] {
            XCTAssertTrue(bar.menuBarItems[title].exists, "菜单栏「\(title)」")
        }
        let search = bar.menuBarItems["検索"]
        search.click()
        XCTAssertTrue(search.menuItems["次を検索"].isEnabled, "已移植的功能可以用")
        XCTAssertTrue(search.menuItems["Grep..."].exists, "原版的「Grep...」")
        XCTAssertFalse(search.menuItems["Grep..."].isEnabled, "还没有移植的功能变灰")
        let incremental = search.menuItems["インクリメンタルサーチ"]
        incremental.hover()
        XCTAssertTrue(incremental.menuItems["前方インクリメンタルサーチ"].waitForExistence(timeout: 3), "子菜单也与原版相同")
        key(XCUIKeyboardKey.escape.rawValue)
        key(XCUIKeyboardKey.escape.rawValue)
    }

    /// 原版的快捷键：F8 コピー、F9 貼り付け、Esc 取消选择（⌘J、⌘R 在 testFindNextAndJump、testReplaceAll）
    func testOriginalShortcuts() {
        editor.typeText("abc")
        key("a", .command)
        key(XCUIKeyboardKey.F8.rawValue)			// コピー
        key(XCUIKeyboardKey.escape.rawValue)		// 取消选择（光标留在末尾）
        key(XCUIKeyboardKey.F9.rawValue)			// 貼り付け
        XCTAssertEqual(text, "abcabc", "F8 コピー → Esc → F9 貼り付け")
    }

    /// 第 34 步（第 2 个 PR）：⌥→ 単語の右端に移動、F6 範囲選択開始（锁定后方向键扩展选择）
    func testWordMoveAndSelectionLock() {
        editor.typeText("abc def")
        key(XCUIKeyboardKey.leftArrow.rawValue, .command)	// 行頭
        key(XCUIKeyboardKey.rightArrow.rawValue, .option)	// 単語の右端に移動
        editor.typeText("X")
        XCTAssertEqual(text, "abc Xdef")
        key(XCUIKeyboardKey.F6.rawValue)					// 範囲選択開始
        key(XCUIKeyboardKey.rightArrow.rawValue)
        key(XCUIKeyboardKey.rightArrow.rawValue)
        editor.typeText("Y")
        XCTAssertEqual(text, "abc XYf", "F6 之后方向键选择，输入替换选择范围")
    }

    /// 設定 >「Windows のキー割り当てを使う」：⌃ 是 Ctrl（⌃A すべて選択）。再选一次回到 Mac 方案
    func testWindowsKeyScheme() {
        editor.typeText("abc")
        let settings = app.menuBars.menuBarItems["設定"]
        settings.click()
        settings.menuItems["Windows のキー割り当てを使う"].click()
        key("a", .control)						// Windows 方案：Ctrl+A すべて選択
        editor.typeText("X")
        XCTAssertEqual(text, "X", "⌃A すべて選択")

        settings.click()
        settings.menuItems["Windows のキー割り当てを使う"].click()
        editor.typeText("yz")
        key("a", .control)						// Mac 方案：⌃ 组合交给 macOS（⌃A 是「段落の先頭へ」），不是すべて選択
        editor.typeText("_")
        XCTAssertEqual(text, "_Xyz", "回到 Mac 方案后 ⌃A 移到行头（第 34 步起 macOS 的移动也走原版的論理行頭に移動），不是すべて選択")
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
    /// 文件放在测试程序的容器里（测试程序也在沙盒里，写不了别处；不放「文稿」：会弹出权限确认）
    func testSandboxedFileReopensFromRecentFilesAfterRestart() throws {
        guard let appPath = ProcessInfo.processInfo.environment["SAKURA_SANDBOX_APP"] else {
            throw XCTSkip("只在 macos/tools/run-tests.sh 里运行")
        }
        app.terminate()
        let appURL = URL(fileURLWithPath: appPath)

        // 沙盒外的文件（App 的容器以外）。测试程序本身也在沙盒里，文件放在测试程序的容器里
        // （~/Library/Containers/…uitests.xctrunner/Data/SakuraMacUITest）：对 App 来说是别的 App 的地方，同样不能直接读。
        // 以前失败时留下的文件先删掉
        let dir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("SakuraMacUITest")
        try? FileManager.default.removeItem(at: dir)
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
        // 对话框的输入框不像编辑区那样限制成英文输入：日文、中文输入法打开时路径会变成未确定文字。
        // 输入路径的这段时间换成英文键盘，之后换回原来的
        let savedInputSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
        if let ascii = TISCopyCurrentASCIICapableKeyboardInputSource()?.takeRetainedValue() {
            TISSelectInputSource(ascii)
        }
        defer { if let savedInputSource { TISSelectInputSource(savedInputSource) } }
        panel.typeKey("g", modifierFlags: [.command, .shift])
        sleep(1)
        panel.typeText(file.path + "\n")
        sleep(1)
        // 文件选中后按「開く」（Return 键有时不起作用：按钮直接点）
        let openButton = first.buttons.matching(NSPredicate(format: "title IN %@ OR label IN %@", ["開く", "Open"], ["開く", "Open"])).firstMatch
        if openButton.waitForExistence(timeout: 5) {
            openButton.click()
        } else {
            panel.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])
        }
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

    // MARK: - 第 33 步：语法高亮

    /// 实际的 App 画出语法颜色：无题文档（「基本」）里的 URL 用蓝色、带下划线显示（原版的默认设置）。
    /// 辅助功能读不到颜色，所以截取编辑区的画面数蓝色的像素
    func testSyntaxColorDrawsUrl() {
        // 行号和カーソル行アンダーライン也是蓝色。每加一行，多一个蓝色的行号（EOF 的空行没有行号），
        // 所以比较「加一行普通文字」和「加一行 URL」各自增加的蓝色像素
        editor.typeText("plain text here\n")
        let start = bluePixels(editor.screenshot().image)
        editor.typeText("plain text more\n")
        let plain = bluePixels(editor.screenshot().image)
        editor.typeText("http://example.com/\n")
        let url = bluePixels(editor.screenshot().image)
        let plainAdded = plain - start, urlAdded = url - plain
        XCTAssertGreaterThan(urlAdded, plainAdded + 100,
                             "URL 用蓝色显示（普通文字的行增加 \(plainAdded)，URL 的行增加 \(urlAdded)）")
    }

    /// 画面里接近纯蓝（0x0000FF）的像素数。截图的颜色空间可能与 sRGB 稍有不同，范围放宽
    private func bluePixels(_ image: NSImage) -> Int {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        guard let data = context.data else { return 0 }
        let bytes = data.assumingMemoryBound(to: UInt8.self)
        var count = 0
        for y in 0..<cg.height {
            for x in 0..<cg.width {
                let o = y * context.bytesPerRow + x * 4
                if bytes[o] < 90 && bytes[o + 1] < 90 && bytes[o + 2] > 180 { count += 1 }
            }
        }
        return count
    }

    /// 「開く」对话框。沙盒里的 App 的对话框由系统的另一个进程（openAndSavePanelService）显示，
    /// 但辅助功能里算 App 的窗口。找不到时返回 App 本身（键盘输入照样进对话框）
    private func openPanel(of app: XCUIApplication) -> XCUIElement {
        for _ in 0..<20 {
            for candidate in [app.dialogs.firstMatch, app.sheets.firstMatch] where candidate.exists {
                return candidate
            }
            usleep(500_000)
        }
        return app
    }
}

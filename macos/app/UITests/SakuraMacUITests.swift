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

    /// ヘルプ > バージョン情報（第 34 步）：原版的内容的窗口，「OK」关闭
    func testAboutPanel() {
        let help = app.menuBars.menuBarItems["ヘルプ"]
        help.click()
        help.menuItems["バージョン情報"].click()
        // NSPanel 在 XCUITest 里不一定是 window，按里面的元素找
        let author = app.staticTexts["原作者: たけ(竹パンダ) さん"]
        XCTAssertTrue(author.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["copyInfo"].exists, "情報をコピー")
        app.buttons["aboutOK"].click()
        XCTAssertFalse(author.waitForExistence(timeout: 1))
    }

    // MARK: - 第 39 步：共通設定窗口

    /// ⌘,（App 菜单的「設定…」）打开共通設定：左边是原版的页，换页，改一项按 OK，再打开时是改过的值、上次的页
    func testCommonSettingsWindow() {
        key(",", .command)
        let window = app.windows["CommonSettings"]
        XCTAssertTrue(window.waitForExistence(timeout: 5), "共通設定窗口")
        XCTAssertTrue(window.staticTexts["CommonSettingsPage_バックアップ"].exists, "页的列表")

        window.staticTexts["CommonSettingsPage_タブバー"].click()
        XCTAssertTrue(window.checkBoxes["IDC_CHECK_DispTabWnd"].waitForExistence(timeout: 2), "タブバー 页")

        window.staticTexts["CommonSettingsPage_全般"].click()
        let freeCaret = window.checkBoxes["IDC_CHECK_FREECARET"]
        XCTAssertTrue(freeCaret.waitForExistence(timeout: 2))
        XCTAssertFalse(window.checkBoxes["IDC_CHECK_USETRAYICON"].isEnabled, "タスクトレイ は Mac 版では使えない")
        let before = freeCaret.value as? Int ?? -1
        freeCaret.click()
        window.buttons["CommonSettingsOK"].click()
        XCTAssertFalse(window.waitForExistence(timeout: 1), "OK で閉じる")

        key(",", .command)
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        XCTAssertTrue(freeCaret.waitForExistence(timeout: 2), "上次的页（全般）")
        XCTAssertEqual(freeCaret.value as? Int, before == 1 ? 0 : 1, "OK した値")

        // キャンセル は変えない
        freeCaret.click()
        window.buttons["CommonSettingsCancel"].click()
        key(",", .command)
        XCTAssertTrue(freeCaret.waitForExistence(timeout: 5))
        XCTAssertEqual(freeCaret.value as? Int, before == 1 ? 0 : 1, "キャンセル した値は残らない")
        window.buttons["CommonSettingsCancel"].click()
    }

    /// 共通設定 > ウィンドウ「位置と大きさの設定」（模态的对话框）、ファイル名表示 的置換リスト（第 39 步第 2 个 PR）
    func testCommonSettingsDialogAndList() {
        key(",", .command)
        let window = app.windows["CommonSettings"]
        XCTAssertTrue(window.waitForExistence(timeout: 5), "共通設定窗口")

        window.staticTexts["CommonSettingsPage_ウィンドウ"].click()
        let sizeButton = window.buttons["IDC_BUTTON_WINSIZE"]
        XCTAssertTrue(sizeButton.waitForExistence(timeout: 2))
        sizeButton.click()
        // 模态的面板在可访问性树里不一定是 windows（NSPanel 有时是 dialogs），按控件找
        let sizeSet = app.radioButtons["IDC_RADIO_WINSIZE_SET"]
        XCTAssertTrue(sizeSet.waitForExistence(timeout: 5), "ウィンドウの位置と大きさ")
        sizeSet.click()
        let width = app.textFields["IDC_EDIT_SX"]
        XCTAssertTrue(width.isEnabled, "直接指定 のとき 幅 を変えられる")
        app.radioButtons["IDC_RADIO_WINSIZE_DEF"].click()
        XCTAssertFalse(width.isEnabled)
        app.buttons["IDOK"].click()
        XCTAssertFalse(sizeSet.waitForExistence(timeout: 1), "閉じる で閉じる")

        window.staticTexts["CommonSettingsPage_ファイル名表示"].click()
        let table = window.tables["IDC_LIST_FNAME_table"]
        XCTAssertTrue(table.waitForExistence(timeout: 2), "置換リスト")
        let count = table.tableRows.count
        let from = window.textFields["IDC_EDIT_FNAME_FROM"]
        // 设置窗口的输入框不限制成英文输入：日文、中文输入法打开时路径会变成未确定文字。输入的这段时间换成英文键盘
        let savedInputSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
        if let ascii = TISCopyCurrentASCIICapableKeyboardInputSource()?.takeRetainedValue() {
            TISSelectInputSource(ascii)
        }
        defer { if let savedInputSource { TISSelectInputSource(savedInputSource) } }
        from.click()
        from.typeKey("a", modifierFlags: .command)
        from.typeText("/Volumes/UITest/")
        window.buttons["IDC_BUTTON_FNAME_ADD"].click()
        XCTAssertEqual(table.tableRows.count, count + 1, "追加")
        window.buttons["IDC_BUTTON_FNAME_DEL"].click()
        XCTAssertEqual(table.tableRows.count, count, "削除")
        window.buttons["CommonSettingsCancel"].click()
    }

    // MARK: - 第 40 步：タイプ別設定窗口

    /// 設定 > タイプ別設定：这个文档的类型（无题是「基本」）。スクリーン 的「SPACEの挿入」打开按 OK → TAB 键输入空白；
    /// 再打开时是改过的值，关掉按 OK → TAB 键输入 TAB。「基本」的名字不能改
    func testTypeSettingsWindow() {
        let window = app.windows["TypeSettings"]
        func openTypeSettings() {
            let settings = app.menuBars.menuBarItems["設定"]
            settings.click()
            let item = settings.menuItems.matching(NSPredicate(format: "title BEGINSWITH 'タイプ別設定' AND NOT (title CONTAINS '一覧')")).firstMatch
            XCTAssertTrue(item.waitForExistence(timeout: 3), "「設定」>「タイプ別設定」")
            item.click()
            XCTAssertTrue(window.waitForExistence(timeout: 5), "タイプ別設定窗口")
        }
        editor.click()
        openTypeSettings()
        XCTAssertTrue(window.staticTexts["TypeSettingsPage_キーワードヘルプ"].exists, "页的列表")
        window.staticTexts["TypeSettingsPage_スクリーン"].click()
        let insSpace = window.checkBoxes["IDC_CHECK_INS_SPACE"]
        XCTAssertTrue(insSpace.waitForExistence(timeout: 2), "スクリーン 页")
        XCTAssertEqual(window.textFields["IDC_EDIT_TYPENAME"].value as? String, "基本", "无题是「基本」")
        XCTAssertFalse(window.textFields["IDC_EDIT_TYPENAME"].isEnabled, "「基本」の名前は変えられない")
        XCTAssertEqual(insSpace.value as? Int, 0)
        insSpace.click()
        window.buttons["TypeSettingsOK"].click()
        XCTAssertFalse(window.waitForExistence(timeout: 1), "OK で閉じる")

        editor.click()
        key(XCUIKeyboardKey.tab.rawValue)
        XCTAssertFalse(text.isEmpty)
        XCTAssertFalse(text.contains("\t"), "SPACEの挿入：TAB 键输入空白")
        XCTAssertTrue(text.allSatisfy { $0 == " " }, "空白：\(text)")

        openTypeSettings()
        XCTAssertTrue(insSpace.waitForExistence(timeout: 2), "上次的页（スクリーン）")
        XCTAssertEqual(insSpace.value as? Int, 1, "OK した値")
        insSpace.click()
        window.buttons["TypeSettingsOK"].click()
        editor.click()
        key("a", .command)
        key(XCUIKeyboardKey.tab.rawValue)
        XCTAssertEqual(text, "\t", "SPACEの挿入 を外すと TAB")
        key("z", .command)
        key("z", .command)
    }

    /// タイプ別設定 > カラー（第 40 步第 2 个 PR）：色指定リストの「コメント」を選び「太字」を切り替えて OK → 再び開くと切り替わっている。
    /// 正規表現キーワード：キーワードを追加して OK → 再び開くと一覧にある
    func testTypeSettingsColorAndRegex() {
        let window = app.windows["TypeSettings"]
        func openTypeSettings() {
            let settings = app.menuBars.menuBarItems["設定"]
            settings.click()
            settings.menuItems.matching(NSPredicate(format: "title BEGINSWITH 'タイプ別設定' AND NOT (title CONTAINS '一覧')")).firstMatch.click()
            XCTAssertTrue(window.waitForExistence(timeout: 5), "タイプ別設定窗口")
        }
        editor.click()
        openTypeSettings()
        window.staticTexts["TypeSettingsPage_カラー"].click()
        let table = window.tables["IDC_LIST_COLORS_table"]
        XCTAssertTrue(table.waitForExistence(timeout: 2), "色指定リスト")
        let comment = table.staticTexts["コメント"]	// 太字にできる色（テキスト・ルーラー等はできない）
        XCTAssertTrue(comment.waitForExistence(timeout: 2))
        comment.click()
        let bold = window.checkBoxes["IDC_CHECK_BOLD"]
        XCTAssertTrue(bold.isEnabled, "コメントは太字にできる")
        let before = bold.value as? Int ?? -1
        bold.click()
        window.buttons["TypeSettingsOK"].click()
        XCTAssertFalse(window.waitForExistence(timeout: 1))

        openTypeSettings()
        XCTAssertTrue(table.waitForExistence(timeout: 2), "上次的页（カラー）")
        comment.click()
        XCTAssertEqual(bold.value as? Int, before == 1 ? 0 : 1, "OK した太字")
        bold.click()	// 元に戻す

        window.staticTexts["TypeSettingsPage_正規表現キーワード"].click()
        let regexTable = window.tables["IDC_LIST_REGEX_table"]
        XCTAssertTrue(regexTable.waitForExistence(timeout: 2))
        let count = regexTable.tableRows.count
        let savedInputSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
        if let ascii = TISCopyCurrentASCIICapableKeyboardInputSource()?.takeRetainedValue() {
            TISSelectInputSource(ascii)
        }
        defer { if let savedInputSource { TISSelectInputSource(savedInputSource) } }
        let field = window.textFields["IDC_EDIT_REGEX"]
        field.click()
        field.typeKey("a", modifierFlags: .command)
        field.typeText("/uitest[0-9]+/k")
        window.buttons["IDC_BUTTON_REGEX_ADD"].click()
        XCTAssertEqual(regexTable.tableRows.count, count + 1, "追加")
        window.buttons["TypeSettingsOK"].click()
        XCTAssertFalse(window.waitForExistence(timeout: 1))

        openTypeSettings()
        XCTAssertTrue(regexTable.waitForExistence(timeout: 2), "上次的页（正規表現キーワード）")
        XCTAssertEqual(regexTable.tableRows.count, count + 1, "OK した一覧")
        // 界面测试模式的设置不保存（UITesting.swift），戻さなくてよい
        window.buttons["TypeSettingsCancel"].click()
    }

    /// 設定 > タイプ別設定一覧（第 40 步第 3 个 PR）：一覧が出る。追加すると 1 行増え、削除（確認して OK）で戻る。
    /// 共通設定 > 強調キーワード：セット名とキーワードの一覧が出る
    func testTypeListAndKeywordPage() {
        editor.click()
        let settings = app.menuBars.menuBarItems["設定"]
        settings.click()
        let item = settings.menuItems.matching(NSPredicate(format: "title BEGINSWITH 'タイプ別設定一覧'")).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 3), "「設定」>「タイプ別設定一覧」")
        item.click()
        let table = app.tables["IDC_LIST_TYPES_table"]
        XCTAssertTrue(table.waitForExistence(timeout: 5), "タイプ別設定一覧")
        let count = table.tableRows.count
        XCTAssertGreaterThan(count, 10)
        XCTAssertTrue(table.staticTexts["基本"].exists)
        app.buttons["IDC_BUTTON_ADD_TYPE"].click()
        XCTAssertEqual(table.tableRows.count, count + 1, "追加")
        app.buttons["IDC_BUTTON_DEL_TYPE"].click()
        let ok = app.buttons["OK"].firstMatch	// 確認（NSAlert）
        XCTAssertTrue(ok.waitForExistence(timeout: 3), "削除の確認")
        ok.click()
        XCTAssertEqual(table.tableRows.count, count, "削除")
        app.buttons["IDCANCEL"].click()
        XCTAssertFalse(table.waitForExistence(timeout: 1), "キャンセルで閉じる")

        key(",", .command)
        let window = app.windows["CommonSettings"]
        XCTAssertTrue(window.waitForExistence(timeout: 5), "共通設定窗口")
        window.staticTexts["CommonSettingsPage_強調キーワード"].click()
        let combo = window.popUpButtons["IDC_COMBO_SET"]
        XCTAssertTrue(combo.waitForExistence(timeout: 2))
        XCTAssertTrue(combo.isEnabled, "強調キーワード のページが使える")
        XCTAssertGreaterThan(window.tables["IDC_LIST_KEYWORD_table"].tableRows.count, 0, "キーワードの一覧")
        window.buttons["CommonSettingsCancel"].click()
    }

    // MARK: - 第 41 步：共通設定 > キー割り当て・メインメニュー・ツールバー・カスタムメニュー

    /// 共通設定 > キー割り当て：種別「選択系」の「すべて選択」を F12 に割り当てて OK → 編集画面で F12 が すべて選択
    func testKeyBindPage() {
        key(",", .command)
        let window = app.windows["CommonSettings"]
        XCTAssertTrue(window.waitForExistence(timeout: 5), "共通設定窗口")
        window.staticTexts["CommonSettingsPage_キー割り当て"].click()
        let combo = window.popUpButtons["IDC_COMBO_FUNCKIND"]
        XCTAssertTrue(combo.waitForExistence(timeout: 2), "キー割り当て のページ")
        combo.click()
        app.menuItems["選択系"].click()
        window.tables["IDC_LIST_FUNC_table"].staticTexts["すべて選択"].click()
        window.tables["IDC_LIST_KEY_table"].staticTexts["F12"].click()
        let keysFunc = window.descendants(matching: .any)["IDC_EDIT_KEYSFUNC"].firstMatch	// 読み取り専用の欄は staticText になることがある
        XCTAssertNotEqual(keysFunc.value as? String, "すべて選択")
        window.buttons["IDC_BUTTON_ASSIGN"].click()
        XCTAssertEqual(keysFunc.value as? String, "すべて選択", "割当")
        XCTAssertTrue(window.tables["IDC_LIST_ASSIGNEDKEYS_table"].staticTexts["F12"].exists, "機能に割り当てられているキー")
        window.buttons["CommonSettingsOK"].click()
        XCTAssertFalse(window.waitForExistence(timeout: 1), "OK で閉じる")

        editor.click()
        editor.typeText("abc")
        editor.typeKey(.F12, modifierFlags: [])
        editor.typeText("x")
        XCTAssertEqual(text, "x", "F12 で すべて選択 して x に置き換わる")
    }

    /// 共通設定 > メインメニュー：「ファイル」を下位項目ごと削除して OK → 菜单栏に「ファイル」が無くなる
    func testMainMenuPage() {
        XCTAssertTrue(app.menuBars.menuBarItems["ファイル"].exists)
        key(",", .command)
        let window = app.windows["CommonSettings"]
        XCTAssertTrue(window.waitForExistence(timeout: 5), "共通設定窗口")
        window.staticTexts["CommonSettingsPage_メインメニュー"].click()
        let outline = window.outlines["IDC_TREE_RES_outline"]
        XCTAssertTrue(outline.waitForExistence(timeout: 2), "メインメニュー のページ")
        outline.staticTexts["ファイル(F)"].click()
        window.buttons["IDC_BUTTON_DELETE"].click()
        let ok = app.buttons["OK"].firstMatch	// 下位項目ごと削除の確認（NSAlert）
        XCTAssertTrue(ok.waitForExistence(timeout: 3), "削除の確認")
        ok.click()
        XCTAssertFalse(outline.staticTexts["ファイル(F)"].exists, "削除")
        window.buttons["CommonSettingsOK"].click()
        XCTAssertFalse(window.waitForExistence(timeout: 1), "OK で閉じる")
        XCTAssertFalse(app.menuBars.menuBarItems["ファイル"].waitForExistence(timeout: 1), "菜单栏を作り直した")
        XCTAssertTrue(app.menuBars.menuBarItems["編集"].exists)
    }

    /// 共通設定 > カスタムメニュー：メニュー名を設定して OK → 開き直してもその名前。ツールバー：アイコン付きの一覧、区切を追加して OK
    func testCustomMenuAndToolbarPages() {
        key(",", .command)
        let window = app.windows["CommonSettings"]
        XCTAssertTrue(window.waitForExistence(timeout: 5), "共通設定窗口")
        window.staticTexts["CommonSettingsPage_カスタムメニュー"].click()
        let menuCombo = window.popUpButtons["IDC_COMBO_MENU"]
        XCTAssertTrue(menuCombo.waitForExistence(timeout: 2), "カスタムメニュー のページ")
        menuCombo.click()
        app.menuItems["メニュー1"].click()
        let name = window.textFields["IDC_EDIT_MENUNAME"]
        // 日文・中文输入法打开时文字会变成未确定文字：输入的这段时间换成英文键盘
        let savedInputSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
        if let ascii = TISCopyCurrentASCIICapableKeyboardInputSource()?.takeRetainedValue() {
            TISSelectInputSource(ascii)
        }
        defer { if let savedInputSource { TISSelectInputSource(savedInputSource) } }
        name.click()
        name.typeKey("a", modifierFlags: .command)
        name.typeText("UITest")
        window.buttons["IDC_BUTTON_MENUNAME"].click()
        XCTAssertEqual(menuCombo.value as? String, "UITest", "メニュー名")

        window.staticTexts["CommonSettingsPage_ツールバー"].click()
        let toolbar = window.tables["IDC_LIST_RES_table"]
        XCTAssertTrue(toolbar.waitForExistence(timeout: 2), "ツールバー のページ")
        XCTAssertTrue(toolbar.images.firstMatch.exists, "アイコン")
        let count = toolbar.tableRows.count
        window.buttons["IDC_BUTTON_INSERTSEPARATOR"].click()
        XCTAssertEqual(toolbar.tableRows.count, count + 1, "区切")
        window.buttons["CommonSettingsOK"].click()
        XCTAssertFalse(window.waitForExistence(timeout: 1), "OK で閉じる")

        key(",", .command)
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        XCTAssertEqual(window.tables["IDC_LIST_RES_table"].tableRows.count, count + 1, "上次的页（ツールバー）、OK した値")
        window.staticTexts["CommonSettingsPage_カスタムメニュー"].click()
        menuCombo.click()
        XCTAssertTrue(app.menuItems["UITest"].exists, "OK したメニュー名")
        app.typeKey(.escape, modifierFlags: [])
        window.buttons["CommonSettingsCancel"].click()
    }

    // MARK: - 第 35 步：导入 Windows 版的设置

    /// 設定 >「Windows 版の設定をインポート…」→ 确认 →（窗口关闭）→ 重新启动后，导入的按键分配生效。
    /// 导入的 ini 是 F8 换成「すべて選択」的设置（默认的 F8 是コピー）。
    /// 文件对话框换成测试用的文件（-SakuraUITestingImportFile），重新启动由测试这边做
    func testImportWindowsSettings() {
        app.terminate()
        let home = "import-\(UUID().uuidString)"
        let base = ["-SakuraUITesting", "YES", "-ApplePersistenceIgnoreState", "YES", "-SakuraUITestingHome", home]

        // 1 回目：导入前 F8 是コピー（不改变文字）
        let first = XCUIApplication()
        first.launchArguments = base + ["-SakuraUITestingImportFile", "windows-sakura.ini"]
        first.launch()
        let firstEditor = first.textViews["editor"]
        XCTAssertTrue(firstEditor.waitForExistence(timeout: 10))
        firstEditor.click()
        firstEditor.typeKey(XCUIKeyboardKey.F8.rawValue, modifierFlags: [])
        firstEditor.typeText("X")
        XCTAssertEqual(firstEditor.value as? String, "X", "导入前 F8 不是すべて選択")
        firstEditor.typeKey("z", modifierFlags: .command)		// 撤销，窗口关闭时不问保存

        let settings = first.menuBars.menuBarItems["設定"]
        settings.click()
        let item = settings.menuItems["Windows 版の設定をインポート…"]
        XCTAssertTrue(item.waitForExistence(timeout: 3), "「設定」>「Windows 版の設定をインポート…」")
        XCTAssertTrue(item.isEnabled)
        item.click()
        let ok = first.buttons["インポートして再起動"].firstMatch	// NSAlert 的按钮在可访问性树里有两个（对话框和窗口）
        XCTAssertTrue(ok.waitForExistence(timeout: 5), "导入前的确认")
        ok.click()
        XCTAssertTrue(first.wait(for: .notRunning, timeout: 10), "窗口关闭、导入以后结束（重新启动）")

        // 2 回目：导入的设置生效：F8 是すべて選択
        app = XCUIApplication()
        app.launchArguments = base
        app.launch()
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.click()
        editor.typeText("abc")
        key(XCUIKeyboardKey.F8.rawValue)
        editor.typeText("X")
        XCTAssertEqual(text, "X", "导入后 F8 是すべて選択（Windows 版的设置）")
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
        // 子菜单的项目的点击が菜单の閉じる動きと重なって効かないことがある（XCUITest）：もう一度菜单から選ぶ
        if !window.waitForExistence(timeout: 5) {
            app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
            fileMenu.click()
            recent.hover()
            XCTAssertTrue(item.waitForExistence(timeout: 3))
            item.click()
        }
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

    /// 第 42 步：沙盒の外のルールファイル（タイプ別設定の「参照」で選ぶ）は、再起動後もアウトライン解析で読める（設定ファイルの書签）
    func testSandboxedRuleFileAfterRestart() throws {
        guard let appPath = ProcessInfo.processInfo.environment["SAKURA_SANDBOX_APP"] else {
            throw XCTSkip("只在 macos/tools/run-tests.sh 里运行")
        }
        app.terminate()
        let appURL = URL(fileURLWithPath: appPath)
        let dir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("SakuraMacUITest")
        try? FileManager.default.removeItem(at: dir)
        let rule = dir.appendingPathComponent("rule-\(UUID().uuidString.prefix(8)).rul")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try (Data([0xEF, 0xBB, 0xBF]) + ";Title=RULE\n# /// h\n".data(using: .utf8)!).write(to: rule)
        } catch {
            throw XCTSkip("测试程序写不了 \(dir.path)：\(error)")
        }
        defer { try? FileManager.default.removeItem(at: rule) }
        let base = ["-SakuraUITesting", "YES", "-ApplePersistenceIgnoreState", "YES", "-SakuraUITestingHome", "rule-\(UUID().uuidString)"]

        // 1. タイプ別設定（基本）> スクリーン：ルールファイル を選ぶ（参照 → 「開く」対話框で路径を入力）
        let first = XCUIApplication(url: appURL)
        first.launchArguments = base
        first.launch()
        XCTAssertTrue(first.textViews["editor"].waitForExistence(timeout: 10))
        let settings = first.menuBars.menuBarItems["設定"]
        settings.click()
        settings.menuItems.matching(NSPredicate(format: "title BEGINSWITH 'タイプ別設定' AND NOT (title CONTAINS '一覧')")).firstMatch.click()
        let window = first.windows["TypeSettings"]
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        window.staticTexts["TypeSettingsPage_スクリーン"].click()
        window.radioButtons["IDC_RADIO_OUTLINERULEFILE"].click()
        window.buttons["IDC_BUTTON_RULEFILE_REF"].click()
        let panel = openPanel(of: first)
        let savedInputSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
        if let ascii = TISCopyCurrentASCIICapableKeyboardInputSource()?.takeRetainedValue() { TISSelectInputSource(ascii) }
        defer { if let savedInputSource { TISSelectInputSource(savedInputSource) } }
        panel.typeKey("g", modifierFlags: [.command, .shift])
        sleep(1)
        panel.typeText(rule.path + "\n")
        sleep(1)
        let openButton = first.buttons.matching(NSPredicate(format: "title IN %@ OR label IN %@", ["開く", "Open"], ["開く", "Open"])).firstMatch
        if openButton.waitForExistence(timeout: 5) { openButton.click() } else { panel.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: []) }
        XCTAssertTrue(waitFor { (window.textFields["IDC_EDIT_OUTLINERULEFILE"].value as? String) == rule.path }, "ルールファイルの路径")
        window.buttons["TypeSettingsOK"].click()
        first.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(first.wait(for: .notRunning, timeout: 10))

        // 2. 再起動して、無題（基本）でアウトライン解析：ルールファイルが読めている
        app = XCUIApplication(url: appURL)
        app.launchArguments = base
        app.launch()
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.click()
        editor.typeText("# one\n# two\n")
        let menu = app.menuBars.menuBarItems["検索"]
        menu.click()
        menu.menuItems["アウトライン解析..."].click()
        let outline = app.dialogs["RULE"]
        XCTAssertTrue(outline.waitForExistence(timeout: 5), "ルールファイルの Title")
        XCTAssertTrue(outline.outlines["IDC_TREE_FL_outline"].staticTexts["# one"].exists)
        XCTAssertTrue(outline.outlines["IDC_TREE_FL_outline"].staticTexts["# two"].exists)
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

    // MARK: - 第 42 步：アウトライン解析

    /// 検索 > アウトライン解析：ツリーに見出し、ダブルクリックでジャンプ、「自動的に閉じる」で閉じて編集画面に戻る
    func testOutlineWindow() {
        editor.typeText("(1) one\n(A) sub\n(2) two\nend")	// 編集画面は英字の入力だけ（UITesting.swift）
        key(XCUIKeyboardKey.upArrow.rawValue, .command)	// 文档的开头
        let menu = app.menuBars.menuBarItems["検索"]
        menu.click()
        menu.menuItems["アウトライン解析..."].click()
        let panel = app.dialogs["テキスト トピックツリー"]
        XCTAssertTrue(panel.waitForExistence(timeout: 5), "アウトライン解析が開いた")
        let tree = panel.outlines["IDC_TREE_FL_outline"]
        XCTAssertTrue(tree.exists)
        XCTAssertTrue(tree.staticTexts["(1) one"].exists)
        XCTAssertTrue(tree.staticTexts["(2) two"].exists)
        XCTAssertTrue(panel.popUpButtons["IDC_COMBO_nSortType"].exists, "順序")
        for title in ["コピー(C)", "ジャンプ(J)", "キャンセル(X)"] {
            XCTAssertTrue(panel.buttons[title].exists, title)
        }
        panel.checkBoxes["自動的に閉じる(D)"].click()
        tree.staticTexts["(2) two"].doubleClick()
        let closed = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: panel)
        wait(for: [closed], timeout: 5)	// 自動的に閉じる
        app.typeText("X")
        XCTAssertEqual(normalizedText, "(1) one\n(A) sub\nX(2) two\nend", "3 行目の先頭へジャンプした")
    }

    /// ▼ >「左ドッキング」：編集窓口の左に入る。項目のクリックでジャンプ、キャプションの × で閉じる
    func testOutlineDocking() {
        editor.typeText("(1) one\n(A) sub\n(2) two\nend")
        key(XCUIKeyboardKey.upArrow.rawValue, .command)
        let menu = app.menuBars.menuBarItems["検索"]
        menu.click()
        menu.menuItems["アウトライン解析..."].click()
        let panel = app.dialogs["テキスト トピックツリー"]
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        panel.buttons["IDC_BUTTON_MENU"].click()
        app.menuItems["左ドッキング(L)"].click()
        let title = app.staticTexts["outlineDockTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5), "ドッキングした")
        XCTAssertEqual(title.value as? String, "テキスト トピックツリー")
        XCTAssertFalse(panel.exists, "フローティングの窓口は閉じた")
        let tree = app.outlines["IDC_TREE_FL_outline"]
        tree.staticTexts["(2) two"].click()	// ドッキングはシングルクリックでジャンプ
        tree.staticTexts["(2) two"].doubleClick()	// ダブルクリックで編集画面へ
        app.typeText("X")
        XCTAssertEqual(normalizedText, "(1) one\n(A) sub\nX(2) two\nend")
        app.buttons["outlineDockClose"].click()
        XCTAssertFalse(title.exists, "閉じた")
    }

    /// キャプション・タイトルバーのドラッグでドッキング配置を変える（原版 Track）：右端へ → 右ドッキング、真ん中へ → フローティング、
    /// フローティングのタイトルバーを左端へ → 左ドッキング
    func testOutlineDockingByDrag() {
        editor.typeText("(1) one\n(2) two\n")
        let menu = app.menuBars.menuBarItems["検索"]
        menu.click()
        menu.menuItems["アウトライン解析..."].click()
        let panel = app.dialogs["テキスト トピックツリー"]
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        panel.buttons["IDC_BUTTON_MENU"].click()
        app.menuItems["左ドッキング(L)"].click()
        let window = app.windows.firstMatch
        let title = app.staticTexts["outlineDockTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertLessThan(title.frame.midX, window.frame.midX, "左")
        // 右端へ
        title.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .click(forDuration: 0.3, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5)))
        XCTAssertTrue(waitFor { title.exists && title.frame.midX > window.frame.midX }, "右にドッキング")
        // 真ん中へ：フローティング
        title.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .click(forDuration: 0.3, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.4)))
        XCTAssertTrue(panel.waitForExistence(timeout: 5), "フローティングになった")
        XCTAssertFalse(title.exists)
        // フローティングのタイトルバーを左端へ
        panel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02))
            .click(forDuration: 0.3, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5)))
        XCTAssertTrue(waitFor { title.exists && title.frame.midX < window.frame.midX }, "左にドッキング")
        XCTAssertFalse(panel.exists)
    }

    private func waitFor(timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            usleep(200_000)
        }
        return condition()
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

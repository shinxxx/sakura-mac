// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import Carbon.HIToolbox
import EditorBridge
import XCTest

/// 菜单与快捷键（计划第 34 步）的测试。
///
/// - 菜单栏按原版的 MainMenu.ini 生成：顶层菜单、项目的名字和功能编号（tag）、已移植的功能有动作、未移植的变灰
/// - 菜单上的快捷键：Mac 方案是 ⌘（⌘C、⌘R 置換、⌘J 指定行へジャンプ、⌘G 次を検索），Windows 方案是 ⌃
/// - Mac 的按键 → 原版的虚拟键码和修饰键（US 键盘、日文键盘的记号键），不查表的键（方向键、⌥ 字符、⌃ 组合）
/// - 编辑画面的 keyDown 按表执行（F8 コピー、Esc 取消选择、Windows 方案的 ⌃Home）
final class MenuKeyTests: XCTestCase {
    private var window: NSWindow!
    private var view: EditorTextView!
    private var pasteboard: NSPasteboard!

    override func setUpWithError() throws {
        _ = TestCore.home
        _ = NSApplication.shared
        UserDefaults.standard.removeObject(forKey: KeyScheme.defaultsKey)
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
        UserDefaults.standard.removeObject(forKey: KeyScheme.defaultsKey)
        pasteboard.releaseGlobally()
        window.close()
        window = nil
        view = nil
    }

    private var text: String { view.document.text }

    // MARK: - 菜单

    private func topMenu(_ menu: NSMenu, _ title: String) -> NSMenu? {
        menu.items.first { $0.title == title }?.submenu
    }

    /// 菜单里找功能编号（tag）是 code 的项目（子菜单里也找）
    private func item(_ menu: NSMenu, tag code: Int) -> NSMenuItem? {
        for item in menu.items {
            if item.tag == code && item.submenu == nil { return item }
            if let sub = item.submenu, let found = self.item(sub, tag: code) { return found }
        }
        return nil
    }

    /// 顶层菜单的名字和顺序与原版相同（最前面是 Mac 的 App 菜单）
    func testTopMenusAreSameAsOriginal() {
        let menu = MainMenuBuilder.build()
        let titles = menu.items.dropFirst().map(\.title)
        XCTAssertEqual(titles, ["ファイル", "編集", "変換", "検索", "ツール", "設定", "ウィンドウ", "ヘルプ"])
    }

    /// 菜单项的名字、功能编号、动作：已移植的有动作，未移植的没有（变灰）
    func testMenuItemsHaveCommandsAndActions() throws {
        let menu = MainMenuBuilder.build()
        let edit = try XCTUnwrap(topMenu(menu, "編集"))
        let copy = try XCTUnwrap(edit.items.first { $0.title == "コピー" })
        XCTAssertEqual(copy.tag, 30602)
        XCTAssertEqual(copy.action, #selector(EditorTextView.copy(_:)))
        XCTAssertNil(copy.target, "沿响应链执行")

        let search = try XCTUnwrap(topMenu(menu, "検索"))
        XCTAssertEqual(search.items.first { $0.title == "置換..." }?.action, #selector(EditorTextView.showReplacePanel(_:)))
        let grep = try XCTUnwrap(search.items.first { $0.tag == 30910 })
        XCTAssertEqual(grep.title, "Grep...")
        XCTAssertNil(grep.action, "Grep 还没有移植：没有动作，菜单里变灰")

        // 子菜单：編集 > 高度な操作 > TABインデント
        let advanced = try XCTUnwrap(edit.items.first { $0.title == "高度な操作" }?.submenu)
        XCTAssertEqual(advanced.items.first { $0.tag == 30260 }?.action, #selector(EditorTextView.indentTab(_:)))
        // 設定 > 折り返し方法 的 3 个
        let settings = try XCTUnwrap(topMenu(menu, "設定"))
        let wrap = try XCTUnwrap(settings.items.first { $0.title == "折り返し方法" }?.submenu)
        XCTAssertEqual(wrap.items.prefix(3).map(\.title), ["折り返さない", "指定桁で折り返す", "右端で折り返す"])
        // 分隔线也与原版相同：ファイル的第 7 项
        let file = try XCTUnwrap(topMenu(menu, "ファイル"))
        XCTAssertTrue(file.items[6].isSeparatorItem)
        XCTAssertEqual(file.items.first?.title, "新規作成")
    }

    /// Mac 的追加：最近使ったファイル（第 31 步）、ウィンドウ > しまう、ウィンドウ一覧（macOS 的窗口一览）、键位方案的切换
    func testMacSpecificItems() throws {
        let menu = MainMenuBuilder.build()
        let file = try XCTUnwrap(topMenu(menu, "ファイル"))
        XCTAssertTrue(file.items.contains { $0.title == "最近使ったファイル" })
        XCTAssertTrue(file.items.contains { $0.title == "最近使ったフォルダー" })
        XCTAssertNotNil(file.delegate, "打开时更新历史")

        let windowMenu = try XCTUnwrap(topMenu(menu, "ウィンドウ"))
        XCTAssertEqual(windowMenu.items.first?.title, "しまう")
        XCTAssertEqual(windowMenu.items.first?.keyEquivalent, "m")
        let list = try XCTUnwrap(windowMenu.items.first { $0.title == "ウィンドウ一覧" }?.submenu)
        XCTAssertTrue(NSApp.windowsMenu === list)

        let settings = try XCTUnwrap(topMenu(menu, "設定"))
        XCTAssertEqual(settings.items.last?.action, #selector(KeySchemeToggle.toggleKeyScheme(_:)))
    }

    /// 菜单上的快捷键：Mac 方案（⌘ = Ctrl）
    func testMenuKeyEquivalentsMacScheme() throws {
        let menu = MainMenuBuilder.build()
        func assertKey(_ code: Int, _ key: String, _ mods: NSEvent.ModifierFlags, line: UInt = #line) {
            let found = item(menu, tag: code)
            XCTAssertEqual(found?.keyEquivalent, key, "\(code)", line: line)
            XCTAssertEqual(found?.keyEquivalentModifierMask, mods, "\(code)", line: line)
        }
        assertKey(30602, "c", .command)					// コピー
        assertKey(30604, "v", .command)					// 貼り付け
        assertKey(30210, "z", .command)					// 元に戻す
        assertKey(30211, "z", [.command, .shift])		// やり直し（Mac 的 ⇧⌘Z，⌘Y 也能用）
        assertKey(30901, "f", .command)					// 検索
        assertKey(30904, "r", .command)					// 置換（原版 Ctrl+R）
        assertKey(30920, "j", .command)					// 指定行へジャンプ（原版 Ctrl+J）
        assertKey(30902, "g", .command)					// 次を検索（Mac 的 ⌘G）
        assertKey(30903, "g", [.command, .shift])
        assertKey(30101, "n", .command)					// 新規作成
        assertKey(30102, "o", .command)					// 開く
        assertKey(30103, "s", .command)					// 上書き保存
        assertKey(30104, "s", [.command, .shift])		// 名前を付けて保存
        assertKey(31320, "w", .command)					// 閉じる
        assertKey(30910, "", [])						// Grep：⌘G 用于次を検索
        assertKey(30400, "", [])						// 単語選択（原版 Ctrl+W）：⌘W 是閉じる
        let f2 = String(Character(UnicodeScalar(NSF2FunctionKey)!))
        assertKey(30971, f2, [])						// 次のブックマークへ（F2）
    }

    /// Windows 方案：菜单上的快捷键是 ⌃
    func testMenuKeyEquivalentsWindowsScheme() throws {
        let menu = MainMenuBuilder.build()
        KeyScheme.current = .windows
        XCTAssertEqual(item(menu, tag: 30602)?.keyEquivalent, "c")
        XCTAssertEqual(item(menu, tag: 30602)?.keyEquivalentModifierMask, .control)
        XCTAssertEqual(item(menu, tag: 30910)?.keyEquivalent, "g", "Grep 是 ⌃G（与原版相同）")
        XCTAssertEqual(item(menu, tag: 30902)?.keyEquivalent, String(Character(UnicodeScalar(NSF3FunctionKey)!)), "次を検索 是 F3")
        KeyScheme.current = .mac
        XCTAssertEqual(item(menu, tag: 30602)?.keyEquivalentModifierMask, .command, "回到 Mac 方案")
    }

    // MARK: - 按键 → 原版的按键

    private func stroke(_ keyCode: Int, _ chars: String?, _ flags: NSEvent.ModifierFlags,
                        _ scheme: KeyScheme = .mac, jis: Bool = false) -> KeyStroke? {
        KeyCommands.stroke(keyCode: UInt16(keyCode), charactersIgnoringModifiers: chars, flags: flags, scheme: scheme, jis: jis)
    }

    func testStrokeMacScheme() {
        XCTAssertEqual(stroke(kVK_ANSI_C, "c", .command), KeyStroke(0x43, .ctrl), "⌘C = Ctrl+C")
        XCTAssertEqual(stroke(kVK_ANSI_C, "c", [.command, .shift]), KeyStroke(0x43, [.ctrl, .shift]))
        XCTAssertEqual(stroke(kVK_F3, nil, []), KeyStroke(114))
        XCTAssertEqual(stroke(kVK_F3, nil, .shift), KeyStroke(114, .shift))
        XCTAssertEqual(stroke(kVK_F3, nil, .option), KeyStroke(114, .alt), "F 键的 ⌥ 是 Alt")
        XCTAssertEqual(stroke(kVK_Tab, "\t", []), KeyStroke(9))
        XCTAssertEqual(stroke(kVK_Escape, "\u{1b}", []), KeyStroke(27))
        XCTAssertEqual(stroke(kVK_ANSI_A, "a", [.command, .option]), KeyStroke(0x41, [.ctrl, .alt]))
        XCTAssertNil(stroke(kVK_ANSI_A, "a", .option), "⌥A 输入 å")
        XCTAssertNil(stroke(kVK_ANSI_A, "a", .control), "⌃A 交给 macOS")
        XCTAssertNil(stroke(kVK_LeftArrow, nil, []), "方向键按 macOS 的习惯")
        XCTAssertNil(stroke(kVK_LeftArrow, nil, .command))
        XCTAssertNil(stroke(kVK_Delete, nil, []))
        XCTAssertNil(stroke(kVK_Return, "\r", []))
        // Dvorak 等：按印着的字母
        XCTAssertEqual(stroke(kVK_ANSI_Semicolon, "s", .command), KeyStroke(0x53, .ctrl))
        // 假名输入时按键的位置
        XCTAssertEqual(stroke(kVK_ANSI_C, "そ", .command), KeyStroke(0x43, .ctrl))
    }

    func testStrokeSymbolKeys() {
        // US 键盘：[ 是 VK_OEM_4
        XCTAssertEqual(stroke(kVK_ANSI_LeftBracket, "[", .command), KeyStroke(0xDB, .ctrl))
        // 日文键盘：P 右边是 @（VK_OEM_3），再右边是 [（VK_OEM_4），: 是 VK_OEM_1
        XCTAssertEqual(stroke(kVK_ANSI_LeftBracket, "@", .command, jis: true), KeyStroke(0xC0, .ctrl))
        XCTAssertEqual(stroke(kVK_ANSI_RightBracket, "[", .command, jis: true), KeyStroke(0xDB, .ctrl))
        XCTAssertEqual(stroke(kVK_ANSI_Quote, ":", .command, jis: true), KeyStroke(0xBA, .ctrl))
        XCTAssertEqual(stroke(kVK_JIS_Underscore, "_", .command, jis: true), KeyStroke(0xE2, .ctrl))
    }

    func testStrokeWindowsScheme() {
        XCTAssertEqual(stroke(kVK_ANSI_C, "c", .control, .windows), KeyStroke(0x43, .ctrl), "⌃C = Ctrl+C")
        XCTAssertNil(stroke(kVK_ANSI_C, "c", .command, .windows), "⌘ 留给 macOS 的菜单")
        XCTAssertEqual(stroke(kVK_LeftArrow, nil, [], .windows), KeyStroke(37))
        XCTAssertEqual(stroke(kVK_Home, nil, .control, .windows), KeyStroke(36, .ctrl))
        XCTAssertEqual(stroke(kVK_ANSI_A, "a", .option, .windows), KeyStroke(0x41, .alt))
    }

    func testCommandForStroke() {
        XCTAssertEqual(KeyCommands.command(for: KeyStroke(0x43, .ctrl), scheme: .mac), 30602)	// ⌘C コピー
        XCTAssertEqual(KeyCommands.command(for: KeyStroke(0x52, .ctrl), scheme: .mac), 30904)	// ⌘R 置換
        XCTAssertEqual(KeyCommands.command(for: KeyStroke(0x4A, .ctrl), scheme: .mac), 30920)	// ⌘J ジャンプ
        XCTAssertEqual(KeyCommands.command(for: KeyStroke(0x59, .ctrl), scheme: .mac), 30211)	// ⌘Y やり直し
        XCTAssertEqual(KeyCommands.command(for: KeyStroke(0x47, .ctrl), scheme: .mac), 30902)	// ⌘G 次を検索
        XCTAssertEqual(KeyCommands.command(for: KeyStroke(0x57, .ctrl), scheme: .mac), 31320)	// ⌘W 閉じる
        XCTAssertEqual(KeyCommands.command(for: KeyStroke(0x51, .ctrl), scheme: .mac), 0, "⌘Q 是退出（App 菜单）")
        XCTAssertEqual(KeyCommands.command(for: KeyStroke(0x48, .ctrl), scheme: .mac), 0, "⌘H 是隐藏")
        XCTAssertEqual(KeyCommands.command(for: KeyStroke(0x47, .ctrl), scheme: .windows), 30910, "⌃G 是 Grep（与原版相同）")
        XCTAssertEqual(KeyCommands.command(for: KeyStroke(0x57, .ctrl), scheme: .windows), 30400, "⌃W 是単語選択")
        XCTAssertEqual(KeyCommands.command(for: KeyStroke(114), scheme: .mac), 30902)			// F3
        XCTAssertEqual(KeyCommands.command(for: KeyStroke(0x41), scheme: .mac), 0)				// A 是输入
    }

    // MARK: - 编辑画面的按键

    private func keyEvent(_ keyCode: Int, _ chars: String, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                         windowNumber: window.windowNumber, context: nil, characters: chars,
                         charactersIgnoringModifiers: chars, isARepeat: false, keyCode: UInt16(keyCode))!
    }

    private func load(_ s: String) {
        XCTAssertEqual(view.document.insert(s, at: EditorPosition(line: 0, column: 0)), .success)
        view.setCaret(EditorPosition(line: 0, column: 0))
    }

    private static func functionKey(_ key: Int) -> String { String(Character(UnicodeScalar(key)!)) }

    /// F8 コピー、F7 切り取り、F9 貼り付け（原版的 F 键）
    func testFunctionKeysRunCommands() {
        load("hello")
        view.selectAll(nil)
        view.keyDown(with: keyEvent(kVK_F8, Self.functionKey(NSF8FunctionKey)))
        XCTAssertEqual(pasteboard.string(forType: .string), "hello", "F8 コピー")
        view.keyDown(with: keyEvent(kVK_F7, Self.functionKey(NSF7FunctionKey)))
        XCTAssertEqual(text, "", "F7 切り取り")
        view.keyDown(with: keyEvent(kVK_F9, Self.functionKey(NSF9FunctionKey)))
        XCTAssertEqual(text, "hello", "F9 貼り付け")
    }

    /// Esc：取消选择（F_CANCEL_MODE）
    func testEscapeCancelsSelection() {
        load("hello")
        view.selectAll(nil)
        XCTAssertTrue(view.hasSelection)
        view.keyDown(with: keyEvent(kVK_Escape, "\u{1b}"))
        XCTAssertFalse(view.hasSelection)
    }

    /// ⌘ 组合（菜单没有接住时）也按表执行：⌘A すべて選択
    func testCommandKeyRunsCommand() {
        load("abc")
        view.keyDown(with: keyEvent(kVK_ANSI_A, "a", .command))
        XCTAssertTrue(view.hasSelection, "⌘A すべて選択")
    }

    /// Windows 方案：⌃End ファイルの最後、⌃Home ファイルの先頭（方向键等也按原版的表）
    func testWindowsSchemeNavigation() {
        KeyScheme.current = .windows
        load("a\nb\nc")
        view.keyDown(with: keyEvent(kVK_End, Self.functionKey(NSEndFunctionKey), .control))
        XCTAssertEqual(view.caret.line, 2, "⌃End")
        view.keyDown(with: keyEvent(kVK_Home, Self.functionKey(NSHomeFunctionKey), .control))
        XCTAssertEqual(view.caret.line, 0, "⌃Home")
    }

    /// 表里没有的键照常输入
    func testPlainKeysAreTyped() {
        view.keyDown(with: keyEvent(kVK_ANSI_X, "x"))
        view.keyDown(with: keyEvent(kVK_Space, " "))
        XCTAssertEqual(text, "x ", "文字和 Space（SPACEインデント 未移植时是输入）")
    }
}

// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge
import XCTest

/// ステータスバー・ツールバー・タブバー（计划第 38 步）的测试。
///
/// - ステータスバーの各欄が Windows 版と同じ（StatusBarSamples：CI の statusbar-windows が Windows 版 sakura.exe で読んだ結果）
/// - 欄の幅（原版 CEditWnd::OnSize）、ダブルクリック・右クリックの機能、各種コードの表示
/// - 表示の切り替え（F_SHOWTOOLBAR、F_SHOWSTATUSBAR、F_SHOWTAB）、メッセージはステータスバーへ
/// - ツールバーの並び（共通設定のツールバー）、ツールチップ、タブの幅・まとめ表示
final class StatusBarTests: XCTestCase {
    private var documents: [SakuraDocument] = []
    private var saved: [String: String] = [:]
    private static let keys = ["bDispTOOLBAR", "bDispSTATUSBAR", "bDispTabWnd", "bDispTabWndMultiWin", "bEnableExtEol"]

    override func setUpWithError() throws {
        _ = TestCore.home
        _ = NSApplication.shared
        for key in Self.keys { saved[key] = EditorCore.commonSetting(section: "Common", key: key) ?? "" }
        _ = EditorCore.setCommonSettings(["bDispTOOLBAR": "1", "bDispSTATUSBAR": "1", "bDispTabWnd": "0",
                                          "bDispTabWndMultiWin": "1", "bEnableExtEol": "0"], section: "Common")
    }

    override func tearDown() {
        for document in documents { document.close() }
        documents = []
        _ = EditorCore.setCommonSettings(saved, section: "Common")
        NotificationCenter.default.post(name: WindowBarSettings.didChangeNotification, object: nil)
    }

    private static var samples: URL {
        Bundle(for: StatusBarTests.self).url(forResource: "StatusBarSamples", withExtension: nil)!
    }

    private func open(_ url: URL) throws -> EditorWindowController {
        let document = try SakuraDocument(contentsOf: url, ofType: "public.plain-text")
        document.makeWindowControllers()
        documents.append(document)
        return try XCTUnwrap(document.editorWindowController)
    }

    private func untitled() throws -> EditorWindowController {
        let document = SakuraDocument()
        document.makeWindowControllers()
        documents.append(document)
        return try XCTUnwrap(document.editorWindowController)
    }

    private func type(_ view: EditorTextView, _ text: String) {
        view.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    // MARK: - Windows 版と同じ

    /// cases.txt の各行：ファイルを開き、先頭から下へ N 回、右へ M 回動かしたときの欄（行・桁、改行、文字コード、文字コードセット、挿入、ズーム）
    func testSameAsWindows() throws {
        let cases = try String(contentsOf: Self.samples.appendingPathComponent("cases.txt"), encoding: .utf8)
            .split(separator: "\n").map(String.init).filter { !$0.isEmpty && !$0.hasPrefix("#") }
        XCTAssertFalse(cases.isEmpty)
        var lines: [String] = []
        for line in cases {
            let f = line.split(separator: " ").map(String.init)
            let controller = try open(Self.samples.appendingPathComponent(f[0]))
            let view = controller.textView
            view.moveToBeginningOfDocument(nil)
            for _ in 0..<(Int(f[1]) ?? 0) { view.moveDown(nil) }
            for _ in 0..<(Int(f[2]) ?? 0) { view.moveRight(nil) }
            controller.updateWindowBars()
            let bar = try XCTUnwrap(controller.statusBar)
            let parts: [StatusBarView.Part] = [.rowCol, .eol, .charCode, .encoding, .insMode, .zoom]
            lines.append(([line] + parts.map { bar.text($0) }).joined(separator: "|"))
            documents.removeLast().close()
        }
        let actual = lines.joined(separator: "\n") + "\n"
        let expected = try String(contentsOf: Self.samples.appendingPathComponent("expected/statusbar.txt"), encoding: .utf8)
        XCTAssertEqual(actual, expected)
    }

    // MARK: - ステータスバー

    func testShownByDefaultWithParts() throws {
        let controller = try untitled()
        let bar = try XCTUnwrap(controller.statusBar)
        XCTAssertTrue(controller.container.subviews.contains(bar))
        XCTAssertEqual(bar.text(.rowCol), StatusBarText.rowCol(line: 1, column: 1))
        XCTAssertEqual(bar.text(.rowCol), "    1 行    1 桁")
        XCTAssertEqual(bar.text(.insMode), "挿入")
        XCTAssertEqual(bar.text(.zoom), " 100 %")
        XCTAssertEqual(bar.text(.rec), "")
        // 入力すると行・桁が変わる
        type(controller.textView, "ab\ncde")
        controller.updateWindowBars()
        XCTAssertEqual(bar.text(.rowCol), "    2 行    4 桁")
        XCTAssertEqual(bar.text(.charCode), "", "EOF では文字コードなし")
        controller.textView.moveLeft(nil)
        controller.updateWindowBars()
        XCTAssertEqual(bar.text(.charCode), "U+0065")
        // 上書きモード
        _ = CommandTable.perform(31001, from: controller.textView)
        controller.updateWindowBars()
        XCTAssertEqual(bar.text(.insMode), "上書")
        _ = CommandTable.perform(31001, from: controller.textView)
    }

    /// 欄の幅：右端（サイズボックスの分を空ける）から、見本の文字の幅＋境界の幅ずつ（原版 CEditWnd::OnSize）
    func testPartWidths() {
        let labels = StatusBarView.sampleLabels()
        XCTAssertEqual(labels.count, StatusBarView.Part.allCases.count)
        XCTAssertEqual(labels[2], "CRLF")
        XCTAssertEqual(labels[3], "AAAAAAAAAAAA")
        let rights = StatusBarView.partRights(width: 900)
        XCTAssertEqual(rights.last, 900 - StatusBarView.sizeBoxWidth)
        for i in 1..<rights.count {
            XCTAssertEqual(rights[i] - rights[i - 1], StatusBarView.width(of: labels[i]) + StatusBarView.borderWidth)
        }
        XCTAssertGreaterThan(rights[0], 400, "メッセージ欄が残りを使う")
    }

    func testDoubleClickCommands() {
        XCTAssertEqual(StatusBarView.command(forDoubleClickOn: .rowCol), 30920)
        XCTAssertEqual(StatusBarView.command(forDoubleClickOn: .encoding), 31010)
        XCTAssertEqual(StatusBarView.command(forDoubleClickOn: .rec), 31250)
        XCTAssertEqual(StatusBarView.command(forDoubleClickOn: .insMode), 31001)
        XCTAssertNil(StatusBarView.command(forDoubleClickOn: .eol))
        XCTAssertNil(StatusBarView.command(forDoubleClickOn: .zoom))
    }

    func testDoubleClickInsertMode() throws {
        let controller = try untitled()
        let bar = try XCTUnwrap(controller.statusBar)
        bar.doubleClicked(.insMode)
        controller.updateWindowBars()
        XCTAssertEqual(bar.text(.insMode), "上書")
        bar.doubleClicked(.insMode)
        controller.updateWindowBars()
        XCTAssertEqual(bar.text(.insMode), "挿入")
    }

    /// 改行コードの欄の右クリック：入力改行コード指定（拡張 EOL が有効なら NEL・LS・PS も）
    func testEolMenu() throws {
        let controller = try untitled()
        let bar = try XCTUnwrap(controller.statusBar)
        var menu = try XCTUnwrap(bar.eolMenu())
        XCTAssertEqual(menu.items.map(\.tag), [31081, 31082, 31083])
        XCTAssertTrue(menu.items.allSatisfy { $0.action == #selector(EditorTextView.changeNewLineEol(_:)) })
        _ = EditorCore.setCommonSetting("1", section: "Common", key: "bEnableExtEol")
        menu = try XCTUnwrap(bar.eolMenu())
        XCTAssertEqual(menu.items.map(\.tag), [31081, 31082, 31083, 31084, 31086, 31085])
        XCTAssertEqual(menu.items.suffix(3).map(\.title), ["NEL", "LS", "PS"])
        // LF を選ぶと欄が LF になる
        let lf = menu.items[1]
        controller.textView.changeNewLineEol(lf)
        type(controller.textView, "a\n")
        controller.updateWindowBars()
        XCTAssertEqual(bar.text(.eol), "LF")
    }

    /// 文字コードの欄のダブルクリック：各種コード（原版 ShowCodeBox）
    func testCodeBox() throws {
        let controller = try untitled()
        let saved = EditorTextView.presentCodeBox
        defer { EditorTextView.presentCodeBox = saved }
        var messages: [String] = []
        EditorTextView.presentCodeBox = { _, message in messages.append(message) }
        controller.statusBar?.doubleClicked(.charCode)
        XCTAssertEqual(messages, [], "文字がないときは出さない")
        type(controller.textView, "あ")
        controller.textView.moveToBeginningOfDocument(nil)
        controller.statusBar?.doubleClicked(.charCode)
        let message = try XCTUnwrap(messages.first)
        XCTAssertTrue(message.contains("U+3042"), message)
        XCTAssertTrue(message.contains("82A0"), message)
        XCTAssertTrue(message.contains("E38182"), message)
    }

    /// ステータスバーの表示中はメッセージをメッセージ欄に出す
    func testMessageGoesToStatusBar() throws {
        let controller = try untitled()
        let view = controller.textView
        view.sendStatusMessage("テスト")
        XCTAssertEqual(controller.statusBar?.text(.message), "テスト")
        XCTAssertEqual(view.statusMessage, "テスト")
        XCTAssertTrue(view.statusLabel?.isHidden ?? true)
        view.sendStatusMessage("")
        XCTAssertEqual(view.statusMessage, "")
    }

    // MARK: - 表示の切り替え

    func testToggleCommands() throws {
        let controller = try untitled()
        XCTAssertNotNil(controller.statusBar)
        XCTAssertNotNil(controller.toolbarView)
        XCTAssertNil(controller.tabBarView)
        let item = NSMenuItem(title: "", action: CommandTable.selector(for: 31102), keyEquivalent: "")
        item.tag = 31102
        XCTAssertEqual(controller.textView.validateMenuItem(item), true)
        XCTAssertEqual(item.state, .on)
        // ステータスバーを消す：メッセージは編集画面の左下へ
        controller.textView.toggleWindowBar(item)
        XCTAssertNil(controller.statusBar)
        XCTAssertFalse(WindowBarSettings.showsStatusBar)
        _ = controller.textView.validateMenuItem(item)
        XCTAssertEqual(item.state, .off)
        controller.textView.sendStatusMessage("abc")
        XCTAssertEqual(controller.textView.statusMessage, " abc ")
        // ツールバーを消す
        let toolbarItem = NSMenuItem(title: "", action: CommandTable.selector(for: 31100), keyEquivalent: "")
        toolbarItem.tag = 31100
        controller.textView.toggleWindowBar(toolbarItem)
        XCTAssertNil(controller.toolbarView)
        // タブバーを出す
        let tabItem = NSMenuItem(title: "", action: CommandTable.selector(for: 31103), keyEquivalent: "")
        tabItem.tag = 31103
        controller.textView.toggleWindowBar(tabItem)
        let tabBar = try XCTUnwrap(controller.tabBarView)
        XCTAssertTrue(controller.container.subviews.contains(tabBar))
        XCTAssertEqual(controller.window?.tabbingMode, .disallowed)
        // 元に戻す
        controller.textView.toggleWindowBar(item)
        controller.textView.toggleWindowBar(toolbarItem)
        controller.textView.toggleWindowBar(tabItem)
        XCTAssertNotNil(controller.statusBar)
        XCTAssertNotNil(controller.toolbarView)
        XCTAssertNil(controller.tabBarView)
    }

    /// バーの分だけ編集画面が小さくなる（ツールバーが上、ステータスバーが下）
    func testEditorAreaExcludesBars() throws {
        let controller = try untitled()
        let container = controller.container
        container.frame = NSRect(x: 0, y: 0, width: 700, height: 500)
        container.arrange()
        let area = container.editorArea
        let toolbar = try XCTUnwrap(controller.toolbarView)
        let status = try XCTUnwrap(controller.statusBar)
        XCTAssertEqual(status.frame.height, StatusBarView.height)
        XCTAssertEqual(area.height, 500 - toolbar.frame.height - status.frame.height, accuracy: 0.5)
        XCTAssertEqual(area.width, 700)
    }

    // MARK: - ツールバー

    func testToolbarItemsFromSettings() throws {
        let current = EditorToolbarView.currentItems()
        XCTAssertFalse(current.items.isEmpty)
        // 区切り・折返は続かない
        for (a, b) in zip(current.items, current.items.dropFirst()) {
            XCTAssertFalse((a == .separator || a == .wrap) && (b == .separator || b == .wrap))
        }
        let controller = try untitled()
        let toolbar = try XCTUnwrap(controller.toolbarView)
        let codes = current.items.compactMap { item -> Int? in
            if case let .button(code, _) = item, code != EditorToolbarView.searchBox { return code }
            return nil
        }
        XCTAssertEqual(toolbar.buttons.map(\.code), codes)
        // 既定のツールバー：新規作成・開く・上書き保存
        XCTAssertTrue(codes.contains(30101))
        XCTAssertTrue(codes.contains(30110) || codes.contains(30102) || codes.contains(EditorToolbarView.fileOpenDropDown))
        for button in toolbar.buttons {
            XCTAssertEqual(button.frame.size, NSSize(width: EditorToolbarView.buttonSize + (button.hasDropDown ? ToolbarButton.arrowWidth : 0),
                                                     height: EditorToolbarView.buttonSize))
            XCTAssertFalse(button.toolTip?.isEmpty ?? true)
        }
    }

    func testToolbarTooltipAndStates() throws {
        XCTAssertEqual(ToolbarButton.shortcutText("s", [.command]), "⌘S")
        XCTAssertEqual(ToolbarButton.shortcutText("\u{F704}", [.shift]), "⇧F1")
        let tip = ToolbarButton.tooltip(code: 30101, name: "新規作成")
        XCTAssertTrue(tip.hasPrefix("新規作成"))
        let controller = try untitled()
        let validation = CommandTable.validate(31001, from: controller.textView)
        XCTAssertTrue(validation.enabled)
        // 元に戻すは何もしていないときは使えない
        XCTAssertFalse(CommandTable.validate(30210, from: controller.textView).enabled)
    }

    func testFileDropDownMenu() throws {
        let controller = try untitled()
        let toolbar = try XCTUnwrap(controller.toolbarView)
        let menu = toolbar.fileDropDownMenu()
        XCTAssertEqual(menu.items.suffix(3).map(\.tag), [30101, 30110, 30102])
    }

    // MARK: - タブバー

    func testTabWidths() {
        let tabBar = TabBarView(settings: TabBarView.Settings())
        let a = ObjectIdentifier(NSObject.self), b = ObjectIdentifier(NSView.self)
        tabBar.setTabs([TabBarView.Tab(id: a, title: "a.txt", toolTip: "", path: ""),
                        TabBarView.Tab(id: b, title: String(repeating: "長い名前", count: 20), toolTip: "", path: "")], selected: a)
        var widths = tabBar.tabWidths(available: 2000)
        XCTAssertLessThan(widths[0], widths[1])
        XCTAssertEqual(widths[1], 200, "最大の幅")
        // 等幅
        var settings = TabBarView.Settings()
        settings.sameWidth = true
        tabBar.settings = settings
        widths = tabBar.tabWidths(available: 308)
        XCTAssertEqual(widths, [150, 150])
        widths = tabBar.tabWidths(available: 2000)
        XCTAssertEqual(widths, [200, 200])
        widths = tabBar.tabWidths(available: 50)
        XCTAssertEqual(widths, [60, 60], "最小の幅")
    }

    func testTabBarListsWindows() throws {
        _ = EditorCore.setCommonSetting("1", section: "Common", key: "bDispTabWnd")
        NotificationCenter.default.post(name: WindowBarSettings.didChangeNotification, object: nil)
        let first = try untitled()
        let second = try untitled()
        first.updateWindowBars()
        second.updateWindowBars()
        let tabBar = try XCTUnwrap(second.tabBarView)
        XCTAssertGreaterThanOrEqual(tabBar.tabs.count, 2)
        XCTAssertTrue(tabBar.tabs.contains { $0.id == ObjectIdentifier(first) })
        XCTAssertEqual(tabBar.selectedID, ObjectIdentifier(second))
        XCTAssertEqual(tabBar.tabs.first { $0.id == ObjectIdentifier(second) }?.title, second.tabTitle)
        let menu = tabBar.listMenu(paths: false)
        XCTAssertGreaterThanOrEqual(menu.items.count, 2)
    }

    // MARK: - 画面（原版の画面と見比べる。$TMPDIR/sakura-dialog-shots/）

    func testScreenshots() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("sakura-dialog-shots")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        print("截图：\(directory.path)")
        func shot(_ controller: EditorWindowController, _ name: String) throws {
            let window = try XCTUnwrap(controller.window)
            window.setContentSize(NSSize(width: 760, height: 360))
            controller.container.arrange()
            controller.updateWindowBars()
            let view = try XCTUnwrap(window.contentView?.superview ?? window.contentView)
            view.layoutSubtreeIfNeeded()
            view.display()
            let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: rep)
            try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent(name + ".png"))
        }
        let first = try open(Self.samples.appendingPathComponent("sjis-crlf.txt"))
        first.textView.moveDown(nil)
        first.textView.moveRight(nil)
        first.textView.moveRight(nil)
        try shot(first, "statusbar-window")
        _ = EditorCore.setCommonSetting("1", section: "Common", key: "bDispTabWnd")
        NotificationCenter.default.post(name: WindowBarSettings.didChangeNotification, object: nil)
        let second = try open(Self.samples.appendingPathComponent("utf8-lf.txt"))
        first.updateWindowBars()
        try shot(second, "tabbar-window")
    }
}

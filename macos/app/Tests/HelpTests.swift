// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge
import WebKit
import XCTest

/// ヘルプ（计划第 49 步）的测试。
///
/// - 原版的帮助（help/sakura、help/macro）都在 bundle 里，目次・キーワード・话题的页都在，页里的链接不断
/// - 功能的话题（原版 FuncID_To_HelpContextID）、对话框的「ヘルプ」、设置窗口的「?」打开原版的那一页
/// - 控件上右键显示原版 Cshelp.txt 的说明
/// - ヘルプ窗口：目次と同期、キーワード、検索、戻る・進む・ホーム、Mac 版の注記、帮助以外的链接用浏览器
/// - ヘルプ メニュー：ヘルプ目次・キーワード検索・コマンド一覧、macOS 的帮助菜单的搜索
final class HelpTests: XCTestCase {
    private var book: HelpBook!
    private var opened: [String] = []

    override func setUpWithError() throws {
        _ = TestCore.home
        _ = NSApplication.shared
        book = try XCTUnwrap(HelpBook.shared, "HelpTopics.json")
        opened = []
        HelpViewer.opened = { [unowned self] in opened.append($0) }
    }

    override func tearDown() {
        HelpViewer.opened = { _ in }
        HelpWindowController.openExternal = { NSWorkspace.shared.open($0) }
        ContextHelp.close()
        HelpWindowController.current?.close()
    }

    private func exists(_ path: String) -> Bool {
        let file = path.split(separator: "#").first.map(String.init) ?? path
        return FileManager.default.fileExists(atPath: book.root.appendingPathComponent(file).path)
    }

    private func allNodes(_ nodes: [HelpBook.Node]) -> [HelpBook.Node] {
        nodes.flatMap { [$0] + allNodes($0.children) }
    }

    // MARK: - 内容

    /// 目次：先頭は Mac 版のページ、続いて原版の sakura.hhc、Merge されていた macro.hhc（原版と同じ位置）
    func testContentsAreOriginal() {
        XCTAssertEqual(book.title, "サクラエディタ ヘルプ")
        XCTAssertEqual(book.home, "sakura/res/HLP000001.html")
        XCTAssertEqual(book.toc.map(\.title), ["Mac 版について", "サクラエディタ ヘルプ目次", "マクロリファレンス"])
        XCTAssertEqual(book.toc[1].children.map(\.title),
                       ["サクラエディタ概要", "基本的な使い方", "コマンド概要", "デフォルト設定値（インストール時）", "仕様等",
                        "マクロ", "サクラエディタについて", "このヘルプファイルについて"])
        let nodes = allNodes(book.toc)
        XCTAssertGreaterThan(nodes.count, 690)
        XCTAssertTrue(nodes.contains { $0.title == "新規作成" && $0.path == "sakura/res/HLP000025.html" })
        XCTAssertTrue(nodes.contains { $0.path == "macro/source/reference/file/S_FileNew.html" })
        // プラグイン（plugin.chm）は Mac 版にないので合併しない
        XCTAssertFalse(nodes.contains { $0.path?.hasPrefix("plugin/") ?? false })
    }

    /// 目次・キーワード・話題・注記のページは全部 bundle にある
    func testEveryPageExists() {
        for node in allNodes(book.toc) {
            if let path = node.path { XCTAssertTrue(exists(path), path) }
        }
        XCTAssertGreaterThan(book.index.count, 900)
        for entry in book.index {
            XCTAssertFalse(entry.topics.isEmpty, entry.keyword)
            for topic in entry.topics { XCTAssertTrue(exists(topic.path), "\(entry.keyword) \(topic.path)") }
        }
        for id in 1...500 {
            if let path = book.path(forTopic: id) { XCTAssertTrue(exists(path), path) }
        }
        XCTAssertEqual(book.path(forTopic: 1), "sakura/res/HLP000001.html")
        for path in book.notes.keys { XCTAssertTrue(exists(path), path) }
    }

    /// キーワードは原版の HTML Help と同じく並べ替えてある
    func testIndexIsSorted() {
        let keywords = book.index.filter { $0.level == 0 }.map(\.keyword)
        let locale = Locale(identifier: "ja_JP")
        for (a, b) in zip(keywords, keywords.dropFirst()) {
            XCTAssertNotEqual(a.compare(b, options: [.caseInsensitive, .widthInsensitive], range: nil, locale: locale),
                              .orderedDescending, "\(a) / \(b)")
        }
        XCTAssertTrue(keywords.contains("Grep"))
        XCTAssertTrue(keywords.contains("Mac 版について"))
    }

    /// 页里的链接（href、src）指向的文件都在（原版的帮助自身的 1 处除外）
    func testLinksInPagesResolve() throws {
        // 原版的帮助（help/macro/source/reference/support/index.html）的书写错误
        let knownBroken: Set<String> = ["macro/source/reference/support/S_ToggleKeyHelpSearchplete.html"]
        var pages = 0
        var broken: [String] = []
        let regex = try NSRegularExpression(pattern: #"(?:href|src)\s*=\s*"([^"]*)""#, options: [.caseInsensitive])
        for folder in ["sakura", "macro"] {
            let base = book.root.appendingPathComponent(folder)
            let files = try XCTUnwrap(FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil))
            for case let url as URL in files where url.pathExtension.lowercased() == "html" {
                pages += 1
                let html = try String(contentsOf: url, encoding: .utf8)
                    .replacingOccurrences(of: "(?s)<!--.*?-->", with: "", options: .regularExpression)
                for match in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
                    guard let range = Range(match.range(at: 1), in: html) else { continue }
                    let link = String(html[range])
                    if link.isEmpty || link.hasPrefix("#") || link.range(of: "^[a-zA-Z]+:", options: .regularExpression) != nil {
                        continue
                    }
                    let file = link.split(separator: "#").first.map(String.init) ?? link
                    let target = url.deletingLastPathComponent()
                        .appendingPathComponent(file.removingPercentEncoding ?? file).standardizedFileURL
                    if !FileManager.default.fileExists(atPath: target.path),
                       let path = book.path(for: target), !knownBroken.contains(path) {
                        broken.append("\(book.path(for: url) ?? url.path) → \(link)")
                    }
                }
            }
        }
        XCTAssertGreaterThan(pages, 700)
        XCTAssertEqual(broken, [])
        // Mac 版のページから原版のページへ
        let mac = try String(contentsOf: book.url(for: "HelpMac.html"), encoding: .utf8)
        XCTAssertTrue(mac.contains("sakura/res/dsk_sakura.css"))
        XCTAssertTrue(exists("sakura/res/dsk_sakura.css"))
    }

    // MARK: - 話題（原版 FuncID_To_HelpContextID）

    func testFunctionTopics() {
        XCTAssertEqual(book.path(forFunction: 30101), "sakura/res/HLP000025.html")	// F_FILENEW 新規作成
        XCTAssertEqual(book.path(forFunction: 30901), "sakura/res/HLP000059.html")	// F_SEARCH_DIALOG
        XCTAssertEqual(book.path(forFunction: 31440), "sakura/res/HLP000100.html")	// F_HELP_CONTENTS
        XCTAssertNil(book.path(forFunction: 0))
        XCTAssertEqual(book.title(of: "sakura/res/HLP000025.html"), "新規作成")
    }

    /// 「ヘルプ」ボタンのある对话框、設定ウィンドウの全部のページに、原版と同じページがある
    func testEveryDialogHasHelpPage() throws {
        var dialogsWithButton: [String] = []
        for resource in ["CommonSettingsDialogs", "TypeSettingsDialogs", "GrepDialogs", "OutlineDialogs", "EditSupportDialogs",
                         "PrintDialogs", "FileSafetyDialogs"] {
            let dialogs = try XCTUnwrap(PropDialogs.load(resource), resource)
            for page in dialogs.pages {
                XCTAssertNotNil(HelpTopics.path(forDialog: page.dialog), page.dialog)	// 設定ウィンドウの「?」
            }
            for page in dialogs.pages + (dialogs.dialogs ?? []) where page.controls.contains(where: { $0.id == "IDC_BUTTON_HELP" }) {
                dialogsWithButton.append(page.dialog)
                let path = try XCTUnwrap(HelpTopics.path(forDialog: page.dialog), page.dialog)
                XCTAssertTrue(exists(path), path)
            }
        }
        XCTAssertEqual(dialogsWithButton.count, 13)
        // 原版と同じページ
        XCTAssertEqual(HelpTopics.path(forDialog: "IDD_GREP"), "sakura/res/HLP000067.html")
        XCTAssertEqual(HelpTopics.path(forDialog: "IDD_WINPOSSIZE"), "sakura/res/HLP000286.html")
        XCTAssertEqual(HelpTopics.path(forDialog: "IDD_PROP_GENERAL"), "sakura/res/HLP000081.html")
        XCTAssertEqual(HelpTopics.path(forDialog: "IDD_PROP_COLOR"), book.path(forTopic: 75))
        for dialog in ["IDD_FIND", "IDD_REPLACE", "IDD_JUMP"] {
            XCTAssertNotNil(HelpTopics.path(forDialog: dialog), dialog)
        }
    }

    /// 对话框的「ヘルプ」ボタン：押すとそのダイアログのページ
    func testHelpButtonOpensDialogPage() throws {
        let definition = try XCTUnwrap(PropDialogs.load("GrepDialogs")?.dialog("IDD_GREP"))
        let page = PropPage(definition: definition)
        var other: [String] = []
        page.onButton = { other.append($0) }
        XCTAssertTrue(page.isEnabled("IDC_BUTTON_HELP"))
        let button = try XCTUnwrap(page.control("IDC_BUTTON_HELP") as? NSButton)
        button.performClick(nil)
        XCTAssertEqual(opened, ["sakura/res/HLP000067.html"])
        XCTAssertEqual(other, [], "ヘルプはダイアログの処理に渡さない")
        XCTAssertEqual(HelpWindowController.current?.window?.isVisible, true)
    }

    /// 設定ウィンドウの「?」：表示しているページのヘルプ（原版 PSN_HELP）
    func testSettingsWindowHelpButton() throws {
        let store = CommonSettingsTests.FakeStore()
        let probe = try XCTUnwrap(CommonSettingsWindowController(store: store))
        let index = try XCTUnwrap(probe.pageIndex(named: "編集"))
        probe.cancel(nil)
        let controller = try XCTUnwrap(CommonSettingsWindowController(store: store, page: index))
        defer { controller.cancel(nil) }
        func find(_ view: NSView?) -> NSView? {
            guard let view else { return nil }
            if view.accessibilityIdentifier() == "CommonSettingsHelp" { return view }
            return view.subviews.lazy.compactMap(find).first
        }
        let help = try XCTUnwrap(find(controller.window?.contentView) as? NSButton)
        XCTAssertEqual(help.bezelStyle, .helpButton)
        help.performClick(nil)
        XCTAssertEqual(opened, [try XCTUnwrap(book.path(forFunction: 32002))])	// F_OPTION_EDIT：HLP000144
        XCTAssertEqual(opened, ["sakura/res/HLP000144.html"])
    }

    // MARK: - 控件の説明（右クリック）

    func testContextHelpTextsAreOriginal() throws {
        XCTAssertEqual(book.popupText(dialog: "IDD_FIND", control: "IDC_CHK_WORD"),
                       "【単語単位で探す】\n\n検索するときに単語単位にするかどうか指定します。")
        XCTAssertNil(book.popupText(dialog: "IDD_FIND", control: "IDC_NONE"))
        XCTAssertGreaterThan(book.dialogsWithPopups.count, 50)
        // Mac 版の対話框の控件：原版に説明がある控件は全部説明が出る
        var covered = 0
        for resource in ["CommonSettingsDialogs", "TypeSettingsDialogs", "GrepDialogs", "OutlineDialogs", "EditSupportDialogs",
                         "PrintDialogs"] {
            for page in (PropDialogs.load(resource)?.pages ?? []) + (PropDialogs.load(resource)?.dialogs ?? []) {
                for (id, _) in book.controlIDs(of: page.dialog) where page.controls.contains(where: { $0.id == id }) {
                    if book.popupText(dialog: page.dialog, control: id) != nil { covered += 1 }
                }
            }
        }
        XCTAssertGreaterThan(covered, 500)
    }

    /// 右クリックした控件の説明を弹出框で表示する
    func testRightClickShowsContextHelp() throws {
        let definition = try XCTUnwrap(PropDialogs.load("GrepDialogs")?.dialog("IDD_GREP"))
        let page = PropPage(definition: definition)
        let window = NSWindow(contentRect: page.view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = page.view
        window.orderFront(nil)
        defer { window.close() }
        let check = try XCTUnwrap(page.control("IDC_CHK_WORD"))
        let point = page.view.convert(NSPoint(x: check.frame.midX, y: check.frame.midY), to: nil)
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseDown, location: point, modifierFlags: [], timestamp: 0,
                                                     windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                                                     clickCount: 1, pressure: 1))
        page.view.rightMouseDown(with: event)
        XCTAssertEqual(ContextHelp.shownText, book.popupText(dialog: "IDD_GREP", control: "IDC_CHK_WORD"))
        XCTAssertTrue(ContextHelp.shownText?.hasPrefix("【") ?? false)
        // 説明のない所（ラベル）では出ない
        ContextHelp.close()
        XCTAssertFalse(ContextHelp.show(at: NSPoint(x: -10, y: -10), in: page.view) { _ in "x" })
        XCTAssertNil(ContextHelp.shownText)
    }

    // MARK: - Mac 版の注記

    func testNotesForMacVersion() {
        // Mac 版にない機能（メニューで灰色）のページ：外部HTMLヘルプ（F_EXTHTMLHELP → HLP000191）
        let external = book.path(forFunction: 31451) ?? ""
        XCTAssertTrue(book.unavailablePaths.contains(external), external)
        XCTAssertEqual(book.note(for: external), book.unavailableNote)
        // ある機能のページには出ない
        XCTAssertFalse(book.unavailablePaths.contains("sakura/res/HLP000025.html"))
        XCTAssertNil(book.note(for: "sakura/res/HLP000025.html"))
        // 手書きの注記（mac_notes.json）
        XCTAssertTrue(book.note(for: "sakura/res/HLP000003.html")?.contains("Apple シリコン") ?? false)
        XCTAssertTrue(book.note(for: "sakura/res/HLP000110.html")?.contains("プラグイン") ?? false)
        // 注記は HTML の断片：閉じていないタグがない
        for (path, note) in book.allNotes {
            XCTAssertEqual(note.components(separatedBy: "<a ").count, note.components(separatedBy: "</a>").count, path)
        }
    }

    // MARK: - ヘルプ窗口

    private func waitForPage(_ help: HelpWindowController, _ action: () -> Void) {
        let loaded = expectation(description: "page")
        help.onPageLoad = { _ in loaded.fulfill() }
        action()
        wait(for: [loaded], timeout: 15)
        help.onPageLoad = nil
    }

    private func evaluate(_ help: HelpWindowController, _ script: String) throws -> Any? {
        let done = expectation(description: "js")
        var value: Any?
        help.webView.evaluateJavaScript(script) { result, _ in
            value = result
            done.fulfill()
        }
        wait(for: [done], timeout: 10)
        return value
    }

    private func newWindow() -> HelpWindowController {
        HelpWindowController.current?.close()
        return HelpWindowController(book: book)
    }

    /// ページを開くと、目次でそのページを選ぶ（HTML Help の自動同期）
    func testShowPageSyncsContents() throws {
        let help = newWindow()
        defer { help.close() }
        waitForPage(help) { help.show(path: "sakura/res/HLP000025.html") }
        XCTAssertEqual(help.currentPath, "sakura/res/HLP000025.html")
        XCTAssertEqual(help.selectedContentsTitle, "新規作成")
        XCTAssertEqual(try evaluate(help, "document.title") as? String, "新規作成")
        XCTAssertEqual(help.window?.title, "サクラエディタ ヘルプ")
        // 目次をクリック：そのページ
        waitForPage(help) { XCTAssertTrue(help.selectContents(titled: "開く")) }
        XCTAssertEqual(help.currentPath, "sakura/res/HLP000015.html")
        // 戻る・進む・ホーム
        waitForPage(help) { help.goBack(nil) }
        XCTAssertEqual(help.currentPath, "sakura/res/HLP000025.html")
        waitForPage(help) { help.goForward(nil) }
        XCTAssertEqual(help.currentPath, "sakura/res/HLP000015.html")
        waitForPage(help) { help.goHome(nil) }
        XCTAssertEqual(help.currentPath, "sakura/res/HLP000001.html")
        XCTAssertEqual(help.selectedContentsTitle, "サクラエディタ ヘルプ目次")
        // 非表示・表示
        XCTAssertFalse(help.isNavigationHidden)
        help.toggleNavigation(nil)
        XCTAssertTrue(help.isNavigationHidden)
        help.toggleNavigation(nil)
        XCTAssertFalse(help.isNavigationHidden)
    }

    /// Mac 版の注記がページの先頭に入る
    func testNoteIsInsertedInPage() throws {
        let help = newWindow()
        defer { help.close() }
        let external = try XCTUnwrap(book.path(forFunction: 31451))
        waitForPage(help) { help.show(path: external) }
        let text = try evaluate(help, "var n = document.getElementById('sakura-mac-note'); n ? n.textContent : ''") as? String
        XCTAssertTrue(text?.contains("Mac 版にはこの機能はありません") ?? false, text ?? "")
        XCTAssertEqual(try evaluate(help, "document.body.firstElementChild.id") as? String, "sakura-mac-note")
        // 注記のないページ
        waitForPage(help) { help.show(path: "sakura/res/HLP000025.html") }
        XCTAssertEqual(try evaluate(help, "document.getElementById('sakura-mac-note') === null") as? Bool, true)
        // 目次の先頭：Mac 版のページ（原版のスタイル）
        waitForPage(help) { help.show(path: "HelpMac.html") }
        XCTAssertEqual(try evaluate(help, "document.title") as? String, "Mac 版について")
        // 原版の dsk_sakura.css が効いている（BODY の background-color: #fff。CSS がないときは透明）
        XCTAssertEqual(try evaluate(help, "getComputedStyle(document.body).backgroundColor") as? String, "rgb(255, 255, 255)")
        XCTAssertEqual(help.selectedContentsTitle, "Mac 版について")
    }

    /// 帮助以外のリンクはブラウザで開く。帮助の中のリンクはヘルプ窗口で
    func testLinks() throws {
        var external: [URL] = []
        HelpWindowController.openExternal = { external.append($0) }
        let help = newWindow()
        defer { help.close() }
        waitForPage(help) { help.show(path: "sakura/res/HLP000001.html") }
        waitForPage(help) { _ = try? self.evaluate(help, "document.querySelector('a[href=\"HLP000002.html\"]').click(); 1") }
        XCTAssertEqual(help.currentPath, "sakura/res/HLP000002.html")
        waitForPage(help) { help.goBack(nil) }
        _ = try evaluate(help, "document.querySelector('a[href^=\"https://sakura-editor.github.io\"]').click(); 1")
        let deadline = Date().addingTimeInterval(5)
        while external.isEmpty && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        XCTAssertEqual(external.first?.host, "sakura-editor.github.io")
        XCTAssertEqual(help.currentPath, "sakura/res/HLP000001.html", "ヘルプ窗口のページは変わらない")
    }

    /// キーワード：入力した文字で始まるキーワードを選び、「表示」でそのページ
    func testIndexTab() throws {
        let help = newWindow()
        defer { help.close() }
        help.show(path: book.home, tab: .index)
        XCTAssertEqual(help.selectedTab, .index)
        XCTAssertNotNil(help.selectIndex(matching: "grep置"))
        XCTAssertEqual(help.selectedIndexKeyword, "Grep置換")
        waitForPage(help) { help.showIndexTopic(nil) }
        XCTAssertEqual(help.currentPath, book.path(forFunction: 30912))	// F_GREP_REPLACE_DLG
        // いくつかの話題があるキーワード：「トピックの選択」
        let entry = try XCTUnwrap(book.index.first { $0.topics.count > 1 })
        var offered: [HelpBook.Topic] = []
        help.chooseTopic = { topics, _ in
            offered = topics
            return topics.last
        }
        XCTAssertNotNil(help.selectIndex(matching: entry.keyword))
        waitForPage(help) { help.showIndexTopic(nil) }
        XCTAssertEqual(offered, entry.topics)
        XCTAssertEqual(help.currentPath, entry.topics.last?.path)
    }

    /// 検索：全部の語を含むページ（全角・半角、大文字・小文字は区別しない）
    func testSearchTab() throws {
        XCTAssertTrue(book.search("インクリメンタルサーチ").contains { $0.path.contains("HLP000") })
        XCTAssertEqual(book.search("ｇｒｅｐ").map(\.path), book.search("GREP").map(\.path))
        XCTAssertTrue(book.search("存在しない語ｘｙｚｗ").isEmpty)
        XCTAssertTrue(book.search("   ").isEmpty)
        let both = book.search("Grep 置換")
        XCTAssertFalse(both.isEmpty)
        XCTAssertTrue(both.count <= book.search("Grep").count)
        // 原版のマクロのヘルプも
        XCTAssertTrue(book.search("ExpandParameter").contains { $0.path.hasPrefix("macro/") })

        let help = newWindow()
        defer { help.close() }
        help.show(path: book.home)
        help.search("タグジャンプ")
        XCTAssertEqual(help.selectedTab, .search)
        XCTAssertFalse(help.searchResultTitles.isEmpty)
        help.selectSearchResult(0)
        waitForPage(help) { help.showSearchResult(nil) }
        XCTAssertEqual(help.currentPath, book.search("タグジャンプ").first?.path)
    }

    // MARK: - ヘルプ メニュー

    func testHelpMenuCommands() throws {
        XCTAssertNotNil(CommandTable.selector(for: 31440))	// F_HELP_CONTENTS
        XCTAssertNotNil(CommandTable.selector(for: 31441))	// F_HELP_SEARCH
        XCTAssertNotNil(CommandTable.selector(for: 31445))	// F_MENU_ALLFUNC
        XCTAssertNil(CommandTable.selector(for: 31450), "外部ヘルプ１は Windows のヘルプ")
        XCTAssertNil(CommandTable.selector(for: 31451), "外部HTMLヘルプは Windows のヘルプ")
        HelpWindowController.current?.close()
        NSApp.showHelpContents(nil)
        let help = try XCTUnwrap(HelpWindowController.current)
        XCTAssertEqual(help.selectedTab, .contents)
        XCTAssertEqual(help.window?.isVisible, true)
        NSApp.showHelpSearch(nil)
        XCTAssertEqual(help.selectedTab, .index)
        XCTAssertTrue(HelpWindowController.shared() === help, "ヘルプ窗口はひとつ")
        // 模态的对话框からも使える
        XCTAssertEqual(help.window?.worksWhenModal, true)
    }

    /// コマンド一覧：原版の「種別」ごとのサブメニュー
    func testAllFunctionsMenu() throws {
        let editor = try XCTUnwrap(EditorCommandSettingsEditor())
        let menu = EditorTextView.allFunctionsMenu()
        XCTAssertEqual(menu.items.map(\.title), editor.functionCategories)
        let file = try XCTUnwrap(menu.items.first?.submenu)
        let new = try XCTUnwrap(file.items.first { $0.tag == 30101 })
        XCTAssertEqual(new.title, editor.name(ofFunction: 30101))
        XCTAssertEqual(new.action, CommandTable.selector(for: 30101))
        // Mac 版にない機能は動作なし（灰色）
        let all = menu.items.compactMap(\.submenu).flatMap(\.items)
        XCTAssertGreaterThan(all.count, 300)
        for item in all { XCTAssertEqual(item.action, CommandTable.selector(for: item.tag), item.title) }

        // 编辑区から：メニューを出す
        let document = try XCTUnwrap(EditorDocument())
        let view = EditorTextView(document: document)
        view.frame = NSRect(x: 0, y: 0, width: 800, height: 400)
        var shown: NSMenu?
        let saved = EditorTextView.popUpAllFunctions
        EditorTextView.popUpAllFunctions = { menu, _, _ in shown = menu }
        defer { EditorTextView.popUpAllFunctions = saved }
        XCTAssertTrue(CommandTable.perform(31445, from: view))
        XCTAssertEqual(shown?.items.count, editor.functionCategories.count)
    }

    /// macOS の帮助菜单的搜索栏：キーワードを探してページを開く
    func testHelpMenuSearch() throws {
        let items = HelpMenuSearch.items(matching: "grep", limit: 20, book: book)
        XCTAssertFalse(items.isEmpty)
        XCTAssertTrue(items.allSatisfy { exists($0.path) })
        XCTAssertEqual(Set(items.map(\.path)).count, items.count, "同じページは一度だけ")
        XCTAssertEqual(HelpMenuSearch.items(matching: "grep", limit: 2, book: book).count, 2)
        XCTAssertTrue(HelpMenuSearch.items(matching: "", limit: 10, book: book).isEmpty)
        XCTAssertEqual(HelpMenuSearch.shared.localizedTitles(forItem: items[0]), [items[0].title])
        HelpMenuSearch.shared.performAction(forItem: items[0])
        let deadline = Date().addingTimeInterval(5)
        while opened.isEmpty && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        XCTAssertEqual(opened, [items[0].path])
    }
}

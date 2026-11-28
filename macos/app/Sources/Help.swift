// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge

/// ヘルプ（计划第 49 步）。
///
/// 原版的 HTML 帮助（help/sakura = sakura.chm、help/macro = macro.chm）的 HTML 原样放在 App 里
/// （project.yml 的文件夹引用，bundle 的 Resources/sakura/、Resources/macro/），
/// 目次・キーワード・话题编号・控件的说明是 macos/tools/help/make_help_data.py 从原版的工程文件生成的 HelpTopics.json。
/// Mac 不支持 CHM（已确认的偏离项 8），用 App 自己的ヘルプ窗口（HelpWindow.swift）显示。
///
/// 原版的入口和 Mac 版：
/// - ヘルプ > ヘルプ目次（F_HELP_CONTENTS）、キーワード検索（F_HELP_SEARCH）：ヘルプ窗口的「目次」「キーワード」
/// - ヘルプ > コマンド一覧（F_MENU_ALLFUNC）：全部功能的弹出菜单（原版 Command_MENU_ALLFUNC）
/// - 对话框的「ヘルプ」按钮、属性表的ヘルプ（PSN_HELP）：那个对话框的页（原版 MyWinHelp の HELP_CONTEXT）
/// - 控件上右键（原版 HELP_CONTEXTMENU）：控件的说明（Cshelp.txt）的弹出框
/// - macOS 的帮助菜单的搜索栏：キーワード 也能搜（NSUserInterfaceItemSearching）
/// - 原版的菜单上按 F1 打开那个命令的页：macOS 的菜单打开时 App 收不到按键，Mac 版没有（帮助菜单的搜索代替）
final class HelpBook {
    struct Node {
        let title: String
        /// App 里的路径（sakura/res/HLP000001.html#c901）。没有页的目录是 nil
        let path: String?
        let children: [Node]
    }

    struct Topic: Equatable {
        let title: String
        let path: String
    }

    struct IndexEntry {
        let keyword: String
        let level: Int
        let topics: [Topic]
    }

    /// 帮助的文件所在的文件夹（bundle 的 Resources）
    let root: URL
    let title: String
    /// 首页（ホーム。原版 sakura.hhp 的 Default topic）
    let home: String
    let toc: [Node]
    /// キーワード（按关键字排好的）
    let index: [IndexEntry]
    /// Mac 版的注记（mac_notes.json）：路径 → HTML
    let notes: [String: String]
    private let topics: [Int: String]
    private let popups: [Int: String]
    private let controls: [String: [String: Int]]

    /// App 的帮助（读不到 HelpTopics.json 时 nil）
    static let shared: HelpBook? = L10n.bundle.resourceURL.flatMap { HelpBook(root: $0) }

    init?(root: URL) {
        guard let data = try? Data(contentsOf: root.appendingPathComponent("HelpTopics.json")),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        self.root = root
        title = json["title"] as? String ?? ""
        home = json["home"] as? String ?? ""
        toc = Self.nodes(json["toc"])
        index = Self.sortedIndex(json["index"])
        notes = json["notes"] as? [String: String] ?? [:]
        unavailableNote = json["unavailableNote"] as? String ?? ""
        noteLabel = json["noteLabel"] as? String ?? ""
        topics = Self.intKeys(json["topics"] as? [String: String] ?? [:])
        popups = Self.intKeys(json["popups"] as? [String: String] ?? [:])
        controls = json["controls"] as? [String: [String: Int]] ?? [:]
    }

    private static func nodes(_ value: Any?) -> [Node] {
        (value as? [[String: Any]] ?? []).map {
            Node(title: $0["t"] as? String ?? "", path: $0["p"] as? String, children: nodes($0["c"]))
        }
    }

    private static func intKeys(_ dict: [String: String]) -> [Int: String] {
        Dictionary(uniqueKeysWithValues: dict.compactMap { key, value in Int(key).map { ($0, value) } })
    }

    /// HTML Help 的キーワード一覧と同じく、関键字の順に並べる（子の关键字は親の後ろのまま）
    private static func sortedIndex(_ value: Any?) -> [IndexEntry] {
        var groups: [[IndexEntry]] = []
        for item in value as? [[String: Any]] ?? [] {
            let topics = (item["p"] as? [[String] ] ?? []).compactMap { pair in
                pair.count == 2 ? Topic(title: pair[0], path: pair[1]) : nil
            }
            let entry = IndexEntry(keyword: item["k"] as? String ?? "", level: item["l"] as? Int ?? 0, topics: topics)
            if entry.level > 0, !groups.isEmpty {
                groups[groups.count - 1].append(entry)
            } else {
                groups.append([entry])
            }
        }
        let locale = Locale(identifier: "ja_JP")
        groups = groups.enumerated().sorted { a, b in
            let order = a.element[0].keyword.compare(b.element[0].keyword, options: [.caseInsensitive, .widthInsensitive],
                                                     range: nil, locale: locale)
            return order == .orderedSame ? a.offset < b.offset : order == .orderedAscending
        }.map(\.element)
        return groups.flatMap { $0 }
    }

    // MARK: 页

    /// 路径（"#…" 可以有）→ 文件的 URL
    func url(for path: String) -> URL {
        let parts = path.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let file = root.appendingPathComponent(String(parts[0]))
        guard parts.count == 2, var components = URLComponents(url: file, resolvingAgainstBaseURL: false) else { return file }
        components.fragment = String(parts[1])
        return components.url ?? file
    }

    /// 文件的 URL → 路径（帮助的文件夹外是 nil）。withFragment：页内的位置（#c901）也要
    func path(for url: URL, withFragment: Bool = false) -> String? {
        guard url.isFileURL else { return nil }
        let base = root.standardizedFileURL.path
        let file = url.standardizedFileURL.path
        guard file.hasPrefix(base + "/") else { return nil }
        var path = String(file.dropFirst(base.count + 1))
        if withFragment, let fragment = url.fragment, !fragment.isEmpty { path += "#" + fragment }
        return path
    }

    /// 话题编号（HLP000025 的 25）→ 页
    func path(forTopic id: Int) -> String? {
        topics[id]
    }

    /// 功能 → 页（原版 FuncID_To_HelpContextID）
    func path(forFunction code: Int) -> String? {
        let id = EditorCore.helpContextID(ofFunction: code)
        return id > 0 ? path(forTopic: id) : nil
    }

    /// 页的名字（目次、キーワード的名字。找不到时文件名）
    func title(of path: String) -> String {
        if let node = Self.find(toc, where: { $0.path == path }) { return node.title }
        let file = path.split(separator: "#").first.map(String.init) ?? path
        if let node = Self.find(toc, where: { $0.path == file }) { return node.title }
        return (file as NSString).lastPathComponent
    }

    static func find(_ nodes: [Node], where match: (Node) -> Bool) -> Node? {
        for node in nodes {
            if match(node) { return node }
            if let found = find(node.children, where: match) { return found }
        }
        return nil
    }

    // MARK: 控件的说明

    /// 对话框（IDD_FIND 等）的控件（IDC_CHK_WORD 等）的说明（原版 Cshelp.txt）
    func popupText(dialog: String, control: String) -> String? {
        guard let id = controls[dialog]?[control] else { return nil }
        return popups[id]
    }

    /// 有控件的说明的对话框（测试用）
    var dialogsWithPopups: [String] { controls.keys.sorted() }

    func controlIDs(of dialog: String) -> [String: Int] {
        controls[dialog] ?? [:]
    }

    // MARK: Mac 版没有的功能

    /// Mac 版没有的功能的页的注记（mac_notes.json 的 _unavailable。帮助的内容是日文，与原版相同）
    let unavailableNote: String
    /// 注记开头的标签（mac_notes.json 的 _label）
    let noteLabel: String

    /// Mac 版没有的功能（菜单里变灰：CommandTable 没有动作）的页。
    /// 这一页的功能（原版 FuncID_To_HelpContextID 指向这一页的功能）全部没有时
    private(set) lazy var unavailablePaths: Set<String> = {
        guard let editor = EditorCommandSettingsEditor() else { return [] }
        var available: [String: Bool] = [:]
        for category in 0..<editor.functionCategories.count {
            for number in editor.functionCodes(inCategory: category) {
                let code = number.intValue
                guard let path = path(forFunction: code)?.split(separator: "#").first.map(String.init) else { continue }
                available[path] = (available[path] ?? false) || CommandTable.selector(for: code) != nil
            }
        }
        return Set(available.filter { !$0.value }.keys)
    }()

    /// 插在页的开头的 Mac 版的注记（HTML）。没有时 nil
    func note(for path: String) -> String? {
        let file = path.split(separator: "#").first.map(String.init) ?? path
        var parts: [String] = []
        if unavailablePaths.contains(file) { parts.append(unavailableNote) }
        if let note = notes[file] { parts.append(note) }
        return parts.isEmpty ? nil : parts.joined(separator: "<br>")
    }

    /// 有注记的全部页（页的脚本用）
    var allNotes: [String: String] {
        var result: [String: String] = [:]
        for path in Set(notes.keys).union(unavailablePaths) {
            result[path] = note(for: path)
        }
        return result
    }

    // MARK: 検索（原版 HTML Help の「検索」タブ：全文検索）

    private struct PageText {
        let path: String
        let title: String
        let text: String
        let foldedTitle: String
    }

    private lazy var pageTexts: [PageText] = loadPageTexts()

    /// 全部的词都在页里的页（原版 HTML Help 的全文検索。大文字・小文字、全角・半角は区別しない）。
    /// 标题里有全部的词的页在前，其余按目次的顺序
    func search(_ query: String) -> [Topic] {
        let words = query.split(whereSeparator: { $0.isWhitespace }).map { Self.fold(String($0)) }
        guard !words.isEmpty else { return [] }
        let hits = pageTexts.filter { page in words.allSatisfy { page.text.contains($0) || page.foldedTitle.contains($0) } }
        let inTitle = hits.filter { page in words.allSatisfy { page.foldedTitle.contains($0) } }
        let rest = hits.filter { page in !words.allSatisfy { page.foldedTitle.contains($0) } }
        return (inTitle + rest).map { Topic(title: $0.title, path: $0.path) }
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "ja_JP"))
    }

    private func loadPageTexts() -> [PageText] {
        // 目次の順に、目次にないページはその後ろに
        var order: [String] = []
        var seen: Set<String> = []
        func walk(_ nodes: [Node]) {
            for node in nodes {
                if let path = node.path?.split(separator: "#").first.map(String.init), seen.insert(path).inserted {
                    order.append(path)
                }
                walk(node.children)
            }
        }
        walk(toc)
        for folder in ["sakura", "macro"] {
            let base = root.appendingPathComponent(folder)
            guard let files = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else { continue }
            var rest: [String] = []
            for case let url as URL in files where url.pathExtension.lowercased() == "html" {
                if let path = path(for: url), !seen.contains(path) { rest.append(path) }
            }
            for path in rest.sorted() where seen.insert(path).inserted { order.append(path) }
        }
        return order.compactMap { path in
            guard let data = try? Data(contentsOf: url(for: path)),
                  let html = String(data: data, encoding: .utf8) else { return nil }
            let title = Self.htmlTitle(html) ?? title(of: path)
            return PageText(path: path, title: title, text: Self.fold(Self.plainText(html)), foldedTitle: Self.fold(title))
        }
    }

    static func htmlTitle(_ html: String) -> String? {
        guard let range = html.range(of: "<title>(.*?)</title>", options: [.regularExpression, .caseInsensitive]) else { return nil }
        let title = html[range].replacingOccurrences(of: "</?title>", with: "", options: [.regularExpression, .caseInsensitive])
        let text = unescape(title).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// HTML → 文字（タグ、スクリプト、コメントを除く）
    static func plainText(_ html: String) -> String {
        var text = html.replacingOccurrences(of: "<!--.*?-->", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "<(script|style)[^>]*>.*?</\\1>", with: " ",
                                         options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "<[^>]*>", with: " ", options: .regularExpression)
        return unescape(text)
    }

    private static func unescape(_ text: String) -> String {
        var result = text
        for (entity, char) in [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&nbsp;", " "), ("&amp;", "&")] {
            result = result.replacingOccurrences(of: entity, with: char)
        }
        return result
    }
}

// MARK: - 对话框的「ヘルプ」按钮

enum HelpTopics {
    /// 对话框（原版的 IDD_*，Mac 版的布局 JSON 的 dialog）→ 原版的「ヘルプ」按钮打开的功能（FuncID_To_HelpContextID）。
    /// 原版各对话框的 OnBnClicked(IDC_BUTTON_HELP)
    static let dialogFunctions: [String: Int] = [
        "IDD_FIND": 30901,				// F_SEARCH_DIALOG（CDlgFind）
        "IDD_REPLACE": 30904,			// F_REPLACE_DIALOG（CDlgReplace）
        "IDD_JUMP": 30920,				// F_JUMP_DIALOG（CDlgJump）
        "IDD_GREP": 30910,				// F_GREP_DIALOG（CDlgGrep）
        "IDD_GREP_REPLACE": 30912,		// F_GREP_REPLACE_DLG（CDlgGrepReplace）
        "IDD_FUNCLIST": 30930,			// F_OUTLINE（CDlgFuncList）
        "IDD_FILETREE": 30990,			// F_FILETREE（CDlgFileTree）
        "IDD_DIFF": 30976,				// F_DIFF_DIALOG（CDlgDiff）
        "IDD_COMPARE": 30950,			// F_COMPARE（CDlgCompare）
        "IDD_TAGJUMPLIST": 30942,		// F_TAGJUMP_LIST（CDlgTagJumpList）
        "IDD_TAG_MAKE": 30943,			// F_TAGS_MAKE（CDlgTagsMake）
        "IDD_PRINTSETTING": 30152,		// F_PRINT_PAGESETUP（CDlgPrintSetting）
        "IDD_PRINTPREVIEWBAR": 30151,	// F_PRINT_PREVIEW（CPrintPreview）
        "IDD_TYPELIST": 31110,			// F_TYPE_LIST（CDlgTypeList）
        "IDD_SETCHARSET": 31010,		// F_CHG_CHARSET（CDlgSetCharSet）
        "IDD_CTRLCODE": 30792,			// F_CTRL_CODE_DIALOG（CDlgCtrlCode）
        "IDD_PROPERTY_FILE": 30190,		// F_PROPERTY_FILE（CDlgProperty）
        "IDD_EXEC": 31270,				// F_EXECMD_DIALOG（CDlgExec）
        "IDD_FAVORITE": 31113,			// F_FAVORITE（CDlgFavorite）
        "IDD_PROFILEMGR": 30191,		// F_PROFILEMGR（CDlgProfileMgr）
        "IDD_WINLIST": 31337,			// F_DLGWINLIST（CDlgWindowList）
        // 共通設定（CPropCommon::OnHelp）
        "IDD_PROP_GENERAL": 32000, "IDD_PROP_WIN": 32001, "IDD_PROP_EDIT": 32002, "IDD_PROP_FILE": 32003,
        "IDD_PROP_BACKUP": 32004, "IDD_PROP_FORMAT": 32005, "IDD_PROP_GREP": 32007, "IDD_PROP_KEYBIND": 32008,
        "IDD_PROP_CUSTMENU": 32009, "IDD_PROP_TOOLBAR": 32010, "IDD_PROP_KEYWORD": 32011, "IDD_PROP_HELPER": 32012,
        "IDD_PROP_MACRO": 32013, "IDD_PROP_FNAME": 32014, "IDD_PROP_TAB": 32015, "IDD_PROP_STATUSBAR": 32016,
        "IDD_PROP_PLUGIN": 32017, "IDD_PROP_MAINMENU": 32018,
        // タイプ別設定（CPropTypes::OnHelp）
        "IDD_PROP_SCREEN": 31115, "IDD_PROP_COLOR": 31116, "IDD_PROP_WINDOW": 31114, "IDD_PROP_SUPPORT": 31117,
        "IDD_PROP_REGEX": 31118, "IDD_PROP_KEYHELP": 31119,
    ]

    /// 话题编号を直接指定する对话框（原版 MyWinHelp(HELP_CONTEXT, HLP000xxx)）
    static let dialogTopics: [String: Int] = [
        "IDD_WINPOSSIZE": 286,		// CDlgWinSize：HLP000286 ウィンドウの位置と大きさ
        "IDD_SAMECOLOR": 316,		// CDlgSameColor：HLP000316
        "IDD_TYPE_ASCERTAIN": 338,	// CDlgTypeAscertain：HLP000338
        "IDD_PLUGIN_OPTION": 153,	// CDlgPluginOption：HLP000153
    ]

    /// 这个对话框的「ヘルプ」打开的页
    static func path(forDialog dialog: String, book: HelpBook? = HelpBook.shared) -> String? {
        guard let book else { return nil }
        if let topic = dialogTopics[dialog] { return book.path(forTopic: topic) }
        if let code = dialogFunctions[dialog] { return book.path(forFunction: code) }
        return nil
    }
}

// MARK: - 控件的说明（右键）

/// 控件的说明（原版 MyWinHelp の HELP_CONTEXTMENU：控件上右键，弹出 Cshelp.txt 的说明）。
/// Mac 版用弹出框（NSPopover）显示。原版的标题栏的「？」按钮 Mac 没有
enum ContextHelp {
    /// 显示着的弹出框
    private(set) static var popover: NSPopover?
    /// 显示着的文字（测试用）
    static var shownText: String? { popover?.isShown == true ? text : nil }
    private static var text: String?

    static func show(_ text: String, for view: NSView) {
        popover?.close()
        let width: CGFloat = 320
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.isSelectable = false
        label.setAccessibilityIdentifier("ContextHelp")
        let size = label.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: 10000))
            ?? NSSize(width: width, height: 60)
        let inset: CGFloat = 10
        let container = NSView(frame: NSRect(x: 0, y: 0, width: ceil(size.width) + inset * 2, height: ceil(size.height) + inset * 2))
        label.frame = NSRect(x: inset, y: inset, width: ceil(size.width), height: ceil(size.height))
        container.addSubview(label)
        let controller = NSViewController()
        controller.view = container
        let popover = NSPopover()
        popover.contentViewController = controller
        popover.behavior = .transient
        popover.animates = false
        popover.show(relativeTo: view.bounds, of: view, preferredEdge: .maxY)
        self.popover = popover
        self.text = text
        // Esc は説明だけを閉じる（原版のポップアップヘルプと同じ。ダイアログは閉じない）
        if escMonitor == nil {
            escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard event.keyCode == 53, ContextHelp.popover?.isShown == true else { return event }
                ContextHelp.close()
                return nil
            }
        }
    }

    private static var escMonitor: Any?

    static func close() {
        popover?.close()
        popover = nil
        text = nil
        if let monitor = escMonitor {
            NSEvent.removeMonitor(monitor)
            escMonitor = nil
        }
    }

    /// 右键的位置（container 的直接的子视图）的控件的说明。有说明时显示，返回 true
    static func handleRightClick(in container: NSView, event: NSEvent, text: (NSView) -> String?) -> Bool {
        let point = container.convert(event.locationInWindow, from: nil)
        return show(at: point, in: container, text: text)
    }

    /// point（container 的坐标）的控件的说明
    @discardableResult
    static func show(at point: NSPoint, in container: NSView, text: (NSView) -> String?) -> Bool {
        // 上に重なっている（後から加えた）控件が先。组框（NSBox）は中の控件の後
        for view in container.subviews.reversed() where !view.isHidden && view.frame.contains(point) {
            if let help = text(view) {
                show(help, for: view)
                return true
            }
        }
        return false
    }
}

// MARK: - macOS 的帮助菜单的搜索栏

/// ヘルプメニューの検索欄（macOS が NSApp.helpMenu に付ける）で、メニュー項目と一緒にヘルプのキーワードも探す。
/// 選んだらそのページを開く（原版の「キーワード検索」の代わりの入口のひとつ）
final class HelpMenuSearch: NSObject, NSUserInterfaceItemSearching {
    static let shared = HelpMenuSearch()

    /// 検索結果の一項目
    final class Item: NSObject {
        let title: String
        let path: String
        init(title: String, path: String) {
            self.title = title
            self.path = path
        }
    }

    /// 入力した語を含むキーワード（同じページは一度だけ）
    static func items(matching text: String, limit: Int, book: HelpBook? = HelpBook.shared) -> [Item] {
        let query = text.trimmingCharacters(in: .whitespaces)
        guard let book, !query.isEmpty, limit > 0 else { return [] }
        var result: [Item] = []
        var seen: Set<String> = []
        for entry in book.index where entry.keyword.range(of: query, options: [.caseInsensitive, .widthInsensitive]) != nil {
            for topic in entry.topics where seen.insert(topic.path).inserted {
                result.append(Item(title: entry.topics.count == 1 ? entry.keyword : "\(entry.keyword) - \(topic.title)",
                                   path: topic.path))
                if result.count >= limit { return result }
            }
        }
        return result
    }

    func searchForItems(withSearch searchString: String, resultLimit: Int,
                        matchedItemHandler handleMatchedItems: @escaping ([Any]) -> Void) {
        handleMatchedItems(Self.items(matching: searchString, limit: resultLimit))
    }

    func localizedTitles(forItem item: Any) -> [String] {
        [(item as? Item)?.title ?? ""]
    }

    func performAction(forItem item: Any) {
        guard let item = item as? Item else { return }
        DispatchQueue.main.async { HelpViewer.show(path: item.path) }
    }
}

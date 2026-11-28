// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge
import WebKit

/// ヘルプ窗口（计划第 49 步。原版的 HTML Help ビューア：sakura.hhp の XHP ウィンドウ）。
///
/// 与原版的 HTML Help 相同的构成：上面是「非表示」「戻る」「進む」「ホーム」「印刷」，
/// 左边是「目次」「キーワード」「検索」三个标签，右边是页。打开页时目次里选中那一页（HTML Help の自動同期）。
/// 一个 App 一个窗口（原版的 HTML Help ビューアもひとつ）。
/// 页的开头插入 Mac 版的注记（HelpBook.note），帮助以外的链接（https 等）用浏览器打开。
final class HelpWindowController: NSWindowController, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate,
                                  NSOutlineViewDataSource, NSOutlineViewDelegate,
                                  NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    enum Tab: Int {
        case contents = 0, index, search
    }

    private static var instance: HelpWindowController?

    /// 窗口（没有时做）
    static func shared(book: HelpBook? = HelpBook.shared) -> HelpWindowController? {
        if let instance { return instance }
        guard let book else { return nil }
        instance = HelpWindowController(book: book)
        return instance
    }

    /// 窗口已经做好时（测试用）
    static var current: HelpWindowController? { instance }

    let book: HelpBook
    let webView: WKWebView
    private let tabView = NSTabView()
    private let splitView = NSSplitView()
    private let navigation = NSView()
    private let contentsOutline = NSOutlineView()
    private let indexField = NSSearchField()
    private let indexTable = NSTableView()
    private let searchField = NSSearchField()
    private let searchTable = NSTableView()
    private let hideButton = NSButton()
    private let backButton = NSButton()
    private let forwardButton = NSButton()
    private var searchResults: [HelpBook.Topic] = []
    /// 目次の選択を页に合わせているとき（选择的变化不再打开页）
    private var syncingContents = false

    /// 显示着的页（帮助的文件夹里的路径，包括 #…）
    private(set) var currentPath: String?
    /// 页读完了（测试用）
    var onPageLoad: ((String?) -> Void)?
    /// 一个キーワード有几个话题时选一个（原版 HTML Help の「トピックの選択」。测试换掉）
    var chooseTopic: ([HelpBook.Topic], NSView) -> HelpBook.Topic? = HelpWindowController.chooseTopicWithMenu

    init(book: HelpBook) {
        self.book = book
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(
            WKUserScript(source: Self.noteScript(book: book), injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        webView = WKWebView(frame: .zero, configuration: configuration)
        // 原版 sakura.hhp の XHP ウィンドウ：[50,50,850,550]（800×500）、ナビゲーションの幅 200
        // 模态的对话框（runModal）的「ヘルプ」で開いたときも操作できるように NSPanel（worksWhenModal）。
        // 原版の HTML Help もダイアログとは別のウィンドウで、ダイアログを開いたまま読める
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 900, height: 620),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.worksWhenModal = true
        window.hidesOnDeactivate = false
        window.isFloatingPanel = false
        window.becomesKeyOnlyIfNeeded = false
        window.title = L10n.tr("サクラエディタ ヘルプ", comment: "ヘルプ窗口的标题（sakura.hhp の Title）")
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 520, height: 320)
        window.setAccessibilityIdentifier("Help")
        super.init(window: window)
        window.delegate = self
        build(in: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: 生成

    private func build(in window: NSWindow) {
        let content = NSView()
        window.contentView = content

        // 上面的按钮（原版 HTML Help のツールバー：非表示・戻る・進む・ホーム・印刷。0x1384e 的按钮）
        let bar = NSStackView()
        bar.orientation = .horizontal
        bar.spacing = 6
        bar.translatesAutoresizingMaskIntoConstraints = false
        configure(hideButton, L10n.tr("非表示", comment: "ヘルプ窗口：目次を隠す"), "sidebar.left", "HelpHide", #selector(toggleNavigation(_:)))
        configure(backButton, L10n.tr("戻る", comment: "ヘルプ窗口"), "chevron.left", "HelpBack", #selector(goBack(_:)))
        configure(forwardButton, L10n.tr("進む", comment: "ヘルプ窗口"), "chevron.right", "HelpForward", #selector(goForward(_:)))
        let homeButton = NSButton(), printButton = NSButton()
        configure(homeButton, L10n.tr("ホーム", comment: "ヘルプ窗口"), "house", "HelpHome", #selector(goHome(_:)))
        configure(printButton, L10n.tr("印刷", comment: "ヘルプ窗口"), "printer", "HelpPrint", #selector(printPage(_:)))
        for button in [hideButton, backButton, forwardButton, homeButton, printButton] { bar.addArrangedSubview(button) }
        content.addSubview(bar)

        // 左：目次・キーワード・検索
        tabView.translatesAutoresizingMaskIntoConstraints = false
        tabView.controlSize = .small
        tabView.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        tabView.setAccessibilityIdentifier("HelpTabs")
        tabView.addTabViewItem(tab(L10n.tr("目次", comment: "ヘルプ窗口的标签"), contentsPane()))
        tabView.addTabViewItem(tab(L10n.tr("キーワード", comment: "ヘルプ窗口的标签"), indexPane()))
        tabView.addTabViewItem(tab(L10n.tr("検索", comment: "ヘルプ窗口的标签"), searchPane()))
        navigation.addSubview(tabView)
        NSLayoutConstraint.activate([
            tabView.leadingAnchor.constraint(equalTo: navigation.leadingAnchor, constant: 4),
            tabView.trailingAnchor.constraint(equalTo: navigation.trailingAnchor, constant: -2),
            tabView.topAnchor.constraint(equalTo: navigation.topAnchor),
            tabView.bottomAnchor.constraint(equalTo: navigation.bottomAnchor, constant: -4),
        ])

        // 右：页
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.setAccessibilityIdentifier("HelpPage")

        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.translatesAutoresizingMaskIntoConstraints = false
        splitView.addArrangedSubview(navigation)
        splitView.addArrangedSubview(webView)
        splitView.setHoldingPriority(.defaultHigh, forSubviewAt: 0)
        content.addSubview(splitView)
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 8),
            bar.topAnchor.constraint(equalTo: content.topAnchor, constant: 6),
            splitView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            splitView.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 6),
            splitView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            navigation.widthAnchor.constraint(greaterThanOrEqualToConstant: 160),
        ])
        content.layoutSubtreeIfNeeded()
        splitView.setPosition(250, ofDividerAt: 0)
        updateButtons()
    }

    private func configure(_ button: NSButton, _ title: String, _ symbol: String, _ id: String, _ action: Selector) {
        button.title = title
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        button.imagePosition = .imageLeading
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        button.target = self
        button.action = action
        button.setAccessibilityIdentifier(id)
    }

    private func tab(_ label: String, _ view: NSView) -> NSTabViewItem {
        let item = NSTabViewItem(identifier: label)
        item.label = label
        item.view = view
        return item
    }

    private func scroll(_ table: NSTableView, id: String, column: String) -> NSScrollView {
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column))
        col.resizingMask = .autoresizingMask
        table.addTableColumn(col)
        table.headerView = nil
        table.rowHeight = 18
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        if !(table is NSOutlineView) {
            table.dataSource = self
            table.delegate = self
        }
        table.target = self
        table.setAccessibilityIdentifier(id)
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        return scroll
    }

    private func contentsPane() -> NSView {
        let pane = NSView()
        let scroll = self.scroll(contentsOutline, id: "HelpContents", column: "title")
        contentsOutline.outlineTableColumn = contentsOutline.tableColumns.first
        contentsOutline.dataSource = self
        contentsOutline.delegate = self
        contentsOutline.indentationPerLevel = 14
        contentsOutline.action = #selector(contentsClicked(_:))
        pane.addSubview(scroll)
        pin(scroll, in: pane)
        return pane
    }

    private func indexPane() -> NSView {
        let pane = NSView()
        let label = NSTextField(labelWithString: L10n.tr("検索するキーワードを入力してください:", comment: "ヘルプ窗口：キーワード"))
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        indexField.delegate = self
        indexField.sendsSearchStringImmediately = false
        indexField.sendsWholeSearchString = true
        indexField.setAccessibilityIdentifier("HelpIndexField")
        indexField.target = self
        indexField.action = #selector(indexFieldEntered(_:))
        let scroll = self.scroll(indexTable, id: "HelpIndexList", column: "keyword")
        indexTable.doubleAction = #selector(showIndexTopic(_:))
        let display = NSButton(title: L10n.tr("表示", comment: "ヘルプ窗口：キーワード・検索のトピックを表示"),
                               target: self, action: #selector(showIndexTopic(_:)))
        display.setAccessibilityIdentifier("HelpIndexDisplay")
        stack(pane, [label, indexField, scroll, display], grow: scroll)
        return pane
    }

    private func searchPane() -> NSView {
        let pane = NSView()
        let label = NSTextField(labelWithString: L10n.tr("検索する語を入力してください:", comment: "ヘルプ窗口：検索"))
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        searchField.setAccessibilityIdentifier("HelpSearchField")
        searchField.sendsWholeSearchString = true
        searchField.target = self
        searchField.action = #selector(runSearch(_:))
        let run = NSButton(title: L10n.tr("検索", comment: "ヘルプ窗口：検索を開始"), target: self, action: #selector(runSearch(_:)))
        run.setAccessibilityIdentifier("HelpSearchButton")
        let scroll = self.scroll(searchTable, id: "HelpSearchResults", column: "title")
        searchTable.doubleAction = #selector(showSearchResult(_:))
        let display = NSButton(title: L10n.tr("表示", comment: "ヘルプ窗口：キーワード・検索のトピックを表示"),
                               target: self, action: #selector(showSearchResult(_:)))
        display.setAccessibilityIdentifier("HelpSearchDisplay")
        stack(pane, [label, searchField, run, scroll, display], grow: scroll)
        return pane
    }

    private func pin(_ view: NSView, in pane: NSView) {
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: pane.leadingAnchor, constant: 4),
            view.trailingAnchor.constraint(equalTo: pane.trailingAnchor, constant: -4),
            view.topAnchor.constraint(equalTo: pane.topAnchor, constant: 4),
            view.bottomAnchor.constraint(equalTo: pane.bottomAnchor, constant: -4),
        ])
    }

    private func stack(_ pane: NSView, _ views: [NSView], grow: NSView) {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        pane.addSubview(stack)
        pin(stack, in: pane)
        for view in views where view is NSScrollView || view is NSSearchField {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        for view in views where view is NSButton {
            (view as? NSButton)?.bezelStyle = .rounded
            (view as? NSButton)?.controlSize = .small
            (view as? NSButton)?.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        }
        grow.setContentHuggingPriority(.defaultLow, for: .vertical)
    }

    // MARK: 显示

    /// 显示窗口和这一页
    func show(path: String, tab: Tab? = nil) {
        if let tab { selectTab(tab) }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        load(path)
    }

    func selectTab(_ tab: Tab) {
        tabView.selectTabViewItem(at: tab.rawValue)
        switch tab {
        case .contents: window?.makeFirstResponder(contentsOutline)
        case .index: window?.makeFirstResponder(indexField)
        case .search: window?.makeFirstResponder(searchField)
        }
    }

    var selectedTab: Tab {
        guard let item = tabView.selectedTabViewItem else { return .contents }
        return Tab(rawValue: tabView.indexOfTabViewItem(item)) ?? .contents
    }

    func load(_ path: String) {
        webView.loadFileURL(book.url(for: path), allowingReadAccessTo: book.root)
    }

    // MARK: 按钮

    @objc func toggleNavigation(_ sender: Any?) {
        navigation.isHidden.toggle()
        splitView.adjustSubviews()
        let hidden = navigation.isHidden
        hideButton.title = hidden ? L10n.tr("表示", comment: "ヘルプ窗口：目次を表示") : L10n.tr("非表示", comment: "ヘルプ窗口：目次を隠す")
    }

    var isNavigationHidden: Bool { navigation.isHidden }

    @objc func goBack(_ sender: Any?) { webView.goBack() }
    @objc func goForward(_ sender: Any?) { webView.goForward() }
    @objc func goHome(_ sender: Any?) { load(book.home) }

    @objc func printPage(_ sender: Any?) {
        guard let window else { return }
        let operation = webView.printOperation(with: NSPrintInfo.shared)
        operation.view?.frame = webView.bounds
        operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }

    private func updateButtons() {
        backButton.isEnabled = webView.canGoBack
        forwardButton.isEnabled = webView.canGoForward
    }

    // MARK: 页的读入（WKNavigationDelegate）

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { return decisionHandler(.cancel) }
        if url.isFileURL {
            // 帮助的文件夹里的页
            decisionHandler(book.path(for: url) != nil ? .allow : .cancel)
        } else if ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") {
            // 帮助以外（原版：HTML Help の中で開く。Mac 版は浏览器）
            if navigationAction.navigationType == .linkActivated { HelpWindowController.openExternal(url) }
            decisionHandler(.cancel)
        } else {
            decisionHandler(url.scheme == "about" ? .allow : .cancel)
        }
    }

    /// target="_blank" のリンク
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            if url.isFileURL, let path = book.path(for: url, withFragment: true) {
                load(path)
            } else if !url.isFileURL {
                HelpWindowController.openExternal(url)
            }
        }
        return nil
    }

    /// 帮助以外的链接（测试换掉）
    static var openExternal: (URL) -> Void = { NSWorkspace.shared.open($0) }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        if let url = webView.url { currentPath = book.path(for: url, withFragment: true) }
        updateButtons()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let url = webView.url { currentPath = book.path(for: url, withFragment: true) }
        updateButtons()
        syncContents()
        onPageLoad?(currentPath)
    }

    /// 目次里选中显示着的页（HTML Help の自動同期）
    private func syncContents() {
        guard let path = currentPath else { return }
        let file = path.split(separator: "#").first.map(String.init) ?? path
        guard let chain = chain(of: path) ?? chain(of: file) else {
            contentsOutline.deselectAll(nil)
            return
        }
        syncingContents = true
        defer { syncingContents = false }
        var item: Any?
        for depth in chain.indices {
            let node = OutlineItem.node(at: Array(chain[...depth]), in: book.toc)
            let object = outlineItem(for: Array(chain[...depth]), node: node)
            if depth < chain.count - 1 { contentsOutline.expandItem(object) }
            item = object
        }
        let row = contentsOutline.row(forItem: item)
        if row >= 0 {
            contentsOutline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            contentsOutline.scrollRowToVisible(row)
        }
    }

    /// 目次の中のこのページの位置（各层的下标）
    private func chain(of path: String) -> [Int]? {
        func search(_ nodes: [HelpBook.Node], prefix: [Int]) -> [Int]? {
            for (i, node) in nodes.enumerated() {
                if node.path == path { return prefix + [i] }
                if let found = search(node.children, prefix: prefix + [i]) { return found }
            }
            return nil
        }
        return search(book.toc, prefix: [])
    }

    /// 显示着的页的目次的名字（目次里选中的项目。测试用）
    var selectedContentsTitle: String? {
        let row = contentsOutline.selectedRow
        guard row >= 0, let item = contentsOutline.item(atRow: row) as? OutlineItem else { return nil }
        return item.node.title
    }

    // MARK: 目次（NSOutlineView）

    /// NSOutlineView の項目（同じ位置には同じオブジェクト）
    final class OutlineItem: NSObject {
        let indexPath: [Int]
        let node: HelpBook.Node
        init(_ indexPath: [Int], _ node: HelpBook.Node) {
            self.indexPath = indexPath
            self.node = node
        }

        static func node(at path: [Int], in toc: [HelpBook.Node]) -> HelpBook.Node {
            var nodes = toc
            var node = toc[path[0]]
            for i in path {
                node = nodes[i]
                nodes = node.children
            }
            return node	// path[0] から順に下りる（先頭の代入は path が空でないことの前提）
        }
    }

    private var outlineItems: [[Int]: OutlineItem] = [:]

    private func outlineItem(for indexPath: [Int], node: HelpBook.Node) -> OutlineItem {
        if let item = outlineItems[indexPath] { return item }
        let item = OutlineItem(indexPath, node)
        outlineItems[indexPath] = item
        return item
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let item = item as? OutlineItem else { return book.toc.count }
        return item.node.children.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let item = item as? OutlineItem else { return outlineItem(for: [index], node: book.toc[index]) }
        return outlineItem(for: item.indexPath + [index], node: item.node.children[index])
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        !((item as? OutlineItem)?.node.children.isEmpty ?? true)
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let item = item as? OutlineItem else { return nil }
        // 原版の目次のアイコン：本（子がある）とページ
        let symbol = item.node.children.isEmpty ? "doc.text" : "book.closed"
        return cell(outlineView, item.node.title, symbol: symbol)
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !syncingContents else { return }
        openSelectedContents()
    }

    @objc private func contentsClicked(_ sender: Any?) {
        // 子のある項目：クリックで開閉（HTML Help と同じ）
        let row = contentsOutline.clickedRow
        guard row >= 0, let item = contentsOutline.item(atRow: row) as? OutlineItem, !item.node.children.isEmpty,
              item.node.path == nil else { return }
        if contentsOutline.isItemExpanded(item) {
            contentsOutline.collapseItem(item)
        } else {
            contentsOutline.expandItem(item)
        }
    }

    private func openSelectedContents() {
        let row = contentsOutline.selectedRow
        guard row >= 0, let item = contentsOutline.item(atRow: row) as? OutlineItem, let path = item.node.path else { return }
        load(path)
    }

    /// 目次のこの名前の項目を選ぶ（测试用：用户点了那一项）
    @discardableResult
    func selectContents(titled title: String) -> Bool {
        guard let chain = Self.chain(titled: title, in: book.toc, prefix: []) else { return false }
        var item: OutlineItem?
        for depth in chain.indices {
            let object = outlineItem(for: Array(chain[...depth]), node: OutlineItem.node(at: Array(chain[...depth]), in: book.toc))
            if depth < chain.count - 1 { contentsOutline.expandItem(object) }
            item = object
        }
        let row = contentsOutline.row(forItem: item)
        guard row >= 0 else { return false }
        contentsOutline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        return true
    }

    private static func chain(titled title: String, in nodes: [HelpBook.Node], prefix: [Int]) -> [Int]? {
        for (i, node) in nodes.enumerated() {
            if node.title == title { return prefix + [i] }
            if let found = chain(titled: title, in: node.children, prefix: prefix + [i]) { return found }
        }
        return nil
    }

    // MARK: キーワード・検索の一覧（NSTableView）

    func numberOfRows(in tableView: NSTableView) -> Int {
        tableView === indexTable ? book.index.count : searchResults.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView === indexTable {
            let entry = book.index[row]
            return cell(tableView, String(repeating: "    ", count: entry.level) + entry.keyword, symbol: nil)
        }
        return cell(tableView, searchResults[row].title, symbol: nil)
    }

    private func cell(_ tableView: NSTableView, _ text: String, symbol: String?) -> NSView {
        let id = NSUserInterfaceItemIdentifier(symbol == nil ? "HelpTextCell" : "HelpIconCell")
        let cell = tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView ?? {
            let cell = NSTableCellView()
            cell.identifier = id
            let field = NSTextField(labelWithString: "")
            field.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            field.lineBreakMode = .byTruncatingTail
            field.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(field)
            cell.textField = field
            var leading = field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2)
            if symbol != nil {
                let image = NSImageView()
                image.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(image)
                cell.imageView = image
                NSLayoutConstraint.activate([
                    image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                    image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    image.widthAnchor.constraint(equalToConstant: 14),
                    image.heightAnchor.constraint(equalToConstant: 14),
                ])
                leading = field.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 4)
            }
            NSLayoutConstraint.activate([
                leading,
                field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
                field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }()
        cell.textField?.stringValue = text
        cell.textField?.setAccessibilityIdentifier(nil)
        if let symbol {
            cell.imageView?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            cell.imageView?.contentTintColor = symbol == "book.closed" ? .systemBrown : .secondaryLabelColor
        }
        return cell
    }

    // キーワード：入力した文字で始まる最初の項目を選ぶ（HTML Help と同じ）
    func controlTextDidChange(_ notification: Notification) {
        guard (notification.object as? NSSearchField) === indexField else { return }
        selectIndex(matching: indexField.stringValue)
    }

    @discardableResult
    func selectIndex(matching text: String) -> Int? {
        guard !text.isEmpty else { return nil }
        let options: String.CompareOptions = [.caseInsensitive, .widthInsensitive, .anchored]
        let row = book.index.firstIndex { $0.keyword.range(of: text, options: options) != nil }
            ?? book.index.firstIndex { $0.keyword.range(of: text, options: [.caseInsensitive, .widthInsensitive]) != nil }
        guard let row else { return nil }
        indexTable.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        indexTable.scrollRowToVisible(row)
        return row
    }

    var selectedIndexKeyword: String? {
        let row = indexTable.selectedRow
        return row >= 0 ? book.index[row].keyword : nil
    }

    @objc private func indexFieldEntered(_ sender: Any?) {
        // Return：選んでいるキーワードを表示（入力中の文字の変化は controlTextDidChange）
        showIndexTopic(sender)
    }

    /// キーワードの「表示」
    @objc func showIndexTopic(_ sender: Any?) {
        let row = indexTable.selectedRow >= 0 ? indexTable.selectedRow : (selectIndex(matching: indexField.stringValue) ?? -1)
        guard row >= 0 else { return }
        let topics = book.index[row].topics
        guard !topics.isEmpty else { return }
        let topic = topics.count == 1 ? topics[0] : chooseTopic(topics, indexTable)
        if let topic { load(topic.path) }
    }

    private static func chooseTopicWithMenu(_ topics: [HelpBook.Topic], _ view: NSView) -> HelpBook.Topic? {
        let menu = NSMenu()
        for (i, topic) in topics.enumerated() {
            let item = NSMenuItem(title: topic.title, action: nil, keyEquivalent: "")
            item.tag = i
            menu.addItem(item)
        }
        let picker = HelpTopicPicker()
        for item in menu.items {
            item.target = picker
            item.action = #selector(HelpTopicPicker.pick(_:))
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.minY), in: view)
        return picker.picked.map { topics[$0] }
    }

    /// 検索
    @objc func runSearch(_ sender: Any?) {
        searchResults = book.search(searchField.stringValue)
        searchTable.reloadData()
        if !searchResults.isEmpty { searchTable.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false) }
    }

    /// 检索的文字（测试用）
    func search(_ text: String) {
        selectTab(.search)
        searchField.stringValue = text
        runSearch(nil)
    }

    var searchResultTitles: [String] { searchResults.map(\.title) }

    @objc func showSearchResult(_ sender: Any?) {
        let row = searchTable.selectedRow
        guard row >= 0, row < searchResults.count else { return }
        load(searchResults[row].path)
    }

    func selectSearchResult(_ row: Int) {
        searchTable.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    }

    // MARK: 窗口

    override func showWindow(_ sender: Any?) {
        if !hasShownOnce { window?.center() }
        hasShownOnce = true
        super.showWindow(sender)
    }

    private var hasShownOnce = false

    func windowWillClose(_ notification: Notification) {
        onPageLoad = nil
    }

    // MARK: Mac 版の注記

    /// 页读完后在页的开头插入 Mac 版的注记（WKUserScript）
    static func noteScript(book: HelpBook) -> String {
        let notes = book.allNotes
        let data = (try? JSONSerialization.data(withJSONObject: notes, options: [.sortedKeys])) ?? Data("{}".utf8)
        let json = String(data: data, encoding: .utf8) ?? "{}"
        var rootURL = book.root.standardizedFileURL.absoluteString
        if !rootURL.hasSuffix("/") { rootURL += "/" }
        let rootData = (try? JSONSerialization.data(withJSONObject: [rootURL], options: []))
            ?? Data("[\"\"]".utf8)
        let root = String(data: rootData, encoding: .utf8) ?? "[\"\"]"
        let labelData = (try? JSONSerialization.data(withJSONObject: [book.noteLabel], options: [])) ?? Data("[\"\"]".utf8)
        let label = String(data: labelData, encoding: .utf8) ?? "[\"\"]"
        return """
            (function () {
              var notes = \(json);
              var root = \(root)[0];
              var label = \(label)[0];
              var href = location.href.split('#')[0];
              if (href.indexOf(root) !== 0 || !document.body) return;
              var note = notes[decodeURIComponent(href.substring(root.length))];
              if (!note || document.getElementById('sakura-mac-note')) return;
              var div = document.createElement('div');
              div.id = 'sakura-mac-note';
              div.setAttribute('role', 'note');
              div.style.cssText = 'margin:4px 0 10px 0;padding:6px 10px;border:1px solid #d8b24a;background:#fff8dc;' +
                'border-radius:4px;font-size:90%;line-height:1.5;color:#333';
              div.innerHTML = label + note;
              document.body.insertBefore(div, document.body.firstChild);
            })();
            """
    }
}

/// 「トピックの選択」のメニューで選んだ項目
private final class HelpTopicPicker: NSObject {
    var picked: Int?
    @objc func pick(_ sender: NSMenuItem) { picked = sender.tag }
}

// MARK: - 命令（ヘルプ メニュー）

extension NSApplication {
    /// ヘルプ > ヘルプ目次（F_HELP_CONTENTS。原版 ShowWinHelpContents：目次とホームのページ）
    @objc func showHelpContents(_ sender: Any?) {
        guard let help = HelpWindowController.shared() else { return NSSound.beep() }
        help.show(path: help.currentPath ?? help.book.home, tab: .contents)
    }

    /// ヘルプ > キーワード検索（F_HELP_SEARCH。原版 HELP_KEY：キーワードのタブ）
    @objc func showHelpSearch(_ sender: Any?) {
        guard let help = HelpWindowController.shared() else { return NSSound.beep() }
        help.show(path: help.currentPath ?? help.book.home, tab: .index)
    }
}

enum HelpViewer {
    /// 这个功能的页（原版 MyWinHelp(HELP_CONTEXT, FuncID_To_HelpContextID(…))）。没有页时 false
    @discardableResult
    static func show(function code: Int) -> Bool {
        guard let path = HelpBook.shared?.path(forFunction: code) else { return false }
        return show(path: path)
    }

    /// 这个对话框的「ヘルプ」的页
    @discardableResult
    static func show(dialog: String) -> Bool {
        guard let path = HelpTopics.path(forDialog: dialog) else { return false }
        return show(path: path)
    }

    @discardableResult
    static func show(path: String) -> Bool {
        guard let help = HelpWindowController.shared() else { return false }
        opened(path)
        help.show(path: path)
        return true
    }

    /// 打开了页（测试用：模态的对话框里按「ヘルプ」时，不等页读完也能确认）
    static var opened: (String) -> Void = { _ in }
}

// MARK: - コマンド一覧（F_MENU_ALLFUNC）

extension EditorTextView {
    /// ヘルプ > コマンド一覧（原版 Command_MENU_ALLFUNC）：「種別」ごとのサブメニューに全部の機能。選んだ機能を実行する
    @objc func showAllFunctions(_ sender: Any?) {
        let menu = Self.allFunctionsMenu()
        // 原版：编辑窗口的客户区的左上から右へ 540（窗口が狭いときは右端）、分割窗口の上端
        let x = visibleRect.minX + min(540, max(0, visibleRect.width - 200))
        let point = NSPoint(x: x, y: isFlipped ? visibleRect.minY : visibleRect.maxY)
        Self.popUpAllFunctions(menu, point, self)
    }

    /// 弹出菜单（测试换掉：popUp 在菜单关闭之前不返回）
    static var popUpAllFunctions: (NSMenu, NSPoint, NSView) -> Void = { menu, point, view in
        menu.popUp(positioning: nil, at: point, in: view)
    }

    /// 原版 CFuncLookup の分類（外部マクロ・カスタムメニュー・プラグインも）と機能。実行できない機能は灰色
    static func allFunctionsMenu() -> NSMenu {
        let menu = NSMenu()
        guard let editor = EditorCommandSettingsEditor() else { return menu }
        for (category, name) in editor.functionCategories.enumerated() {
            let submenu = NSMenu(title: name)
            let codes = editor.functionCodes(inCategory: category)
            let names = editor.functionNames(inCategory: category)
            for (code, title) in zip(codes, names) where code.intValue != 0 {
                let item = NSMenuItem(title: title, action: CommandTable.selector(for: code.intValue), keyEquivalent: "")
                item.tag = code.intValue
                submenu.addItem(item)
            }
            let item = NSMenuItem(title: name, action: nil, keyEquivalent: "")
            item.submenu = submenu
            menu.addItem(item)
        }
        return menu
    }
}

// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge

/// ファイルツリー設定（第 43 步。原版 CDlgFileTree）。
///
/// 布局照原版 IDD_FILETREE（Resources/OutlineDialogs.json）。設定の読み込み・保存・インポート・エクスポートは核心库（FileTreeCore）。
/// 項目の編集（追加・挿入・更新・削除・移動）はツリーの上で行い、OK で保存する（原版 GetData）。
final class FileTreeDialogController: NSObject {
    /// 模态运行（单元测试换掉：不出窗口，直接调用 handler）。OK なら true
    static var runModal: ((FileTreeDialogController) -> Bool)?

    let page: PropPage
    let title: String
    /// 現在の設定（原版 m_fileTreeSetting）
    let setting: FileTreeSetting
    let typeIndex: Int
    /// 相対パスの起点
    let folder: String
    var onClose: ((Bool) -> Void)?

    /// ツリーの一項目（原版 lParam が m_aItems の番号）
    final class Node: PropTreeNode {
        var item: FileTreeItem
        init(_ item: FileTreeItem) {
            self.item = item
            super.init(title: Node.label(item), canHaveChildren: item.type == .folder)
        }

        func update(_ item: FileTreeItem) {
            self.item = item
            title = Node.label(item)
            canHaveChildren = item.type == .folder
        }

        /// 原版 GetFileTreeLabel
        static func label(_ item: FileTreeItem) -> String {
            if item.type != .folder {
                if !item.label.isEmpty { return item.label }
                if [".", ".\\", "./"].contains(item.path) {
                    return L10n.tr("<カレントフォルダー>", comment: "STR_FILETREE_CURDIR")
                }
                return item.path
            }
            return item.label.isEmpty ? "Folder" : item.label
        }
    }

    init?(typeIndex: Int, folder: String) {
        guard let definition = PropDialogs.load("OutlineDialogs")?.dialog("IDD_FILETREE") else { return nil }
        page = PropPage(definition: definition)
        title = definition.name
        self.typeIndex = typeIndex
        self.folder = folder
        // 原版 OnInitDialog：LoadFileTreeSetting
        setting = FileTreeDialogController.loadSetting(typeIndex: typeIndex, folder: folder)
        super.init()
        setUpControls()
        setDataInit()
        setData()
    }

    /// 設定を読む（デフォルト設定ファイルは設定で選んだときの書签で読む）
    static func loadSetting(typeIndex: Int, folder: String) -> FileTreeSetting {
        FolderAccess.shared.startAccess(path: folder)
        let name = EditorCore.commonSetting(section: Self.section(typeIndex), key: "szFileTreeProjectIni") ?? ""
        return BookmarkStore.settingFiles.withAccess(path: name) { FileTreeCore.load(typeIndex: typeIndex, folder: folder) }
    }

    /// 設定の項目のセクション（原版 ProfDockSet：ドッキング配置が「タイプ別」ならタイプ別設定）
    static func section(_ typeIndex: Int) -> String {
        OutlineDockSettings.useType ? "Types(\(typeIndex))" : "Common"
    }

    func runModal(parent: NSWindow? = nil) -> Bool {
        if let handler = Self.runModal { return handler(self) }
        return PropModal.run(page, title: title, parent: parent ?? NSApp.keyWindow, identifier: "FileTreeDialog") { close in onClose = close }
    }

    var tree: PropTree? { page.tree("IDC_TREE_FL") }

    // MARK: - 控件

    private func setUpControls() {
        page.setUnavailable(["IDC_BUTTON_HELP"], reason: L10n.tr("Mac 版にはまだヘルプがありません", comment: "help"))
        (page.control("IDC_STATIC_SETTFING_FROM") as? NSTextField)?.lineBreakMode = .byTruncatingMiddle
        // 「...」（10×13）と「▼(3)」（21×14）：原版は小さなボタンが隣り合う。Mac の角丸ボタンでは重なるので、
        // アウトラインの ▼・■ と同じく余白のない四角いボタンにして原版の位置に置く
        // （くっついて 1 つのボタンに見えないように 3 点空ける。右端は原版の「▼(3)」の右端）
        let edit = page.control("IDC_EDIT_PATH")?.frame ?? .zero
        var x = edit.maxX + 2
        for (id, right) in [("IDC_BUTTON_REF2", nil), ("IDC_BUTTON_PATH_MENU", PropPage.pointsX(192))] as [(String, CGFloat?)] {
            guard let button = page.control(id) as? NSButton else { continue }
            button.bezelStyle = .smallSquare
            button.controlSize = .small
            button.font = PropPage.font
            let width = right.map { $0 - x } ?? PropPage.pointsX(10)
            button.frame = NSRect(x: x, y: edit.minY, width: width, height: edit.height)
            x = button.frame.maxX + 3
        }
        if let button = page.control("IDC_BUTTON_PATH_MENU") as? NSButton {
            button.title = "▼"	// 原版「▼(&3)」。アクセスキーの (3) は入らない
            button.toolTip = L10n.tr("▼(3)", comment: "IDD_FILETREE")
        }
        // 「読み込み」は右のボタンの列にくっつかないように（原版は 1 単位の隙間）
        if let load = page.control("IDC_BUTTON_LOAD"), let column = page.control("IDC_BUTTON_INSERT_A") {
            load.frame.origin.x = min(load.frame.minX, column.frame.minX - 4 - load.frame.width)
        }
        page.onButton = { [weak self] id in self?.buttonClicked(id) }
        page.onChange = { [weak self] id in self?.controlChanged(id) }
    }

    /// 原版 SetDataInit：設定の出所、各フォルダーの設定を読み込む、デフォルト設定ファイル名
    private func setDataInit() {
        var enableDefIni = true
        if setting.loadedFrom != .file {
            var text = setting.loadedFrom == .common
                ? L10n.tr("設定: 共通設定", comment: "STR_FILETREE_FROM_COMMON")
                : L10n.tr("設定: タイプ別設定", comment: "STR_FILETREE_FROM_TYPE")
            if !setting.loadedIni.isEmpty {
                text += "+" + L10n.tr("ファイル", comment: "F_FILE_TOPMENU")
            }
            page.setText("IDC_STATIC_SETTFING_FROM", text)
        } else {
            page.setText("IDC_STATIC_SETTFING_FROM",
                         String(format: L10n.tr("設定: %@", comment: "STR_FILETREE_FROM_FILE"), setting.loadedIni))
            enableDefIni = false
        }
        page.setEnabled("IDC_BUTTON_LOAD", enableDefIni)
        page.setChecked("IDC_CHECK_LOADINI", setting.project)
        page.setText("IDC_EDIT_DEFINI", setting.defaultProjectIni)
    }

    /// 共通設定・タイプ別設定に保存する（設定ファイルを読んでいないとき。原版 bSaveShareData）
    private var savesShareData: Bool { setting.loadedIni.isEmpty }

    /// 原版 SetData：ツリーを作る
    private func setData() {
        guard let tree else { return }
        var stack: [Node?] = [nil]
        var roots: [PropTreeNode] = []
        var warned = false
        for (i, item) in setting.items.enumerated() {
            if savesShareData && FileTreeCore.maxItems < i + 1 && !warned {
                warned = true
                CommonSettingsPages.inform(Self.maxCountMessage)
            }
            while item.depth < stack.count - 1 { stack.removeLast() }
            let node = Node(item.copy() as! FileTreeItem)
            if let parent = stack.last ?? nil {
                node.parent = parent
                parent.children.append(node)
            } else {
                roots.append(node)
            }
            if item.type == .folder { stack.append(node) }
        }
        tree.roots = roots
        tree.reload()
        tree.select(roots.first, notify: false)
        setDataItem(roots.first as? Node)
        changeEnableAddInsert()
    }

    static var maxCountMessage: String {
        String(format: L10n.tr("最大数(%d)を超えたため切り捨てました", comment: "STR_FILETREE_MAXCOUNT"), FileTreeCore.maxItems)
    }

    /// 原版 SetDataItem：項目の内容をコントロールに（項目が無いときは初期値）
    private func setDataItem(_ node: Node?) {
        let item = node?.item ?? FileTreeItem()
        page.setChecked("IDC_RADIO_GREP", item.type == .grep)
        page.setChecked("IDC_RADIO_FILE", item.type == .file)
        page.setChecked("IDC_RADIO_FOLDER", item.type == .folder)
        page.setText("IDC_EDIT_PATH", item.path)
        page.setText("IDC_EDIT_LABEL", item.label)
        page.setText("IDC_EDIT_FILE", item.file)
        page.setChecked("IDC_CHECK_HIDDEN", item.ignoreHidden)
        page.setChecked("IDC_CHECK_READONLY", item.ignoreReadOnly)
        page.setChecked("IDC_CHECK_SYSTEM", item.ignoreSystem)
        changeEnableItemType()
    }

    private var selectedType: FileTreeItemType {
        page.isChecked("IDC_RADIO_GREP") ? .grep : page.isChecked("IDC_RADIO_FILE") ? .file : .folder
    }

    /// 原版 ChangeEnableItemType：パスは Grep・ファイル、対象ファイルと非表示属性は Grep だけ
    private func changeEnableItemType() {
        let grep = selectedType == .grep
        let path = grep || selectedType == .file
        for id in ["IDC_STATIC_PATH", "IDC_EDIT_PATH", "IDC_BUTTON_REF2", "IDC_BUTTON_PATH_MENU"] { page.setEnabled(id, path) }
        for id in ["IDC_STATIC_FILE", "IDC_EDIT_FILE", "IDC_CHECK_HIDDEN", "IDC_CHECK_READONLY", "IDC_CHECK_SYSTEM"] { page.setEnabled(id, grep) }
    }

    /// 原版 ChangeEnableAddInsert：共通設定・タイプ別設定に保存するときは最大数を超えたら追加できない
    private func changeEnableAddInsert() {
        guard savesShareData, let tree else { return }
        let enable = !(FileTreeCore.maxItems < count(tree.roots))
        for id in ["IDC_BUTTON_ADD", "IDC_BUTTON_INSERT", "IDC_BUTTON_INSERT_A"] { page.setEnabled(id, enable) }
    }

    private func count(_ nodes: [PropTreeNode]) -> Int {
        nodes.reduce(0) { $0 + 1 + count($1.children) }
    }

    /// 原版 GetDataItem：コントロールの内容（使わない欄は初期値）
    func currentItem() -> FileTreeItem {
        let item = FileTreeItem()
        item.type = selectedType
        if item.type != .folder { item.path = page.text("IDC_EDIT_PATH") }
        item.label = page.text("IDC_EDIT_LABEL")
        if item.type == .grep {
            item.file = page.text("IDC_EDIT_FILE")
            item.ignoreHidden = page.isChecked("IDC_CHECK_HIDDEN")
            item.ignoreReadOnly = page.isChecked("IDC_CHECK_READONLY")
            item.ignoreSystem = page.isChecked("IDC_CHECK_SYSTEM")
        }
        return item
    }

    /// 原版 GetDataTree：ツリーの順に、階層を付けて
    func treeItems() -> [FileTreeItem] {
        var result: [FileTreeItem] = []
        func walk(_ nodes: [PropTreeNode], depth: Int) {
            for case let node as Node in nodes {
                let item = node.item.copy() as! FileTreeItem
                item.depth = depth
                result.append(item)
                walk(node.children, depth: depth + 1)
            }
        }
        walk(tree?.roots ?? [], depth: 0)
        return result
    }

    // MARK: - 動作（原版 OnBnClicked・OnNotify）

    private func controlChanged(_ id: String) {
        switch id {
        case "IDC_RADIO_GREP", "IDC_RADIO_FILE", "IDC_RADIO_FOLDER":
            changeEnableItemType()
            // [Folder]以外を子がいるFolderに上書きするの禁止
            var enableUpdate = true
            if let node = tree?.selectedNode as? Node, selectedType != .folder, node.item.type == .folder, !node.children.isEmpty {
                enableUpdate = false
            }
            page.setEnabled("IDC_BUTTON_UPDATE", enableUpdate)
        case "IDC_TREE_FL":
            // TVN_SELCHANGED
            setDataItem(tree?.selectedNode as? Node)
            page.setEnabled("IDC_BUTTON_UPDATE", true)
        default:
            break
        }
    }

    /// 单元测试：按钮
    func press(_ id: String) {
        buttonClicked(id)
    }

    private func buttonClicked(_ id: String) {
        guard let tree else { return }
        switch id {
        case "IDC_BUTTON_REF1":
            // 原版 CDlgOpenFile::SelectFile（*.ini）
            if let path = TypeSettingsPages.chooseFile(page.text("IDC_EDIT_DEFINI"), ["ini"], page.view.window) {
                page.setText("IDC_EDIT_DEFINI", path)
            }
        case "IDC_BUTTON_LOAD":
            let path = page.text("IDC_EDIT_DEFINI")
            _ = BookmarkStore.settingFiles.withAccess(path: path) { FileTreeCore.loadDefaultIni(path, into: setting) }
            setDataInit()
            setData()
        case "IDC_BUTTON_REF2":
            chooseTarget()
        case "IDC_BUTTON_PATH_MENU":
            showPathMenu()
        case "IDC_BUTTON_DELETE":
            delete()
        case "IDC_BUTTON_INSERT", "IDC_BUTTON_INSERT_A", "IDC_BUTTON_ADD":
            insert([currentItem()], id)
            changeEnableAddInsert()
        case "IDC_BUTTON_UPDATE":
            guard let node = tree.selectedNode as? Node else { return }
            node.update(currentItem())
            tree.reloadNode(node)
        case "IDC_BUTTON_FILEADD":
            guard let paths = Self.chooseFiles(page.view.window), !paths.isEmpty else { return }
            let items = paths.map { path -> FileTreeItem in
                let item = FileTreeItem()
                item.type = .file
                item.path = path.replacingOccurrences(of: "%", with: "%%")
                item.label = (path as NSString).lastPathComponent
                return item
            }
            insert(items, id)
        case "IDC_BUTTON_REPLACE":
            replacePaths()
        case "IDC_BUTTON_UP", "IDC_BUTTON_DOWN":
            guard let node = tree.selectedNode else { return }
            var siblings = node.siblings(in: tree)
            guard let index = siblings.firstIndex(where: { $0 === node }) else { return }
            let other = id == "IDC_BUTTON_UP" ? index - 1 : index + 1
            guard siblings.indices.contains(other) else { return }
            siblings.swapAt(index, other)
            setSiblings(siblings, of: node.parent)
            tree.reload()
            tree.select(node, notify: false)
        case "IDC_BUTTON_RIGHT":
            // 直前がフォルダーなら、その最後の子に
            guard let node = tree.selectedNode else { return }
            var siblings = node.siblings(in: tree)
            guard let index = siblings.firstIndex(where: { $0 === node }), index > 0, siblings[index - 1].canHaveChildren else { return }
            let newParent = siblings[index - 1]
            siblings.remove(at: index)
            setSiblings(siblings, of: node.parent)
            node.parent = newParent
            newParent.children.append(node)
            tree.reload()
            tree.select(node, notify: false)
        case "IDC_BUTTON_LEFT":
            // 親の次に
            guard let node = tree.selectedNode, let parent = node.parent else { return }
            parent.children.removeAll { $0 === node }
            var siblings = parent.siblings(in: tree)
            guard let index = siblings.firstIndex(where: { $0 === parent }) else { return }
            node.parent = parent.parent
            siblings.insert(node, at: index + 1)
            setSiblings(siblings, of: parent.parent)
            tree.reload()
            tree.select(node, notify: false)
        case "IDC_BUTTON_IMPORT":
            // 原版 CImpExpFileTree::ImportUI
            guard let path = TypeSettingsPages.chooseImportFile(["ini"], page.view.window) else { return }
            guard let items = FileTreeCore.importItems(path: path) else { return }
            setting.items = items
            setData()
        case "IDC_BUTTON_EXPORT":
            guard let path = TypeSettingsPages.chooseExportFile("", ["ini"], page.view.window) else { return }
            let error = FileTreeCore.exportItems(treeItems(), path: path)
            TypeSettingsPages.showMessage(error.isEmpty
                ? L10n.tr("ファイルをエクスポートしました。\n\n", comment: "STR_IMPEXP_OK_EXPORT") + path : error)
        case "IDOK":
            getData()
            onClose?(true)
        case "IDCANCEL":
            onClose?(false)
        default:
            break
        }
    }

    private func setSiblings(_ siblings: [PropTreeNode], of parent: PropTreeNode?) {
        if let parent {
            parent.children = siblings
        } else {
            tree?.roots = siblings
        }
    }

    /// 原版 IDC_BUTTON_DELETE：子があれば確かめる。次（無ければ前）を選ぶ
    private func delete() {
        guard let tree, let node = tree.selectedNode else { return }
        if !node.children.isEmpty,
           !CommonSettingsPages.confirm(L10n.tr("選択している項目を下位項目ごと削除します。\nよろしいですか？", comment: "STR_PROPCOMMAINMENU_DEL")) {
            return
        }
        var siblings = node.siblings(in: tree)
        guard let index = siblings.firstIndex(where: { $0 === node }) else { return }
        siblings.remove(at: index)
        setSiblings(siblings, of: node.parent)
        let next = siblings.indices.contains(index) ? siblings[index] : siblings.indices.contains(index - 1) ? siblings[index - 1] : nil
        tree.select(nil, notify: false)
        tree.reload()
        tree.select(next, notify: false)
        setDataItem(next as? Node)
        changeEnableAddInsert()
    }

    /// 原版 IDC_BUTTON_INSERT（上⇒）・INSERT_A（下⇒）・ADD（>>）・FILEADD
    private func insert(_ items: [FileTreeItem], _ id: String) {
        guard let tree, !items.isEmpty else { return }
        var parent: PropTreeNode?
        var position = tree.roots.count
        if let selected = tree.selectedNode {
            let siblings = selected.siblings(in: tree)
            let index = siblings.firstIndex { $0 === selected } ?? siblings.count
            switch id {
            case "IDC_BUTTON_ADD":
                // フォルダーなら最後の子、そうでなければ同じ階層の最後
                parent = selected.canHaveChildren ? selected : selected.parent
                position = (parent?.children ?? tree.roots).count
            case "IDC_BUTTON_INSERT_A":
                // フォルダーなら最初の子、そうでなければ次
                if selected.canHaveChildren {
                    parent = selected
                    position = 0
                } else {
                    parent = selected.parent
                    position = index + 1
                }
            case "IDC_BUTTON_FILEADD":
                // フォルダーなら最初の子、そうでなければ同じ階層の最後
                if selected.canHaveChildren {
                    parent = selected
                    position = 0
                } else {
                    parent = selected.parent
                    position = siblings.count
                }
            default:
                // 上⇒：前に
                parent = selected.parent
                position = index
            }
        }
        let nodes = items.map { Node($0) }
        for (offset, node) in nodes.enumerated() {
            node.parent = parent
            if let parent {
                parent.children.insert(node, at: min(position + offset, parent.children.count))
            } else {
                tree.roots.insert(node, at: min(position + offset, tree.roots.count))
            }
        }
        tree.reload()
        if let parent { tree.expand(parent) }
        tree.select(nodes.first, notify: false)
        setDataItem(nodes.first)
    }

    /// 「...」（原版 IDC_BUTTON_REF2）：Grep はフォルダー、ファイルはファイルを選ぶ
    private func chooseTarget() {
        if selectedType == .grep {
            var start = page.text("IDC_EDIT_PATH")
            if start.isEmpty || !start.hasPrefix("/") { start = folder }
            guard let url = GrepDialogController.chooseFolderPanel(start, page.view.window) else { return }
            FolderAccess.shared.remember(url)
            page.setText("IDC_EDIT_PATH", url.path)
        } else {
            guard let path = TypeSettingsPages.chooseFile("", [], page.view.window) else { return }
            page.setText("IDC_EDIT_PATH", path.replacingOccurrences(of: "%", with: "%%"))
        }
    }

    /// 「▼」（原版 IDC_BUTTON_PATH_MENU）：パスの変数を入れる
    static let pathMenu: [(title: String, value: String)] = [
        (L10n.tr("INIルート(I)", comment: "STR_FILETREE_MENU_ROOT"), "<iniroot>"),
        (L10n.tr("マイ ドキュメント(Y)", comment: "STR_FILETREE_MENU_MYDOC"), "%MYDOC%"),
        (L10n.tr("マイ ミュージック(M)", comment: "STR_FILETREE_MENU_MYMUSIC"), "%MYMUSIC%"),
        (L10n.tr("マイ ビデオ(V)", comment: "STR_FILETREE_MENU_MYVIDEO"), "%MYVIDEO%"),
        (L10n.tr("デスクトップ(D)", comment: "STR_FILETREE_MENU_DESK"), "%DESKTOP%"),
        (L10n.tr("Temp(T)", comment: "STR_FILETREE_MENU_TEMP"), "%TEMP%"),
        (L10n.tr("sakura(S)", comment: "STR_FILETREE_MENU_SAKURA"), "%SAKURA%"),
        (L10n.tr("sakuraデータ(A)", comment: "STR_FILETREE_MENU_SAKURADATA"), "%SAKURADATA%"),
    ]

    func makePathMenu() -> NSMenu {
        let menu = NSMenu()
        for (index, entry) in Self.pathMenu.enumerated() {
            let item = NSMenuItem(title: entry.title, action: #selector(pathMenuChosen(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            menu.addItem(item)
        }
        return menu
    }

    private func showPathMenu() {
        guard let button = page.control("IDC_BUTTON_PATH_MENU") else { return }
        makePathMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: button.frame.height), in: button)
    }

    /// 選んだ変数を選択範囲に入れる（原版 EditCtl_ReplaceSel）
    @objc func pathMenuChosen(_ sender: NSMenuItem) {
        guard Self.pathMenu.indices.contains(sender.tag), let field = page.control("IDC_EDIT_PATH") as? NSTextField else { return }
        let value = Self.pathMenu[sender.tag].value
        if let editor = field.currentEditor() {
            editor.replaceCharacters(in: editor.selectedRange, with: value)
        } else {
            field.stringValue += value
        }
    }

    /// 「パスの一括置換」（原版 IDC_BUTTON_REPLACE）：全部の項目のパスの文字列を置き換える
    private func replacePaths() {
        let title = L10n.tr("文字列を指定してください。", comment: "STR_DLGREPLC_STR")
        guard let from = CommonSettingsPages.input(title, L10n.tr("置換元パスを指定してください", comment: "STR_FILETREE_REPLACE_PATH_FROM"), 259, ""),
              let to = CommonSettingsPages.input(title, L10n.tr("置換先文字列を指定してください", comment: "STR_FILETREE_REPLACE_PATH_TO"), 259, "") else { return }
        func walk(_ nodes: [PropTreeNode]) {
            for case let node as Node in nodes {
                if !from.isEmpty {
                    let replaced = node.item.path.replacingOccurrences(of: from, with: to)
                    if replaced.utf16.count < 260 {
                        let item = node.item.copy() as! FileTreeItem
                        item.path = replaced
                        node.update(item)
                    }
                }
                walk(node.children)
            }
        }
        walk(tree?.roots ?? [])
        tree?.reload()
        if let node = tree?.selectedNode as? Node { setDataItem(node) }
    }

    /// 「ファイル挿入」の選択（原版 CDlgOpenFile::DoModalOpenDlg。複数選べる）。测试可以换
    static var chooseFiles: (_ window: NSWindow?) -> [String]? = { _ in
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return nil }
        for url in panel.urls { BookmarkStore.settingFiles.remember(url) }	// 重启后も沙盒で開けるように
        return panel.urls.map(\.path)
    }

    /// 原版 GetData：共通設定・タイプ別設定、または読み込んだ設定ファイルへ
    private func getData() {
        setting.project = page.isChecked("IDC_CHECK_LOADINI")
        setting.defaultProjectIni = page.text("IDC_EDIT_DEFINI")
        setting.items = treeItems()
        var truncated: ObjCBool = false
        let error = BookmarkStore.settingFiles.withAccess(path: setting.loadedIni) {
            FileTreeCore.save(setting, typeIndex: typeIndex, truncated: &truncated)
        }
        if truncated.boolValue { CommonSettingsPages.inform(Self.maxCountMessage) }
        if !error.isEmpty { TypeSettingsPages.showMessage(error) }
    }
}

// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge

/// 共通設定 > メインメニュー（计划第 41 步第 2 个 PR。原版 CPropMainMenu）。
///
/// - 编辑在核心库的复制上（CommonSettingsValues.commandEditor，与 キー割り当て 页共用）。ツリーは原版の TreeView と同じ操作
///   （削除・＋・---・上⇒・下⇒・>>・↑↓→←・全開・全閉・検査・クリア・初期設定・インポート・エクスポート）。
/// - GetData でツリーを複製に書き（原版 GetData：「共通設定」が無いと最後に追加）、sakura.ini の [MainMenu] の値にする。
/// - OK 后菜单栏按新的设置重新做（MainMenuBuilder）。
final class MainMenuPage: CommonSettingsPageLogic {
    static let section = "MainMenu"
    static let maxNameLength = 40		// MAX_MAIN_MENU_NAME_LEN
    static let maxTop = 20				// MAX_MAINMENU_TOP
    static let maxItems = 500			// MAX_MAINMENU
    static let nodeCode = 0				// F_NODE
    static let separatorCode = 1		// F_SEPARATOR
    static let optionCode = 31112		// F_OPTION
    static let specialRange = 29001...29006	// F_SPECIAL_FIRST～F_SPECIAL_LAST

    /// ツリーの一項目（原版 SMainMenuWork）
    final class MenuNode: PropTreeNode {
        var code: Int
        var name: String
        var accessKey: String
        var isNode: Bool
        /// アクセスキー重複エラー（表示の先頭に「>」）
        var duplicate = false

        init(code: Int, name: String, accessKey: String, isNode: Bool) {
            self.code = code
            self.name = name
            self.accessKey = accessKey
            self.isNode = isNode
            super.init(title: "", canHaveChildren: isNode)
            updateTitle()
        }

        /// 原版 MakeDispLabel
        func updateTitle() {
            let label = String(name.prefix(MainMenuPage.maxNameLength))
            title = (duplicate ? ">" : "") + label + (accessKey.isEmpty ? "" : "(\(accessKey))")
        }

        var menuChildren: [MenuNode] { children.compactMap { $0 as? MenuNode } }
    }

    private var editor: EditorCommandSettingsEditor?
    /// 「機能」列表的功能编号
    private var functionCodes: [Int] = []
    /// 「特別機能」的种别（原版 nSpecialFuncsNum）
    private var specialCategory = -1

    private func tree(_ page: PropPage) -> PropTree? { page.tree(idc("TREE_RES")) }

    // MARK: SetData / GetData

    func setData(_ page: PropPage, _ values: CommonSettingsValues) {
        editor = values.commandEditor
        guard let editor else { return }
        // 原版 SetData：種別（最後に「特別機能」）、先頭を選ぶ
        let categories = editor.functionCategories + [editor.specialFunctionCategory]
        specialCategory = categories.count - 1
        page.setItems(idc("COMBO_FUNCKIND"), categories, selected: 0)
        loadTree(page)
        loadFunctions(page)
        if let tree = tree(page) {
            let outline = tree.outline
            tree.onDoubleClick = { [weak self, weak page] node in
                guard let self, let page else { return }
                self.editAccessKey(page, node as? MenuNode)
            }
            outline.onCharacter = { [weak self, weak page] character in
                guard let page, let node = self?.tree(page)?.selectedNode as? MenuNode, node.code != Self.separatorCode else { return false }
                node.accessKey = character
                node.duplicate = false
                node.updateTitle()
                self?.tree(page)?.reloadNode(node)
                return true
            }
            outline.onDelete = { [weak page] in page?.onButton?(idc("BUTTON_DELETE")) }
            outline.onRename = { [weak self, weak page] in
                guard let self, let page else { return }
                self.renameNode(page)
            }
        }
    }

    /// 複製のメインメニューをツリーに（原版 SetData）
    private func loadTree(_ page: PropPage) {
        guard let editor, let tree = tree(page) else { return }
        page.setChecked(idc("CHECK_KEY_PARENTHESES"), editor.mainMenuKeyParentheses)
        var roots: [PropTreeNode] = []
        var stack: [MenuNode] = []	// stack[level - 1] が親
        for entry in editor.mainMenuEntries {
            let node = MenuNode(code: entry.code, name: entry.name, accessKey: entry.accessKey, isNode: entry.isNode)
            let level = min(max(0, entry.level), stack.count)	// 原版：深くなるのは一段ずつ
            stack.removeSubrange(level...)
            if let parent = stack.last, level > 0 {
                node.parent = parent
                parent.children.append(node)
            } else {
                roots.append(node)
            }
            stack.append(node)
        }
        tree.roots = roots
        tree.select(nil, notify: false)
        tree.reload()
    }

    func getData(_ page: PropPage, _ values: CommonSettingsValues) {
        storeTree(page)
        KeyBindPage.storeIniValues(editor, section: Self.section, values)
    }

    /// ツリーを複製に書く（原版 GetData）
    private func storeTree(_ page: PropPage) {
        guard let editor, let tree = tree(page) else { return }
        var entries: [EditorMainMenuEntry] = []
        func add(_ nodes: [PropTreeNode], level: Int) {
            for case let node as MenuNode in nodes {
                entries.append(EditorMainMenuEntry(level: level, isNode: node.isNode, code: node.code, name: node.name, accessKey: node.accessKey))
                add(node.children, level: level + 1)
            }
        }
        add(tree.roots, level: 0)
        _ = editor.setMainMenu(entries, keyParentheses: page.isChecked(idc("CHECK_KEY_PARENTHESES")))
    }

    /// 原版 PSN_SETACTIVE：機能一覧を作り直す（カスタムメニュー 页で変えた名前）
    func activate(_ page: PropPage, _ values: CommonSettingsValues) {
        let row = page.list(idc("LIST_FUNC"))?.selectedRow ?? -1
        loadFunctions(page)
        if row >= 0 { page.list(idc("LIST_FUNC"))?.select(row) }
    }

    /// 原版 CBN_SELCHANGE
    private func loadFunctions(_ page: PropPage) {
        guard let editor else { return }
        let category = page.selectedIndex(idc("COMBO_FUNCKIND"))
        if category == specialCategory {
            functionCodes = editor.specialFunctionCodes.map(\.intValue)
            page.list(idc("LIST_FUNC"))?.setRows(editor.specialFunctionNames.map { [$0] })
        } else {
            functionCodes = editor.functionCodes(inCategory: category).map(\.intValue)
            page.list(idc("LIST_FUNC"))?.setRows(editor.functionNames(inCategory: category).map { [$0] })
        }
    }

    // MARK: 有効・無効

    func enable(_ page: PropPage) {
        // 原版 SetDlgItemsEnableState
        let node = tree(page)?.selectedNode
        let siblings = node.flatMap { n in tree(page).map { n.siblings(in: $0) } } ?? []
        let index = node.flatMap { n in siblings.firstIndex { $0 === n } }
        page.setEnabled(idc("BUTTON_DELETE"), node != nil)
        page.setEnabled(idc("BUTTON_UP"), (index ?? 0) > 0)
        page.setEnabled(idc("BUTTON_DOWN"), index.map { $0 + 1 < siblings.count } ?? false)
        page.setEnabled(idc("BUTTON_RIGHT"), (index ?? 0) > 0)
        page.setEnabled(idc("BUTTON_LEFT"), node?.parent != nil)
        let function = (page.list(idc("LIST_FUNC"))?.selectedRow ?? -1) >= 0
        page.setEnabled(idc("BUTTON_INSERT"), function && node != nil)
        page.setEnabled(idc("BUTTON_INSERT_A"), function && node != nil)
        page.setEnabled(idc("BUTTON_ADD"), function)
    }

    func changed(_ id: String, _ page: PropPage, _ values: CommonSettingsValues) {
        if id == idc("COMBO_FUNCKIND") { loadFunctions(page) }
    }

    // MARK: 操作

    func buttonPressed(_ id: String, _ page: PropPage, _ values: CommonSettingsValues, window: NSWindow?) {
        guard let editor, let tree = tree(page) else { return }
        switch id {
        case idc("BUTTON_IMPORT"):
            guard let path = TypeSettingsPages.chooseImportFile(["ini"], window) else { return }
            var message: NSString?
            let ok = editor.importMainMenu(path: path, message: &message)
            TypeSettingsPages.showMessage(message as String? ?? "")
            if ok { loadTree(page) }
        case idc("BUTTON_EXPORT"):
            storeTree(page)	// 原版：GetData してから
            guard let path = TypeSettingsPages.chooseExportFile("", ["ini"], window) else { return }
            var message: NSString?
            let ok = editor.exportMainMenu(path: path, message: &message)
            let text = message as String? ?? ""
            TypeSettingsPages.showMessage(!ok || !text.isEmpty ? text
                                          : NSLocalizedString("ファイルをエクスポートしました。\n\n", comment: "STR_IMPEXP_OK_EXPORT") + path)
        case idc("BUTTON_CLEAR"):
            guard CommonSettingsPages.confirm(NSLocalizedString("メニューの設定をクリアします。\nよろしいですか？", comment: "STR_PROPCOMMAINMENU_CLEAR")) else { return }
            tree.roots = []
            tree.reload()
        case idc("BUTTON_INITIALIZE"):
            guard CommonSettingsPages.confirm(NSLocalizedString("メニューの設定を初期状態に戻します。\nよろしいですか？", comment: "STR_PROPCOMMAINMENU_INIT")) else { return }
            editor.initializeMainMenu()
            loadTree(page)
        case idc("BUTTON_DELETE"):
            delete(page, tree)
        case idc("BUTTON_INSERT_NODE"), idc("BUTTON_INSERTSEPARATOR"), idc("BUTTON_INSERT"), idc("BUTTON_INSERT_A"), idc("BUTTON_ADD"):
            insert(id, page, tree)
        case idc("BUTTON_UP"), idc("BUTTON_DOWN"):
            guard let node = tree.selectedNode else { return }
            var siblings = node.siblings(in: tree)
            guard let index = siblings.firstIndex(where: { $0 === node }) else { return }
            let other = id == idc("BUTTON_UP") ? index - 1 : index + 1
            guard siblings.indices.contains(other) else { return }
            siblings.swapAt(index, other)
            setSiblings(siblings, of: node.parent, tree)
            tree.reload()
            tree.select(node)
        case idc("BUTTON_RIGHT"):
            // 前の項目が子菜单のとき、その最後の下位項目に
            guard let node = tree.selectedNode else { return }
            var siblings = node.siblings(in: tree)
            guard let index = siblings.firstIndex(where: { $0 === node }), index > 0, siblings[index - 1].canHaveChildren else { return }
            let newParent = siblings[index - 1]
            siblings.remove(at: index)
            setSiblings(siblings, of: node.parent, tree)
            node.parent = newParent
            newParent.children.append(node)
            tree.reload()
            tree.select(node)
        case idc("BUTTON_LEFT"):
            // 親の次に
            guard let node = tree.selectedNode, let parent = node.parent else { return }
            parent.children.removeAll { $0 === node }
            var siblings = parent.siblings(in: tree)
            guard let index = siblings.firstIndex(where: { $0 === parent }) else { return }
            node.parent = parent.parent
            siblings.insert(node, at: index + 1)
            setSiblings(siblings, of: parent.parent, tree)
            tree.reload()
            tree.select(node)
        case idc("BUTTON_EXPAND"):
            tree.expandAll(true)
        case idc("BUTTON_COLLAPSE"):
            tree.expandAll(false)
        case idc("BUTTON_CHECK"):
            let errors = check(tree)
            if errors.isEmpty {
                CommonSettingsPages.inform(NSLocalizedString("問題ありませんでした。", comment: "STR_PROPCOMMAINMENU_OK"))
            } else {
                CommonSettingsPages.inform(errors)
            }
        default:
            break
        }
    }

    private func setSiblings(_ siblings: [PropTreeNode], of parent: PropTreeNode?, _ tree: PropTree) {
        if let parent {
            parent.children = siblings
        } else {
            tree.roots = siblings
        }
    }

    /// 原版 IDC_BUTTON_DELETE：下位項目があるときは確認。次（無ければ前）の項目を選ぶ
    private func delete(_ page: PropPage, _ tree: PropTree) {
        guard let node = tree.selectedNode else { return }
        if !node.children.isEmpty,
           !CommonSettingsPages.confirm(NSLocalizedString("選択している項目を下位項目ごと削除します。\nよろしいですか？", comment: "STR_PROPCOMMAINMENU_DEL")) {
            return
        }
        var siblings = node.siblings(in: tree)
        guard let index = siblings.firstIndex(where: { $0 === node }) else { return }
        siblings.remove(at: index)
        setSiblings(siblings, of: node.parent, tree)
        let next = siblings.indices.contains(index) ? siblings[index] : siblings.indices.contains(index - 1) ? siblings[index - 1] : nil
        tree.select(nil, notify: false)
        tree.reload()
        tree.select(next)
    }

    /// 原版 IDC_BUTTON_INSERT_NODE・INSERTSEPARATOR・INSERT・INSERT_A・ADD
    private func insert(_ id: String, _ page: PropPage, _ tree: PropTree) {
        let node: MenuNode
        var functionRow: Int?
        switch id {
        case idc("BUTTON_INSERT_NODE"):
            node = MenuNode(code: Self.nodeCode, name: NSLocalizedString("編集してください", comment: "STR_PROPCOMMAINMENU_EDIT"), accessKey: "", isNode: true)
        case idc("BUTTON_INSERTSEPARATOR"):
            node = MenuNode(code: Self.separatorCode, name: Self.separatorLabel, accessKey: "", isNode: false)
        default:
            guard let row = page.list(idc("LIST_FUNC"))?.selectedRow, functionCodes.indices.contains(row) else { return }
            functionRow = row
            node = MenuNode(code: functionCodes[row], name: page.list(idc("LIST_FUNC"))?.rows[row][0] ?? "", accessKey: "", isNode: false)
        }
        let selected = tree.selectedNode
        var parent: PropTreeNode?
        var position: Int
        if let selected {
            let siblings = selected.siblings(in: tree)
            let index = siblings.firstIndex { $0 === selected } ?? siblings.count
            switch id {
            case idc("BUTTON_ADD"):
                // 子菜单なら最後の下位項目、そうでなければ同じ階層の最後
                if (selected as? MenuNode)?.isNode == true {
                    parent = selected
                    position = selected.children.count
                } else {
                    parent = selected.parent
                    position = siblings.count
                }
            case idc("BUTTON_INSERT_NODE"), idc("BUTTON_INSERT_A"):
                // 子菜单なら最初の下位項目、そうでなければ次
                if (selected as? MenuNode)?.isNode == true {
                    parent = selected
                    position = 0
                } else {
                    parent = selected.parent
                    position = index + 1
                }
            default:
                // 上⇒・---：前に
                parent = selected.parent
                position = index
            }
        } else {
            position = tree.roots.count
        }
        node.parent = parent
        if let parent {
            parent.children.insert(node, at: min(position, parent.children.count))
        } else {
            tree.roots.insert(node, at: min(position, tree.roots.count))
        }
        tree.reload()
        if let parent { tree.expand(parent) }
        tree.select(node)
        if let functionRow { page.list(idc("LIST_FUNC"))?.select(functionRow + 1) }	// 次の機能を選ぶ
    }

    static var separatorLabel: String {
        NSLocalizedString("――――――――――", comment: "STR_PROPCOMMAINMENU_SEP")
    }

    /// 原版 NM_DBLCLK：アクセスキーの設定（区切線以外）
    private func editAccessKey(_ page: PropPage, _ node: MenuNode?) {
        guard let node, node.code != Self.separatorCode,
              let key = CommonSettingsPages.input(NSLocalizedString("メニューアイテムのアクセスキー設定", comment: "STR_PROPCOMMAINMENU_ACCKEY1"),
                                                  NSLocalizedString("キーを入力してください。", comment: "STR_PROPCOMMAINMENU_ACCKEY2"),
                                                  1, node.accessKey) else { return }
        node.accessKey = String(key.prefix(1))
        node.duplicate = false
        node.updateTitle()
        tree(page)?.reloadNode(node)
    }

    /// 原版 F2 → TVN_BEGINLABELEDIT / TVN_ENDLABELEDIT：子菜单の名前（空は「編集してください」、変えたら F_NODE）
    private func renameNode(_ page: PropPage) {
        guard let node = tree(page)?.selectedNode as? MenuNode, node.isNode,
              let name = CommonSettingsPages.input(NSLocalizedString("名前の変更", comment: "メインメニュー：子菜单の名前（Mac 版）"),
                                                   "", Self.maxNameLength, node.name) else { return }
        let newName = name.isEmpty ? NSLocalizedString("編集してください", comment: "STR_PROPCOMMAINMENU_EDIT") : name
        if newName != node.name { node.code = Self.nodeCode }
        node.name = newName
        node.updateTitle()
        tree(page)?.reloadNode(node)
    }

    /// 原版 Check_MainMenu：エラーのメッセージ（無ければ空）。重複したアクセスキーは「>」を付け、最初のエラーの項目を選ぶ
    private func check(_ tree: PropTree) -> String {
        var optionOk = false
        var menuCount = 0, topCount = 0, duplicateCount = 0, missingCount = 0
        var firstError: PropTreeNode?
        func visit(_ nodes: [PropTreeNode], level: Int) {
            var keys: [String: MenuNode] = [:]
            for case let node as MenuNode in nodes {
                menuCount += 1
                if level == 0 { topCount += 1 }
                // 原版：F_NODE は子菜单、F_SEPARATOR は区切線、特別機能、それ以外は isNode なら子菜单、でなければ命令
                let isSeparator = node.code == Self.separatorCode
                let isSpecial = !isSeparator && node.code != Self.nodeCode && Self.specialRange.contains(node.code)
                let isNodeType = node.code == Self.nodeCode || (!isSeparator && !isSpecial && node.isNode)
                let isLeaf = !isNodeType && !isSeparator && !isSpecial
                if isLeaf && node.code == Self.optionCode { optionOk = true }
                if node.accessKey.isEmpty {
                    if isNodeType || isLeaf {
                        if missingCount == 0 && firstError == nil { firstError = node }
                        missingCount += 1
                    }
                } else if let first = keys[node.accessKey] {
                    if duplicateCount == 0 && firstError == nil { firstError = first }
                    duplicateCount += 1
                    node.duplicate = true
                    first.duplicate = true
                    first.updateTitle()
                } else {
                    keys[node.accessKey] = node
                    node.duplicate = false
                }
                node.updateTitle()
                visit(node.children, level: level + 1)
            }
        }
        visit(tree.roots, level: 0)
        tree.reload()
        var message = ""
        if !optionOk { message += NSLocalizedString("『共通設定』が有りません。\n", comment: "STR_PROPCOMMAINMENU_ERR2") }
        if topCount > Self.maxTop { message += NSLocalizedString("トップレベルの項目数が多すぎます。\n", comment: "STR_PROPCOMMAINMENU_ERR3") }
        if menuCount > Self.maxItems { message += NSLocalizedString("登録項目数が多すぎます。\n", comment: "STR_PROPCOMMAINMENU_ERR4") }
        if duplicateCount > 0 { message += NSLocalizedString("重複したアクセスキーがあります。\n", comment: "STR_PROPCOMMAINMENU_ERR5") }
        if missingCount > 0 { message += NSLocalizedString("未設定のアクセスキーがあります。\n", comment: "STR_PROPCOMMAINMENU_ERR6") }
        if let firstError { tree.select(firstError) }
        return message
    }
}

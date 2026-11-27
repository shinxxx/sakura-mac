// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge

/// ファイルツリー（第 43 步。原版 CDlgFuncList::SetTreeFile・SetTreeFileSub・OnJump の OUTLINE_FILETREE）。
///
/// 設定の読み込み、パスの展開、フォルダーの中の枚举は核心库（FileTreeCore）。ここはツリーの項目と、
/// 開いたとき（原版 TVN_ITEMEXPANDING）に中を読むこと。沙盒では授权されたフォルダーだけ読める：
/// 権限の無いフォルダーを開くとき「許可」を求める（FolderAccess。一度許可すれば再起動後も聞かない）。
final class FileTreeNode {
    enum Kind {
        case grepRoot		// Grep の項目（原版 lParam -(n*10+3)）
        case file			// ファイルの項目（原版 lParam n）
        case group			// フォルダーの項目（原版 lParam -4：ラベルだけ）
        case folder			// Grep の中のフォルダー（原版 lParam -2）
        case grepFile		// Grep の中のファイル（原版 lParam -1）
        case message		// 「<Wild Card Error>」（原版 lParam -4）
    }

    let kind: Kind
    let label: String
    /// フォルダー・ファイルのフルパス（group、message は空）
    let path: String
    /// Grep の項目の設定（中を読むときの対象ファイル・除外・隠しファイル）
    let item: FileTreeItem?
    weak var parent: FileTreeNode?
    /// 子。nil はまだ読んでいない（Grep・フォルダー）
    var children: [FileTreeNode]?

    init(kind: Kind, label: String, path: String, item: FileTreeItem?) {
        self.kind = kind
        self.label = label
        self.path = path
        self.item = item
        if kind == .group || kind == .file || kind == .grepFile || kind == .message { children = [] }
    }

    /// 中を読む項目（Grep・フォルダー）
    var isFolder: Bool { kind == .grepRoot || kind == .folder }

    func add(_ child: FileTreeNode) {
        child.parent = self
        children = (children ?? []) + [child]
    }
}

/// ファイルツリーのデータ（原版 IDC_TREE_FL の項目）
final class FileTreeData: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
    private(set) var roots: [FileTreeNode] = []
    /// 権限を聞くときの親の窓口
    weak var window: NSWindow?
    /// 権限の無いフォルダーを開くときに聞く（「すべて展開」のときは聞かない）
    private var promptsForAccess = true

    /// 設定からツリーを作る（原版 SetTreeFile）。folder は相対パスの起点（編集中のファイルのフォルダー）
    func load(_ setting: FileTreeSetting, folder: String) {
        var stack: [FileTreeNode?] = [nil]	// 原版 hParentTree（nil は TVI_ROOT）
        var result: [FileTreeNode] = []
        for root in FileTreeCore.roots(setting, folder: folder) {
            while root.depth < stack.count - 1 { stack.removeLast() }
            let item = setting.items[root.itemIndex]
            let node: FileTreeNode
            switch root.type {
            case .grep: node = FileTreeNode(kind: .grepRoot, label: root.label, path: root.path, item: item)
            case .file: node = FileTreeNode(kind: .file, label: root.label, path: root.path, item: item)
            default: node = FileTreeNode(kind: .group, label: root.label, path: "", item: item)
            }
            if let parent = stack.last ?? nil { parent.add(node) } else { result.append(node) }
            if root.type == .folder { stack.append(node) }
        }
        roots = result
        // 原版は Grep の項目の中をすぐ読む（中が無ければ [+] を消す）。権限が既にあるときだけ読む（作るときは聞かない）
        func walk(_ nodes: [FileTreeNode]) {
            for node in nodes {
                if node.kind == .grepRoot, FolderAccess.shared.startAccess(path: node.path) { loadChildren(node) }
                walk(node.children ?? [])
            }
        }
        walk(roots)
    }

    /// フォルダーの中を読む（原版 SetTreeFileSub）。読めたら true
    @discardableResult
    func loadChildren(_ node: FileTreeNode) -> Bool {
        guard node.isFolder, node.children == nil else { return true }
        guard let item = rootItem(of: node) else { return false }
        if !FolderAccess.shared.startAccess(path: node.path) {
            guard promptsForAccess, !FolderAccess.doesNotExist(node.path),
                  FolderAccess.shared.ensureAccess(paths: [node.path], parent: window, message: Self.accessMessage) else { return false }
        }
        let listing = FileTreeCore.list(item, folder: node.path)
        node.children = []
        if listing.wildcardError {
            node.add(FileTreeNode(kind: .message, label: "<Wild Card Error>", path: "", item: nil))
            return true
        }
        let base = node.path.hasSuffix("/") ? node.path : node.path + "/"
        for name in listing.folders { node.add(FileTreeNode(kind: .folder, label: name, path: base + name, item: nil)) }
        for name in listing.files { node.add(FileTreeNode(kind: .grepFile, label: name, path: base + name, item: nil)) }
        return true
    }

    static var accessMessage: String { L10n.tr("「%@」をファイルツリーに表示するには、このフォルダーへのアクセスを許可してください。",
                                                 comment: "ファイルツリーのフォルダーの許可") }

    /// Grep の項目の設定（原版 GetTreeFileFullName の nItem）
    private func rootItem(of node: FileTreeNode) -> FileTreeItem? {
        var current: FileTreeNode? = node
        while let n = current {
            if n.kind == .grepRoot { return n.item }
            current = n.parent
        }
        return nil
    }

    /// すべて展開（原版 TreeView_ExpandAll：64 階層まで）。権限の無いフォルダーは開かない（全部のフォルダーで聞かない）
    func expandAll(_ outline: NSOutlineView) {
        promptsForAccess = false
        defer { promptsForAccess = true }
        func walk(_ nodes: [FileTreeNode], depth: Int) {
            guard depth < 64 else { return }
            for node in nodes where outline.isExpandable(node) {
                outline.expandItem(node)
                if outline.isItemExpanded(node) { walk(node.children ?? [], depth: depth + 1) }
            }
        }
        walk(roots, depth: 0)
    }

    // MARK: NSOutlineViewDataSource

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let node = item as? FileTreeNode else { return roots.count }
        return node.children?.count ?? 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let node = item as? FileTreeNode else { return roots[index] }
        return node.children?[index] as Any
    }

    /// まだ読んでいないフォルダーは [+] を出す（原版 cChildren = 1）。読んで中が無ければ消す
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let node = item as? FileTreeNode else { return false }
        guard let children = node.children else { return node.isFolder }
        return !children.isEmpty
    }

    // MARK: NSOutlineViewDelegate

    /// 開くとき中を読む（原版 TVN_ITEMEXPANDING → SetTreeFileSub）
    func outlineView(_ outlineView: NSOutlineView, shouldExpandItem item: Any) -> Bool {
        guard let node = item as? FileTreeNode else { return true }
        guard node.children == nil else { return !(node.children ?? []).isEmpty }
        guard loadChildren(node) else { return false }
        if node.children?.isEmpty ?? true {
            // [+]記号削除（展開の処理が終わってから。その前にツリーが作り直されていたら何もしない）
            DispatchQueue.main.async { [weak self, weak outlineView, weak node] in
                guard let self, let outlineView, let node, outlineView.dataSource === self, outlineView.row(forItem: node) >= 0 else { return }
                outlineView.reloadItem(node)
            }
            return false
        }
        outlineView.reloadItem(node, reloadChildren: true)
        return true
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        (notification.object as? OutlineTreeView)?.fitColumn()
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        (notification.object as? OutlineTreeView)?.fitColumn()
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        OutlineCell(text: (item as? FileTreeNode)?.label ?? "", color: (outlineView as? OutlineTreeView)?.textColor)
    }

    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        OutlineRowView(back: (outlineView as? OutlineTreeView)?.textColor == nil ? nil : outlineView.backgroundColor)
    }

    /// 選んでいるファイル（原版 GetData の m_sJumpFile、ファイルの項目の m_cmemFileName）。ファイル以外は nil
    func selectedFile(_ outline: NSOutlineView) -> String? {
        guard let node = outline.item(atRow: outline.selectedRow) as? FileTreeNode,
              node.kind == .file || node.kind == .grepFile else { return nil }
        return node.path
    }
}

extension EditorTextView {
    /// 検索 > ファイルツリー（F_FILETREE。原版 Command_FUNCLIST( OUTLINE_FILETREE )）
    @objc func showFileTree(_ sender: Any?) {
        outlineCommand(action: .normal, type: .fileTree)
    }

    /// ファイルツリーの相対パスの起点（原版はカレントフォルダー。Mac 版は編集中のファイルのフォルダー、無題はホームフォルダー）
    var fileTreeBaseFolder: String {
        guard let path = sakuraDocument?.fileURL?.path, !path.isEmpty else { return GrepDialogController.homeFolder }
        return (path as NSString).deletingLastPathComponent
    }
}

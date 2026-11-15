// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge

/// ファイル >「最近使ったファイル」「最近使ったフォルダー」的子菜单（第 31 步）。
///
/// 内容是核心库的历史（原版 CMRUFile::CreateMenu、CMRUFolder::CreateMenu，sakura.ini 的 [MRU]），
/// 每次打开菜单时重新做（NSMenuDelegate.menuNeedsUpdate）。
/// 菜单的文字与原版相同（GetMenuFullLabel_MRU："1 路径  [编码]"），只是 macOS 的菜单没有「&」的快捷字母，去掉。
/// 历史是空的时与原版相同，「最近使ったファイル」本身变灰（MF_GRAYED）：去掉子菜单，没有动作的菜单项 macOS 自动变灰。
/// 所以「ファイル」菜单打开时也要更新（FileMenuUpdater）。
final class RecentMenu: NSObject, NSMenuDelegate {
    enum Kind {
        case files
        case folders
    }

    let kind: Kind
    let menu: NSMenu
    /// 「ファイル」菜单里的这一项（子菜单挂在这里）
    let item: NSMenuItem

    /// 菜单的 delegate 是弱引用，这里拿着
    private static var instances: [RecentMenu] = []

    init(kind: Kind) {
        self.kind = kind
        let title = kind == .files
            ? NSLocalizedString("最近使ったファイル", comment: "ファイル > 最近使ったファイル（34006）")
            : NSLocalizedString("最近使ったフォルダー", comment: "ファイル > 最近使ったフォルダー（34007）")
        menu = NSMenu(title: title)
        item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        Self.instances.append(self)
        update()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        update()
    }

    /// 全部的历史菜单按现在的历史更新（「ファイル」菜单打开时）
    static func updateAll() {
        instances.forEach { $0.update() }
    }

    /// 按现在的历史重新做菜单项
    func update() {
        menu.removeAllItems()
        let entries: [(label: String, path: String)]
        switch kind {
        case .files:
            entries = EditorCore.recentFiles.map { ($0.menuLabel, $0.path) }
        case .folders:
            entries = EditorCore.recentFolders.map { ($0.menuLabel, $0.path) }
        }
        for entry in entries {
            let entryItem = NSMenuItem(title: Self.labelWithoutMnemonic(entry.label),
                                  action: kind == .files ? #selector(openFile(_:)) : #selector(openFolder(_:)),
                                  keyEquivalent: "")
            entryItem.target = self
            entryItem.representedObject = entry.path
            entryItem.toolTip = entry.path
            menu.addItem(entryItem)
        }
        // 空的时变灰（原版 CEditWnd::InitMenu_Function 的 MF_GRAYED）
        if entries.isEmpty {
            if item.submenu != nil {
                item.submenu = nil
                item.action = nil	// 挂子菜单时 AppKit 设了 submenuAction:，去掉
            }
        } else if item.submenu !== menu {
            item.submenu = menu
        }
    }

    /// Windows 菜单的快捷字母记号：「&x」→「x」，「&&」→「&」
    static func labelWithoutMnemonic(_ label: String) -> String {
        var result = ""
        var iterator = label.makeIterator()
        while let c = iterator.next() {
            if c == "&" {
                if let next = iterator.next() { result.append(next) }
            } else {
                result.append(c)
            }
        }
        return result
    }

    @objc func openFile(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String,
              let controller = NSDocumentController.shared as? SakuraDocumentController else { return }
        controller.openRecentFile(path: path)
    }

    @objc func openFolder(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String,
              let controller = NSDocumentController.shared as? SakuraDocumentController else { return }
        controller.openRecentFolder(path: path)
    }
}

/// 「ファイル」菜单打开时更新历史的子菜单（空的变灰）
final class FileMenuUpdater: NSObject, NSMenuDelegate {
    static let shared = FileMenuUpdater()

    func menuNeedsUpdate(_ menu: NSMenu) {
        RecentMenu.updateAll()
    }
}

// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge

/// 主菜单（第 34 步）。
///
/// 按原版的 MainMenu.ini（核心库的 EditorCore.mainMenu，共通設定 > メインメニュー）生成：
/// 顶层菜单、子菜单、分隔线的顺序和名字与原版相同。各项目的 tag 是功能编号，
/// 动作和快捷键按 CommandTable、KeyCommands。还没有移植的功能没有动作，自动变灰。
///
/// 与原版不同的地方（macOS 的规矩）：
/// - 最前面加 App 菜单（已确认的偏离项 1）
/// - 「ウィンドウ」的开头加「しまう」（⌘M）；「ウィンドウ一覧」的子菜单由 macOS 自动列出窗口（原版的 29001 ウィンドウリスト）
/// - 「設定」的最后加「Windows のキー割り当てを使う」（KeyScheme）和「Windows 版の設定をインポート…」（第 35 步）
/// - 菜单的「&」快捷字母（m_sKey）不显示
enum MainMenuBuilder {
    static func build() -> NSMenu {
        let mainMenu = NSMenu()
        mainMenu.addItem(submenuItem(appMenu()))
        var stack: [NSMenu] = [mainMenu]		// stack[level] 是 level 这一层的项目放进去的菜单
        var skipDeeperThan: Int?				// 换成 Mac 的菜单的子菜单：原版的子项目不要
        for entry in EditorCore.mainMenu {
            let level = entry.level
            if let skip = skipDeeperThan {
                if level > skip { continue }
                skipDeeperThan = nil
            }
            guard level < stack.count else { continue }	// 层次跳了（MainMenu.ini 写错了）
            stack.removeSubrange((level + 1)...)
            let parent = stack[level]
            switch entry.type {
            case .submenu:
                let item = submenu(for: entry, level: level)
                parent.addItem(item)
                if let menu = item.submenu, !isReplaced(entry.command) {
                    stack.append(menu)
                } else {
                    skipDeeperThan = level
                }
            case .command:
                parent.addItem(commandItem(entry))
            case .separator:
                parent.addItem(.separator())
            case .special:
                // 29001 ウィンドウリスト 由 macOS 列出；29005 登録済みマクロリスト は開くときに作る（第 45 步）；
                // 29004 カスタムメニュー、29006 プラグイン は以后
                if entry.command == 29005 { parent.delegate = UserMacroMenu.shared }
            @unknown default:
                break
            }
        }
        applyKeyEquivalents(mainMenu)
        for name in [KeyScheme.didChangeNotification, keyBindingsDidChangeNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                applyKeyEquivalents(mainMenu)
            }
        }
        return mainMenu
    }

    /// 共通設定 > キー割り当て を OK した（第 41 步）：菜单的快捷键按新的分配
    static let keyBindingsDidChangeNotification = Notification.Name("SakuraKeyBindingsDidChange")
    /// 共通設定 > メインメニュー を OK した（第 41 步）：菜单栏を作り直す（AppDelegate）
    static let mainMenuDidChangeNotification = Notification.Name("SakuraMainMenuDidChange")

    /// 原版的顶层菜单、子菜单的功能编号（Funccode_x.hsrc 的 F_*_TOPMENU 等）
    enum MenuCode {
        static let file = 34052, settings = 34057, window = 34058, help = 34059
        static let recentFiles = 34006, recentFolders = 34007, windowList = 34060
    }

    /// 子项目由 Mac 的菜单做的子菜单
    private static func isReplaced(_ code: Int) -> Bool {
        [MenuCode.recentFiles, MenuCode.recentFolders, MenuCode.windowList].contains(code)
    }

    private static func submenu(for entry: EditorMenuItem, level: Int) -> NSMenuItem {
        let title = RecentMenu.labelWithoutMnemonic(entry.name)
        let item: NSMenuItem
        switch entry.command {
        case MenuCode.recentFiles:
            // 第 31 步：最近使ったファイル（29002）
            item = RecentMenu(kind: .files).item
        case MenuCode.recentFolders:
            item = RecentMenu(kind: .folders).item
        case MenuCode.windowList:
            // 窗口（标签也算一个窗口）的一览由 macOS 自动加在 windowsMenu 里
            let menu = NSMenu(title: title)
            NSApp.windowsMenu = menu
            item = submenuItem(menu)
        default:
            let menu = NSMenu(title: title)
            item = submenuItem(menu)
            if level == 0 { decorateTopMenu(menu, code: entry.command) }
        }
        item.tag = entry.command
        return item
    }

    /// 顶层菜单的 Mac 的追加
    private static func decorateTopMenu(_ menu: NSMenu, code: Int) {
        switch code {
        case MenuCode.file:
            menu.delegate = FileMenuUpdater.shared	// 打开时更新历史的子菜单（第 31 步）
        case MenuCode.window:
            menu.addItem(withTitle: NSLocalizedString("しまう", comment: "ウィンドウ > しまう（macOS）"),
                         action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
            menu.addItem(.separator())
        case MenuCode.help:
            NSApp.helpMenu = menu
        default:
            break
        }
    }

    private static func commandItem(_ entry: EditorMenuItem) -> NSMenuItem {
        let item = NSMenuItem(title: RecentMenu.labelWithoutMnemonic(entry.name),
                              action: CommandTable.selector(for: entry.command), keyEquivalent: "")
        item.tag = entry.command
        return item
    }

    /// 设定的最后加的 Mac 版的项目（顶层菜单全部做好以后）
    private static func addSettingsExtras(_ mainMenu: NSMenu) {
        guard let settings = mainMenu.items.first(where: { $0.tag == MenuCode.settings })?.submenu,
              !settings.items.contains(where: { $0.action == #selector(KeySchemeToggle.toggleKeyScheme(_:)) }) else { return }
        settings.addItem(.separator())
        let toggle = NSMenuItem(title: NSLocalizedString("Windows のキー割り当てを使う", comment: "設定 > キーの方案（Mac 版）"),
                                action: #selector(KeySchemeToggle.toggleKeyScheme(_:)), keyEquivalent: "")
        toggle.target = KeySchemeToggle.shared
        settings.addItem(toggle)
        // 第 35 步：Windows 版的 sakura.ini 的导入
        let importItem = NSMenuItem(title: NSLocalizedString("Windows 版の設定をインポート…", comment: "設定 > 設定のインポート（Mac 版）"),
                                    action: #selector(SettingsImporter.importWindowsSettings(_:)), keyEquivalent: "")
        importItem.target = SettingsImporter.shared
        settings.addItem(importItem)
    }

    /// 全部的菜单项按现在的方案设快捷键（方案改变时重新设）
    static func applyKeyEquivalents(_ menu: NSMenu) {
        if menu.supermenu == nil { addSettingsExtras(menu) }
        for item in menu.items {
            if let submenu = item.submenu {
                applyKeyEquivalents(submenu)
            } else if item.tag > 0 && item.target == nil {
                if let key = KeyCommands.menuKeyEquivalent(for: item.tag) {
                    item.keyEquivalent = key.key
                    item.keyEquivalentModifierMask = key.modifiers
                } else {
                    item.keyEquivalent = ""
                    item.keyEquivalentModifierMask = []
                }
            }
        }
    }

    /// App 菜单：macOS 必备，原版没有（已确认的偏离项 1）。
    private static func appMenu() -> NSMenu {
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Sakura Editor for Mac"
        let menu = NSMenu(title: name)
        menu.addItem(withTitle: "\(name) について", action: #selector(NSApplication.showSakuraAbout(_:)), keyEquivalent: "")	// 原版のバージョン情報
        menu.addItem(.separator())
        // 共通設定（第 39 步：CommonSettingsWindow.swift。与 設定 > 共通設定 相同，打开上次的页）。
        // tag 不设功能编号：⌘, 是 macOS 的设置的键，不按键位方案换
        let settings = NSMenuItem(title: NSLocalizedString("設定…", comment: "App 菜单（macOS）"),
                                  action: #selector(NSApplication.showCommonSettings(_:)), keyEquivalent: ",")
        menu.addItem(settings)
        menu.addItem(.separator())
        let services = NSMenuItem(title: "サービス", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: "サービス")
        services.submenu = servicesMenu
        NSApp.servicesMenu = servicesMenu
        menu.addItem(services)
        menu.addItem(.separator())
        menu.addItem(withTitle: "\(name) を隠す", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = NSMenuItem(title: "ほかを隠す", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(hideOthers)
        menu.addItem(withTitle: "すべてを表示", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "\(name) を終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    private static func submenuItem(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}

/// 設定 >「Windows のキー割り当てを使う」：打勾时用原版的 Windows 键位（⌃ 是 Ctrl），否则 ⌘ 当作 Ctrl
final class KeySchemeToggle: NSObject, NSMenuItemValidation {
    static let shared = KeySchemeToggle()

    @objc func toggleKeyScheme(_ sender: Any?) {
        KeyScheme.current = KeyScheme.current == .mac ? .windows : .mac
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem.state = KeyScheme.current == .windows ? .on : .off
        return true
    }
}

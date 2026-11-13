// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit

/// 主菜单。
///
/// 顶层菜单的名称和顺序与原版一致（sakura_core/sakura_rc.rc 的 F_*_TOPMENU）。
/// 各菜单的内容将在后续步骤中按原版的 MainMenu.ini 生成；
/// 目前只放了窗口空壳运行所需的最少项目。
enum MainMenuBuilder {
    static func build() -> NSMenu {
        let mainMenu = NSMenu()
        mainMenu.addItem(submenuItem(appMenu()))
        mainMenu.addItem(submenuItem(fileMenu()))
        mainMenu.addItem(submenuItem(editMenu()))
        mainMenu.addItem(submenuItem(NSMenu(title: "変換")))
        mainMenu.addItem(submenuItem(NSMenu(title: "検索")))
        mainMenu.addItem(submenuItem(NSMenu(title: "ツール")))
        mainMenu.addItem(submenuItem(NSMenu(title: "設定")))

        let windowMenu = NSMenu(title: "ウィンドウ")
        windowMenu.addItem(withTitle: "しまう", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(.separator())
        // 原版的 F_NEXTWINDOW / F_PREVWINDOW。窗口一览和标签的菜单项由 macOS 自动加在这个菜单里
        windowMenu.addItem(withTitle: "次のウィンドウ", action: #selector(AppDelegate.activateNextWindow(_:)), keyEquivalent: "")
        windowMenu.addItem(withTitle: "前のウィンドウ", action: #selector(AppDelegate.activatePreviousWindow(_:)), keyEquivalent: "")
        mainMenu.addItem(submenuItem(windowMenu))
        NSApp.windowsMenu = windowMenu

        let helpMenu = NSMenu(title: "ヘルプ")
        mainMenu.addItem(submenuItem(helpMenu))
        NSApp.helpMenu = helpMenu

        return mainMenu
    }

    /// App 菜单：macOS 必备，原版没有（已确认的偏离项 1）。
    private static func appMenu() -> NSMenu {
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Sakura Editor for Mac"
        let menu = NSMenu(title: name)
        menu.addItem(withTitle: "\(name) について", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        // 共通設定。窗口在阶段 3 实现，目前不可用。
        let settings = NSMenuItem(title: "設定…", action: nil, keyEquivalent: ",")
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

    private static func fileMenu() -> NSMenu {
        let menu = NSMenu(title: "ファイル")
        // 新建、打开、保存由 NSDocumentController / NSDocument 处理（第 26 步）
        menu.addItem(withTitle: "新規作成", action: #selector(NSDocumentController.newDocument(_:)), keyEquivalent: "n")
        menu.addItem(withTitle: "開く…", action: #selector(NSDocumentController.openDocument(_:)), keyEquivalent: "o")
        menu.addItem(.separator())
        menu.addItem(withTitle: "上書き保存", action: #selector(NSDocument.save(_:)), keyEquivalent: "s")
        let saveAs = NSMenuItem(title: "名前を付けて保存…", action: #selector(NSDocument.saveAs(_:)), keyEquivalent: "s")
        saveAs.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(saveAs)
        menu.addItem(.separator())
        menu.addItem(withTitle: "閉じる", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        return menu
    }

    /// 編集：第 25 步先放撤销和重做（F_UNDO、F_REDO），其余按原版在后面的步骤加入
    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: "編集")
        menu.addItem(withTitle: "元に戻す", action: #selector(EditorTextView.undo(_:)), keyEquivalent: "z")
        let redo = NSMenuItem(title: "やり直し", action: #selector(EditorTextView.redo(_:)), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(redo)
        return menu
    }

    private static func submenuItem(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}

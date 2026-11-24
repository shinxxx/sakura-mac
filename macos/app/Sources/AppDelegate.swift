// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge

final class AppDelegate: NSObject, NSApplicationDelegate {
    // 在打开文件、新建无题文档之前启动核心库和建立菜单
    func applicationWillFinishLaunching(_ notification: Notification) {
        // 自动界面测试时用临时的设置和剪贴板（UITesting.swift）
        UITesting.prepare()
        // 核心库：建立共通设置，读入 sakura.ini（第 24 步）
        if !EditorCore.startup() {
            NSLog("Sakura core startup failed")
        }
        // 排版的文字宽度用 Core Text 测，字体与绘制相同（第 27 步）
        EditorCore.useCoreTextMeasurement()
        EditorCore.setLayoutFont(name: EditorTextView.fontName, size: EditorTextView.fontSize)
        NSApp.mainMenu = MainMenuBuilder.build()
        // 共通設定 > メインメニュー を OK したら菜单栏を作り直す（第 41 步）
        NotificationCenter.default.addObserver(forName: MainMenuBuilder.mainMenuDidChangeNotification, object: nil, queue: .main) { _ in
            NSApp.mainMenu = MainMenuBuilder.build()
        }
        UITesting.prepareSettingsImport()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        UITesting.openTestFileIfRequested()
    }

    // 界面测试打开测试用的文件时不另外开无题窗口（键盘输入要进那个文件的窗口）
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        !UITesting.opensTestFile
    }

    // 原版在最后一个编辑窗口关闭时退出（不常驻任务托盘），这里保持一致。
    // 设置的导入途中（关闭所有窗口以后导入、重新启动）不结束（第 35 步）
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !SettingsImporter.shared.isImporting
    }

    // 原版在控制进程结束时写出 sakura.ini（导入了设置、重新启动之前不写出：核心库判断）
    func applicationWillTerminate(_ notification: Notification) {
        if EditorCore.isStarted {
            // 结束时还开着的文件也登记到「最近使ったファイル」（原版是每个窗口关闭时，第 31 步）
            for case let document as SakuraDocument in NSDocumentController.shared.documents {
                document.addToRecent()
            }
            BookmarkStore.shared.pruneToRecentFiles()
            EditorCore.shutdown(savingSettings: UITesting.savesSettings)
        }
    }

    // MARK: - ウィンドウ > 次のウィンドウ / 前のウィンドウ（F_NEXTWINDOW / F_PREVWINDOW）

    /// 按打开的顺序排列的编辑窗口（标签也算一个窗口，与原版的窗口一览相同）
    static func editorWindows() -> [NSWindow] {
        NSDocumentController.shared.documents.flatMap { $0.windowControllers.compactMap(\.window) }
    }

    @objc func activateNextWindow(_ sender: Any?) {
        activateWindow(offset: 1)
    }

    @objc func activatePreviousWindow(_ sender: Any?) {
        activateWindow(offset: -1)
    }

    private func activateWindow(offset: Int) {
        let windows = Self.editorWindows()
        guard windows.count > 1 else { return }
        let current = windows.firstIndex { $0 === NSApp.mainWindow } ?? 0
        let next = (current + offset + windows.count) % windows.count
        windows[next].makeKeyAndOrderFront(nil)
    }
}

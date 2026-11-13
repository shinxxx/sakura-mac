// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge

final class AppDelegate: NSObject, NSApplicationDelegate {
    // 在打开文件、新建无题文档之前启动核心库和建立菜单
    func applicationWillFinishLaunching(_ notification: Notification) {
        // 核心库：建立共通设置，读入 sakura.ini（第 24 步）
        if !EditorCore.startup() {
            NSLog("Sakura core startup failed")
        }
        // 排版的文字宽度用 Core Text 测，字体与绘制相同（第 27 步）
        EditorCore.useCoreTextMeasurement()
        EditorCore.setLayoutFont(name: EditorTextView.fontName, size: EditorTextView.fontSize)
        NSApp.mainMenu = MainMenuBuilder.build()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
    }

    // 原版在最后一个编辑窗口关闭时退出（不常驻任务托盘），这里保持一致。
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // 原版在控制进程结束时写出 sakura.ini
    func applicationWillTerminate(_ notification: Notification) {
        if EditorCore.isStarted {
            EditorCore.shutdown(savingSettings: true)
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

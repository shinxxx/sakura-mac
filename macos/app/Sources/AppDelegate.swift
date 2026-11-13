// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowControllers: [EditorWindowController] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 核心库：建立共通设置，读入 sakura.ini（第 24 步）
        if !EditorCore.startup() {
            NSLog("Sakura core startup failed")
        }
        NSApp.mainMenu = MainMenuBuilder.build()
        newEditorWindow(nil)
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

    @objc func newEditorWindow(_ sender: Any?) {
        guard let document = EditorDocument() else {
            NSSound.beep()
            return
        }
        showWindow(EditorWindowController(document: document))
    }

    /// ファイル > 開く（F_FILEOPEN）。保存在后面的步骤加入。
    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            openFile(url)
        }
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        openFile(URL(fileURLWithPath: filename))
    }

    @discardableResult
    private func openFile(_ url: URL) -> Bool {
        guard let document = EditorDocument() else { return false }
        let result = document.open(path: url.path)
        guard result == .success || result == .lostSome else {
            let alert = NSAlert()
            alert.messageText = "ファイルを開けませんでした。"
            alert.informativeText = url.path
            alert.runModal()
            return false
        }
        showWindow(EditorWindowController(document: document))
        return true
    }

    private func showWindow(_ controller: EditorWindowController) {
        windowControllers.append(controller)
        controller.onClose = { [weak self, weak controller] in
            self?.windowControllers.removeAll { $0 === controller }
        }
        controller.showWindow(nil)
    }
}

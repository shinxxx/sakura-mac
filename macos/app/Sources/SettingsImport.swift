// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge

/// 設定 >「Windows 版の設定をインポート…」（计划第 35 步）。
///
/// Windows 版的 sakura.ini 的设置（共通設定、キー割り当て、タイプ別設定、メインメニュー、強調キーワード等）
/// 换成 Mac 版的设置。ini 的格式和读法与 Windows 版相同（核心库 EditorCore.importSettings）。
/// 历史（最近使ったファイル等）是这台 Mac 的文件，保留 Mac 的。
///
/// 与在 Windows 版换掉 sakura.ini 后重新启动相同，导入以后重新启动 App：
/// 1. 选文件 → 确认是设置文件 → 确认（导入以后重新启动）
/// 2. 关闭所有的窗口（修改过的文件确认保存。取消时什么也不做）
/// 3. 导入（导入前的设置备份在 sakura.ini.before-import）→ 重新启动
final class SettingsImporter: NSObject, NSMenuItemValidation {
    static let shared = SettingsImporter()

    /// 关闭窗口、导入的途中（这时最后一个窗口关闭也不结束 App）
    private(set) var isImporting = false

    // MARK: - 对话框等（单元测试换成不出来的）

    /// 选择设置文件。取消时 nil
    static var chooseFile: () -> URL? = {
        let panel = NSOpenPanel()
        panel.message = L10n.tr("インポートする設定ファイル（sakura.ini）を選択してください。", comment: "設定のインポート（Mac 版）")
        panel.prompt = L10n.tr("選択", comment: "設定のインポート（Mac 版）")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// 导入前的确认。继续时 true
    static var confirm: (_ source: String, _ backup: String) -> Bool = { source, backup in
        let alert = NSAlert()
        alert.messageText = L10n.tr("Windows 版の設定をインポートしますか?", comment: "設定のインポート（Mac 版）")
        alert.informativeText = String(format: L10n.tr(
            "共通設定、キー割り当て、タイプ別設定、メインメニューなどを次のファイルの内容に置き換えます。\n%@\n\n履歴（最近使ったファイルなど）はこの Mac のものを残します。現在の設定は次のファイルに保存します。\n%@\n\nインポートした設定はサクラエディタの再起動後に有効になります。開いているファイルはすべて閉じます。",
            comment: "設定のインポート（Mac 版）"), source, backup)
        alert.addButton(withTitle: L10n.tr("インポートして再起動", comment: "設定のインポート（Mac 版）"))
        alert.addButton(withTitle: L10n.tr("キャンセル", comment: "メッセージボックス"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// 错误的消息
    static var showError: (String) -> Void = { message in
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.addButton(withTitle: L10n.tr("OK", comment: "メッセージボックス"))
        alert.runModal()
    }

    /// 关闭所有的文档（修改过的确认保存）。全部关闭了 true，取消了 false
    static var closeAllDocuments: (@escaping (Bool) -> Void) -> Void = { completion in
        CloseAllDocuments(completion: completion).run()
    }

    /// 重新启动 App：新的 App 启动以后，这个结束（设置已经导入，结束时不写出）
    static var relaunch: () -> Void = {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            DispatchQueue.main.async {
                if let error { NSLog("Sakura relaunch failed: \(error)") }
                NSApp.terminate(nil)
            }
        }
    }

    // MARK: - 命令

    /// Windows 版の設定をインポート
    @objc func importWindowsSettings(_ sender: Any?) {
        guard !isImporting, let url = Self.chooseFile() else { return }
        let path = url.path
        switch EditorCore.checkSettingsFile(path) {
        case .imported:
            break
        case .notSettingsFile:
            Self.showError(String(format: L10n.tr("%@\n\nサクラエディタの設定ファイルではありません。", comment: "設定のインポート（Mac 版）"), path))
            return
        default:
            Self.showError(String(format: L10n.tr("%@\n\nファイルを読み込めませんでした。", comment: "設定のインポート（Mac 版）"), path))
            return
        }
        guard Self.confirm(path, EditorCore.settingsBackupPath) else { return }

        isImporting = true
        // 关闭的文件在关闭时登记到历史（SakuraDocument.close），导入时作为 Mac 的历史留下
        Self.closeAllDocuments { [weak self] closedAll in
            guard let self else { return }
            guard closedAll else {
                self.isImporting = false
                return
            }
            self.finishImport(path: path)
        }
    }

    /// 窗口全部关闭以后：导入，重新启动
    private func finishImport(path: String) {
        let result = EditorCore.importSettings(path)
        guard result == .imported else {
            isImporting = false
            Self.showError(String(format: L10n.tr("設定ファイルに書き込めませんでした。\n%@", comment: "設定のインポート（Mac 版）"),
                                  EditorCore.settingsFilePath))
            return
        }
        Self.relaunch()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        !isImporting
    }
}

/// NSDocumentController.closeAllDocuments 的回调要 Objective-C 的选择子
private final class CloseAllDocuments: NSObject {
    let completion: (Bool) -> Void
    private var keep: CloseAllDocuments?

    init(completion: @escaping (Bool) -> Void) {
        self.completion = completion
    }

    func run() {
        keep = self		// 回调之前不释放
        NSDocumentController.shared.closeAllDocuments(withDelegate: self,
                                                      didCloseAllSelector: #selector(documentController(_:didCloseAll:contextInfo:)),
                                                      contextInfo: nil)
    }

    @objc private func documentController(_ controller: NSDocumentController, didCloseAll: Bool, contextInfo: UnsafeMutableRawPointer?) {
        completion(didCloseAll)
        keep = nil
    }
}

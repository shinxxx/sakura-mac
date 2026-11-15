// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge

/// 打开对话框加「文字コードセット」（第 30 步。原版 CDlgOpenFile::DoModalOpenDlg）。
///
/// 选了「自動選択」以外的编码时，用这个编码打开（不自动识别）。
/// 从 Finder 打开时与原版相同，自动识别。
/// 第 31 步：从「最近使ったファイル」打开（用上次的编码和书签的访问权限）、从「最近使ったフォルダー」打开对话框。
/// main.swift 在 App 启动前建立这个类的实例，它就成为 NSDocumentController.shared。
final class SakuraDocumentController: NSDocumentController {
    override func beginOpenPanel(_ openPanel: NSOpenPanel, forTypes inTypes: [String]?,
                                 completionHandler: @escaping (Int) -> Void) {
        let accessory = FileDialogAccessory(mode: .open, encoding: ECEncodingAutoDetect)
        openPanel.accessoryView = accessory.view
        openPanel.isAccessoryViewDisclosed = true
        // 「最近使ったフォルダー」から：そのフォルダーを開いた状態で表示する（第 31 步）
        if let directory = nextOpenPanelDirectory {
            openPanel.directoryURL = directory
            nextOpenPanelDirectory = nil
        }
        super.beginOpenPanel(openPanel, forTypes: inTypes) { result in
            if result == NSApplication.ModalResponse.OK.rawValue && accessory.encoding != ECEncodingAutoDetect {
                for url in openPanel.urls {
                    SakuraDocument.requestedEncodings[SakuraDocument.encodingKey(url)] = accessory.encoding
                }
            }
            completionHandler(result)
        }
    }

    /// 打开以后（已经打开的文件只是显示出来）去掉指定的编码，之后从别处打开时自动识别
    override func openDocument(withContentsOf url: URL, display displayDocument: Bool,
                               completionHandler: @escaping (NSDocument?, Bool, Error?) -> Void) {
        let key = SakuraDocument.encodingKey(url)
        super.openDocument(withContentsOf: url, display: displayDocument) { document, alreadyOpen, error in
            SakuraDocument.requestedEncodings.removeValue(forKey: key)
            completionHandler(document, alreadyOpen, error)
        }
    }

    // MARK: - 最近使ったファイル／フォルダー（第 31 步。原版 CEditWnd::OnCommand 的 IDM_SELMRU、IDM_SELOPENFOLDER）

    /// 下一次打开对话框最初显示的文件夹
    var nextOpenPanelDirectory: URL?

    /// 从历史打开文件：用上次的编码（原版 SLoadInfo(m_szPath, m_nCharCode)），用书签取回沙盒的访问权限
    func openRecentFile(path: String) {
        let original = URL(fileURLWithPath: path)
        let scoped = BookmarkStore.shared.resolve(path: path)
        let accessing = scoped?.startAccessingSecurityScopedResource() ?? false
        // 书签解析出来的路径可能是符号链接的另一边（/var → /private/var）。同一个文件时用历史里的路径打开，
        // 历史（上次的编码、光标）才对得上。文件被移动过时用书签找到的地方
        let url: URL
        if let scoped, scoped.resolvingSymlinksInPath().path != original.resolvingSymlinksInPath().path {
            url = scoped
        } else {
            url = original
        }
        if let recent = EditorCore.recentFile(path: path) {
            SakuraDocument.requestedEncodings[SakuraDocument.encodingKey(url)] = recent.encoding
        }
        openDocument(withContentsOf: url, display: true) { document, alreadyOpen, error in
            if accessing, let scoped {
                if let document = document as? SakuraDocument, !alreadyOpen {
                    document.holdSecurityScope(scoped)	// 关闭时还回去
                } else {
                    scoped.stopAccessingSecurityScopedResource()
                }
            }
            if let error {
                NSApp.presentError(error)
            }
        }
    }

    /// 从历史的文件夹打开：在那个文件夹打开「開く」对话框
    func openRecentFolder(path: String) {
        nextOpenPanelDirectory = URL(fileURLWithPath: path, isDirectory: true)
        openDocument(nil)
    }
}

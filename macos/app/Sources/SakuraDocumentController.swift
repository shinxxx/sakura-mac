// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge

/// 打开对话框加「文字コードセット」（第 30 步。原版 CDlgOpenFile::DoModalOpenDlg）。
///
/// 选了「自動選択」以外的编码时，用这个编码打开（不自动识别）。
/// 从「最近使用的文件」、Finder 打开时与原版相同，自动识别。
/// main.swift 在 App 启动前建立这个类的实例，它就成为 NSDocumentController.shared。
final class SakuraDocumentController: NSDocumentController {
    override func beginOpenPanel(_ openPanel: NSOpenPanel, forTypes inTypes: [String]?,
                                 completionHandler: @escaping (Int) -> Void) {
        let accessory = FileDialogAccessory(mode: .open, encoding: ECEncodingAutoDetect)
        openPanel.accessoryView = accessory.view
        openPanel.isAccessoryViewDisclosed = true
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
}

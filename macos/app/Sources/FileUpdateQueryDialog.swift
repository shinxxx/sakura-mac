// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit

/// 「ファイルが更新されました」（第 46 步。原版 CDlgFileUpdateQuery、IDD_FILEUPDATEQUERY）。
///
/// 布局照原版（Resources/FileSafetyDialogs.json）：ファイル名（読み取り専用）、「このファイルは外部のエディタ等で変更されています。」、
/// 変更があるとき「再ロードを行うと変更が失われますがよろしいですか?」、ないとき「再ロードしますか?」、
/// ボタンは 再読込(R)・閉じる(C)（既定）・以後未編集で再読込(L)・以後通知メッセージのみ(M)・以後更新を監視しない(N)。
/// Esc は「閉じる」と同じ（原版 IDCANCEL → EFUQ_CLOSE）。
final class FileUpdateQueryDialog: NSObject {
    let page: PropPage
    let title: String
    private(set) var result: FileUpdateQuery = .close
    var onClose: (() -> Void)?

    /// ボタン → 答え（原版 OnBnClicked）
    static let buttons: [String: FileUpdateQuery] = [
        "IDC_BTN_RELOAD": .reload,
        "IDC_BTN_CLOSE": .close,
        "IDC_BTN_NOTIFYONLY": .notifyOnly,
        "IDC_BTN_NOSUPERVISION": .noSupervision,
        "IDC_BTN_AUTOLOAD": .autoload,
    ]

    init?(path: String, modified: Bool) {
        guard let definition = PropDialogs.load("FileSafetyDialogs")?.dialog("IDD_FILEUPDATEQUERY") else { return nil }
        page = PropPage(definition: definition)
        title = definition.name
        super.init()
        // 原版 OnInitDialog
        page.setText("IDC_UPDATEDFILENAME", path)
        page.setText("IDC_QUERYRELOADMSG", modified
                     ? L10n.tr("再ロードを行うと変更が失われますがよろしいですか?", comment: "STR_ERR_DLGUPQRY1")
                     : L10n.tr("再ロードしますか?", comment: "STR_ERR_DLGUPQRY2"))
        // 文字のなかったラベルは、入れた文字の幅にする（ダイアログの幅まで）
        if let label = page.control("IDC_QUERYRELOADMSG") as? NSTextField, let message = page.control("IDC_FILEUPDATEMSG") {
            label.frame.size.width = max(message.frame.width, min(ceil(label.fittingSize.width), page.view.frame.width - label.frame.minX))
        }
        fitPath()
        (page.control("IDC_BTN_CLOSE") as? NSButton)?.keyEquivalent = "\r"	// DEFPUSHBUTTON
        page.onButton = { [weak self] id in
            guard let self else { return }
            self.result = Self.buttons[id] ?? .close
            self.onClose?()
        }
    }

    /// ファイル名の欄：パスは文字単位で折り返し、2 行に入らない長いパスは欄を高くしてファイル名まで見えるようにする
    /// （Mac の文字は原版より広く、深い容器のパスだとファイル名が隠れる）。下のコントロールとダイアログをその分下げる
    private func fitPath() {
        guard let field = page.control("IDC_UPDATEDFILENAME") as? NSTextField, let cell = field.cell else { return }
        cell.lineBreakMode = .byCharWrapping
        let needed = ceil(cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: field.frame.width, height: .greatestFiniteMagnitude)).height)
        let delta = needed - field.frame.height
        guard delta > 0 else { return }
        let bottom = field.frame.maxY
        field.frame.size.height = needed
        for view in page.view.subviews where view !== field && view.frame.minY >= bottom - 1 {
            view.frame.origin.y += page.view.isFlipped ? delta : 0
        }
        page.view.setFrameSize(NSSize(width: page.view.frame.width, height: page.view.frame.height + delta))
    }

    /// 原版 DoModal：閉じるまで待つ
    func runModal(parent: NSWindow?) -> FileUpdateQuery {
        let panel = EscapePanel(contentRect: NSRect(origin: .zero, size: page.view.frame.size),
                                styleMask: [.titled], backing: .buffered, defer: false)
        panel.title = title
        panel.isReleasedWhenClosed = false
        panel.setAccessibilityIdentifier("FileUpdateQueryDialog")
        panel.contentView = page.view
        panel.initialFirstResponder = page.control("IDC_BTN_CLOSE")
        panel.onCancel = { [weak self] in
            self?.result = .close
            self?.onClose?()
        }
        if let parent {
            panel.setFrameOrigin(NSPoint(x: parent.frame.midX - panel.frame.width / 2, y: parent.frame.midY - panel.frame.height / 2))
        } else {
            panel.center()
        }
        onClose = { NSApp.stopModal() }
        NSApp.activate(ignoringOtherApps: false)
        _ = NSApp.runModal(for: panel)
        onClose = nil
        panel.orderOut(nil)
        return result
    }
}

/// Esc で閉じるパネル（原版 IDCANCEL）
final class EscapePanel: NSPanel {
    var onCancel: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

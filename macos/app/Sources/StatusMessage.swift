// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit

/// ステータスメッセージ（第 44 步，原版 CEditView::SendStatusMessage）。
///
/// Mac 版にはまだステータスバーがないので、編集画面の左下に小さなラベルで出す
/// （原版もステータスバーを表示していないときはメニューバーに出す）。
/// インクリメンタルサーチ中はずっと、ほかのメッセージ（「▼先頭から再検索しました」等）は数秒で消える。
final class StatusMessageLabel: NSTextField {
    init() {
        super.init(frame: .zero)
        isEditable = false
        isSelectable = false
        isBezeled = false
        drawsBackground = true
        backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.92)
        textColor = .labelColor
        font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        lineBreakMode = .byTruncatingTail
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.separatorColor.cgColor
        setAccessibilityIdentifier("statusMessage")
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}

extension EditorTextView {
    /// 表示中のステータスメッセージ（空は表示していない）
    var statusMessage: String { statusLabel?.isHidden == false ? statusLabel?.stringValue ?? "" : "" }

    /// ステータスメッセージを出す。空なら消す。persistent でないものは 4 秒で消える
    func sendStatusMessage(_ text: String, persistent: Bool = false) {
        statusTimer?.invalidate()
        statusTimer = nil
        guard let host = enclosingScrollView else { return }
        if text.isEmpty {
            statusLabel?.isHidden = true
            return
        }
        let label: StatusMessageLabel
        if let existing = statusLabel, existing.superview === host {
            label = existing
        } else {
            label = StatusMessageLabel()
            host.addSubview(label, positioned: .above, relativeTo: nil)
            statusLabel = label
        }
        label.stringValue = " " + text + " "
        label.sizeToFit()
        // スクロールバーにかからない、編集画面の左下（行番号の右）
        let bottom = host.horizontalScroller.map { host.hasHorizontalScroller && !$0.isHidden ? $0.frame.height : 0 } ?? 0
        let width = min(label.frame.width, max(40, host.bounds.width - gutterWidth - 24))
        let y = host.isFlipped ? host.bounds.height - bottom - label.frame.height - 4 : bottom + 4
        label.frame = NSRect(x: gutterWidth + 4, y: y, width: width, height: label.frame.height)
        label.autoresizingMask = host.isFlipped ? [.minYMargin, .maxXMargin] : [.maxYMargin, .maxXMargin]
        label.isHidden = false
        if !persistent {
            let timer = Timer(timeInterval: 4, repeats: false) { [weak self] _ in
                self?.statusLabel?.isHidden = true
                self?.statusTimer = nil
            }
            RunLoop.main.add(timer, forMode: .common)
            statusTimer = timer
        }
    }

    /// 検索・ブックマーク等の結果のメッセージ（原版 STR_ERR_SRNEXT1/2、STR_ERR_SRPREV1/2）。
    /// wrapped：先頭（末尾）から再検索した、nil：見つからなかった
    func sendSearchStatus(next: Bool, wrapped: Bool?) {
        switch (next, wrapped) {
        case (true, true?): sendStatusMessage(NSLocalizedString("▼先頭から再検索しました", comment: "STR_ERR_SRNEXT1"))
        case (false, true?): sendStatusMessage(NSLocalizedString("▲末尾から再検索しました", comment: "STR_ERR_SRPREV1"))
        case (true, nil): sendStatusMessage(NSLocalizedString("▽見つかりませんでした", comment: "STR_ERR_SRNEXT2"))
        case (false, nil): sendStatusMessage(NSLocalizedString("△見つかりませんでした", comment: "STR_ERR_SRPREV2"))
        default: sendStatusMessage("")
        }
    }
}

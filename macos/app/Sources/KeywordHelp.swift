// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge

/// キーワードヘルプの小さな窓（第 44 步，原版 CTipWnd）。ダブルクリックで辞書のその行を開く
final class KeywordTipWindow: NSPanel {
    let label = NSTextField(wrappingLabelWithString: "")
    var onDoubleClick: (() -> Void)?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 100, height: 20), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        isReleasedWhenClosed = false
        hidesOnDeactivate = true
        hasShadow = true
        backgroundColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 0.2, alpha: 1) : NSColor(srgbRed: 1, green: 1, blue: 0.88, alpha: 1)
        }
        label.font = Self.font
        label.textColor = .labelColor
        label.setAccessibilityIdentifier("keywordTip")
        let content = NSView()
        content.addSubview(label)
        contentView = content
        content.wantsLayer = true
        content.layer?.borderWidth = 1
        content.layer?.borderColor = NSColor.separatorColor.cgColor
    }

    /// キーワードヘルプのフォント（共通設定『支援』の「キーワードヘルプのフォント」。原版 m_lf_kh）
    static var font: NSFont {
        let face = EditorCore.commonSetting(section: "Common", key: "khlfFaceName") ?? ""
        let points = Int(EditorCore.commonSetting(section: "Common", key: "khps") ?? "") ?? 0
        if face.isEmpty || points <= 0 { return NSFont.systemFont(ofSize: NSFont.smallSystemFontSize) }
        return LogFontSetting.font(face: face, pointSize: points, bold: false, italic: false)
    }

    /// 文字を入れて、左上が point（画面座標，原版 Show の x, y）になるように出す
    func show(_ text: String, at point: NSPoint, parent: NSWindow?) {
        label.font = Self.font
        label.stringValue = text
        let maxWidth: CGFloat = 480
        label.preferredMaxLayoutWidth = maxWidth
        let size = label.sizeThatFits(NSSize(width: maxWidth, height: .greatestFiniteMagnitude))
        label.frame = NSRect(x: 4, y: 3, width: ceil(size.width), height: ceil(size.height))
        var frame = NSRect(x: point.x, y: point.y - (ceil(size.height) + 6), width: ceil(size.width) + 8, height: ceil(size.height) + 6)
        if let screen = (parent?.screen ?? NSScreen.main)?.visibleFrame {
            if frame.maxX > screen.maxX { frame.origin.x = max(screen.minX, screen.maxX - frame.width) }
            if frame.minY < screen.minY { frame.origin.y = screen.minY }
        }
        setFrame(frame, display: true)
        if parent != nil && self.parent == nil { parent?.addChildWindow(self, ordered: .above) }
        orderFront(nil)
    }

    func hideTip() {
        parent?.removeChildWindow(self)
        orderOut(nil)
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { onDoubleClick?() }
    }
}

/// キーワードヘルプ（第 44 步，原版 CEditView::KeyWordHelpSearchDict・KeySearchCore、F_TOGGLE_KEY_SEARCH）
extension EditorTextView {
    /// キャレット位置の単語を辞書検索する（原版 m_Common.m_sSearch.m_bUseCaretKeyWord。sakura.ini には保存しない。最初は OFF）
    static var useCaretKeyWord = false

    /// 支援 > キーワードヘルプ自動表示（F_TOGGLE_KEY_SEARCH，原版 Command_ToggleKeySearch）
    @objc func toggleKeySearch(_ sender: Any?) {
        Self.useCaretKeyWord.toggle()
    }

    func validateKeywordHelpMenuItem(_ menuItem: NSMenuItem) -> Bool? {
        guard menuItem.action == #selector(toggleKeySearch(_:)) else { return nil }
        menuItem.state = Self.useCaretKeyWord ? .on : .off	// 原版 IsFuncChecked
        return true
    }

    /// マウスが止まってから辞書 Tip を出すまで（原版 OnTimer：300ms）
    static var keywordTipDelay: TimeInterval = 0.3

    /// マウスが動いた・キーを押した：辞書 Tip を消して、また待つ（原版 m_dwTipTimer = GetTickCount()）
    func restartKeywordTipTimer() {
        hideKeywordTip()
        keywordTipTimer?.invalidate()
        guard document.usesKeywordHelp else { return }
        let timer = Timer(timeInterval: Self.keywordTipDelay, repeats: false) { [weak self] _ in self?.keywordTipTimerFired() }
        RunLoop.main.add(timer, forMode: .common)
        keywordTipTimer = timer
    }

    /// 原版 KeyWordHelpSearchDict(LID_SKH_ONTIMER)：選択範囲（複数行なら先頭の行）、なければ（キャレット位置の単語を辞書検索するとき）
    /// キャレット位置の単語を辞書で探し、マウスの位置に出す
    func keywordTipTimerFired() {
        keywordTipTimer = nil
        guard document.usesKeywordHelp, window?.isKeyWindow == true, window?.firstResponder === self, !hokanActive,
              let window, NSMouseInRect(NSEvent.mouseLocation, window.convertToScreen(convert(visibleRect, to: nil)), false),
              let key = keywordHelpKey(), !key.isEmpty else { return }
        guard showKeywordTip(key, at: NSPoint(x: NSEvent.mouseLocation.x, y: NSEvent.mouseLocation.y - lineHeight)) else { return }
    }

    /// 探す文字（原版 GetSelectedDataOne(…, 101) か GetCurrentWord）
    func keywordHelpKey() -> String? {
        if let selection {
            let text = document.text(in: selection) as NSString
            var line = text.components(separatedBy: CharacterSet(charactersIn: "\r\n")).first ?? ""
            if (line as NSString).length > 101 { line = (line as NSString).substring(to: 101) }
            return line
        }
        guard Self.useCaretKeyWord else { return nil }
        var range = EditorRange()
        guard document.wordRange(at: caret, range: &range) else { return nil }
        return document.text(in: range)
    }

    /// 辞書 Tip を出す。ヒットしなければ false（原版：既に検索済みで該当キーがなかったときは探さない）
    @discardableResult
    func showKeywordTip(_ key: String, at point: NSPoint) -> Bool {
        if key == keywordTipKey && !keywordTipHit { return false }
        keywordTipKey = key
        let help = withSupportFileAccess { document.lookupKeywordHelp(key) }
        keywordTipHit = help != nil
        guard let help else { return false }
        let tip = keywordTip ?? KeywordTipWindow()
        keywordTip = tip
        tip.onDoubleClick = { [weak self] in self?.openKeywordDictionary(help) }
        tip.show(help.info, at: point, parent: window)
        return true
    }

    func hideKeywordTip() {
        keywordTip?.hideTip()
    }

    /// 辞書 Tip のダブルクリック：辞書のその行を開く（原版 CTipWnd → タグジャンプ）
    private func openKeywordDictionary(_ help: KeywordHelp) {
        hideKeywordTip()
        let path = document.supportFilePaths.first { ($0 as NSString).lastPathComponent == (help.dictionaryPath as NSString).lastPathComponent }
            ?? help.dictionaryPath
        _ = BookmarkStore.settingFiles.resolve(path: path)?.startAccessingSecurityScopedResource()
        openAndJump(path: path, line: help.line, column: 1, close: false)
    }

    /// 補完ウィンドウで選んでいる単語のキーワードヘルプ（原版 CHokanMgr::ShowTip）：補完ウィンドウの右に
    func hokanShowTip() {
        guard document.usesKeywordHelp, let controller = hokanWindow, controller.isVisible,
              let word = controller.selectedWord else { return }
        let row = controller.table.selectedRow
        let rowRect = controller.table.rect(ofRow: row)
        let inPanel = controller.table.convert(rowRect, to: nil)
        let screen = controller.panel.convertToScreen(inPanel)
        let point = NSPoint(x: controller.panel.frame.maxX, y: screen.maxY)
        if !showKeywordTip(word, at: point) { hideKeywordTip() }
    }
}

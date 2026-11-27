// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge

/// 模式切换和设定的命令（计划第 34 步。原版 CViewCommander_ModeChange.cpp、CViewCommander_Settings.cpp）。
///
/// - 挿入／上書きモード切り替え（Insert 键）：上書き时输入的字换掉光标处的字，光标变成一个字宽
/// - 文字コードセット指定：下次保存用的编码和 BOM（对话框与原版的「文字コードの指定」相同）
/// - 入力改行コード指定(CRLF/LF/CR/NEL/PS/LS)：现在的换行符打勾
/// - 現在のウィンドウ幅で折り返し：ウィンドウ幅 → 最大値 → 設定値 的切换（算法在核心库）
/// - フォントサイズ拡大／縮小：原版的倍率表。不保存（与原版的一時的な変更相同），所有窗口一起变（Mac 版的字体是共通的）
extension EditorTextView {
    // MARK: - 挿入／上書きモード

    /// 挿入／上書きモード切り替え（F_CHGMOD_INS）
    @objc func toggleInsertMode(_ sender: Any?) {
        document.insertMode.toggle()
        needsDisplay = true
    }

    /// 上書きモードで入力するか：上書きモード、没有选择、没有指定替换的范围时（原版 Command_WCHAR）
    func shouldOverwrite(replacementRange: NSRange) -> Bool {
        !document.insertMode && selection == nil && boxRange == nil && replacementRange.location == NSNotFound
    }

    /// 上書きモードの光标宽度：光标处的字的宽度（行末、TAB 时是半角一字。原版 CCaret::ShowEditCaret 的 Windows 型）
    var overwriteCaretWidth: CGFloat? {
        guard !document.insertMode, !hasMarkedText() else { return nil }
        let c = caretRowAndIndex
        let r = row(c.row)
        let text = r.text
        guard c.index < text.length, c.index + 1 < r.xs.count else { return charWidth }
        let ch = text.character(at: c.index)
        if ch == 0x09 || ch == 0x0A || ch == 0x0D { return charWidth }
        let end = NSMaxRange(text.rangeOfComposedCharacterSequence(at: c.index))
        return max(1, r.xs[min(end, r.xs.count - 1)] - r.xs[c.index])
    }

    // MARK: - 入力改行コード指定

    /// 入力改行コード指定（F_CHGMOD_EOL_CRLF～LS）：功能编号从菜单项的 tag、CommandSender 取得
    @objc func changeNewLineEol(_ sender: Any?) {
        guard let code = Self.commandCode(of: sender), (31081...31086).contains(code),
              document.isEnabled(code) else { return }
        _ = document.execute(code)
    }

    // MARK: - 文字コードセット指定

    /// 选择编码和 BOM 的对话框（原版 CDlgSetCharSet）。单元测试换成不出对话框的。
    /// 参数是视图、现在的编码和 BOM、结果（取消时 nil）
    static var chooseCharset: (EditorTextView, EditorEncoding, Bool, @escaping ((EditorEncoding, Bool)?) -> Void) -> Void = { view, encoding, bom, completion in
        let accessory = FileDialogAccessory(mode: .charset, encoding: encoding, bom: bom)
        let alert = NSAlert()
        alert.messageText = L10n.tr("文字コードの指定", comment: "IDD_SETCHARSET")
        alert.accessoryView = accessory.view
        accessory.view.frame.size = accessory.view.fittingSize
        alert.addButton(withTitle: L10n.tr("OK", comment: "IDD_SETCHARSET"))
        alert.addButton(withTitle: L10n.tr("キャンセル", comment: "IDD_SETCHARSET"))
        let handler: (NSApplication.ModalResponse) -> Void = { response in
            completion(response == .alertFirstButtonReturn ? (accessory.encoding, accessory.bom) : nil)
        }
        if let window = view.window, window.isVisible {
            alert.beginSheetModal(for: window, completionHandler: handler)
        } else {
            handler(alert.runModal())
        }
    }

    /// 文字コードセット指定（F_CHG_CHARSET）
    @objc func changeCharset(_ sender: Any?) {
        Self.chooseCharset(self, document.encoding, document.hasBOM) { [weak self] result in
            guard let self, let (encoding, bom) = result else { return }
            self.document.setEncoding(encoding, bom: bom)
            self.onChange?()	// 窗口的副标题（编码）、关闭时的确认
            self.needsDisplay = true
        }
    }

    // MARK: - 現在のウィンドウ幅で折り返し

    /// 現在のウィンドウ幅で折り返し（F_WRAPWINDOWWIDTH）：折り返し方法变成「指定桁で折り返す」
    @objc func wrapWindowWidthToggle(_ sender: Any?) {
        let visible = enclosingScrollView?.contentSize.width ?? frame.width
        let columns = document.wrapWindowWidthColumns(forWidth: Int(max(0, visible - textOriginX)))
        guard columns >= 0 else {
            // 原版も折り返し方法だけ「指定桁で折り返す」にする（桁数は元のまま）
            if document.setWrap(.settingWidth, columns: settings.wrapColumns) { contentDidChange() }
            return
        }
        if document.setWrap(.settingWidth, columns: columns) {
            if isBoxSelection { clearSelection() }
            contentDidChange()
        }
    }

    // MARK: - フォントサイズ

    /// フォントサイズ拡大（F_SETFONTSIZEUP）
    @objc func fontSizeUp(_ sender: Any?) {
        if !Self.zoomFont(steps: 1) { NSSound.beep() }
    }

    /// フォントサイズ縮小（F_SETFONTSIZEDOWN）
    @objc func fontSizeDown(_ sender: Any?) {
        if !Self.zoomFont(steps: -1) { NSSound.beep() }
    }

    // MARK: - 菜单

    /// 模式、设定的菜单项：可否执行和打勾（原版 IsFuncEnable / IsFuncChecked）。不是这里的项目时 nil
    func validateModeMenuItem(_ item: NSMenuItem) -> Bool? {
        switch item.action {
        case #selector(toggleInsertMode(_:)):
            item.state = document.insertMode ? .on : .off
            return true
        case #selector(changeNewLineEol(_:)):
            item.state = document.isChecked(item.tag) ? .on : .off
            return document.isEnabled(item.tag)
        case #selector(changeCharset(_:)), #selector(wrapWindowWidthToggle(_:)):
            return !hasMarkedText()
        case #selector(fontSizeUp(_:)), #selector(fontSizeDown(_:)):
            return true
        default:
            return nil
        }
    }
}

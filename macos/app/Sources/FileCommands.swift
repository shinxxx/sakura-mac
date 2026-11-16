// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge

/// ファイル菜单的命令（计划第 34 步。原版 CViewCommander_File.cpp、CDocFileOperation.cpp）。
///
/// - 閉じて(無題)：保存的确认之后，同一个窗口变成新文档
/// - 閉じて開く：保存的确认之后出「開く」对话框，选的文件在同一个窗口打开（取消时原来的文件留着）
/// - 保存して閉じる、上書き保存(限定動作)、すべて上書き保存（无题的窗口不保存）
/// - ○○で開き直す、開き直す：用指定的编码重新读入（修改过时先确认），光标和表示域留在原来的地方
/// 保存的确认用 macOS 的对话框（NSDocument.canClose），内容与原版相同（保存、不保存、取消）。
extension SakuraDocument {
    /// ○○で開き直す 的功能编号 → 编码（F_FILE_REOPEN_SJIS 等）。開き直す（30119）是现在的编码
    static let reopenEncodings: [Int: EditorEncoding] = [
        30111: ECEncodingSJIS,		// F_FILE_REOPEN_SJIS
        30112: ECEncodingJIS,		// F_FILE_REOPEN_JIS
        30113: ECEncodingEUC,		// F_FILE_REOPEN_EUC
        30114: ECEncodingUTF16LE,	// F_FILE_REOPEN_UNICODE
        30115: ECEncodingUTF8,		// F_FILE_REOPEN_UTF8
        30116: ECEncodingUTF7,		// F_FILE_REOPEN_UTF7
        30117: ECEncodingUTF16BE,	// F_FILE_REOPEN_UNICODEBE
        30118: ECEncodingCESU8,		// F_FILE_REOPEN_CESU8
        30122: ECEncodingLatin1,	// F_FILE_REOPEN_LATIN1
    ]
    static let reopenCurrent = 30119	// F_FILE_REOPEN

    var editorWindowController: EditorWindowController? {
        windowControllers.lazy.compactMap { $0 as? EditorWindowController }.first
    }

    // MARK: - 開き直す

    /// 重新读入前的确认（原版 STR_ERR_CEDITVIEW_CMD29）。单元测试换成不出对话框的。参数是路径，返回 true 继续
    static var confirmReload: (String) -> Bool = { path in
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = String(format: NSLocalizedString("%@\n\nこのファイルは変更されています。\n再ロードを行うと変更が失われますが、よろしいですか?",
                                                             comment: "STR_ERR_CEDITVIEW_CMD29"), path)
        alert.addButton(withTitle: NSLocalizedString("OK", comment: "メッセージボックス"))
        alert.addButton(withTitle: NSLocalizedString("キャンセル", comment: "メッセージボックス"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// ○○で開き直す（F_FILE_REOPEN_*）：功能编号从菜单项的 tag、CommandSender 取得
    @objc func reopenWithEncoding(_ sender: Any?) {
        guard let code = EditorTextView.commandCode(of: sender) else { return }
        if code == Self.reopenCurrent {
            reopen(encoding: editor.encoding)
        } else if let encoding = Self.reopenEncodings[code] {
            reopen(encoding: encoding)
        }
    }

    /// 用这个编码重新读入（原版 Command_FILE_REOPEN → CDocFileOperation::ReloadCurrentFile）
    func reopen(encoding: EditorEncoding, confirm: Bool = true) {
        guard let url = fileURL, FileManager.default.fileExists(atPath: url.path) else {
            // ファイルが存在しない：文字コードだけ設定（BOM は標準設定）
            editor.setEncoding(encoding, bom: EditorCore.bomDefault(encoding))
            contentDidChange()
            return
        }
        if confirm && editor.isModified && !Self.confirmReload(url.path) { return }
        guard let view = editorWindowController?.textView else { return }
        // カーソル位置と表示域を保存して、読み直した後で戻す
        let caret = view.caret
        let top = view.topVisibleRow
        let result = editor.open(path: url.path, encoding: encoding)
        guard result == .success || result == .lostSome else {
            NSSound.beep()
            return
        }
        fileModificationDate = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        view.textChanged()
        view.restoreView(caret: caret, topRow: top, toEnd: false)	// 范围外时 setCaret 收到范围内
        contentDidChange()
        if result == .lostSome {
            showLostSomeMessage()
        }
    }

    // MARK: - 閉じて(無題)、閉じて開く

    /// 閉じて(無題)（F_FILECLOSE）
    @objc func closeToUntitled(_ sender: Any?) {
        confirmClose { [weak self] in self?.resetToUntitled() }
    }

    /// 閉じて開く（F_FILECLOSE_OPEN）：「開く」で取消したときは元のファイルが残る（原版も同じ）
    @objc func closeAndOpen(_ sender: Any?) {
        confirmClose { [weak self] in
            guard let self else { return }
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = true
            NSDocumentController.shared.beginOpenPanel(panel, forTypes: nil) { result in
                guard result == NSApplication.ModalResponse.OK.rawValue, let first = panel.urls.first else { return }
                self.replace(with: first)
                // 他のファイルは新規ウィンドウ
                for url in panel.urls.dropFirst() {
                    NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
                }
            }
        }
    }

    /// 保存的确认（原版 CEditDoc::OnFileClose）之后执行 then。取消时什么也不做
    func confirmClose(then: @escaping () -> Void) {
        CloseConfirmation(then: then).ask(self)
    }

    /// 内容、文件名都清除，同一个窗口变成新文档（原版 CDocFileOperation::FileClose）
    func resetToUntitled() {
        addToRecent()		// ファイルを閉じるときのMRU登録
        editor.closeToUntitled()
        fileURL = nil
        fileModificationDate = nil
        updateChangeCount(.changeCleared)
        if let view = editorWindowController?.textView {
            view.textChanged()
            view.setCaret(EditorPosition(line: 0, column: 0))
            view.scrollRow(toTop: 0)
        }
        contentDidChange()
    }

    /// 这个窗口换成 url 的文件（閉じて開く）。已经在别的窗口打开时显示那个窗口，这个窗口留下无题（原版相同）
    func replace(with url: URL) {
        resetToUntitled()
        if let other = NSDocumentController.shared.document(for: url) {
            other.showWindows()
            return
        }
        let key = Self.encodingKey(url)
        let encoding = Self.requestedEncodings.removeValue(forKey: key) ?? ECEncodingAutoDetect
        let path = url.path
        let result = editor.open(path: path, encoding: encoding) { current, previous in
            Self.askUsePreviousEncoding(path, current, previous)
        }
        guard result == .success || result == .lostSome else {
            editor.closeToUntitled()
            NSApp.presentError(CocoaError(.fileReadNoSuchFile, userInfo: [NSURLErrorKey: url]))
            return
        }
        fileURL = url
        fileModificationDate = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
        BookmarkStore.shared.remember(url)
        if let view = editorWindowController?.textView {
            view.textChanged()
            if let restored = editor.restoredView {
                view.restoreView(caret: restored.caret, topRow: restored.viewTopLine, toEnd: restored.toEnd)
            } else {
                view.setCaret(EditorPosition(line: 0, column: 0))
            }
        }
        contentDidChange()
        if result == .lostSome { showLostSomeMessage() }
    }

    // MARK: - 保存

    /// 上書き保存できるか（原版 IsFuncEnable の F_FILESAVE：変更あり、文字コードセットの変更、無変更でも上書き）
    var canSaveInPlace: Bool {
        fileURL != nil && (editor.isEnabled(30103) || editor.isEncodingChanged)
    }

    /// 上書き保存(限定動作)（F_FILESAVE_QUIET）：ファイル名がない（無題）ときは何もしない
    @objc func saveQuietly(_ sender: Any?) {
        guard canSaveInPlace else { return }
        save(sender)
    }

    /// 保存して閉じる（F_FILESAVECLOSE）：保存が不要なら単に閉じる。無題は「名前を付けて保存」してから閉じる
    @objc func saveAndClose(_ sender: Any?) {
        if !editor.isModified && !editor.isEncodingChanged && !canSaveInPlace {
            close()
            return
        }
        save(withDelegate: self, didSave: #selector(SakuraDocument.document(_:didSaveForClose:contextInfo:)), contextInfo: nil)
    }

    @objc private func document(_ document: NSDocument, didSaveForClose didSave: Bool, contextInfo: UnsafeMutableRawPointer?) {
        if didSave { close() }
    }

    // MARK: - 菜单

    /// ファイル菜单的项目：可否执行和打勾。不是这里的项目时 nil
    func validateFileCommand(_ item: NSValidatedUserInterfaceItem) -> Bool? {
        switch item.action {
        case #selector(reopenWithEncoding(_:)):
            // 現在の文字コードにチェック（原版 IsFuncChecked）
            if let menuItem = item as? NSMenuItem {
                menuItem.state = editor.isChecked(menuItem.tag) ? .on : .off
            }
            return true
        case #selector(saveQuietly(_:)):
            return canSaveInPlace
        default:
            return nil
        }
    }
}

/// 保存的确认（NSDocument.canClose 的回调要 Objective-C 的选择子）
private final class CloseConfirmation: NSObject {
    let then: () -> Void
    private var keep: CloseConfirmation?

    init(then: @escaping () -> Void) {
        self.then = then
    }

    func ask(_ document: NSDocument) {
        keep = self		// 回调之前不释放
        document.canClose(withDelegate: self, shouldClose: #selector(CloseConfirmation.document(_:shouldClose:contextInfo:)), contextInfo: nil)
    }

    @objc private func document(_ document: NSDocument, shouldClose: Bool, contextInfo: UnsafeMutableRawPointer?) {
        if shouldClose { then() }
        keep = nil
    }
}

extension SakuraDocumentController {
    /// すべて上書き保存（F_FILESAVEALL）：编辑中的所有窗口执行「上書き保存(限定動作)」（无题的不保存）
    @objc func saveAllQuietly(_ sender: Any?) {
        for case let document as SakuraDocument in documents {
            document.saveQuietly(sender)
        }
    }
}

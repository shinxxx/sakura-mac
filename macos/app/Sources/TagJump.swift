// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge

/// タグジャンプ（第 43 步。原版 CViewCommander_TagJump.cpp の Command_TAGJUMP・Command_TAGJUMPBACK、CEditView::TagJumpSub）。
///
/// 飛び先は核心库が決める（EditorDocument.tagJump(at:)：Grep の結果の各形式、「ファイル名(行,桁)」のメッセージ）。
/// tags ファイルのタグジャンプ（ダイレクトタグジャンプ）は第 44 步。
/// 原版は戻り先を共有メモリに積む（CTagJumpManager。最大 MAX_TAGJUMPNUM 個）。Mac 版は App の中に積む。
enum TagJumpStack {
    struct Entry {
        weak var view: EditorTextView?
        let position: EditorPosition
    }
    /// 原版 MAX_TAGJUMPNUM
    static let limit = 100
    static var entries: [Entry] = []

    static func push(_ view: EditorTextView, _ position: EditorPosition) {
        entries.append(Entry(view: view, position: position))
        if entries.count > limit { entries.removeFirst(entries.count - limit) }
    }

    static func pop() -> Entry? {
        entries.popLast()
    }
}

extension EditorTextView {
    /// 検索 > タグジャンプ（F_TAGJUMP）
    @objc func tagJump(_ sender: Any?) {
        tagJump(close: false)
    }

    /// 検索 > 閉じてタグジャンプ（F_TAGJUMP_CLOSE）：元の窓口を閉じる
    @objc func tagJumpClose(_ sender: Any?) {
        tagJump(close: true)
    }

    /// 検索 > タグジャンプバック（F_TAGJUMPBACK）：ジャンプした元の窓口のジャンプした位置に戻る
    @objc func tagJumpBack(_ sender: Any?) {
        guard let entry = TagJumpStack.pop(), let view = entry.view, let window = view.window else {
            NSSound.beep()
            sendStatusMessage(NSLocalizedString("タグジャンプバックできません", comment: "STR_ERR_TAGJMPBK1"))	// 第 44 步
            return
        }
        window.makeKeyAndOrderFront(nil)
        view.jumpToTagPosition(line: entry.position.line + 1, column: entry.position.column + 1)
    }

    /// 開いている文書（単体テストでは差し替える）
    static var openDocuments: () -> [NSDocument] = { NSDocumentController.shared.documents }
    /// ファイルを開く（単体テストでは差し替える）
    static var openForTagJump: (URL, @escaping (NSDocument?, Error?) -> Void) -> Void = { url, completion in
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { document, _, error in completion(document, error) }
    }

    /// 窓口のどれかの、この番号の文書（「編集中のテキストから検索」の結果の :HWND:[番号]）
    static func view(grepSourceID id: UInt64) -> EditorTextView? {
        for document in openDocuments() {
            if let view = (document as? SakuraDocument)?.editorWindowController?.textView, view.grepSourceID == id {
                return view
            }
        }
        return nil
    }

    /// タグジャンプ（原版 Command_TagJumpNoMessage + TagJumpSub）。飛べたら true
    @discardableResult
    func tagJump(close: Bool) -> Bool {
        guard let target = document.tagJump(at: caret.line) else {
            NSSound.beep()	// 原版はステータスバーに「タグジャンプできません」
            return false
        }
        let origin = caret
        let line = target.line, column = target.column
        if target.hasSourceID {
            guard let view = Self.view(grepSourceID: target.sourceID) else {
                NSSound.beep()
                return false
            }
            TagJumpStack.push(self, origin)
            view.window?.makeKeyAndOrderFront(nil)
            if line > 0 { view.jumpToTagPosition(line: line, column: column) }
            if close && view !== self { window?.performClose(nil) }
            return true
        }
        let path = target.path
        FolderAccess.shared.startAccess(file: path)
        TagJumpStack.push(self, origin)
        openAndJump(path: path, line: line, column: column, close: close)
        return true
    }

    /// ファイルを開いて（開いていればその窓口で）行・桁へ移る。close：元の窓口を閉じる（原版 TagJumpSub）
    func openAndJump(path: String, line: Int, column: Int, close: Bool) {
        let url = URL(fileURLWithPath: path)
        let sourceWindow = window
        let selfView = self
        Self.openForTagJump(url) { document, error in
            guard let view = (document as? SakuraDocument)?.editorWindowController?.textView else {
                if let error { NSApp.presentError(error) }
                return
            }
            view.window?.makeKeyAndOrderFront(nil)
            if line > 0 { view.jumpToTagPosition(line: line, column: column) }
            if close && view !== selfView { sourceWindow?.performClose(nil) }
        }
    }

    /// 行・桁（1 開始。桁が 0 なら行頭）へ移る（原版 MYWM_SETCARETPOS）
    func jumpToTagPosition(line: Int, column: Int) {
        jumpFromOutline(line: line - 1, column: max(0, column - 1))
    }
}

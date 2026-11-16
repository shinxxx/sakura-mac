// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit

/// 原版的功能编号（EFunctionCode，Funccode_x.hsrc）→ Mac 版的动作（第 34 步）。
///
/// 菜单（MainMenuBuilder）和快捷键（KeyCommands）都按这个表执行：菜单项的 tag 是功能编号，
/// action 是这里的选择子，目标是 nil（沿响应链找编辑画面、文档、App）。
/// 表里没有的功能还没有移植：菜单项没有动作，macOS 自动变灰；分配了这个功能的按键按普通的输入处理。
/// 各功能在哪一步移植见 macos/docs/feature-matrix.csv。
enum CommandTable {
    /// 功能编号 → 选择子。AppDelegate 的动作写成字符串（单元测试里没有 AppDelegate）
    static let selectors: [Int: Selector] = [
        // ファイル（第 26 步：NSDocumentController / NSDocument）
        30101: #selector(NSDocumentController.newDocument(_:)),		// F_FILENEW 新規作成
        30102: #selector(NSDocumentController.openDocument(_:)),	// F_FILEOPEN 開く
        30103: #selector(NSDocument.save(_:)),						// F_FILESAVE 上書き保存
        30104: #selector(NSDocument.saveAs(_:)),					// F_FILESAVEAS_DIALOG 名前を付けて保存
        30195: #selector(NSApplication.terminate(_:)),				// F_EXITALL サクラエディタの全終了

        // 編集（第 25、28、29 步）
        30210: #selector(EditorTextView.undo(_:)),					// F_UNDO
        30211: #selector(EditorTextView.redo(_:)),					// F_REDO
        30601: #selector(EditorTextView.cut(_:)),					// F_CUT
        30602: #selector(EditorTextView.copy(_:)),					// F_COPY
        30604: #selector(EditorTextView.paste(_:)),					// F_PASTE
        30605: #selector(EditorTextView.pasteAsBox(_:)),			// F_PASTEBOX 矩形貼り付け
        30221: #selector(EditorTextView.delete(_:)),				// F_DELETE
        30222: #selector(EditorTextView.deleteBack(_:)),			// F_DELETE_BACK
        30401: #selector(EditorTextView.selectAll(_:)),				// F_SELECTALL
        30260: #selector(EditorTextView.indentTab(_:)),				// F_INDENT_TAB
        30261: #selector(EditorTextView.unindentTab(_:)),			// F_UNINDENT_TAB

        // 移動・選択・矩形選択（第 34 步：CursorCommands.swift。普通、(範囲選択)、(矩形選択) 都经过 cursorCommandAction）
        30360: #selector(EditorTextView.curLineCenter(_:)),			// F_CURLINECENTER
        30361: #selector(EditorTextView.curLineTop(_:)),			// F_CURLINETOP
        30362: #selector(EditorTextView.curLineBottom(_:)),			// F_CURLINEBOTTOM
        30370: #selector(EditorTextView.jumpHistoryPrev(_:)),		// F_JUMPHIST_PREV
        30371: #selector(EditorTextView.jumpHistoryNext(_:)),		// F_JUMPHIST_NEXT
        30372: #selector(EditorTextView.jumpHistorySet(_:)),		// F_JUMPHIST_SET
        30380: #selector(EditorTextView.wndScrollDown(_:)),			// F_WndScrollDown
        30381: #selector(EditorTextView.wndScrollUp(_:)),			// F_WndScrollUp
        30400: #selector(EditorTextView.selectCurrentWord(_:)),		// F_SELECTWORD
        30403: #selector(EditorTextView.selectCurrentLine(_:)),		// F_SELECTLINE
        30410: #selector(EditorTextView.beginSelection(_:)),		// F_BEGIN_SEL
        30510: #selector(EditorTextView.beginBoxSelectionAction(_:)),	// F_BEGIN_BOX
        31099: #selector(NSResponder.cancelOperation(_:)),			// F_CANCEL_MODE 各種モードの取り消し

        // 検索（第 32 步）
        30901: #selector(EditorTextView.showFindPanel(_:)),			// F_SEARCH_DIALOG
        30902: #selector(EditorTextView.searchNext(_:)),			// F_SEARCH_NEXT
        30903: #selector(EditorTextView.searchPrevious(_:)),		// F_SEARCH_PREV
        30904: #selector(EditorTextView.showReplacePanel(_:)),		// F_REPLACE_DIALOG
        30905: #selector(EditorTextView.toggleSearchMark(_:)),		// F_SEARCH_CLEARMARK
        30909: #selector(EditorTextView.jumpToSearchStart(_:)),		// F_JUMP_SRCHSTARTPOS
        30920: #selector(EditorTextView.showJumpDialog(_:)),		// F_JUMP_DIALOG

        // 設定（第 27、28 步）
        31120: #selector(EditorTextView.showFontPanel(_:)),			// F_FONT フォント設定
        31141: #selector(EditorTextView.wrapNone(_:)),				// F_TMPWRAPNOWRAP
        31142: #selector(EditorTextView.wrapSettingWidth(_:)),		// F_TMPWRAPSETTING
        31143: #selector(EditorTextView.wrapWindowWidth(_:)),		// F_TMPWRAPWINDOW

        // ウィンドウ（第 26 步）
        31320: #selector(NSWindow.performClose(_:)),				// F_WINCLOSE 閉じる
        31340: Selector(("activateNextWindow:")),					// F_NEXTWINDOW（AppDelegate）
        31341: Selector(("activatePreviousWindow:")),				// F_PREVWINDOW（AppDelegate）

        // ヘルプ（バージョン情報は第 34 步的第 3 个 PR 换成原版的内容）
        31455: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),	// F_ABOUT
    ]

    /// 这个功能的动作。还没有移植时是 nil
    static func selector(for code: Int) -> Selector? {
        if let selector = selectors[code] { return selector }
        if EditorTextView.cursorCommands[code] != nil { return #selector(EditorTextView.cursorCommandAction(_:)) }
        if (30385...30392).contains(code) { return #selector(EditorTextView.wheelCommandAction(_:)) }	// F_WHEELUP～F_WHEELPAGERIGHT
        return nil
    }

    /// 按功能编号执行：先从 view 沿响应链找（单元测试里窗口不是 key 也能用），再交给 NSApp。
    /// sender 是带着功能编号的 CommandSender（几个功能共用一个动作时用来区分）。执行了时返回 true
    @discardableResult
    static func perform(_ code: Int, from responder: NSResponder?) -> Bool {
        guard let selector = selector(for: code) else { return false }
        let sender = CommandSender(code)
        if let responder, responder.tryToPerform(selector, with: sender) { return true }
        return NSApp.sendAction(selector, to: nil, from: sender)
    }
}

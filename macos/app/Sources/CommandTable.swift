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
        // 第 34 步：FileCommands.swift
        30105: #selector(SakuraDocument.closeToUntitled(_:)),		// F_FILECLOSE 閉じて(無題)
        30107: #selector(SakuraDocument.closeAndOpen(_:)),			// F_FILECLOSE_OPEN 閉じて開く
        30109: #selector(SakuraDocument.saveAndClose(_:)),			// F_FILESAVECLOSE 保存して閉じる
        30110: #selector(NSDocumentController.newDocument(_:)),	// F_FILENEW_NEWWINDOW（Mac 版は一つのプロセスで新しいウィンドウ）
        30111: #selector(SakuraDocument.reopenWithEncoding(_:)),	// F_FILE_REOPEN_SJIS
        30112: #selector(SakuraDocument.reopenWithEncoding(_:)),	// F_FILE_REOPEN_JIS
        30113: #selector(SakuraDocument.reopenWithEncoding(_:)),	// F_FILE_REOPEN_EUC
        30114: #selector(SakuraDocument.reopenWithEncoding(_:)),	// F_FILE_REOPEN_UNICODE
        30115: #selector(SakuraDocument.reopenWithEncoding(_:)),	// F_FILE_REOPEN_UTF8
        30116: #selector(SakuraDocument.reopenWithEncoding(_:)),	// F_FILE_REOPEN_UTF7
        30117: #selector(SakuraDocument.reopenWithEncoding(_:)),	// F_FILE_REOPEN_UNICODEBE
        30118: #selector(SakuraDocument.reopenWithEncoding(_:)),	// F_FILE_REOPEN_CESU8
        30119: #selector(SakuraDocument.reopenWithEncoding(_:)),	// F_FILE_REOPEN 開き直す
        30120: #selector(SakuraDocumentController.saveAllQuietly(_:)),	// F_FILESAVEALL すべて上書き保存
        30121: #selector(SakuraDocument.saveQuietly(_:)),			// F_FILESAVE_QUIET 上書き保存(限定動作)
        30122: #selector(SakuraDocument.reopenWithEncoding(_:)),	// F_FILE_REOPEN_LATIN1
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

        // モード切り替え（第 34 步：ModeCommands.swift）
        31001: #selector(EditorTextView.toggleInsertMode(_:)),		// F_CHGMOD_INS 挿入／上書きモード切り替え
        31010: #selector(EditorTextView.changeCharset(_:)),			// F_CHG_CHARSET 文字コードセット指定
        31081: #selector(EditorTextView.changeNewLineEol(_:)),		// F_CHGMOD_EOL_CRLF 入力改行コード指定
        31082: #selector(EditorTextView.changeNewLineEol(_:)),		// F_CHGMOD_EOL_LF
        31083: #selector(EditorTextView.changeNewLineEol(_:)),		// F_CHGMOD_EOL_CR
        31084: #selector(EditorTextView.changeNewLineEol(_:)),		// F_CHGMOD_EOL_NEL
        31085: #selector(EditorTextView.changeNewLineEol(_:)),		// F_CHGMOD_EOL_PS
        31086: #selector(EditorTextView.changeNewLineEol(_:)),		// F_CHGMOD_EOL_LS

        // 検索（第 32 步）
        30901: #selector(EditorTextView.showFindPanel(_:)),			// F_SEARCH_DIALOG
        30902: #selector(EditorTextView.searchNext(_:)),			// F_SEARCH_NEXT
        30903: #selector(EditorTextView.searchPrevious(_:)),		// F_SEARCH_PREV
        30904: #selector(EditorTextView.showReplacePanel(_:)),		// F_REPLACE_DIALOG
        30905: #selector(EditorTextView.toggleSearchMark(_:)),		// F_SEARCH_CLEARMARK
        30909: #selector(EditorTextView.jumpToSearchStart(_:)),		// F_JUMP_SRCHSTARTPOS
        30920: #selector(EditorTextView.showJumpDialog(_:)),		// F_JUMP_DIALOG
        // 第 43 步：Grep・Grep置換・タグジャンプ（GrepDialog.swift、GrepRunner.swift、TagJump.swift）
        30910: #selector(EditorTextView.showGrepDialog(_:)),		// F_GREP_DIALOG Grep
        30912: #selector(EditorTextView.showGrepReplaceDialog(_:)),	// F_GREP_REPLACE_DLG Grep置換
        30940: #selector(EditorTextView.tagJump(_:)),				// F_TAGJUMP タグジャンプ
        30941: #selector(EditorTextView.tagJumpBack(_:)),			// F_TAGJUMPBACK タグジャンプバック
        30945: #selector(EditorTextView.tagJumpClose(_:)),			// F_TAGJUMP_CLOSE 閉じてタグジャンプ
        // 第 44 步：編集支援（BracketPair.swift 等）
        30960: #selector(EditorTextView.bracketPair(_:)),			// F_BRACKETPAIR 対括弧の検索
        // 第 42 步：アウトライン解析（OutlineWindow.swift）
        30930: #selector(EditorTextView.showOutline(_:)),			// F_OUTLINE アウトライン解析
        30931: #selector(EditorTextView.toggleOutline(_:)),			// F_OUTLINE_TOGGLE アウトライン解析(toggle)
        30990: #selector(EditorTextView.showFileTree(_:)),			// F_FILETREE ファイルツリー
        30988: #selector(EditorTextView.funcListNext(_:)),			// F_FUNCLIST_NEXT 次の関数リストマークへ
        30989: #selector(EditorTextView.funcListPrev(_:)),			// F_FUNCLIST_PREV 前の関数リストマークへ

        // 設定（第 27、28 步）
        31120: #selector(EditorTextView.showFontPanel(_:)),			// F_FONT フォント設定
        31122: #selector(EditorTextView.fontSizeUp(_:)),			// F_SETFONTSIZEUP フォントサイズ拡大（第 34 步）
        31123: #selector(EditorTextView.fontSizeDown(_:)),			// F_SETFONTSIZEDOWN フォントサイズ縮小
        31140: #selector(EditorTextView.wrapWindowWidthToggle(_:)),	// F_WRAPWINDOWWIDTH 現在のウィンドウ幅で折り返し
        31141: #selector(EditorTextView.wrapNone(_:)),				// F_TMPWRAPNOWRAP
        31142: #selector(EditorTextView.wrapSettingWidth(_:)),		// F_TMPWRAPSETTING
        31143: #selector(EditorTextView.wrapWindowWidth(_:)),		// F_TMPWRAPWINDOW
        // 第 39 步：共通設定（CommonSettingsWindow.swift）。各页的功能打开那一页
        31112: #selector(NSApplication.showCommonSettings(_:)),	// F_OPTION 共通設定
        32000: #selector(NSApplication.showCommonSettings(_:)),	// F_OPTION_GENERAL 共通設定『全般』
        32001: #selector(NSApplication.showCommonSettings(_:)),	// F_OPTION_WINDOW
        32002: #selector(NSApplication.showCommonSettings(_:)),	// F_OPTION_EDIT
        32003: #selector(NSApplication.showCommonSettings(_:)),	// F_OPTION_FILE
        32004: #selector(NSApplication.showCommonSettings(_:)),	// F_OPTION_BACKUP
        32005: #selector(NSApplication.showCommonSettings(_:)),	// F_OPTION_FORMAT
        32007: #selector(NSApplication.showCommonSettings(_:)),	// F_OPTION_GREP
        32008: #selector(NSApplication.showCommonSettings(_:)),	// F_OPTION_KEYBIND
        32009: #selector(NSApplication.showCommonSettings(_:)),	// F_OPTION_CUSTMENU
        32010: #selector(NSApplication.showCommonSettings(_:)),	// F_OPTION_TOOLBAR
        32011: #selector(NSApplication.showCommonSettings(_:)),	// F_OPTION_KEYWORD
        32012: #selector(NSApplication.showCommonSettings(_:)),	// F_OPTION_HELPER
        32013: #selector(NSApplication.showCommonSettings(_:)),	// F_OPTION_MACRO
        32014: #selector(NSApplication.showCommonSettings(_:)),	// F_OPTION_FNAME
        32015: #selector(NSApplication.showCommonSettings(_:)),	// F_OPTION_TAB
        32016: #selector(NSApplication.showCommonSettings(_:)),	// F_OPTION_STATUSBAR
        32017: #selector(NSApplication.showCommonSettings(_:)),	// F_OPTION_PLUGIN
        32018: #selector(NSApplication.showCommonSettings(_:)),	// F_OPTION_MAINMENU

        // 第 40 步：タイプ別設定（TypeSettingsWindow.swift）。この文書のタイプ。各页的功能打开那一页
        31110: #selector(EditorTextView.showTypeList(_:)),			// F_TYPE_LIST タイプ別設定一覧
        31111: #selector(EditorTextView.showTypeSettings(_:)),		// F_OPTION_TYPE タイプ別設定
        31114: #selector(EditorTextView.showTypeSettings(_:)),		// F_TYPE_WINDOW タイプ別設定『ウィンドウ』
        31115: #selector(EditorTextView.showTypeSettings(_:)),		// F_TYPE_SCREEN タイプ別設定『スクリーン』
        31116: #selector(EditorTextView.showTypeSettings(_:)),		// F_TYPE_COLOR
        31117: #selector(EditorTextView.showTypeSettings(_:)),		// F_TYPE_HELPER
        31118: #selector(EditorTextView.showTypeSettings(_:)),		// F_TYPE_REGEX_KEYWORD
        31119: #selector(EditorTextView.showTypeSettings(_:)),		// F_TYPE_KEYHELP

        // ウィンドウ（第 26 步）
        31320: #selector(NSWindow.performClose(_:)),				// F_WINCLOSE 閉じる
        31340: Selector(("activateNextWindow:")),					// F_NEXTWINDOW（AppDelegate）
        31341: Selector(("activatePreviousWindow:")),				// F_PREVWINDOW（AppDelegate）

        // ヘルプ（第 34 步：AboutPanel.swift，原版的内容）
        31455: #selector(NSApplication.showSakuraAbout(_:)),		// F_ABOUT バージョン情報
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

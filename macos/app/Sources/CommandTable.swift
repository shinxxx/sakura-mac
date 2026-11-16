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

        // 移動・選択（第 28 步。其余的在第 34 步的第 2 个 PR）
        30311: #selector(NSResponder.moveUp(_:)),					// F_UP
        30312: #selector(NSResponder.moveDown(_:)),					// F_DOWN
        30313: #selector(NSResponder.moveLeft(_:)),					// F_LEFT
        30314: #selector(NSResponder.moveRight(_:)),				// F_RIGHT
        30332: #selector(NSResponder.moveToBeginningOfLine(_:)),	// F_GOLINETOP
        30333: #selector(NSResponder.moveToEndOfLine(_:)),			// F_GOLINEEND
        30350: #selector(NSResponder.moveToBeginningOfDocument(_:)),	// F_GOFILETOP
        30351: #selector(NSResponder.moveToEndOfDocument(_:)),		// F_GOFILEEND
        30411: #selector(NSResponder.moveUpAndModifySelection(_:)),		// F_UP_SEL
        30412: #selector(NSResponder.moveDownAndModifySelection(_:)),	// F_DOWN_SEL
        30413: #selector(NSResponder.moveLeftAndModifySelection(_:)),	// F_LEFT_SEL
        30414: #selector(NSResponder.moveRightAndModifySelection(_:)),	// F_RIGHT_SEL
        30432: #selector(NSResponder.moveToBeginningOfLineAndModifySelection(_:)),		// F_GOLINETOP_SEL
        30433: #selector(NSResponder.moveToEndOfLineAndModifySelection(_:)),			// F_GOLINEEND_SEL
        30450: #selector(NSResponder.moveToBeginningOfDocumentAndModifySelection(_:)),	// F_GOFILETOP_SEL
        30451: #selector(NSResponder.moveToEndOfDocumentAndModifySelection(_:)),		// F_GOFILEEND_SEL
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
        selectors[code]
    }

    /// 按功能编号执行：先从 view 沿响应链找（单元测试里窗口不是 key 也能用），再交给 NSApp。
    /// 执行了时返回 true
    @discardableResult
    static func perform(_ code: Int, from responder: NSResponder?) -> Bool {
        guard let selector = selector(for: code) else { return false }
        if let responder, responder.tryToPerform(selector, with: responder) { return true }
        return NSApp.sendAction(selector, to: nil, from: responder)
    }
}

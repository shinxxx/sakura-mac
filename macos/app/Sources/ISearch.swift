// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge

/// インクリメンタルサーチの状態（第 44 步，原版 CEditView の m_nISearchMode、m_nISearchDirection 等）
struct ISearchState {
    enum Mode: Int {
        case none = 0, normal, regexp, migemo	// 原版 SEARCH_NONE、SEARCH_NORMAL、SEARCH_REGEXP、SEARCH_MIGEMO
    }
    var mode: Mode = .none
    /// 検索方向（原版 m_nISearchDirection。初期値は後方）
    var forward = false
    /// 最初の文字の入力で検索文字列を空にする（原版 m_bISearchFirst）
    var first = false
    /// 見つからなかった：次の「次を検索」は先頭（末尾）から（原版 m_bISearchWrap）
    var wrap = false
    /// 1 文字ずつの履歴（原版 m_sISearchHistory・m_bISearchFlagHistory・m_nISearchHistoryCount）。
    /// 範囲（選択していないときはカーソル位置の空の範囲）と、「次を検索」だったか
    var history = [EditorRange](repeating: EditorRange(), count: 256)
    var flagHistory = [Bool](repeating: false, count: 256)
    var historyCount = 0

    var isActive: Bool { mode != .none }
}

extension EditorDocument {
    /// インクリメンタルサーチの検索（見つからないときは nil）
    func isearchFind(_ key: String, from: EditorPosition, forward: Bool, options: EditorSearchOptions, migemo: Bool) -> EditorRange? {
        var range = EditorRange()
        return isearchFind(key, from: from, forward: forward, options: options, migemo: migemo, range: &range) ? range : nil
    }
}

/// インクリメンタルサーチ（F_ISEARCH_NEXT/PREV、REGEXP_NEXT/PREV、MIGEMO_NEXT/PREV。原版 view/CEditView_Cmdisrch.cpp）
extension EditorTextView {
    /// インクリメンタルサーチの機能番号（原版 F_ISEARCH_NEXT ～ F_ISEARCH_MIGEMO_PREV）
    static let isearchCommands: [Int: (mode: ISearchState.Mode, forward: Bool)] = [
        30981: (.normal, true), 30982: (.normal, false),
        30983: (.regexp, true), 30984: (.regexp, false),
        30985: (.migemo, true), 30986: (.migemo, false),
    ]

    /// 検索 > インクリメンタルサーチ の各機能（sender の機能番号で区別）
    @objc func isearchCommand(_ sender: Any?) {
        guard let code = (sender as? CommandSender)?.code ?? (sender as? NSMenuItem)?.tag,
              let command = Self.isearchCommands[code] else { return }
        isearchEnter(command.mode, forward: command.forward)
    }

    /// メニューのチェック（原版 IsISearchEnabled）
    func validateISearchMenuItem(_ menuItem: NSMenuItem) -> Bool? {
        guard menuItem.action == #selector(isearchCommand(_:)), let command = Self.isearchCommands[menuItem.tag] else { return nil }
        menuItem.state = isearch.mode == command.mode && isearch.forward == command.forward ? .on : .off
        return !hasMarkedText()
    }

    /// インクリメンタルサーチモードに入る（原版 ISearchEnter）。同じモードのときは次を検索
    func isearchEnter(_ mode: ISearchState.Mode, forward: Bool) {
        if isearch.mode == mode {
            isearch.forward = forward
            if isearch.first { isearch.first = false }
            isearchExec(next: true)
            return
        }
        clearSelection()	// 選択範囲の解除
        var options = EditorCore.searchSettings.options
        switch mode {
        case .normal:
            options = []
        case .regexp:
            options.insert(.regularExpression)
            options.remove(.matchCase)
        case .migemo:
            guard prepareMigemo() else { return }
            options.insert(.regularExpression)
            options.remove(.matchCase)
        case .none:
            break
        }
        searchState.options = options
        // 検索開始位置を記録。インクリメンタルサーチ間でモードを切り替える場合には開始と見なさない
        if isearch.mode == .none { searchState.startPosition = caret }
        searchState.markOn = false
        isearch.forward = forward
        isearch.mode = mode
        isearch.historyCount = 0
        isearch.history[0] = EditorRange(from: caret, to: caret)
        needsDisplay = true
        sendStatusMessage(isearchStatusMessage, persistent: true)
        isearch.wrap = false
        isearch.first = true
    }

    /// MIGEMO の辞書を読む。辞書のフォルダーは共通設定『支援』の「辞書」（沙盒：フォルダーの許可）
    private func prepareMigemo() -> Bool {
        let folder = Self.migemoDictionaryFolder
        if !FolderAccess.shared.startAccess(path: folder) && !FolderAccess.doesNotExist(folder) {
            _ = FolderAccess.shared.ensureAccess(paths: [folder], parent: window, message: L10n.tr(
                "Migemo の辞書「%@」を読むには、このフォルダーへのアクセスを許可してください。", comment: "Migemo 辞書のフォルダーの許可"))
        }
        switch EditorCore.prepareMigemo() {
        case .ready:
            return true
        case .noLibrary:
            Self.beep()
            sendStatusMessage(L10n.tr("MIGEMO.DLLが使用できません。", comment: "STR_EDITVWISRCH_MIGEGO1"))
        default:
            Self.beep()
            sendStatusMessage(L10n.tr("MIGEMOは使用できません。", comment: "STR_EDITVWISRCH_MIGEGO2"))
        }
        return false
    }

    /// Migemo の辞書のフォルダー（原版 CMigemo::migemo_load_all：空のときは sakura.ini のフォルダーの dict、相対パスは sakura.ini から）
    static var migemoDictionaryFolder: String {
        let setting = EditorCore.commonSetting(section: "Common", key: "szMigemoDict") ?? ""
        let iniFolder = (EditorCore.settingsFilePath as NSString).deletingLastPathComponent
        if setting.isEmpty { return (iniFolder as NSString).appendingPathComponent("dict") }
        if setting.hasPrefix("/") { return setting }
        return (iniFolder as NSString).appendingPathComponent(setting)
    }

    /// インクリメンタルサーチモードから抜ける（原版 ISearchExit）
    func isearchExit() {
        guard isearch.isActive else { return }
        // シーケンスを上書きして現在の検索キーを維持する
        if !searchState.key.isEmpty && (searchState.key as NSString).length < 260 {
            EditorCore.addSearchKey(searchState.key)
        }
        searchState.sequence = EditorCore.searchKeySequence
        let settings = EditorCore.searchSettings
        settings.options = searchState.options
        EditorCore.searchSettings = settings
        isearch.forward = false
        isearch.mode = .none
        if isearch.historyCount == 0 { searchState.key = "" }
        sendStatusMessage("")
    }

    /// 検索文字列に追加して検索（原版 ISearchExec(DWORD)、ISearchExec(LPCWSTR)）。改行で抜ける
    func isearchAdd(_ text: String) {
        for scalar in text.unicodeScalars {
            if scalar == "\r" || scalar == "\n" {
                isearchExit()
                return
            }
            if isearch.first {
                isearch.first = false
                searchState.key = ""
            }
            searchState.key.unicodeScalars.append(scalar)
            isearchExec(next: false)
        }
    }

    /// 検索の実行（原版 ISearchExec(bool)）。next：次の候補、false：今の位置から
    func isearchExec(next: Bool) {
        let key = searchState.key
        guard !key.isEmpty, isearch.isActive else {
            sendStatusMessage(isearchStatusMessage, persistent: true)
            return
        }
        var from = caret
        if next && isearch.wrap {
            from = isearch.forward ? EditorPosition(line: 0, column: 0) : document.isearchWrapBackwardStart
        } else if let selection {
            // 前方検索で現在位置から・後方検索で次を検索：選択範囲の先頭から。それ以外は後ろから
            from = isearch.forward != next ? selection.from : selection.to
        }
        isearch.historyCount += 1
        var message = isearchStatusMessage
        if isearch.historyCount >= 256 {
            isearch.historyCount = 156
            for i in 100...255 {
                isearch.flagHistory[i - 100] = isearch.flagHistory[i]
                isearch.history[i - 100] = isearch.history[i]
            }
        }
        isearch.flagHistory[isearch.historyCount] = next
        let match = document.isearchFind(key, from: from, forward: isearch.forward, options: searchState.options,
                                         migemo: isearch.mode == .migemo)
        if let match {
            setSelection(from: match.to, to: match.from)	// カーソルは見つかった範囲の先頭
            scrollToVisible(caretRect.insetBy(dx: -8, dy: -CGFloat(max(1, viewRowCount / (20 / 3))) * lineHeight))
            isearch.wrap = false
            isearch.history[isearch.historyCount] = match
        } else {
            message += L10n.tr(" (見つかりません)", comment: "STR_EDITVWISRCH_NOMATCH")
            if next { isearch.wrap = true }
            isearch.history[isearch.historyCount] = selection ?? EditorRange(from: caret, to: caret)
        }
        searchState.markOn = true
        needsDisplay = true
        sendStatusMessage(message, persistent: true)
    }

    /// バックスペース（原版 ISearchBack）：1 文字前の状態に戻る
    func isearchBack() {
        guard isearch.historyCount > 0 else { return }
        if isearch.historyCount == 1 {
            searchState.markOn = false
            isearch.first = true
        } else if !isearch.flagHistory[isearch.historyCount] {
            // 検索文字をへらす
            let key = searchState.key as NSString
            if key.length > 0 {
                let last = key.rangeOfComposedCharacterSequence(at: key.length - 1)
                let surrogate = last.length == 2 && CFStringIsSurrogateHighCharacter(key.character(at: last.location))
                searchState.key = key.substring(to: key.length - (surrogate ? 2 : 1))
                if searchState.key.isEmpty { searchState.markOn = false }
            } else {
                Self.beep()
            }
        }
        isearch.historyCount -= 1
        var range = isearch.history[isearch.historyCount]
        if isearch.historyCount == 0 {
            clearSelection()
            range = EditorRange(from: range.from, to: range.from)
        }
        if isearch.historyCount != 0 && !Self.same(range.from, range.to) {
            setSelection(from: range.to, to: range.from)
        } else {
            setCaret(range.from)
        }
        needsDisplay = true
        sendStatusMessage(isearchStatusMessage, persistent: true)
    }

    /// ステータスバーのメッセージ（原版 ISearchSetStatusMsg）
    var isearchStatusMessage: String {
        var message: String
        switch isearch.mode {
        case .normal: message = "I-Search"
        case .regexp: message = "[RegExp] I-Search"
        case .migemo: message = "[Migemo] I-Search"
        case .none: return ""
        }
        message += isearch.forward ? ": " : " Backward: "
        if isearch.historyCount > 0 { message += searchState.key }
        return message
    }

    /// インクリメンタルサーチ中のキー（原版 TranslateCommand_isearch）。処理したら true
    /// code はキー割り当ての機能番号（0 は割り当てなし：文字入力・Mac の編集キー）
    func isearchHandleKey(code: Int) -> Bool {
        guard isearch.isActive else { return false }
        switch code {
        case 0:
            return false	// 文字入力・Return・Backspace 等は insertText / doCommand で
        case _ where Self.isearchCommands[code] != nil:
            return false	// インクリメンタルサーチの機能は普通に実行
        case 30222:		// F_DELETE_BACK
            isearchBack()
            return true
        case 30260, 30261:	// F_INDENT_TAB、F_UNINDENT_TAB：TAB はインデントではなく単なる TAB 文字
            isearchAdd("\t")
            return true
        case 30262, 30263:	// F_INDENT_SPACE、F_UNINDENT_SPACE
            isearchAdd(" ")
            return true
        default:
            isearchExit()	// それ以外の機能はインクリメンタルサーチを抜けてから実行
            return false
        }
    }

    /// インクリメンタルサーチ中の編集キー（doCommand）。処理したら true
    func isearchHandleSelector(_ selector: Selector) -> Bool {
        guard isearch.isActive else { return false }
        switch selector {
        case #selector(insertNewline(_:)), #selector(insertLineBreak(_:)):
            isearchExit()
            return true
        case #selector(deleteBackward(_:)):
            isearchBack()
            return true
        case #selector(insertTab(_:)), #selector(insertBacktab(_:)):
            isearchAdd("\t")
            return true
        default:
            isearchExit()
            return false
        }
    }
}

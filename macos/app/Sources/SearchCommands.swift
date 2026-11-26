// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge

/// 编辑视图的查找状态（第 32 步。原版 CEditView 的 m_strCurSearchKey、m_sCurSearchOption 等）
struct SearchState {
    /// 现在的查找文字（原版 m_strCurSearchKey）
    var key = "" { didSet { markCache.removeAll() } }
    /// 现在的查找条件（原版 m_sCurSearchOption）
    var options: EditorSearchOptions = [] { didSet { markCache.removeAll() } }
    /// 取得查找文字时的历史序号（原版 m_nCurSearchKeySequence。-1 是还没有设置）
    var sequence = -1
    /// 对话框改了查找文字（原版 m_bCurSearchUpdate）
    var updated = false
    /// 显示検索文字列的颜色（原版 m_bCurSrchKeyMark）
    var markOn = false
    /// 検索開始位置（原版 m_ptSrchStartPos_PHY。「検索開始位置へ戻る」用）
    var startPosition: EditorPosition?
    /// 对话框打开后还没有登记検索開始位置（原版 m_bSearch）
    var registerStart = false
    /// 上次长度 0 的匹配的位置（原版是长度 0 的选择范围）
    var zeroMatch: EditorPosition?
    /// 每个逻辑行的検索文字列的位置（绘制用。内容、查找文字变化时清空）
    var markCache: [Int: [EditorSearchMark]] = [:]
}

/// 查找、置换、指定行へジャンプ的命令（第 32 步。原版 CViewCommander_Search.cpp、CViewCommander_Bookmark.cpp）
extension EditorTextView {
    // MARK: - 消息

    /// 测试用：代替显示消息框和蜂鸣。参数是消息（nil 是蜂鸣）
    static var messageHandler: ((String?) -> Void)?

    /// 显示消息（原版 InfoMessage / OkMessage。原版的消息框是模态的，这里也用模态）
    static func showMessage(_ text: String, informative: String = "", style: NSAlert.Style = .informational) {
        if let handler = messageHandler {
            handler(informative.isEmpty ? text : text + "\n" + informative)
            return
        }
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = text
        alert.informativeText = informative
        alert.runModal()
    }

    /// 蜂鸣（原版 ErrorBeep / DefaultBeep）
    static func beep() {
        if let handler = messageHandler {
            handler(nil)
        } else {
            NSSound.beep()
        }
    }

    /// 正则表达式的错误（原版 CBregexp：STR_REGEX_COMPILE_ERR_PREAMBLE）
    static func showRegexpError(_ error: String) {
        showMessage(NSLocalizedString("正規表現の構文に誤りがあります。", comment: "STR_REGEX_COMPILE_ERR_PREAMBLE"),
                    informative: NSLocalizedString("詳細：", comment: "STR_REGEX_COMPILE_ERR_PREAMBLE") + error,
                    style: .warning)
    }

    /// 正则表达式的语法检查（原版 CheckRegexpSyntax）。没有错误时 true
    static func checkRegexpSyntax(_ pattern: String, options: EditorSearchOptions) -> Bool {
        guard options.contains(.regularExpression) else { return true }
        if let error = EditorCore.regexpSyntaxError(pattern, matchCase: options.contains(.matchCase)) {
            showRegexpError(error)
            return false
        }
        return true
    }

    /// 找不到时（原版 AlertNotFound）：设置了「見つからないときにメッセージを表示」时显示消息，否则蜂鸣
    static func alertNotFound(_ message: String, replaceAll: Bool = false) {
        if EditorCore.searchSettings.notifyNotFound && !replaceAll {
            showMessage(message)
        } else {
            beep()
        }
    }

    /// 找不到时的消息里的查找文字（原版：_MAX_PATH 字为止，长的加「...」）
    static func keyName(_ key: String) -> String {
        let utf16 = Array(key.utf16)
        let maxPath = 260
        guard utf16.count > maxPath else { return key }
        return String(utf16CodeUnits: utf16, count: maxPath) + "..."
    }

    // MARK: - 查找的状态

    /// 查找命令的输入：光标和选择（长度 0 的匹配也算选择）
    var searchView: EditorSearchView {
        if let selection {
            return EditorSearchView(caret: caret, hasSelection: true, selection: selection)
        }
        let empty = EditorRange(from: caret, to: caret)
        if let zero = searchState.zeroMatch, Self.same(zero, caret), !isBoxSelection {
            return EditorSearchView(caret: caret, hasSelection: true, selection: empty)
        }
        return EditorSearchView(caret: caret, hasSelection: false, selection: empty)
    }

    /// 查找命令的结果放到画面上：找到的范围选中，光标在开头（原版 SetSelectArea + MoveCursor）
    func applySearchView(_ view: EditorSearchView) {
        if view.hasSelection && !Self.same(view.selection.from, view.selection.to) {
            let anchor = Self.same(view.caret, view.selection.from) ? view.selection.to : view.selection.from
            setSelection(from: anchor, to: view.caret)
            searchState.zeroMatch = nil
        } else {
            setCaret(view.caret)
            searchState.zeroMatch = view.hasSelection ? view.caret : nil
        }
    }

    /// 对话框设置查找文字（原版 CDlgFind::GetData / CDlgReplace::GetData 的后半）
    func setSearchKey(_ key: String, options: EditorSearchOptions) {
        if searchState.key != key || searchState.options != options {
            searchState.key = key
            searchState.options = options
            searchState.updated = true
        }
        searchState.sequence = EditorCore.searchKeySequence
    }

    /// 决定现在的查找文字（原版 CEditView::ChangeCurRegexp）。
    /// 视图的查找文字是空的、或者别的视图查找过（「次・前検索で他のビューの検索条件を引き継ぐ」）时，用历史的第一个。
    /// 正则表达式有错误时显示消息，返回 false
    @discardableResult
    func changeCurrentRegexp() -> Bool {
        let settings = EditorCore.searchSettings
        var changed = false
        if searchState.key.isEmpty || (settings.inheritKeyOtherView && searchState.sequence < EditorCore.searchKeySequence) {
            searchState.key = EditorCore.searchKeyHistory.first ?? ""
            searchState.options = settings.options
            searchState.sequence = EditorCore.searchKeySequence
            changed = true
        } else if searchState.updated {
            changed = true
        }
        searchState.updated = false
        if changed {
            if !searchState.key.isEmpty && !Self.checkRegexpSyntax(searchState.key, options: searchState.options) {
                searchState.markOn = false
                needsDisplay = true
                return false
            }
            searchState.markOn = true
            needsDisplay = true
            return true
        }
        if !searchState.markOn {
            searchState.markOn = true
            needsDisplay = true
        }
        return true
    }

    /// 选择范围或光标位置的单词（原版 GetCurrentTextForSearch。到第一个换行为止）
    func currentTextForSearch() -> String {
        var text = ""
        if let selection {
            text = document.text(in: selection)
        } else if let box = boxRange {
            text = document.boxText(box)
        } else {
            var range = EditorRange()
            if document.wordRange(at: caret, range: &range) {
                text = document.text(in: range)
            }
        }
        return Self.firstLine(text)
    }

    /// 对话框的初始查找文字（原版 GetCurrentTextForSearchDlg）
    func currentTextForSearchDialog() -> String {
        if hasSelection { return currentTextForSearch() }
        if EditorCore.searchSettings.caretTextForSearch {
            let text = currentTextForSearch()
            if !text.isEmpty { return text }
        }
        // 历史里有别的视图登记的新的查找文字时用它，否则用这个视图的查找文字
        if let first = EditorCore.searchKeyHistory.first, searchState.sequence < EditorCore.searchKeySequence {
            return first
        }
        return searchState.key
    }

    // MARK: - 命令

    /// 検索 > 検索…（F_SEARCH_DIALOG）
    @objc func showFindPanel(_ sender: Any?) {
        guard !hasMarkedText() else { return }
        let text = currentTextForSearchDialog()
        if let panel = findPanel, panel.window?.isVisible == true {
            panel.activate(text: text)
            return
        }
        let panel = findPanel ?? FindPanelController(view: self)
        findPanel = panel
        panel.open(text: text)
    }

    /// 検索 > 置換…（F_REPLACE_DIALOG）
    @objc func showReplacePanel(_ sender: Any?) {
        guard !hasMarkedText() else { return }
        let text = currentTextForSearchDialog()
        if let panel = replacePanel, panel.window?.isVisible == true {
            panel.activate(text: text)
            return
        }
        let panel = replacePanel ?? ReplacePanelController(view: self)
        replacePanel = panel
        // 選択範囲が複数行のときは「選択範囲」（原版 Command_REPLACE_DIALOG）
        let selected = selection.map { $0.from.line != $0.to.line } ?? false
        panel.open(text: text, selected: selected)
    }

    /// 検索 > 次を検索（F_SEARCH_NEXT）
    @objc func searchNext(_ sender: Any?) {
        searchNextCommand()
    }

    /// 検索 > 前を検索（F_SEARCH_PREV）
    @objc func searchPrevious(_ sender: Any?) {
        searchPrevCommand()
    }

    /// 次を検索（原版 Command_SEARCH_NEXT）。notFoundMessage は見つからないときのメッセージ（nil は標準）
    func searchNextCommand(notFoundMessage: String? = nil) {
        guard !hasMarkedText() else { return }
        guard changeCurrentRegexp(), !searchState.key.isEmpty else { return }
        let settings = EditorCore.searchSettings
        let oldView = searchView
        let result = document.searchNext(searchState.key, options: searchState.options, view: oldView, searchAll: settings.searchAll)
        if result.status == .found || result.status == .wrapped { addCurrentLineToHistory() }	// 移動履歴（第 34 步）
        clearBoxSelectionForSearch()
        applySearchView(result.view)
        switch result.status {
        case .found:
            break
        case .wrapped:
            sendSearchStatus(next: true, wrapped: true)	// 第 44 步：ステータスメッセージ
        case .invalidPattern:
            Self.showRegexpError(result.error)
        default:
            sendSearchStatus(next: true, wrapped: nil)
            Self.alertNotFound(notFoundMessage ?? String(format: NSLocalizedString(
                "前方(↓) に文字列 '%@' が１つも見つかりません。", comment: "STR_ERR_SRNEXT3"), Self.keyName(searchState.key)))
        }
    }

    /// 前を検索（原版 Command_SEARCH_PREV）
    func searchPrevCommand() {
        guard !hasMarkedText() else { return }
        guard changeCurrentRegexp(), !searchState.key.isEmpty else { return }
        let settings = EditorCore.searchSettings
        let result = document.searchPrev(searchState.key, options: searchState.options, view: searchView, searchAll: settings.searchAll)
        if result.status == .found || result.status == .wrapped { addCurrentLineToHistory() }	// 移動履歴（第 34 步）
        clearBoxSelectionForSearch()
        applySearchView(result.view)
        switch result.status {
        case .found:
            break
        case .wrapped:
            sendSearchStatus(next: false, wrapped: true)
        case .invalidPattern:
            Self.showRegexpError(result.error)
        default:
            sendSearchStatus(next: false, wrapped: nil)
            Self.alertNotFound(String(format: NSLocalizedString(
                "後方(↑) に文字列 '%@' が１つも見つかりません。", comment: "STR_ERR_SRPREV3"), Self.keyName(searchState.key)))
        }
    }

    /// 矩形選択中に検索したら矩形選択は解除する（Mac 版：矩形選択からの検索は光标位置から）
    private func clearBoxSelectionForSearch() {
        if isBoxSelection { clearSelection() }
    }

    /// 置換（原版 Command_REPLACE）。置換後の文字列 replacement（paste 时是剪贴板的文字）。
    /// 剪贴板是空的时返回 false（对话框关掉「クリップボードから貼り付ける」）
    @discardableResult
    func replaceCommand(_ replacement: String, options: EditorReplaceOptions) -> Bool {
        guard !hasMarkedText() else { return true }
        guard changeCurrentRegexp(), !searchState.key.isEmpty else { return true }
        var options = options
        options.search = searchState.options
        if options.target == .deleteLine { options.paste = false }
        var text = replacement
        if options.paste {
            guard let clip = clipboardText else {
                Self.showMessage(NSLocalizedString("クリップボードに有効なデータがありません！", comment: "STR_ERR_CEDITVIEW_CMD10"))
                return false
            }
            text = clip
        }
        if isBoxSelection { clearSelection() }
        let result = document.replaceNext(searchState.key, with: text, options: options, view: searchView)
        if result.count > 0 { textChanged() }
        applySearchView(result.view)
        switch result.status {
        case .invalidPattern:
            Self.showRegexpError(result.error)
        case .notFound:
            Self.alertNotFound(String(format: NSLocalizedString(
                "前方(↓) に文字列 '%@' が１つも見つかりません。", comment: "STR_ERR_SRNEXT3"), Self.keyName(searchState.key)))
        default:
            if result.next == .notFound {
                Self.alertNotFound(NSLocalizedString("最後まで置換しました。", comment: "STR_ERR_CEDITVIEW_CMD11"))
            }
        }
        return true
    }

    /// すべて置換（原版 Command_REPLACE_ALL）。置換した数を返す。剪贴板是空的时 nil
    func replaceAllCommand(_ replacement: String, options: EditorReplaceOptions) -> Int? {
        guard !hasMarkedText() else { return 0 }
        guard changeCurrentRegexp(), !searchState.key.isEmpty else { return 0 }
        var options = options
        options.search = searchState.options
        if options.target == .deleteLine { options.paste = false }
        var text = replacement
        if options.paste {
            guard let clip = clipboardText else {
                Self.showMessage(NSLocalizedString("クリップボードに有効なデータがありません！", comment: "STR_ERR_CEDITVIEW_CMD10"))
                return nil
            }
            text = clip
        }
        // 選択範囲は普通の選択のときだけ（Mac 版：矩形選択の範囲内置換はまだない）
        if options.selectedArea && selection == nil { options.selectedArea = false }
        if isBoxSelection { clearSelection() }
        let result = document.replaceAll(searchState.key, with: text, options: options, view: searchView)
        if result.status == .invalidPattern {
            Self.showRegexpError(result.error)
            return 0
        }
        if result.count > 0 { textChanged() }
        applySearchView(result.view)
        return result.count
    }

    /// 検索 > 検索マークの切替え（F_SEARCH_CLEARMARK）。
    /// 选择中：选择的文字作为查找文字显示颜色（不用正则表达式、单词单位）。没有选择：不显示查找文字的颜色
    @objc func toggleSearchMark(_ sender: Any?) {
        guard !hasMarkedText() else { return }
        if hasSelection {
            let text = currentTextForSearch()
            var options = searchState.options
            if searchState.sequence < EditorCore.searchKeySequence {
                options = EditorCore.searchSettings.options
            }
            options.remove(.regularExpression)
            options.remove(.wholeWord)
            searchState.key = text
            searchState.options = options
            if (text as NSString).length < 260 {
                EditorCore.addSearchKey(text)
                let settings = EditorCore.searchSettings
                settings.options = options
                EditorCore.searchSettings = settings
            }
            searchState.sequence = EditorCore.searchKeySequence
            searchState.updated = true
            changeCurrentRegexp()
        } else {
            searchState.markOn = false
        }
        needsDisplay = true
    }

    /// 検索 > 検索開始位置へ戻る（F_JUMP_SRCHSTARTPOS）
    @objc func jumpToSearchStart(_ sender: Any?) {
        guard !hasMarkedText() else { return }
        guard let start = searchState.startPosition else {
            Self.beep()
            return
        }
        setCaret(start)
    }

    /// 検索 > 指定行へジャンプ…（F_JUMP_DIALOG）
    @objc func showJumpDialog(_ sender: Any?) {
        guard !hasMarkedText(), let window else { return }
        JumpDialogController.shared.begin(for: self, in: window)
    }

    /// 指定行へジャンプ（原版 Command_JUMP）
    func jumpCommand(_ options: EditorJumpOptions) {
        var position = EditorPosition()
        guard document.jumpPosition(options, position: &position) else {
            Self.beep()
            return
        }
        addCurrentLineToHistory()	// 移動履歴（第 34 步，原版 Command_JUMP）
        setCaret(position)
    }

    /// 検索メニューの有効・無効（原版 IsFuncEnable）。検索メニュー以外は nil
    func validateSearchMenuItem(_ menuItem: NSMenuItem) -> Bool? {
        switch menuItem.action {
        case #selector(showFindPanel(_:)), #selector(searchNext(_:)), #selector(searchPrevious(_:)),
             #selector(showReplacePanel(_:)), #selector(toggleSearchMark(_:)), #selector(jumpToSearchStart(_:)),
             #selector(showJumpDialog(_:)):
            return !hasMarkedText()
        default:
            return nil
        }
    }
}

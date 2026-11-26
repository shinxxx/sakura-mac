// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge

/// 入力補完の窓口（第 44 步，原版 CHokanMgr・IDD_HOKAN）：候補の一覧。編集画面からキーを受けて動く（フォーカスは取らない）
final class HokanWindowController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    let panel: NSPanel
    let table: NSTableView
    private(set) var words: [String] = []
    weak var view: EditorTextView?
    /// 窓口の大きさ（原版 m_nWidth・m_nHeight：利用者が変えたら次もその大きさ。最初は IDD_HOKAN の 125×100）
    static var size = NSSize(width: PropPage.pointsX(125), height: PropPage.points(100))

    init(view: EditorTextView) {
        self.view = view
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: Self.size),
                        styleMask: [.nonactivatingPanel, .resizable, .utilityWindow, .titled, .fullSizeContentView],
                        backing: .buffered, defer: true)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 60, height: 40)
        table = NSTableView()
        super.init()
        table.headerView = nil
        table.style = .plain	// 原版のリストボックス：左右の余白・角の丸い選択なし
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("word")))
        table.dataSource = self
        table.delegate = self
        table.refusesFirstResponder = true	// 編集画面のフォーカスはそのまま（原版 WM_MOUSEACTIVATE → MA_NOACTIVATE）
        table.rowHeight = 16
        table.allowsEmptySelection = false
        table.target = self
        table.doubleAction = #selector(doubleClicked(_:))
        table.setAccessibilityIdentifier("hokanList")
        let scroll = NSScrollView()
        // 題名の帯（透明）の分を空けない：一覧は窓の上端から（原版のリストボックスは窓いっぱい）
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsetsZero
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        panel.contentView = scroll
        NotificationCenter.default.addObserver(self, selector: #selector(panelDidResize(_:)), name: NSWindow.didResizeNotification, object: panel)
    }

    var isVisible: Bool { panel.isVisible }

    /// 候補を出す（原版 Search の後半）。point は単語の先頭の左下（画面座標）、lineHeight は行の高さ
    func show(words: [String], below point: NSPoint, lineHeight: CGFloat, parent: NSWindow?) {
        self.words = words
        table.reloadData()
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        table.scrollRowToVisible(0)
        // 下に入るなら下、入らなければ上、どちらも入らなければ広いほう（原版と同じ考え方）
        let screen = (parent?.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        var frame = NSRect(origin: .zero, size: Self.size)
        frame.origin.x = point.x
        frame.origin.y = point.y - 4 - frame.height
        if frame.minY < screen.minY {
            let above = point.y + lineHeight + 4
            if above + frame.height < screen.maxY {
                frame.origin.y = above
            } else if point.y - screen.minY > screen.maxY - above {
                frame.size.height = point.y - 4 - screen.minY
                frame.origin.y = screen.minY
            } else {
                frame.origin.y = above
                frame.size.height = screen.maxY - above
            }
        }
        if frame.maxX > screen.maxX {
            frame.origin.x = max(screen.minX, screen.maxX - frame.width)
        }
        panel.setFrame(frame, display: true)
        if panel.parent == nil, let parent { parent.addChildWindow(panel, ordered: .above) }
        panel.orderFront(nil)
    }

    func hide() {
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    var selectedWord: String? {
        words.indices.contains(table.selectedRow) ? words[table.selectedRow] : nil
    }

    /// 一覧の移動（原版 KeyProc：リストボックスのデフォルトの動作）
    func move(_ key: Int) {
        guard !words.isEmpty else { return }
        let page = max(1, Int(table.enclosingScrollView?.contentSize.height ?? 0) / Int(table.rowHeight + table.intercellSpacing.height) - 1)
        var row = max(0, table.selectedRow)
        switch key {
        case NSUpArrowFunctionKey: row -= 1
        case NSDownArrowFunctionKey: row += 1
        case NSHomeFunctionKey: row = 0
        case NSEndFunctionKey: row = words.count - 1
        case NSPageUpFunctionKey: row -= page
        case NSPageDownFunctionKey: row += page
        default: return
        }
        row = min(max(0, row), words.count - 1)
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        table.scrollRowToVisible(row)
    }

    @objc private func doubleClicked(_ sender: Any?) {
        guard table.clickedRow >= 0 else { return }
        view?.hokanDecide(key: nil)
    }

    @objc private func panelDidResize(_ notification: Notification) {
        if panel.isVisible { Self.size = panel.frame.size }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { words.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let label = NSTextField(labelWithString: words.indices.contains(row) ? words[row] : "")
        label.font = PropPage.font
        label.lineBreakMode = .byClipping
        return label
    }

    /// 選択行はいつも強調色（フォーカスを取らない窓でも原版のリストボックスと同じく青）
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        HokanRowView()
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        view?.hokanShowTip()	// 原版 OnLbnSelChange → ShowTip
    }
}

/// 入力補完の一覧の行：選択はいつも強調色、文字は白
final class HokanRowView: NSTableRowView {
    override var isEmphasized: Bool {
        get { true }
        set {}
    }
}

/// 入力補完（F_HOKAN，原版 view/CEditView_CmdHokan.cpp、Command_HOKAN）
extension EditorTextView {
    /// 支援 > 入力補完（F_HOKAN，原版 Command_HOKAN）：カーソル直前の単語で候補を出す。候補が 1 つならそれに決める
    @objc func hokanCommand(_ sender: Any?) {
        guard !hasMarkedText() else { return }
        let word = document.leftWord(at: caret)
        if word.isEmpty {
            Self.beep()
            sendStatusMessage(NSLocalizedString("補完対象がありません", comment: "STR_SUPPORT_NOT_COMPLITE"))
            return
        }
        showHokan(word, autoDecided: true)
    }

    /// 補完ウィンドウを表示する（原版 ShowHokanMgr）
    func showHokan(_ word: String, autoDecided: Bool) {
        let candidates = withSupportFileAccess { document.hokanCandidates(key: word, caret: caret) }
        if candidates.isEmpty {
            if hokanActive {
                hokanHide()
                Self.beep()
            }
            return
        }
        if autoDecided && candidates.count == 1 {
            if hokanActive { hokanHide() }
            hokanInsert(candidates[0])
            return
        }
        // 一覧は並べ替える（原版 LBS_SORT）
        let sorted = candidates.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        let controller = hokanWindow ?? HokanWindowController(view: self)
        hokanWindow = controller
        // 単語の先頭の下（原版：カーソル位置から単語の幅を引く）
        let rect = caretRect
        let width = (word as NSString).size(withAttributes: [.font: font]).width
        let local = NSPoint(x: max(textOriginX, rect.minX - width) - charWidth, y: rect.maxY)
        let screen = window?.convertPoint(toScreen: convert(local, to: nil)) ?? .zero
        controller.show(words: sorted, below: screen, lineHeight: lineHeight, parent: window)
        hokanActive = true
    }

    /// 決める（原版 DoHokan）。key は Return・Tab・→ のどれか（共通設定『支援』の補完候補決定キー）。nil はダブルクリック
    @discardableResult
    func hokanDecide(key: Int?) -> Bool {
        if let key {
            let settings = [NSCarriageReturnCharacter: "bHokanKey_RETURN", NSTabCharacter: "bHokanKey_TAB", NSRightArrowFunctionKey: "bHokanKey_RIGHT"]
            guard let setting = settings[key], GrepDialogController.commonBool(setting) else { return false }
        }
        guard let word = hokanWindow?.selectedWord else { return false }
        hokanInsert(word)
        hokanHide()
        return true
    }

    /// 単語の左端まで削除して候補を入れる（原版 F_WordDeleteToStart + F_INSTEXT_W）
    private func hokanInsert(_ word: String) {
        var from = EditorPosition()
        if !document.wordMoveTarget(from: caret, left: true, position: &from) {
            from = caret.column > 0 ? EditorPosition(line: caret.line, column: caret.column - 1) : caret
        }
        document.beginEdit()
        var end = EditorPosition()
        if document.replace(EditorRange(from: from, to: caret), with: word, newEnd: &end) == .success {
            setCaret(end)
        }
        document.endEdit()
        textChanged()
    }

    func hokanHide() {
        hokanWindow?.hide()
        hokanActive = false
        hideKeywordTip()
    }

    /// 入力・Backspace のあと（原版 PostprocessCommand_hokan）：単語が変わったので候補を出し直す
    func hokanPostprocess() {
        guard hokanActive else { return }
        let word = document.leftWord(at: caret)
        if word.isEmpty {
            hokanHide()
        } else {
            showHokan(word, autoDecided: false)
        }
    }

    /// 補完ウィンドウが出ているときのキー（原版 CHokanMgr::KeyProc）。処理したら true
    func hokanHandleKey(_ event: NSEvent) -> Bool {
        guard hokanActive, let controller = hokanWindow, controller.isVisible,
              event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
              let key = event.charactersIgnoringModifiers?.utf16.first.map(Int.init) else { return false }
        switch key {
        case NSUpArrowFunctionKey, NSDownArrowFunctionKey, NSHomeFunctionKey, NSEndFunctionKey, NSPageUpFunctionKey, NSPageDownFunctionKey:
            controller.move(key)
            return true
        case NSCarriageReturnCharacter, NSEnterCharacter, NSTabCharacter, NSRightArrowFunctionKey:
            return hokanDecide(key: key == NSEnterCharacter ? NSCarriageReturnCharacter : key)
        default:
            return false
        }
    }

    /// 機能の前（原版 PreprocessCommand_hokan）：入力補完・文字入力・Backspace 以外の機能は補完ウィンドウを消す
    func hokanPreprocess(code: Int) {
        guard hokanActive, code != 0, code != 31430, code != 30222 else { return }
        hokanHide()
    }

    /// 補完ファイル・キーワード辞書を沙盒で読む（設定で選んだときの書签）
    func withSupportFileAccess<T>(_ body: () -> T) -> T {
        var urls: [URL] = []
        for path in document.supportFilePaths {
            if let url = BookmarkStore.settingFiles.resolve(path: path), url.startAccessingSecurityScopedResource() { urls.append(url) }
        }
        defer { for url in urls { url.stopAccessingSecurityScopedResource() } }
        return body()
    }
}

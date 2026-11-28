// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge

/// タグジャンプ一覧（第 44 步，原版 CDlgTagJumpList・IDD_TAGJUMPLIST）。
/// ダイレクトタグジャンプで候補が複数のとき、キーワードを指定してタグジャンプ のとき。検索は核心库（TagJumpSearch）
final class TagJumpListDialogController: NSObject, NSWindowDelegate, NSComboBoxDelegate {
    static var runModal: ((TagJumpListDialogController) -> Bool)?
    /// キーワードを入力してから一覧を更新するまで（原版 TAGJUMP_TIMER_DELAY 700ms、最初は TAGJUMP_TIMER_DELAY_SHORT 50ms）
    static var timerDelay: TimeInterval = 0.7
    static var timerDelayShort: TimeInterval = 0.05

    let page: PropPage
    let window: NSPanel
    let search: TagJumpSearch
    let isDirect: Bool
    private var keyword: String
    private var accepted = false
    private var timer: Timer?
    /// OK 後：選んだ候補のファイルと行
    private(set) var selectedPath: String?
    private(set) var selectedLine = 0

    init?(search: TagJumpSearch, direct: Bool, keyword: String?) {
        guard let definition = PropDialogs.load("EditSupportDialogs")?.dialog("IDD_TAGJUMPLIST") else { return nil }
        self.search = search
        isDirect = direct
        self.keyword = keyword ?? ""
        page = PropPage(definition: definition)
        window = NSPanel(contentRect: NSRect(origin: .zero, size: page.view.frame.size), styleMask: [.titled], backing: .buffered, defer: true)
        window.title = definition.name
        window.contentView = page.view
        window.isReleasedWhenClosed = false
        super.init()
        window.delegate = self
        (page.control("IDOK") as? NSButton)?.keyEquivalent = "\r"
        (page.control("IDCANCEL") as? NSButton)?.keyEquivalent = "\u{1b}"
        page.onButton = { [weak self] id in self?.buttonClicked(id) }
        page.onChange = { [weak self] id in self?.controlChanged(id) }
        if let list = page.list("IDC_LIST_TAGJUMP") {
            // 列（原版 OnInitDialog：幅は一覧の幅の 20・7・8・9・35・21%）
            let width = list.table.enclosingScrollView?.contentSize.width ?? 600
            list.setColumns([L10n.tr("キーワード", comment: "STR_DLGTAGJMP_LIST1"), L10n.tr("階層", comment: "STR_DLGTAGJMP_LIST2"),
                             L10n.tr("行番号", comment: "STR_DLGTAGJMP_LIST3"), L10n.tr("種類", comment: "STR_DLGTAGJMP_LIST4"),
                             L10n.tr("ファイル名", comment: "STR_DLGTAGJMP_LIST5"), L10n.tr("備考", comment: "STR_DLGTAGJMP_LIST6")],
                            widths: [20, 7, 8, 9, 35, 21].map { width * CGFloat($0) / 100 - 3 })
            list.columnAlignments = [.left, .center, .right, .left, .left, .left]	// 原版 LVCFMT_LEFT・CENTER・RIGHT
            list.onDoubleClick = { [weak self] _, _ in self?.buttonClicked("IDOK") }
        }
        (page.control("IDC_KEYWORD") as? NSComboBox)?.delegate = self
        setData()
    }

    // MARK: - 原版 SetData・UpdateData・GetData

    private var icase: Bool { page.isChecked("IDC_CHECK_ICASE") }
    private var partial: Bool { page.isChecked("IDC_CHECK_ANYWHERE") }

    private func setData() {
        // ダイレクトタグジャンプの時は、キーワードを非表示（原版 OnInitDialog）
        for id in ["IDC_STATIC_KEYWORD", "IDC_KEYWORD", "IDC_CHECK_ICASE", "IDC_CHECK_ANYWHERE"] {
            page.control(id)?.isHidden = isDirect
        }
        if isDirect {
            page.setChecked("IDC_CHECK_ICASE", false)
            page.setChecked("IDC_CHECK_ANYWHERE", false)
        } else {
            page.setChecked("IDC_CHECK_ICASE", Self.otherBool("m_bTagJumpICase"))
            page.setChecked("IDC_CHECK_ANYWHERE", Self.otherBool("m_bTagJumpAnyWhere"))
            let history = EditorCore.tagJumpKeywordHistory
            page.setItems("IDC_KEYWORD", history, selected: -1)
            if keyword.isEmpty, let first = history.first { keyword = first }
            page.setText("IDC_KEYWORD", keyword)
        }
        page.setText("IDC_STATIC_BASEDIR", search.baseDirectory)
        (page.control("IDC_STATIC_BASEDIR") as? NSTextField)?.lineBreakMode = .byTruncatingMiddle	// 長いパスは途中を省略
        updateData(initial: true)
        if !isDirect { startTimer(Self.timerDelayShort) }	// 最初は規定時間待たない
    }

    static func otherBool(_ key: String) -> Bool { (EditorCore.commonSetting(section: "Other", key: key) ?? "0") != "0" }

    /// 一覧を作り直す（原版 UpdateData）
    func updateData(initial: Bool) {
        let items = search.items
        var rows = items.map { item -> [String] in
            [item.keyword, item.hasBaseDir ? "(\(item.depth))" : "\(item.depth)", "\(item.line)", item.kind, item.file, item.note]
        }
        if !initial && items.isEmpty {
            rows.append([L10n.tr("(通知)", comment: "STR_DLGTAGJMP1"), "", "", "",
                         L10n.tr("(候補は見つかりませんでした)", comment: "STR_DLGTAGJMP2"), ""])
        }
        page.list("IDC_LIST_TAGJUMP")?.setRows(rows)
        // ダイレクトタグジャンプで、ページングの必要がないときは非表示
        let hidePaging = isDirect && !search.hasPrevPage && !search.hasNextPage
        page.control("IDC_BUTTON_NEXTTAG")?.isHidden = hidePaging
        page.control("IDC_BUTTON_PREVTAG")?.isHidden = hidePaging
        page.setEnabled("IDC_BUTTON_NEXTTAG", search.hasNextPage)
        page.setEnabled("IDC_BUTTON_PREVTAG", search.hasPrevPage)
        let best = search.bestIndex
        if best >= 0 { page.list("IDC_LIST_TAGJUMP")?.select(best) }
    }

    private func getData() -> Bool {
        let index = page.list("IDC_LIST_TAGJUMP")?.selectedRow ?? -1
        if !isDirect {
            _ = EditorCore.setCommonSetting(icase ? "1" : "0", section: "Other", key: "m_bTagJumpICase")
            _ = EditorCore.setCommonSetting(partial ? "1" : "0", section: "Other", key: "m_bTagJumpAnyWhere")
            guard index >= 0 && index < search.items.count else { return false }
            keyword = page.text("IDC_KEYWORD")
            EditorCore.addTagJumpKeyword(keyword)
        }
        guard index >= 0 && index < search.items.count else { return false }
        var line = 0
        guard let path = search.fullPath(at: index, line: &line) else { return false }
        selectedPath = path
        selectedLine = line
        return true
    }

    // MARK: - 操作

    private func buttonClicked(_ id: String) {
        switch id {
        case "IDOK":
            stopTimer()
            accepted = getData()
            close()
        case "IDCANCEL":
            stopTimer()
            accepted = false
            close()
        case "IDC_BUTTON_NEXTTAG":
            stopTimer()
            search.nextPage(currentKeyword, ignoreCase: icase, partialMatch: partial)
            updateData(initial: false)
        case "IDC_BUTTON_PREVTAG":
            stopTimer()
            search.prevPage(currentKeyword, ignoreCase: icase, partialMatch: partial)
            updateData(initial: false)
        default:
            break
        }
    }

    private var currentKeyword: String { isDirect ? keyword : page.text("IDC_KEYWORD") }

    private func controlChanged(_ id: String) {
        switch id {
        case "IDC_CHECK_ICASE", "IDC_CHECK_ANYWHERE":
            startTimer(Self.timerDelayShort)
        case "IDC_KEYWORD":
            startTimer(Self.timerDelay)
        default:
            break
        }
    }

    func comboBoxSelectionDidChange(_ notification: Notification) {
        startTimer(Self.timerDelay)	// 原版 OnCbnSelChange
    }

    /// 一覧の更新（原版 OnTimer → FindNext(true)）
    func findNow() {
        stopTimer()
        search.find(currentKeyword, ignoreCase: icase, partialMatch: partial, newFind: true)
        updateData(initial: false)
    }

    private func startTimer(_ delay: TimeInterval) {
        stopTimer()
        let t = Timer(timeInterval: delay, repeats: false) { [weak self] _ in self?.findNow() }
        RunLoop.main.add(t, forMode: .common)
        RunLoop.main.add(t, forMode: .modalPanel)
        timer = t
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    func run(parent: NSWindow?) -> Bool {
        if let hook = Self.runModal { return hook(self) }
        if let parent {
            let frame = parent.frame
            window.setFrameOrigin(NSPoint(x: frame.midX - window.frame.width / 2, y: frame.midY - window.frame.height / 2))
        } else {
            window.center()
        }
        window.makeFirstResponder(isDirect ? page.list("IDC_LIST_TAGJUMP")?.table : page.control("IDC_KEYWORD"))
        NSApp.runModal(for: window)
        return accepted
    }

    func press(_ id: String) {
        if let button = page.control(id) as? NSButton, button.target != nil {
            button.performClick(nil)
        } else {
            buttonClicked(id)
        }
    }

    var isAccepted: Bool { accepted }

    private func close() {
        if NSApp.modalWindow === window { NSApp.stopModal() }
        window.orderOut(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        stopTimer()
        accepted = false
        close()
        return false
    }
}

/// tags ファイルのタグジャンプ（第 44 步，原版 Command_TagJumpByTagsFile・Command_TagJumpByTagsFileKeyword）
extension EditorTextView {
    /// 検索 > ダイレクトタグジャンプ（F_DIRECT_TAGJUMP，原版 Command_TagJumpByTagsFileMsg(true)）
    @objc func directTagJump(_ sender: Any?) {
        guard !hasMarkedText() else { return }
        if !tagJumpByTagsFile(close: false) {
            sendStatusMessage(L10n.tr("タグジャンプできません", comment: "STR_ERR_TAGJMP1"))
            NSSound.beep()
        }
    }

    /// 検索 > キーワードを指定してタグジャンプ（F_TAGJUMP_KEYWORD，原版 Command_TagJumpByTagsFileKeyword(nullptr)）
    @objc func tagJumpKeyword(_ sender: Any?) {
        guard !hasMarkedText(), let base = tagJumpBaseFile() else { return }
        let search = TagJumpSearch(baseFilePath: base, direct: false)
        guard let dialog = TagJumpListDialogController(search: search, direct: false, keyword: nil),
              dialog.run(parent: window), let path = dialog.selectedPath else { return }
        tagJumpTo(path: path, line: dialog.selectedLine, close: false)
    }

    /// ダイレクトタグジャンプ（原版 Command_TagJumpByTagsFile）：カーソル位置の単語（選択範囲）を tags で探す。
    /// 候補が 1 つならジャンプ、複数なら一覧。ジャンプしたかキャンセルしたら true
    @discardableResult
    func tagJumpByTagsFile(close: Bool) -> Bool {
        let keyword = currentTextForSearch()
        guard !keyword.isEmpty, let base = tagJumpBaseFile() else { return false }
        let search = TagJumpSearch(baseFilePath: base, direct: true)
        let matches = search.findDirect(keyword)
        if matches > 1 {
            guard let dialog = TagJumpListDialogController(search: search, direct: true, keyword: keyword) else { return false }
            if !dialog.run(parent: window) { return true }	// キャンセル
            guard let path = dialog.selectedPath else { return false }
            tagJumpTo(path: path, line: dialog.selectedLine, close: close)
            return true
        }
        guard matches > 0 else { return false }
        var line = 0
        guard let path = search.fullPath(at: 0, line: &line) else { return false }
        tagJumpTo(path: path, line: line, close: close)
        return true
    }

    /// 基準のファイル（原版 Sub_PreProcTagJumpByTagsFile）。無題はホームフォルダー（原版はカレントフォルダー）の dmy.拡張子。
    /// 沙盒：tags を探すフォルダーの許可がなければ求める（Grep と同じ FolderAccess。上のフォルダーを選ぶとその下の tags も読める）
    func tagJumpBaseFile() -> String? {
        var base = document.path
        if base.isEmpty {
            if sakuraDocument?.isGrepMode == true { return nil }
            let ext = EditorCore.typeSettings.first { $0.index == document.typeIndex }?.extensions
                .split(whereSeparator: { ",; ".contains($0) }).first.map(String.init) ?? ""
            base = (GrepDialogController.homeFolder as NSString).appendingPathComponent(ext.isEmpty ? "dmy" : "dmy.\(ext)")
        }
        let folder = (base as NSString).deletingLastPathComponent
        if !FolderAccess.shared.startAccess(path: folder) && !FolderAccess.doesNotExist(folder) {
            _ = FolderAccess.shared.ensureAccess(paths: [folder], parent: window, message: L10n.tr(
                "「%@」の tags ファイルを読むには、このフォルダー（またはその上のフォルダー）へのアクセスを許可してください。", comment: "タグジャンプのフォルダーの許可"))
        }
        return base
    }

    /// ジャンプ（原版 TagJumpSub）：タグジャンプバックのために今の位置を覚える
    func tagJumpTo(path: String, line: Int, close: Bool) {
        FolderAccess.shared.startAccess(file: path)
        TagJumpStack.push(self, caret)
        openAndJump(path: path, line: line, column: 0, close: close)
    }

    /// メニュー（原版 IsFuncEnable：Grep の窓口と無題のときは使えない）
    func validateTagJumpMenuItem(_ menuItem: NSMenuItem) -> Bool? {
        switch menuItem.action {
        case #selector(directTagJump(_:)), #selector(tagJumpKeyword(_:)):
            return !hasMarkedText() && !(sakuraDocument?.isGrepMode ?? false) && !document.path.isEmpty
        default:
            return nil
        }
    }
}

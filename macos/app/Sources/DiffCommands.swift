// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge

/// 比較の相手になる、ほかの編集中の文書（原版 CAppNodeManager::GetOpenedWindowArr と MYWM_GETFILEINFO）
struct EditingDocument {
    let view: EditorTextView
    var document: EditorDocument { view.document }
    var path: String { document.path }
    var isGrep: Bool { view.sakuraDocument?.isGrepMode ?? false }

    /// 一覧の文字（原版 GetMenuFullLabel_WinListNoEscape）。index が -1 のときはアクセスキーなし
    func label(index: Int) -> String {
        EditorCore.windowListLabel(path: path, untitledId: -1, modified: document.isModified, encoding: document.encoding,
                                   grepKey: isGrep ? view.sakuraDocument?.grepKey : nil, index: index)
    }

    /// 開いている文書（单元测试换掉）
    static var all: () -> [EditorTextView] = {
        NSDocumentController.shared.documents.compactMap { ($0 as? SakuraDocument)?.editorWindowController?.textView }
    }
}

// MARK: - DIFF差分表示（IDD_DIFF）

/// DIFF差分表示 のダイアログ（第 44 步，原版 CDlgDiff）。布局照原版 IDD_DIFF（Resources/EditSupportDialogs.json）
final class DiffDialogController: NSObject, NSWindowDelegate {
    /// 模态运行（单元测试换掉）
    static var runModal: ((DiffDialogController) -> Bool)?
    /// ファイルの選択（单元测试换掉）
    static var chooseFile: (_ initial: String, _ parent: NSWindow?) -> String? = { initial, parent in
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if !initial.isEmpty { panel.directoryURL = URL(fileURLWithPath: (initial as NSString).deletingLastPathComponent, isDirectory: true) }
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
    /// 原版 m_pShareData->m_nDiffFlgOpt（sakura.ini の [Other] nDiffFlgOpt）
    static var lastFlags: Int {
        get { Int(EditorCore.commonSetting(section: "Other", key: "nDiffFlgOpt") ?? "0") ?? 0 }
        set { _ = EditorCore.setCommonSetting(String(newValue), section: "Other", key: "nDiffFlgOpt") }
    }

    let page: PropPage
    let window: NSPanel
    let view: EditorTextView
    /// 一覧の文書（一覧の順）
    private(set) var others: [EditingDocument] = []
    private var indexSave = 0
    private var accepted = false

    /// OK 後：選択肢（原版 m_nDiffFlgOpt）、相手のファイル（外部ファイルのとき）または文書
    private(set) var flags = 0
    private(set) var file2 = ""
    private(set) var target: EditingDocument?

    init?(view: EditorTextView) {
        guard let definition = PropDialogs.load("EditSupportDialogs")?.dialog("IDD_DIFF") else { return nil }
        self.view = view
        page = PropPage(definition: definition)
        window = NSPanel(contentRect: NSRect(origin: .zero, size: page.view.frame.size), styleMask: [.titled], backing: .buffered, defer: true)
        window.title = definition.name
        window.contentView = page.view
        window.isReleasedWhenClosed = false
        super.init()
        window.delegate = self
        (page.control("IDOK") as? NSButton)?.keyEquivalent = "\r"
        (page.control("IDCANCEL") as? NSButton)?.keyEquivalent = "\u{1b}"
        page.setUnavailable(["IDC_BUTTON_HELP"], reason: L10n.tr("Mac 版にはまだヘルプがありません", comment: "help"))
        page.onButton = { [weak self] id in self?.buttonClicked(id) }
        page.onChange = { [weak self] id in self?.controlChanged(id) }
        setData()
    }

    // MARK: - 原版 SetData・GetData

    private func setData() {
        flags = Self.lastFlags
        page.setChecked("IDC_CHECK_DIFF_OPT_CASE", flags & 0x01 != 0)
        page.setChecked("IDC_CHECK_DIFF_OPT_SPACE", flags & 0x02 != 0)
        page.setChecked("IDC_CHECK_DIFF_OPT_SPCCHG", flags & 0x04 != 0)
        page.setChecked("IDC_CHECK_DIFF_OPT_BLINE", flags & 0x08 != 0)
        page.setChecked("IDC_CHECK_DIFF_OPT_TABSPC", flags & 0x10 != 0)
        page.setChecked("IDC_RADIO_DIFF_FILE1", flags & 0x20 == 0)
        page.setChecked("IDC_RADIO_DIFF_FILE2", flags & 0x20 != 0)
        page.setChecked("IDC_CHECK_DIFF_EXEC_STATE", flags & 0x40 != 0)
        let settings = EditorCore.searchSettings
        page.setChecked("IDC_CHECK_NOTIFYNOTFOUND", settings.notifyNotFound)
        page.setChecked("IDC_CHECK_SEARCHALL", settings.searchAll)

        // 編集中のファイル一覧：自分は上の欄に、ほかは一覧に。名前の似ているもの（同じ文字コード）を選ぶ
        let all = EditingDocument.all()
        let file1 = (view.document.path as NSString).lastPathComponent
        var score = 0, selectedCode: EditorEncoding = -1
        var entries: [(label: String, doc: EditingDocument)] = []
        for (i, other) in all.enumerated() {
            let doc = EditingDocument(view: other)
            if other === view {
                page.setText("IDC_STATIC_DIFF_SRC", doc.label(index: -1))
                continue
            }
            entries.append((doc.label(index: i), doc))
        }
        entries.sort { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }	// LBS_SORT
        others = entries.map(\.doc)
        var selIndex = 0
        for (index, doc) in others.enumerated() {
            let scoreTemp = EditorCore.fileMatchScore(file1, (doc.path as NSString).lastPathComponent)
            if score < scoreTemp || (selectedCode != view.document.encoding && view.document.encoding == doc.document.encoding && score == scoreTemp) {
                score = scoreTemp
                selIndex = index
                selectedCode = doc.document.encoding
            }
        }
        let list = page.list("IDC_LIST_DIFF_FILES")
        list?.setRows(entries.map { [$0.label] })
        list?.onSelect = { [weak self] in self?.listSelected() }
        if others.isEmpty {
            page.setChecked("IDC_RADIO_DIFF_DST1", true)
            page.setChecked("IDC_RADIO_DIFF_DST2", false)
            page.setEnabled("IDC_RADIO_DIFF_DST2", false)
            page.setEnabled("IDC_LIST_DIFF_FILES", false)
        } else {
            page.setChecked("IDC_RADIO_DIFF_DST1", false)
            page.setChecked("IDC_RADIO_DIFF_DST2", true)
            list?.select(selIndex)
        }
        indexSave = selIndex
    }

    /// TRUE==正常 FALSE==入力エラー（原版 GetData）
    private func getData() -> Bool {
        flags = 0
        if page.isChecked("IDC_CHECK_DIFF_OPT_CASE") { flags |= 0x01 }
        if page.isChecked("IDC_CHECK_DIFF_OPT_SPACE") { flags |= 0x02 }
        if page.isChecked("IDC_CHECK_DIFF_OPT_SPCCHG") { flags |= 0x04 }
        if page.isChecked("IDC_CHECK_DIFF_OPT_BLINE") { flags |= 0x08 }
        if page.isChecked("IDC_CHECK_DIFF_OPT_TABSPC") { flags |= 0x10 }
        if page.isChecked("IDC_RADIO_DIFF_FILE2") { flags |= 0x20 }
        if page.isChecked("IDC_CHECK_DIFF_EXEC_STATE") { flags |= 0x40 }
        Self.lastFlags = flags
        file2 = ""
        target = nil
        var ok = true
        if page.isChecked("IDC_RADIO_DIFF_DST1") {
            file2 = page.text("IDC_EDIT_DIFF_DST")
            if file2.isEmpty { ok = false }
        } else if page.isChecked("IDC_RADIO_DIFF_DST2") {
            let row = page.list("IDC_LIST_DIFF_FILES")?.selectedRow ?? -1
            if others.indices.contains(row) { target = others[row] } else { ok = false }
        } else {
            ok = false
        }
        let settings = EditorCore.searchSettings
        settings.notifyNotFound = page.isChecked("IDC_CHECK_NOTIFYNOTFOUND")
        settings.searchAll = page.isChecked("IDC_CHECK_SEARCHALL")
        EditorCore.searchSettings = settings
        return ok
    }

    // MARK: - 操作

    private func buttonClicked(_ id: String) {
        switch id {
        case "IDC_BUTTON_DIFF_DST":	// 参照
            if let path = Self.chooseFile(view.document.path, window) {
                page.setText("IDC_EDIT_DIFF_DST", path)
                page.setChecked("IDC_RADIO_DIFF_DST1", true)
                page.setChecked("IDC_RADIO_DIFF_DST2", false)
                deselectList()
            }
        case "IDOK":
            accepted = getData()
            close()
        case "IDCANCEL":
            accepted = false
            close()
        default:
            break
        }
    }

    private func deselectList() {
        guard let list = page.list("IDC_LIST_DIFF_FILES") else { return }
        if list.selectedRow >= 0 { indexSave = list.selectedRow }
        list.onSelect = nil
        list.table.deselectAll(nil)
        list.onSelect = { [weak self] in self?.listSelected() }
    }

    /// 一覧を選んだ（原版 OnLbnSelChange）
    private func listSelected() {
        page.setChecked("IDC_RADIO_DIFF_DST1", false)
        page.setChecked("IDC_RADIO_DIFF_DST2", true)
    }

    /// 外部ファイルの名前を変えた（原版 OnEnChange）、ラジオボタン（原版 OnBnClicked の IDC_RADIO_DIFF_DST1・DST2）
    private func controlChanged(_ id: String) {
        switch id {
        case "IDC_EDIT_DIFF_DST":
            page.setChecked("IDC_RADIO_DIFF_DST1", true)
            page.setChecked("IDC_RADIO_DIFF_DST2", false)
            deselectList()
        case "IDC_RADIO_DIFF_DST1":
            deselectList()
        case "IDC_RADIO_DIFF_DST2":
            if let list = page.list("IDC_LIST_DIFF_FILES"), list.selectedRow < 0 { list.select(indexSave) }
        default:
            break
        }
    }

    func run(parent: NSWindow?) -> Bool {
        if let hook = Self.runModal { return hook(self) }
        if let parent {
            let frame = parent.frame
            window.setFrameOrigin(NSPoint(x: frame.midX - window.frame.width / 2, y: frame.midY - window.frame.height / 2))
        } else {
            window.center()
        }
        NSApp.runModal(for: window)
        return accepted
    }

    /// 单元测试：按钮
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
        accepted = false
        close()
        return false
    }
}

// MARK: - ファイル内容比較（IDD_COMPARE）

/// ファイル内容比較 のダイアログ（第 44 步，原版 CDlgCompare）。原版は別のプロセスの窓口、Mac 版は同じ App の窓口から選ぶ
final class CompareDialogController: NSObject, NSWindowDelegate {
    static var runModal: ((CompareDialogController) -> Bool)?

    let page: PropPage
    let window: NSPanel
    let view: EditorTextView
    private(set) var others: [EditingDocument] = []
    private var accepted = false
    private(set) var target: EditingDocument?
    private(set) var tileHorizontally = false

    init?(view: EditorTextView) {
        guard let definition = PropDialogs.load("EditSupportDialogs")?.dialog("IDD_COMPARE") else { return nil }
        self.view = view
        page = PropPage(definition: definition)
        window = NSPanel(contentRect: NSRect(origin: .zero, size: page.view.frame.size), styleMask: [.titled], backing: .buffered, defer: true)
        window.title = definition.name
        window.contentView = page.view
        window.isReleasedWhenClosed = false
        super.init()
        window.delegate = self
        (page.control("IDOK") as? NSButton)?.keyEquivalent = "\r"
        (page.control("IDCANCEL") as? NSButton)?.keyEquivalent = "\u{1b}"
        page.setUnavailable(["IDC_BUTTON_HELP"], reason: L10n.tr("Mac 版にはまだヘルプがありません", comment: "help"))
        page.onButton = { [weak self] id in self?.buttonClicked(id) }
        page.list("IDC_LIST_FILES")?.onDoubleClick = { [weak self] _, _ in self?.buttonClicked("IDOK") }
        setData()
    }

    /// 原版 SetData：自分以外の窓口の一覧。名前の一番似ているものを選ぶ
    private func setData() {
        let file1 = (view.document.path as NSString).lastPathComponent
        var entries: [(label: String, doc: EditingDocument)] = []
        for (i, other) in EditingDocument.all().enumerated() {
            let doc = EditingDocument(view: other)
            if other === view {
                page.setText("IDC_STATIC_COMPARESRC", doc.label(index: -1))
                continue
            }
            entries.append((doc.label(index: i), doc))
        }
        entries.sort { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }	// LBS_SORT
        others = entries.map(\.doc)
        var score = 0, selIndex = 0
        for (index, doc) in others.enumerated() {
            let scoreTemp = EditorCore.fileMatchScore(file1, (doc.path as NSString).lastPathComponent)
            if score < scoreTemp {
                score = scoreTemp
                selIndex = index
            }
        }
        page.list("IDC_LIST_FILES")?.setRows(entries.map { [$0.label] })
        page.list("IDC_LIST_FILES")?.select(selIndex)
        page.setChecked("IDC_CHECK_TILE_H", GrepDialogController.commonBool("bCompareAndTileHorz"))
    }

    private func buttonClicked(_ id: String) {
        switch id {
        case "IDOK":
            let row = page.list("IDC_LIST_FILES")?.selectedRow ?? -1
            guard others.indices.contains(row) else { return }	// 原版 GetData が FALSE：閉じない
            target = others[row]
            tileHorizontally = page.isChecked("IDC_CHECK_TILE_H")
            accepted = true
            close()
        case "IDCANCEL":
            accepted = false
            close()
        default:
            break
        }
    }

    func run(parent: NSWindow?) -> Bool {
        if let hook = Self.runModal { return hook(self) }
        if let parent {
            let frame = parent.frame
            window.setFrameOrigin(NSPoint(x: frame.midX - window.frame.width / 2, y: frame.midY - window.frame.height / 2))
        } else {
            window.center()
        }
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
        accepted = false
        close()
        return false
    }
}

// MARK: - 命令

/// DIFF差分表示・ファイル内容比較（第 44 步，原版 cmd/CViewCommander_Diff.cpp、view/CEditView_Diff.cpp）
extension EditorTextView {
    /// 検索 > DIFF差分表示...（F_DIFF_DIALOG，原版 Command_Diff_Dialog）
    @objc func diffDialog(_ sender: Any?) {
        guard !hasMarkedText(), let dialog = DiffDialogController(view: self), dialog.run(parent: window) else { return }
        let otherText: String
        if let target = dialog.target {
            otherText = target.document.text
        } else {
            guard let text = readDiffFile(dialog.file2) else { return }
            otherText = text
        }
        viewDiff(otherText, flags: dialog.flags)
    }

    /// 相手のファイルを読む（原版 Command_Diff の IsFileExists、MakeDiffTmpFile2）。沙盒：読めないときはフォルダーの許可を求める
    func readDiffFile(_ path: String) -> String? {
        let folder = (path as NSString).deletingLastPathComponent
        if !FileManager.default.isReadableFile(atPath: path) && !FolderAccess.doesNotExist(path) {
            _ = FolderAccess.shared.ensureAccess(paths: [folder], parent: window, message: L10n.tr(
                "「%@」のファイルと比べるには、このフォルダーへのアクセスを許可してください。", comment: "DIFF のフォルダーの許可"))
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue,
              let text = EditorDocument.textOfFile(atPath: path) else {
            Self.showMessage(L10n.tr("差分コマンド実行は失敗しました。\n\n比較するファイルが見つかりません。", comment: "STR_ERR_DLGEDITVWDIFF1"),
                             style: .warning)
            return nil
        }
        return text
    }

    /// 差分表示（原版 ViewDiffInfo）：差分を計算して、この文書の行に印を付ける
    func viewDiff(_ otherText: String, flags: Int) {
        switch document.applyDiff(otherText, flags: flags) {
        case .binary:
            Self.showMessage(L10n.tr("DIFF差分を行おうとしたファイルはバイナリファイルです。", comment: "STR_ERR_DLGEDITVWDIFF4"),
                             style: .warning)
        case .noDiff:
            if flags & 0x40 != 0 {	// DIFF差分がないときにメッセージを表示
                Self.showMessage(L10n.tr("DIFF差分は見つかりませんでした。", comment: "STR_ERR_DLGEDITVWDIFF5"))
            }
        default:
            break
        }
        needsDisplay = true
    }

    /// 次の差分へ（F_DIFF_NEXT）
    @objc func diffNext(_ sender: Any?) { moveToDiff(next: true) }

    /// 前の差分へ（F_DIFF_PREV）
    @objc func diffPrev(_ sender: Any?) { moveToDiff(next: false) }

    /// 原版 Command_Diff_Next / Prev（選択ロック中は選択を広げる）
    private func moveToDiff(next: Bool) {
        var wrapped: ObjCBool = false
        let line = document.findDiffMark(from: caret.line, forward: next, searchAll: EditorCore.searchSettings.searchAll, wrapped: &wrapped)
        if line >= 0 {
            moveCursorSelecting(EditorPosition(line: line, column: 0))
            sendSearchStatus(next: next, wrapped: wrapped.boolValue)
            return
        }
        sendSearchStatus(next: next, wrapped: nil)
        Self.alertNotFound(next
            ? L10n.tr("前方(↓) に差分が見つかりません。", comment: "STR_DIFF_NEXT_NOT_FOUND")
            : L10n.tr("後方(↑) に差分が見つかりません。", comment: "STR_DIFF_PREV_NOT_FOUND"))
    }

    /// 差分の全解除（F_DIFF_RESET）
    @objc func diffReset(_ sender: Any?) {
        document.resetDiffMarks()
        needsDisplay = true
    }

    /// ファイル内容比較（F_COMPARE，原版 Command_COMPARE）：カーソル位置から一文字ずつ比べ、最初に異なる位置へ両方のカーソルを移す
    @objc func compareFiles(_ sender: Any?) {
        guard !hasMarkedText(), let dialog = CompareDialogController(view: self), dialog.run(parent: window),
              let target = dialog.target else { return }
        GrepDialogController.setCommon("bCompareAndTileHorz", dialog.tileHorizontally)
        var mine = EditorPosition(), theirs = EditorPosition()
        let different = document.compare(with: target.document, from: caret, otherFrom: target.view.caret, mine: &mine, theirs: &theirs)
        // 比較後、左右に並べて表示
        if dialog.tileHorizontally, let left = window, let right = target.view.window, let screen = left.screen ?? NSScreen.main {
            let area = screen.visibleFrame
            let width = area.width / 2
            for w in [left, right] where w.isZoomed { w.zoom(nil) }
            right.setFrame(NSRect(x: area.minX + width, y: area.minY, width: width, height: area.height), display: true)
            left.setFrame(NSRect(x: area.minX, y: area.minY, width: width, height: area.height), display: true)
        }
        if different {
            target.view.setCaret(theirs)
            setCaret(mine)
            window?.makeKeyAndOrderFront(nil)
            Self.showMessage(L10n.tr("異なる箇所が見つかりました。", comment: "STR_ERR_CEDITVIEW_CMD23"), style: .warning)
        } else {
            window?.makeKeyAndOrderFront(nil)
            Self.showMessage(L10n.tr("異なる箇所は見つかりませんでした。", comment: "STR_ERR_CEDITVIEW_CMD22"))
        }
    }

    /// メニューの有効・無効（原版 IsFuncEnable：差分を表示していないときは次・前・全解除は使えない、
    /// ファイル内容比較は窓口が 2 つ以上）
    func validateDiffMenuItem(_ menuItem: NSMenuItem) -> Bool? {
        switch menuItem.action {
        case #selector(diffNext(_:)), #selector(diffPrev(_:)), #selector(diffReset(_:)):
            return document.isDiffUsed
        case #selector(compareFiles(_:)):
            return EditingDocument.all().count >= 2
        default:
            return nil
        }
    }
}

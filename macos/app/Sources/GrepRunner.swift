// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge

/// Grep・Grep置換 的执行和结果的窗口，タグジャンプ（第 43 步。原版 CViewCommander_Grep.cpp、CGrepAgent::DoGrep 的窗口部分、
/// CViewCommander_TagJump.cpp）。
///
/// 检索在核心库（GrepSession：原版 DoGrep）里，在别的线程运行。这里：
/// - 决定结果的窗口（原版 Command_GREP：Grep 的窗口（检索中以外）、或者没改过的空的无题窗口就用这个窗口，否则开新窗口）
/// - 「Grep実行中」对话框（IDD_GREPRUNNING：件数、ファイル、フォルダー、リアルタイム表示、キャンセル）
/// - 每 0.1 秒取出结果加到文档的最后（リアルタイム表示 关着时最后一次加）
/// - 结束时：没有修改、光标在加入之前的行、Grep 的条件用「検索文字列」的颜色显示（原版 m_bCurSrchKeyMark）
final class GrepRunner: NSObject {
    /// 「Grep実行中」对话框（单元测试不显示）
    static var showsRunningPanel = true
    /// 进行中的 Grep（单元测试等它结束）
    private(set) static var running: [GrepRunner] = []

    weak var view: EditorTextView?
    let session: GrepSession
    let options: GrepOptions
    private var timer: Timer?
    private var panel: GrepRunningPanel?
    private var pending = ""
    private var startLine = 0
    private(set) var finished = false
    /// 结束后（单元测试）
    var onFinish: ((GrepResult) -> Void)?

    init(view: EditorTextView, options: GrepOptions, sources: [GrepSourceText]) {
        self.view = view
        self.options = options
        session = GrepSession(options: options, sources: sources)
        super.init()
    }

    /// 开始（原版 DoGrep）
    func start() {
        guard let view else { return }
        Self.running.append(self)
        let document = view.sakuraDocument
        document?.isGrepMode = true
        document?.grepKey = options.key
        document?.grepRunner = self
        document?.contentDidChange()
        // 検索文字列のマーク（原版 m_bCurSrchKeyMark、m_strCurSearchKey、m_sCurSearchOption）
        var searchOptions: EditorSearchOptions = []
        if options.matchCase { searchOptions.insert(.matchCase) }
        if options.wholeWord { searchOptions.insert(.wholeWord) }
        if options.regularExpression { searchOptions.insert(.regularExpression) }
        view.searchState.key = options.key
        view.searchState.options = searchOptions
        view.searchState.sequence = EditorCore.searchKeySequence
        view.searchState.markOn = true
        startLine = view.document.endPosition.line	// 原版 tmp_PosY_Layout：Grep 直前の位置
        if Self.showsRunningPanel, let window = view.window {
            panel = GrepRunningPanel(runner: self, parent: window)
            panel?.show()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.poll() }
        let session = self.session
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = session.run()
            DispatchQueue.main.async { self?.finish(result) }
        }
    }

    /// 結果を取り出して足す（リアルタイム表示のときだけ文書に足す）、進み具合を表示する
    private func poll() {
        pending += session.takeOutput()
        if session.realTimeView {
            flush()
        }
        panel?.update(hitCount: session.progressHitCount, file: session.progressFile, folder: session.progressFolder)
    }

    private func flush() {
        guard !pending.isEmpty, let view else { return }
        let end = view.document.appendWithoutUndo(pending)
        pending = ""
        view.textChanged()
        view.setCaret(end)	// 原版 Command_GOFILEEND
    }

    func cancel() {
        session.cancel()
    }

    private func finish(_ result: GrepResult) {
        timer?.invalidate()
        timer = nil
        pending += session.takeOutput()
        flush()
        finished = true
        panel?.close()
        panel = nil
        Self.running.removeAll { $0 === self }
        if let view {
            view.document.setUnmodified()	// 原版 SetModified(false,false)
            view.setCaret(EditorPosition(line: startLine, column: 0))	// カーソルをGrep直前の位置に戻す
            view.textChanged()
            view.sakuraDocument?.grepRunner = nil
            view.sakuraDocument?.contentDidChange()
            view.window?.makeKeyAndOrderFront(nil)	// 原版 ActivateFrameWindow
            view.refreshOutline()	// 原版 CNormalProcess：Grep 後にアウトラインを再解析
        }
        if !result.errorMessage.isEmpty {
            GrepDialogController.showMessage(result.errorMessage, view?.window)
        }
        onFinish?(result)
    }
}

/// 「Grep実行中」对话框（原版 IDD_GREPRUNNING、CDlgGrepRunning）
final class GrepRunningPanel: NSObject, NSWindowDelegate {
    let page: PropPage
    let window: NSPanel
    weak var runner: GrepRunner?
    weak var parent: NSWindow?

    init?(runner: GrepRunner, parent: NSWindow) {
        guard let definition = PropDialogs.load("GrepDialogs")?.dialog("IDD_GREPRUNNING") else { return nil }
        self.runner = runner
        self.parent = parent
        page = PropPage(definition: definition)
        window = NSPanel(contentRect: NSRect(origin: .zero, size: page.view.frame.size), styleMask: [.titled], backing: .buffered, defer: true)
        window.title = definition.name
        window.contentView = page.view
        window.isReleasedWhenClosed = false
        window.isFloatingPanel = true
        super.init()
        window.delegate = self
        (page.control("IDCANCEL") as? NSButton)?.keyEquivalent = "\u{1b}"
        page.setChecked("IDC_CHECK_REALTIMEVIEW", runner.session.realTimeView)
        update(hitCount: 0, file: " ", folder: "")
        page.onButton = { [weak self] id in
            if id == "IDCANCEL" { self?.runner?.cancel() }
        }
        page.onChange = { [weak self] id in
            guard let self, id == "IDC_CHECK_REALTIMEVIEW" else { return }
            self.runner?.session.realTimeView = self.page.isChecked(id)
        }
    }

    func show() {
        guard let parent else { return }
        let frame = parent.frame
        window.setFrameOrigin(NSPoint(x: frame.midX - window.frame.width / 2, y: frame.midY - window.frame.height / 2))
        parent.addChildWindow(window, ordered: .above)
        window.orderFront(nil)
    }

    func update(hitCount: Int, file: String, folder: String) {
        page.setText("IDC_STATIC_HITCOUNT", String(hitCount))
        page.setText("IDC_STATIC_CURFILE", file)
        page.setText("IDC_STATIC_CURPATH", folder)
    }

    func close() {
        parent?.removeChildWindow(window)
        window.orderOut(nil)
    }
}

// MARK: - 命令

extension EditorTextView {
    /// Grep の結果の新しい窓口（単体テストでは NSDocumentController を使わずに作る）
    static var makeGrepDocument: () -> SakuraDocument? = {
        try? NSDocumentController.shared.openUntitledDocumentAndDisplay(true) as? SakuraDocument
    }

    var sakuraDocument: SakuraDocument? {
        window?.windowController?.document as? SakuraDocument
    }

    /// Grep の窓口か（原版 m_pcGrepAgent->m_bGrepMode）
    var isGrepMode: Bool { sakuraDocument?.isGrepMode ?? false }

    /// 対話框の初期の検索文字列（原版 GetCurrentTextForSearchDlg(cmem, bGetHistory)）。設定しないときは nil
    func currentTextForGrepDialog(getHistory: Bool) -> String? {
        if hasSelection { return currentTextForSearch() }
        var get = false
        if EditorCore.searchSettings.caretTextForSearch {
            let text = currentTextForSearch()
            if !text.isEmpty { return text }
            get = getHistory
        } else {
            get = true
        }
        guard get else { return nil }
        if let first = EditorCore.searchKeyHistory.first, searchState.sequence < EditorCore.searchKeySequence {
            return first
        }
        return searchState.sequence >= 0 ? searchState.key : nil
    }

    /// 「編集中のテキストから検索」の文書の番号（原版はウィンドウハンドル）
    var grepSourceID: UInt64 { UInt64(UInt(bitPattern: ObjectIdentifier(self).hashValue)) }

    /// この文書の全部の行（「編集中のテキストから検索」。Grep は別のスレッドなので先に取り出す）
    func grepSourceText() -> GrepSourceText {
        let source = GrepSourceText()
        source.sourceID = grepSourceID
        source.filePath = sakuraDocument?.fileURL?.path ?? ""
        source.windowLabel = sakuraDocument?.displayName ?? ""
        source.isGrep = isGrepMode
        source.encoding = document.encoding
        source.lines = (0..<document.lineCount).map { document.line(at: $0, withEol: true) }
        return source
    }

    /// 検索 > Grep（F_GREP_DIALOG。原版 Command_GREP_DIALOG）
    @objc func showGrepDialog(_ sender: Any?) {
        guard !hasMarkedText() else { return }
        let state = grepDialogState
        if let text = currentTextForGrepDialog(getHistory: !state.setText) {
            state.text = text
            state.setText = true
        }
        guard let dialog = GrepDialogController(replace: false, state: state, currentFilePath: sakuraDocument?.fileURL?.path ?? "",
                                                sourceToken: GrepCore.sourceToken(grepSourceID)),
              dialog.run(parent: window), let options = dialog.options else { return }
        grep(options, sources: state.fromThisText ? [grepSourceText()] : [])
    }

    /// 検索 > Grep置換（F_GREP_REPLACE_DLG。原版 Command_GREP_REPLACE_DLG）
    @objc func showGrepReplaceDialog(_ sender: Any?) {
        guard !hasMarkedText() else { return }
        let state = grepReplaceDialogState
        if let text = currentTextForGrepDialog(getHistory: !state.setText), !text.isEmpty {
            state.text = text
            state.setText = true
        }
        if let first = EditorCore.replaceKeyHistory.first, state.replaceKeySequence < EditorCore.replaceKeySequence {
            state.text2 = first
        }
        guard let dialog = GrepDialogController(replace: true, state: state, currentFilePath: sakuraDocument?.fileURL?.path ?? "",
                                                sourceToken: GrepCore.sourceToken(grepSourceID)),
              dialog.run(parent: window), let options = dialog.options else { return }
        if options.paste {
            options.pasteText = grepPasteText()
        }
        grep(options, sources: [])
    }

    /// Grep置換の貼り付ける文字（原版 DoGrep の MyGetClipboardData と続く処理）
    func grepPasteText() -> String? {
        guard var text = clipboardText else { return nil }
        let settings = document.editSettings
        let types = pasteboard.types ?? []
        // 矩形・ラインモード貼り付けは未サポート。ラインモードのテキストで末尾が改行でなければ改行を足す
        if settings.lineModePaste && types.contains(Self.lineSelectType), let last = text.utf16.last, !Self.isLineDelimiter(last) {
            text += EditorCore.text(ofEol: document.newLineEol)
        }
        if settings.convertEolOnPaste {
            text = document.convertEolToNewLine(text)
        }
        return text
    }

    /// Grep を実行する（原版 Command_GREP・Command_GREP_REPLACE）：この窓口か新しい窓口に結果を出す
    func grep(_ options: GrepOptions, sources: [GrepSourceText]) {
        let doc = sakuraDocument
        let useThis = (isGrepMode && doc?.grepRunner == nil)
            || (!document.isModified && doc?.fileURL == nil)
        if useThis {
            if !document.isModified && document.lineCount == 0 && !isGrepMode {
                // Grep タイプ別適用（拡張子 grepout のタイプ）
                if document.changeTypeTemporarily(GrepCore.outputTypeIndex) { typeSettingsReloaded() }
            }
            GrepRunner(view: self, options: options, sources: sources).start()
            return
        }
        // 新しい窓口（原版 CControlTray::DoGrepCreateWindow：-GREPMODE で起動、タイプは grepout）
        guard let newDoc = Self.makeGrepDocument(), let newView = newDoc.editorWindowController?.textView else { return }
        if newView.document.changeTypeTemporarily(GrepCore.outputTypeIndex) { newView.typeSettingsReloaded() }
        newView.grepDialogState.text = grepDialogState.text
        newView.grepDialogState.setText = true
        GrepRunner(view: newView, options: options, sources: sources).start()
    }
}

// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge
import UniformTypeIdentifiers

/// キーマクロ（第 45 步。原版 CViewCommander_Macro.cpp、CKeyMacroMgr、CViewCommander::HandleCommand の記録の部分）。
///
/// - キーマクロの記録開始／終了（F_RECKEYMACRO）：記録中は、実行した機能（キーマクロに記録できるもの：MacroCore.canRecord）を
///   原版 CMacro::AddLParam と同じ引数で記録する（MacroHost.recordedArgs）。記録をやめるとマクロ用フォルダーの RecKey.mac に保存し、
///   それが「キーマクロの実行」で実行するファイルになる
/// - 記録する場所：CommandTable.perform（キー割り当て）、メニュー（NSMenu.willSendActionNotification、項目の tag が機能番号）、
///   入力（insertText → Char・CharIme）、キーの既定の動き（doCommand(by:) の選択子 → 機能番号）、検索・置換・ジャンプのダイアログ
/// - 記録中は窓口のタイトルに「【キーマクロの記録中】」（原版のキャプションの ${M?…$}）。ステータスバーの REC 欄も濃く表示する（第 38 步）
/// - キーマクロの保存（F_SAVEKEYMACRO）・読み込み（F_LOADKEYMACRO。原版と同じくファイル名を覚えるだけ）・実行（F_EXECKEYMACRO。実行の直前に読む）。
///   選んだファイルは安全書签を残す（BookmarkStore.settingFiles。沙盒で再起動後も読める）
/// - 実行は全体で一つの取り消し単位（原版 ExecKeyMacroAfter の SetUndoBuffer）
final class KeyMacroRecorder {
    static let shared = KeyMacroRecorder()

    /// キーボードマクロの記録中（原版 m_bRecordingKeyMacro）
    private(set) var isRecording = false
    /// 記録中のウィンドウ（原版 m_hwndRecordingKeyMacro）
    private(set) weak var window: NSWindow?
    /// キーマクロのバッファ（原版 CSMacroMgr の STAND_KEYMACRO）
    var calls: [MacroCall] = []
    /// 実行するキーマクロのファイル（原版 m_szKeyMacroFileName。設定ファイルには保存しない）
    var keyMacroFileName = ""
    /// 記録しない（マクロの中から機能を呼ぶとき等）
    var suppressed = 0

    private init() {
        // メニューから実行した機能を記録する（原版はメニューも HandleCommand を通る）
        NotificationCenter.default.addObserver(forName: NSMenu.willSendActionNotification, object: nil, queue: nil) { [weak self] note in
            guard let item = note.userInfo?["MenuItem"] as? NSMenuItem else { return }
            MainActor.assumeIsolated { self?.menuWillSendAction(item) }
        }
        // 記録中のウィンドウを閉じたら記録をやめる（原版 WM_DESTROY。保存しない）
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: nil) { [weak self] note in
            guard let self, self.isRecording, let window = note.object as? NSWindow, window === self.window else { return }
            self.isRecording = false
            self.window = nil
        }
    }

    /// このウィンドウで記録中か
    func isRecording(in window: NSWindow?) -> Bool {
        isRecording && window != nil && self.window === window
    }

    func start(in window: NSWindow?) {
        calls = []
        isRecording = true
        self.window = window
        Self.updateTitles()
    }

    func stop() {
        isRecording = false
        window = nil
        Self.updateTitles()
    }

    /// 記録中のとき、この機能を記録する（原版 CViewCommander::HandleCommand の記録の部分）
    func record(_ code: Int, view: EditorTextView, lParam: Int = 0, text: String? = nil,
                replace: (text: String, options: EditorReplaceOptions)? = nil, jump: EditorJumpOptions? = nil) {
        guard suppressed == 0, isRecording(in: view.window), MacroCore.canRecord(code),
              code != MacroHost.Code.execExtMacro else { return }	// F_EXECEXTMACRO は個別に記録する
        calls.append(MacroCall(code: code, args: MacroHost.recordedArgs(code, view: view, lParam: lParam, text: text,
                                                                         replace: replace, jump: jump)))
    }

    private func menuWillSendAction(_ item: NSMenuItem) {
        guard isRecording, let window = NSApp.keyWindow, window === self.window,
              item.tag > 0, let action = item.action, CommandTable.selector(for: item.tag) == action,
              let view = (window.windowController as? EditorWindowController)?.textView else { return }
        record(item.tag, view: view)
    }

    /// 窓口のタイトル（【キーマクロの記録中】）を出し直す
    static func updateTitles() {
        for document in NSDocumentController.shared.documents {
            for controller in document.windowControllers { controller.synchronizeWindowTitleWithDocumentName() }
        }
    }

    /// タイトルに付ける文字（原版 STR_CAPTION_ACTIVE_KEYMACRO。既定のキャプション「${M?  【キーマクロの記録中】$}」）
    static var recordingCaption: String { "  " + L10n.tr("【キーマクロの記録中】", comment: "STR_CAPTION_ACTIVE_KEYMACRO") }

    // MARK: - ファイル

    /// マクロ用フォルダー（共通設定 Folders の szMACROFOLDER。相対パスは設定ファイルのフォルダーから。原版 GetInidirOrExedir）
    static var macroFolder: String {
        let iniDir = (EditorCore.settingsFilePath as NSString).deletingLastPathComponent
        let folder = EditorCore.commonSetting(section: "Folders", key: "szMACROFOLDER") ?? ""
        // 空・Windows のパス（インポートした設定）は設定ファイルのフォルダー
        if folder.isEmpty || folder.contains("\\") || folder.contains(":") { return iniDir }
        if folder.hasPrefix("/") { return folder }
        return (iniDir as NSString).appendingPathComponent(folder)
    }

    /// 記録したキーマクロのファイル（原版 GetMacroFilename(-1)：マクロ用フォルダーの RecKey.mac）
    static var recordFilePath: String {
        (macroFolder as NSString).appendingPathComponent("RecKey.mac")
    }
}

// MARK: - コマンド（原版 CViewCommander_Macro.cpp）

extension EditorTextView {
    /// 保存ダイアログ（原版 CDlgOpenFile::DoModal_GetSaveFileName、*.mac）。単体テストで差し替える。引数は初期フォルダー
    static var chooseKeyMacroSaveURL: (String, NSWindow?) -> URL? = { folder, _ in
        let panel = NSSavePanel()
        panel.directoryURL = URL(fileURLWithPath: folder, isDirectory: true)
        if let type = UTType(filenameExtension: "mac") { panel.allowedContentTypes = [type] }
        panel.allowsOtherFileTypes = true
        panel.nameFieldStringValue = "RecKey.mac"
        panel.title = L10n.tr("キーマクロの保存", comment: "F_SAVEKEYMACRO")
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// 開くダイアログ（原版 DoModal_GetOpenFileName。すべてのファイル）。単体テストで差し替える
    static var chooseKeyMacroOpenURL: (String, NSWindow?) -> URL? = { folder, _ in
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: folder, isDirectory: true)
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = L10n.tr("キーマクロの読み込み", comment: "F_LOADKEYMACRO")
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// 原版 ErrorMessage（タイトルはアプリ名）
    private static func keyMacroError(_ message: String) {
        MacroHost.showError(AboutPanel.appName, message)
    }

    /// ツール > キーマクロの記録開始／終了（F_RECKEYMACRO）
    @objc func recKeyMacro(_ sender: Any?) {
        let recorder = KeyMacroRecorder.shared
        if recorder.isRecording {
            recorder.stop()
            // キーマクロをマクロ用フォルダーに「RecKey.mac」という名で保存
            let path = KeyMacroRecorder.recordFilePath
            recorder.keyMacroFileName = path
            if !MacroCore.saveKeyMacroFile(path, calls: recorder.calls) {
                Self.keyMacroError(String(format: L10n.tr("マクロファイルを作成できませんでした。\n\n%@", comment: "STR_ERR_CEDITVIEW_CMD25"), path))
            }
        } else {
            recorder.start(in: window)
        }
    }

    /// ツール > キーマクロの保存（F_SAVEKEYMACRO）
    @objc func saveKeyMacro(_ sender: Any?) {
        let recorder = KeyMacroRecorder.shared
        if recorder.isRecording { recorder.stop() }
        guard let url = Self.chooseKeyMacroSaveURL(KeyMacroRecorder.macroFolder, window) else { return }
        BookmarkStore.settingFiles.remember(url)
        if !MacroCore.saveKeyMacroFile(url.path, calls: recorder.calls) {
            Self.keyMacroError(String(format: L10n.tr("マクロファイルを作成できませんでした。\n\n%@", comment: "STR_ERR_CEDITVIEW_CMD27"), url.path))
        }
    }

    /// ツール > キーマクロの読み込み（F_LOADKEYMACRO）：ファイル名を覚えるだけ。実行の直前に読む
    @objc func loadKeyMacro(_ sender: Any?) {
        let recorder = KeyMacroRecorder.shared
        if recorder.isRecording { recorder.stop() }
        guard let url = Self.chooseKeyMacroOpenURL(KeyMacroRecorder.macroFolder, window) else { return }
        BookmarkStore.settingFiles.remember(url)	// 沙盒：再起動まで・再起動後も読めるように
        recorder.keyMacroFileName = url.path
    }

    /// ツール > キーマクロの実行（F_EXECKEYMACRO）
    @objc func execKeyMacro(_ sender: Any?) {
        let recorder = KeyMacroRecorder.shared
        if recorder.isRecording { recKeyMacro(sender) }	// 記録中は終了してから実行
        let path = recorder.keyMacroFileName
        guard !path.isEmpty else { return }
        let result = BookmarkStore.settingFiles.withAccess(path: path) { MacroCore.loadKeyMacroFile(path) }
        guard result.result == .success else {
            // 文法の誤り（原版 LoadKeyMacro のメッセージボックス）のあと、読み込めなかったこと
            if !result.errorMessage.isEmpty { MacroHost.showError(result.errorTitle, result.errorMessage) }
            let format = result.result == .encodingError
                ? L10n.tr("文字コードの変換に失敗しました。\nBOM付きUTF-8またはShift_JIS等で保存されているか確認してください。\n\n%@", comment: "STR_ERR_MACRO_ENCODING")
                : L10n.tr("ファイルを開けませんでした。\n\n%@", comment: "STR_ERR_CEDITVIEW_CMD28")
            Self.keyMacroError(String(format: format, path))
            return
        }
        recorder.calls = result.calls
        runKeyMacro(result.calls, path: path)
    }

    /// キーマクロを実行する（原版 CKeyMacroMgr::ExecKeyMacro2）：全体を一つの取り消し単位にする。途中で失敗したらそこでやめる
    func runKeyMacro(_ calls: [MacroCall], path: String = "") {
        let previousPath = MacroHost.currentMacroPath
        MacroHost.currentMacroPath = path
        MacroHost.beginMacroEdit(document)
        for call in calls where !MacroHost.execute(call, view: self) { break }
        MacroHost.endMacroEdit(document)
        MacroHost.currentMacroPath = previousPath
        contentDidChange(keepCaches: true)	// 各命令が画面を直している。選択は残す
    }

    // MARK: - 記録（入力と既定のキー）

    /// キーの既定の動き（選択子）→ 機能番号（原版の既定のキー割り当て：BkSp、Del、Tab、矢印等）。Return は Char(13)
    static let keyMacroSelectorCodes: [Selector: Int] = [
        #selector(moveUp(_:)): 30311, #selector(moveDown(_:)): 30312, #selector(moveLeft(_:)): 30313, #selector(moveRight(_:)): 30314,
        #selector(moveWordLeft(_:)): 30320, #selector(moveWordRight(_:)): 30321,
        #selector(moveWordBackward(_:)): 30320, #selector(moveWordForward(_:)): 30321,
        #selector(moveToBeginningOfLine(_:)): 30332, #selector(moveToEndOfLine(_:)): 30333,
        #selector(moveToLeftEndOfLine(_:)): 30332, #selector(moveToRightEndOfLine(_:)): 30333,
        #selector(pageUp(_:)): 30342, #selector(pageDown(_:)): 30343,
        #selector(moveToBeginningOfDocument(_:)): 30350, #selector(moveToEndOfDocument(_:)): 30351,
        #selector(moveUpAndModifySelection(_:)): 30411, #selector(moveDownAndModifySelection(_:)): 30412,
        #selector(moveLeftAndModifySelection(_:)): 30413, #selector(moveRightAndModifySelection(_:)): 30414,
        #selector(moveWordLeftAndModifySelection(_:)): 30420, #selector(moveWordRightAndModifySelection(_:)): 30421,
        #selector(moveWordBackwardAndModifySelection(_:)): 30420, #selector(moveWordForwardAndModifySelection(_:)): 30421,
        #selector(moveToBeginningOfLineAndModifySelection(_:)): 30432, #selector(moveToEndOfLineAndModifySelection(_:)): 30433,
        #selector(moveToLeftEndOfLineAndModifySelection(_:)): 30432, #selector(moveToRightEndOfLineAndModifySelection(_:)): 30433,
        #selector(pageUpAndModifySelection(_:)): 30442, #selector(pageDownAndModifySelection(_:)): 30443,
        #selector(moveToBeginningOfDocumentAndModifySelection(_:)): 30450, #selector(moveToEndOfDocumentAndModifySelection(_:)): 30451,
        #selector(moveParagraphForwardAndModifySelection(_:)): 30482, #selector(moveParagraphBackwardAndModifySelection(_:)): 30483,
        #selector(deleteBackward(_:)): 30222, #selector(deleteForward(_:)): 30221,
        #selector(insertTab(_:)): 30260, #selector(insertBacktab(_:)): 30261,
        #selector(insertNewline(_:)): MacroHost.Code.wchar,
    ]

    /// doCommand(by:) で実行する選択子を記録する
    func recordKeyMacro(selector: Selector) {
        guard KeyMacroRecorder.shared.isRecording, let code = Self.keyMacroSelectorCodes[selector] else { return }
        KeyMacroRecorder.shared.record(code, view: self, lParam: code == MacroHost.Code.wchar ? 0x0D : 0)
    }

    /// 入力した文字を記録する（原版 WM_CHAR → F_WCHAR、WM_IME_CHAR → F_IME_CHAR。一文字ずつ）。
    /// BMP 外の文字（サロゲートペア）は一文字ずつにできないので InsText にする
    func recordKeyMacro(typed text: String, fromInputMethod: Bool) {
        let recorder = KeyMacroRecorder.shared
        guard recorder.isRecording, !text.isEmpty else { return }
        if text.unicodeScalars.contains(where: { $0.value > 0xFFFF }) {
            recorder.record(MacroHost.Code.insText, view: self, text: text)
            return
        }
        let code = fromInputMethod ? MacroHost.Code.imeChar : MacroHost.Code.wchar
        for unit in text.utf16 { recorder.record(code, view: self, lParam: Int(unit)) }
    }

    /// キーマクロのメニュー項目（原版 IsFuncEnable、SetMenuFuncSel：記録中は「記録終了」の名前）。キーマクロ以外は nil
    func validateKeyMacroMenuItem(_ menuItem: NSMenuItem) -> Bool? {
        let recorder = KeyMacroRecorder.shared
        let codes = [MacroHost.Code.recKeyMacro, MacroHost.Code.saveKeyMacro, MacroHost.Code.loadKeyMacro, MacroHost.Code.execKeyMacro]
        guard let action = menuItem.action,
              [#selector(recKeyMacro(_:)), #selector(saveKeyMacro(_:)), #selector(loadKeyMacro(_:)), #selector(execKeyMacro(_:))].contains(action),
              codes.contains(menuItem.tag) else { return nil }
        let names: [Int: (String, String)] = [
            MacroHost.Code.recKeyMacro: (L10n.tr("キーマクロの記録開始", comment: "F_RECKEYMACRO_REC"),
                                         L10n.tr("キーマクロの記録終了", comment: "F_RECKEYMACRO_APPE")),
            MacroHost.Code.saveKeyMacro: (L10n.tr("キーマクロの保存", comment: "F_SAVEKEYMACRO_REC"),
                                          L10n.tr("キーマクロの記録終了&保存", comment: "F_SAVEKEYMACRO_APPE")),
            MacroHost.Code.loadKeyMacro: (L10n.tr("キーマクロの読み込み", comment: "F_LOADKEYMACRO_REC"),
                                          L10n.tr("キーマクロの記録終了&読み込み", comment: "F_LOADKEYMACRO_APPE")),
            MacroHost.Code.execKeyMacro: (L10n.tr("キーマクロの実行", comment: "F_EXECKEYMACRO_REC"),
                                          L10n.tr("キーマクロの記録終了&実行", comment: "F_EXECKEYMACRO_APPE")),
        ]
        if let name = names[menuItem.tag] {
            let title = recorder.isRecording ? name.1 : name.0
            if menuItem.title != title { menuItem.title = title }
        }
        // 記録中は記録しているウィンドウだけ（原版 IsFuncEnable）
        if recorder.isRecording { return recorder.isRecording(in: window) && !hasMarkedText() }
        switch menuItem.tag {
        case MacroHost.Code.execKeyMacro: return !recorder.keyMacroFileName.isEmpty && !hasMarkedText()
        default: return !hasMarkedText()
        }
    }
}

extension EditorTextView {
    /// ダイアログから実行する検索・置換・ジャンプを記録する（原版はダイアログも HandleCommand を通る）
    func recordKeyMacro(_ code: Int, replace: (text: String, options: EditorReplaceOptions)? = nil, jump: EditorJumpOptions? = nil) {
        KeyMacroRecorder.shared.record(code, view: self, replace: replace, jump: jump)
    }
}

// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge

/// ファイルの安全機能（第 46 步）：保存時のバックアップ、自動保存、ファイルの更新の監視。
///
/// - バックアップ：原版 CBackupAgent::OnPreBeforeSave。ファイル名の書式・作成は核心库（BackupCore：macos/core/api/Backup.cpp）、
///   確認のメッセージボックスとごみ箱はここ（BackupAlertHandler）。沙盒ではバックアップを作るフォルダーの許可を求める（原版にはない）
/// - 自動保存：原版 CAutoSaveAgent・CPassiveTimer。間隔ごとに、変更があってファイル名があれば「上書き保存」と同じ保存
/// - 更新の監視：原版 CAutoReloadAgent・CDlgFileUpdateQuery。3 秒ごとにファイルの更新日時を比べ、
///   変わっていたら問い合わせ（IDD_FILEUPDATEQUERY）、通知メッセージのみ、未編集で再読込、監視しない
/// 原版は編集窓口の IDT_EDIT タイマー（500 ms）から呼ぶ（CEditWnd::OnEditTimer）。Mac 版は文書ごとに 500 ms のタイマー。

// MARK: - バックアップの確認（原版 MYMESSAGEBOX・TopConfirmMessage）

/// バックアップの作成中のメッセージボックスとごみ箱（核心库の BackupHandler）
final class BackupAlertHandler: NSObject, BackupHandler {
    /// 確認（原版 MB_ICONQUESTION | MB_TOPMOST）。題が空のときは題をアプリ名にする（原版 TopConfirmMessage）
    func confirm(title: String, message: String, withCancel: Bool) -> BackupAnswer {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title.isEmpty ? CommonSettingsPages.appName : title
        alert.informativeText = message
        alert.addButton(withTitle: NSLocalizedString("はい", comment: "メッセージボックス"))
        let no = alert.addButton(withTitle: NSLocalizedString("いいえ", comment: "メッセージボックス"))
        if withCancel {
            let cancel = alert.addButton(withTitle: NSLocalizedString("キャンセル", comment: "メッセージボックス"))
            cancel.keyEquivalent = "\u{1b}"
        } else {
            no.keyEquivalent = "\u{1b}"
        }
        alert.window.setAccessibilityIdentifier("BackupConfirm")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .yes
        case .alertSecondButtonReturn: return .no
        default: return .cancel
        }
    }

    /// 削除・移動の失敗（原版 ::MessageBox(hwnd, path, 「削除失敗」, MB_OK)）
    func showError(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    /// ごみ箱へ（原版 SHFileOperation FO_DELETE FOF_ALLOWUNDO）
    func moveToTrash(_ path: String) -> Bool {
        (try? FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)) != nil
    }
}

extension SakuraDocument {
    /// バックアップの確認・ごみ箱（单元测试换成不出对话框的）
    static var backupHandler: () -> BackupHandler = { BackupAlertHandler() }

    /// 保存の前のバックアップ（原版 CBackupAgent::OnPreBeforeSave）。保存を続けるとき true。
    /// url は保存先（名前を付けて保存で別の既存のファイルに保存するときは、そのファイルのバックアップ。原版 pSaveInfo->cFilePath）
    func backupBeforeSave(to url: URL) -> Bool {
        let path = url.path
        guard BackupCore.isNeeded(for: path) else { return true }
        // 沙盒：バックアップを作るフォルダー（無いときは一段上：MakeBackup は一段だけ作る）の許可。
        // 許可されなくても続ける（作れないと核心库が原版の「バックアップの作成に失敗しました」を確かめる）
        if let backup = BackupCore.formatPath(for: path, date: nil) {
            var folder = (backup as NSString).deletingLastPathComponent
            if FolderAccess.doesNotExist(folder) { folder = (folder as NSString).deletingLastPathComponent }
            _ = FolderAccess.shared.ensureAccess(paths: [folder], parent: windowControllers.first?.window,
                                                 message: NSLocalizedString("バックアップを作成するには、「%@」へのアクセスを許可してください。",
                                                                            comment: "バックアップのフォルダーの許可"))
        }
        return BackupCore.backupBeforeSave(path, handler: Self.backupHandler())
    }

    /// ファイルの更新日時（無いとき nil）
    static func modificationDate(_ path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    /// NSDocument が保存のときに出す「ほかのアプリケーションで変更されました」を出さない（原版は保存のときに確かめない）：
    /// NSDocument の覚えている更新日時を今のファイルのものにする
    func syncFileModificationDate(_ url: URL? = nil) {
        guard let path = (url ?? fileURL)?.path, let date = Self.modificationDate(path) else { return }
        fileModificationDate = date
    }
}

// MARK: - 自動保存のタイマー（原版 CPassiveTimer）

/// 一定時間ごとの動作のタイマー（原版 CPassiveTimer）。呼ばれたときに時間が経ったか調べる
struct PassiveTimer {
    /// 設定できる最大の間隔（分。原版 INT_MAX / 60000）
    static let maxInterval = 35791

    /// 今の時刻（秒。单元测试换える）
    var now: () -> TimeInterval
    /// 間隔（秒）
    private(set) var interval: TimeInterval = 60
    private(set) var isEnabled = false
    private var lastTick: TimeInterval = 0

    init(now: @escaping () -> TimeInterval) {
        self.now = now
    }

    /// 間隔（分）。1～35791 に収める（原版 SetInterval）
    mutating func setInterval(minutes: Int) {
        interval = TimeInterval(min(max(minutes, 1), Self.maxInterval) * 60)
    }

    /// 有効・無効。無効から有効にしたときはリセット（原版 Enable）
    mutating func enable(_ flag: Bool) {
        guard isEnabled != flag else { return }
        isEnabled = flag
        if flag { reset() }
    }

    mutating func reset() {
        lastTick = now()
    }

    /// 所定の時間が経ったら true（このとき測り始めをリセット。原版 CheckAction）
    mutating func checkAction() -> Bool {
        guard isEnabled, now() - lastTick >= interval else { return false }
        reset()
        return true
    }
}

// MARK: - 更新の監視（原版 CAutoReloadAgent）

/// ファイルが更新されたときの動作（原版 WatchUpdate）
enum WatchUpdate {
    case query		//!< 再読込を行うかどうかダイアログボックスで問い合わせる（WU_QUERY）
    case notify		//!< 更新されたことをステータスバーで通知（WU_NOTIFY）
    case none		//!< 更新監視を行わない（WU_NONE）
    case autoload	//!< 更新され未編集の場合に再ロード（WU_AUTOLOAD）
}

/// 「ファイルが更新されました」の答え（原版 EFileUpdateQuery）
enum FileUpdateQuery {
    case reload			//!< 再読込(R)
    case close			//!< 閉じる(C)
    case notifyOnly		//!< 以後通知メッセージのみ(M)
    case noSupervision	//!< 以後更新を監視しない(N)
    case autoload		//!< 以後未編集で再読込(L)
}

/// 文書ごとの自動保存・更新の監視（原版 CAutoSaveAgent・CAutoReloadAgent と CEditWnd::OnEditTimer）
final class FileSafetyAgent: NSObject {
    /// 時刻（秒。单元测试换える）
    static var clock: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    /// 文書の窓口がアクティブか（原版 ::GetActiveWindow() == 編集窓口。单元测试换える）
    static var isActiveWindow: (NSWindow?) -> Bool = { window in
        NSApp.isActive && window?.isKeyWindow == true
    }
    /// 「ファイルが更新されました」の問い合わせ（原版 CDlgFileUpdateQuery::DoModal。单元测试换える）
    static var queryFileUpdate: (_ path: String, _ modified: Bool, _ window: NSWindow?) -> FileUpdateQuery = { path, modified, window in
        FileUpdateQueryDialog(path: path, modified: modified)?.runModal(parent: window) ?? .close
    }
    /// 自動保存の保存（原版 CDocFileOperation::FileSave：上書き保存。单元测试换える）。終わったら completion
    static var performAutoSave: (_ document: SakuraDocument, _ completion: @escaping () -> Void) -> Void = { document, completion in
        document.saveForAutoSave(completion)
    }

    private weak var document: SakuraDocument?

    // 更新の監視
    /// 更新監視方法（原版 m_eWatchUpdate）
    var watchUpdate: WatchUpdate = .query
    /// 1 以上の間は監視しない（原版 m_nPauseCount）
    private(set) var pauseCount = 0
    /// 未編集で再ロード時の遅延カウンタ（原版 m_nDelayCount）
    var delayCount = 0
    /// 開いた・保存したときのファイルの更新日時（原版 CDocFile::m_sFileInfo.cFileTime）
    var fileTime: Date?

    // 自動保存
    /// 自動保存のタイマー（原版 m_cPassiveTimer）
    var autoSaveTimer = PassiveTimer(now: { FileSafetyAgent.clock() })

    /// 500 ms ごとの呼び出しの数（原版 CEditWnd::m_nTimerCount）
    private(set) var timerCount = 0
    private var timer: Timer?
    private var settingsObserver: NSObjectProtocol?

    init(document: SakuraDocument) {
        self.document = document
        super.init()
    }

    deinit {
        stop()
    }

    /// タイマーを始める（窓口を作ったとき）
    func start() {
        reloadAutoSaveParam()
        if settingsObserver == nil {
            settingsObserver = NotificationCenter.default.addObserver(forName: EditorTextView.commonSettingsDidChangeNotification,
                                                                      object: nil, queue: .main) { [weak self] _ in
                self?.reloadAutoSaveParam()
            }
        }
        guard timer == nil else { return }
        // 原版 IDT_EDIT（500 ms）。モーダルの間は動かない（.default のみ）
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.onEditTimer() }
        RunLoop.main.add(timer, forMode: .default)
        self.timer = timer
    }

    /// タイマーを止める（閉じたとき）
    func stop() {
        timer?.invalidate()
        timer = nil
        if let settingsObserver { NotificationCenter.default.removeObserver(settingsObserver) }
        settingsObserver = nil
    }

    /// 500 ms ごと（原版 CEditWnd::OnEditTimer：6 回に 1 回、マウスのキャプチャがないときファイルの更新を調べる。毎回自動保存を調べる）
    func onEditTimer() {
        timerCount += 1
        if timerCount >= 6 { timerCount = 0 }	// 原版 IncrementTimerCount(6)
        if timerCount == 0 && NSEvent.pressedMouseButtons == 0 {
            checkFileTimeStamp()
        }
        checkAutoSave()
    }

    // MARK: 自動保存（原版 CAutoSaveAgent）

    /// 設定変更を自動保存動作に反映する（原版 ReloadAutoSaveParam）
    func reloadAutoSaveParam() {
        autoSaveTimer.setInterval(minutes: GrepDialogController.commonInt("bBackUpType2_Opt3"))
        autoSaveTimer.enable(GrepDialogController.commonInt("bBackUpType2_Opt1") & 64 != 0)	// BKUP_AUTO
    }

    /// 原版 CheckAutoSave：間隔が経ったら、変更があってファイル名があれば上書き保存
    func checkAutoSave() {
        guard let document else { return }
        // シート・モーダルの対話框の間は保存しない（閉じた後で保存する）
        let window = document.windowControllers.first?.window
        if window?.attachedSheet != nil || NSApp.modalWindow != nil { return }
        guard autoSaveTimer.checkAction() else { return }
        guard document.editor.isModified else { return }	// ここでは，「無変更でも保存」は無視する
        guard document.fileURL != nil else { return }		// まだファイル名が設定されていなければ保存しない
        let enabled = autoSaveTimer.isEnabled
        autoSaveTimer.enable(false)	// 2重呼び出しを防ぐため
        Self.performAutoSave(document) { [weak self] in
            self?.autoSaveTimer.enable(enabled)
        }
    }

    // MARK: 更新の監視（原版 CAutoReloadAgent）

    /// 監視の一時停止（原版 PauseWatching）
    func pauseWatching() {
        pauseCount += 1
    }

    /// 監視の再開（原版 ResumeWatching）
    func resumeWatching() {
        pauseCount = max(0, pauseCount - 1)
    }

    var isPausing: Bool { pauseCount >= 1 }

    /// 今のファイルの更新日時を覚える（開いた・開き直した・保存したとき）
    func storeFileTime(_ url: URL?) {
        fileTime = url.flatMap { SakuraDocument.modificationDate($0.path) }
    }

    /// 調べるか（原版 _ToDoChecking）。原版の「排他制御」（nFileShareMode）は見ない：Mac 版はファイルをロックしない
    func toDoChecking() -> Bool {
        guard let document, !isPausing else { return false }
        guard GrepDialogController.commonBool("bCheckFileTimeStamp") else { return false }	// 更新の監視設定
        guard watchUpdate != .none else { return false }
        guard Self.isActiveWindow(document.windowControllers.first?.window) else { return false }	// アクティブ？
        guard document.fileURL != nil else { return false }
        return fileTime != nil	// 現在編集中のファイルのタイムスタンプ
    }

    /// ファイルのタイムスタンプのチェック処理（原版 CheckFileTimeStamp）
    func checkFileTimeStamp() {
        // 未編集で再ロード時の遅延
        if watchUpdate == .autoload {
            delayCount += 1
            if delayCount < GrepDialogController.commonInt("nAutoloadDelay") { return }
            delayCount = 0
        }
        guard toDoChecking(), let document, let url = document.fileURL else { return }
        // 古い日時に変わったときも更新とする（原版 CompareFileTime != 0）
        guard let newTime = SakuraDocument.modificationDate(url.path), newTime != fileTime else { return }
        fileTime = newTime	// タイムスタンプ更新
        document.fileModificationDate = newTime
        let view = document.editorWindowController?.textView

        switch watchUpdate {
        case .notify:
            // ファイル更新のお知らせ -> ステータスバー
            view?.sendStatusMessage(Self.notifyMessage(newTime))
        case .autoload where !document.editor.isModified:
            pauseWatching()
            document.reopen(encoding: document.editor.encoding, confirm: false)	// 同一ファイルの再オープン
            watchUpdate = .autoload
            resumeWatching()
        default:
            pauseWatching()
            let result = Self.queryFileUpdate(url.path, document.editor.isModified, document.windowControllers.first?.window)
            switch result {
            case .reload:
                document.reopen(encoding: document.editor.encoding, confirm: false)
                watchUpdate = .query
            case .notifyOnly:
                watchUpdate = .notify
            case .noSupervision:
                watchUpdate = .none
            case .autoload:
                document.reopen(encoding: document.editor.encoding, confirm: false)
                watchUpdate = .autoload
                delayCount = 0
            case .close:
                watchUpdate = .query
            }
            resumeWatching()
        }
    }

    /// 「★ファイル更新 %02d:%02d:%02d」（原版 STR_AUTORELOAD_NOFITY。ファイルの更新時刻、現地時刻）
    static func notifyMessage(_ time: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute, .second], from: time)
        return String(format: NSLocalizedString("★ファイル更新 %02d:%02d:%02d", comment: "STR_AUTORELOAD_NOFITY"),
                      c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }

    // MARK: 保存の前後（原版 CAutoReloadAgent::OnBeforeSave・OnAfterSave）

    /// 保存が完了するまではファイル更新の通知を抑制する
    func beforeSave() {
        pauseWatching()
    }

    /// 通知を元に戻す。名前を付けて保存で対象ファイルが変わったときは更新監視方法をデフォルトに戻す
    func afterSave(succeeded: Bool, overwrite: Bool, url: URL) {
        resumeWatching()
        guard succeeded else { return }
        storeFileTime(url)
        if !overwrite { watchUpdate = .query }
    }
}

extension SakuraDocument {
    /// 自動保存の上書き保存（「上書き保存」と同じ：NSDocument の保存。保存前の確認・バックアップも同じ）
    func saveForAutoSave(_ completion: @escaping () -> Void) {
        autoSaveCompletions.append(completion)
        save(withDelegate: self, didSave: #selector(document(_:didAutoSave:contextInfo:)), contextInfo: nil)
    }

    @objc private func document(_ document: NSDocument, didAutoSave didSave: Bool, contextInfo: UnsafeMutableRawPointer?) {
        let completions = autoSaveCompletions
        autoSaveCompletions = []
        completions.forEach { $0() }
    }
}

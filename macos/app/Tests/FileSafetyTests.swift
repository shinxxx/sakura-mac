// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge
import XCTest

/// ファイルの安全機能（第 46 步）的测试：保存时的备份、自动保存、文件更新的监视。
///
/// 对话框都换成测试用的（SakuraDocument.backupHandler、FileSafetyAgent.queryFileUpdate），
/// 时钟（FileSafetyAgent.clock）、窗口是否活动（isActiveWindow）也换掉，不等真的时间。
/// 文档的 500 ms 计时器停掉，测试直接调用 checkAutoSave・checkFileTimeStamp・onEditTimer。
/// 备份文件名的各种书式由核心库的测试（test-mac-backup.cpp）逐项确认，这里确认保存的流程。
final class FileSafetyTests: XCTestCase {
    private var workDir: URL!
    private var documents: [SakuraDocument] = []
    private var savedSettings: [String: String?] = [:]
    private var savedHandler: (() -> BackupHandler)!
    private var savedClock: (() -> TimeInterval)!
    private var savedActive: ((NSWindow?) -> Bool)!
    private var savedQuery: ((String, Bool, NSWindow?) -> FileUpdateQuery)!
    private var savedAutoSave: ((SakuraDocument, @escaping () -> Void) -> Void)!
    private var savedChoose: ((String, String, NSWindow?) -> URL?)!
    private var now: TimeInterval = 1000
    private var queries: [(path: String, modified: Bool)] = []
    private var answer: FileUpdateQuery = .close

    /// 確認の答えと呼ばれた記録
    final class FakeBackupHandler: NSObject, BackupHandler {
        var answers: [BackupAnswer] = []
        var confirms: [(title: String, message: String, withCancel: Bool)] = []
        var errors: [String] = []
        var trashed: [String] = []
        func confirm(title: String, message: String, withCancel: Bool) -> BackupAnswer {
            confirms.append((title, message, withCancel))
            return answers.isEmpty ? .yes : answers.removeFirst()
        }
        func showError(title: String, message: String) { errors.append(title + ":" + message) }
        func moveToTrash(_ path: String) -> Bool {
            trashed.append(path)
            return (try? FileManager.default.removeItem(atPath: path)) != nil
        }
    }

    private var handler = FakeBackupHandler()

    override func setUpWithError() throws {
        _ = TestCore.home
        _ = NSApplication.shared
        workDir = TestCore.home.appendingPathComponent("filesafety-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        savedHandler = SakuraDocument.backupHandler
        savedClock = FileSafetyAgent.clock
        savedActive = FileSafetyAgent.isActiveWindow
        savedQuery = FileSafetyAgent.queryFileUpdate
        savedAutoSave = FileSafetyAgent.performAutoSave
        savedChoose = FolderAccess.choose
        handler = FakeBackupHandler()
        SakuraDocument.backupHandler = { [unowned self] in self.handler }
        FileSafetyAgent.clock = { [unowned self] in self.now }
        FileSafetyAgent.isActiveWindow = { _ in true }
        FileSafetyAgent.queryFileUpdate = { [unowned self] path, modified, _ in
            self.queries.append((path, modified))
            return self.answer
        }
        // 沙盒外（单元测试）：フォルダーは読めるので許可の対話框は出ない
        FolderAccess.choose = { path, _, _ in
            XCTFail("フォルダーの許可を求めた：\(path)")
            return nil
        }
        // 既定：バックアップなし、更新の監視あり、遅延なし、自動保存なし
        set(["bBackUp": "0", "bBackUpDialog": "0", "bBackUpDustBox": "0", "bBackUpFolder": "0", "bBackUpPathAdvanced": "0",
             "nBackUpType": "1", "bBackUpType2_Opt1": "0", "bBackUpType2_Opt3": "5",
             "bCheckFileTimeStamp": "1", "nAutoloadDelay": "0"])
    }

    override func tearDown() {
        SakuraDocument.backupHandler = savedHandler
        FileSafetyAgent.clock = savedClock
        FileSafetyAgent.isActiveWindow = savedActive
        FileSafetyAgent.queryFileUpdate = savedQuery
        FileSafetyAgent.performAutoSave = savedAutoSave
        FolderAccess.choose = savedChoose
        for (key, value) in savedSettings {
            _ = EditorCore.setCommonSetting(value ?? "0", section: "Common", key: key)
        }
        savedSettings = [:]
        for document in documents {
            document.fileSafety.stop()
            for controller in document.windowControllers {
                controller.window?.orderOut(nil)
                document.removeWindowController(controller)
            }
        }
        documents = []
        try? FileManager.default.removeItem(at: workDir)
    }

    // MARK: - 補助

    private func set(_ values: [String: String]) {
        for (key, value) in values {
            if savedSettings[key] == nil { savedSettings[key] = .some(EditorCore.commonSetting(section: "Common", key: key)) }
            XCTAssertTrue(EditorCore.setCommonSetting(value, section: "Common", key: key), key)
        }
    }

    private func write(_ name: String, _ text: String, date: Date? = nil) throws -> URL {
        let url = workDir.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        if let date { try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path) }
        return url
    }

    /// 外部のアプリが書き換えた（更新日時は確実に変える）
    private func modifyExternally(_ url: URL, _ text: String, secondsLater: TimeInterval = 10) throws {
        let old = SakuraDocument.modificationDate(url.path) ?? Date()
        try Data(text.utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: old.addingTimeInterval(secondsLater)], ofItemAtPath: url.path)
    }

    private func open(_ url: URL) throws -> SakuraDocument {
        let document = try SakuraDocument(contentsOf: url, ofType: "public.plain-text")
        document.makeWindowControllers()
        document.fileSafety.stop()	// 500 ms のタイマーは止めて、テストから直接呼ぶ
        documents.append(document)
        return document
    }

    private func view(_ document: SakuraDocument) throws -> EditorTextView {
        try XCTUnwrap(document.editorWindowController?.textView)
    }

    private func type(_ document: SakuraDocument, _ text: String) throws {
        try view(document).insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    private func read(_ url: URL) -> String? {
        (try? Data(contentsOf: url)).flatMap { String(data: $0, encoding: .utf8) }
    }

    /// NSDocument の保存（上書き保存・名前を付けて保存の対話框の後と同じ経路）。エラーを返す
    @discardableResult
    private func save(_ document: SakuraDocument, to url: URL? = nil, _ operation: NSDocument.SaveOperationType = .saveOperation) throws -> Error? {
        let target = try XCTUnwrap(url ?? document.fileURL)
        let done = expectation(description: "save")
        var result: Error?
        document.save(to: target, ofType: "public.plain-text", for: operation) { error in
            result = error
            done.fulfill()
        }
        wait(for: [done], timeout: 10)
        return result
    }

    private func text(_ document: SakuraDocument) -> String {
        document.editor.text
    }

    // MARK: - 保存時のバックアップ（原版 CBackupAgent::OnPreBeforeSave）

    /// .bak：保存の前のファイルの内容がバックアップになる。設定が off なら作らない
    func testBackupBakOnSave() throws {
        let url = try write("memo.txt", "old\n")
        let document = try open(url)
        try type(document, "new ")
        XCTAssertNil(try save(document))
        XCTAssertFalse(FileManager.default.fileExists(atPath: workDir.appendingPathComponent("memo.bak").path), "設定が off")
        set(["bBackUp": "1"])
        try type(document, "again ")
        XCTAssertNil(try save(document))
        XCTAssertEqual(read(workDir.appendingPathComponent("memo.bak")), "new old\n", "保存の前の内容")
        XCTAssertEqual(read(url), "new again old\n")
        XCTAssertTrue(handler.confirms.isEmpty, "確認なし")
    }

    /// 各種類のファイル名：元の拡張子を保存、連番、保存時の日付・時刻、指定フォルダー（相対パスはファイルのフォルダーから）
    func testBackupTypesOnSave() throws {
        set(["bBackUp": "1"])
        let url = try write("memo.txt", "0")
        let document = try open(url)
        set(["nBackUpType": "5"])
        try type(document, "1")
        XCTAssertNil(try save(document))
        XCTAssertEqual(read(workDir.appendingPathComponent("memo.txt.bak")), "0")
        set(["nBackUpType": "3", "bBackUpType2_Opt2": String((Int(Character("b").asciiValue!) << 16) | 3)])
        try type(document, "2")
        XCTAssertNil(try save(document))
        try type(document, "3")
        XCTAssertNil(try save(document))
        XCTAssertEqual(read(workDir.appendingPathComponent("memo.b00")), "120", "連番：.b00 が最新")
        XCTAssertEqual(read(workDir.appendingPathComponent("memo.b01")), "10")
        set(["nBackUpType": "2", "bBackUpType2_Opt1": "56"])	// 年月日
        try type(document, "4")
        XCTAssertNil(try save(document))
        let day = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        let name = String(format: "memo_%04d%02d%02d.txt", day.year!, day.month!, day.day!)
        XCTAssertEqual(read(workDir.appendingPathComponent(name)), "1230", name)
        set(["nBackUpType": "1", "bBackUpType2_Opt1": "0", "bBackUpFolder": "1", "szBackUpFolder": "bk"])
        try type(document, "5")
        XCTAssertNil(try save(document))
        XCTAssertEqual(read(workDir.appendingPathComponent("bk/memo.bak")), "12340", "指定フォルダー（一段だけ作る）")
        XCTAssertEqual(read(url), "123450")
    }

    /// 作成前に確認する：はい → 作る、いいえ → 作らずに保存、キャンセル → 保存しない（NSDocument には userCancelled）
    func testBackupConfirmAnswers() throws {
        set(["bBackUp": "1", "bBackUpDialog": "1"])
        let url = try write("memo.txt", "A")
        let document = try open(url)
        let bak = workDir.appendingPathComponent("memo.bak")

        handler.answers = [.no]
        try type(document, "1")
        XCTAssertNil(try save(document))
        XCTAssertFalse(FileManager.default.fileExists(atPath: bak.path), "いいえ：作らない")
        XCTAssertEqual(read(url), "1A", "いいえ：保存は続ける")
        XCTAssertEqual(handler.confirms.count, 1)
        XCTAssertEqual(handler.confirms.first?.withCancel, true, "はい・いいえ・キャンセル")
        XCTAssertEqual(handler.confirms.first?.title, "バックアップ作成の確認")
        XCTAssertTrue(handler.confirms.first?.message.contains(url.path) == true, handler.confirms.first?.message ?? "")
        XCTAssertTrue(handler.confirms.first?.message.contains(bak.path) == true)

        handler.answers = [.yes]
        try type(document, "2")
        XCTAssertNil(try save(document))
        XCTAssertEqual(read(bak), "1A", "はい：作る")
        XCTAssertEqual(read(url), "12A")

        handler.answers = [.cancel]
        try type(document, "3")
        let error = try save(document)
        XCTAssertEqual((error as? CocoaError)?.code, .userCancelled, "キャンセル：保存を中止")
        XCTAssertEqual(read(url), "12A", "キャンセル：ファイルは変わらない")
        XCTAssertEqual(read(bak), "1A")
        XCTAssertTrue(document.editor.isModified, "変更は残る")
    }

    /// ごみ箱に放り込む：作ったバックアップをごみ箱へ（確認ははい・いいえの 2 つ）
    func testBackupDustBox() throws {
        set(["bBackUp": "1", "bBackUpDustBox": "1", "bBackUpDialog": "1"])
        let url = try write("memo.txt", "A")
        let document = try open(url)
        try type(document, "1")
        XCTAssertNil(try save(document))
        let bak = workDir.appendingPathComponent("memo.bak")
        XCTAssertEqual(handler.confirms.first?.withCancel, false, "はい・いいえ")
        XCTAssertEqual(handler.trashed, [bak.path])
        XCTAssertFalse(FileManager.default.fileExists(atPath: bak.path), "ごみ箱へ移った")
        XCTAssertEqual(read(url), "1A")
    }

    /// 作れないとき（フォルダーが二段ない）：「バックアップの作成に失敗しました」の確認。いいえで保存しない
    func testBackupFailureAsksToContinue() throws {
        set(["bBackUp": "1", "bBackUpFolder": "1", "szBackUpFolder": "no/such"])
        let url = try write("memo.txt", "A")
        let document = try open(url)
        try type(document, "1")
        handler.answers = [.no]
        let error = try save(document)
        XCTAssertEqual((error as? CocoaError)?.code, .userCancelled)
        XCTAssertEqual(handler.confirms.count, 1)
        XCTAssertTrue(handler.confirms.first?.message.contains("バックアップの作成に失敗しました") == true, handler.confirms.first?.message ?? "")
        XCTAssertEqual(read(url), "A")
        handler.answers = [.yes]
        XCTAssertNil(try save(document))
        XCTAssertEqual(read(url), "1A", "はい：上書きを続ける")
    }

    /// 名前を付けて保存で別の既存のファイルに保存：そのファイルのバックアップ（原版 pSaveInfo->cFilePath）。新しいファイルには作らない
    func testBackupOnSaveAsToExistingFile() throws {
        set(["bBackUp": "1"])
        let url = try write("a.txt", "A")
        let other = try write("b.txt", "B")
        let document = try open(url)
        XCTAssertNil(try save(document, to: other, .saveAsOperation))
        XCTAssertEqual(read(workDir.appendingPathComponent("b.bak")), "B")
        XCTAssertFalse(FileManager.default.fileExists(atPath: workDir.appendingPathComponent("a.bak").path))
        XCTAssertNil(try save(document, to: workDir.appendingPathComponent("c.txt"), .saveAsOperation))
        XCTAssertFalse(FileManager.default.fileExists(atPath: workDir.appendingPathComponent("c.bak").path), "新しいファイル")
    }

    // MARK: - NSDocument の「ほかのアプリケーションで変更されました」

    /// 外部で変わった後の上書き保存：NSDocument の確認を出さずに保存する（原版は保存のときに確かめない）
    func testNoDocumentAlertAfterExternalChange() throws {
        set(["bCheckFileTimeStamp": "0"])
        let url = try write("memo.txt", "A")
        let document = try open(url)
        try modifyExternally(url, "outside")
        try type(document, "1")
        let done = expectation(description: "save")
        FileSafetyAgent.performAutoSave(document) { done.fulfill() }	// save(withDelegate:)：「上書き保存」と同じ経路
        wait(for: [done], timeout: 10)
        XCTAssertEqual(read(url), "1A")
        XCTAssertNil(document.windowControllers.first?.window?.attachedSheet)
        XCTAssertFalse(document.editor.isModified)
        // 他のアプリがファイルを変えても NSDocument は読み直さない
        try modifyExternally(url, "outside again")
        document.presentedItemDidChange()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(text(document), "1A")
    }

    // MARK: - 自動保存（原版 CAutoSaveAgent）

    /// 間隔が経ったら、変更があってファイル名があるときだけ上書き保存。保存中は止める
    func testAutoSaveAfterInterval() throws {
        var saves: [SakuraDocument] = []
        var completions: [() -> Void] = []
        FileSafetyAgent.performAutoSave = { document, completion in
            saves.append(document)
            completions.append(completion)
        }
        set(["bBackUpType2_Opt1": "64", "bBackUpType2_Opt3": "2"])
        let url = try write("memo.txt", "A")
        let document = try open(url)
        let agent = document.fileSafety
        agent.reloadAutoSaveParam()
        XCTAssertTrue(agent.autoSaveTimer.isEnabled)
        XCTAssertEqual(agent.autoSaveTimer.interval, 120)
        // 変更なし：時間が経っても保存しない（ここでは「無変更でも保存」は無視）
        now += 120
        agent.checkAutoSave()
        XCTAssertTrue(saves.isEmpty)
        try type(document, "x")
        now += 119
        agent.checkAutoSave()
        XCTAssertTrue(saves.isEmpty, "まだ 2 分経っていない（さっきリセットされた）")
        now += 1
        agent.checkAutoSave()
        XCTAssertEqual(saves.count, 1)
        XCTAssertFalse(agent.autoSaveTimer.isEnabled, "保存中は止める（2 重呼び出しを防ぐ）")
        now += 1000
        agent.checkAutoSave()
        XCTAssertEqual(saves.count, 1)
        completions.removeFirst()()
        XCTAssertTrue(agent.autoSaveTimer.isEnabled, "保存の後で戻す（リセットされる）")
        now += 119
        agent.checkAutoSave()
        XCTAssertEqual(saves.count, 1)
        now += 1
        agent.checkAutoSave()
        XCTAssertEqual(saves.count, 2)
    }

    /// 無題は保存しない。無効のときは保存しない。無効 → 有効で測り始めをリセット。間隔は 1～35791 分
    func testAutoSaveEnableAndUntitled() throws {
        var count = 0
        FileSafetyAgent.performAutoSave = { _, completion in
            count += 1
            completion()
        }
        let untitled = SakuraDocument()
        untitled.makeWindowControllers()
        untitled.fileSafety.stop()
        documents.append(untitled)
        set(["bBackUpType2_Opt1": "64", "bBackUpType2_Opt3": "1"])
        untitled.fileSafety.reloadAutoSaveParam()
        try type(untitled, "x")
        now += 60
        untitled.fileSafety.checkAutoSave()
        XCTAssertEqual(count, 0, "まだファイル名がない")

        let document = try open(try write("memo.txt", "A"))
        let agent = document.fileSafety
        try type(document, "x")
        set(["bBackUpType2_Opt1": "0"])
        agent.reloadAutoSaveParam()
        now += 100
        agent.checkAutoSave()
        XCTAssertEqual(count, 0, "無効")
        set(["bBackUpType2_Opt1": "64"])
        agent.reloadAutoSaveParam()	// 無効 → 有効：今から測る
        now += 59
        agent.checkAutoSave()
        XCTAssertEqual(count, 0)
        now += 1
        agent.checkAutoSave()
        XCTAssertEqual(count, 1)
        // 共通設定の変更の通知で設定を読み直す
        set(["bBackUpType2_Opt3": "0"])
        agent.start()
        defer { agent.stop() }
        NotificationCenter.default.post(name: EditorTextView.commonSettingsDidChangeNotification, object: nil)
        XCTAssertEqual(agent.autoSaveTimer.interval, 60, "0 分は 1 分")
        set(["bBackUpType2_Opt3": "99999"])
        NotificationCenter.default.post(name: EditorTextView.commonSettingsDidChangeNotification, object: nil)
        XCTAssertEqual(agent.autoSaveTimer.interval, 35791 * 60)
    }

    /// 本当の自動保存：「上書き保存」と同じ（バックアップも作る）
    func testAutoSaveWritesFileWithBackup() throws {
        set(["bBackUpType2_Opt1": "64", "bBackUpType2_Opt3": "1", "bBackUp": "1"])
        let url = try write("memo.txt", "A")
        let document = try open(url)
        document.fileSafety.reloadAutoSaveParam()
        try type(document, "1")
        now += 60
        document.fileSafety.checkAutoSave()
        XCTAssertTrue(waitFor { self.read(url) == "1A" && document.fileSafety.autoSaveTimer.isEnabled }, read(url) ?? "")
        XCTAssertEqual(read(workDir.appendingPathComponent("memo.bak")), "A")
        XCTAssertFalse(document.editor.isModified)
    }

    // MARK: - 更新の監視（原版 CAutoReloadAgent）

    /// 問い合わせの答えごとの動作（原版 CheckFileTimeStamp の switch）
    func testWatchQueryAnswers() throws {
        let url = try write("memo.txt", "A")
        let document = try open(url)
        let agent = document.fileSafety
        XCTAssertEqual(agent.watchUpdate, .query)
        agent.checkFileTimeStamp()
        XCTAssertTrue(queries.isEmpty, "変わっていない")

        // 閉じる：読み直さない、問い合わせのまま。もう一度は聞かない（日時を覚えた）
        answer = .close
        try modifyExternally(url, "B")
        agent.checkFileTimeStamp()
        XCTAssertEqual(queries.count, 1)
        XCTAssertEqual(queries.last?.path, url.path)
        XCTAssertEqual(queries.last?.modified, false)
        XCTAssertEqual(text(document), "A")
        XCTAssertEqual(agent.watchUpdate, .query)
        XCTAssertEqual(document.fileModificationDate, SakuraDocument.modificationDate(url.path), "NSDocument の日時も")
        agent.checkFileTimeStamp()
        XCTAssertEqual(queries.count, 1)

        // 再読込：読み直す。変更があるときは問い合わせに「変更あり」
        try type(document, "edit")
        answer = .reload
        try modifyExternally(url, "C")
        agent.checkFileTimeStamp()
        XCTAssertEqual(queries.last?.modified, true)
        XCTAssertEqual(text(document), "C")
        XCTAssertFalse(document.editor.isModified)
        XCTAssertEqual(agent.watchUpdate, .query)

        // 古い日時に変わったときも更新（原版 CompareFileTime != 0）
        try modifyExternally(url, "D", secondsLater: -3600)
        agent.checkFileTimeStamp()
        XCTAssertEqual(queries.count, 3)
        XCTAssertEqual(text(document), "D")

        // 以後通知メッセージのみ：読み直さない。次はステータスメッセージだけ
        answer = .notifyOnly
        try modifyExternally(url, "E")
        agent.checkFileTimeStamp()
        XCTAssertEqual(agent.watchUpdate, .notify)
        XCTAssertEqual(text(document), "D")
        try modifyExternally(url, "F")
        agent.checkFileTimeStamp()
        XCTAssertEqual(queries.count, 4, "もう聞かない")
        let time = try XCTUnwrap(SakuraDocument.modificationDate(url.path))
        XCTAssertEqual(try view(document).statusMessage.trimmingCharacters(in: .whitespaces), FileSafetyAgent.notifyMessage(time))
        XCTAssertEqual(text(document), "D")
    }

    /// 以後更新を監視しない：その後は何もしない。開き直すと問い合わせに戻る（原版 CEditDoc::InitDoc）
    func testWatchNoSupervision() throws {
        let url = try write("memo.txt", "A")
        let document = try open(url)
        let agent = document.fileSafety
        answer = .noSupervision
        try modifyExternally(url, "B")
        agent.checkFileTimeStamp()
        XCTAssertEqual(agent.watchUpdate, .none)
        try modifyExternally(url, "C")
        agent.checkFileTimeStamp()
        XCTAssertEqual(queries.count, 1)
        XCTAssertEqual(text(document), "A")
        document.reopen(encoding: document.editor.encoding, confirm: false)
        XCTAssertEqual(agent.watchUpdate, .query)
        XCTAssertEqual(text(document), "C")
    }

    /// 以後未編集で再読込：読み直して、次からは未編集なら聞かずに読み直す。編集中なら聞く。遅延（nAutoloadDelay）
    func testWatchAutoload() throws {
        let url = try write("memo.txt", "A")
        let document = try open(url)
        let agent = document.fileSafety
        answer = .autoload
        try modifyExternally(url, "B")
        agent.checkFileTimeStamp()
        XCTAssertEqual(text(document), "B")
        XCTAssertEqual(agent.watchUpdate, .autoload)
        XCTAssertEqual(agent.delayCount, 0)

        try modifyExternally(url, "C")
        agent.checkFileTimeStamp()
        XCTAssertEqual(queries.count, 1, "未編集：聞かない")
        XCTAssertEqual(text(document), "C")
        XCTAssertEqual(agent.watchUpdate, .autoload)

        // 遅延 2：2 回目の確認で読み直す
        set(["nAutoloadDelay": "2"])
        try modifyExternally(url, "D")
        agent.checkFileTimeStamp()
        XCTAssertEqual(text(document), "C", "1 回目は待つ")
        XCTAssertEqual(agent.delayCount, 1)
        agent.checkFileTimeStamp()
        XCTAssertEqual(text(document), "D")
        XCTAssertEqual(agent.delayCount, 0)
        set(["nAutoloadDelay": "0"])

        // 編集中：問い合わせ（閉じる → 問い合わせに戻る）
        try type(document, "x")
        answer = .close
        try modifyExternally(url, "E")
        agent.checkFileTimeStamp()
        XCTAssertEqual(queries.count, 2)
        XCTAssertEqual(queries.last?.modified, true)
        XCTAssertEqual(agent.watchUpdate, .query)
        XCTAssertEqual(text(document), "xD")
    }

    /// 窓口がアクティブでないとき、設定が off のとき、無題のときは調べない
    func testWatchConditions() throws {
        let url = try write("memo.txt", "A")
        let document = try open(url)
        let agent = document.fileSafety
        try modifyExternally(url, "B")
        FileSafetyAgent.isActiveWindow = { _ in false }
        agent.checkFileTimeStamp()
        XCTAssertTrue(queries.isEmpty, "アクティブでない")
        FileSafetyAgent.isActiveWindow = { _ in true }
        set(["bCheckFileTimeStamp": "0"])
        agent.checkFileTimeStamp()
        XCTAssertTrue(queries.isEmpty, "更新の監視が off")
        set(["bCheckFileTimeStamp": "1"])
        agent.checkFileTimeStamp()
        XCTAssertEqual(queries.count, 1, "条件がそろえば聞く")
        // 本当の判定：表示していない窓口はアクティブでない
        FileSafetyAgent.isActiveWindow = savedActive
        XCTAssertFalse(FileSafetyAgent.isActiveWindow(document.windowControllers.first?.window))
        XCTAssertFalse(FileSafetyAgent.isActiveWindow(nil))

        let untitled = SakuraDocument()
        untitled.makeWindowControllers()
        untitled.fileSafety.stop()
        documents.append(untitled)
        FileSafetyAgent.isActiveWindow = { _ in true }
        XCTAssertFalse(untitled.fileSafety.toDoChecking(), "無題")
    }

    /// 保存中は監視しない。自分の保存の後は聞かない。名前を付けて保存すると問い合わせに戻る
    func testWatchPauseDuringSave() throws {
        let url = try write("memo.txt", "A")
        let document = try open(url)
        let agent = document.fileSafety
        agent.beforeSave()
        XCTAssertTrue(agent.isPausing)
        try modifyExternally(url, "B")
        agent.checkFileTimeStamp()
        XCTAssertTrue(queries.isEmpty, "保存中")
        agent.afterSave(succeeded: false, overwrite: true, url: url)
        XCTAssertFalse(agent.isPausing)

        // 保存中に監視が止まっていることを本当の保存で確かめる（保存前の自動実行の代わりにバックアップの確認の中で調べる）
        set(["bBackUp": "1", "bBackUpDialog": "1"])
        var pausedDuringSave = false
        final class Probe: NSObject, BackupHandler {
            var check: () -> Void = {}
            func confirm(title: String, message: String, withCancel: Bool) -> BackupAnswer { check(); return .no }
            func showError(title: String, message: String) {}
            func moveToTrash(_ path: String) -> Bool { false }
        }
        let probe = Probe()
        SakuraDocument.backupHandler = { probe }
        probe.check = { pausedDuringSave = agent.isPausing }
        try type(document, "1")
        XCTAssertNil(try save(document))
        XCTAssertFalse(pausedDuringSave, "バックアップは OnBeforeSave より前（原版 NotifyPreBeforeSave）")
        XCTAssertFalse(agent.isPausing)
        // 自分の保存で日時は覚え直す：聞かない（外部の変更 B は保存で上書きされた）
        agent.checkFileTimeStamp()
        XCTAssertTrue(queries.isEmpty)
        XCTAssertEqual(read(url), "1A")

        set(["bBackUp": "0", "bBackUpDialog": "0"])
        answer = .notifyOnly
        try modifyExternally(url, "C")
        agent.checkFileTimeStamp()
        XCTAssertEqual(agent.watchUpdate, .notify)
        XCTAssertNil(try save(document, to: workDir.appendingPathComponent("other.txt"), .saveAsOperation))
        XCTAssertEqual(agent.watchUpdate, .query, "名前を付けて保存：既定に戻す")
        XCTAssertNil(try save(document))
        XCTAssertEqual(agent.watchUpdate, .query)
    }

    /// 500 ms ごとの呼び出しの 6 回に 1 回だけファイルを調べる（原版 IncrementTimerCount(6)：3 秒ごと）
    func testEditTimerChecksEverySixth() throws {
        let url = try write("memo.txt", "A")
        let document = try open(url)
        let agent = document.fileSafety
        try modifyExternally(url, "B")
        for _ in 0..<5 { agent.onEditTimer() }
        XCTAssertTrue(queries.isEmpty)
        agent.onEditTimer()
        XCTAssertEqual(queries.count, 1)
        try modifyExternally(url, "C")
        for _ in 0..<5 { agent.onEditTimer() }
        XCTAssertEqual(queries.count, 1)
        agent.onEditTimer()
        XCTAssertEqual(queries.count, 2)
    }

    /// 通知メッセージ（原版 STR_AUTORELOAD_NOFITY「★ファイル更新 %02d:%02d:%02d」：ファイルの更新時刻）
    func testNotifyMessage() throws {
        let date = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 3, minute: 4, second: 5)))
        XCTAssertEqual(FileSafetyAgent.notifyMessage(date), "★ファイル更新 03:04:05")
    }

    // MARK: - 「ファイルが更新されました」（原版 CDlgFileUpdateQuery）

    /// 原版と同じ文字・ボタン。ボタンの答え。既定のボタンは「閉じる」
    func testFileUpdateQueryDialog() throws {
        let path = "/tmp/some folder/memo.txt"
        let dialog = try XCTUnwrap(FileUpdateQueryDialog(path: path, modified: false))
        XCTAssertEqual(dialog.title, "ファイルが更新されました")
        XCTAssertEqual(dialog.page.text("IDC_UPDATEDFILENAME"), path)
        XCTAssertEqual(dialog.page.text("IDC_FILEUPDATEMSG"), "このファイルは外部のエディタ等で変更されています。")
        XCTAssertEqual(dialog.page.text("IDC_QUERYRELOADMSG"), "再ロードしますか?")
        XCTAssertEqual(try XCTUnwrap(FileUpdateQueryDialog(path: path, modified: true)).page.text("IDC_QUERYRELOADMSG"),
                       "再ロードを行うと変更が失われますがよろしいですか?")
        let titles = ["IDC_BTN_RELOAD": "再読込(R)", "IDC_BTN_CLOSE": "閉じる(C)", "IDC_BTN_AUTOLOAD": "以後未編集で再読込(L)",
                      "IDC_BTN_NOTIFYONLY": "以後通知メッセージのみ(M)", "IDC_BTN_NOSUPERVISION": "以後更新を監視しない(N)"]
        for (id, title) in titles {
            let button = try XCTUnwrap(dialog.page.control(id) as? NSButton, id)
            XCTAssertEqual(button.title, title)
            XCTAssertEqual(button.accessibilityIdentifier(), id)
            XCTAssertLessThanOrEqual(ceil(button.fittingSize.width), button.frame.width + 1, "\(id) の文字が切れない")
        }
        XCTAssertEqual((dialog.page.control("IDC_BTN_CLOSE") as? NSButton)?.keyEquivalent, "\r")
        XCTAssertFalse((dialog.page.control("IDC_UPDATEDFILENAME") as? NSTextField)?.isEditable ?? true, "読み取り専用")
        let label = try XCTUnwrap(dialog.page.control("IDC_QUERYRELOADMSG") as? NSTextField)
        XCTAssertLessThanOrEqual(ceil(label.fittingSize.width), label.frame.width + 1, "メッセージが切れない")
        let expected: [String: FileUpdateQuery] = ["IDC_BTN_RELOAD": .reload, "IDC_BTN_CLOSE": .close, "IDC_BTN_AUTOLOAD": .autoload,
                                                   "IDC_BTN_NOTIFYONLY": .notifyOnly, "IDC_BTN_NOSUPERVISION": .noSupervision]
        for (id, result) in expected {
            var closed = false
            dialog.onClose = { closed = true }
            (dialog.page.control(id) as? NSButton)?.performClick(nil)
            XCTAssertTrue(closed, id)
            XCTAssertEqual(dialog.result, result, id)
        }
        // ボタンが重ならない、ダイアログの中に収まる
        let frames = titles.keys.compactMap { dialog.page.control($0)?.frame }
        for (i, a) in frames.enumerated() {
            XCTAssertTrue(dialog.page.view.bounds.contains(a), "\(a)")
            for b in frames[(i + 1)...] { XCTAssertFalse(a.intersects(b), "\(a) \(b)") }
        }
    }

    /// 長いパス（深い容器の中のファイル）：欄を高くしてファイル名まで見える。下のコントロールも下がって重ならない
    func testFileUpdateQueryDialogLongPath() throws {
        let path = "/Users/someone/Library/Containers/com.example.some.long.bundle.identifier/Data/SakuraMacUITest/watch-0123abcd/another/deeper/folder/structure/for/testing/watched-file-name.txt"
        let short = try XCTUnwrap(FileUpdateQueryDialog(path: "/tmp/a.txt", modified: false))
        let dialog = try XCTUnwrap(FileUpdateQueryDialog(path: path, modified: false))
        let field = try XCTUnwrap(dialog.page.control("IDC_UPDATEDFILENAME") as? NSTextField)
        let cell = try XCTUnwrap(field.cell)
        let needed = cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: field.frame.width, height: .greatestFiniteMagnitude)).height
        XCTAssertLessThanOrEqual(needed, field.frame.height + 0.5, "パスが全部入る")
        XCTAssertGreaterThan(dialog.page.view.frame.height, short.page.view.frame.height, "ダイアログが高くなる")
        let ids = ["IDC_UPDATEDFILENAME", "IDC_FILEUPDATEMSG", "IDC_QUERYRELOADMSG", "IDC_BTN_RELOAD", "IDC_BTN_CLOSE", "IDC_BTN_AUTOLOAD",
                   "IDC_BTN_NOTIFYONLY", "IDC_BTN_NOSUPERVISION"]
        let frames = ids.compactMap { dialog.page.control($0)?.frame }
        XCTAssertEqual(frames.count, ids.count)
        for (i, a) in frames.enumerated() {
            XCTAssertTrue(dialog.page.view.bounds.contains(a), "\(ids[i]) \(a)")
            for (j, b) in frames.enumerated() where j > i { XCTAssertFalse(a.intersects(b), "\(ids[i]) \(ids[j])") }
        }
    }

    private func waitFor(timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        return condition()
    }
}

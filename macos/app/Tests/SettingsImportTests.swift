// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge
import XCTest

/// 設定 >「Windows 版の設定をインポート…」（计划第 35 步）的测试。
///
/// 对话框、关闭窗口、重新启动换成测试用的（SettingsImporter 的 static 钩子）。
/// 导入的内容（重新启动后与 Windows 版相同、历史留 Mac 的、旧版本的 ini 等）由核心库的测试
/// （test-mac-import.cpp）确认；这里确认 App 的步骤：选文件 → 检查 → 确认 → 关闭窗口 → 导入 → 重新启动。
final class SettingsImportTests: XCTestCase {
    private var workDir: URL!
    private var savedChooseFile: (() -> URL?)!
    private var savedConfirm: ((String, String) -> Bool)!
    private var savedShowError: ((String) -> Void)!
    private var savedCloseAll: ((@escaping (Bool) -> Void) -> Void)!
    private var savedRelaunch: (() -> Void)!

    // 各钩子被调用的记录
    private var errors: [String] = []
    private var confirmed: [(String, String)] = []
    private var closeAllCount = 0
    private var relaunchCount = 0

    override func setUpWithError() throws {
        _ = TestCore.home
        _ = NSApplication.shared
        workDir = TestCore.home.appendingPathComponent("import-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        savedChooseFile = SettingsImporter.chooseFile
        savedConfirm = SettingsImporter.confirm
        savedShowError = SettingsImporter.showError
        savedCloseAll = SettingsImporter.closeAllDocuments
        savedRelaunch = SettingsImporter.relaunch
        SettingsImporter.showError = { [unowned self] in errors.append($0) }
        SettingsImporter.confirm = { [unowned self] in confirmed.append(($0, $1)); return true }
        SettingsImporter.closeAllDocuments = { [unowned self] completion in closeAllCount += 1; completion(true) }
        SettingsImporter.relaunch = { [unowned self] in relaunchCount += 1 }
    }

    override func tearDown() {
        SettingsImporter.chooseFile = savedChooseFile
        SettingsImporter.confirm = savedConfirm
        SettingsImporter.showError = savedShowError
        SettingsImporter.closeAllDocuments = savedCloseAll
        SettingsImporter.relaunch = savedRelaunch
        try? FileManager.default.removeItem(at: workDir)
    }

    /// 选这个文件
    private func choose(_ url: URL?) {
        SettingsImporter.chooseFile = { url }
    }

    /// Windows 版的 sakura.ini：现在的设置文件，F8 换成「挿入／上書きモード切り替え」
    private func windowsIni() throws -> URL {
        // 字节单位替换（UTF-8 的 BOM 留着：没有 BOM 的 ini 按 Shift_JIS 读）
        var ini = try Data(contentsOf: URL(fileURLWithPath: EditorCore.settingsFilePath))
        if let range = ini.range(of: Data("KeyBind[018]=0077,30602,".utf8)) {
            ini.replaceSubrange(range, with: Data("KeyBind[018]=0077,31001,".utf8))
        }
        XCTAssertNotNil(ini.range(of: Data("KeyBind[018]=0077,31001,".utf8)))
        let url = workDir.appendingPathComponent("sakura.ini")
        try ini.write(to: url)
        return url
    }

    // MARK: - 菜单

    func testMenuItemInSettingsMenu() throws {
        let menu = MainMenuBuilder.build()
        let settings = try XCTUnwrap(menu.items.first { $0.title == "設定" }?.submenu)
        let item = try XCTUnwrap(settings.items.first { $0.action == #selector(SettingsImporter.importWindowsSettings(_:)) })
        XCTAssertEqual(item.title, "Windows 版の設定をインポート…")
        XCTAssertTrue(item.target === SettingsImporter.shared)
        XCTAssertTrue(SettingsImporter.shared.validateMenuItem(item))
    }

    // MARK: - 不导入的情况

    /// 选文件时取消：什么也不做
    func testCancelChoosingFile() {
        choose(nil)
        SettingsImporter().importWindowsSettings(nil)
        XCTAssertTrue(confirmed.isEmpty)
        XCTAssertEqual(closeAllCount, 0)
        XCTAssertTrue(errors.isEmpty)
    }

    /// 不是设置文件：错误的消息，不确认、不关闭窗口
    func testNotSettingsFile() throws {
        let url = workDir.appendingPathComponent("readme.txt")
        try "hello\n".write(to: url, atomically: true, encoding: .utf8)
        choose(url)
        SettingsImporter().importWindowsSettings(nil)
        XCTAssertEqual(errors.count, 1)
        XCTAssertTrue(errors.first?.contains("サクラエディタの設定ファイルではありません。") ?? false)
        XCTAssertTrue(errors.first?.contains(url.path) ?? false)
        XCTAssertTrue(confirmed.isEmpty)
        XCTAssertEqual(closeAllCount, 0)
    }

    /// 读不了的文件
    func testMissingFile() {
        choose(workDir.appendingPathComponent("missing.ini"))
        SettingsImporter().importWindowsSettings(nil)
        XCTAssertEqual(errors.count, 1)
        XCTAssertTrue(errors.first?.contains("ファイルを読み込めませんでした。") ?? false)
        XCTAssertEqual(closeAllCount, 0)
    }

    /// 确认时取消：不关闭窗口，设置不变
    func testCancelConfirmation() throws {
        let url = try windowsIni()
        choose(url)
        SettingsImporter.confirm = { [unowned self] in confirmed.append(($0, $1)); return false }
        let before = try Data(contentsOf: URL(fileURLWithPath: EditorCore.settingsFilePath))
        SettingsImporter().importWindowsSettings(nil)
        XCTAssertEqual(confirmed.count, 1)
        XCTAssertEqual(confirmed.first?.0, url.path)
        XCTAssertEqual(confirmed.first?.1, EditorCore.settingsBackupPath)
        XCTAssertEqual(closeAllCount, 0)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: EditorCore.settingsFilePath)), before)
    }

    /// 关闭窗口时取消（修改过的文件的确认里取消）：不导入，可以再执行
    func testCancelWhileClosingWindows() throws {
        choose(try windowsIni())
        SettingsImporter.closeAllDocuments = { [unowned self] completion in closeAllCount += 1; completion(false) }
        let importer = SettingsImporter()
        let before = try Data(contentsOf: URL(fileURLWithPath: EditorCore.settingsFilePath))
        importer.importWindowsSettings(nil)
        XCTAssertEqual(closeAllCount, 1)
        XCTAssertFalse(importer.isImporting)
        XCTAssertEqual(relaunchCount, 0)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: EditorCore.settingsFilePath)), before)
        XCTAssertTrue(importer.validateMenuItem(NSMenuItem()))
    }

    // MARK: - 导入

    /// 窗口全部关闭以后导入，重新启动。关闭窗口的途中最后一个窗口关闭也不结束 App
    func testImportThenRelaunch() throws {
        let url = try windowsIni()
        choose(url)
        let importer = SettingsImporter()
        var importingWhileClosing = false
        SettingsImporter.closeAllDocuments = { [unowned self] completion in
            closeAllCount += 1
            importingWhileClosing = importer.isImporting
            XCTAssertFalse(EditorCore.isSettingsImportPending, "窗口关闭以后才导入")
            completion(true)
        }
        importer.importWindowsSettings(nil)

        XCTAssertTrue(errors.isEmpty)
        XCTAssertEqual(confirmed.count, 1)
        XCTAssertEqual(closeAllCount, 1)
        XCTAssertTrue(importingWhileClosing)
        XCTAssertFalse(importer.validateMenuItem(NSMenuItem()), "导入途中不能再执行")
        XCTAssertEqual(relaunchCount, 1)

        // 导入了：sakura.ini 是导入的设置，导入前的有备份，重新启动之前不写出
        XCTAssertTrue(EditorCore.isSettingsImportPending)
        let ini = try String(contentsOfFile: EditorCore.settingsFilePath, encoding: .utf8)
        XCTAssertTrue(ini.contains("KeyBind[018]=0077,31001,"))
        let backup = try String(contentsOfFile: EditorCore.settingsBackupPath, encoding: .utf8)
        XCTAssertTrue(backup.contains("KeyBind[018]=0077,30602,"))
        // 现在的设置在重新启动之前不变（与 Windows 版换掉 sakura.ini 相同）
        XCTAssertNotEqual(EditorCore.command(forKeyCode: 0x77, modifiers: []), 31001)
    }
}

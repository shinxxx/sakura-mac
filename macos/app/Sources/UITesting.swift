// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge

/// 自动界面测试（XCUITest，macos/app/UITests）用的启动方式。
///
/// 测试用启动参数 `-SakuraUITesting YES` 启动 App。这时：
/// - 设置文件 sakura.ini 放在临时目录，结束时不写出（不碰用户自己的设置）
/// - 剪贴板用测试专用的（不碰用户自己的剪贴板）
/// - 编辑区只用英文输入（日文、中文输入法打开时，测试输入的字母会变成未确定文字）
/// - 键位方案用默认的 Mac 方案（第 34 步）
/// 普通启动时什么也不改。
///
/// 第 31 步（重启后从「最近使ったファイル」打开）的测试另外用：
/// - `-SakuraUITestingHome 名字`：设置放在临时目录里这个名字的文件夹（两次启动用同一个），结束时写出设置
/// - `-SakuraUITestingOpenFile 名字`：在这个文件夹里做一个测试用的文件并打开（沙盒里测试那边放不了文件）
/// - `-SakuraUITestingOpenPath 路径`：不经过对话框直接打开这个文件，打不开时显示错误。
///   用来确认 App 真的在沙盒里（沙盒外的文件应该打不开）
///
/// 第 35 步（导入 Windows 版的设置，重启后生效）的测试另外用：
/// - `-SakuraUITestingImportFile 名字`：「Windows 版の設定をインポート…」不出文件对话框，用设置文件夹里这个名字的 ini
///   （没有时做一个：现在的设置的 F8 换成「すべて選択」，相当于在 Windows 版改过的设置）。
///   重新启动换成只结束（测试那边再启动）
enum UITesting {
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "SakuraUITesting")
    }

    /// 两次启动共用的设置文件夹的名字
    private static var homeName: String? {
        guard isEnabled else { return nil }
        return UserDefaults.standard.string(forKey: "SakuraUITestingHome")
    }

    /// 结束时写出 sakura.ini：普通启动时写；测试时只有指定了共用的文件夹时写
    static var savesSettings: Bool {
        !isEnabled || homeName != nil
    }

    /// 测试用文件的内容（测试那边也用这个比较）
    static let testFileContent = "line1\nline2\nline3\nline4\n"

    private static var home: URL?

    /// 测试专用剪贴板的名字（测试那边也用这个名字读写）
    static let pasteboardName = NSPasteboard.Name("jp.sakura-editor.uitesting")

    /// 启动核心库之前调用
    static func prepare() {
        guard isEnabled else { return }
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent(homeName.map { "sakura-uitest-\($0)" } ?? "sakura-uitest-\(ProcessInfo.processInfo.processIdentifier)")
        try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        setenv("HOME", home.path, 1)
        Self.home = home
        EditorTextView.defaultPasteboard = NSPasteboard(name: pasteboardName)
        EditorTextView.romanInputOnly = true
        // 第 34 步：键位方案每次从默认（Mac 方案）开始（测试里切换过也不留到下一次）
        UserDefaults.standard.removeObject(forKey: KeyScheme.defaultsKey)
    }

    /// 第 35 步：`-SakuraUITestingImportFile` 指定时，设置的导入用测试用的 ini。核心库启动以后调用
    static func prepareSettingsImport() {
        guard isEnabled, let home, let name = UserDefaults.standard.string(forKey: "SakuraUITestingImportFile") else { return }
        let url = home.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: url.path),
           var ini = try? Data(contentsOf: URL(fileURLWithPath: EditorCore.settingsFilePath)),
           let range = ini.range(of: Data("KeyBind[018]=0077,30602,".utf8)) {
            // 字节单位替换（UTF-8 的 BOM 留着：没有 BOM 的 ini 按 Shift_JIS 读，与 Windows 版相同）
            ini.replaceSubrange(range, with: Data("KeyBind[018]=0077,30401,".utf8))
            try? ini.write(to: url)
        }
        SettingsImporter.chooseFile = { url }
        SettingsImporter.relaunch = { NSApp.terminate(nil) }
    }

    /// 启动时打开测试用的文件
    static var opensTestFile: Bool {
        isEnabled && (UserDefaults.standard.string(forKey: "SakuraUITestingOpenFile") != nil
                      || UserDefaults.standard.string(forKey: "SakuraUITestingOpenPath") != nil)
    }

    /// `-SakuraUITestingOpenFile` 指定时，做测试用的文件（已经有时不改）并打开
    static func openTestFileIfRequested() {
        guard isEnabled else { return }
        if let path = UserDefaults.standard.string(forKey: "SakuraUITestingOpenPath") {
            NSDocumentController.shared.openDocument(withContentsOf: URL(fileURLWithPath: path), display: true) { _, _, error in
                if let error { NSApp.presentError(error) }
            }
            return
        }
        guard let home, let name = UserDefaults.standard.string(forKey: "SakuraUITestingOpenFile") else { return }
        let url = home.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? testFileContent.write(to: url, atomically: true, encoding: .utf8)
        }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
    }
}

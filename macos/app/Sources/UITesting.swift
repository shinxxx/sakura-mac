// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit

/// 自动界面测试（XCUITest，macos/app/UITests）用的启动方式。
///
/// 测试用启动参数 `-SakuraUITesting YES` 启动 App。这时：
/// - 设置文件 sakura.ini 放在临时目录，结束时不写出（不碰用户自己的设置）
/// - 剪贴板用测试专用的（不碰用户自己的剪贴板）
/// - 编辑区只用英文输入（日文、中文输入法打开时，测试输入的字母会变成未确定文字）
/// 普通启动时什么也不改。
enum UITesting {
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "SakuraUITesting")
    }

    /// 测试专用剪贴板的名字（测试那边也用这个名字读写）
    static let pasteboardName = NSPasteboard.Name("jp.sakura-editor.uitesting")

    /// 启动核心库之前调用
    static func prepare() {
        guard isEnabled else { return }
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("sakura-uitest-\(ProcessInfo.processInfo.processIdentifier)")
        try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        setenv("HOME", home.path, 1)
        EditorTextView.defaultPasteboard = NSPasteboard(name: pasteboardName)
        EditorTextView.romanInputOnly = true
    }
}

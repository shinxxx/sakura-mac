// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import EditorBridge
import Foundation

/// 测试用的核心库：一个进程里只启动一次（与 App 相同）。
/// 设置文件写在临时目录，不碰运行者自己的 sakura.ini。进程结束时不写出设置。
enum TestCore {
    static let home: URL = {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("sakura-mac-tests-\(ProcessInfo.processInfo.processIdentifier)")
        try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        setenv("HOME", home.path, 1)
        precondition(EditorCore.startup(), "核心库启动失败")
        return home
    }()
}

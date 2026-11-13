// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import EditorBridge
import Foundation
import XCTest

/// 测试用的核心库：一个进程里只启动一次（与 App 相同），全部测试结束时结束。
/// 设置文件写在临时目录，不碰运行者自己的 sakura.ini，也不写出设置。
///
/// 注：不用 `static let x = { ... }()` 的写法：Swift 6.3 编译多个测试文件时会在这里崩溃（IRGen）。
enum TestCore {
    private static var startedHome: URL?

    /// 第一次访问时启动核心库，返回测试用的 HOME
    static var home: URL {
        if let home = startedHome { return home }
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("sakura-mac-tests-\(ProcessInfo.processInfo.processIdentifier)")
        try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        setenv("HOME", home.path, 1)
        precondition(EditorCore.startup(), "核心库启动失败")
        // 与 App 相同：文字宽度用 Core Text 测（第 27 步）
        EditorCore.useCoreTextMeasurement()
        EditorCore.setLayoutFont(name: EditorTextView.fontName, size: EditorTextView.fontSize)
        XCTestObservationCenter.shared.addTestObserver(TestCoreObserver())
        startedHome = home
        return home
    }
}

/// 进程结束前先结束核心库（不结束就退出，全局对象的析构顺序会出问题）
final class TestCoreObserver: NSObject, XCTestObservation {
    func testBundleDidFinish(_ testBundle: Bundle) {
        EditorCore.shutdown(savingSettings: false)
        try? FileManager.default.removeItem(at: TestCore.home)
    }
}

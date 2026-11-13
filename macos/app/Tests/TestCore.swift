// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import EditorBridge
import Foundation
import XCTest

/// 测试用的核心库：一个进程里只启动一次（与 App 相同），全部测试结束时结束。
/// 设置文件写在临时目录，不碰运行者自己的 sakura.ini，也不写出设置。
enum TestCore {
    static let home: URL = {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("sakura-mac-tests-\(ProcessInfo.processInfo.processIdentifier)")
        try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        setenv("HOME", home.path, 1)
        precondition(EditorCore.startup(), "核心库启动失败")
        XCTestObservationCenter.shared.addTestObserver(Observer())
        return home
    }()

    /// 进程结束前先结束核心库（不结束就退出，全局对象的析构顺序会出问题）
    private final class Observer: NSObject, XCTestObservation {
        func testBundleDidFinish(_ testBundle: Bundle) {
            EditorCore.shutdown(savingSettings: false)
            try? FileManager.default.removeItem(at: TestCore.home)
        }
    }
}

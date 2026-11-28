// 第 37 步（原计划第 50 步）：run-tests.sh 用的输入法小工具。
// 界面测试打字时 XCUITest 会临时切到「Unicode 十六进制输入」，中途被打断时可能留在这个布局。
// run-tests.sh 开始时记下当前的输入法，结束或被打断时切回（2026-11-28 项目负责人同意）。
//
//   inputsource get          打印当前的输入法 ID（例：com.apple.keylayout.ABC）
//   inputsource set ID       切到这个输入法（只在已启用的输入法里找；找不到时返回 1）
//
// 编译：xcrun swiftc -O -o build/inputsource macos/tools/inputsource.swift
import Carbon
import Foundation

func sourceID(_ source: TISInputSource) -> String? {
    guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
    return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
}

func current() -> String? {
    guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
    return sourceID(source)
}

let args = CommandLine.arguments
switch args.count > 1 ? args[1] : "" {
case "get":
    guard let id = current() else { exit(1) }
    print(id)
case "set" where args.count > 2:
    let want = args[2]
    if current() == want { exit(0) }
    let filter = [kTISPropertyInputSourceID as String: want] as CFDictionary
    guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource],
          let source = list.first else {
        FileHandle.standardError.write("没有启用的输入法：\(want)\n".data(using: .utf8)!)
        exit(1)
    }
    let status = TISSelectInputSource(source)
    if status != noErr {
        FileHandle.standardError.write("切换失败（\(status)）：\(want)\n".data(using: .utf8)!)
        exit(1)
    }
    // 切换是异步的：等到真的切过去（最多 2 秒）
    for _ in 0..<20 where current() != want {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
    }
    exit(current() == want ? 0 : 1)
default:
    FileHandle.standardError.write("用法：inputsource get | inputsource set ID\n".data(using: .utf8)!)
    exit(2)
}

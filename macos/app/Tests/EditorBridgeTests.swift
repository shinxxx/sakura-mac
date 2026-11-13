// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import EditorBridge
import XCTest

/// 桥接层的测试（计划第 24 步）。
///
/// 完成标志：Swift 代码能通过桥接层打开文件并读到文本。
/// 核心库本身的测试在 macos/core/tests（956 个）；这里只确认 Swift → Objective-C++ → C++ 的连接，
/// 以及文字（UTF-16）、位置、编码等在边界上不走样。
final class EditorBridgeTests: XCTestCase {
    private var workDir: URL!

    override func setUpWithError() throws {
        workDir = TestCore.home.appendingPathComponent("work-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    }

    private func write(_ name: String, _ bytes: [UInt8]) throws -> String {
        let url = workDir.appendingPathComponent(name)
        try Data(bytes).write(to: url)
        return url.path
    }

    private func newDocument() throws -> EditorDocument {
        try XCTUnwrap(EditorDocument())
    }

    func testCoreIsStarted() {
        XCTAssertTrue(EditorCore.isStarted)
        XCTAssertTrue(EditorCore.settingsFilePath.hasSuffix("/Library/Application Support/sakura/sakura.ini"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: EditorCore.settingsFilePath))
    }

    /// 完成标志：打开 UTF-8 文件，读到文字
    func testOpenUTF8FileAndReadText() throws {
        let text = "#include <stdio.h>\n// さくらエディタ 🌸\nint main() { return 0; }\n"
        let path = try write("hello.cpp", Array(text.utf8))
        let doc = try newDocument()
        XCTAssertEqual(doc.open(path: path), .success)
        XCTAssertEqual(doc.text, text)
        XCTAssertEqual(doc.lineCount, 3)
        XCTAssertEqual(doc.line(at: 1), "// さくらエディタ 🌸")
        XCTAssertEqual(doc.line(at: 1, withEol: true), "// さくらエディタ 🌸\n")
        XCTAssertEqual(doc.eol(ofLine: 0), .lf)
        XCTAssertEqual(doc.encoding, ECEncodingUTF8)
        XCTAssertFalse(doc.hasBOM)
        XCTAssertEqual(doc.path, path)
        XCTAssertEqual(doc.typeName, "C/C++")
        XCTAssertFalse(doc.isModified)
        XCTAssertEqual(EditorCore.name(ofEncoding: doc.encoding), "UTF-8")
    }

    /// SJIS（CRLF）自动识别
    func testOpenShiftJISFile() throws {
        // 「日本語のテキスト」+ CRLF + 「二行目」
        let sjis: [UInt8] = [0x93, 0xFA, 0x96, 0x7B, 0x8C, 0xEA, 0x82, 0xCC, 0x83, 0x65, 0x83, 0x4C, 0x83, 0x58, 0x83, 0x67,
                             0x0D, 0x0A, 0x93, 0xF1, 0x8D, 0x73, 0x96, 0xDA]
        let path = try write("sjis.txt", sjis)
        let doc = try newDocument()
        XCTAssertEqual(doc.open(path: path), .success)
        XCTAssertEqual(doc.encoding, ECEncodingSJIS)
        XCTAssertEqual(doc.text, "日本語のテキスト\r\n二行目")
        XCTAssertEqual(doc.eol(ofLine: 0), .crlf)
        XCTAssertEqual(doc.typeName, "テキスト")
    }

    func testOpenMissingFileFails() throws {
        let doc = try newDocument()
        XCTAssertEqual(doc.open(path: workDir.appendingPathComponent("none.txt").path), .failed)
    }

    /// 编辑、撤销、查找、保存：位置和文字在 Swift 和 C++ 之间正确传递
    func testEditFindUndoAndSave() throws {
        let doc = try newDocument()
        XCTAssertEqual(doc.insert("abc\n🌸def\n", at: EditorPosition(line: 0, column: 0)), .success)
        XCTAssertEqual(doc.lineCount, 2)
        XCTAssertTrue(doc.isModified)
        // 补充平面字符是 2 个 UTF-16 单位
        var found = EditorRange()
        XCTAssertTrue(doc.find("def", from: EditorPosition(line: 0, column: 0), backward: false, options: [], range: &found))
        XCTAssertEqual(found.from.line, 1)
        XCTAssertEqual(found.from.column, 2)
        XCTAssertEqual(found.to.column, 5)
        XCTAssertEqual(doc.text(in: found), "def")

        var end = EditorPosition()
        XCTAssertEqual(doc.replace(found, with: "XYZ\n", newEnd: &end), .success)
        XCTAssertEqual(end.line, 2)
        XCTAssertEqual(end.column, 0)
        XCTAssertEqual(doc.text, "abc\n🌸XYZ\n\n")
        XCTAssertEqual(doc.replaceAll("[A-Z]", with: "_", options: [.regularExpression, .matchCase]), 3)
        XCTAssertEqual(doc.text, "abc\n🌸___\n\n")

        XCTAssertTrue(doc.canUndo)
        XCTAssertEqual(doc.undo(), .success)
        XCTAssertEqual(doc.undo(), .success)
        XCTAssertEqual(doc.text, "abc\n🌸def\n")
        XCTAssertEqual(doc.redo(), .success)
        XCTAssertEqual(doc.text, "abc\n🌸XYZ\n\n")

        // 超出范围的位置被拒绝
        XCTAssertEqual(doc.insert("x", at: EditorPosition(line: 99, column: 0)), .invalidArgument)
        XCTAssertEqual(doc.insert("x", at: EditorPosition(line: Int(Int32.max) + 1, column: 0)), .invalidArgument)

        let path = workDir.appendingPathComponent("out.txt").path
        XCTAssertEqual(doc.save(to: path, encoding: ECEncodingUTF16LE, bom: true, eol: .crlf), .success)
        let bytes = try [UInt8](Data(contentsOf: URL(fileURLWithPath: path)))
        var expected: [UInt8] = [0xFF, 0xFE]
        for unit in "abc\r\n🌸XYZ\r\n\r\n".utf16 {
            expected.append(UInt8(unit & 0xFF))
            expected.append(UInt8(unit >> 8))
        }
        XCTAssertEqual(bytes, expected)
        XCTAssertFalse(doc.isModified)
    }

    func testCommands() throws {
        XCTAssertEqual(EditorCore.name(ofCommand: ECCommandUndo), "元に戻す")
        XCTAssertTrue(EditorDocument.isSupported(ECCommandUndo))
        XCTAssertFalse(EditorDocument.isSupported(30401))  // F_SELECTALL（需要编辑画面）
        let doc = try newDocument()
        XCTAssertFalse(doc.isEnabled(ECCommandUndo))
        XCTAssertEqual(doc.insert("a", at: EditorPosition(line: 0, column: 0)), .success)
        XCTAssertTrue(doc.isEnabled(ECCommandUndo))
        XCTAssertEqual(doc.execute(ECCommandUndo), .success)
        XCTAssertEqual(doc.text, "")
        XCTAssertEqual(doc.execute(ECCommandNewLineLF), .success)
        XCTAssertEqual(doc.newLineEol, .lf)
        XCTAssertEqual(EditorCore.text(ofEol: .crlf), "\r\n")
    }
}

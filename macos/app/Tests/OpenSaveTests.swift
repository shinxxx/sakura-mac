// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge
import XCTest

/// 打开与保存的测试（计划第 30 步）。
///
/// 完成标志：第 18 步的样本文件在 App 里（SakuraDocument）打开再保存，字节不变。
/// 另外确认打开、保存对话框追加的部分（FileDialogAccessory）：编码列表、CP、BOM、换行符。
final class OpenSaveTests: XCTestCase {
    private var workDir: URL!

    override func setUpWithError() throws {
        _ = TestCore.home
        _ = NSApplication.shared
        workDir = TestCore.home.appendingPathComponent("open-save-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        SakuraDocument.requestedEncodings.removeAll()
        try? FileManager.default.removeItem(at: workDir)
    }

    private struct Sample {
        let name: String
        let encoding: EditorEncoding
        let bom: Bool
        let autoDetect: Bool
    }

    /// 第 18 步的样本（macos/core/tests/data/roundtrip，作为测试的资源复制进来）
    private func samples() throws -> (URL, [Sample]) {
        let dir = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "roundtrip", withExtension: nil), "样本文件夹")
        let manifest = try String(contentsOf: dir.appendingPathComponent("manifest.tsv"), encoding: .utf8)
        let samples = manifest.split(whereSeparator: \.isNewline).compactMap { line -> Sample? in
            guard !line.hasPrefix("#") else { return nil }
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 5, let code = Int(f[1]), let detect = Int(f[4]) else { return nil }
            return Sample(name: f[0], encoding: code, bom: f[3] == "1", autoDetect: detect != -1)
        }
        return (dir, samples)
    }

    /// 打开（打开对话框选了编码时与 SakuraDocumentController 相同：记下编码再打开）
    private func open(_ url: URL, encoding: EditorEncoding = ECEncodingAutoDetect) throws -> SakuraDocument {
        if encoding != ECEncodingAutoDetect {
            SakuraDocument.requestedEncodings[SakuraDocument.encodingKey(url)] = encoding
        }
        defer { SakuraDocument.requestedEncodings.removeAll() }
        return try SakuraDocument(contentsOf: url, ofType: "public.plain-text")
    }

    // MARK: - 完成标志

    func testSamplesOpenThenSaveAreByteIdentical() throws {
        let (dir, samples) = try samples()
        XCTAssertGreaterThanOrEqual(samples.count, 80)
        for sample in samples {
            let src = dir.appendingPathComponent(sample.name + ".bin")
            // 能自动识别的用「自動選択」，其他的在打开对话框里指定编码
            let document = try open(src, encoding: sample.autoDetect ? ECEncodingAutoDetect : sample.encoding)
            XCTAssertEqual(document.editor.encoding, sample.encoding, sample.name)
            XCTAssertEqual(document.editor.hasBOM, sample.bom, sample.name)
            XCTAssertFalse(document.lostSomeOnLoad, sample.name)

            // 上書き保存（现在的编码、BOM，不转换换行符）
            let dst = workDir.appendingPathComponent(sample.name + ".bin")
            try document.writeSafely(to: dst, ofType: "public.plain-text", for: .saveAsOperation)
            XCTAssertEqual(try Data(contentsOf: dst), try Data(contentsOf: src), sample.name)
        }
    }

    // MARK: - 打开时指定编码

    func testOpenWithSpecifiedEncoding() throws {
        let url = workDir.appendingPathComponent("a.txt")
        try Data([0x82, 0xA0, 0x0D, 0x0A]).write(to: url)	// SJIS 的「あ」
        XCTAssertEqual(try open(url).editor.encoding, ECEncodingSJIS)
        XCTAssertEqual(try open(url).editor.text, "あ\r\n")
        // 指定 Latin1：两个字节各是一个字
        let latin1 = try open(url, encoding: ECEncodingLatin1)
        XCTAssertEqual(latin1.editor.encoding, ECEncodingLatin1)
        XCTAssertEqual(latin1.editor.lineCount, 1)
        XCTAssertEqual((latin1.editor.line(at: 0) as NSString).length, 2)
        // 指定的编码只用一次
        XCTAssertTrue(SakuraDocument.requestedEncodings.isEmpty)
    }

    // MARK: - 保存时指定编码、BOM、换行符

    func testSaveWithEncodingBomAndEol() throws {
        let url = workDir.appendingPathComponent("b.txt")
        try Data("a\r\nb\nc".utf8).write(to: url)
        let document = try open(url)
        document.makeWindowControllers()
        defer { document.windowControllers.forEach { $0.window?.orderOut(nil); document.removeWindowController($0) } }

        // UTF-16LE、BOM、LF
        let dst = workDir.appendingPathComponent("b16.txt")
        document.nextSaveSettings = .init(encoding: ECEncodingUTF16LE, bom: true, eol: .lf)
        try document.writeSafely(to: dst, ofType: "public.plain-text", for: .saveAsOperation)
        document.nextSaveSettings = nil
        var expected = Data([0xFF, 0xFE])
        expected.append("a\nb\nc".data(using: .utf16LittleEndian)!)
        XCTAssertEqual(try Data(contentsOf: dst), expected)
        // 文档也换成了这个编码，换行符的统一可以撤销
        XCTAssertEqual(document.editor.encoding, ECEncodingUTF16LE)
        XCTAssertTrue(document.editor.hasBOM)
        XCTAssertEqual(document.editor.text, "a\nb\nc")
        XCTAssertEqual(document.editor.newLineEol, .lf)

        // 之后的上書き保存沿用
        try document.writeSafely(to: dst, ofType: "public.plain-text", for: .saveOperation)
        XCTAssertEqual(try Data(contentsOf: dst), expected)

        // UTF-8 不加 BOM，CRLF
        document.nextSaveSettings = .init(encoding: ECEncodingUTF8, bom: false, eol: .crlf)
        try document.writeSafely(to: dst, ofType: "public.plain-text", for: .saveAsOperation)
        XCTAssertEqual(try Data(contentsOf: dst), Data("a\r\nb\r\nc".utf8))
    }

    /// 没有要问的事情时，保存前的检查直接通过
    func testConfirmSaveWithoutWarnings() throws {
        let url = workDir.appendingPathComponent("c.txt")
        try Data("abc\n".utf8).write(to: url)
        let document = try open(url)
        let settings = SakuraDocument.SaveSettings(encoding: ECEncodingSJIS, bom: false, eol: EditorEol.none)
        var result: SakuraDocument.SaveSettings?
        document.confirmSave(settings) { result = $0 }
        XCTAssertEqual(result, settings)
    }

    /// 保存前的检查本身（问用户的对话框由界面测试以外的手动确认）
    func testSaveCheck() throws {
        let url = workDir.appendingPathComponent("d.txt")
        try Data("a\r\nb\né".utf8).write(to: url)
        let document = try open(url)
        let mixed = document.editor.checkSave(encoding: ECEncodingUTF8, eol: EditorEol.none)
        XCTAssertTrue(mixed.eolMixed)
        XCTAssertFalse(mixed.lostSome)
        XCTAssertFalse(document.editor.checkSave(encoding: ECEncodingUTF8, eol: .lf).eolMixed)
        let sjis = document.editor.checkSave(encoding: ECEncodingSJIS, eol: .lf)
        XCTAssertTrue(sjis.lostSome)
        XCTAssertEqual(sjis.lostLine, 2)
        XCTAssertEqual(sjis.lostColumn, 0)
        XCTAssertEqual(sjis.lostCharacter, "é")
        XCTAssertEqual(sjis.lostCharCode, "U+00E9")
        XCTAssertEqual(SakuraDocument.eolName(.crlf), "CRLF")
    }

    // MARK: - 对话框追加的部分

    func testOpenAccessory() {
        let accessory = FileDialogAccessory(mode: .open, encoding: ECEncodingAutoDetect)
        XCTAssertEqual(accessory.encoding, ECEncodingAutoDetect)
        XCTAssertFalse(accessory.codePagesShown)
        XCTAssertTrue(accessory.selectEncoding(ECEncodingEUC))
        XCTAssertEqual(accessory.encoding, ECEncodingEUC)
        XCTAssertFalse(accessory.selectEncoding(932), "勾选 CP 之前没有代码页")
        accessory.showCodePages()
        XCTAssertTrue(accessory.codePagesShown)
        XCTAssertEqual(accessory.encoding, ECEncodingEUC, "勾选 CP 不改选择")
        XCTAssertTrue(accessory.selectEncoding(932))
        XCTAssertTrue(accessory.selectEncoding(ECEncodingUTF32LE))
        XCTAssertFalse(accessory.bom, "打开对话框没有 BOM")
    }

    func testSaveAccessory() {
        // SJIS 的文档：没有「自動選択」，BOM 不能选
        let accessory = FileDialogAccessory(mode: .save, encoding: ECEncodingSJIS, bom: false)
        XCTAssertEqual(accessory.encoding, ECEncodingSJIS)
        XCTAssertFalse(accessory.selectEncoding(ECEncodingAutoDetect))
        XCTAssertFalse(accessory.bom)
        accessory.setBOM(true)
        XCTAssertFalse(accessory.bom)
        XCTAssertEqual(accessory.eol, EditorEol.none, "换行符一开始是「変換なし」")

        // 换成 UTF-16：BOM 默认勾选；UTF-8：默认不勾选，可以勾选
        accessory.selectEncoding(ECEncodingUTF16LE)
        XCTAssertTrue(accessory.bom)
        accessory.selectEncoding(ECEncodingUTF8)
        XCTAssertFalse(accessory.bom)
        accessory.setBOM(true)
        XCTAssertTrue(accessory.bom)

        accessory.selectEol(.lf)
        XCTAssertEqual(accessory.eol, .lf)
        XCTAssertEqual(FileDialogAccessory.eolChoices.map { $0.eol }, [EditorEol.none, .crlf, .lf, .cr])
    }

    func testSaveAccessoryKeepsCurrentBom() {
        // UTF-8 BOM 的文档：一开始勾选 BOM；换成别的再换回来，回到文档现在的状态
        let accessory = FileDialogAccessory(mode: .save, encoding: ECEncodingUTF8, bom: true)
        XCTAssertTrue(accessory.bom)
        accessory.selectEncoding(ECEncodingSJIS)
        XCTAssertFalse(accessory.bom)
        accessory.selectEncoding(ECEncodingUTF8)
        XCTAssertTrue(accessory.bom)
    }

    func testSaveAccessoryWithCodePageDocument() {
        // 现在的编码是代码页：一开始就显示代码页并选中，「CP」不能取消
        let accessory = FileDialogAccessory(mode: .save, encoding: 1252, bom: false)
        XCTAssertTrue(accessory.codePagesShown)
        XCTAssertEqual(accessory.encoding, 1252)
    }
}

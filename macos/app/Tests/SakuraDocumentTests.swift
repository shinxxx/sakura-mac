// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge
import XCTest

/// 文档和窗口框架的测试（计划第 26 步）。
///
/// 完成标志：能同时打开多个文件并切换。
/// 测试不启动 App（NSDocumentController 不认识测试进程的文档类型），所以直接建立 SakuraDocument。
final class SakuraDocumentTests: XCTestCase {
    private var workDir: URL!
    private var documents: [SakuraDocument] = []

    override func setUpWithError() throws {
        _ = TestCore.home
        _ = NSApplication.shared
        workDir = TestCore.home.appendingPathComponent("docs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        for document in documents {
            for controller in document.windowControllers {
                controller.window?.orderOut(nil)
                document.removeWindowController(controller)
            }
        }
        documents = []
    }

    private func write(_ name: String, _ text: String) throws -> URL {
        let url = workDir.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        return url
    }

    private func open(_ url: URL) throws -> SakuraDocument {
        let document = try SakuraDocument(contentsOf: url, ofType: "public.plain-text")
        document.makeWindowControllers()
        documents.append(document)
        return document
    }

    private func window(_ document: SakuraDocument) throws -> NSWindow {
        try XCTUnwrap(document.windowControllers.first?.window)
    }

    /// 完成标志：同时打开多个文件，各自一个窗口，内容互不影响，可以切换
    func testOpenMultipleFilesAndSwitch() throws {
        let a = try open(try write("a.txt", "AAA\n"))
        let b = try open(try write("b.cpp", "int b;\n"))
        XCTAssertEqual(a.editor.text, "AAA\n")
        XCTAssertEqual(b.editor.text, "int b;\n")
        XCTAssertEqual(b.editor.typeName, "C/C++")

        let wa = try window(a)
        let wb = try window(b)
        XCTAssertFalse(wa === wb)
        XCTAssertEqual(wa.title, "a.txt")
        XCTAssertEqual(wb.title, "b.cpp")

        // 切换：哪个窗口在前，输入就进哪个文件
        wa.makeKeyAndOrderFront(nil)
        let viewA = try XCTUnwrap(wa.initialFirstResponder as? EditorTextView)
        let viewB = try XCTUnwrap(wb.initialFirstResponder as? EditorTextView)
        viewA.insertText("x", replacementRange: NSRange(location: NSNotFound, length: 0))
        wb.makeKeyAndOrderFront(nil)
        viewB.insertText("y", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(a.editor.text, "xAAA\n")
        XCTAssertEqual(b.editor.text, "yint b;\n")
    }

    /// 窗口可以合并成标签，标签之间可以切换
    func testWindowsMergeIntoTabs() throws {
        let a = try open(try write("a.txt", "A"))
        let b = try open(try write("b.txt", "B"))
        let wa = try window(a)
        let wb = try window(b)
        XCTAssertEqual(wa.tabbingIdentifier, EditorWindowController.tabbingIdentifier)
        XCTAssertEqual(wb.tabbingIdentifier, EditorWindowController.tabbingIdentifier)

        wa.makeKeyAndOrderFront(nil)
        wa.addTabbedWindow(wb, ordered: .above)
        XCTAssertEqual(wa.tabbedWindows?.count, 2)
        XCTAssertTrue(wa.tabbedWindows?.contains { $0 === wb } ?? false)

        wb.makeKeyAndOrderFront(nil)
        XCTAssertTrue(wa.tabGroup?.selectedWindow === wb)
        wb.selectNextTab(nil)
        XCTAssertTrue(wa.tabGroup?.selectedWindow === wa)
    }

    /// 修改后标题加「(更新)」，撤销回到原样后去掉（与原版相同）
    func testModifiedMarkInTitle() throws {
        let a = try open(try write("memo.txt", "abc"))
        let w = try window(a)
        let view = try XCTUnwrap(w.initialFirstResponder as? EditorTextView)
        XCTAssertFalse(a.isDocumentEdited)

        view.insertText("!", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(a.isDocumentEdited)
        XCTAssertEqual(w.title, "memo.txt (更新)")
        XCTAssertTrue(w.isDocumentEdited)

        view.undo(nil)
        XCTAssertFalse(a.isDocumentEdited)
        XCTAssertEqual(w.title, "memo.txt")
        XCTAssertFalse(w.isDocumentEdited)
    }

    /// 新建的文档是「(無題)」；另存为后变成文件名，按扩展名换类型
    func testUntitledDocumentAndSave() throws {
        let document = SakuraDocument()
        document.makeWindowControllers()
        documents.append(document)
        let w = try window(document)
        XCTAssertEqual(document.displayName, "(無題)")
        XCTAssertEqual(w.title, "(無題)")

        let view = try XCTUnwrap(w.initialFirstResponder as? EditorTextView)
        view.insertText("int main() {}", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(w.title, "(無題) (更新)")

        let url = workDir.appendingPathComponent("new.cpp")
        try document.writeSafely(to: url, ofType: "public.plain-text", for: .saveAsOperation)
        XCTAssertEqual(try Data(contentsOf: url), Data("int main() {}".utf8))
        XCTAssertFalse(document.isDocumentEdited)
        XCTAssertEqual(document.editor.typeName, "C/C++")

        // 覆盖保存
        view.insertText("\n", replacementRange: NSRange(location: NSNotFound, length: 0))
        try document.writeSafely(to: url, ofType: "public.plain-text", for: .saveOperation)
        XCTAssertEqual(try Data(contentsOf: url), Data("int main() {}\n".utf8))
    }

    /// 打开时保留编码，保存时沿用（SJIS 的文件保存后还是 SJIS）
    func testSaveKeepsEncoding() throws {
        let url = workDir.appendingPathComponent("sjis.txt")
        let sjis = Data([0x93, 0xFA, 0x96, 0x7B, 0x8C, 0xEA, 0x82, 0xCC, 0x83, 0x65, 0x83, 0x4C, 0x83, 0x58, 0x83, 0x67, 0x0D, 0x0A])
        try sjis.write(to: url)
        let document = try open(url)
        XCTAssertEqual(document.editor.encoding, ECEncodingSJIS)
        XCTAssertEqual(try window(document).subtitle, "SJIS")
        try document.writeSafely(to: url, ofType: "public.plain-text", for: .saveOperation)
        XCTAssertEqual(try Data(contentsOf: url), sjis)
    }

    func testOpenMissingFileThrows() {
        XCTAssertThrowsError(try SakuraDocument(contentsOf: workDir.appendingPathComponent("none.txt"), ofType: "public.plain-text"))
    }
}

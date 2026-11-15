// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge
import XCTest

/// 沙盒文件访问和「最近使ったファイル」的测试（计划第 31 步）。
///
/// 完成标志：重启 App 后最近文件仍能直接打开。这里确认 App 这边的部分：
/// - 安全书签存到文件里，新的 BookmarkStore（相当于重启后）读得回来，找得到文件
/// - 打开、关闭时登记到历史，再打开时恢复光标和表示域
/// - 打开时的编码与上次不同时问用户（原版 CMruListener）
/// - 「最近使ったファイル」「最近使ったフォルダー」菜单的内容
/// 真的重启 App 再从菜单打开，由界面测试（SakuraMacUITests.testReopenFromRecentFilesAfterRestart）确认。
final class RecentFilesTests: XCTestCase {
    private var workDir: URL!
    private var documents: [SakuraDocument] = []
    private var savedAsk: ((String, EditorEncoding, EditorEncoding) -> Bool)!

    override func setUpWithError() throws {
        _ = TestCore.home
        _ = NSApplication.shared
        workDir = TestCore.home.appendingPathComponent("recent-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        savedAsk = SakuraDocument.askUsePreviousEncoding
        SakuraDocument.askUsePreviousEncoding = { _, _, _ in
            XCTFail("不应该问编码")
            return false
        }
    }

    override func tearDown() {
        for document in documents {
            for controller in document.windowControllers {
                controller.window?.orderOut(nil)
                document.removeWindowController(controller)
            }
        }
        documents = []
        SakuraDocument.askUsePreviousEncoding = savedAsk
        SakuraDocument.requestedEncodings.removeAll()
        try? FileManager.default.removeItem(at: workDir)
    }

    private func write(_ name: String, _ data: Data) throws -> URL {
        let url = workDir.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    private func open(_ url: URL, encoding: EditorEncoding = ECEncodingAutoDetect) throws -> SakuraDocument {
        if encoding != ECEncodingAutoDetect {
            SakuraDocument.requestedEncodings[SakuraDocument.encodingKey(url)] = encoding
        }
        defer { SakuraDocument.requestedEncodings.removeAll() }
        let document = try SakuraDocument(contentsOf: url, ofType: "public.plain-text")
        document.makeWindowControllers()
        documents.append(document)
        return document
    }

    private func textView(_ document: SakuraDocument) throws -> EditorTextView {
        try XCTUnwrap(document.windowControllers.first as? EditorWindowController).textView
    }

    // MARK: - 安全书签（完成标志：重启后仍能打开）

    func testBookmarkSurvivesNewStore() throws {
        let file = try write("a.txt", Data("abc".utf8))
        let storeURL = workDir.appendingPathComponent("bookmarks.plist")
        let store = BookmarkStore(fileURL: storeURL)
        XCTAssertTrue(store.remember(file))
        XCTAssertTrue(FileManager.default.fileExists(atPath: storeURL.path), "书签写进了文件")

        // 重启后：新的实例从文件读回来
        let restarted = BookmarkStore(fileURL: storeURL)
        XCTAssertTrue(restarted.hasBookmark(forPath: file.path))
        let resolved = try XCTUnwrap(restarted.resolve(path: file.path))
        XCTAssertEqual(resolved.resolvingSymlinksInPath().path, file.resolvingSymlinksInPath().path)
        let accessing = resolved.startAccessingSecurityScopedResource()
        defer { if accessing { resolved.stopAccessingSecurityScopedResource() } }
        XCTAssertEqual(try String(contentsOf: resolved, encoding: .utf8), "abc")
    }

    func testBookmarkFollowsMovedFile() throws {
        let file = try write("before.txt", Data("moved".utf8))
        let store = BookmarkStore(fileURL: workDir.appendingPathComponent("bookmarks.plist"))
        XCTAssertTrue(store.remember(file))
        let moved = workDir.appendingPathComponent("after.txt")
        try FileManager.default.moveItem(at: file, to: moved)
        // 书签跟着文件走（原版只有路径，移动后找不到）
        let resolved = try XCTUnwrap(store.resolve(path: file.path))
        XCTAssertEqual(resolved.resolvingSymlinksInPath().path, moved.resolvingSymlinksInPath().path)
    }

    func testBookmarkPrune() throws {
        let a = try write("a.txt", Data("a".utf8))
        let b = try write("b.txt", Data("b".utf8))
        let store = BookmarkStore(fileURL: workDir.appendingPathComponent("bookmarks.plist"))
        store.remember(a)
        store.remember(b)
        store.prune { $0 == a.path }
        XCTAssertEqual(store.paths, [a.path])
        XCTAssertEqual(BookmarkStore(fileURL: store.fileURL).paths, [a.path], "删掉的也写进了文件")
        XCTAssertNil(store.resolve(path: b.path))
    }

    func testOpenRemembersBookmarkAndHistory() throws {
        let file = try write("remember.txt", Data("x\n".utf8))
        _ = try open(file)
        XCTAssertTrue(BookmarkStore.shared.hasBookmark(forPath: file.path), "打开成功后记下书签")
        XCTAssertNotNil(EditorCore.recentFile(path: file.path), "登记到历史")
        XCTAssertTrue(EditorCore.recentFolders.contains { $0.path == workDir.path + "/" }, "文件夹也登记（末尾带 /）")
    }

    // MARK: - 上次的位置（原版 CMruListener::OnAfterLoad）

    func testCaretAndTopLineRestoredOnReopen() throws {
        let lines = (1...200).map { "line \($0)" }.joined(separator: "\n") + "\n"
        let file = try write("caret.txt", Data(lines.utf8))
        let first = try open(file)
        let view = try textView(first)
        view.restoreView(caret: EditorPosition(line: 120, column: 3), topRow: 100, toEnd: false)
        let top = view.topVisibleRow
        XCTAssertGreaterThan(top, 50, "滚动了")
        XCTAssertEqual(view.caret.line, 120)
        XCTAssertNotNil(first.fileURL)
        XCTAssertEqual(first.editor.path, file.path, "核心库的路径")
        XCTAssertIdentical((first.windowControllers.first as? EditorWindowController)?.textView, view)
        first.addToRecent()
        XCTAssertEqual(EditorCore.recentFile(path: file.path)?.caret.line, 120, "关闭前也能登记")
        first.close()	// 关闭前登记（原版 OnBeforeClose）
        XCTAssertEqual(EditorCore.recentFiles.first?.path, file.path, "最新的一项")
        XCTAssertEqual(EditorCore.recentFiles.first?.caret.line, 120, "最新的一项的光标")
        documents.removeAll { $0 === first }

        let recent = try XCTUnwrap(EditorCore.recentFile(path: file.path))
        XCTAssertEqual(recent.caret.line, 120)
        XCTAssertEqual(recent.caret.column, 3)
        XCTAssertEqual(recent.viewTopLine, top)

        let second = try open(file)
        let restored = try textView(second)
        XCTAssertEqual(restored.caret.line, 120, "光标回到上次的位置")
        XCTAssertEqual(restored.caret.column, 3)
        XCTAssertEqual(restored.topVisibleRow, top, "表示域的第一行也恢复")
    }

    func testCaretPastEndMovesToEnd() throws {
        let file = try write("short.txt", Data("1\n2\n3\n4\n5\n".utf8))
        let first = try open(file)
        try textView(first).setCaret(EditorPosition(line: 4, column: 1))
        first.close()
        documents.removeAll { $0 === first }
        // 文件在外面变短了：上次的位置超过文件末尾，移到文件末尾
        try Data("1\n".utf8).write(to: file)
        let second = try open(file)
        let view = try textView(second)
        XCTAssertEqual(view.caret.line, second.editor.endPosition.line)
        XCTAssertEqual(view.caret.column, second.editor.endPosition.column)
    }

    // MARK: - 上次的编码（原版 CMruListener::OnBeforeLoad）

    func testAskWhenEncodingDiffersFromPrevious() throws {
        // UTF-8 的日文。第一次指定 EUC 打开（历史记下 EUC），第二次自动识别是 UTF-8，与上次不同
        let file = try write("enc.txt", Data("日本語のテキスト\n".utf8))
        let first = try open(file, encoding: ECEncodingEUC)
        XCTAssertEqual(first.editor.encoding, ECEncodingEUC)
        first.close()
        documents.removeAll { $0 === first }

        var asked: [(EditorEncoding, EditorEncoding)] = []
        SakuraDocument.askUsePreviousEncoding = { path, current, previous in
            XCTAssertEqual(path, file.path)
            asked.append((current, previous))
            return false	// いいえ：这次的编码
        }
        let second = try open(file)
        XCTAssertEqual(asked.count, 1, "问了一次")
        XCTAssertEqual(asked.first?.0, ECEncodingUTF8)
        XCTAssertEqual(asked.first?.1, ECEncodingEUC)
        XCTAssertEqual(second.editor.encoding, ECEncodingUTF8)
        second.close()
        documents.removeAll { $0 === second }

        // 历史现在是 UTF-8：再打开不问
        SakuraDocument.askUsePreviousEncoding = { _, _, _ in
            XCTFail("编码与上次相同，不问")
            return false
        }
        let third = try open(file)
        XCTAssertEqual(third.editor.encoding, ECEncodingUTF8)
        third.close()
        documents.removeAll { $0 === third }

        // 指定的编码与上次不同时也问（原版相同）。いいえ：用指定的 EUC
        SakuraDocument.askUsePreviousEncoding = { _, _, _ in false }
        let fourth = try open(file, encoding: ECEncodingEUC)
        XCTAssertEqual(fourth.editor.encoding, ECEncodingEUC)
        fourth.close()
        documents.removeAll { $0 === fourth }
        // はい：自动识别是 UTF-8，用上次的 EUC
        SakuraDocument.askUsePreviousEncoding = { _, _, _ in true }
        let fifth = try open(file)
        XCTAssertEqual(fifth.editor.encoding, ECEncodingEUC)
    }

    func testOpenFromRecentUsesPreviousEncodingWithoutAsking() throws {
        // 从「最近使ったファイル」打开时与原版相同，指定上次的编码（不问）
        let file = try write("prev.txt", Data("日本語のテキスト\n".utf8))
        let first = try open(file, encoding: ECEncodingEUC)
        first.close()
        documents.removeAll { $0 === first }
        let recent = try XCTUnwrap(EditorCore.recentFile(path: file.path))
        let second = try open(file, encoding: recent.encoding)
        XCTAssertEqual(second.editor.encoding, ECEncodingEUC)
    }

    // MARK: - 菜单

    func testRecentMenusListHistory() throws {
        let file = try write("menu.txt", Data("m\n".utf8))
        let document = try open(file)
        document.close()
        documents.removeAll { $0 === document }

        let files = RecentMenu(kind: .files)
        XCTAssertIdentical(files.item.submenu, files.menu)
        let item = try XCTUnwrap(files.menu.items.first { ($0.representedObject as? String) == file.path }, "历史里的文件在菜单里")
        XCTAssertTrue(item.title.contains("menu.txt"), item.title)
        XCTAssertFalse(item.title.contains("&"), "去掉了快捷字母的记号：\(item.title)")
        XCTAssertEqual(files.menu.items.first?.representedObject as? String, file.path, "新的在最前")
        XCTAssertEqual(files.menu.items.count, EditorCore.recentFiles.count)

        let folders = RecentMenu(kind: .folders)
        XCTAssertTrue(folders.menu.items.contains { ($0.representedObject as? String) == workDir.path + "/" })
    }

    func testRecentMenuGrayedWhenEmpty() throws {
        // 菜单只显示「ファイルの履歴MAX」个，后面还有：全部删掉
        for _ in 0..<100 {
            guard let path = EditorCore.recentFiles.first?.path else { break }
            EditorCore.removeRecentFile(path: path)
        }
        XCTAssertTrue(EditorCore.recentFiles.isEmpty)
        let files = RecentMenu(kind: .files)
        XCTAssertNil(files.item.submenu, "历史是空的：没有子菜单")
        XCTAssertNil(files.item.action, "没有动作的项 macOS 自动变灰")
        let file = try write("again.txt", Data("a".utf8))
        _ = try open(file)
        files.update()
        XCTAssertIdentical(files.item.submenu, files.menu, "有了历史就有子菜单")
    }

    func testLabelWithoutMnemonic() {
        XCTAssertEqual(RecentMenu.labelWithoutMnemonic("&1 /a/b.txt  [UTF-8]"), "1 /a/b.txt  [UTF-8]")
        XCTAssertEqual(RecentMenu.labelWithoutMnemonic("&A /R&&D/x"), "A /R&D/x")
    }

    // MARK: - 拖放

    func testDroppedFileURLs() throws {
        let file = try write("drop.txt", Data("d".utf8))
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("jp.sakura-editor.tests.drop-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.writeObjects([file as NSURL, "not a file" as NSString])
        XCTAssertEqual(EditorTextView.droppedFileURLs(pasteboard).map(\.path), [file.path])
        let view = EditorTextView(document: try XCTUnwrap(EditorDocument()))
        XCTAssertTrue(view.registeredDraggedTypes.contains(.fileURL), "接受文件的拖放")
    }
}

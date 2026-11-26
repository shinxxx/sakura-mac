// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge
import XCTest

/// 第 43 步的对话框的截图（Grep・Grep置換・Grep実行中・ファイルツリー設定・ファイルツリー）。
///
/// 外观的自动检查在 GrepTests・FileTreeTests（PropLayoutTests.truncated）。这里把画面写成 PNG，供人对照原版查看
/// （写到 $TMPDIR/sakura-dialog-shots/，路径打印在测试日志里）。
final class DialogScreenshotTests: XCTestCase {
    private var directory: URL!
    private var documents: [SakuraDocument] = []

    override func setUpWithError() throws {
        _ = TestCore.home
        _ = NSApplication.shared
        OutlineWindowController.hidesOnDeactivate = false
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("sakura-dialog-shots")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        print("截图：\(directory.path)")
    }

    override func tearDown() {
        for document in documents {
            document.editorWindowController?.textView.outlinePanel?.close()
            document.close()
        }
        documents = []
    }

    /// 窗口的内容画成 PNG（2 倍）。返回图的大小
    @discardableResult
    private func shot(_ view: NSView, _ name: String) throws -> NSSize {
        view.layoutSubtreeIfNeeded()
        view.display()
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try data.write(to: directory.appendingPathComponent(name + ".png"))
        XCTAssertGreaterThan(rep.pixelsWide, 100)
        return view.bounds.size
    }

    private func makeView() throws -> EditorTextView {
        let document = SakuraDocument()
        document.makeWindowControllers()
        documents.append(document)
        return try XCTUnwrap(document.editorWindowController?.textView)
    }

    func testGrepDialogs() throws {
        let view = try makeView()
        for replace in [false, true] {
            let dialog = try XCTUnwrap(GrepDialogController(replace: replace, state: replace ? view.grepReplaceDialogState : view.grepDialogState,
                                                            currentFilePath: "", sourceToken: GrepCore.sourceToken(view.grepSourceID)))
            dialog.page.setText("IDC_COMBO_TEXT", "HIT")
            dialog.window.orderFront(nil)
            try shot(try XCTUnwrap(dialog.window.contentView), replace ? "IDD_GREP_REPLACE" : "IDD_GREP")
            dialog.window.orderOut(nil)
        }
        let runner = GrepRunner(view: view, options: GrepOptions(), sources: [])
        let panel = try XCTUnwrap(GrepRunningPanel(runner: runner, parent: try XCTUnwrap(view.window)))
        panel.update(hitCount: 12345, file: "a.txt", folder: "/Users/example/project/src")
        try shot(panel.page.view, "IDD_GREPRUNNING")
    }

    func testFileTreeDialogs() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("shot-tree-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Sub"), withIntermediateDirectories: true)
        try "x".write(to: folder.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: folder) }
        // 項目：見本のフォルダー（終わったら共通設定を戻す）
        let saved = FileTreeCore.load(typeIndex: 0, folder: folder.path)
        let setting = FileTreeCore.load(typeIndex: 0, folder: folder.path)
        let grep = FileTreeItem()
        grep.path = folder.path
        grep.label = "project"
        let group = FileTreeItem()
        group.type = .folder
        group.label = "Docs"
        let file = FileTreeItem()
        file.type = .file
        file.path = folder.appendingPathComponent("a.txt").path
        file.depth = 1
        setting.items = [grep, group, file]
        setting.loadedIni = ""
        var truncated: ObjCBool = false
        _ = FileTreeCore.save(setting, typeIndex: 0, truncated: &truncated)
        defer {
            saved.loadedIni = ""
            _ = FileTreeCore.save(saved, typeIndex: 0, truncated: &truncated)
        }
        let dialog = try XCTUnwrap(FileTreeDialogController(typeIndex: 0, folder: folder.path))
        let window = NSPanel(contentRect: NSRect(origin: .zero, size: dialog.page.view.frame.size), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = dialog.page.view
        window.orderFront(nil)
        try shot(dialog.page.view, "IDD_FILETREE")
        window.orderOut(nil)

        let view = try makeView()
        view.showFileTree(nil)
        let panel = try XCTUnwrap(view.outlinePanel)
        if let root = panel.treeView.item(atRow: 0) { panel.treeView.expandItem(root) }
        try shot(try XCTUnwrap(panel.window?.contentView), "IDD_FUNCLIST_filetree")
    }
}

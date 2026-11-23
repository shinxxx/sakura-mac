// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge
import XCTest

/// タイプ別設定一覧（计划第 40 步第 3 个 PR。原版 CDlgTypeList、CDlgTypeAscertain）。
/// 真的核心库のタイプ別設定を変えるので、各テストの最後に追加したタイプを削除して元に戻す。
final class TypeListTests: XCTestCase {
    private var countBefore = 0
    private var saved: (confirm: (String) -> Bool, inform: (String) -> Void, show: (String) -> Void)!
    private var messages: [String] = []

    override func setUp() {
        _ = TestCore.home
        _ = NSApplication.shared
        countBefore = EditorCore.typeSettings.count
        saved = (CommonSettingsPages.confirm, CommonSettingsPages.inform, TypeSettingsPages.showMessage)
        CommonSettingsPages.confirm = { [unowned self] in self.messages.append($0); return true }
        CommonSettingsPages.inform = { [unowned self] in self.messages.append($0) }
        TypeSettingsPages.showMessage = { [unowned self] in self.messages.append($0) }
    }

    override func tearDown() {
        // 追加したタイプを消す
        while EditorCore.typeSettings.count > countBefore {
            XCTAssertTrue(EditorCore.deleteTypeSetting(EditorCore.typeSettings.count - 1))
        }
        (CommonSettingsPages.confirm, CommonSettingsPages.inform, TypeSettingsPages.showMessage) = saved
    }

    private var cpp: Int { EditorCore.typeSettings.first { $0.name == "C/C++" }?.index ?? -1 }

    func testListShowsTypes() throws {
        let dialog = try XCTUnwrap(TypeListDialog(selectedIndex: 0, enableTempChange: true))
        XCTAssertEqual(dialog.title, "タイプ別設定一覧")
        let list = try XCTUnwrap(dialog.page.list("IDC_LIST_TYPES"))
        XCTAssertEqual(list.rows.count, countBefore)
        XCTAssertEqual(list.rows[0][0], "基本")
        XCTAssertEqual(list.rows[cpp][0], TypeListDialog.label(EditorCore.typeSettings[cpp]))
        XCTAssertTrue(list.rows[cpp][0].hasPrefix("C/C++ ( "))
        // 「基本」は動かせない・削除できない
        XCTAssertFalse(dialog.page.isEnabled("IDC_BUTTON_UP_TYPE"))
        XCTAssertFalse(dialog.page.isEnabled("IDC_BUTTON_DOWN_TYPE"))
        XCTAssertFalse(dialog.page.isEnabled("IDC_BUTTON_DEL_TYPE"))
        XCTAssertFalse(dialog.page.isEnabled("IDC_CHECK_EXT_RMENU"), "Windows の関連付け")
        list.select(1)
        dialog.enable()
        XCTAssertFalse(dialog.page.isEnabled("IDC_BUTTON_UP_TYPE"), "2 番目は「基本」の上に行けない")
        XCTAssertTrue(dialog.page.isEnabled("IDC_BUTTON_DOWN_TYPE"))
        XCTAssertTrue(dialog.page.isEnabled("IDC_BUTTON_DEL_TYPE"))
    }

    /// 設定変更・一時適用（ボタン、ダブルクリック）・キャンセル
    func testResults() throws {
        let dialog = try XCTUnwrap(TypeListDialog(selectedIndex: cpp, enableTempChange: true))
        XCTAssertEqual(dialog.selectedIndex, cpp)
        dialog.button("IDOK")
        XCTAssertEqual(dialog.result, TypeListDialog.Result(index: cpp, temporary: false))
        dialog.button("IDC_BUTTON_TEMPCHANGE")
        XCTAssertEqual(dialog.result, TypeListDialog.Result(index: cpp, temporary: true))
        dialog.page.list("IDC_LIST_TYPES")?.onDoubleClick?(2, 0)
        XCTAssertEqual(dialog.result, TypeListDialog.Result(index: 2, temporary: true))
        dialog.button("IDCANCEL")
        XCTAssertNil(dialog.result)
    }

    /// 追加・複製・↑↓・削除・初期化。一覧が変わると文書に知らせる
    func testEditList() throws {
        let dialog = try XCTUnwrap(TypeListDialog(selectedIndex: cpp, enableTempChange: false))
        XCTAssertFalse(dialog.page.isEnabled("IDC_BUTTON_TEMPCHANGE"))
        dialog.button("IDC_BUTTON_COPY_TYPE")
        XCTAssertEqual(dialog.types.count, countBefore + 1)
        XCTAssertEqual(dialog.selectedIndex, countBefore)
        XCTAssertEqual(dialog.types.last?.name, "C/C++2")
        dialog.button("IDC_BUTTON_ADD_TYPE")
        XCTAssertEqual(dialog.selectedIndex, countBefore + 1)
        let added = try XCTUnwrap(dialog.types.last).name
        XCTAssertTrue(added.hasPrefix("設定"))

        let listChanged = expectation(forNotification: TypeSettingsWindowController.listDidChangeNotification, object: nil)
        dialog.button("IDC_BUTTON_UP_TYPE")
        wait(for: [listChanged], timeout: 1)
        XCTAssertEqual(dialog.selectedIndex, countBefore)
        XCTAssertEqual(dialog.types[countBefore].name, added)

        // 初期化：拡張子がないタイプは確認しない
        messages = []
        let typeChanged = expectation(forNotification: TypeSettingsWindowController.didChangeNotification, object: nil) { note in
            note.userInfo?["index"] as? Int == self.countBefore
        }
        dialog.button("IDC_BUTTON_INITIALIZE")
        wait(for: [typeChanged], timeout: 1)
        XCTAssertEqual(messages.count, 1)
        XCTAssertTrue(messages[0].hasSuffix("を初期化しました。"), "\(messages)")

        // 削除：確認する
        messages = []
        dialog.button("IDC_BUTTON_DEL_TYPE")
        XCTAssertEqual(messages.first.map { $0.hasSuffix("を削除します。 よろしいですか？") }, true)
        XCTAssertEqual(dialog.types.count, countBefore + 1)
    }

    /// エクスポート → インポート（確認ダイアログで新規追加、色は「そのまま」）
    func testImportExport() throws {
        let dir = TestCore.home.appendingPathComponent("type-list")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("cpp.ini").path
        let savedFiles = (TypeSettingsPages.chooseExportFile, TypeSettingsPages.chooseImportFile, TypeSettingsPages.runTypeAscertainDialog)
        defer { (TypeSettingsPages.chooseExportFile, TypeSettingsPages.chooseImportFile, TypeSettingsPages.runTypeAscertainDialog) = savedFiles }
        var defaultName = ""
        TypeSettingsPages.chooseExportFile = { name, extensions, _ in defaultName = name; return extensions == ["ini"] ? path : nil }
        TypeSettingsPages.chooseImportFile = { extensions, _ in extensions == ["ini"] ? path : nil }
        var ascertained: (to: String, file: String, colors: [String])?
        TypeSettingsPages.runTypeAscertainDialog = { dialog, _ in
            ascertained = ((dialog.page.control("IDC_RADIO_TYPE_TO") as? NSButton)?.title ?? "", dialog.page.text("IDC_STATIC_TYPE_FILE"),
                           dialog.page.itemTitles("IDC_COMBO_COLORS"))
            XCTAssertTrue(dialog.page.isChecked("IDC_RADIO_TYPE_ADD"), "新規追加が既定")
            dialog.ok()
            return true
        }
        let dialog = try XCTUnwrap(TypeListDialog(selectedIndex: cpp, enableTempChange: true))
        dialog.button("IDC_BUTTON_EXPORT")
        XCTAssertEqual(defaultName, "C/C++.ini")
        XCTAssertTrue(messages.last?.hasPrefix("ファイルをエクスポートしました。") ?? false, "\(messages)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))

        dialog.button("IDC_BUTTON_IMPORT")
        XCTAssertEqual(ascertained?.to, "C/C++(B)")
        XCTAssertEqual(ascertained?.file, "C/C++")
        XCTAssertEqual(ascertained?.colors.first, "--そのままインポート--")
        XCTAssertEqual(dialog.types.count, countBefore + 1)
        XCTAssertEqual(dialog.types.last?.name, "C/C++")
        XCTAssertEqual(dialog.selectedIndex, countBefore)
        XCTAssertTrue(messages.last?.hasPrefix("ファイルをインポートしました。") ?? false, "\(messages)")

        // 確認ダイアログの選択：上書き・タイプの色
        let ascertain = try XCTUnwrap(TypeAscertainDialog(typeNameTo: "A", typeNameFile: "B", colorFiles: ["x.col"]))
        ascertain.page.setChecked("IDC_RADIO_TYPE_TO", true)
        (ascertain.page.control("IDC_COMBO_COLORS") as? NSPopUpButton)?.selectItem(withTag: 2)
        ascertain.ok()
        XCTAssertEqual(ascertain.choice, TypeAscertainDialog.Choice(addNew: false, colorType: 2, colorFile: ""))
        (ascertain.page.control("IDC_COMBO_COLORS") as? NSPopUpButton)?.selectItem(withTag: EditorCore.maxTypeSettings)
        ascertain.ok()
        XCTAssertEqual(ascertain.choice, TypeAscertainDialog.Choice(addNew: false, colorType: -1, colorFile: "x.col"))
    }

    /// 設定 > タイプ別設定一覧（F_TYPE_LIST）：一時適用はこの文書だけ、設定変更はそのタイプの設定を開く
    func testCommandFromEditor() throws {
        let dir = TestCore.home.appendingPathComponent("type-list-cmd")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("a.txt")
        try "abc\n".write(to: url, atomically: true, encoding: .utf8)
        let document = try XCTUnwrap(EditorDocument())
        XCTAssertEqual(document.open(path: url.path), .success)
        let view = EditorTextView(document: document)
        XCTAssertEqual(CommandTable.selector(for: 31110), #selector(EditorTextView.showTypeList(_:)))
        let savedRun = TypeSettingsPages.runTypeListDialog
        defer { TypeSettingsPages.runTypeListDialog = savedRun }
        let cpp = self.cpp
        var selected = -1
        TypeSettingsPages.runTypeListDialog = { dialog, _ in
            selected = dialog.selectedIndex
            dialog.button("IDC_BUTTON_TEMPCHANGE")
            return true
        }
        let text = document.typeIndex
        XCTAssertTrue(CommandTable.perform(31110, from: view))
        XCTAssertEqual(selected, text, "この文書のタイプを選んで開く")
        XCTAssertEqual(document.typeIndex, text)

        TypeSettingsPages.runTypeListDialog = { dialog, _ in
            dialog.page.list("IDC_LIST_TYPES")?.select(cpp)
            dialog.button("IDC_BUTTON_TEMPCHANGE")
            return true
        }
        XCTAssertTrue(CommandTable.perform(31110, from: view))
        XCTAssertEqual(document.typeIndex, cpp, "一時適用")
        XCTAssertEqual(document.typeName, "C/C++")

        TypeSettingsPages.runTypeListDialog = { dialog, _ in
            dialog.button("IDOK")
            return true
        }
        XCTAssertTrue(CommandTable.perform(31110, from: view))
        let shown = try XCTUnwrap(TypeSettingsWindowController.shared)
        XCTAssertEqual(shown.typeIndex, cpp, "設定変更：そのタイプの設定を開く")
        shown.cancel(nil)
    }
}

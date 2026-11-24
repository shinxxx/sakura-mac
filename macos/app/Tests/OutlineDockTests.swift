// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge
import XCTest

/// アウトライン解析のドッキング（计划第 42 步第 3 个 PR。原版 CDlgFuncList のドッキング部分）的测试。
///
/// 編集窓口（EditorContainerView）の上下左右に置く、大きさ、キャプションのボタン、
/// ドッキング中の動作（シングルクリックでジャンプ、Esc で編集画面へ）、設定（共通設定・タイプ別設定、同期、統一）、
/// ファイルを開いたときに開く（原版 ChangeLayout）。
final class OutlineDockTests: XCTestCase {
    private var window: NSWindow!
    private var container: EditorContainerView!
    private var view: EditorTextView!
    private var messages: [String?] = []
    private var saved: [String: String] = [:]
    private var directory: URL!

    private static let commonKeys = ["nOutlineDockSet", "bOutlineDockSync", "bOutlineDockDisp", "eOutlineDockSide", "xyOutlineDock",
                                     "nDockOutline", "bAutoCloseDlgFuncList", "bFunclistSetFocusOnJump", "bRememberOutlineWindowPos"]

    override func setUpWithError() throws {
        _ = TestCore.home
        _ = NSApplication.shared
        OutlineWindowController.hidesOnDeactivate = false
        messages = []
        EditorTextView.messageHandler = { [unowned self] in messages.append($0) }
        for key in Self.commonKeys {
            saved[key] = EditorCore.commonSetting(section: "Common", key: key) ?? ""
        }
        _ = EditorCore.setCommonSettings(["nOutlineDockSet": "0", "bOutlineDockSync": "0", "bOutlineDockDisp": "0", "eOutlineDockSide": "0",
                                          "xyOutlineDock": "0,0,0,0", "bAutoCloseDlgFuncList": "0", "bFunclistSetFocusOnJump": "0"],
                                         section: "Common")
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("outline-dock-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        (window, container, view) = try Self.makeWindow()
    }

    override func tearDown() {
        view.outlinePanel?.close()
        EditorTextView.messageHandler = nil
        _ = EditorCore.setCommonSettings(saved, section: "Common")
        window.close()
        window = nil
        view = nil
        try? FileManager.default.removeItem(at: directory)
    }

    static func makeWindow() throws -> (NSWindow, EditorContainerView, EditorTextView) {
        let document = try XCTUnwrap(EditorDocument())
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 600, height: 400),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let scroll = NSScrollView()
        let view = EditorTextView(document: document)
        scroll.documentView = view
        let container = EditorContainerView(editor: scroll)
        window.contentView = container
        window.orderFront(nil)	// 見えている編集窓口（原版 IsWindowVisible：閉じたときに表示の設定を OFF にする）
        container.layoutSubtreeIfNeeded()
        window.makeFirstResponder(view)
        return (window, container, view)
    }

    private func open(_ name: String, _ text: String, in view: EditorTextView? = nil) throws {
        let url = directory.appendingPathComponent(name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        let target = view ?? self.view!
        XCTAssertEqual(target.document.open(path: url.path), .success)
        target.setCaret(EditorPosition(line: 0, column: 0))
    }

    private var panel: OutlineWindowController {
        get throws { try XCTUnwrap(view.outlinePanel) }
    }

    private static let text = "■第一章\n□節 A\n■第二章\n□節 B\n"

    /// ▼ メニューのドッキング配置を選ぶ
    private func choose(_ title: String) throws {
        let menu = try panel.makeMenu(dropDown: true)
        let item = try XCTUnwrap(menu.items.first { $0.title == title }, title)
        XCTAssertTrue(item.isEnabled, title)
        _ = item.target?.perform(item.action, with: item)
    }

    // MARK: - 配置

    func testDockLeftRightTopBottomAndFloat() throws {
        try open("a.txt", Self.text)
        view.showOutline(nil)
        XCTAssertFalse(try panel.isDocking)
        try choose("左ドッキング(L)")
        let dock = try XCTUnwrap(container.dock, "左にドッキングした")
        XCTAssertEqual(dock.side, .left)
        XCTAssertFalse(try panel.window?.isVisible ?? true, "フローティングの窓口は閉じた")
        container.layoutSubtreeIfNeeded()
        // 初回は 1/3（原版 GetIdealStretch）
        XCTAssertEqual(dock.frame.width, (600.0 / 3).rounded(.down), accuracy: 1)
        XCTAssertEqual(container.editor.frame.minX, dock.frame.maxX, accuracy: 0.5)
        XCTAssertEqual(EditorCore.commonSetting(section: "Common", key: "eOutlineDockSide"), "1")
        XCTAssertEqual(EditorCore.commonSetting(section: "Common", key: "bOutlineDockDisp"), "1")
        // ドッキング中は下のボタン・チェックボックスを隠す、ツリーは下まで
        let page = try panel.page
        for id in ["IDOK", "IDCANCEL", "IDC_BUTTON_COPY", "IDC_BUTTON_MENU", "IDC_BUTTON_WINSIZE", "IDC_CHECK_bAutoCloseDlgFuncList"] {
            XCTAssertTrue(page.control(id)?.isHidden ?? false, id)
        }
        let tree = try XCTUnwrap(page.control("IDC_TREE_FL"))
        XCTAssertEqual(tree.frame.maxY, page.view.bounds.height, accuracy: 0.5)
        XCTAssertFalse(page.control("IDC_COMBO_nSortType")?.isHidden ?? true, "順序は見える")

        try choose("右ドッキング(R)")
        container.layoutSubtreeIfNeeded()
        XCTAssertEqual(container.dock?.side, .right)
        XCTAssertEqual(container.dock?.frame.maxX ?? 0, container.bounds.width, accuracy: 0.5)
        try choose("下ドッキング(B)")
        container.layoutSubtreeIfNeeded()
        XCTAssertEqual(container.dock?.side, .bottom)
        XCTAssertEqual(container.dock?.frame.maxY ?? 0, container.bounds.height, accuracy: 0.5)
        XCTAssertEqual(container.dock?.frame.height ?? 0, (400.0 / 3).rounded(.down), accuracy: 1)
        try choose("上ドッキング(T)")
        container.layoutSubtreeIfNeeded()
        XCTAssertEqual(container.dock?.side, .top)
        XCTAssertEqual(container.dock?.frame.minY ?? -1, 0, accuracy: 0.5)

        // フローティングへ：ドッキングは消えて窓口
        try choose("フローティング(F)")
        XCTAssertNil(container.dock)
        XCTAssertTrue(try panel.window?.isVisible ?? false)
        XCTAssertEqual(EditorCore.commonSetting(section: "Common", key: "eOutlineDockSide"), "0")
        // ドッキング禁止：窓口のまま
        try choose("ドッキング禁止(I)")
        XCTAssertNil(container.dock)
        XCTAssertEqual(EditorCore.commonSetting(section: "Common", key: "eOutlineDockSide"), "-1")
    }

    /// ドラッグのドロップ先（原版 GetDropRect）：編集窓口の端（カーソルの大きさ以内）はドッキング、それ以外はフローティング、Ctrl はフローティング
    func testDropRect() throws {
        try open("a.txt", Self.text)
        view.showOutline(nil)
        let panel = try panel
        let space = container.dockSpaceOnScreen
        let start = NSPoint(x: space.midX, y: space.midY)
        var r = panel.dropRect(dragStart: start, drop: NSPoint(x: space.minX + 5, y: space.midY), forceFloat: false)
        XCTAssertEqual(r.0, .left)
        XCTAssertEqual(r.1.width, (space.width / 3).rounded(.down), accuracy: 1)
        XCTAssertEqual(r.1.minX, space.minX, accuracy: 0.5)
        r = panel.dropRect(dragStart: start, drop: NSPoint(x: space.maxX - 5, y: space.midY), forceFloat: false)
        XCTAssertEqual(r.0, .right)
        XCTAssertEqual(r.1.maxX, space.maxX, accuracy: 0.5)
        r = panel.dropRect(dragStart: start, drop: NSPoint(x: space.midX, y: space.maxY - 5), forceFloat: false)
        XCTAssertEqual(r.0, .top)
        XCTAssertEqual(r.1.maxY, space.maxY, accuracy: 0.5)
        r = panel.dropRect(dragStart: start, drop: NSPoint(x: space.midX, y: space.minY + 5), forceFloat: false)
        XCTAssertEqual(r.0, .bottom)
        r = panel.dropRect(dragStart: start, drop: NSPoint(x: space.minX + 5, y: space.midY), forceFloat: true)
        XCTAssertEqual(r.0, .float, "Ctrl はフローティング")
        r = panel.dropRect(dragStart: start, drop: NSPoint(x: space.midX + 10, y: space.midY), forceFloat: false)
        XCTAssertEqual(r.0, .float)
        // ドロップでドッキング
        let left = panel.dropRect(dragStart: start, drop: NSPoint(x: space.minX + 5, y: space.midY), forceFloat: false)
        panel.drop(side: left.0, rect: left.1)
        XCTAssertEqual(container.dock?.side, .left)
        // ドッキングから外へドロップ：フローティングの窓口はドロップした場所に
        let docked = try self.panel
        let far = NSPoint(x: space.midX + 20, y: space.midY - 20)	// 画面の中（画面の外だと窓口が画面に収められる）
        let float = docked.dropRect(dragStart: start, drop: far, forceFloat: false)
        XCTAssertEqual(float.0, .float)
        docked.drop(side: float.0, rect: float.1)
        XCTAssertNil(container.dock)
        XCTAssertEqual(try self.panel.window?.frame.minX ?? 0, float.1.minX, accuracy: 1)
    }

    /// ドッキングの外観：キャプションの文字は切れない・ボタンと重ならない、ボタンはキャプションの中、
    /// ツリー・リストは下まで、色は編集画面の文字の色・背景色、選んだ行は反転（原版 SyncColor）
    func testDockedAppearance() throws {
        try open("a.txt", Self.text)
        view.showOutline(nil)
        try choose("左ドッキング(L)")
        let panel = try panel
        let dock = try XCTUnwrap(container.dock)
        container.layoutSubtreeIfNeeded()
        dock.layout()
        dock.caption.layout()
        let caption = dock.caption
        // すべてのアウトラインの名前がキャプションに入る（既定の幅：600 の 1/3）
        for title in ["C++ メソッドツリー", "テキスト トピックツリー", "Visual Basic アウトライン", "WZ階層付テキスト", "アセンブラ アウトライン"] {
            caption.title.stringValue = title
            XCTAssertLessThanOrEqual(ceil(caption.title.fittingSize.width), caption.title.frame.width + 0.5, title)
        }
        for b in [caption.closeButton, caption.menuButton, caption.updateButton] {
            XCTAssertFalse(b.frame.intersects(caption.title.frame), "ボタンとタイトルが重ならない")
            XCTAssertTrue(caption.bounds.contains(b.frame), "ボタンはキャプションの中")
        }
        XCTAssertFalse(caption.closeButton.frame.intersects(caption.menuButton.frame))
        XCTAssertFalse(caption.menuButton.frame.intersects(caption.updateButton.frame))
        XCTAssertEqual(caption.frame.height, OutlineDockView.captionHeight)
        // 中身はキャプションの下、分割バーの内側
        XCTAssertEqual(dock.content.frame.minY, caption.frame.maxY, accuracy: 0.5)
        XCTAssertFalse(dock.content.frame.intersects(dock.splitterRect))
        // ツリーは下まで
        let tree = try XCTUnwrap(panel.page.control("IDC_TREE_FL"))
        XCTAssertEqual(tree.frame.maxY, panel.page.view.bounds.height, accuracy: 0.5)
        XCTAssertEqual(tree.frame.maxX, panel.page.view.bounds.width, accuracy: 0.5)
        // 色
        let text = view.color(.text)
        let back = EditorTextView.nsColor(text.back), fore = EditorTextView.nsColor(text.text)
        XCTAssertEqual(panel.treeView.backgroundColor.usingColorSpace(.sRGB), back.usingColorSpace(.sRGB))
        XCTAssertEqual(panel.treeView.textColor?.usingColorSpace(.sRGB), fore.usingColorSpace(.sRGB))
        let row = panel.treeView.selectedRow
        XCTAssertGreaterThanOrEqual(row, 0, "キャレットの位置の項目を選んでいる")
        let cell = try XCTUnwrap(panel.treeView.view(atColumn: 0, row: row, makeIfNecessary: true) as? OutlineCell)
        cell.backgroundStyle = .emphasized
        XCTAssertEqual(cell.textField?.textColor?.usingColorSpace(.sRGB), OutlineRowView.inverted(fore).usingColorSpace(.sRGB), "選んだ行の文字は反転")
        let inv = try XCTUnwrap(OutlineRowView.inverted(NSColor(srgbRed: 1, green: 0.98, blue: 0.94, alpha: 1)).usingColorSpace(.sRGB))
        XCTAssertEqual(inv.redComponent, 0, accuracy: 0.01)
        XCTAssertEqual(inv.blueComponent, 0.06, accuracy: 0.01)
        // フローティングに戻すと標準の色
        try choose("フローティング(F)")
        XCTAssertNil(try self.panel.treeView.textColor)
    }

    /// キャプションのボタンはマウスが上にあるとき強調（原版 OnNcPaint のハイライト）
    func testCaptionButtonHover() throws {
        try open("a.txt", Self.text)
        view.showOutline(nil)
        try choose("左ドッキング(L)")
        let button = try XCTUnwrap(container.dock?.caption.closeButton)
        XCTAssertFalse(button.isHovered)
        let event = try XCTUnwrap(NSEvent.enterExitEvent(with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0,
                                                         windowNumber: window.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil))
        button.mouseEntered(with: event)
        XCTAssertTrue(button.isHovered)
        XCTAssertEqual(button.contentTintColor, NSColor.selectedMenuItemTextColor)
        button.mouseExited(with: event)
        XCTAssertFalse(button.isHovered)
    }

    func testSplitterSizeIsSaved() throws {
        try open("a.txt", Self.text)
        view.showOutline(nil)
        try choose("左ドッキング(L)")
        try panel.dockSizeChanged(150)
        container.layoutSubtreeIfNeeded()
        XCTAssertEqual(container.dock?.frame.width ?? 0, 150, accuracy: 0.5)
        XCTAssertEqual(EditorCore.commonSetting(section: "Common", key: "xyOutlineDock"), "150,0,0,0")
        // 小さすぎる・大きすぎるときは最小の大きさを残す
        try panel.dockSizeChanged(10)
        container.layoutSubtreeIfNeeded()
        XCTAssertEqual(container.dock?.frame.width ?? 0, OutlineDockSettings.minSize, accuracy: 0.5)
    }

    func testCaptionButtons() throws {
        try open("a.txt", Self.text)
        view.showOutline(nil)
        try choose("左ドッキング(L)")
        let caption = try XCTUnwrap(container.dock?.caption)
        XCTAssertEqual(caption.title.stringValue, "テキスト トピックツリー")
        XCTAssertEqual(caption.closeButton.toolTip, "閉じる")
        XCTAssertEqual(caption.menuButton.toolTip, "ウィンドウの位置")
        XCTAssertEqual(caption.updateButton.toolTip, "更新")
        // 更新：再解析
        _ = view.document.insert("■第三章\n", at: view.document.endPosition)
        caption.updateButton.performClick(nil)
        XCTAssertEqual(try panel.result.items.count, 5)
        // 閉じる：ドッキングがなくなり、表示の設定は OFF
        caption.closeButton.performClick(nil)
        XCTAssertNil(container.dock)
        XCTAssertNil(view.outlinePanel)
        XCTAssertEqual(EditorCore.commonSetting(section: "Common", key: "bOutlineDockDisp"), "0")
    }

    /// ドッキング中はシングルクリックでジャンプ（フォーカスはそのまま）、ダブルクリック・Esc は編集画面へ
    func testDockedJump() throws {
        try open("a.txt", Self.text)
        view.showOutline(nil)
        try choose("左ドッキング(L)")
        let panel = try panel
        let tree = panel.treeView
        tree.expandItem(nil, expandChildren: true)
        let row = try XCTUnwrap((0..<tree.numberOfRows).first { (tree.item(atRow: $0) as? OutlineTreeItem)?.node.label == "■第二章" })
        tree.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        panel.singleClicked()
        XCTAssertEqual(view.caret.line, 2)
        window.makeFirstResponder(tree)
        panel.cancel()
        XCTAssertTrue(window.firstResponder === view, "Esc で編集画面へ")
    }

    // MARK: - ファイルを開いたとき（原版 ChangeLayout / Refresh）

    func testDockedOutlineOpensWithNewWindow() throws {
        try open("a.txt", Self.text)
        view.showOutline(nil)
        try choose("右ドッキング(R)")
        // 別の窓口でファイルを開くと、ドッキングしたアウトラインも開く
        let (window2, container2, view2) = try Self.makeWindow()
        defer { view2.outlinePanel?.close(); window2.close() }
        try open("b.txt", "■X\n", in: view2)
        view2.refreshOutline()
        XCTAssertEqual(container2.dock?.side, .right)
        XCTAssertEqual(view2.outlinePanel?.result.items.count, 1)
        // フローティングは開かない（原版：ファイル切替ではフローティングは開かない）
        let (window3, container3, view3) = try Self.makeWindow()
        defer { view3.outlinePanel?.close(); window3.close() }
        _ = EditorCore.setCommonSetting("0", section: "Common", key: "eOutlineDockSide")
        try open("c.txt", "■Y\n", in: view3)
        view3.refreshOutline()
        XCTAssertNil(container3.dock)
        XCTAssertNil(view3.outlinePanel)
    }

    // MARK: - 設定（同期、タイプ別、統一）

    func testSyncMovesOtherWindows() throws {
        try open("a.txt", Self.text)
        view.showOutline(nil)
        try choose("左ドッキング(L)")
        let (window2, container2, view2) = try Self.makeWindow()
        defer { view2.outlinePanel?.close(); window2.close() }
        try open("b.txt", "■X\n", in: view2)
        view2.refreshOutline()
        XCTAssertEqual(container2.dock?.side, .left)
        // 同期しない：ほかの窓口はそのまま
        try choose("下ドッキング(B)")
        XCTAssertEqual(container2.dock?.side, .left)
        // 同期する
        try choose("ドッキング配置を同期(S)")
        XCTAssertEqual(EditorCore.commonSetting(section: "Common", key: "bOutlineDockSync"), "1")
        XCTAssertEqual(container2.dock?.side, .bottom, "同期をオンにしたら合わせる")
        try choose("右ドッキング(R)")
        XCTAssertEqual(container2.dock?.side, .right)
        // 閉じると、ほかの窓口も閉じる
        container.dock?.caption.closeButton.performClick(nil)
        XCTAssertNil(container2.dock)
    }

    func testTypeSpecificDocking() throws {
        try open("a.txt", Self.text)
        let section = "Types(\(view.document.typeIndex))"
        let before = ["bOutlineDockDisp", "eOutlineDockSide", "xyOutlineDock", "nDockOutline"].reduce(into: [String: String]()) {
            $0[$1] = EditorCore.commonSetting(section: section, key: $1) ?? ""
        }
        defer { _ = EditorCore.setCommonSettings(before, section: section) }
        view.showOutline(nil)
        let menu = try panel.makeMenu(dropDown: true)
        XCTAssertEqual(menu.items.first { $0.title == "ドッキング配置を共通継承(C)" }?.state, .on)
        try choose("ドッキング配置をタイプ別継承(Y)")
        XCTAssertEqual(EditorCore.commonSetting(section: "Common", key: "nOutlineDockSet"), "1")
        // このタイプの設定は「表示しない」なので閉じる（原版 ChangeLayout）。開き直して左に
        XCTAssertNil(view.outlinePanel)
        view.showOutline(nil)
        try choose("左ドッキング(L)")
        XCTAssertEqual(EditorCore.commonSetting(section: section, key: "eOutlineDockSide"), "1", "タイプ別設定に記憶")
        XCTAssertEqual(EditorCore.commonSetting(section: "Common", key: "eOutlineDockSide"), "0", "共通設定は変わらない")
        // 別のタイプのファイル（C）を別の窓口で開いても、そのタイプはフローティングなので開かない
        let (window2, container2, view2) = try Self.makeWindow()
        defer { view2.outlinePanel?.close(); window2.close() }
        try open("b.c", "int f(void)\n{\n}\n", in: view2)
        view2.refreshOutline()
        XCTAssertNil(container2.dock)
    }

    func testUnify() throws {
        try open("a.txt", Self.text)
        let types = EditorCore.typeSettings.map(\.index)
        let before = types.map { index in
            ["bOutlineDockDisp", "eOutlineDockSide", "xyOutlineDock"].reduce(into: [String: String]()) {
                $0[$1] = EditorCore.commonSetting(section: "Types(\(index))", key: $1) ?? ""
            }
        }
        defer { for (i, index) in types.enumerated() { _ = EditorCore.setCommonSettings(before[i], section: "Types(\(index))") } }
        view.showOutline(nil)
        try choose("左ドッキング(L)")
        try panel.dockSizeChanged(170)
        OutlineWindowController.confirmHandler = { message in
            XCTAssertEqual(message, "現在の画面のドッキング配置情報をすべての共通設定・タイプ別設定にコピーして統一します。\n（現在開いている他画面の状態も統一します。）\n")
            return true
        }
        defer { OutlineWindowController.confirmHandler = nil }
        try choose("継承情報を統一(U)")
        for index in types {
            XCTAssertEqual(EditorCore.commonSetting(section: "Types(\(index))", key: "eOutlineDockSide"), "1", "Types(\(index))")
            XCTAssertEqual(EditorCore.commonSetting(section: "Types(\(index))", key: "bOutlineDockDisp"), "1")
            XCTAssertEqual(EditorCore.commonSetting(section: "Types(\(index))", key: "xyOutlineDock")?.hasPrefix("170,"), true)
        }
    }
}

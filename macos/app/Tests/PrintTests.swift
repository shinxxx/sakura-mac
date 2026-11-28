// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge
import XCTest

/// 印刷（第 47 步）的测试：印刷ページ設定ダイアログ、印刷プレビュー、印刷（NSPrintOperation）、メニューの機能。
///
/// 排版（文字の位置・折り返し・行番号・ヘッダー・フッター・段組）は核心库の测试（test-mac-print.cpp、Windows 官方版との対照）が確かめる。
/// ここは App の側：対話框の値と動き、プレビューの操作バー、印刷の情報、描画。
/// 対話框・印刷のパネルは測試用に差し替える（PrintPreviewController.runPrintOperation 等）。設定は終わったら元に戻す
final class PrintTests: XCTestCase {
    private var documents: [SakuraDocument] = []
    private var savedSettings: [PrintSetting] = []
    private var savedInput: ((String, String, Int, String) -> String?)!
    private var savedChooseFont: ((NSFont, NSWindow?) -> NSFont?)!
    private var savedRunPrint: ((NSPrintOperation, NSWindow?, @escaping (Bool) -> Void) -> Void)!
    private var savedPageLayout: ((NSPrintInfo, NSWindow?) -> Bool)!
    private var savedSettingDialog: ((PrintSettingDialog, NSWindow?) -> Bool)!

    override func setUpWithError() throws {
        _ = TestCore.home
        _ = NSApplication.shared
        savedSettings = (0 ..< PrintCore.settingCount).map { PrintCore.setting(at: $0) }
        savedInput = CommonSettingsPages.input
        savedChooseFont = CommonSettingsPages.chooseFont
        savedRunPrint = PrintPreviewController.runPrintOperation
        savedPageLayout = PrintPreviewController.runPageLayout
        savedSettingDialog = PrintPreviewController.runPrintSettingDialog
        CommonSettingsPages.input = { _, _, _, _ in
            XCTFail("入力の対話框")
            return nil
        }
        PrintPreviewController.runPrintOperation = { _, _, completion in
            XCTFail("印刷のパネル")
            completion(false)
        }
    }

    override func tearDown() {
        for (index, setting) in savedSettings.enumerated() {
            PrintCore.setSetting(setting, at: index)
        }
        CommonSettingsPages.input = savedInput
        CommonSettingsPages.chooseFont = savedChooseFont
        PrintPreviewController.runPrintOperation = savedRunPrint
        PrintPreviewController.runPageLayout = savedPageLayout
        PrintPreviewController.runPrintSettingDialog = savedSettingDialog
        for document in documents {
            document.editorWindowController?.printPreview?.close()
            document.fileSafety.stop()
            for controller in document.windowControllers {
                controller.window?.orderOut(nil)
                document.removeWindowController(controller)
            }
        }
        documents = []
    }

    // MARK: - 補助

    private func makeDocument(lines: Int = 100) throws -> (SakuraDocument, EditorWindowController) {
        let document = SakuraDocument()
        document.makeWindowControllers()
        document.fileSafety.stop()
        documents.append(document)
        let controller = try XCTUnwrap(document.editorWindowController)
        let text = (1 ... lines).map { "line \($0) 印刷のテスト" }.joined(separator: "\n") + "\n"
        controller.textView.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
        controller.window?.setContentSize(NSSize(width: 900, height: 700))
        return (document, controller)
    }

    private func openPreview(_ controller: EditorWindowController) throws -> PrintPreviewController {
        controller.togglePrintPreview()
        return try XCTUnwrap(controller.printPreview, "プレビューを開いた")
    }

    /// 設定 index を変える
    private func modify(_ index: Int = 0, _ change: (PrintSetting) -> Void) {
        let setting = PrintCore.setting(at: index)
        change(setting)
        PrintCore.setSetting(setting, at: index)
    }

    private func label(_ page: PropPage, _ id: String) -> String {
        page.text(id)
    }

    // MARK: - 印刷ページ設定（原版 CDlgPrintSetting）

    /// 開いたとき：今の設定の値、8 つの設定名、用紙の一覧、範囲、行あたりの文字数・行数、ポイント数
    func testPrintSettingDialogShowsSetting() throws {
        let dialog = try XCTUnwrap(PrintSettingDialog(currentIndex: 0, lineNumberColumns: 3))
        let page = dialog.page
        let s = PrintCore.setting(at: 0)
        XCTAssertEqual(page.itemTitles("IDC_COMBO_SETTINGNAME"), (0 ..< 8).map { PrintCore.setting(at: $0).name })
        XCTAssertEqual(page.selectedTag("IDC_COMBO_SETTINGNAME"), 0)
        XCTAssertEqual(page.int("IDC_EDIT_FONTHEIGHT"), s.fontHeight)
        XCTAssertEqual(page.int("IDC_EDIT_LINESPACE"), s.lineSpacing)
        XCTAssertEqual(page.int("IDC_EDIT_DANSUU"), s.columns)
        XCTAssertEqual(page.int("IDC_EDIT_DANSPACE"), s.columnSpace / 10)
        XCTAssertEqual(page.int("IDC_EDIT_MARGINTY"), s.marginTop / 10)
        XCTAssertEqual(page.int("IDC_EDIT_MARGINBY"), s.marginBottom / 10)
        XCTAssertEqual(page.int("IDC_EDIT_MARGINLX"), s.marginLeft / 10)
        XCTAssertEqual(page.int("IDC_EDIT_MARGINRX"), s.marginRight / 10)
        XCTAssertEqual(page.selectedTag("IDC_COMBO_PAPER"), s.paperSize)
        XCTAssertEqual(page.itemTitles("IDC_COMBO_PAPER"), PrintCore.papers.map(\.name))
        XCTAssertTrue(page.isChecked("IDC_RADIO_PORTRAIT"))
        XCTAssertFalse(page.isChecked("IDC_RADIO_LANDSCAPE"))
        XCTAssertEqual(page.isChecked("IDC_CHECK_WORDWRAP"), s.wordWrap)
        XCTAssertEqual(page.isChecked("IDC_CHECK_LINENUMBER"), s.lineNumber)
        XCTAssertEqual(page.text("IDC_EDIT_HEAD1"), s.headers[0])
        XCTAssertEqual(page.text("IDC_EDIT_FOOT2"), s.footers[1])
        // フォントの一覧に設定のフォント（Windows の名前）もある
        XCTAssertTrue(dialog.fontNames.contains(s.fontHan))
        XCTAssertEqual(page.itemTitles("IDC_COMBO_FONT_HAN")[page.selectedIndex("IDC_COMBO_FONT_HAN")], s.fontHan)
        // 計算
        var width = 0
        var height = 0
        XCTAssertTrue(PrintCore.paperSize(s.paperSize, orientation: s.orientation, width: &width, height: &height))
        XCTAssertEqual(label(page, "IDC_STATIC_ENABLECOLUMNS"), String(PrintCore.printableColumns(s, paperWidth: width, lineNumberColumns: 0)))
        XCTAssertEqual(label(page, "IDC_STATIC_ENABLELINES"), String(PrintCore.printableLines(s, paperHeight: height)))
        XCTAssertEqual(label(page, "IDC_STATIC_FONTSIZE"), PrintCore.fontSizeText(s.fontHeight))
        XCTAssertTrue(page.isEnabled("IDOK"))
        XCTAssertTrue(page.isEnabled("IDC_BUTTON_HELP"), "第 49 步：ヘルプ")
        // ヘッダー・フッターのフォントは指定なし
        XCTAssertFalse(page.isChecked("IDC_CHECK_USE_FONT_HEAD"))
        XCTAssertFalse(page.isEnabled("IDC_CHECK_USE_FONT_HEAD"))
        XCTAssertEqual(page.text("IDC_STATIC_FONT_HEAD"), "")
    }

    /// 数値の欄：範囲の外は端に直す（フォント高は 2 桁になるまで直さない）。行番号・用紙・向きで桁数と行数が変わる。印字できる場所がないと OK を押せない
    func testPrintSettingDialogCorrectsAndCalculates() throws {
        let dialog = try XCTUnwrap(PrintSettingDialog(currentIndex: 0, lineNumberColumns: 5))
        let page = dialog.page
        func type(_ id: String, _ text: String) {
            page.setText(id, text)
            page.onChange?(id)
        }
        type("IDC_EDIT_DANSUU", "9")
        XCTAssertEqual(page.int("IDC_EDIT_DANSUU"), 4, "段数は 4 まで")
        type("IDC_EDIT_DANSUU", "0")
        XCTAssertEqual(page.int("IDC_EDIT_DANSUU"), 1, "段数は 1 から")
        type("IDC_EDIT_MARGINTY", "70")
        XCTAssertEqual(page.int("IDC_EDIT_MARGINTY"), 50, "余白は 50 mm まで")
        type("IDC_EDIT_FONTHEIGHT", "1")
        XCTAssertEqual(page.text("IDC_EDIT_FONTHEIGHT"), "1", "1 桁のうちは直さない")
        type("IDC_EDIT_FONTHEIGHT", "12")
        XCTAssertEqual(page.int("IDC_EDIT_FONTHEIGHT"), 12)
        XCTAssertEqual(label(page, "IDC_STATIC_FONTSIZE"), PrintCore.fontSizeText(12))
        type("IDC_EDIT_FONTHEIGHT", "500")
        XCTAssertEqual(page.int("IDC_EDIT_FONTHEIGHT"), 200, "フォント高は 200 まで")
        type("IDC_EDIT_FONTHEIGHT", "24")

        let columns = Int(label(page, "IDC_STATIC_ENABLECOLUMNS")) ?? -1
        page.setChecked("IDC_CHECK_LINENUMBER", true)
        page.onChange?("IDC_CHECK_LINENUMBER")
        XCTAssertEqual(Int(label(page, "IDC_STATIC_ENABLECOLUMNS")), columns - 5, "行番号（5 桁）の分減る（原版 CalculatePrintableColumns）")
        let lines = Int(label(page, "IDC_STATIC_ENABLELINES")) ?? -1
        page.setChecked("IDC_RADIO_LANDSCAPE", true)
        page.onChange?("IDC_RADIO_LANDSCAPE")
        XCTAssertLessThan(Int(label(page, "IDC_STATIC_ENABLELINES")) ?? -1, lines, "横向きは行が減る")
        XCTAssertGreaterThan(Int(label(page, "IDC_STATIC_ENABLECOLUMNS")) ?? -1, columns - 5, "横向きは桁が増える")

        // 印字できる場所がない：4 段・隙間 30 mm・余白 50 mm・フォント高 200 → 0 桁
        type("IDC_EDIT_DANSUU", "4")
        type("IDC_EDIT_DANSPACE", "30")
        type("IDC_EDIT_MARGINLX", "50")
        type("IDC_EDIT_MARGINRX", "50")
        type("IDC_EDIT_FONTHEIGHT", "200")
        XCTAssertEqual(label(page, "IDC_STATIC_ENABLECOLUMNS"), "0")
        XCTAssertFalse(page.isEnabled("IDOK"), "OK を押せない")
        type("IDC_EDIT_DANSUU", "1")
        XCTAssertTrue(page.isEnabled("IDOK"))
    }

    /// 設定の切り替え（前の設定は覚えておく）、設定名変更、OK で全部の設定を書き戻して設定の番号を文書に入れる
    func testPrintSettingDialogSwitchRenameAndApply() throws {
        let (document, _) = try makeDocument(lines: 3)
        let dialog = try XCTUnwrap(PrintSettingDialog(currentIndex: 0, lineNumberColumns: 3))
        let page = dialog.page
        page.setText("IDC_EDIT_LINESPACE", "77")
        page.onChange?("IDC_EDIT_LINESPACE")
        page.select("IDC_COMBO_SETTINGNAME", 2)
        page.onChange?("IDC_COMBO_SETTINGNAME")
        XCTAssertEqual(dialog.selectedIndex, 2)
        XCTAssertEqual(page.int("IDC_EDIT_LINESPACE"), PrintCore.setting(at: 2).lineSpacing)
        // 設定名変更（原版 STR_DLGPRNST1・STR_DLGPRNST2、32 文字まで）
        var asked: (String, String, Int, String)?
        CommonSettingsPages.input = { title, message, max, initial in
            asked = (title, message, max, initial)
            return "テスト用の設定"
        }
        page.onButton?("IDC_BUTTON_EDITSETTINGNAME")
        XCTAssertEqual(asked?.0, "設定名の変更")
        XCTAssertEqual(asked?.1, "設定の名称を入力してください。")
        XCTAssertEqual(asked?.2, 32)
        XCTAssertEqual(asked?.3, PrintCore.setting(at: 2).name)
        XCTAssertEqual(page.itemTitles("IDC_COMBO_SETTINGNAME")[2], "テスト用の設定")
        CommonSettingsPages.input = { _, _, _, _ in "" }
        page.onButton?("IDC_BUTTON_EDITSETTINGNAME")
        XCTAssertEqual(page.itemTitles("IDC_COMBO_SETTINGNAME")[2], "テスト用の設定", "空は変えない")
        page.setText("IDC_EDIT_HEAD3", "右 $f")

        var notified = 0
        let observer = NotificationCenter.default.addObserver(forName: PrintPreviewController.settingsDidChangeNotification,
                                                              object: nil, queue: nil) { _ in notified += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }
        dialog.onClose = {}
        page.onButton?("IDOK")
        XCTAssertTrue(dialog.result)
        XCTAssertEqual(document.editor.printSettingIndex, 0)
        dialog.apply(to: document.editor)
        XCTAssertEqual(PrintCore.setting(at: 0).lineSpacing, 77, "切り替える前の設定も書き戻す")
        XCTAssertEqual(PrintCore.setting(at: 2).name, "テスト用の設定")
        XCTAssertEqual(PrintCore.setting(at: 2).headers[2], "右 $f")
        XCTAssertEqual(document.editor.printSettingIndex, 2, "文書（タイプ別設定）の設定の番号")
        XCTAssertEqual(notified, 1, "PM_PRINTSETTING")
        document.editor.changePrintSettingIndex(0)
    }

    /// ヘッダーのフォント：初めは半角フォントのフォント高、選ぶと名前と大きさ、「使用」を外すと指定なし
    func testPrintSettingDialogHeaderFont() throws {
        let dialog = try XCTUnwrap(PrintSettingDialog(currentIndex: 0, lineNumberColumns: 3))
        let page = dialog.page
        var initial: NSFont?
        CommonSettingsPages.chooseFont = { font, _ in
            initial = font
            return NSFont(name: "Helvetica-Bold", size: 12)
        }
        page.onButton?("IDC_BUTTON_FONT_HEAD")
        let s = PrintCore.setting(at: 0)
        XCTAssertEqual(initial?.familyName, PrintCore.macFontFace(s.fontHan))
        XCTAssertEqual(Double(initial?.pointSize ?? 0), Double(s.fontHeight) * 72 / 254, accuracy: 0.01, "フォント高（1/10 mm）のポイント")
        XCTAssertTrue(page.isChecked("IDC_CHECK_USE_FONT_HEAD"))
        XCTAssertTrue(page.isEnabled("IDC_CHECK_USE_FONT_HEAD"))
        XCTAssertEqual(page.text("IDC_STATIC_FONT_HEAD"), "Helvetica(12pt/4.4mm)")
        let field = try XCTUnwrap(page.control("IDC_STATIC_FONT_HEAD") as? NSTextField)
        XCTAssertEqual(field.font?.familyName, "Helvetica", "そのフォントで表示")
        XCTAssertEqual(field.font?.pointSize, PropPage.font.pointSize, "大きさはダイアログの文字")
        // ヘッダーの高さが変わる
        let lines = Int(page.text("IDC_STATIC_ENABLELINES")) ?? 0
        XCTAssertNotEqual(lines, 0)
        // 「使用」を外す
        page.setChecked("IDC_CHECK_USE_FONT_HEAD", false)
        page.onChange?("IDC_CHECK_USE_FONT_HEAD")
        XCTAssertEqual(page.text("IDC_STATIC_FONT_HEAD"), "")
        XCTAssertFalse(page.isEnabled("IDC_CHECK_USE_FONT_HEAD"))
        dialog.onClose = {}
        page.onButton?("IDOK")
        let (document, _) = try makeDocument(lines: 1)
        dialog.apply(to: document.editor)
        XCTAssertEqual(PrintCore.setting(at: 0).headerFont.faceName, "")
        // もう一度選んで OK：太字が残る
        let again = try XCTUnwrap(PrintSettingDialog(currentIndex: 0, lineNumberColumns: 3))
        again.page.onButton?("IDC_BUTTON_FONT_FOOT")
        again.onClose = {}
        again.page.onButton?("IDOK")
        again.apply(to: document.editor)
        let footer = PrintCore.setting(at: 0).footerFont
        XCTAssertEqual(footer.faceName, "Helvetica")
        XCTAssertEqual(footer.pointSize, 120)
        XCTAssertTrue(footer.bold)
    }

    // MARK: - 印刷プレビュー（原版 CPrintPreview）

    /// 開く：窓の中身が操作バーと用紙になる。ページ・倍率の表示とボタン、戻るで編集画面に戻る
    func testPreviewPagesZoomAndBack() throws {
        let (document, controller) = try makeDocument(lines: 100)
        let window = try XCTUnwrap(controller.window)
        let editorContent = window.contentView
        let preview = try openPreview(controller)
        XCTAssertTrue(window.contentView === preview.container)
        XCTAssertTrue(window.firstResponder === preview.previewView)
        XCTAssertTrue(document.isPrintPreview)
        let count = preview.pageCount
        XCTAssertGreaterThanOrEqual(count, 2, "100 行は 2 ページ以上")
        let page = preview.page
        XCTAssertEqual(page.text("IDC_STATIC_PAGENUM"), "1/\(count)頁")
        XCTAssertEqual(page.text("IDC_STATIC_ZOOM"), "100 %")
        XCTAssertFalse(page.isEnabled("IDC_BUTTON_PREVPAGE"))
        XCTAssertTrue(page.isEnabled("IDC_BUTTON_NEXTPAGE"))
        XCTAssertTrue(page.isEnabled("IDC_CHECK_ANTIALIAS"), "「滑らか」は使える")
        XCTAssertFalse(page.isChecked("IDC_CHECK_ANTIALIAS"))
        let paper = PrintCore.papers.first { $0.paperID == PrintCore.setting(at: 0).paperSize }?.name ?? "?"
        XCTAssertEqual(page.text("IDC_STATIC_PAPER"), "\(paper)  縦")
        XCTAssertEqual(page.text("IDC_STATIC_PRNDEV"), PrintPreviewController.printerName(PrintCore.setting(at: 0)))

        page.onButton?("IDC_BUTTON_NEXTPAGE")
        XCTAssertEqual(page.text("IDC_STATIC_PAGENUM"), "2/\(count)頁")
        XCTAssertTrue(page.isEnabled("IDC_BUTTON_PREVPAGE"))
        for _ in 0 ..< count { page.onButton?("IDC_BUTTON_NEXTPAGE") }
        XCTAssertEqual(preview.currentPage, count - 1)
        XCTAssertFalse(page.isEnabled("IDC_BUTTON_NEXTPAGE"))
        page.onButton?("IDC_BUTTON_PREVPAGE")
        XCTAssertEqual(preview.currentPage, count - 2)

        // ページ番号を指定（原版 STR_ERR_DLGPRNPRVW5・4）。数字以外は何もしない、範囲の外は端
        var asked: (String, String, Int, String)?
        CommonSettingsPages.input = { title, message, max, initial in
            asked = (title, message, max, initial)
            return "1"
        }
        page.onButton?("IDC_BUTTON_DIRECTPAGE")
        XCTAssertEqual(asked?.0, "プレビューページ指定")
        XCTAssertEqual(asked?.1, "表示するページ番号を指定してください。(1 - \(count))")
        XCTAssertEqual(asked?.3, String(count - 1))
        XCTAssertEqual(preview.currentPage, 0)
        CommonSettingsPages.input = { _, _, _, _ in "2a" }
        page.onButton?("IDC_BUTTON_DIRECTPAGE")
        XCTAssertEqual(preview.currentPage, 0, "数字以外")
        CommonSettingsPages.input = { _, _, _, _ in "999" }
        page.onButton?("IDC_BUTTON_DIRECTPAGE")
        XCTAssertEqual(preview.currentPage, count - 1, "最後のページ")

        // 倍率：10 % ずつ、10～400 %
        let size = preview.previewView.contentSize
        page.onButton?("IDC_BUTTON_ZOOMUP")
        XCTAssertEqual(page.text("IDC_STATIC_ZOOM"), "110 %")
        XCTAssertEqual(preview.previewView.contentSize.width, size.width * 1.1, accuracy: 2)
        for _ in 0 ..< 40 { page.onButton?("IDC_BUTTON_ZOOMUP") }
        XCTAssertEqual(preview.zoom, 400)
        XCTAssertFalse(page.isEnabled("IDC_BUTTON_ZOOMUP"))
        for _ in 0 ..< 50 { page.onButton?("IDC_BUTTON_ZOOMDOWN") }
        XCTAssertEqual(preview.zoom, 10)
        XCTAssertEqual(page.text("IDC_STATIC_ZOOM"), "10 %")
        XCTAssertFalse(page.isEnabled("IDC_BUTTON_ZOOMDOWN"))
        XCTAssertTrue(page.isEnabled("IDC_BUTTON_ZOOMUP"))

        // 「滑らか」
        page.setChecked("IDC_CHECK_ANTIALIAS", true)
        page.onChange?("IDC_CHECK_ANTIALIAS")
        XCTAssertTrue(preview.previewView.antialias)

        // プレビュー中は印刷の機能だけ
        let save = NSMenuItem(title: "save", action: #selector(NSDocument.save(_:)), keyEquivalent: "")
        XCTAssertFalse(document.validateUserInterfaceItem(save))
        let toggle = NSMenuItem(title: "preview", action: #selector(SakuraDocument.printPreviewCommand(_:)), keyEquivalent: "")
        XCTAssertTrue(document.validateUserInterfaceItem(toggle))

        // 戻る
        page.onButton?("IDCANCEL")
        XCTAssertNil(controller.printPreview)
        XCTAssertTrue(window.contentView === editorContent, "編集画面に戻る")
        XCTAssertTrue(window.firstResponder === controller.textView)
        XCTAssertTrue(document.validateUserInterfaceItem(save))
    }

    /// プレビュー中に窓を閉じる操作はプレビューを閉じる（原版 SC_CLOSE）
    func testCloseWindowClosesPreview() throws {
        let (document, controller) = try makeDocument(lines: 3)
        _ = try openPreview(controller)
        var closed: Bool?
        let delegate = CloseDelegate { closed = $0 }
        document.shouldCloseWindowController(controller, delegate: delegate,
                                             shouldClose: #selector(CloseDelegate.document(_:shouldClose:contextInfo:)), contextInfo: nil)
        XCTAssertEqual(closed, false, "窓は閉じない")
        XCTAssertNil(controller.printPreview, "プレビューを閉じた")
    }

    final class CloseDelegate: NSObject {
        let done: (Bool) -> Void
        init(_ done: @escaping (Bool) -> Void) { self.done = done }
        @objc func document(_ document: NSDocument?, shouldClose: Bool, contextInfo: UnsafeMutableRawPointer?) {
            done(shouldClose)
        }
    }

    /// 印字できる場所がないときは開かずに「印刷ページ設定エラー:印字可能領域がありません」
    func testPreviewWithoutPrintableArea() throws {
        modify { s in
            s.columns = 4
            s.columnSpace = 300
            s.marginLeft = 500
            s.marginRight = 500
            s.fontHeight = 200
            s.fontWidth = 100
        }
        let (_, controller) = try makeDocument(lines: 3)
        controller.togglePrintPreview()
        XCTAssertNil(controller.printPreview)
        XCTAssertTrue(controller.window?.contentView is EditorContainerView)
        XCTAssertEqual(controller.textView.statusMessage.trimmingCharacters(in: .whitespaces), "印刷ページ設定エラー:印字可能領域がありません")
    }

    /// 他の窓で設定が変わったら作り直す（PM_PRINTSETTING）。行番号を入れるとページの文字の位置がずれる
    func testPreviewFollowsSettingChange() throws {
        let (_, controller) = try makeDocument(lines: 5)
        let preview = try openPreview(controller)
        let before = try XCTUnwrap(preview.previewView.page?.runs.first { $0.text.hasPrefix("line") }?.x)
        modify { $0.lineNumber = true }
        NotificationCenter.default.post(name: PrintPreviewController.settingsDidChangeNotification, object: nil)
        XCTAssertTrue(preview.layout?.setting.lineNumber ?? false)
        let runs = try XCTUnwrap(preview.previewView.page?.runs)
        XCTAssertTrue(runs.contains { $0.text.trimmingCharacters(in: .whitespaces) == "1" }, "行番号")
        XCTAssertGreaterThan(runs.first { $0.text.hasPrefix("line") }?.x ?? 0, before, "本文は右へ")
        XCTAssertFalse(preview.previewView.page?.rules.isEmpty ?? true, "区切りの縦線")
    }

    /// プレビューから「ページ設定」：プレビューの行番号の桁数を渡し、OK で作り直す
    func testPreviewPageSetting() throws {
        let (_, controller) = try makeDocument(lines: 120)
        modify { $0.lineNumber = true }
        let preview = try openPreview(controller)
        XCTAssertEqual(preview.layout?.lineNumberColumns, 4, "120 行：3 桁と区切り")
        var columns = 0
        PrintPreviewController.runPrintSettingDialog = { dialog, _ in
            columns = dialog.lineNumberColumns
            dialog.page.setText("IDC_EDIT_DANSUU", "2")
            dialog.page.onChange?("IDC_EDIT_DANSUU")
            dialog.onClose = {}
            dialog.page.onButton?("IDOK")
            return dialog.result
        }
        preview.page.onButton?("IDC_BUTTON_PRINTSETTING")
        XCTAssertEqual(columns, 4, "プレビューの排版の桁数")
        XCTAssertEqual(preview.layout?.setting.columns, 2, "2 段で作り直した")
        // メニューから（プレビューでないとき）は 3
        preview.close()
        controller.showPrintSetting()
        XCTAssertEqual(columns, 3)
    }

    /// 「プリンター」：用紙設定のパネルの用紙と向きを、一番近い原版の用紙にして設定に入れる
    func testSelectPrinter() throws {
        let (_, controller) = try makeDocument(lines: 3)
        let preview = try openPreview(controller)
        PrintPreviewController.runPageLayout = { info, _ in
            info.orientation = .landscape
            info.paperSize = NSSize(width: 792, height: 612)	// レター（8.5 × 11 インチ）横
            return true
        }
        preview.page.onButton?("IDC_BUTTON_PRINTERSELECT")
        let setting = PrintCore.setting(at: 0)
        XCTAssertEqual(setting.paperSize, 1, "DMPAPER_LETTER")
        XCTAssertEqual(setting.orientation, .landscape)
        let letter = PrintCore.papers.first { $0.paperID == 1 }?.name ?? "?"
        XCTAssertEqual(preview.page.text("IDC_STATIC_PAPER"), "\(letter)  横")
        XCTAssertGreaterThan(preview.layout?.paperWidth ?? 0, preview.layout?.paperHeight ?? 0)
        XCTAssertEqual(PrintPreviewController.nearestPaper(width: 2100, height: 2970)?.paperID, 9, "A4")
    }

    // MARK: - 印刷（原版 OnPrint）

    /// 印刷の情報：ジョブ名（無題は「無題」）、用紙の大きさ、余白なし、ページ数。印刷したらプレビューを閉じる、キャンセルは残る
    func testPrintOperation() throws {
        let (document, controller) = try makeDocument(lines: 100)
        var operations: [NSPrintOperation] = []
        var answer = false
        PrintPreviewController.runPrintOperation = { operation, _, completion in
            operations.append(operation)
            completion(answer)
        }
        // F_PRINT：プレビューを開いてから印刷。キャンセルはプレビューのまま
        document.printCommand(nil)
        let preview = try XCTUnwrap(controller.printPreview)
        let operation = try XCTUnwrap(operations.first)
        XCTAssertEqual(operation.jobTitle, "無題")
        let info = operation.printInfo
        XCTAssertEqual(info.paperSize.width, 2100 * 72 / 254, accuracy: 0.5, "A4")
        XCTAssertEqual(info.paperSize.height, 2970 * 72 / 254, accuracy: 0.5)
        XCTAssertEqual(info.topMargin, 0)
        XCTAssertEqual(info.leftMargin, 0)
        let view = try XCTUnwrap(operation.view as? PrintPagesView)
        var range = NSRange()
        XCTAssertTrue(view.knowsPageRange(&range))
        XCTAssertEqual(range, NSRange(location: 1, length: preview.pageCount))
        XCTAssertEqual(view.rectForPage(2).minY, info.paperSize.height, accuracy: 0.5)
        // 印刷した：プレビューを閉じる
        answer = true
        preview.page.onButton?("IDOK")
        XCTAssertEqual(operations.count, 2)
        XCTAssertNil(controller.printPreview)
    }

    /// 印刷のページを描く：本文の文字の位置に黒い点がある、余白には何もない
    func testPrintPageRendering() throws {
        let (document, controller) = try makeDocument(lines: 5)
        let layout = document.editor.makePrintLayout(PrintCore.setting(at: 0))
        let renderer = PrintPageRenderer(layout: layout)
        let pages = PrintPagesView(layout: layout, renderer: renderer, view: controller.textView.expandParameterView)
        // 1 点 = 2 ドット
        let scale: CGFloat = 2
        let width = Int(CGFloat(layout.paperWidth) * PrintPagesView.unitsToPoints * scale)
        let height = Int(CGFloat(layout.paperHeight) * PrintPagesView.unitsToPoints * scale)
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // 下向きにする
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        pages.drawPage(0, in: context)
        let image = try XCTUnwrap(context.makeImage())
        let rep = NSBitmapImageRep(cgImage: image)
        func dark(_ rect: CGRect) -> Int {
            var count = 0
            let x0 = Int(rect.minX * PrintPagesView.unitsToPoints * scale), x1 = Int(rect.maxX * PrintPagesView.unitsToPoints * scale)
            let y0 = Int(rect.minY * PrintPagesView.unitsToPoints * scale), y1 = Int(rect.maxY * PrintPagesView.unitsToPoints * scale)
            for y in stride(from: max(0, y0), to: min(height, y1), by: 1) {
                for x in stride(from: max(0, x0), to: min(width, x1), by: 1) where (rep.colorAt(x: x, y: y)?.brightnessComponent ?? 1) < 0.5 {
                    count += 1
                }
            }
            return count
        }
        let page = layout.page(0, view: controller.textView.expandParameterView)
        let first = try XCTUnwrap(page.runs.first { $0.text.hasPrefix("line") })
        let fontHeight = CGFloat(layout.setting.fontHeight)
        XCTAssertGreaterThan(dark(CGRect(x: CGFloat(first.x), y: CGFloat(first.baseline) - fontHeight, width: fontHeight * 4, height: fontHeight)), 10,
                             "本文の文字")
        XCTAssertEqual(dark(CGRect(x: 0, y: 0, width: CGFloat(layout.setting.marginLeft) - 10, height: CGFloat(layout.paperHeight))), 0, "左の余白")
        // フッター「- 1 -」
        let footer = try XCTUnwrap(page.runs.max { $0.baseline < $1.baseline })
        XCTAssertEqual(footer.text.replacingOccurrences(of: " ", with: ""), "-1-")
        XCTAssertGreaterThan(dark(CGRect(x: CGFloat(footer.x), y: CGFloat(footer.baseline) - fontHeight, width: fontHeight * 3, height: fontHeight)), 5)
    }

    // MARK: - 機能

    func testCommandTable() {
        XCTAssertEqual(CommandTable.selector(for: 30150), #selector(SakuraDocument.printCommand(_:)))
        XCTAssertEqual(CommandTable.selector(for: 30151), #selector(SakuraDocument.printPreviewCommand(_:)))
        XCTAssertEqual(CommandTable.selector(for: 30152), #selector(SakuraDocument.printPageSetupCommand(_:)))
    }

    /// 対話框・操作バーの文字が切れない（PropLayoutTests と同じ確認）
    func testPrintDialogsHaveNoTruncatedText() throws {
        var problems: [String] = []
        let setting = try XCTUnwrap(PrintSettingDialog(currentIndex: 0, lineNumberColumns: 3))
        problems += PropLayoutTests.truncated(setting.page).map { "IDD_PRINTSETTING: \($0)" }
        let (_, controller) = try makeDocument(lines: 3)
        let preview = try openPreview(controller)
        problems += PropLayoutTests.truncated(preview.page).map { "IDD_PRINTPREVIEWBAR: \($0)" }
        XCTAssertEqual(problems, [], problems.joined(separator: "\n"))
    }

    /// 截图（PNG。DialogScreenshotTests と同じ所）
    func testPrintScreenshots() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("sakura-dialog-shots")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        func shot(_ view: NSView, _ name: String) throws {
            view.layoutSubtreeIfNeeded()
            view.display()
            let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: rep)
            try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent(name + ".png"))
        }
        modify { s in
            s.lineNumber = true
            s.headers = ["$f", "印刷のテスト", "$p/$P"]
        }
        let dialog = try XCTUnwrap(PrintSettingDialog(currentIndex: 0, lineNumberColumns: 3))
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: dialog.page.view.frame.size), styleMask: [.titled], backing: .buffered, defer: false)
        panel.contentView = dialog.page.view
        panel.orderFront(nil)
        try shot(dialog.page.view, "IDD_PRINTSETTING")
        panel.orderOut(nil)
        let (_, controller) = try makeDocument(lines: 60)
        let preview = try openPreview(controller)
        controller.window?.orderFront(nil)
        try shot(preview.container, "print-preview")
        print("截图：\(directory.path)")
    }
}

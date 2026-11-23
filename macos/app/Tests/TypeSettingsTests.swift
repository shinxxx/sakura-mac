// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge
import XCTest

/// タイプ別設定窗口（计划第 40 步）。
///
/// - 页和控件与原版的对话框模板（IDD_PROP_SCREEN 等）相同，各功能（F_OPTION_TYPE、F_TYPE_*）打开那一页
/// - 各页的 SetData / GetData 与原版相同：值、范围限制、nInts 的各个数、联动
/// - OK 时只写回改过的项（节是 Types(N)），键盘的类型的文档跟着变；キャンセル 什么也不改
/// 值的读写大多用假的设置（CommonSettingsTests.FakeStore：没写过的项从核心库读），不改测试进程的设置。
final class TypeSettingsTests: XCTestCase {
    private var store: CommonSettingsTests.FakeStore!
    /// テストに使うタイプ（C/C++）
    private var cpp = 0
    private var section: String { "Types(\(cpp))" }

    override func setUp() {
        _ = TestCore.home
        _ = NSApplication.shared
        store = CommonSettingsTests.FakeStore()
        cpp = EditorCore.typeSettings.first { $0.name == "C/C++" }?.index ?? -1
    }

    override func tearDown() {
        CommonSettingsPages.chooseFont = { font, window in FontPicker.choose(font, window: window) }
    }

    private func open(_ pageName: String, type: Int? = nil) throws -> (TypeSettingsWindowController, PropPage) {
        let probe = try XCTUnwrap(TypeSettingsWindowController(store: store, typeIndex: type ?? cpp))
        let index = try XCTUnwrap(probe.pageIndex(named: pageName))
        probe.cancel(nil)
        let controller = try XCTUnwrap(TypeSettingsWindowController(store: store, typeIndex: type ?? cpp, page: index))
        return (controller, controller.page(index))
    }

    private func click(_ page: PropPage, _ id: String, _ on: Bool = true) {
        page.setChecked(id, on)
        page.onChange?(id)
    }

    private func type(_ page: PropPage, _ id: String, _ text: String) {
        page.setText(id, text)
        page.onChange?(id)
    }

    private func choose(_ page: PropPage, _ id: String, tag: Int) {
        let popup = page.control(id) as? NSPopUpButton
        popup?.selectItem(withTag: tag)
        page.onChange?(id)
    }

    /// nInts の n 番目（0 から）
    private func nInt(_ n: Int) -> Int {
        let ints = (store.values["\(section)/nInts"] ?? EditorCore.commonSetting(section: section, key: "nInts") ?? "").split(separator: ",")
        return ints.count == 12 ? Int(ints[n]) ?? -1 : -1
    }

    // MARK: - 布局、打开

    func testPagesAndControlsMatchOriginalDialogs() throws {
        XCTAssertGreaterThan(cpp, 0)
        let controller = try XCTUnwrap(TypeSettingsWindowController(store: store, typeIndex: cpp))
        defer { controller.cancel(nil) }
        XCTAssertEqual(controller.window?.title, "タイプ別設定")
        // 页的顺序与原版 CPropTypes::DoPropertySheet 相同
        XCTAssertEqual((0..<controller.pageCount).map(controller.pageName),
                       ["スクリーン", "カラー", "ウィンドウ", "支援", "正規表現キーワード", "キーワードヘルプ"])
        for index in 0..<controller.pageCount {
            let definition = controller.dialogs.pages[index]
            let page = controller.page(index)
            XCTAssertEqual(page.view.frame.size, NSSize(width: PropPage.points(definition.size[0]), height: PropPage.points(definition.size[1])))
            for control in definition.controls where control.id != "IDC_STATIC" && control.kind != "icon" {
                let view = try XCTUnwrap(page.control(control.id), "\(definition.name) \(control.id)")
                if control.kind == "check" || control.kind == "radio" {
                    XCTAssertEqual((view as? NSButton)?.title, control.text ?? "", "\(definition.name) \(control.id)")
                }
            }
        }
        let screen = controller.page(0)
        XCTAssertEqual((screen.control("IDC_CHECK_INS_SPACE") as? NSButton)?.title, "SPACEの挿入")
        XCTAssertNotNil(controller.page(2).control("IDC_TRACKBAR_BACKIMG_TRANSPARENCY") as? NSSlider, "透明度のトラックバー")
    }

    /// 設定 > タイプ別設定 的各功能打开那一页（原版 F_TYPE_*）
    func testCommandOpensItsPage() throws {
        for (code, name) in [(31115, "スクリーン"), (31116, "カラー"), (31114, "ウィンドウ"), (31117, "支援"),
                             (31118, "正規表現キーワード"), (31119, "キーワードヘルプ")] {
            let page = try XCTUnwrap(TypeSettingsWindowController.pageOfCommand[code])
            let controller = try XCTUnwrap(TypeSettingsWindowController(store: store, typeIndex: cpp, page: page))
            XCTAssertEqual(controller.pageName(controller.currentIndex), name, "\(code)")
            controller.cancel(nil)
        }
        for code in [31111, 31114, 31115, 31116, 31117, 31118, 31119] {
            XCTAssertEqual(CommandTable.selector(for: code), #selector(EditorTextView.showTypeSettings(_:)), "\(code)")
        }
    }

    /// 編集画面から：その文書のタイプの設定を開く
    func testEditorOpensSettingsOfItsType() throws {
        let dir = TestCore.home.appendingPathComponent("type-settings-open")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("a.cpp")
        try "int a;\n".write(to: url, atomically: true, encoding: .utf8)
        let document = try XCTUnwrap(EditorDocument())
        XCTAssertEqual(document.open(path: url.path), .success)
        let view = EditorTextView(document: document)
        XCTAssertTrue(CommandTable.perform(31115, from: view))
        let shown = try XCTUnwrap(TypeSettingsWindowController.shared)
        XCTAssertEqual(shown.typeIndex, cpp)
        XCTAssertEqual(shown.pageName(shown.currentIndex), "スクリーン")
        XCTAssertEqual(shown.page(0).text("IDC_EDIT_TYPENAME"), "C/C++")
        shown.cancel(nil)
        XCTAssertNil(TypeSettingsWindowController.shared)
    }

    // MARK: - OK / キャンセル

    func testOKWritesChangedItemsToTypeSection() throws {
        store.values["\(section)/bInsSpace"] = "0"
        let (controller, page) = try open("スクリーン")
        click(page, "IDC_CHECK_INS_SPACE")
        controller.ok(nil)
        XCTAssertEqual(store.values["\(section)/bInsSpace"], "1")
        XCTAssertEqual(store.writes, ["\(section)/bInsSpace"], "改过的项才写")
        XCTAssertEqual(store.saveCount, 1)
    }

    func testCancelChangesNothing() throws {
        let (controller, page) = try open("スクリーン")
        click(page, "IDC_CHECK_INS_SPACE", !page.isChecked("IDC_CHECK_INS_SPACE"))
        controller.cancel(nil)
        XCTAssertEqual(store.writes, [])
        XCTAssertEqual(store.saveCount, 0)
    }

    /// 真的核心库：OK 以后这个类型的设置变了，通知里是类型的编号；这个类型的编辑画面按新的设置排版
    func testOKAppliesToCoreAndOpenEditors() throws {
        let text = try XCTUnwrap(EditorCore.typeSettings.first { $0.name == "テキスト" }).index
        let section = "Types(\(text))"
        let original = try XCTUnwrap(EditorCore.commonSetting(section: section, key: "nLineSpace"))
        defer {
            XCTAssertTrue(EditorCore.setCommonSetting(original, section: section, key: "nLineSpace"))
            NotificationCenter.default.post(name: TypeSettingsWindowController.didChangeNotification, object: nil, userInfo: ["index": text])
        }
        let dir = TestCore.home.appendingPathComponent("type-settings-ok")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("a.txt")
        try "abc\n".write(to: url, atomically: true, encoding: .utf8)
        let document = try XCTUnwrap(EditorDocument())
        XCTAssertEqual(document.open(path: url.path), .success)
        let view = EditorTextView(document: document)
        let other = EditorTextView(document: try XCTUnwrap(EditorDocument()))	// 無題は「基本」
        let otherSpacing = other.document.viewSettings.lineSpacing

        let controller = try XCTUnwrap(TypeSettingsWindowController(typeIndex: text, page: 0))
        let page = controller.page(0)
        let spacing = original == "9" ? 8 : 9
        type(page, "IDC_EDIT_LINESPACE", String(spacing))
        let notified = expectation(forNotification: TypeSettingsWindowController.didChangeNotification, object: nil) { note in
            note.userInfo?["index"] as? Int == text
        }
        controller.ok(nil)
        wait(for: [notified], timeout: 1)
        XCTAssertEqual(EditorCore.commonSetting(section: section, key: "nLineSpace"), String(spacing))
        XCTAssertEqual(view.document.viewSettings.lineSpacing, spacing, "テキストの文書は新しい設定")
        XCTAssertEqual(other.document.viewSettings.lineSpacing, otherSpacing, "別のタイプの文書はそのまま")
    }

    // MARK: - スクリーン

    func testScreenPageLayoutValues() throws {
        store.values["\(section)/nInts"] = "\(cpp),120,2,8,1,2,0,1,1,0,0,0"
        store.values["\(section)/nTextWrapMethod"] = "1"
        store.values["\(section)/nLineSpace"] = "-3"
        store.values["\(section)/bTabArrow"] = "0"
        store.values["\(section)/szTabViewString"] = "»       "
        let (controller, page) = try open("スクリーン")
        XCTAssertEqual(page.text("IDC_EDIT_MAXLINELEN"), "120")
        XCTAssertEqual(page.text("IDC_EDIT_CHARSPACE"), "2")
        XCTAssertEqual(page.text("IDC_EDIT_TABSPACE"), "8")
        XCTAssertEqual(page.text("IDC_EDIT_LINESPACE"), "-3")
        XCTAssertEqual(page.selectedIndex("IDC_COMBO_WRAPMETHOD"), 1)
        XCTAssertEqual(page.itemTitles("IDC_COMBO_WRAPMETHOD"), ["折り返さない", "指定桁で折り返す", "右端で折り返す"])
        XCTAssertTrue(page.isEnabled("IDC_EDIT_TABVIEWSTRING"), "文字指定")

        // 範囲（原版 GetData）：折り返し桁数 10～10240、文字の間隔 0～64、行の間隔 -128～128、TAB幅 1～64
        type(page, "IDC_EDIT_MAXLINELEN", "5")
        type(page, "IDC_EDIT_CHARSPACE", "100")
        type(page, "IDC_EDIT_LINESPACE", "-500")
        type(page, "IDC_EDIT_TABSPACE", "99")
        // TAB表示：矢印のときは文字を変えられない
        page.select("IDC_CHECK_TAB_ARROW", 2)
        page.onChange?("IDC_CHECK_TAB_ARROW")
        XCTAssertFalse(page.isEnabled("IDC_EDIT_TABVIEWSTRING"))
        page.select("IDC_COMBO_TSV_MODE", 2)
        click(page, "IDC_CHECK_WORDWRAP")
        controller.ok(nil)
        // nInts：変えた数だけ変わり、ほかの数（強調キーワード、行番号区切り等）はそのまま
        XCTAssertEqual(store.values["\(section)/nInts"], "\(cpp),10,64,64,1,2,0,1,1,1,0,2")
        XCTAssertEqual(store.values["\(section)/nLineSpace"], "-128")
        XCTAssertEqual(store.values["\(section)/bTabArrow"], "2")
    }

    /// TAB表示文字列（原版 GetData）：「^」と空白 7 個に入力した文字を先頭から入れる。TAB・改行まで
    func testTabViewString() {
        XCTAssertEqual(TypeScreenPage.tabViewString(""), "^       ")
        XCTAssertEqual(TypeScreenPage.tabViewString("»"), "»       ")
        XCTAssertEqual(TypeScreenPage.tabViewString("123456789"), "12345678")
        XCTAssertEqual(TypeScreenPage.tabViewString("ab\tcd"), "ab      ")
    }

    /// 「基本」は名前と拡張子を変えられない（書かない）
    func testBasisNameCannotBeChanged() throws {
        let (controller, page) = try open("スクリーン", type: 0)
        XCTAssertEqual(page.text("IDC_EDIT_TYPENAME"), "基本")
        XCTAssertFalse(page.isEnabled("IDC_EDIT_TYPENAME"))
        XCTAssertFalse(page.isEnabled("IDC_EDIT_TYPEEXTS"))
        page.setText("IDC_EDIT_TYPENAME", "X")
        controller.ok(nil)
        XCTAssertNil(store.values["Types(0)/szTypeName"])

        let (other, otherPage) = try open("スクリーン")
        XCTAssertTrue(otherPage.isEnabled("IDC_EDIT_TYPENAME"))
        type(otherPage, "IDC_EDIT_TYPENAME", "C++")
        type(otherPage, "IDC_EDIT_TYPEEXTS", "cpp,hpp")
        other.ok(nil)
        XCTAssertEqual(store.values["\(section)/szTypeName"], "C++")
        XCTAssertEqual(store.values["\(section)/szTypeExts"], "cpp,hpp")
    }

    /// アウトライン解析方法：標準ルール（リスト）／ルールファイル
    func testScreenOutline() throws {
        store.values["\(section)/nDefaultOutline"] = "13"	// OUTLINE_PYTHON
        store.values["\(section)/szOutlineRuleFilename"] = "rule.txt"
        let (controller, page) = try open("スクリーン")
        XCTAssertTrue(page.isChecked("IDC_RADIO_OUTLINEDEFAULT"))
        XCTAssertEqual(page.selectedTag("IDC_COMBO_OUTLINES"), 13)
        XCTAssertEqual(page.itemTitles("IDC_COMBO_OUTLINES").first, "C/C++")
        XCTAssertTrue(page.isEnabled("IDC_COMBO_OUTLINES"))
        XCTAssertFalse(page.isEnabled("IDC_EDIT_OUTLINERULEFILE"))
        XCTAssertEqual(page.text("IDC_EDIT_OUTLINERULEFILE"), "rule.txt", "使わなくても表示")

        click(page, "IDC_RADIO_OUTLINERULEFILE")
        XCTAssertFalse(page.isEnabled("IDC_COMBO_OUTLINES"))
        XCTAssertTrue(page.isEnabled("IDC_EDIT_OUTLINERULEFILE"))
        XCTAssertTrue(page.isEnabled("IDC_BUTTON_RULEFILE_REF"))
        let chooseFile = TypeSettingsPages.chooseFile
        defer { TypeSettingsPages.chooseFile = chooseFile }
        var asked: [String] = []
        TypeSettingsPages.chooseFile = { _, extensions, _ in asked = extensions; return "/tmp/my.rule" }
        page.onButton?("IDC_BUTTON_RULEFILE_REF")
        XCTAssertEqual(asked, ["rul", "rule", "txt"])
        XCTAssertEqual(page.text("IDC_EDIT_OUTLINERULEFILE"), "/tmp/my.rule")
        controller.ok(nil)
        XCTAssertEqual(store.values["\(section)/nDefaultOutline"], "12")	// OUTLINE_FILE
        XCTAssertEqual(store.values["\(section)/szOutlineRuleFilename"], "/tmp/my.rule")

        // 標準ルールに戻す：リストの先頭（C/C++）
        store.values["\(section)/nDefaultOutline"] = "12"
        let (back, backPage) = try open("スクリーン")
        XCTAssertTrue(backPage.isChecked("IDC_RADIO_OUTLINERULEFILE"))
        click(backPage, "IDC_RADIO_OUTLINEDEFAULT")
        XCTAssertEqual(backPage.selectedTag("IDC_COMBO_OUTLINES"), 1)	// OUTLINE_C_CPP
        back.ok(nil)
        XCTAssertEqual(store.values["\(section)/nDefaultOutline"], "1")
    }

    /// 禁則処理：ぶら下げを隠す は改行ぶら下げか句読点ぶら下げのとき
    func testScreenKinsoku() throws {
        store.values["\(section)/bKinsokuRet"] = "0"
        store.values["\(section)/bKinsokuKuto"] = "0"
        let (controller, page) = try open("スクリーン")
        XCTAssertFalse(page.isEnabled("IDC_CHECK_KINSOKUHIDE"))
        click(page, "IDC_CHECK_KINSOKUKUTO")
        XCTAssertTrue(page.isEnabled("IDC_CHECK_KINSOKUHIDE"))
        type(page, "IDC_EDIT_KINSOKUHEAD", "!?")
        controller.ok(nil)
        XCTAssertEqual(store.values["\(section)/bKinsokuKuto"], "1")
        XCTAssertEqual(store.values["\(section)/szKinsokuHead"], "!?")
    }

    /// タイプ別フォント：選ぶと「使用する」になり、フォント名を表示。外すと表示を消し、もう選べない
    func testScreenTypeFont() throws {
        store.values["\(section)/bUseTypeFont"] = "0"
        let (controller, page) = try open("スクリーン")
        XCTAssertFalse(page.isChecked("IDC_CHECK_USETYPEFONT"))
        XCTAssertFalse(page.isEnabled("IDC_CHECK_USETYPEFONT"))
        XCTAssertEqual(page.text("IDC_STATIC_TYPEFONT"), "")
        var initial: NSFont?
        CommonSettingsPages.chooseFont = { font, _ in
            initial = font
            return NSFont(name: "Menlo-Bold", size: 13)
        }
        page.onButton?("IDC_BUTTON_TYPEFONT")
        XCTAssertEqual(initial?.pointSize, EditorTextView.currentFont.pointSize, "使っていなければ編集画面のフォントから")
        XCTAssertTrue(page.isChecked("IDC_CHECK_USETYPEFONT"))
        XCTAssertTrue(page.isEnabled("IDC_CHECK_USETYPEFONT"))
        XCTAssertEqual(page.text("IDC_STATIC_TYPEFONT"), "Menlo(13pt)")
        controller.ok(nil)
        XCTAssertEqual(store.values["\(section)/bUseTypeFont"], "1")
        XCTAssertEqual(store.values["\(section)/nPointSize"], "130")
        XCTAssertEqual(store.values["\(section)/lfFaceName"], "Menlo")
        let lf = try XCTUnwrap(store.values["\(section)/lf"]).split(separator: ",")
        XCTAssertEqual(lf[0], "-17")	// 13pt（96 DPI）
        XCTAssertEqual(lf[4], "700")	// 太字

        let (again, againPage) = try open("スクリーン")
        XCTAssertEqual(againPage.text("IDC_STATIC_TYPEFONT"), "Menlo(13pt)")
        click(againPage, "IDC_CHECK_USETYPEFONT", false)
        XCTAssertEqual(againPage.text("IDC_STATIC_TYPEFONT"), "")
        XCTAssertFalse(againPage.isEnabled("IDC_CHECK_USETYPEFONT"))
        again.ok(nil)
        XCTAssertEqual(store.values["\(section)/bUseTypeFont"], "0")
        XCTAssertEqual(store.values["\(section)/lfFaceName"], "Menlo", "フォントの設定は残す")
    }

    // MARK: - ウィンドウ

    func testWindowPage() throws {
        store.values["\(section)/nImeState"] = String(3 << 2 | 1)	// 全角カタカナ、常にON
        store.values["\(section)/nInts"] = "\(cpp),120,0,4,1,2,0,0,2,0,0,0"
        store.values["\(section)/cLineTermChar"] = "|"
        store.values["\(section)/nLineNumWidth"] = "4"
        store.values["\(section)/bgImgOpacity"] = "200"
        store.values["\(section)/eDefaultEoltype"] = "2"	// LF
        let (controller, page) = try open("ウィンドウ")
        XCTAssertEqual(page.selectedIndex("IDC_COMBO_IMESWITCH"), 1)
        XCTAssertEqual(page.selectedIndex("IDC_COMBO_IMESTATE"), 3)
        XCTAssertTrue(page.isChecked("IDC_RADIO_LINENUM_LAYOUT"))
        XCTAssertTrue(page.isChecked("IDC_RADIO_LINETERMTYPE2"))
        XCTAssertTrue(page.isEnabled("IDC_EDIT_LINETERMCHAR"))
        XCTAssertEqual(page.text("IDC_EDIT_LINETERMCHAR"), "|")
        XCTAssertEqual(page.selectedIndex("IDC_COMBO_DEFAULT_EOLTYPE"), 1)
        // 透明度 = 255 - 不透明度。トラックバーと数字は連動
        XCTAssertEqual(page.text("IDC_EDIT_BACKIMG_TRANSPARENCY"), "55")
        XCTAssertEqual(page.sliderValue("IDC_TRACKBAR_BACKIMG_TRANSPARENCY"), 55)
        page.setSliderValue("IDC_TRACKBAR_BACKIMG_TRANSPARENCY", 100)
        page.onChange?("IDC_TRACKBAR_BACKIMG_TRANSPARENCY")
        XCTAssertEqual(page.text("IDC_EDIT_BACKIMG_TRANSPARENCY"), "100")
        type(page, "IDC_EDIT_BACKIMG_TRANSPARENCY", "20")
        XCTAssertEqual(page.sliderValue("IDC_TRACKBAR_BACKIMG_TRANSPARENCY"), 20)

        click(page, "IDC_RADIO_LINETERMTYPE1")
        XCTAssertFalse(page.isEnabled("IDC_EDIT_LINETERMCHAR"))
        click(page, "IDC_RADIO_LINENUM_CRLF")
        page.select("IDC_COMBO_IMESTATE", 4)
        page.select("IDC_COMBO_IMESWITCH", 2)
        type(page, "IDC_EDIT_LINENUMWIDTH", "30")
        type(page, "IDC_EDIT_BACKIMG_OFFSET_X", "-12")
        controller.ok(nil)
        XCTAssertEqual(store.values["\(section)/nImeState"], String(4 << 2 | 2))
        XCTAssertEqual(store.values["\(section)/nInts"], "\(cpp),120,0,4,1,2,0,1,1,0,0,0")
        XCTAssertEqual(store.values["\(section)/nLineNumWidth"], "11")
        XCTAssertEqual(store.values["\(section)/bgImgOpacity"], "235")
        XCTAssertEqual(store.values["\(section)/bgImgPosOffsetX"], "-12")
    }

    /// デフォルトの文字コード：一覧（CanDefault）、BOM の連動、CP（コードページ）
    func testWindowPageEncoding() throws {
        store.values["\(section)/eDefaultCodetype"] = "4"	// UTF-8
        store.values["\(section)/bDefaultBom"] = "0"
        let (controller, page) = try open("ウィンドウ")
        XCTAssertEqual(page.selectedTag("IDC_COMBO_DEFAULT_CODETYPE"), 4)
        XCTAssertFalse(page.itemTitles("IDC_COMBO_DEFAULT_CODETYPE").contains("自動選択"), "自動選択はデフォルトにできない")
        XCTAssertFalse(page.isChecked("IDC_CHECK_CP"))
        XCTAssertTrue(page.isEnabled("IDC_CHECK_CP"))
        XCTAssertTrue(page.isEnabled("IDC_CHECK_DEFAULT_BOM"))
        // UTF-16LE：BOM は既定でつける
        choose(page, "IDC_COMBO_DEFAULT_CODETYPE", tag: 3)
        XCTAssertTrue(page.isChecked("IDC_CHECK_DEFAULT_BOM"))
        // SJIS：BOM はつけられない
        choose(page, "IDC_COMBO_DEFAULT_CODETYPE", tag: 0)
        XCTAssertFalse(page.isChecked("IDC_CHECK_DEFAULT_BOM"))
        XCTAssertFalse(page.isEnabled("IDC_CHECK_DEFAULT_BOM"))
        // CP：コードページを足す。もう押せない
        let count = page.itemTitles("IDC_COMBO_DEFAULT_CODETYPE").count
        click(page, "IDC_CHECK_CP")
        XCTAssertTrue(page.isChecked("IDC_CHECK_CP"))
        XCTAssertFalse(page.isEnabled("IDC_CHECK_CP"))
        XCTAssertEqual(page.itemTitles("IDC_COMBO_DEFAULT_CODETYPE").count, count + EditorCore.codePageChoices.count)
        XCTAssertEqual(page.selectedTag("IDC_COMBO_DEFAULT_CODETYPE"), 0, "選んでいた文字コードはそのまま")
        controller.ok(nil)
        XCTAssertEqual(store.values["\(section)/eDefaultCodetype"], "0")
        XCTAssertFalse(store.writes.contains("\(section)/bDefaultBom"), "変わっていない")

        // 一覧にない（コードページ）とき：CP をチェックして、そのコードページを選ぶ
        let codePage = try XCTUnwrap(EditorCore.codePageChoices.last).encoding
        store.values["\(section)/eDefaultCodetype"] = String(codePage)
        let (cp, cpPage) = try open("ウィンドウ")
        XCTAssertTrue(cpPage.isChecked("IDC_CHECK_CP"))
        XCTAssertFalse(cpPage.isEnabled("IDC_CHECK_CP"))
        XCTAssertEqual(cpPage.selectedTag("IDC_COMBO_DEFAULT_CODETYPE"), codePage)
        cp.cancel(nil)
    }

    /// 背景画像の参照
    func testWindowPageBackgroundImage() throws {
        let (controller, page) = try open("ウィンドウ")
        let chooseFile = TypeSettingsPages.chooseFile
        defer { TypeSettingsPages.chooseFile = chooseFile }
        var asked: [String] = []
        TypeSettingsPages.chooseFile = { _, extensions, _ in asked = extensions; return "/tmp/back.png" }
        page.onButton?("IDC_BUTTON_BACKIMG_PATH_SEL")
        XCTAssertEqual(asked, ["bmp", "jpg", "jpeg", "png"])
        page.select("IDC_COMBO_BACKIMG_POS", 4)
        let repeatY = !page.isChecked("IDC_CHECK_BACKIMG_REP_Y")
        click(page, "IDC_CHECK_BACKIMG_REP_Y", repeatY)
        controller.ok(nil)
        XCTAssertEqual(store.values["\(section)/bgImgPath"], "/tmp/back.png")
        XCTAssertEqual(store.values["\(section)/bgImgPos"], "4")	// 中央
        XCTAssertEqual(store.values["\(section)/bgImgRepeartY"], repeatY ? "1" : "0")
    }

    // MARK: - 支援

    func testSupportPage() throws {
        store.values["\(section)/nHokanType"] = "20001"	// プラグインの補完（Mac 版にはない）
        store.values["\(section)/bChkEnterAtEnd"] = "0"
        let (controller, page) = try open("支援")
        for id in ["IDC_COMBO_HOKAN_TYPE", "IDC_EDIT_TYPEEXTHELP", "IDC_BUTTON_TYPEOPENHELP", "IDC_EDIT_TYPEEXTHTMLHELP",
                   "IDC_BUTTON_TYPEOPENEXTHTMLHELP", "IDC_CHECK_TYPEHTMLHELPISSINGLE"] {
            XCTAssertFalse(page.isEnabled(id), id)
        }
        XCTAssertTrue(page.isEnabled("IDC_EDIT_HOKANFILE"))
        let chooseFile = TypeSettingsPages.chooseFile
        defer { TypeSettingsPages.chooseFile = chooseFile }
        TypeSettingsPages.chooseFile = { _, extensions, _ in extensions == ["kwd"] ? "/tmp/cpp.kwd" : nil }
        page.onButton?("IDC_BUTTON_HOKANFILE_REF")
        click(page, "IDC_CHECK_CHKENTERATEND")
        click(page, "IDC_CHECK_INDENTCPPUNDO", !page.isChecked("IDC_CHECK_INDENTCPPUNDO"))
        controller.ok(nil)
        XCTAssertEqual(store.values["\(section)/szHokanFile"], "/tmp/cpp.kwd")
        XCTAssertEqual(store.values["\(section)/bChkEnterAtEnd"], "1")
        XCTAssertNotNil(store.values["\(section)/bIndentCppUndoSep"])
        XCTAssertEqual(store.values["\(section)/nHokanType"], "20001", "Mac 版で使えない設定は変えない")
    }

    /// 以后移植的页（カラー 等）：表示だけ、変えられない
    func testLaterPagesAreDisabled() throws {
        let (controller, page) = try open("カラー")
        XCTAssertFalse(page.isEnabled("IDC_CHECK_DISP"))
        XCTAssertFalse(page.isEnabled("IDC_BUTTON_IMPORT"))
        controller.ok(nil)
        XCTAssertEqual(store.writes, [])
    }
}

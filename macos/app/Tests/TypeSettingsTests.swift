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
            XCTAssertEqual(page.view.frame.size, NSSize(width: PropPage.pointsX(definition.size[0]), height: PropPage.points(definition.size[1])))
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

    // MARK: - カラー（第 2 个 PR）

    /// sakura.ini の色の値（原版「%u,%u,%06x,%06x,%u」、色は BGR）
    func testColorSettingValue() throws {
        let value = try XCTUnwrap(ColorSettingValue(ini: "1,0,0000ff,ffffff,1"))
        XCTAssertTrue(value.display)
        XCTAssertFalse(value.bold)
        XCTAssertTrue(value.underline)
        XCTAssertEqual(value.text, 0x0000FF)	// 赤（BGR）
        XCTAssertEqual(ColorSettingValue.color(value.text).usingColorSpace(.sRGB)?.redComponent, 1)
        XCTAssertEqual(ColorSettingValue.bgr(NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)), 0xFF0000)
        XCTAssertEqual(value.ini, "1,0,0000ff,ffffff,1")
        XCTAssertNil(ColorSettingValue(ini: "1,0,zz,0,0"))
    }

    /// 縦線桁指定：「桁」と「Step(Begin,End)」（原版 SetData / GetData）
    func testVerticalLines() {
        XCTAssertEqual(VerticalLines.values("10,20"), [10, 20, 0])
        XCTAssertEqual(VerticalLines.values("4(8,40),80"), [-8, 40, 4, 80, 0])
        XCTAssertEqual(VerticalLines.values("4(8,)"), [-8, 10240, 4, 0], "End がないときは最大")
        XCTAssertEqual(VerticalLines.values("10,x,20"), [10, 0], "読めないところで終わり")
        XCTAssertEqual(VerticalLines.values(""), [0])
        XCTAssertEqual(VerticalLines.text([-8, 40, 4, 80, 0]), "4(8,40),80")
        XCTAssertEqual(VerticalLines.text([10, 20, 0, 30]), "10,20")
        XCTAssertEqual(VerticalLines.text([-40, 8, 4, 5, 0]), "5", "End < Begin は無視")
    }

    private func colorKey(_ name: String) -> String { "\(section)/\(name)" }

    /// 色指定リスト：行は原版の色の順序。✓・太字・下線・色の選択、OK で変えた色だけ書く
    func testColorPageList() throws {
        store.values[colorKey("C[TXT]")] = "1,0,000000,ffffff,0"
        store.values[colorKey("C[CMT]")] = "1,0,008000,ffffff,0"
        let (controller, page) = try open("カラー")
        let list = try XCTUnwrap(page.list("IDC_LIST_COLORS"))
        let items = EditorCore.colorItems
        XCTAssertEqual(list.rows.count, items.count)
        XCTAssertEqual(list.rows.first?.first, "テキスト")
        let comment = try XCTUnwrap(items.firstIndex { $0.key == "C[CMT]" })
        // テキストは「色分け/表示」を外せない
        XCTAssertFalse(page.isEnabled("IDC_CHECK_DISP"))
        list.onClick?(0, 0)
        XCTAssertTrue(page.isChecked("IDC_CHECK_DISP"))

        list.select(comment)
        list.onSelect?()
        XCTAssertTrue(page.isEnabled("IDC_CHECK_DISP"))
        XCTAssertTrue(page.isChecked("IDC_CHECK_DISP"))
        XCTAssertFalse(page.isChecked("IDC_CHECK_BOLD"))
        // ✓ をクリック → 表示しない。名前をダブルクリック → 太字。右クリック → 下線
        list.onClick?(comment, 0)
        XCTAssertFalse(page.isChecked("IDC_CHECK_DISP"))
        list.onDoubleClick?(comment, 1)
        XCTAssertTrue(page.isChecked("IDC_CHECK_BOLD"))
        list.onRightClick?(comment, 1)
        XCTAssertTrue(page.isChecked("IDC_CHECK_UNDERLINE"))
        // 文字色：ボタンでも見本のクリックでも色を選ぶ
        let chooseColor = TypeSettingsPages.chooseColor
        defer { TypeSettingsPages.chooseColor = chooseColor }
        TypeSettingsPages.chooseColor = { _, _ in NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1) }
        page.onButton?("IDC_BUTTON_TEXTCOLOR")
        TypeSettingsPages.chooseColor = { _, _ in NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1) }
        list.onClick?(comment, 3)
        controller.ok(nil)
        XCTAssertEqual(store.values[colorKey("C[CMT]")], "0,1,0000ff,ff0000,1")
        XCTAssertFalse(store.writes.contains(colorKey("C[TXT]")), "変えていない色は書かない")
    }

    /// 色のない項目（キャレットの背景色など）は選べない
    func testColorPageAttributes() throws {
        let (controller, page) = try open("カラー")
        let items = EditorCore.colorItems
        let caret = try XCTUnwrap(items.firstIndex { $0.noBack })
        let list = try XCTUnwrap(page.list("IDC_LIST_COLORS"))
        list.select(caret)
        list.onSelect?()
        XCTAssertFalse(page.isEnabled("IDC_BUTTON_BACKCOLOR"))
        XCTAssertFalse(page.isEnabled("IDC_BUTTON_SAMEBKCOLOR"))
        var asked = false
        let chooseColor = TypeSettingsPages.chooseColor
        defer { TypeSettingsPages.chooseColor = chooseColor }
        TypeSettingsPages.chooseColor = { color, _ in asked = true; return color }
        list.onClick?(caret, 3)
        XCTAssertFalse(asked, "背景色のない項目の見本は押せない")
        controller.cancel(nil)
    }

    /// コメント・文字列・縦線（原版 SetData / GetData）
    func testColorPageCommentsAndLines() throws {
        store.values[colorKey("szLineComment")] = "//"
        store.values[colorKey("nLineCommentColumn")] = "-1"	// 桁指定なし（~0）
        store.values[colorKey("szLineComment2")] = "REM"
        store.values[colorKey("nLineCommentColumn2")] = "0"	// 1 桁目
        store.values[colorKey("szBlockCommentFrom")] = "/*"
        store.values[colorKey("szBlockCommentTo")] = "*/"
        store.values[colorKey("bStringLineOnly")] = "0"
        store.values[colorKey("nVertLineIdx1")] = "-8"
        store.values[colorKey("nVertLineIdx2")] = "40"
        store.values[colorKey("nVertLineIdx3")] = "4"
        store.values[colorKey("nVertLineIdx4")] = "0"
        let (controller, page) = try open("カラー")
        XCTAssertFalse(page.isChecked("IDC_CHECK_LCPOS"))
        XCTAssertEqual(page.text("IDC_EDIT_LINECOMMENTPOS"), "1")
        XCTAssertFalse(page.isEnabled("IDC_EDIT_LINECOMMENTPOS"))
        XCTAssertTrue(page.isChecked("IDC_CHECK_LCPOS2"))
        XCTAssertEqual(page.text("IDC_EDIT_LINECOMMENTPOS2"), "1")
        XCTAssertEqual(page.text("IDC_EDIT_BLOCKCOMMENT_FROM"), "/*")
        XCTAssertFalse(page.isEnabled("IDC_CHECK_STRINGENDLINE"))
        XCTAssertEqual(page.text("IDC_EDIT_VERTLINE"), "4(8,40)")

        click(page, "IDC_CHECK_LCPOS")
        type(page, "IDC_EDIT_LINECOMMENTPOS", "5")
        type(page, "IDC_EDIT_LINECOMMENTPOS2", "0")	// 0 は桁指定なし
        click(page, "IDC_CHECK_STRINGLINEONLY")
        XCTAssertTrue(page.isEnabled("IDC_CHECK_STRINGENDLINE"))
        page.select("IDC_COMBO_STRINGLITERAL", 4)	// Python
        type(page, "IDC_EDIT_VERTLINE", "10,20")
        controller.ok(nil)
        XCTAssertEqual(store.values[colorKey("nLineCommentColumn")], "4")
        XCTAssertEqual(store.values[colorKey("nLineCommentColumn2")], "-1")
        XCTAssertEqual(store.values[colorKey("bStringLineOnly")], "1")
        XCTAssertEqual(nInt(6), 4, "文字列エスケープは nInts の 7 番目")
        XCTAssertEqual(store.values[colorKey("nVertLineIdx1")], "10")
        XCTAssertEqual(store.values[colorKey("nVertLineIdx2")], "20")
        XCTAssertEqual(store.values[colorKey("nVertLineIdx3")], "0")
    }

    /// 強調キーワード：1 はコンボボックス、2～10 はダイアログ。途中の「なし」は詰めて、色も一緒に動く
    func testColorPageKeywordSets() throws {
        let names = EditorCore.keywordSetNames
        XCTAssertGreaterThan(names.count, 2)
        store.values["\(section)/nInts"] = "\(cpp),120,0,4,0,-1,0,1,1,0,0,0"
        store.values[colorKey("nKeywordSelect3")] = "1"
        store.values[colorKey("C[KW2]")] = "1,0,000002,ffffff,0"
        store.values[colorKey("C[KW3]")] = "1,0,000003,ffffff,0"
        let (controller, page) = try open("カラー")
        XCTAssertEqual(page.selectedTag("IDC_COMBO_SET"), 0)
        XCTAssertEqual(page.itemTitles("IDC_COMBO_SET"), [" "] + names, "先頭は空白")
        let runDialog = TypeSettingsPages.runKeywordSelectDialog
        defer { TypeSettingsPages.runKeywordSelectDialog = runDialog }
        var shown: [Int] = []
        TypeSettingsPages.runKeywordSelectDialog = { dialog, _ in
            shown = (0..<10).map { dialog.page.selectedTag("IDC_COMBO\($0 + 1)") ?? -99 }
            return false	// キャンセル：詰めるだけ
        }
        page.onButton?("IDC_BUTTON_KEYWORD_SELECT")
        XCTAssertEqual(Array(shown.prefix(4)), [0, -1, 1, -1])
        controller.ok(nil)
        // 3 番目が 2 番目に詰まり、色も 2 番目へ
        XCTAssertEqual(nInt(5), 1)
        XCTAssertEqual(store.values[colorKey("nKeywordSelect3")], "-1")
        XCTAssertEqual(store.values[colorKey("C[KW2]")], "1,0,000003,ffffff,0")
        XCTAssertEqual(store.values[colorKey("C[KW3]")], "1,0,000002,ffffff,0")
    }

    /// 文字色統一（原版 CDlgSameColor）：チェックした色を使っている項目をそろえる
    func testSameColorDialog() throws {
        let items = EditorCore.colorItems
        var colors = items.map { _ in ColorSettingValue(display: true, text: 0x111111, back: 0xFFFFFF) }
        colors[1].text = 0x222222
        colors[2].text = 0x222222
        colors[3].text = 0x333333
        let dialog = try XCTUnwrap(SameColorDialog(items: items, colors: colors, text: true, color: 0x111111))
        XCTAssertEqual(dialog.title, "文字色統一")
        XCTAssertFalse(dialog.candidates.contains(0x111111), "そろえる色は出さない")
        let second = try XCTUnwrap(dialog.candidates.firstIndex(of: 0x222222))
        let list = try XCTUnwrap(dialog.page.list("IDC_LIST_COLORS"))
        list.select(second)
        list.onSelect?()
        XCTAssertEqual(Array(dialog.itemNames.prefix(2)), [items[1].name, items[2].name].filter { _ in !items[1].noText })
        dialog.toggle(second)
        dialog.ok()
        XCTAssertEqual(dialog.result[1].text, 0x111111)
        XCTAssertEqual(dialog.result[2].text, 0x111111)
        XCTAssertEqual(dialog.result[3].text, 0x333333, "チェックしていない色はそのまま")
        dialog.checkAll(true)
        dialog.ok()
        XCTAssertEqual(dialog.result[3].text, 0x111111, "全チェック")
    }

    /// 色設定のエクスポート・インポート（原版と同じ *.col）。まだ OK していない色もエクスポートする
    func testColorImportExport() throws {
        let dir = TestCore.home.appendingPathComponent("type-colors")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("a.col").path
        let saved = (TypeSettingsPages.chooseExportFile, TypeSettingsPages.chooseImportFile, TypeSettingsPages.showMessage)
        defer { (TypeSettingsPages.chooseExportFile, TypeSettingsPages.chooseImportFile, TypeSettingsPages.showMessage) = saved }
        var messages: [String] = []
        TypeSettingsPages.showMessage = { messages.append($0) }
        TypeSettingsPages.chooseExportFile = { _, extensions, _ in extensions == ["col"] ? path : nil }
        TypeSettingsPages.chooseImportFile = { extensions, _ in extensions == ["col"] ? path : nil }

        let (controller, page) = try open("カラー")
        let comment = try XCTUnwrap(EditorCore.colorItems.firstIndex { $0.key == "C[CMT]" })
        let list = try XCTUnwrap(page.list("IDC_LIST_COLORS"))
        list.select(comment)
        list.onSelect?()
        TypeSettingsPages.chooseColor = { _, _ in NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1) }
        defer { TypeSettingsPages.chooseColor = { color, _ in ColorPicker.choose(color) } }
        page.onButton?("IDC_BUTTON_TEXTCOLOR")
        page.onButton?("IDC_BUTTON_EXPORT")
        XCTAssertTrue(messages.last?.hasPrefix("ファイルをエクスポートしました。") ?? false, "\(messages)")
        let file = try String(contentsOfFile: path, encoding: .utf8)
        XCTAssertTrue(file.contains("C[CMT]="), file)
        XCTAssertTrue(file.contains(",00ff00,"), "まだ OK していない色")
        controller.cancel(nil)

        // 別のタイプにインポート：OK で書く
        let text = try XCTUnwrap(EditorCore.typeSettings.first { $0.name == "テキスト" }).index
        let (other, otherPage) = try open("カラー", type: text)
        otherPage.onButton?("IDC_BUTTON_IMPORT")
        other.ok(nil)
        XCTAssertTrue(try XCTUnwrap(store.values["Types(\(text))/C[CMT]"]).contains(",00ff00,"))
    }

    // MARK: - 正規表現キーワード（第 2 个 PR）

    /// 一覧（「色の名前,キーワード」）の表示と、挿入・追加・更新・削除・移動。減った項目は空にする
    func testRegexPage() throws {
        store.values["\(section)/bUseRegexKeyword"] = "0"
        store.values["\(section)/RxKey[000]"] = "RK1,/aa/k"
        store.values["\(section)/RxKey[001]"] = "RK2,/bb/k"
        store.values["\(section)/RxKey[002]"] = "RK3,/cc/k"
        let (controller, page) = try open("正規表現キーワード")
        let list = try XCTUnwrap(page.list("IDC_LIST_REGEX"))
        XCTAssertEqual(list.rows.map { $0[0] }, ["/aa/k", "/bb/k", "/cc/k"])
        XCTAssertEqual(list.rows[1][1], "正規表現キーワード2")
        XCTAssertEqual(list.selectedRow, 0)
        XCTAssertEqual(page.text("IDC_EDIT_REGEX"), "/aa/k")
        XCTAssertFalse(page.text("IDC_LABEL_REGEX_VERSION").isEmpty, "組み込みの正規表現ライブラリ")
        let rk5 = try XCTUnwrap(EditorCore.colorItems.first { $0.key == "C[RK5]" }).index
        XCTAssertTrue(page.itemTitles("IDC_COMBO_REGEX_COLOR").contains("正規表現キーワード5"))

        // 選んだ行を変えるとエディットに写す
        list.select(2)
        page.onChange?("IDC_LIST_REGEX")
        XCTAssertEqual(page.text("IDC_EDIT_REGEX"), "/cc/k")
        // 更新：選んだ行を換える
        type(page, "IDC_EDIT_REGEX", "/dd/k")
        (page.control("IDC_COMBO_REGEX_COLOR") as? NSPopUpButton)?.selectItem(withTag: rk5)
        page.onButton?("IDC_BUTTON_REGEX_UPD")
        XCTAssertEqual(list.rows[2], ["/dd/k", "正規表現キーワード5"])
        // 先頭へ
        page.onButton?("IDC_BUTTON_REGEX_TOP")
        XCTAssertEqual(list.rows.map { $0[0] }, ["/dd/k", "/aa/k", "/bb/k"])
        XCTAssertEqual(list.selectedRow, 0)
        // 削除して OK
        list.select(2)
        page.onChange?("IDC_LIST_REGEX")
        page.onButton?("IDC_BUTTON_REGEX_DEL")
        click(page, "IDC_CHECK_REGEX")
        controller.ok(nil)
        XCTAssertEqual(store.values["\(section)/bUseRegexKeyword"], "1")
        XCTAssertEqual(store.values["\(section)/RxKey[000]"], "RK5,/dd/k")
        XCTAssertEqual(store.values["\(section)/RxKey[001]"], "RK1,/aa/k")
        XCTAssertEqual(store.values["\(section)/RxKey[002]"], "", "減った項目は空")
    }

    /// 登録の検査（原版 CheckKeywordList）：囲み・同じキーワード・文法（確認して登録できる）・最大数
    func testRegexPageChecks() throws {
        store.values["\(section)/RxKey[000]"] = "RK1,/aa/k"
        let (controller, page) = try open("正規表現キーワード")
        let list = try XCTUnwrap(page.list("IDC_LIST_REGEX"))
        let saved = (TypeSettingsPages.showMessage, CommonSettingsPages.confirm)
        defer { (TypeSettingsPages.showMessage, CommonSettingsPages.confirm) = saved }
        var messages: [String] = []
        TypeSettingsPages.showMessage = { messages.append($0) }
        var answer = false
        CommonSettingsPages.confirm = { messages.append($0); return answer }

        type(page, "IDC_EDIT_REGEX", "abc")
        page.onButton?("IDC_BUTTON_REGEX_ADD")
        XCTAssertTrue(messages.last?.hasPrefix("正規表現キーワードを / と /k で囲ってください。") ?? false)
        type(page, "IDC_EDIT_REGEX", "/aa/k")
        page.onButton?("IDC_BUTTON_REGEX_ADD")
        XCTAssertEqual(messages.last, "同じキーワードで登録済みです。")
        type(page, "IDC_EDIT_REGEX", "/a(/k")
        page.onButton?("IDC_BUTTON_REGEX_ADD")
        XCTAssertTrue(messages.last?.hasPrefix("書式が正しくないか") ?? false)
        XCTAssertEqual(list.rows.count, 1, "いいえ：登録しない")
        answer = true
        page.onButton?("IDC_BUTTON_REGEX_ADD")
        XCTAssertEqual(list.rows.count, 2, "はい：登録する")
        // 挿入：選んだ行の前
        list.select(0)
        page.onChange?("IDC_LIST_REGEX")
        type(page, "IDC_EDIT_REGEX", "/zz/k")
        page.onButton?("IDC_BUTTON_REGEX_INS")
        XCTAssertEqual(list.rows.map { $0[0] }, ["/zz/k", "/aa/k", "/a(/k"])
        // 更新：選んでいないとき
        list.table.deselectAll(nil)
        page.onButton?("IDC_BUTTON_REGEX_UPD")
        XCTAssertEqual(messages.last, "キーワードが選択されていません。")
        controller.cancel(nil)
    }

    /// インポート・エクスポート（*.rkw）
    func testRegexImportExport() throws {
        let dir = TestCore.home.appendingPathComponent("type-regex")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("a.rkw").path
        let saved = (TypeSettingsPages.chooseExportFile, TypeSettingsPages.chooseImportFile, TypeSettingsPages.showMessage)
        defer { (TypeSettingsPages.chooseExportFile, TypeSettingsPages.chooseImportFile, TypeSettingsPages.showMessage) = saved }
        TypeSettingsPages.showMessage = { _ in }
        TypeSettingsPages.chooseExportFile = { _, extensions, _ in extensions == ["rkw"] ? path : nil }
        TypeSettingsPages.chooseImportFile = { extensions, _ in extensions == ["rkw"] ? path : nil }
        let (controller, page) = try open("正規表現キーワード")
        // まだ OK していないキーワードもエクスポートする
        for (keyword, color) in [("/aa/k", "C[RK1]"), ("/bb/k", "C[RK2]")] {
            type(page, "IDC_EDIT_REGEX", keyword)
            let tag = try XCTUnwrap(EditorCore.colorItems.first { $0.key == color }).index
            (page.control("IDC_COMBO_REGEX_COLOR") as? NSPopUpButton)?.selectItem(withTag: tag)
            page.onButton?("IDC_BUTTON_REGEX_ADD")
        }
        page.onButton?("IDC_BUTTON_REGEX_EXPORT")
        let file = try String(contentsOfFile: path, encoding: .utf8)
        XCTAssertTrue(file.contains("RxKey[001]=RK2,/bb/k"), file)
        controller.cancel(nil)

        let text = try XCTUnwrap(EditorCore.typeSettings.first { $0.name == "テキスト" }).index
        let (other, otherPage) = try open("正規表現キーワード", type: text)
        otherPage.onButton?("IDC_BUTTON_REGEX_IMPORT")
        XCTAssertEqual(otherPage.list("IDC_LIST_REGEX")?.rows.map { $0[0] }, ["/aa/k", "/bb/k"])
        other.ok(nil)
        XCTAssertEqual(store.values["Types(\(text))/RxKey[001]"], "RK2,/bb/k")
    }

    // MARK: - キーワードヘルプ（第 2 个 PR）

    func testKeyHelpPage() throws {
        let dir = TestCore.home.appendingPathComponent("type-keyhelp")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dict1 = dir.appendingPathComponent("one.khp").path, dict2 = dir.appendingPathComponent("two.khp").path
        try "First dictionary, v1\nabc\n".write(toFile: dict1, atomically: true, encoding: .ascii)
        try "Second\n".write(toFile: dict2, atomically: true, encoding: .ascii)
        store.values["\(section)/bUseKeyWordHelp"] = "0"
        store.values["\(section)/KDct[00]"] = "1,First dictionary. v1,\(dict1)"
        let (controller, page) = try open("キーワードヘルプ")
        let list = try XCTUnwrap(page.list("IDC_LIST_KEYHELP"))
        XCTAssertEqual(list.rows, [["one.khp", "First dictionary. v1", dict1]])
        XCTAssertEqual(page.text("IDC_EDIT_KEYHELP"), dict1)
        XCTAssertFalse(page.isEnabled("IDC_LIST_KEYHELP"), "キーワードヘルプを使わないときは変えられない")
        click(page, "IDC_CHECK_KEYHELP")
        XCTAssertTrue(page.isEnabled("IDC_LIST_KEYHELP"))

        let saved = TypeSettingsPages.showMessage
        defer { TypeSettingsPages.showMessage = saved }
        var messages: [String] = []
        TypeSettingsPages.showMessage = { messages.append($0) }
        // 挿入：辞書の 1 行目が説明。同じ辞書は登録できない、開けない辞書も
        page.onButton?("IDC_BUTTON_KEYHELP_INS")
        XCTAssertEqual(messages.last, "既に登録済みの辞書です。")
        type(page, "IDC_EDIT_KEYHELP", dir.appendingPathComponent("none.khp").path)
        page.onButton?("IDC_BUTTON_KEYHELP_INS")
        XCTAssertTrue(messages.last?.hasPrefix("ファイルを開けませんでした。") ?? false)
        list.table.deselectAll(nil)
        type(page, "IDC_EDIT_KEYHELP", dict2)
        page.onButton?("IDC_BUTTON_KEYHELP_INS")
        XCTAssertEqual(list.rows.map { $0[1] }, ["First dictionary. v1", "Second"])
        XCTAssertEqual(page.text("IDC_LABEL_KEYHELP_ABOUT"), "Second")
        // 上へ
        list.select(1)
        page.onChange?("IDC_LIST_KEYHELP")
        page.onButton?("IDC_BUTTON_KEYHELP_UP")
        XCTAssertEqual(list.rows.map { $0[0] }, ["two.khp", "one.khp"])
        page.select("IDC_COMBO_MENU", 2)
        click(page, "IDC_CHECK_KEYHELP_PREFIX")
        controller.ok(nil)
        XCTAssertEqual(store.values["\(section)/bUseKeyWordHelp"], "1")
        XCTAssertEqual(store.values["\(section)/KDct[00]"], "1,Second,\(dict2)")
        XCTAssertEqual(store.values["\(section)/KDct[01]"], "1,First dictionary. v1,\(dict1)")
        XCTAssertEqual(store.values["\(section)/nKeyHelpRMenuShowType"], "2")
    }

    /// 全部消すと説明を表示。チェックボックスで使う・使わない
    func testKeyHelpPageDeleteAndUse() throws {
        store.values["\(section)/KDct[00]"] = "1,About,/tmp/a.khp"
        store.values["\(section)/KDct[01]"] = "1,About2,/tmp/b.khp"
        let (controller, page) = try open("キーワードヘルプ")
        let list = try XCTUnwrap(page.list("IDC_LIST_KEYHELP"))
        let check = try XCTUnwrap(list.table.view(atColumn: 0, row: 1, makeIfNecessary: true) as? NSButton)
        XCTAssertEqual(check.title, "b.khp")
        XCTAssertEqual(check.state, .on)
        check.performClick(nil)	// チェックを外す：使わない
        list.select(0)
        page.onButton?("IDC_BUTTON_KEYHELP_DEL")
        XCTAssertEqual(list.rows.count, 1)
        controller.ok(nil)
        XCTAssertEqual(store.values["\(section)/KDct[00]"], "0,About2,/tmp/b.khp")
        XCTAssertEqual(store.values["\(section)/KDct[01]"], "")

        store.values["\(section)/KDct[01]"] = nil
        let (again, againPage) = try open("キーワードヘルプ")
        againPage.list("IDC_LIST_KEYHELP")?.select(0)
        againPage.onButton?("IDC_BUTTON_KEYHELP_DEL")
        XCTAssertEqual(againPage.text("IDC_LABEL_KEYHELP_ABOUT"), "辞書ファイルの１行目の文字列")
        XCTAssertEqual(againPage.text("IDC_EDIT_KEYHELP"), "キーワード辞書ファイル パス")
        again.cancel(nil)
    }
}

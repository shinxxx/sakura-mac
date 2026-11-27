// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge
import XCTest

/// 界面本地化（计划第 48 步）。完成标志「切换系统语言后界面没有遗漏的字符串」用这里的测试确认：
/// - Mac 版自己的文字：源代码里的日文都通过 `L10n.tr`，英文、中文的 Localizable.strings 里每个都有翻译；
/// - 原版的对话框模板：英文、中文的布局（*.lproj/*Dialogs.json）与日文的控件相同，文字已经翻译；
/// - 实际做出来的界面（共通設定・タイプ別設定的全部页、从页打开的对话框、菜单栏）在英文、中文时没有日文，
///   文字不被截断（与第 41 步的 PropLayoutTests 相同的检查）。
/// 英文里不能有假名、汉字；中文里不能有假名（汉字是共通的）。
final class LocalizationTests: XCTestCase {
    static let languages = ["en", "zh-Hans"]

    override func setUp() {
        _ = TestCore.home
        _ = NSApplication.shared
    }

    // MARK: - 工具

    /// 在 language 的界面里运行（核心库的语言也换），结束时回到日文
    static func inLanguage(_ language: String, _ body: () throws -> Void) rethrows {
        let saved = L10n.language
        L10n.language = language
        EditorCore.uiLanguage = L10n.coreLanguage
        defer {
            L10n.language = saved
            EditorCore.uiLanguage = L10n.coreLanguage
        }
        try body()
    }

    static func isKana(_ u: Unicode.Scalar) -> Bool {
        // ・（U+30FB）は記号として使われる（原版の英語版「Searching・・・」）
        (0x3040...0x30FA).contains(u.value) || (0x30FC...0x30FF).contains(u.value) || (0xFF66...0xFF9F).contains(u.value)
    }

    static func isKanji(_ u: Unicode.Scalar) -> Bool {
        (0x3400...0x9FFF).contains(u.value)
    }

    /// この言語の界面に出てはいけない文字がある
    static func hasJapanese(_ text: String, language: String) -> Bool {
        text.unicodeScalars.contains { isKana($0) || (language == "en" && isKanji($0)) }
    }

    /// 视图里显示的全部文字（编辑框的内容是数据，不算）。(位置, 文字)
    static func texts(in view: NSView, page: PropPage? = nil) -> [(String, String)] {
        var result: [(String, String)] = []
        func id(_ v: NSView) -> String { v.identifier?.rawValue ?? String(describing: type(of: v)) }
        func walk(_ v: NSView) {
            if v.isHidden { return }
            switch v {
            case let popup as NSPopUpButton:
                result += popup.itemTitles.map { (id(popup), $0) }
            case let button as NSButton:
                result.append((id(button), button.title))
            case let combo as NSComboBox:
                result += combo.objectValues.compactMap { $0 as? String }.map { (id(combo), $0) }
            case let field as NSTextField where !field.isEditable:
                result.append((id(field), field.stringValue))
            case let box as NSBox:
                result.append((id(box), box.title))
            case let table as NSTableView:
                result += table.tableColumns.map { (id(table), $0.title) }
            default:
                break
            }
            v.subviews.forEach(walk)
        }
        walk(view)
        // 列表、树的行（原版 ListBox・ListView・TreeView）
        if let page {
            for control in page.definition.controls {
                if let list = page.list(control.id) {
                    result += list.rows.flatMap { $0 }.map { (control.id, $0) }
                }
                if let tree = page.tree(control.id) {
                    func nodes(_ n: PropTreeNode) -> [String] { [n.title] + n.children.flatMap(nodes) }
                    result += tree.roots.flatMap(nodes).map { (control.id, $0) }
                }
            }
        }
        return result
    }

    /// 菜单的全部项目（子菜单也）
    static func titles(of menu: NSMenu, path: String = "") -> [(String, String)] {
        menu.items.flatMap { item -> [(String, String)] in
            if item.isSeparatorItem { return [] }
            let here = path + "/" + item.title
            return [(here, item.title)] + (item.submenu.map { titles(of: $0, path: here) } ?? [])
        }
    }

    // MARK: - Mac 版自己的文字（L10n.tr）

    static var sourcesURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources")
    }

    /// Swift 的字符串（简单的分析：注释、\( ) 、""" 也考虑）。(行, 文字, 前面的代码)
    static func stringLiterals(_ text: String) -> [(line: Int, value: String, before: String)] {
        let chars = Array(text)
        var result: [(Int, String, String)] = []
        var i = 0, line = 1
        func starts(_ s: String, at k: Int) -> Bool {
            let t = Array(s)
            return k + t.count <= chars.count && Array(chars[k..<(k + t.count)]) == t
        }
        while i < chars.count {
            let c = chars[i]
            if c == "\n" { line += 1; i += 1; continue }
            if starts("//", at: i) {
                while i < chars.count && chars[i] != "\n" { i += 1 }
                continue
            }
            if starts("/*", at: i) {
                i += 2
                while i < chars.count && !starts("*/", at: i) {
                    if chars[i] == "\n" { line += 1 }
                    i += 1
                }
                i += 2
                continue
            }
            if c == "\"" {
                let multi = starts("\"\"\"", at: i)
                let start = i, startLine = line
                i += multi ? 3 : 1
                var value = ""
                while i < chars.count {
                    if chars[i] == "\\" && i + 1 < chars.count {
                        if chars[i + 1] == "(" {
                            var depth = 1
                            i += 2
                            while i < chars.count && depth > 0 {
                                if chars[i] == "(" { depth += 1 } else if chars[i] == ")" { depth -= 1 }
                                i += 1
                            }
                            continue
                        }
                        value.append(chars[i]); value.append(chars[i + 1])
                        i += 2
                        continue
                    }
                    if multi && starts("\"\"\"", at: i) { i += 3; break }
                    if !multi && chars[i] == "\"" { i += 1; break }
                    if chars[i] == "\n" { line += 1 }
                    value.append(chars[i])
                    i += 1
                }
                let before = String(chars[max(0, start - 40)..<start]).trimmingCharacters(in: .whitespacesAndNewlines)
                result.append((startLine, value, before))
                continue
            }
            i += 1
        }
        return result
    }

    /// 按日文的文字找标签用的 ID（显示的文字不是这个）
    static let labelKeys: Set<String> = ["左クリックメニューのショートカットキー(K)", "排他制御(H)"]

    /// 源代码里的日文都是 L10n.tr 的文字（或者注释参数），没有直接写的
    func testNoJapaneseTextOutsideL10n() throws {
        let files = try FileManager.default.contentsOfDirectory(at: Self.sourcesURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" && $0.lastPathComponent != "Localization.swift" }
        XCTAssertGreaterThan(files.count, 40)
        var problems: [String] = []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for literal in Self.stringLiterals(text) where Self.hasJapanese(literal.value, language: "en") {
                if literal.before.hasSuffix("L10n.tr(") || literal.before.hasSuffix("comment:") { continue }
                if Self.labelKeys.contains(literal.value) { continue }
                problems.append("\(file.lastPathComponent):\(literal.line) \(literal.value)")
            }
        }
        XCTAssertEqual(problems, [], problems.joined(separator: "\n"))
    }

    /// L10n.tr の全部の文字に英語・中国語の翻訳がある
    func testEveryL10nStringIsTranslated() throws {
        let files = try FileManager.default.contentsOfDirectory(at: Self.sourcesURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" && $0.lastPathComponent != "Localization.swift" }
        var keys: Set<String> = []
        for file in files {
            let literals = Self.stringLiterals(try String(contentsOf: file, encoding: .utf8))
            for literal in literals where literal.before.hasSuffix("L10n.tr(") {
                // ソースの \n 等を実際の文字にする（Localizable.strings の键と比べる）
                let value = literal.value
                    .replacingOccurrences(of: "\\n", with: "\n").replacingOccurrences(of: "\\t", with: "\t")
                    .replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\")
                keys.insert(value)
            }
        }
        XCTAssertGreaterThan(keys.count, 300)
        for language in Self.languages {
            let table = L10n.table(for: language)
            XCTAssertGreaterThan(table.count, 300, language)
            let missing = keys.filter { table[$0] == nil }.sorted()
            XCTAssertEqual(missing, [], "\(language): \(missing.joined(separator: " / "))")
            let untranslated = table.filter { Self.hasJapanese($0.value, language: language) }.map(\.key).sorted()
            XCTAssertEqual(untranslated, [], "\(language) に日本語: \(untranslated.joined(separator: " / "))")
        }
    }

    func testTranslationLookup() {
        XCTAssertEqual(L10n.language, "ja", "単体テストは日本語")
        XCTAssertEqual(L10n.tr("キャンセル", comment: ""), "キャンセル")
        Self.inLanguage("en") {
            XCTAssertEqual(L10n.tr("キャンセル", comment: ""), "Cancel")
            XCTAssertEqual(L10n.tr("最近使ったファイル", comment: ""), "Recently Used File")
            XCTAssertEqual(EditorCore.uiLanguage, .english)
            XCTAssertEqual(EditorCore.resourceString(30101), "New")	// F_FILENEW
        }
        Self.inLanguage("zh-Hans") {
            XCTAssertEqual(L10n.tr("キャンセル", comment: ""), "取消")
            XCTAssertEqual(EditorCore.resourceString(30101), "新建")
        }
        XCTAssertEqual(EditorCore.uiLanguage, .japanese)
        XCTAssertEqual(EditorCore.resourceString(30101), "新規作成")
    }

    // MARK: - 原版的对话框模板

    static let dialogResources = ["CommonSettingsDialogs", "TypeSettingsDialogs", "OutlineDialogs", "GrepDialogs",
                                  "EditSupportDialogs", "FileSafetyDialogs", "PrintDialogs"]

    /// 英文、中文的布局与日文的控件（ID、种类、顺序）相同，文字已经翻译
    func testDialogLayoutsAreTranslated() throws {
        var problems: [String] = []
        for resource in Self.dialogResources {
            let ja = try XCTUnwrap(PropDialogs.load(resource), resource)
            for language in Self.languages {
                var other: PropDialogs?
                Self.inLanguage(language) { other = PropDialogs.load(resource) }
                let loaded = try XCTUnwrap(other, "\(language) \(resource)")
                XCTAssertEqual(ja.pages.count, loaded.pages.count)
                XCTAssertEqual(ja.dialogs?.count, loaded.dialogs?.count)
                // ページ：name は日本語のまま（ページを探す・識別子）、表示は title。対話框：name は標題（その言語）
                let pairs = zip(ja.pages, loaded.pages).map { ($0, $1, true) } + zip(ja.dialogs ?? [], loaded.dialogs ?? []).map { ($0, $1, false) }
                for (a, b, isPage) in pairs {
                    XCTAssertEqual(a.dialog, b.dialog)
                    if isPage { XCTAssertEqual(a.name, b.name) }
                    XCTAssertEqual(a.controls.map { "\($0.id) \($0.kind)" }, b.controls.map { "\($0.id) \($0.kind)" }, "\(language) \(b.dialog)")
                    let texts = (isPage ? [b.title ?? ""] : [b.name]) + b.controls.compactMap(\.text)
                    for text in texts where Self.hasJapanese(text, language: language) {
                        problems.append("\(language) \(b.dialog) \(text)")
                    }
                }
            }
        }
        XCTAssertEqual(problems, [], problems.joined(separator: "\n"))
    }

    // MARK: - 实际的界面

    func testCommonSettingsPagesAreTranslated() throws {
        var problems: [String] = []
        for language in Self.languages {
            try Self.inLanguage(language) {
                let controller = try XCTUnwrap(CommonSettingsWindowController(store: CommonSettingsTests.FakeStore()))
                defer { controller.cancel(nil) }
                let window = try XCTUnwrap(controller.window)
                for (where_, text) in Self.texts(in: try XCTUnwrap(window.contentView)) where Self.hasJapanese(text, language: language) {
                    problems.append("\(language) 窓 \(where_) \(text)")
                }
                for index in 0..<controller.pageCount {
                    let page = controller.page(index)
                    for (where_, text) in Self.texts(in: page.view, page: page) where Self.hasJapanese(text, language: language) {
                        problems.append("\(language) \(controller.pageName(index)) \(where_) \(text)")
                    }
                    problems += Self.truncated(page).map { "\(language) \(controller.pageName(index)) 切れ: \($0)" }
                }
            }
        }
        XCTAssertEqual(problems, [], problems.joined(separator: "\n"))
    }

    /// 英語・中国語のページで切れている文字。
    /// 閉じた下拉框は除く：原版の語言包でも枠（日本語と同じ大きさ）に入らない項目がある（例：「Wrap at right side of window」）。
    /// 原版の Windows 版も選んだ項目の後ろが切れて表示され、開いたメニューには全部の文字が出る（Mac 版も同じ）
    static func truncated(_ page: PropPage) -> [String] {
        PropLayoutTests.truncated(page).filter { !$0.contains(" 下拉框 ") }
    }

    func testTypeSettingsPagesAreTranslated() throws {
        var problems: [String] = []
        for language in Self.languages {
            try Self.inLanguage(language) {
                let controller = try XCTUnwrap(TypeSettingsWindowController(store: CommonSettingsTests.FakeStore(), typeIndex: 0))
                defer { controller.cancel(nil) }
                let window = try XCTUnwrap(controller.window)
                XCTAssertFalse(Self.hasJapanese(window.title, language: language), "\(language) \(window.title)")
                for index in 0..<controller.pageCount {
                    let page = controller.page(index)
                    for (where_, text) in Self.texts(in: page.view, page: page) where Self.hasJapanese(text, language: language) {
                        problems.append("\(language) \(controller.pageName(index)) \(where_) \(text)")
                    }
                    problems += Self.truncated(page).map { "\(language) \(controller.pageName(index)) 切れ: \($0)" }
                }
            }
        }
        XCTAssertEqual(problems, [], problems.joined(separator: "\n"))
    }

    /// 从页打开的对话框、Grep・印刷等的对话框：文字不被截断
    func testDialogsHaveNoTruncatedText() throws {
        var problems: [String] = []
        for language in Self.languages {
            Self.inLanguage(language) {
                for resource in ["CommonSettingsDialogs", "TypeSettingsDialogs", "EditSupportDialogs"] {
                    for definition in PropDialogs.load(resource)?.dialogs ?? [] {
                        problems += PropLayoutTests.truncated(PropPage(definition: definition)).map { "\(language) \(definition.dialog): \($0)" }
                    }
                }
            }
        }
        XCTAssertEqual(problems, [], problems.joined(separator: "\n"))
    }

    /// 菜单栏（原版的 MainMenu.ini + Mac 的 App 菜单）
    func testMainMenuIsTranslated() {
        let savedWindowsMenu = NSApp.windowsMenu
        let savedServicesMenu = NSApp.servicesMenu
        let savedHelpMenu = NSApp.helpMenu
        defer {
            NSApp.windowsMenu = savedWindowsMenu
            NSApp.servicesMenu = savedServicesMenu
            NSApp.helpMenu = savedHelpMenu
        }
        var problems: [String] = []
        for language in Self.languages {
            Self.inLanguage(language) {
                let menu = MainMenuBuilder.build()
                let all = Self.titles(of: menu)
                XCTAssertGreaterThan(all.count, 100)
                for (path, title) in all where Self.hasJapanese(title, language: language) {
                    problems.append("\(language) \(path)")
                }
            }
        }
        XCTAssertEqual(problems, [], problems.joined(separator: "\n"))
        // 英語の「ファイル」メニュー
        Self.inLanguage("en") {
            let menu = MainMenuBuilder.build()
            XCTAssertTrue(menu.items.contains { $0.title == "File" }, menu.items.map(\.title).joined(separator: ","))
        }
    }

    /// 日付・時刻の書式：曜日、午前/午後は界面の言語
    func testDateFormatFollowsLanguage() {
        var components = DateComponents()
        components.year = 2026; components.month = 1; components.day = 5; components.hour = 15; components.minute = 4; components.second = 9
        let date = Calendar(identifier: .gregorian).date(from: components)!
        XCTAssertEqual(WindowsDateFormat.date(date, type: 1, format: "dddd"), "月曜日")
        XCTAssertEqual(WindowsDateFormat.time(date, type: 1, format: "tt h"), "午後 3")
        Self.inLanguage("en") {
            XCTAssertEqual(WindowsDateFormat.date(date, type: 1, format: "dddd"), "Monday")
            XCTAssertEqual(WindowsDateFormat.time(date, type: 1, format: "tt h"), "PM 3")
            XCTAssertEqual(WindowsDateFormat.time(date, type: 0, format: ""), "3:04:09 PM")
        }
        Self.inLanguage("zh-Hans") {
            XCTAssertEqual(WindowsDateFormat.date(date, type: 1, format: "dddd"), "星期一")
            XCTAssertEqual(WindowsDateFormat.time(date, type: 1, format: "tt h"), "下午 3")
        }
    }
}

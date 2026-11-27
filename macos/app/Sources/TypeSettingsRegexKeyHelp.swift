// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge

/// タイプ別設定 > 正規表現キーワード・キーワードヘルプ（计划第 40 步第 2 个 PR。原版 CPropTypesRegex、CPropTypesKeyHelp）。
///
/// 値は sakura.ini の RxKey[000]～（「色の名前,キーワード」）、KDct[00]～（「使う,辞書の説明,パス」）。
/// 一覧が短くなったときは、なくなった項目に空の値を書く（核心库は空の値の項目がなくてもよい）。

/// 一覧の項目を動かす・入れる・消す（原版の 先頭・上へ・下へ・最終・挿入・削除。行はそのまま持ち運ぶ）
enum ListEditing {
    /// index の行を to へ動かす。動かしたら新しい位置
    static func move<T>(_ rows: inout [T], from index: Int, to: Int) -> Int? {
        guard rows.indices.contains(index) else { return nil }
        let target = min(max(to, 0), rows.count - 1)
        guard target != index else { return nil }
        let row = rows.remove(at: index)
        rows.insert(row, at: target)
        return target
    }
}

// MARK: - 正規表現キーワード（CPropTypesRegex.cpp）

final class TypeRegexPage: CommonSettingsPageLogic {
    static let maxKeywords = 100	// MAX_REGEX_KEYWORD
    let typeIndex: Int
    /// 色指定に使える色（文字色と背景色がある色。原版 SetData のコンボボックス）
    let colorItems: [EditorColorItem]
    /// 一覧（キーワード、色の番号）
    private(set) var keywords: [(keyword: String, color: Int)] = []
    /// 前回選んでいた行（原版 nPrevIndex：同じ行のときはエディットに写さない）
    private var lastPosition = -1
    private let regex1: Int

    init(typeIndex: Int) {
        self.typeIndex = typeIndex
        let all = EditorCore.colorItems
        colorItems = all.filter { !$0.noText && !$0.noBack }
        regex1 = all.first { $0.key == "C[RK1]" }?.index ?? 0
    }

    private static func key(_ i: Int) -> String { String(format: "RxKey[%03d]", i) }

    /// 「RK1」等（sakura.ini の色の名前）→ 色の番号
    private func colorIndex(shortName: String) -> Int {
        EditorCore.colorItems.first { $0.key == "C[\(shortName)]" }?.index ?? (Int(shortName) ?? regex1)
    }

    private func shortName(_ color: Int) -> String {
        let key = EditorCore.colorItems.first { $0.index == color }?.key ?? "C[RK1]"
        return String(key.dropFirst(2).dropLast())
    }

    private func colorName(_ color: Int) -> String {
        EditorCore.colorItems.first { $0.index == color }?.name ?? ""
    }

    func setData(_ page: PropPage, _ values: CommonSettingsValues) {
        page.setChecked(idc("CHECK_REGEX"), values.bool("bUseRegexKeyword"))
        // Mac 版は組み込みの正規表現ライブラリ（原版 CheckRegexpVersion）
        let version = EditorCore.regexpVersion
        page.setText(idc("LABEL_REGEX_VERSION"), version.isEmpty
            ? L10n.tr("正規表現キーワードは使えません。", comment: "STR_PROPTYPEREGEX_NOUSE") : version)
        page.setTaggedItems(idc("COMBO_REGEX_COLOR"), colorItems.map { (Int($0.index), $0.name) }, selectedValue: regex1)
        if let list = page.list(idc("LIST_REGEX")), list.table.tableColumns.count < 2, let scroll = page.control(idc("LIST_REGEX")) {
            let width = scroll.frame.width
            list.setColumns([L10n.tr("キーワード", comment: "STR_PROPTYPEREGEX_LIST1"),
                             L10n.tr("色指定", comment: "STR_PROPTYPEREGEX_LIST2")],
                            widths: [(width * 54 / 100).rounded(), (width * 38 / 100).rounded()])
        }
        loadKeywords(values)
        showKeywords(page)
        page.setText(idc("EDIT_REGEX"), "//k")
        if !keywords.isEmpty { page.list(idc("LIST_REGEX"))?.select(0) }
        selectionChanged(page)
    }

    private func loadKeywords(_ values: CommonSettingsValues) {
        keywords = []
        for i in 0..<Self.maxKeywords {
            let value = values.string(Self.key(i))
            guard let comma = value.firstIndex(of: ","), !value.isEmpty else { break }
            let keyword = String(value[value.index(after: comma)...])
            if keyword.isEmpty { break }
            keywords.append((keyword, colorIndex(shortName: String(value[..<comma]))))
        }
    }

    private func showKeywords(_ page: PropPage) {
        lastPosition = -1
        page.list(idc("LIST_REGEX"))?.setRows(keywords.map { [$0.keyword, colorName($0.color)] })
    }

    func getData(_ page: PropPage, _ values: CommonSettingsValues) {
        values.set(page.isChecked(idc("CHECK_REGEX")), "bUseRegexKeyword")
        for (i, entry) in keywords.enumerated() {
            values.set("\(shortName(entry.color)),\(entry.keyword)", Self.key(i))
        }
        // 減った項目は空にする
        for i in keywords.count..<Self.maxKeywords where !values.string(Self.key(i)).isEmpty {
            values.set("", Self.key(i))
        }
    }

    func changed(_ id: String, _ page: PropPage, _ values: CommonSettingsValues) {
        if id == idc("LIST_REGEX") { selectionChanged(page) }
    }

    /// 原版 LVN_ITEMCHANGED：選んだ行をエディットと色へ。選んでいなければ初期値
    private func selectionChanged(_ page: PropPage) {
        let index = page.list(idc("LIST_REGEX"))?.selectedRow ?? -1
        if index == -1 {
            page.setText(idc("EDIT_REGEX"), "//k")
            page.setTaggedItems(idc("COMBO_REGEX_COLOR"), colorItems.map { (Int($0.index), $0.name) }, selectedValue: regex1)
        } else if index != lastPosition, keywords.indices.contains(index) {
            page.setText(idc("EDIT_REGEX"), keywords[index].keyword)
            page.setTaggedItems(idc("COMBO_REGEX_COLOR"), colorItems.map { (Int($0.index), $0.name) }, selectedValue: keywords[index].color)
        }
        lastPosition = index
    }

    /// 原版 CheckKeywordList：囲み、文法（間違っていても登録できる）、同じキーワード
    private func check(_ keyword: String, updating: Int) -> Bool {
        guard EditorCore.regexKeywordHasDelimiters(keyword) else {
            TypeSettingsPages.showMessage(L10n.tr("正規表現キーワードを / と /k で囲ってください。\nキーワードに / がある場合は m# と #k で囲ってください。", comment: "STR_PROPTYPEREGEX_KAKOMI"))
            return false
        }
        if !EditorCore.regexKeywordSyntaxOK(keyword),
           !CommonSettingsPages.confirm(L10n.tr("書式が正しくないか、正規表現ライブラリが見つかりません。\n\n登録しますか？", comment: "STR_PROPTYPEREGEX_INVALID")) {
            return false
        }
        if keywords.enumerated().contains(where: { $0.offset != updating && $0.element.keyword == keyword }) {
            TypeSettingsPages.showMessage(L10n.tr("同じキーワードで登録済みです。", comment: "STR_PROPTYPEREGEX_ALREADY"))
            return false
        }
        return true
    }

    func buttonPressed(_ id: String, _ page: PropPage, _ values: CommonSettingsValues, window: NSWindow?) {
        guard let list = page.list(idc("LIST_REGEX")) else { return }
        let index = list.selectedRow
        let keyword = page.text(idc("EDIT_REGEX"))
        let color = page.selectedTag(idc("COMBO_REGEX_COLOR")) ?? regex1
        var select: Int?
        switch id {
        case idc("BUTTON_REGEX_INS"), idc("BUTTON_REGEX_ADD"):
            guard keywords.count < Self.maxKeywords else {
                TypeSettingsPages.showMessage(L10n.tr("これ以上登録できません。", comment: "STR_PROPTYPEREGEX_NOREG"))
                return
            }
            guard check(keyword, updating: -1) else { return }
            let at = id == idc("BUTTON_REGEX_INS") && index != -1 ? index : keywords.count
            keywords.insert((keyword, color), at: at)
            select = at
        case idc("BUTTON_REGEX_UPD"):
            guard index != -1 else {
                TypeSettingsPages.showMessage(L10n.tr("キーワードが選択されていません。", comment: "STR_PROPTYPEREGEX_NOSEL"))
                return
            }
            guard check(keyword, updating: index) else { return }
            keywords[index] = (keyword, color)
            select = index
        case idc("BUTTON_REGEX_DEL"):
            guard keywords.indices.contains(index) else { return }
            keywords.remove(at: index)
            select = keywords.indices.contains(index) ? index : nil
        case idc("BUTTON_REGEX_TOP"): select = ListEditing.move(&keywords, from: index, to: 0)
        case idc("BUTTON_REGEX_UP"): select = ListEditing.move(&keywords, from: index, to: index - 1)
        case idc("BUTTON_REGEX_DOWN"): select = ListEditing.move(&keywords, from: index, to: index + 1)
        case idc("BUTTON_REGEX_LAST"): select = ListEditing.move(&keywords, from: index, to: keywords.count - 1)
        case idc("BUTTON_REGEX_IMPORT"):
            importFile(page, values, window)
            return
        case idc("BUTTON_REGEX_EXPORT"):
            getData(page, values)
            TypeSettingsPages.exportFile(.regexKeywords, typeIndex: typeIndex, values: values, extensions: ["rkw"], window: window)
            return
        default:
            return
        }
        showKeywords(page)
        if let select {
            list.select(select)
            lastPosition = select	// 選んだ行はエディットに写さない（今の入力のまま）
        }
    }

    private func importFile(_ page: PropPage, _ values: CommonSettingsValues, _ window: NSWindow?) {
        getData(page, values)
        guard TypeSettingsPages.importFile(.regexKeywords, typeIndex: typeIndex, values: values, extensions: ["rkw"], window: window) else { return }
        loadKeywords(values)
        showKeywords(page)
        if !keywords.isEmpty { page.list(idc("LIST_REGEX"))?.select(0) }
        selectionChanged(page)
    }
}

// MARK: - キーワードヘルプ（CPropTypesKeyHelp.cpp）

/// 右クリックメニュー（原版 nKeyHelpRMenuType。値は EKeyHelpRMenuType）
let keyHelpMenuTypes: NamedValues = [
    (0, L10n.tr("表示しない", comment: "STR_KEYHELP_RMENU_NONE")),
    (1, L10n.tr("先頭に表示", comment: "STR_KEYHELP_RMENU_TOP")),
    (2, L10n.tr("末尾に表示", comment: "STR_KEYHELP_RMENU_BOTTOM")),
]

final class TypeKeyHelpPage: CommonSettingsPageLogic {
    static let maxFiles = 20	// MAX_KEYHELP_FILE
    let typeIndex: Int
    /// 辞書の一覧（使う、辞書の説明、パス）
    private(set) var dictionaries: [(use: Bool, about: String, path: String)] = []

    private let checks: [(id: String, key: String)] = [
        (idc("CHECK_KEYHELP"), "bUseKeyWordHelp"),
        (idc("CHECK_KEYHELP_ALLSEARCH"), "bUseKeyHelpAllSearch"),
        (idc("CHECK_KEYHELP_KEYDISP"), "bUseKeyHelpKeyDisp"),
        (idc("CHECK_KEYHELP_PREFIX"), "bUseKeyHelpPrefix"),
    ]

    init(typeIndex: Int) {
        self.typeIndex = typeIndex
    }

    private static func key(_ i: Int) -> String { String(format: "KDct[%02d]", i) }

    func setData(_ page: PropPage, _ values: CommonSettingsValues) {
        page.loadChecks(checks, values)
        page.loadCombo(idc("COMBO_MENU"), keyHelpMenuTypes, value: values.int("nKeyHelpRMenuShowType"))
        if let list = page.list(idc("LIST_KEYHELP")), list.table.tableColumns.count < 3, let scroll = page.control(idc("LIST_KEYHELP")) {
            let width = scroll.frame.width
            list.setColumns([L10n.tr("    辞書ファイル", comment: "STR_PROPTYPKEYHELP_DIC"),
                             L10n.tr("辞書の説明", comment: "STR_PROPTYPKEYHELP_INFO"),
                             L10n.tr("パス", comment: "STR_PROPTYPKEYHELP_PATH")],
                            widths: [(width * 25 / 100).rounded(), (width * 55 / 100).rounded(), (width * 18 / 100).rounded()])
            // 1 列目はチェックボックス（原版 LVS_EX_CHECKBOXES）とファイル名
            list.cellView = { [weak self] row, column in
                guard let self, column == 0, self.dictionaries.indices.contains(row) else { return nil }
                let check = NSButton(checkboxWithTitle: Self.fileName(self.dictionaries[row].path), target: self, action: #selector(self.useClicked(_:)))
                check.font = PropPage.font
                check.controlSize = .small
                check.tag = row
                check.state = self.dictionaries[row].use ? .on : .off
                return check
            }
        }
        loadDictionaries(values)
        showDictionaries(page)
        if dictionaries.isEmpty {
            showPlaceholder(page)
        } else {
            page.list(idc("LIST_KEYHELP"))?.select(0)
            selectionChanged(page)
        }
    }

    @objc private func useClicked(_ sender: NSButton) {
        setUse(sender.tag, sender.state == .on)
    }

    /// チェックボックス（使う／使わない）
    func setUse(_ row: Int, _ use: Bool) {
        guard dictionaries.indices.contains(row) else { return }
        dictionaries[row].use = use
    }

    static func fileName(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }

    /// 一覧が空のときの説明（原版：初期値として用途を表示）
    private func showPlaceholder(_ page: PropPage) {
        page.setText(idc("LABEL_KEYHELP_ABOUT"), L10n.tr("辞書ファイルの１行目の文字列", comment: "STR_PROPTYPKEYHELP_LINE1"))
        page.setText(idc("EDIT_KEYHELP"), L10n.tr("キーワード辞書ファイル パス", comment: "STR_PROPTYPKEYHELP_DICPATH"))
    }

    private func loadDictionaries(_ values: CommonSettingsValues) {
        dictionaries = []
        for i in 0..<Self.maxFiles {
            // 「使う,辞書の説明,パス」（パスにカンマがあってもよい）
            let parts = values.string(Self.key(i)).split(separator: ",", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 3, !parts[2].isEmpty else { break }
            dictionaries.append((use: (Int(parts[0]) ?? 0) != 0, about: parts[1], path: parts[2]))
        }
    }

    private func showDictionaries(_ page: PropPage) {
        page.list(idc("LIST_KEYHELP"))?.setRows(dictionaries.map { [Self.fileName($0.path), $0.about, $0.path] })
    }

    func getData(_ page: PropPage, _ values: CommonSettingsValues) {
        page.storeChecks(checks, values)
        values.set(page.selectedIndex(idc("COMBO_MENU")), "nKeyHelpRMenuShowType")
        for (i, dictionary) in dictionaries.enumerated() {
            values.set("\(dictionary.use ? 1 : 0),\(dictionary.about),\(dictionary.path)", Self.key(i))
        }
        for i in dictionaries.count..<Self.maxFiles where !values.string(Self.key(i)).isEmpty {
            values.set("", Self.key(i))
        }
    }

    func enable(_ page: PropPage) {
        let on = page.isChecked(idc("CHECK_KEYHELP"))
        for id in ["FRAME_KEYHELP", "LIST_KEYHELP", "LABEL_KEYHELP_TITLE", "LABEL_KEYHELP_ABOUT", "BUTTON_KEYHELP_UPD",
                   "LABEL_KEYHELP_KEYWORD", "EDIT_KEYHELP", "BUTTON_KEYHELP_REF", "LABEL_KEYHELP_PRIOR", "BUTTON_KEYHELP_TOP",
                   "BUTTON_KEYHELP_UP", "BUTTON_KEYHELP_DOWN", "BUTTON_KEYHELP_LAST", "BUTTON_KEYHELP_INS", "BUTTON_KEYHELP_DEL",
                   "CHECK_KEYHELP_ALLSEARCH", "CHECK_KEYHELP_KEYDISP", "CHECK_KEYHELP_PREFIX", "STATIC_MENU", "COMBO_MENU"] {
            page.setEnabled(idc(id), on)
        }
    }

    func changed(_ id: String, _ page: PropPage, _ values: CommonSettingsValues) {
        if id == idc("LIST_KEYHELP") { selectionChanged(page) }
    }

    /// 原版 LVN_ITEMCHANGED：選んだ辞書の説明とパス
    private func selectionChanged(_ page: PropPage) {
        let index = page.list(idc("LIST_KEYHELP"))?.selectedRow ?? -1
        guard dictionaries.indices.contains(index) else { return }
        page.setText(idc("LABEL_KEYHELP_ABOUT"), dictionaries[index].about)
        page.setText(idc("EDIT_KEYHELP"), dictionaries[index].path)
    }

    func buttonPressed(_ id: String, _ page: PropPage, _ values: CommonSettingsValues, window: NSWindow?) {
        guard let list = page.list(idc("LIST_KEYHELP")) else { return }
        let index = list.selectedRow
        var select: Int?
        switch id {
        case idc("BUTTON_KEYHELP_INS"), idc("BUTTON_KEYHELP_UPD"):
            let insert = id == idc("BUTTON_KEYHELP_INS")
            if insert && dictionaries.count >= Self.maxFiles {
                TypeSettingsPages.showMessage(L10n.tr("これ以上登録できません。", comment: "STR_PROPTYPKEYHELP_ERR_REG1"))
                return
            }
            if !insert && index == -1 {
                TypeSettingsPages.showMessage(L10n.tr("更新する辞書をリストから選択してください。", comment: "STR_PROPTYPKEYHELP_SELECT"))
                return
            }
            let path = page.text(idc("EDIT_KEYHELP"))
            guard !path.isEmpty else { return }
            if dictionaries.enumerated().contains(where: { $0.element.path == path && !(!insert && $0.offset == index) }) {
                TypeSettingsPages.showMessage(L10n.tr("既に登録済みの辞書です。", comment: "STR_PROPTYPKEYHELP_ERR_REG2"))
                return
            }
            guard let about = EditorCore.keywordHelpDictionaryAbout(path) else {
                TypeSettingsPages.showMessage(String(format: L10n.tr("ファイルを開けませんでした。\n\n%@", comment: "STR_PROPTYPKEYHELP_ERR_OPEN"), path))
                return
            }
            page.setText(idc("LABEL_KEYHELP_ABOUT"), about)
            let at = insert ? (index == -1 ? dictionaries.count : index) : index
            if !insert { dictionaries.remove(at: index) }
            dictionaries.insert((use: true, about: about, path: path), at: at)	// 登録した辞書は使う
            select = at
        case idc("BUTTON_KEYHELP_DEL"):
            guard dictionaries.indices.contains(index) else { return }
            dictionaries.remove(at: index)
            select = dictionaries.isEmpty ? nil : min(index, dictionaries.count - 1)
            if dictionaries.isEmpty {
                showDictionaries(page)
                showPlaceholder(page)
                return
            }
        case idc("BUTTON_KEYHELP_TOP"): select = ListEditing.move(&dictionaries, from: index, to: 0)
        case idc("BUTTON_KEYHELP_UP"): select = ListEditing.move(&dictionaries, from: index, to: index - 1)
        case idc("BUTTON_KEYHELP_DOWN"): select = ListEditing.move(&dictionaries, from: index, to: index + 1)
        case idc("BUTTON_KEYHELP_LAST"): select = ListEditing.move(&dictionaries, from: index, to: dictionaries.count - 1)
        case idc("BUTTON_KEYHELP_REF"):
            if let path = TypeSettingsPages.chooseFile(page.text(idc("EDIT_KEYHELP")), ["khp"], window) {
                page.setText(idc("EDIT_KEYHELP"), path)
            }
            return
        case idc("BUTTON_KEYHELP_IMPORT"):
            getData(page, values)
            guard TypeSettingsPages.importFile(.keywordHelp, typeIndex: typeIndex, values: values, extensions: ["txt"], window: window) else { return }
            loadDictionaries(values)
            showDictionaries(page)
            if !dictionaries.isEmpty {
                list.select(0)
                selectionChanged(page)
            }
            return
        case idc("BUTTON_KEYHELP_EXPORT"):
            getData(page, values)
            TypeSettingsPages.exportFile(.keywordHelp, typeIndex: typeIndex, values: values, extensions: ["txt"], window: window)
            return
        default:
            return
        }
        showDictionaries(page)
        if let select {
            list.select(select)
            selectionChanged(page)
        }
    }
}

// MARK: - インポート・エクスポート（原版 CImpExpManager::ImportUI / ExportUI）

extension TypeSettingsPages {
    /// ファイルを選んで読み込み、窗口の値を換える。読めたら true（メッセージは原版と同じ）
    @discardableResult
    static func importFile(_ kind: EditorTypeSettingFile, typeIndex: Int, values: CommonSettingsValues,
                           extensions: [String], window: NSWindow?) -> Bool {
        guard let path = chooseImportFile(extensions, window) else { return false }
        let result = EditorCore.importTypeSettingFile(kind, typeIndex: typeIndex, pending: values.pending, path: path)
        guard result.succeeded else {
            showMessage(result.message)
            return false
        }
        for (key, value) in result.values.sorted(by: { $0.key < $1.key }) where values.string(key) != value {
            values.set(value, key)
        }
        if !result.message.isEmpty { showMessage(result.message) }
        return true
    }

    /// ファイルを選んで書き出す
    static func exportFile(_ kind: EditorTypeSettingFile, typeIndex: Int, values: CommonSettingsValues,
                           extensions: [String], window: NSWindow?) {
        guard let path = chooseExportFile("", extensions, window) else { return }
        let result = EditorCore.exportTypeSettingFile(kind, typeIndex: typeIndex, pending: values.pending, path: path)
        showMessage(result.succeeded
            ? L10n.tr("ファイルをエクスポートしました。\n\n", comment: "STR_IMPEXP_OK_EXPORT") + path
            : result.message)
    }
}

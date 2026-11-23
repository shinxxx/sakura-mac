// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge

/// 共通設定 > 強調キーワード（计划第 40 步第 3 个 PR。原版 CPropKeyword）。
///
/// - キーワードの編集は核心库の複製（EditorKeywordSetEditor。原版 CPropCommon::m_Common と同じ）の上で行い、
///   GetData で sakura.ini の [KeyWords] の値（szSN[nn]、nCASE[nn]、nKWN[nn]、szKW[nn] 等）にする。
/// - セットを削除すると、そのセットを使っているタイプ別設定の強調キーワードは「なし」、後ろのセットは 1 つ前に（原版と同じ）。
///   タイプ別設定の値（[Types(N)] の nInts、nKeywordSelect3～10）もここで書く。
/// - タイプ別設定 > カラー の「共通設定...」からは、このページだけの対話框として開く（tempSets：編集中のタイプの強調キーワード）。
final class KeywordSettingsPage: CommonSettingsPageLogic {
    static let maxSets = 100		// MAX_SETNUM
    static let maxSetName = 32		// MAX_SETNAMELEN
    static let maxKeyword = 63		// MAX_KEYWORDLEN

    private(set) var editor: EditorKeywordSetEditor?
    /// 各タイプの強調キーワード 1～10（原版 m_Types_nKeyWordSetIdx）
    private var typeSets: [(index: Int, sets: [Int])] = []
    private var originalTypeSets: [Int: [Int]] = [:]
    /// タイプ別設定から開いたとき、編集中のタイプの強調キーワード 1～10（原版 InitData の第 1 引数）
    var tempSets: [Int]?
    /// タイプ別設定から開いたとき、編集中のタイプの名前と拡張子（削除の確認に「(Temp)」として出す）
    var tempTypeName = ""
    var tempTypeExts = ""
    /// 編集中のタイプ（タイプ別設定から開いたときは、そのタイプのセットは tempSets で扱う）
    var tempTypeIndex: Int?

    // MARK: SetData / GetData

    func setData(_ page: PropPage, _ values: CommonSettingsValues) {
        // 共通設定のページのときは OK・キャンセル はない（原版：独立ウィンドウのときだけ表示）
        page.control("IDOK")?.isHidden = tempTypeIndex == nil
        page.control("IDCANCEL")?.isHidden = tempTypeIndex == nil
        page.list(idc("LIST_KEYWORD"))?.table.headerView = nil	// 原版 LVS_NOCOLUMNHEADER
        editor = EditorKeywordSetEditor()
        typeSets = EditorCore.typeSettings.compactMap { type in
            if type.index == tempTypeIndex { return nil }
            return (type.index, Self.keywordSets(values, section: "Types(\(type.index))"))
        }
        originalTypeSets = Dictionary(uniqueKeysWithValues: typeSets.map { ($0.index, $0.sets) })
        if let tempSets, let first = tempSets.first, first >= 0 { editor?.currentSet = first }	// 原版：強調キーワード 1 のセットから
        page.list(idc("LIST_KEYWORD"))?.onDoubleClick = { [weak self, weak page] _, _ in
            guard let self, let page else { return }
            self.editKeyword(page)
        }
        loadSets(page)
    }

    /// タイプの強調キーワード 1～10（nInts の 5・6 番目と nKeywordSelect3～10）
    static func keywordSets(_ values: CommonSettingsValues, section: String) -> [Int] {
        let ints = values.string("nInts", section: section).split(separator: ",").map { Int($0.trimmingCharacters(in: .whitespaces)) ?? -1 }
        var sets = [ints.count == 12 ? ints[4] : -1, ints.count == 12 ? ints[5] : -1]
        for i in 3...10 { sets.append(Int(values.string("nKeywordSelect\(i)", section: section)) ?? -1) }
        return sets
    }

    static func storeKeywordSets(_ sets: [Int], _ values: CommonSettingsValues, section: String) {
        var ints = values.string("nInts", section: section).split(separator: ",").map { Int($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
        if ints.count == 12 {
            ints[4] = sets[0]
            ints[5] = sets[1]
            values.set(ints.map(String.init).joined(separator: ","), "nInts", section: section)
        }
        for i in 3...10 { values.set(sets[i - 1], "nKeywordSelect\(i)", section: section) }
    }

    func getData(_ page: PropPage, _ values: CommonSettingsValues) {
        guard let editor else { return }
        for (key, value) in editor.iniValues.sorted(by: { $0.key < $1.key }) where values.string(key, section: "KeyWords") != value {
            values.set(value, key, section: "KeyWords")
        }
        for type in typeSets where originalTypeSets[type.index] != type.sets {
            Self.storeKeywordSets(type.sets, values, section: "Types(\(type.index))")
        }
    }

    // MARK: 表示

    private var currentSet: Int { editor?.currentSet ?? -1 }

    /// 原版 SetData：セット名のコンボボックスと、選んだセットのキーワード
    private func loadSets(_ page: PropPage) {
        guard let editor else { return }
        page.setTaggedItems(idc("COMBO_SET"), (0..<editor.setCount).map { ($0, editor.name(ofSet: $0)) },
                            selectedValue: currentSet, selectIfMissing: nil)
        showSet(page)
    }

    /// 原版 SetKeyWordSet
    private func showSet(_ page: PropPage) {
        guard let editor else { return }
        let set = currentSet
        page.setChecked(idc("CHECK_KEYWORDCASE"), set >= 0 && editor.isCaseSensitive(set))
        page.list(idc("LIST_KEYWORD"))?.setRows(set >= 0 ? editor.keywords(ofSet: set).map { [$0] } : [])
        showCount(page)
    }

    /// 原版 DispKeywordCount
    private func showCount(_ page: PropPage) {
        guard let editor, currentSet >= 0 else {
            page.setText(idc("STATIC_KEYWORD_COUNT"), "")
            return
        }
        let count = page.list(idc("LIST_KEYWORD"))?.rows.count ?? 0
        page.setText(idc("STATIC_KEYWORD_COUNT"), String(format: NSLocalizedString("(最大 %d 文字, 登録数 %d, 空き %d 個)", comment: "STR_PROPCOMKEYWORD_INFO"),
                                                          Self.maxKeyword, count, editor.freeCount(ofSet: currentSet)))
    }

    func enable(_ page: PropPage) {
        let hasSet = currentSet >= 0
        for id in ["BUTTON_KEYSETRENAME", "BUTTON_DELSET", "CHECK_KEYWORDCASE", "LIST_KEYWORD", "BUTTON_ADDKEYWORD",
                   "BUTTON_KEYCLEAN", "BUTTON_IMPORT", "BUTTON_EXPORT"] {
            page.setEnabled(idc(id), hasSet)
        }
        let selected = hasSet && (page.list(idc("LIST_KEYWORD"))?.selectedRow ?? -1) >= 0
        page.setEnabled(idc("BUTTON_EDITKEYWORD"), selected)
        page.setEnabled(idc("BUTTON_DELKEYWORD"), selected)
    }

    func changed(_ id: String, _ page: PropPage, _ values: CommonSettingsValues) {
        guard let editor else { return }
        switch id {
        case idc("COMBO_SET"):
            if let set = page.selectedTag(id) {
                editor.currentSet = set
                showSet(page)
            }
        case idc("CHECK_KEYWORDCASE"):
            editor.setCaseSensitive(page.isChecked(id), ofSet: currentSet)
        default:
            break
        }
    }

    // MARK: ボタン

    func buttonPressed(_ id: String, _ page: PropPage, _ values: CommonSettingsValues, window: NSWindow?) {
        guard let editor else { return }
        switch id {
        case idc("BUTTON_ADDSET"):
            guard editor.setCount < Self.maxSets else {
                CommonSettingsPages.inform(String(format: NSLocalizedString("セットは%d個までしか登録できません。\n", comment: "STR_PROPCOMKEYWORD_SETMAX"), Self.maxSets))
                return
            }
            guard let name = CommonSettingsPages.input(NSLocalizedString("キーワードのセット追加", comment: "STR_PROPCOMKEYWORD_SETNAME1"),
                                                       NSLocalizedString("セット名を入力してください。", comment: "STR_PROPCOMKEYWORD_SETNAME2"),
                                                       Self.maxSetName, ""), !name.isEmpty else { return }
            if editor.addSet(name) { loadSets(page) }
        case idc("BUTTON_DELSET"):
            deleteSet(page)
        case idc("BUTTON_KEYSETRENAME"):
            guard currentSet >= 0,
                  let name = CommonSettingsPages.input(NSLocalizedString("セットの名称変更", comment: "STR_PROPCOMKEYWORD_RENAME1"),
                                                       NSLocalizedString("セット名を入力してください。", comment: "STR_PROPCOMKEYWORD_RENAME2"),
                                                       Self.maxSetName, editor.name(ofSet: currentSet)), !name.isEmpty else { return }
            editor.renameSet(currentSet, to: name)
            loadSets(page)
        case idc("BUTTON_ADDKEYWORD"):
            guard currentSet >= 0 else { return }
            guard editor.canAddKeyword(toSet: currentSet) else {
                CommonSettingsPages.inform(NSLocalizedString("登録できるキーワード数が上限に達しています。\n", comment: "STR_PROPCOMKEYWORD_KEYMAX"))
                return
            }
            guard let keyword = CommonSettingsPages.input(NSLocalizedString("キーワード追加", comment: "STR_PROPCOMKEYWORD_KEYADD1"),
                                                          NSLocalizedString("キーワードを入力してください。", comment: "STR_PROPCOMKEYWORD_KEYADD2"),
                                                          Self.maxKeyword, ""), !keyword.isEmpty else { return }
            if editor.addKeyword(keyword, toSet: currentSet) == 0 {
                showSet(page)
                if let row = editor.keywords(ofSet: currentSet).firstIndex(of: keyword) { page.list(idc("LIST_KEYWORD"))?.select(row) }
            }
        case idc("BUTTON_EDITKEYWORD"):
            editKeyword(page)
        case idc("BUTTON_DELKEYWORD"):
            guard let row = selectedRow(page) else { return }
            editor.deleteKeyword(editor.keywordIndices(ofSet: currentSet)[row].intValue, ofSet: currentSet)
            showSet(page)
            page.list(idc("LIST_KEYWORD"))?.select(row)
        case idc("BUTTON_KEYCLEAN"):
            guard currentSet >= 0,
                  CommonSettingsPages.confirm(NSLocalizedString("現在の設定では強調キーワードとして表示できないキーワードを削除しますか？", comment: "STR_PROPCOMKEYWORD_DEL")) else { return }
            _ = editor.clean(set: currentSet)
            showSet(page)
        case idc("BUTTON_IMPORT"):
            guard currentSet >= 0, let path = TypeSettingsPages.chooseImportFile(["kwd"], window) else { return }
            var message: NSString?
            let ok = editor.importFile(toSet: currentSet, path: path, message: &message)
            if !ok || !(message?.length == 0) { TypeSettingsPages.showMessage(message as String? ?? "") }
            showSet(page)
        case idc("BUTTON_EXPORT"):
            guard currentSet >= 0, let path = TypeSettingsPages.chooseExportFile(editor.name(ofSet: currentSet), ["kwd"], window) else { return }
            var message: NSString?
            let ok = editor.exportFile(set: currentSet, path: path, message: &message)
            TypeSettingsPages.showMessage(ok ? NSLocalizedString("ファイルをエクスポートしました。\n\n", comment: "STR_IMPEXP_OK_EXPORT") + path
                                             : message as String? ?? "")
        default:
            break
        }
    }

    private func selectedRow(_ page: PropPage) -> Int? {
        guard currentSet >= 0, let row = page.list(idc("LIST_KEYWORD"))?.selectedRow, row >= 0 else { return nil }
        return row
    }

    /// 原版 Edit_List_KeyWord：空にすると削除
    private func editKeyword(_ page: PropPage) {
        guard let editor, let row = selectedRow(page) else { return }
        let index = editor.keywordIndices(ofSet: currentSet)[row].intValue
        guard let keyword = CommonSettingsPages.input(NSLocalizedString("キーワード編集", comment: "STR_PROPCOMKEYWORD_KEYEDIT1"),
                                                      NSLocalizedString("キーワードを編集してください。", comment: "STR_PROPCOMKEYWORD_KEYEDIT2"),
                                                      Self.maxKeyword, editor.keywords(ofSet: currentSet)[row]) else { return }
        if keyword.isEmpty {
            editor.deleteKeyword(index, ofSet: currentSet)
        } else {
            _ = editor.updateKeyword(index, ofSet: currentSet, to: keyword)
        }
        showSet(page)
        page.list(idc("LIST_KEYWORD"))?.select(row)
    }

    /// 原版 IDC_BUTTON_DELSET：使っているタイプを示して確認し、タイプの強調キーワードを直してから削除
    private func deleteSet(_ page: PropPage) {
        guard let editor, currentSet >= 0 else { return }
        let set = currentSet
        var label = ""
        if let tempSets, tempSets.contains(set) {
            label += "・(Temp)\(tempTypeName)(\(tempTypeExts))\n"
        }
        let types = Dictionary(uniqueKeysWithValues: EditorCore.typeSettings.map { ($0.index, $0) })
        for type in typeSets where type.sets.contains(set) {
            if let info = types[type.index] { label += "・\(info.name)(\(info.extensions))\n" }
        }
        let message = String(format: NSLocalizedString("「%@」のセットを削除します。\nよろしいですか？\n削除しようとするセットは、以下のファイルタイプに割り当てられています。\n削除したセットは無効になります。\n\n%@", comment: "STR_PROPCOMKEYWORD_SETDEL"),
                             editor.name(ofSet: set), label)
        guard CommonSettingsPages.confirm(message) else { return }
        func adjust(_ sets: [Int]) -> [Int] { sets.map { $0 == set ? -1 : $0 > set ? $0 - 1 : $0 } }
        typeSets = typeSets.map { ($0.index, adjust($0.sets)) }
        if let sets = tempSets { tempSets = adjust(sets) }
        _ = editor.deleteSet(set)
        loadSets(page)
    }
}

// MARK: - 「共通設定 - 強調キーワード」の対話框（タイプ別設定 > カラー の「共通設定...」。原版 CPropKeyword::DlgProc_dialog）

final class KeywordSettingsDialog: NSObject {
    let page: PropPage
    let logic: KeywordSettingsPage
    let values: CommonSettingsValues
    let title: String
    var onClose: ((Bool) -> Void)?

    init?(store: CommonSettingsStore = CoreCommonSettingsStore(), tempSets: [Int], typeIndex: Int, typeName: String, typeExts: String) {
        guard let definition = PropDialogs.load()?.pages.first(where: { $0.dialog == "IDD_PROP_KEYWORD" }) else { return nil }
        page = PropPage(definition: definition)
        logic = KeywordSettingsPage()
        logic.tempSets = tempSets
        logic.tempTypeIndex = typeIndex
        logic.tempTypeName = typeName
        logic.tempTypeExts = typeExts
        values = CommonSettingsValues(store: store)
        title = NSLocalizedString("共通設定", comment: "STR_PROPCOMMON") + " - " + NSLocalizedString("強調キーワード", comment: "STR_PROPCOMMON_KEYWORD")
        super.init()
        // 原版：独立ウィンドウのときは OK・キャンセル の下までの大きさ
        if let ok = page.control("IDOK") {
            page.view.setFrameSize(NSSize(width: page.view.frame.width, height: ok.frame.maxY + 12))
        }
        logic.setData(page, values)
        logic.enable(page)
        page.onChange = { [weak self] id in
            guard let self else { return }
            self.logic.changed(id, self.page, self.values)
            self.logic.enable(self.page)
        }
        page.onButton = { [weak self] id in
            guard let self else { return }
            switch id {
            case "IDOK": self.onClose?(true)
            case "IDCANCEL": self.onClose?(false)
            default:
                self.logic.buttonPressed(id, self.page, self.values, window: self.page.view.window)
                self.logic.enable(self.page)
            }
        }
    }

    /// OK：すぐに書き込む（原版 ApplyData）。変わったとき true
    @discardableResult
    func apply() -> Bool {
        logic.getData(page, values)
        let changed = !values.changes.isEmpty
        values.apply()
        return changed
    }
}

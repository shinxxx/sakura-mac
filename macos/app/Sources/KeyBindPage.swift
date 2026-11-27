// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge

/// 共通設定 > キー割り当て（计划第 41 步。原版 CPropKeybind）。
///
/// - 编辑在核心库的复制上（EditorCommandSettingsEditor，原版 CPropCommon::m_Common）。メインメニュー・ツールバー・
///   カスタムメニュー 页也用同一个复制（CommonSettingsValues.commandEditor）。
/// - GetData 时把 sakura.ini 的 [KeyBind] 的值（KeyBind[nnn]）写进窗口的值，OK 时写回核心库。
/// - Mac 方案（默认）时原版的 Ctrl 是 ⌘（第 34 步），列表里的名字与原版相同写「Ctrl+」。
final class KeyBindPage: CommonSettingsPageLogic {
    static let section = "KeyBind"
    /// 原版 STR_SHIFT_PLUS 等
    static let modifierNames: [(mask: Int, name: String, id: String)] = [
        (1, "Shift+", idc("CHECK_SHIFT")), (2, "Ctrl+", idc("CHECK_CTRL")), (4, "Alt+", idc("CHECK_ALT")),
    ]

    private var editor: EditorCommandSettingsEditor?
    /// 「機能」列表的功能编号（与列表的行对应）
    private var functionCodes: [Int] = []

    // MARK: SetData / GetData

    func setData(_ page: PropPage, _ values: CommonSettingsValues) {
        editor = values.commandEditor
        guard let editor else { return }
        // 原版 SetData：種別のコンボボックス（先頭を選ぶ）、キー一覧
        page.setItems(idc("COMBO_FUNCKIND"), editor.functionCategories, selected: 0)
        page.list(idc("LIST_KEY"))?.setRows((0..<editor.keyCount).map { [editor.name(ofKey: $0)] })
        // 原版 WM_INITDIALOG：キー一覧の先頭を選ぶ、種別の機能一覧
        page.list(idc("LIST_KEY"))?.select(0)
        keySelected(page)
        loadFunctions(page)
    }

    func getData(_ page: PropPage, _ values: CommonSettingsValues) {
        Self.storeIniValues(editor, section: Self.section, values)
    }

    /// 复制的这一节的值里与窗口的值不同的项写进窗口的值（OK 时写回）
    static func storeIniValues(_ editor: EditorCommandSettingsEditor?, section: String, _ values: CommonSettingsValues) {
        guard let editor else { return }
        for (key, value) in editor.iniValues(section: section).sorted(by: { $0.key < $1.key })
        where values.string(key, section: section) != value {
            values.set(value, key, section: section)
        }
    }

    /// 原版 PSN_SETACTIVE：表示を更新する（カスタムメニュー・マクロ 页改的名字）
    func activate(_ page: PropPage, _ values: CommonSettingsValues) {
        guard editor != nil else { return }
        let row = page.list(idc("LIST_FUNC"))?.selectedRow ?? -1
        refreshKeyList(page)
        loadFunctions(page)
        if row >= 0 {
            page.list(idc("LIST_FUNC"))?.select(row)
            functionSelected(page)
        }
    }

    // MARK: 表示

    /// チェックボックスの組み合わせ（原版 _SHIFT | _CTRL | _ALT）
    private func modifiers(_ page: PropPage) -> Int {
        Self.modifierNames.reduce(0) { $0 | (page.isChecked($1.id) ? $1.mask : 0) }
    }

    private func selectedKey(_ page: PropPage) -> Int {
        page.list(idc("LIST_KEY"))?.selectedRow ?? -1
    }

    /// 原版 CBN_SELCHANGE：機能一覧（原版 CFuncLookup::SetListItem）
    private func loadFunctions(_ page: PropPage) {
        guard let editor else { return }
        let category = page.selectedIndex(idc("COMBO_FUNCKIND"))
        functionCodes = editor.functionCodes(inCategory: category).map(\.intValue)
        page.list(idc("LIST_FUNC"))?.setRows(editor.functionNames(inCategory: category).map { [$0] })
    }

    /// 原版 ChangeKeyList：キー一覧の名前にチェックボックスの「Shift+」等を付ける。選択はそのまま
    private func refreshKeyList(_ page: PropPage) {
        guard let editor, let list = page.list(idc("LIST_KEY")) else { return }
        let row = list.selectedRow
        let mask = modifiers(page)
        let prefix = Self.modifierNames.filter { mask & $0.mask != 0 }.map(\.name).joined()
        list.setRows((0..<editor.keyCount).map { [prefix + editor.name(ofKey: $0)] })
        list.select(row)
        keySelected(page)
    }

    /// 原版 IDC_LIST_KEY の LBN_SELCHANGE：キーに割り当てられている機能
    private func keySelected(_ page: PropPage) {
        guard let editor else { return }
        let key = selectedKey(page)
        guard key >= 0 else {
            page.setText(idc("EDIT_KEYSFUNC"), "")
            return
        }
        let code = editor.function(ofKey: key, modifiers: modifiers(page))
        page.setText(idc("EDIT_KEYSFUNC"), code == 0 ? L10n.tr("未割当", comment: "STR_PROPCOMKEYBIND_UNASSIGN")
                                                     : editor.name(ofFunction: code))
    }

    /// 原版 IDC_LIST_FUNC の LBN_SELCHANGE：機能に割り当てられているキー
    private func functionSelected(_ page: PropPage) {
        guard let editor else { return }
        let row = page.list(idc("LIST_FUNC"))?.selectedRow ?? -1
        let keys = functionCodes.indices.contains(row) ? editor.keysAssigned(toFunction: functionCodes[row]) : []
        page.list(idc("LIST_ASSIGNEDKEYS"))?.setRows(keys.map { [$0] })
    }

    /// 原版 IDC_LIST_ASSIGNEDKEYS の LBN_SELCHANGE：そのキーとチェックボックスを選ぶ
    private func assignedKeySelected(_ page: PropPage) {
        guard let editor, let list = page.list(idc("LIST_ASSIGNEDKEYS")), list.rows.indices.contains(list.selectedRow) else { return }
        var name = Substring(list.rows[list.selectedRow][0])
        var mask = 0
        for modifier in Self.modifierNames where name.hasPrefix(modifier.name) {	// Shift+、Ctrl+、Alt+ の順
            name = name.dropFirst(modifier.name.count)
            mask |= modifier.mask
        }
        guard let key = (0..<editor.keyCount).first(where: { editor.name(ofKey: $0) == name }) else { return }
        page.list(idc("LIST_KEY"))?.select(key)
        for modifier in Self.modifierNames { page.setChecked(modifier.id, mask & modifier.mask != 0) }
        refreshKeyList(page)
    }

    // MARK: 操作

    func enable(_ page: PropPage) {
        // 原版 WM_TIMER：割当 はキー・種別・機能を選んでいるとき、解除 はキーを選んでいるとき
        let key = selectedKey(page) >= 0
        let function = (page.list(idc("LIST_FUNC"))?.selectedRow ?? -1) >= 0
        page.setEnabled(idc("BUTTON_ASSIGN"), key && function)
        page.setEnabled(idc("BUTTON_RELEASE"), key)
    }

    func changed(_ id: String, _ page: PropPage, _ values: CommonSettingsValues) {
        switch id {
        case idc("CHECK_SHIFT"), idc("CHECK_CTRL"), idc("CHECK_ALT"):
            refreshKeyList(page)
        case idc("LIST_KEY"):
            keySelected(page)
        case idc("LIST_FUNC"):
            functionSelected(page)
        case idc("COMBO_FUNCKIND"):
            loadFunctions(page)
            functionSelected(page)
        case idc("LIST_ASSIGNEDKEYS"):
            assignedKeySelected(page)
        default:
            break
        }
    }

    func buttonPressed(_ id: String, _ page: PropPage, _ values: CommonSettingsValues, window: NSWindow?) {
        guard let editor else { return }
        switch id {
        case idc("BUTTON_ASSIGN"), idc("BUTTON_RELEASE"):
            let key = selectedKey(page)
            guard key >= 0 else { return }
            var code = 0	// 解除は F_DEFAULT
            if id == idc("BUTTON_ASSIGN") {
                let row = page.list(idc("LIST_FUNC"))?.selectedRow ?? -1
                guard functionCodes.indices.contains(row) else { return }
                code = functionCodes[row]
            }
            editor.setFunction(code, ofKey: key, modifiers: modifiers(page))
            keySelected(page)
            functionSelected(page)
        case idc("BUTTON_IMPORT"):
            guard let path = TypeSettingsPages.chooseImportFile(["key"], window) else { return }
            var message: NSString?
            let ok = editor.importKeyBind(path: path, message: &message)
            TypeSettingsPages.showMessage(message as String? ?? "")
            guard ok else { return }
            // 原版 Import：キー一覧と、機能に割り当てられているキーを更新
            refreshKeyList(page)
            functionSelected(page)
        case idc("BUTTON_EXPORT"):
            guard let path = TypeSettingsPages.chooseExportFile("", ["key"], window) else { return }
            var message: NSString?
            let ok = editor.exportKeyBind(path: path, message: &message)
            let text = message as String? ?? ""
            TypeSettingsPages.showMessage(!ok || !text.isEmpty ? text
                                          : L10n.tr("ファイルをエクスポートしました。\n\n", comment: "STR_IMPEXP_OK_EXPORT") + path)
        default:
            break
        }
    }
}

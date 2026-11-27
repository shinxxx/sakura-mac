// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge

/// タイプ別設定一覧（计划第 40 步第 3 个 PR。原版 CDlgTypeList：設定 > タイプ別設定一覧）。
///
/// - テンプレートは IDD_TYPELIST。設定変更（そのタイプの設定を開く）、一時適用（この文書だけそのタイプにする）、
///   インポート・エクスポート（*.ini。確認は IDD_TYPE_ASCERTAIN）、初期化、複製、↑↓、追加、削除。
/// - 一覧を変えたら、開いている文書のタイプの番号を直す（原版 PM_CHANGESETTING_TYPE2・ALL）。
/// - 「右クリックメニューに追加」「ダブルクリックで開く」は Windows のファイルの関連付け（レジストリ）なので Mac 版にはない（変灰）。
final class TypeListDialog: NSObject {
    struct Result: Equatable {
        let index: Int
        /// 一時適用（原版 PROP_TEMPCHANGE_FLAG）
        let temporary: Bool
    }

    let page: PropPage
    let title: String
    let enableTempChange: Bool
    private(set) var result: Result?
    var onClose: ((Bool) -> Void)?
    private(set) var types: [EditorTypeSetting] = []

    init?(selectedIndex: Int, enableTempChange: Bool) {
        guard let definition = PropDialogs.load("TypeSettingsDialogs")?.dialog("IDD_TYPELIST") else { return nil }
        page = PropPage(definition: definition)
        title = definition.name
        self.enableTempChange = enableTempChange
        super.init()
        page.setUnavailable([idc("CHECK_EXT_RMENU"), idc("CHECK_EXT_DBLCLICK")],
                            reason: L10n.tr("Mac 版では使用できません。", comment: "共通設定：Mac 版不能用的项目"))
        page.setUnavailable([idc("BUTTON_HELP")], reason: L10n.tr("この項目は今後のバージョンで対応します。", comment: "共通設定：以后的版本移植的项目"))
        if let list = page.list(idc("LIST_TYPES")) {
            list.onDoubleClick = { [weak self] row, _ in self?.close(Result(index: row, temporary: true)) }
            list.onSelect = { [weak self] in self?.enable() }
        }
        page.onButton = { [weak self] id in self?.button(id) }
        reload(select: selectedIndex)
    }

    /// 一覧の表示（原版 SetData：「名前 ( 拡張子 )」）
    static func label(_ type: EditorTypeSetting) -> String {
        type.extensions.isEmpty ? type.name : "\(type.name) ( \(type.extensions) )"
    }

    func reload(select index: Int) {
        types = EditorCore.typeSettings
        let labels = types.map { Self.label($0) }
        if let list = page.list(idc("LIST_TYPES")) {
            // 長い名前は横にスクロール（原版 List_SetHorizontalExtent）
            let width = labels.map { ($0 as NSString).size(withAttributes: [.font: PropPage.font]).width }.max() ?? 0
            list.table.columnAutoresizingStyle = .noColumnAutoresizing
            list.table.tableColumns.first?.width = max(width + 12, (list.table.enclosingScrollView?.contentSize.width ?? 0) - 4)
            list.table.enclosingScrollView?.hasHorizontalScroller = true
        }
        page.list(idc("LIST_TYPES"))?.setRows(labels.map { [$0] })
        page.list(idc("LIST_TYPES"))?.select(min(max(0, index), types.count - 1))
        enable()
    }

    var selectedIndex: Int { page.list(idc("LIST_TYPES"))?.selectedRow ?? -1 }

    /// 原版 LBN_SELCHANGE・SetData の有効・無効
    func enable() {
        let index = selectedIndex
        page.setEnabled(idc("BUTTON_UP_TYPE"), 1 < index)
        page.setEnabled(idc("BUTTON_DOWN_TYPE"), index != 0 && index < types.count - 1)
        page.setEnabled(idc("BUTTON_DEL_TYPE"), index > 0)
        page.setEnabled(idc("BUTTON_TEMPCHANGE"), enableTempChange)
        page.setEnabled(idc("BUTTON_COPY_TYPE"), types.count < EditorCore.maxTypeSettings)
        page.setEnabled(idc("BUTTON_ADD_TYPE"), types.count < EditorCore.maxTypeSettings)
    }

    private func close(_ result: Result?) {
        self.result = result
        onClose?(result != nil)
    }

    private static func notifyList() {
        NotificationCenter.default.post(name: TypeSettingsWindowController.listDidChangeNotification, object: nil)
    }

    private static func notifyType(_ index: Int) {
        NotificationCenter.default.post(name: TypeSettingsWindowController.didChangeNotification, object: nil, userInfo: ["index": index])
    }

    func button(_ id: String) {
        let index = selectedIndex
        switch id {
        case "IDOK":
            if index >= 0 { close(Result(index: index, temporary: false)) }
        case idc("BUTTON_TEMPCHANGE"):
            if index >= 0 { close(Result(index: index, temporary: true)) }
        case "IDCANCEL":
            close(nil)
        case idc("BUTTON_IMPORT"):
            importType(index)
        case idc("BUTTON_EXPORT"):
            guard types.indices.contains(index),
                  let path = TypeSettingsPages.chooseExportFile(types[index].name + ".ini", ["ini"], page.view.window) else { return }
            let result = EditorCore.exportTypeSetting(index, path: path)
            TypeSettingsPages.showMessage(result.message)
        case idc("BUTTON_INITIALIZE"):
            guard types.indices.contains(index) else { return }
            // 拡張子のないタイプ（追加したばかり等）は確認しない（原版）
            if !types[index].extensions.isEmpty || index == 0 {
                guard CommonSettingsPages.confirm(String(format: L10n.tr("%@ を初期化します。 よろしいですか？", comment: "STR_DLGTYPELIST_INIT1"), types[index].name)) else { return }
            }
            let name = EditorCore.initializeTypeSetting(index)
            guard !name.isEmpty else { return }
            Self.notifyType(index)
            reload(select: index)
            CommonSettingsPages.inform(String(format: L10n.tr("%@ を初期化しました。", comment: "STR_DLGTYPELIST_INIT2"), name))
        case idc("BUTTON_COPY_TYPE"):
            let copied = EditorCore.copyTypeSetting(index)
            if copied >= 0 { reload(select: copied) }
        case idc("BUTTON_ADD_TYPE"):
            let added = EditorCore.addTypeSetting()
            if added >= 0 { reload(select: added) }
        case idc("BUTTON_UP_TYPE"), idc("BUTTON_DOWN_TYPE"):
            let moved = EditorCore.moveTypeSetting(index, up: id == idc("BUTTON_UP_TYPE"))
            guard moved >= 0 else { return }
            Self.notifyList()
            reload(select: moved)
        case idc("BUTTON_DEL_TYPE"):
            guard index > 0, types.indices.contains(index),
                  CommonSettingsPages.confirm(String(format: L10n.tr("%@ を削除します。 よろしいですか？", comment: "STR_DLGTYPELIST_DEL"), types[index].name)),
                  EditorCore.deleteTypeSetting(index) else { return }
            Self.notifyList()
            reload(select: index)
        default:
            break
        }
    }

    /// 原版 CDlgTypeList::Import：ファイル → バージョンの確認 → インポート確認（新規追加か、選んだタイプに上書きか、色）
    private func importType(_ index: Int) {
        guard types.indices.contains(index), let path = TypeSettingsPages.chooseImportFile(["ini"], page.view.window) else { return }
        let info = EditorCore.checkTypeSettingFile(path)
        guard info.succeeded else {
            TypeSettingsPages.showMessage(info.message)
            return
        }
        if info.versionDiffers {
            guard CommonSettingsPages.confirm(String(format: L10n.tr("エクスポートした %@(%@/%d) とバージョンが異なります。\n\nインポートしてもよろしいですか？", comment: "STR_IMPEXP_VER"),
                                                     CommonSettingsPages.appName, info.version, info.structureVersion)) else { return }
        }
        guard let ascertain = TypeAscertainDialog(typeNameTo: types[index].name, typeNameFile: info.typeName, colorFiles: info.colorFiles),
              TypeSettingsPages.runTypeAscertainDialog(ascertain, page.view.window), let choice = ascertain.choice else { return }
        let result = EditorCore.importTypeSetting(path, index: index, addNew: choice.addNew, colorType: choice.colorType, colorFile: choice.colorFile)
        if !result.message.isEmpty { TypeSettingsPages.showMessage(result.message) }
        guard result.succeeded else { return }
        if !result.added { Self.notifyType(result.index) }
        reload(select: result.index)
    }
}

// MARK: - インポート確認（原版 CDlgTypeAscertain）

final class TypeAscertainDialog: NSObject {
    struct Choice: Equatable {
        let addNew: Bool
        /// -1：ファイルの色、0 以上：そのタイプの色
        let colorType: Int
        /// 空でなければ同じフォルダーの色設定ファイル
        let colorFile: String
    }

    let page: PropPage
    let title: String
    private let colorFiles: [String]
    private(set) var choice: Choice?
    var onClose: ((Bool) -> Void)?

    init?(typeNameTo: String, typeNameFile: String, colorFiles: [String]) {
        guard let definition = PropDialogs.load("TypeSettingsDialogs")?.dialog("IDD_TYPE_ASCERTAIN") else { return nil }
        page = PropPage(definition: definition)
        title = definition.name
        self.colorFiles = colorFiles
        super.init()
        (page.control(idc("RADIO_TYPE_TO")) as? NSButton)?.title = typeNameTo + "(B)"
        page.setText(idc("STATIC_TYPE_FILE"), typeNameFile)
        page.setChecked(idc("RADIO_TYPE_ADD"), true)
        // 色選択：先頭は「そのまま」、次に各タイプ、同じフォルダーの *.col
        var items: [(value: Int, title: String)] = [(-1, L10n.tr("--そのままインポート--", comment: "STR_DLGTYPEASC_IMPORT"))]
        items += EditorCore.typeSettings.map { type in
            (type.index, type.extensions.isEmpty ? type.name : "\(type.name) (\(type.extensions))")
        }
        items += colorFiles.enumerated().map { (EditorCore.maxTypeSettings + $0.offset, "File -- \($0.element)") }
        page.setTaggedItems(idc("COMBO_COLORS"), items, selectedValue: -1)
        page.setUnavailable([idc("BUTTON_HELP")], reason: L10n.tr("この項目は今後のバージョンで対応します。", comment: "共通設定：以后的版本移植的项目"))
        page.onButton = { [weak self] id in
            guard let self else { return }
            if id == "IDOK" {
                self.ok()
                self.onClose?(true)
            } else if id == "IDCANCEL" {
                self.onClose?(false)
            }
        }
    }

    /// 原版 OnBnClicked(IDOK)
    func ok() {
        let tag = page.selectedTag(idc("COMBO_COLORS")) ?? -1
        let file = tag >= EditorCore.maxTypeSettings ? colorFiles[tag - EditorCore.maxTypeSettings] : ""
        choice = Choice(addNew: page.isChecked(idc("RADIO_TYPE_ADD")), colorType: file.isEmpty ? tag : -1, colorFile: file)
    }
}

extension TypeSettingsPages {
    /// タイプ別設定一覧（原版 CDlgTypeList::DoModal）。测试可以换。設定変更・一時適用のとき true
    static var runTypeListDialog: (_ dialog: TypeListDialog, _ window: NSWindow?) -> Bool = { dialog, window in
        PropModal.run(dialog.page, title: dialog.title, parent: window, identifier: "TypeListDialog") { close in dialog.onClose = close }
    }

    /// インポート確認（原版 CDlgTypeAscertain::DoModal）。测试可以换。OK のとき true
    static var runTypeAscertainDialog: (_ dialog: TypeAscertainDialog, _ window: NSWindow?) -> Bool = { dialog, window in
        PropModal.run(dialog.page, title: dialog.title, parent: window, identifier: "TypeAscertainDialog") { close in dialog.onClose = close }
    }
}

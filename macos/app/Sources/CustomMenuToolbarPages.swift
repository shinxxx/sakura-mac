// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge

/// 共通設定 > カスタムメニュー（计划第 41 步第 3 个 PR。原版 CPropCustmenu）。
///
/// - 编辑在核心库的复制上（CommonSettingsValues.commandEditor）。原版も項目の操作のたびに m_Common を直接変える。
/// - メニュー名の「設定」でコンボボックスの名前が変わり、キー割り当て・メインメニュー の「機能」にも出る（同じ複製）。
/// - GetData で sakura.ini の [CustMenu] の値にする。
final class CustomMenuPage: CommonSettingsPageLogic {
    static let section = "CustMenu"

    private var editor: EditorCommandSettingsEditor?
    private var functionCodes: [Int] = []
    private var specialCategory = -1

    /// 選んでいるメニュー（原版 IDC_COMBO_MENU の選択）
    private var menuIndex = 0

    // MARK: SetData / GetData

    func setData(_ page: PropPage, _ values: CommonSettingsValues) {
        editor = values.commandEditor
        guard let editor else { return }
        // 原版 SetData：種別（最後に「特別機能」）、メニュー一覧の先頭、項目の先頭を選ぶ
        let categories = editor.functionCategories + [editor.specialFunctionCategory]
        specialCategory = categories.count - 1
        page.setItems(idc("COMBO_FUNCKIND"), categories, selected: 0)
        loadMenuNames(page, selected: 0)
        loadMenu(page)
        page.list(idc("LIST_RES"))?.select(0)
        loadFunctions(page)
        page.list(idc("LIST_RES"))?.onDoubleClick = { [weak self, weak page] row, _ in
            guard let self, let page else { return }
            self.editAccessKey(page, row)
        }
    }

    func getData(_ page: PropPage, _ values: CommonSettingsValues) {
        KeyBindPage.storeIniValues(editor, section: Self.section, values)
    }

    /// 原版 PSN_SETACTIVE：項目と機能一覧を作り直す（選択はそのまま）
    func activate(_ page: PropPage, _ values: CommonSettingsValues) {
        let menuRow = page.list(idc("LIST_RES"))?.selectedRow ?? -1
        let functionRow = page.list(idc("LIST_FUNC"))?.selectedRow ?? -1
        loadMenu(page)
        if menuRow >= 0 { page.list(idc("LIST_RES"))?.select(menuRow) }
        loadFunctions(page)
        if functionRow >= 0 { page.list(idc("LIST_FUNC"))?.select(functionRow) }
    }

    /// メニュー一覧（原版 Custmenu2Name）
    private func loadMenuNames(_ page: PropPage, selected: Int) {
        guard let editor else { return }
        page.setItems(idc("COMBO_MENU"), (0..<editor.customMenuCount).map { editor.displayName(ofCustomMenu: $0) }, selected: selected)
        menuIndex = selected
    }

    /// 原版 SetDataMenuList：項目（区切線、機能名(キー)）、メニュー名、サブメニューとして表示
    private func loadMenu(_ page: PropPage) {
        guard let editor else { return }
        let menu = menuIndex
        let keys = editor.accessKeys(ofCustomMenu: menu)
        let rows = editor.codes(ofCustomMenu: menu).enumerated().map { index, code -> [String] in
            let label = code.intValue == 0 ? Self.separatorLabel : editor.name(ofFunction: code.intValue)
            let key = keys.indices.contains(index) ? keys[index] : ""
            return [key.isEmpty ? label : "\(label)(\(key))"]
        }
        page.list(idc("LIST_RES"))?.setRows(rows)
        page.setText(idc("EDIT_MENUNAME"), editor.name(ofCustomMenu: menu))
        page.setChecked(idc("CHECK_SUBMENU"), editor.customMenuIsSubmenu(menu))
    }

    static var separatorLabel: String {
        NSLocalizedString(" ─────────────", comment: "STR_PROPCOMCUSTMENU_SEP")
    }

    private func loadFunctions(_ page: PropPage) {
        guard let editor else { return }
        let category = page.selectedIndex(idc("COMBO_FUNCKIND"))
        if category == specialCategory {
            functionCodes = editor.specialFunctionCodes.map(\.intValue)
            page.list(idc("LIST_FUNC"))?.setRows(editor.specialFunctionNames.map { [$0] })
        } else {
            functionCodes = editor.functionCodes(inCategory: category).map(\.intValue)
            page.list(idc("LIST_FUNC"))?.setRows(editor.functionNames(inCategory: category).map { [$0] })
        }
    }

    // MARK: 有効・無効

    func enable(_ page: PropPage) {
        // 原版 SetDlgItemsEnableState
        guard let editor else { return }
        let menu = menuIndex
        let row = page.list(idc("LIST_RES"))?.selectedRow ?? -1
        let count = page.list(idc("LIST_RES"))?.rows.count ?? 0
        let function = (page.list(idc("LIST_FUNC"))?.selectedRow ?? -1) >= 0
        page.setEnabled(idc("BUTTON_DELETE"), row >= 0)
        page.setEnabled(idc("BUTTON_UP"), row > 0)
        page.setEnabled(idc("BUTTON_DOWN"), row >= 0 && row + 1 < count)
        let full = editor.codes(ofCustomMenu: menu).count >= editor.maxCustomMenuItems
        page.setEnabled(idc("BUTTON_INSERT"), row >= 0 && function && !full)
        page.setEnabled(idc("BUTTON_ADD"), function && !full)
        page.setEnabled(idc("BUTTON_INSERTSEPARATOR"), !full)
    }

    func changed(_ id: String, _ page: PropPage, _ values: CommonSettingsValues) {
        guard let editor else { return }
        let menu = menuIndex
        switch id {
        case idc("COMBO_MENU"):
            menuIndex = page.selectedIndex(id)
            loadMenu(page)
        case idc("COMBO_FUNCKIND"):
            loadFunctions(page)
        case idc("CHECK_SUBMENU"):
            editor.setCustomMenu(menu, isSubmenu: page.isChecked(id))
        default:
            break
        }
    }

    // MARK: 操作

    private func items(_ editor: EditorCommandSettingsEditor, _ menu: Int) -> [(code: Int, key: String)] {
        let keys = editor.accessKeys(ofCustomMenu: menu)
        return editor.codes(ofCustomMenu: menu).enumerated().map { ($1.intValue, keys.indices.contains($0) ? keys[$0] : "") }
    }

    private func store(_ editor: EditorCommandSettingsEditor, _ menu: Int, _ items: [(code: Int, key: String)]) {
        editor.setCustomMenu(menu, codes: items.map { NSNumber(value: $0.code) }, accessKeys: items.map(\.key))
    }

    func buttonPressed(_ id: String, _ page: PropPage, _ values: CommonSettingsValues, window: NSWindow?) {
        guard let editor, let list = page.list(idc("LIST_RES")) else { return }
        let menu = menuIndex
        var list_ = items(editor, menu)
        let row = list.selectedRow
        let functionRow = page.list(idc("LIST_FUNC"))?.selectedRow ?? -1
        let full = list_.count >= editor.maxCustomMenuItems
        switch id {
        case idc("BUTTON_IMPORT"):
            guard let path = TypeSettingsPages.chooseImportFile(["mnu"], window) else { return }
            var message: NSString?
            let ok = editor.importCustomMenu(path: path, message: &message)
            TypeSettingsPages.showMessage(message as String? ?? "")
            if ok {
                loadMenuNames(page, selected: menu)
                loadMenu(page)
            }
            return
        case idc("BUTTON_EXPORT"):
            guard let path = TypeSettingsPages.chooseExportFile("", ["mnu"], window) else { return }
            var message: NSString?
            let ok = editor.exportCustomMenu(path: path, message: &message)
            let text = message as String? ?? ""
            TypeSettingsPages.showMessage(!ok || !text.isEmpty ? text
                                          : NSLocalizedString("ファイルをエクスポートしました。\n\n", comment: "STR_IMPEXP_OK_EXPORT") + path)
            return
        case idc("BUTTON_MENUNAME"):
            // 原版：名前を設定してコンボボックスの名前を換える
            editor.setName(page.text(idc("EDIT_MENUNAME")), ofCustomMenu: menu)
            loadMenuNames(page, selected: menu)
            return
        case idc("BUTTON_INSERTSEPARATOR"):
            guard !full else { return }
            let at = max(row, 0)
            list_.insert((0, ""), at: min(at, list_.count))
            store(editor, menu, list_)
            loadMenu(page)
            list.select(at)
        case idc("BUTTON_DELETE"):
            guard list_.indices.contains(row) else { return }
            list_.remove(at: row)
            store(editor, menu, list_)
            loadMenu(page)
            if !list_.isEmpty { list.select(min(row, list_.count - 1)) }
        case idc("BUTTON_INSERT"), idc("BUTTON_ADD"):
            guard !full, functionCodes.indices.contains(functionRow) else { return }
            let at = id == idc("BUTTON_ADD") ? list_.count : max(row, 0)
            list_.insert((functionCodes[functionRow], ""), at: min(at, list_.count))
            store(editor, menu, list_)
            loadMenu(page)
            list.select(at)
            page.list(idc("LIST_FUNC"))?.select(functionRow + 1)	// 次の機能
        case idc("BUTTON_UP"), idc("BUTTON_DOWN"):
            let other = id == idc("BUTTON_UP") ? row - 1 : row + 1
            guard list_.indices.contains(row), list_.indices.contains(other) else { return }
            list_.swapAt(row, other)
            store(editor, menu, list_)
            loadMenu(page)
            list.select(other)
        default:
            break
        }
    }

    /// 原版 LBN_DBLCLK：アクセスキーの設定（区切線以外）
    private func editAccessKey(_ page: PropPage, _ row: Int) {
        guard let editor else { return }
        let menu = menuIndex
        var list = items(editor, menu)
        guard list.indices.contains(row), list[row].code != 0,
              let key = CommonSettingsPages.input(NSLocalizedString("メニューアイテムのアクセスキー設定", comment: "STR_PROPCOMCUSTMENU_AC1"),
                                                  NSLocalizedString("キーを入力してください。", comment: "STR_PROPCOMCUSTMENU_AC2"),
                                                  1, list[row].key) else { return }
        list[row].key = String(key.prefix(1))
        store(editor, menu, list)
        loadMenu(page)
        page.list(idc("LIST_RES"))?.select(row)
    }
}

/// 共通設定 > ツールバー（计划第 41 步第 3 个 PR。原版 CPropToolBar）。
///
/// - ボタン番号の一覧を編集し、GetData で複製に書き（原版 GetData）、sakura.ini の [Toolbar] の値にする。
/// - 列表は原版と同じくアイコン（mytool.bmp）と機能名。区切・折返・不明は原版の文字。
/// - Mac 版にはまだツールバーが無い（ツールバーを作るステップで使う）。
final class ToolbarPage: CommonSettingsPageLogic {
    static let section = "Toolbar"

    private var editor: EditorCommandSettingsEditor?
    /// 「機能」列表・「ツールバー」列表のボタン番号
    private var functionButtons: [Int] = []
    private(set) var buttons: [Int] = []

    func setData(_ page: PropPage, _ values: CommonSettingsValues) {
        editor = values.commandEditor
        guard let editor else { return }
        page.setItems(idc("COMBO_FUNCKIND"), editor.functionCategories, selected: 0)
        buttons = editor.toolbarButtons.map(\.intValue)
        for id in [idc("LIST_FUNC"), idc("LIST_RES")] {
            page.list(id)?.cellView = { [weak self, weak page] row, _ in
                guard let self, let page else { return nil }
                let list = id == idc("LIST_FUNC") ? self.functionButtons : self.buttons
                _ = page
                return list.indices.contains(row) ? self.cell(list[row]) : nil
            }
        }
        loadButtons(page)
        page.list(idc("LIST_RES"))?.select(0)
        loadFunctions(page)
        page.setChecked(idc("CHECK_TOOLBARISFLAT"), editor.toolbarIsFlat)
    }

    func getData(_ page: PropPage, _ values: CommonSettingsValues) {
        guard let editor else { return }
        editor.setToolbar(buttons.map { NSNumber(value: $0) }, flat: page.isChecked(idc("CHECK_TOOLBARISFLAT")))
        KeyBindPage.storeIniValues(editor, section: Self.section, values)
    }

    /// ボタンの表示名（原版 DrawToolBarItemList）
    func label(_ number: Int) -> String {
        guard let editor else { return "" }
        switch editor.kind(ofToolbarButton: number) {
        case 0: return editor.name(ofFunction: editor.function(ofToolbarButton: number))
        case 1: return NSLocalizedString("───────────", comment: "STR_PROPCOMTOOL_ITEM1")
        case 2: return NSLocalizedString("――ツールバー折返――", comment: "STR_PROPCOMTOOL_ITEM2")
        default: return NSLocalizedString("────不　明────", comment: "STR_PROPCOMTOOL_ITEM3")
        }
    }

    /// 一行：アイコンと名前
    private func cell(_ number: Int) -> NSView {
        let label = NSTextField(labelWithString: self.label(number))
        label.font = PropPage.font
        label.lineBreakMode = .byTruncatingTail
        let icon = editor.flatMap { ToolbarIcons.shared.image($0.icon(ofToolbarButton: number)) }
        let imageView = NSImageView(image: icon ?? NSImage(size: NSSize(width: 16, height: 16)))
        imageView.imageScaling = .scaleNone
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.widthAnchor.constraint(equalToConstant: 16).isActive = true
        imageView.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let stack = NSStackView(views: [imageView, label])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.distribution = .fill
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 2, bottom: 0, right: 0)
        stack.setAccessibilityElement(false)
        imageView.setAccessibilityIdentifier("ToolbarIcon")
        return stack
    }

    private func loadButtons(_ page: PropPage) {
        page.list(idc("LIST_RES"))?.setRows(buttons.map { [label($0)] })
    }

    /// 原版 CBN_SELCHANGE：ボタンのある機能だけ
    private func loadFunctions(_ page: PropPage) {
        guard let editor else { return }
        let category = page.selectedIndex(idc("COMBO_FUNCKIND"))
        functionButtons = editor.functionCodes(inCategory: category).map { editor.toolbarButton(forFunction: $0.intValue) }.filter { $0 >= 0 }
        page.list(idc("LIST_FUNC"))?.setRows(functionButtons.map { [label($0)] })
    }

    func enable(_ page: PropPage) {
        // 原版 SetDlgItemsEnableState
        let row = page.list(idc("LIST_RES"))?.selectedRow ?? -1
        let function = (page.list(idc("LIST_FUNC"))?.selectedRow ?? -1) >= 0
        page.setEnabled(idc("BUTTON_DELETE"), row >= 0)
        page.setEnabled(idc("BUTTON_UP"), row > 0)
        page.setEnabled(idc("BUTTON_DOWN"), row >= 0 && row + 1 < buttons.count)
        page.setEnabled(idc("BUTTON_INSERT"), row >= 0 && function)
        page.setEnabled(idc("BUTTON_ADD"), function)
    }

    func changed(_ id: String, _ page: PropPage, _ values: CommonSettingsValues) {
        if id == idc("COMBO_FUNCKIND") { loadFunctions(page) }
    }

    func buttonPressed(_ id: String, _ page: PropPage, _ values: CommonSettingsValues, window: NSWindow?) {
        guard let editor, let list = page.list(idc("LIST_RES")) else { return }
        let row = list.selectedRow
        let functionRow = page.list(idc("LIST_FUNC"))?.selectedRow ?? -1
        switch id {
        case idc("BUTTON_INSERTSEPARATOR"), idc("BUTTON_INSERTWRAP"):
            // 選んでいる項目の前（無ければ先頭）に挿入して選ぶ
            let at = min(max(row, 0), buttons.count)
            buttons.insert(id == idc("BUTTON_INSERTWRAP") ? editor.toolbarWrapButton : editor.toolbarSeparatorButton, at: at)
            loadButtons(page)
            list.select(at)
        case idc("BUTTON_DELETE"):
            guard buttons.indices.contains(row) else { return }
            buttons.remove(at: row)
            loadButtons(page)
            if !buttons.isEmpty { list.select(min(row, buttons.count - 1)) }
        case idc("BUTTON_INSERT"):
            // 前に挿入し、選択は元の項目のまま（原版 nIndex1 + 1）
            guard functionButtons.indices.contains(functionRow) else { return }
            let at = min(max(row, 0), buttons.count)
            buttons.insert(functionButtons[functionRow], at: at)
            loadButtons(page)
            list.select(at + 1)
            page.list(idc("LIST_FUNC"))?.select(functionRow + 1)
        case idc("BUTTON_ADD"):
            guard functionButtons.indices.contains(functionRow) else { return }
            buttons.append(functionButtons[functionRow])
            loadButtons(page)
            list.select(buttons.count - 1)
            page.list(idc("LIST_FUNC"))?.select(functionRow + 1)
        case idc("BUTTON_UP"), idc("BUTTON_DOWN"):
            let other = id == idc("BUTTON_UP") ? row - 1 : row + 1
            guard buttons.indices.contains(row), buttons.indices.contains(other) else { return }
            buttons.swapAt(row, other)
            loadButtons(page)
            list.select(other)
        default:
            break
        }
    }
}

/// ツールバーのアイコン（原版 mytool.bmp：16×16 のアイコンが横に 32 個（MAX_TOOLBAR_ICON_X）×15 段。左上の点の色が透明。原版 CImageListMgr）
final class ToolbarIcons {
    static let shared = ToolbarIcons()
    static let size = 16
    static let columns = 32	// MAX_TOOLBAR_ICON_X（bmp はもう 1 列広いが、原版も 32 列として使う）

    private let bitmap: NSBitmapImageRep?
    private var cache: [Int: NSImage] = [:]

    init(url: URL? = Bundle(for: ToolbarIcons.self).url(forResource: "mytool", withExtension: "bmp")
         ?? Bundle.main.url(forResource: "mytool", withExtension: "bmp")) {
        bitmap = url.flatMap { NSImage(contentsOf: $0) }?.representations.first as? NSBitmapImageRep
            ?? url.flatMap { try? Data(contentsOf: $0) }.flatMap { NSBitmapImageRep(data: $0) }
    }

    /// アイコンの数
    var count: Int {
        guard let bitmap else { return 0 }
        return min(bitmap.pixelsWide / Self.size, Self.columns) * (bitmap.pixelsHigh / Self.size)
    }

    /// この番号のアイコン。無いとき nil
    func image(_ index: Int) -> NSImage? {
        guard let bitmap, index >= 0, index < count, let source = bitmap.cgImage else { return nil }
        if let image = cache[index] { return image }
        let size = Self.size
        // 左上の点の色（透明にする色）。RGBA 8 ビットに描いてから比べる
        func pixels(_ image: CGImage, width: Int, height: Int) -> (CGContext, UnsafeMutablePointer<UInt8>)? {
            guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
                  let data = context.data else { return nil }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return (context, data.assumingMemoryBound(to: UInt8.self))
        }
        let sx = (index % Self.columns) * size, sy = (index / Self.columns) * size
        guard let corner = source.cropping(to: CGRect(x: 0, y: 0, width: 1, height: 1)),
              let (cornerContext, cornerPixel) = pixels(corner, width: 1, height: 1),
              let cell = source.cropping(to: CGRect(x: sx, y: sy, width: size, height: size)),
              let (context, data) = pixels(cell, width: size, height: size) else { return nil }
        // 点の値は context が生きているうちに読む
        let transparent = withExtendedLifetime(cornerContext) { (cornerPixel[0], cornerPixel[1], cornerPixel[2]) }
        for i in 0..<(size * size) {
            let p = data + i * 4
            if (p[0], p[1], p[2]) == transparent { p[0] = 0; p[1] = 0; p[2] = 0; p[3] = 0 }
        }
        guard let result = withExtendedLifetime(context, { context.makeImage() }) else { return nil }
        let image = NSImage(cgImage: result, size: NSSize(width: size, height: size))
        cache[index] = image
        return image
    }

    /// 透明でない点の数（テスト用）
    func opaquePixelCount(_ index: Int) -> Int {
        guard let cg = image(index)?.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let context = CGContext(data: nil, width: Self.size, height: Self.size, bitsPerComponent: 8, bytesPerRow: Self.size * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data?.assumingMemoryBound(to: UInt8.self) else { return 0 }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: Self.size, height: Self.size))
        return withExtendedLifetime(context) { (0..<(Self.size * Self.size)).filter { data[$0 * 4 + 3] > 0 }.count }
    }
}

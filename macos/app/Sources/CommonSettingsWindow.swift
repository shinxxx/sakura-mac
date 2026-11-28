// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge

/// 共通設定窗口（计划第 39 步。原版 CPropCommon：設定 > 共通設定）。
///
/// - 页的顺序、每页的控件（位置、文字）用原版的对话框模板（sakura_rc.rc 的 IDD_PROP_*）：
///   macos/tools/settings/make_prop_dialogs.py 生成 Resources/CommonSettingsDialogs.json，这里按对话框单位排列。
///   控件是 Mac 的标准控件（已确认的偏离项 4：布局、项目、文字照原版，外观是 Mac 的）。
/// - 每页的 SetData / GetData / Enable…Input 移植在 CommonSettingsPages.swift。
///   值按 sakura.ini 的「节/项目」读写（核心库 GetCommonSetting / SetCommonSetting，用原版 CShareData_IO），
///   所以范围限制、写法与原版完全相同。
/// - 与原版相同：打开时复制设置，OK 时写回（没看过的页不改），然后保存 sakura.ini，通知所有窗口；キャンセル 什么也不改。
/// - 原版的属性页是标签，18 页 Mac 的标签放不下，换成左边的列表（偏离项 4）。
/// - Mac 版做不到的项目（任务托盘、DLL 等）变灰（偏离项 7、9）；以后的步骤移植的页（メインメニュー 等）现在只显示。

// MARK: - 设置的读写

/// 共通設定的读写（sakura.ini 的「节/项目」）。平时是核心库，测试可以换
protocol CommonSettingsStore: AnyObject {
    func value(section: String, key: String) -> String?
    /// 一次改同一节的几项（项目 → 值）。有一项不行时什么也不改，返回 false
    func setValues(_ values: [String: String], section: String) -> Bool
    func save() -> Bool
}

/// 核心库的共通設定（sakura::core::GetCommonSetting 等）
final class CoreCommonSettingsStore: CommonSettingsStore {
    func value(section: String, key: String) -> String? {
        EditorCore.commonSetting(section: section, key: key)
    }

    func setValues(_ values: [String: String], section: String) -> Bool {
        EditorCore.setCommonSettings(values, section: section)
    }

    func save() -> Bool {
        EditorCore.saveSettings()
    }
}

/// 窗口里的设置的值（原版 CPropCommon::m_Common：打开时复制，OK 时写回）
final class CommonSettingsValues {
    struct Item: Hashable {
        let section: String
        let key: String
    }

    let store: CommonSettingsStore
    /// 不指定节时的节：共通設定是 Common，タイプ別設定是 Types(N)（第 40 步）
    let defaultSection: String
    /// 上次 apply 写的节（第 40 步：強調キーワード・タイプ別設定变了时各文档重新排版）
    private(set) var appliedSections: Set<String> = []
    private var original: [Item: String] = [:]
    private var current: [Item: String] = [:]
    private var order: [Item] = []

    /// 共通設定 > キー割り当て・メインメニュー・ツールバー・カスタムメニュー 共用的复制（第 41 步。原版 CPropCommon::m_Common）
    lazy var commandEditor: EditorCommandSettingsEditor? = EditorCommandSettingsEditor()

    init(store: CommonSettingsStore, defaultSection: String = "Common") {
        self.store = store
        self.defaultSection = defaultSection
    }

    /// 值（sakura.ini 的写法）。第一次读时从核心库取
    func string(_ key: String, section: String? = nil) -> String {
        let section = section ?? defaultSection
        let item = Item(section: section, key: key)
        if let value = current[item] { return value }
        let value = store.value(section: section, key: key) ?? ""
        original[item] = value
        current[item] = value
        return value
    }

    func int(_ key: String, section: String? = nil) -> Int {
        Int(string(key, section: section).trimmingCharacters(in: .whitespaces)) ?? 0
    }

    func bool(_ key: String, section: String? = nil) -> Bool {
        int(key, section: section) != 0
    }

    func set(_ value: String, _ key: String, section: String? = nil) {
        let section = section ?? defaultSection
        let item = Item(section: section, key: key)
        _ = string(key, section: section)	// 先记下原来的值
        current[item] = value
        if !order.contains(item) { order.append(item) }
    }

    func set(_ value: Int, _ key: String, section: String? = nil) {
        set(String(value), key, section: section)
    }

    func set(_ value: Bool, _ key: String, section: String? = nil) {
        set(value ? 1 : 0, key, section: section)
    }

    /// 与打开时不同的项，按改的顺序
    var changes: [(item: Item, value: String)] {
        order.compactMap { item in
            guard let value = current[item], value != original[item] else { return nil }
            return (item, value)
        }
    }

    /// 不指定节的节里还没 OK 的值（项目 → 值）。タイプ別設定的导入・导出用（第 40 步）
    var pending: [String: String] {
        var result: [String: String] = [:]
        for (item, value) in changes where item.section == defaultSection { result[item.key] = value }
        return result
    }

    /// 写回核心库，保存 sakura.ini（原版 CPropCommon::ApplyData 以后 CShareData_IO::SaveShareData）。都成功时 true
    @discardableResult
    func apply() -> Bool {
        let changes = self.changes
        guard !changes.isEmpty else { return true }
        var succeeded = true
        // 按节一起写（ファイル名表示 的置換リスト：ArrNum 和 From%02d、To%02d 要一起读入）
        var sections: [String] = []
        var bySection: [String: [String: String]] = [:]
        for (item, value) in changes {
            if bySection[item.section] == nil { sections.append(item.section) }
            bySection[item.section, default: [:]][item.key] = value
        }
        appliedSections = Set(sections)
        for section in sections where !store.setValues(bySection[section] ?? [:], section: section) {
            succeeded = false
        }
        if !store.save() { succeeded = false }
        // 下次从核心库重新读（范围限制以后的值）
        original.removeAll()
        current.removeAll()
        order.removeAll()
        return succeeded
    }
}

// MARK: - 对话框模板

/// 原版的对话框模板（Resources/CommonSettingsDialogs.json）
struct PropDialogs: Decodable {
    struct Control: Decodable {
        let id: String
        let kind: String
        let frame: [Double]
        let text: String?
        let flags: [String]?
        /// IDC_STATIC 的标签的日文的文字（英文、中文的布局。按文字找标签时用，第 48 步）
        let key: String?

        func has(_ flag: String) -> Bool { flags?.contains(flag) ?? false }
    }

    struct Page: Decodable {
        /// 固定的日文名（找页、辅助功能的标识用）
        let name: String
        /// 显示的页名（原版 STR_PROPCOMMON_* 等，界面的语言。第 48 步）
        let title: String?
        let dialog: String
        let size: [Double]
        let controls: [Control]
    }

    let pages: [Page]
    /// 从页打开的对话框（ウィンドウの位置と大きさ 等）
    let dialogs: [Page]?

    func dialog(_ name: String) -> Page? {
        dialogs?.first { $0.dialog == name }
    }

    /// resource：共通設定是 CommonSettingsDialogs，タイプ別設定是 TypeSettingsDialogs（第 40 步）
    static func load(_ resource: String = "CommonSettingsDialogs") -> PropDialogs? {
        // 第 48 步：界面的语言的布局（Resources/<语言>.lproj/）
        guard let url = L10n.resourceURL(resource, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PropDialogs.self, from: data)
    }
}

/// 左上是原点的视图（对话框的坐标）
final class PropFlippedView: NSView {
    override var isFlipped: Bool { true }

    /// 控件的说明（第 49 步：原版 HELP_CONTEXTMENU，右键显示 Cshelp.txt 的说明）。nil 时没有说明
    var contextHelpText: ((NSView) -> String?)?

    override func rightMouseDown(with event: NSEvent) {
        if let text = contextHelpText, ContextHelp.handleRightClick(in: self, event: event, text: text) { return }
        super.rightMouseDown(with: event)
    }
}

// MARK: - 一页

/// 一页（原版 IDD_PROP_* 的对话框）。控件按 ID（IDC_…）找，与原版的 GetDlgItem 相同
final class PropPage: NSObject, NSTextFieldDelegate, NSComboBoxDelegate {
    /// 对话框单位 → 点（縦）
    static let scale: CGFloat = 1.6
    /// 横は少し広く：Mac の文字は原版（Windows）の文字より幅があるので、原版の枠のままだと文字が切れる（第 41 步）。
    /// 英語・中国語は原版の語言包の枠（日本語と同じ大きさ）に長い文字が入るので、もっと広く（第 48 步）
    static var scaleX: CGFloat { L10n.language == "ja" ? 1.95 : 2.3 }
    static let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)

    let definition: PropDialogs.Page
    let view: PropFlippedView
    private var controls: [String: NSView] = [:]
    private var labels: [String: NSTextField] = [:]
    /// 数值框 → 旁边的上下按钮（原版 UDS_AUTOBUDDY 的 Spin）
    private var steppers: [String: NSStepper] = [:]
    private var stepperBuddies: [ObjectIdentifier: String] = [:]
    /// Mac 版不能用的控件（一直变灰）
    private var unavailable: Set<String> = []
    /// 列表（原版 ListBox、ListView）
    private var lists: [String: PropList] = [:]
    /// ツリー（原版 TreeView。第 41 步）
    private var trees: [String: PropTree] = [:]
    /// 负数也可以的数值框（上下按钮的范围的下限是负数）
    private var signedFields: Set<String> = []

    /// 复选框、单选按钮、组合框、数值框变了（原版 WM_COMMAND 的 BN_CLICKED、CBN_SELCHANGE、EN_CHANGE）
    var onChange: ((String) -> Void)?
    /// 按钮按了
    var onButton: ((String) -> Void)?

    init(definition: PropDialogs.Page) {
        self.definition = definition
        view = PropFlippedView(frame: NSRect(x: 0, y: 0,
                                             width: Self.pointsX(definition.size[0]), height: Self.points(definition.size[1])))
        super.init()
        build()
        view.contextHelpText = { [weak self] view in
            view.identifier.flatMap { self?.contextHelpText($0.rawValue) }
        }
    }

    static func points(_ units: Double) -> CGFloat {
        (CGFloat(units) * scale).rounded()
    }

    /// 横の対話框単位 → 点
    static func pointsX(_ units: Double) -> CGFloat {
        (CGFloat(units) * scaleX).rounded()
    }

    private static func rect(_ frame: [Double]) -> NSRect {
        NSRect(x: pointsX(frame[0]), y: points(frame[1]), width: pointsX(frame[2]), height: points(frame[3]))
    }

    // MARK: 生成

    private func build() {
        // 组框先放（在下面），不挡住里面的控件
        for control in definition.controls where control.kind == "group" {
            let box = NSBox(frame: Self.rect(control.frame))
            box.boxType = .primary
            box.titleFont = Self.font
            box.title = control.text ?? ""
            box.titlePosition = (control.text ?? "").isEmpty ? .noTitle : .atTop
            view.addSubview(box)
            register(box, control)
        }

        // 单选按钮的组（原版 WS_GROUP：有这个样式的控件开始新的组）。每组放进一个透明的视图，Mac 的单选按钮按视图分组
        var group = 0
        var radioGroups: [Int: [(NSButton, NSRect)]] = [:]
        var lastEdit: (String, NSTextField)?

        for control in definition.controls {
            if control.has("group") { group += 1 }
            let frame = Self.rect(control.frame)
            let text = control.text ?? ""
            switch control.kind {
            case "group":
                continue
            case "check":
                let button = NSButton(checkboxWithTitle: text, target: self, action: #selector(controlClicked(_:)))
                setUpButton(button, multiline: text.contains("\n") || control.has("multiline"))
                button.frame = widened(frame, for: button, multiline: text.contains("\n") || control.has("multiline"))
                // Mac のチェックボックスは文字のない所をクリックしても変わらないので、1 行のものは文字の幅にする
                if !text.contains("\n") && !control.has("multiline") {
                    button.frame.size.width = min(button.frame.width, ceil(button.fittingSize.width) + 2)
                }
                view.addSubview(button)
                register(button, control)
            case "radio":
                let button = NSButton(radioButtonWithTitle: text, target: self, action: #selector(controlClicked(_:)))
                setUpButton(button, multiline: text.contains("\n") || control.has("multiline"))
                radioGroups[group, default: []].append((button, frame))
                register(button, control)
            case "button":
                let button = NSButton(title: text, target: self, action: #selector(pushButtonClicked(_:)))
                button.bezelStyle = .rounded
                button.controlSize = .small
                button.font = Self.font
                // Mac 的按钮比 Windows 高：上下居中
                let height = max(frame.height, 22)
                // Mac のボタンは枠の内側に余白があるので左右に 4 点広げる。ただし隣のボタンと重ならないように（第 41 步）
                let (left, right) = buttonMargins(frame, id: control.id)
                button.frame = NSRect(x: frame.minX - left, y: frame.midY - height / 2, width: frame.width + left + right, height: height)
                // 文字が入らないときは空いているほうへ広げる（第 41 步）
                if button.fittingSize.width > button.frame.width {
                    button.frame = widened(button.frame, original: frame, needed: ceil(button.fittingSize.width))
                }
                view.addSubview(button)
                register(button, control)
            case "label":
                let label = text.contains("\n") || frame.height > Self.points(12)
                    ? NSTextField(wrappingLabelWithString: text) : NSTextField(labelWithString: text)
                label.font = Self.font
                if control.has("right") { label.alignment = .right }
                if control.has("center") { label.alignment = .center }
                // 左寄せの 1 行の説明は、Mac の文字が原版より広いとき切れないように広げる（第 41 步）
                label.frame = control.has("right") || control.has("center") ? frame
                    : widened(frame, for: label, multiline: text.contains("\n") || frame.height > Self.points(12))
                view.addSubview(label)
                register(label, control)
                if !text.isEmpty { labels[text] = label }
                if let key = control.key { labels[key] = label }	// 英文、中文也能用日文的文字找（第 48 步）
            case "edit":
                let field = NSTextField(frame: frame)
                field.font = Self.font
                field.controlSize = .small
                field.delegate = self
                field.isEditable = !control.has("readonly")
                if control.has("readonly") { field.drawsBackground = false }
                if control.has("right") { field.alignment = .right }
                if control.has("multiline") {
                    field.usesSingleLineMode = false
                    field.cell?.wraps = true
                    field.cell?.isScrollable = false
                } else {
                    field.cell?.isScrollable = true
                }
                view.addSubview(field)
                register(field, control)
                lastEdit = (control.id, field)
            case "combo" where !control.has("dropdownlist"):
                // 原版 CBS_DROPDOWN：入力できるコンボボックス（Grep ダイアログの条件・フォルダー 等。第 43 步）
                let box = NSComboBox(frame: NSRect(x: frame.minX, y: frame.minY - 1, width: frame.width, height: 22))
                box.controlSize = .small
                box.font = Self.font
                box.completes = false
                box.usesDataSource = false
                box.numberOfVisibleItems = 15
                box.delegate = self
                box.target = self
                box.action = #selector(controlClicked(_:))
                view.addSubview(box)
                register(box, control)
            case "combo":
                let popup = NSPopUpButton(frame: NSRect(x: frame.minX, y: frame.minY - 1, width: frame.width, height: 22),
                                          pullsDown: false)
                popup.controlSize = .small
                popup.font = Self.font
                popup.target = self
                popup.action = #selector(controlClicked(_:))
                view.addSubview(popup)
                register(popup, control)
            case "spin":
                // 原版的 Spin 跟在前一个数值框的右边（UDS_AUTOBUDDY | UDS_ALIGNRIGHT）
                guard let edit = lastEdit else { continue }
                let buddyID = edit.0, buddy = edit.1
                // 分组框の枠線・ページの端からはみ出すときは、数値欄を縮めて中に収める（第 41 步）
                let edge = (enclosingGroup(buddy.frame).map { $0.maxX - Self.groupMargin } ?? view.frame.width)
                let overflow = buddy.frame.maxX + 1 + 15 - edge
                if overflow > 0 && buddy.frame.width - overflow >= 24 { buddy.frame.size.width -= overflow }
                let stepper = NSStepper(frame: NSRect(x: buddy.frame.maxX + 1, y: buddy.frame.minY - 2, width: 15, height: buddy.frame.height + 4))
                stepper.controlSize = .small
                stepper.valueWraps = false
                stepper.minValue = 0
                stepper.maxValue = Double(Int32.max)
                stepper.target = self
                stepper.action = #selector(stepperClicked(_:))
                view.addSubview(stepper)
                steppers[buddyID] = stepper
                stepperBuddies[ObjectIdentifier(stepper)] = buddyID
                if control.id != "IDC_STATIC" { controls[control.id] = stepper }
            case "tree":
                // 原版 SysTreeView32（共通設定 > メインメニュー，第 41 步）
                let scroll = NSScrollView(frame: frame)
                scroll.borderType = .bezelBorder
                scroll.hasVerticalScroller = true
                let tree = PropTree()
                tree.outline.tableColumns.first?.width = frame.width - 4	// 列は枠の幅いっぱい
                tree.outline.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
                tree.onSelect = { [weak self] in self?.onChange?(control.id) }
                trees[control.id] = tree
                scroll.documentView = tree.outline
                view.addSubview(scroll)
                register(scroll, control)
                tree.outline.setAccessibilityIdentifier(control.id + "_outline")
            case "list", "listview":
                let scroll = NSScrollView(frame: frame)
                scroll.borderType = .bezelBorder
                scroll.hasVerticalScroller = true
                let list = PropList(header: control.kind == "listview")
                if control.kind == "list" { list.table.tableColumns.first?.width = frame.width - 4 }	// ListBox の列は枠の幅いっぱい
                list.onSelect = { [weak self] in self?.onChange?(control.id) }
                lists[control.id] = list
                scroll.documentView = list.table
                view.addSubview(scroll)
                register(scroll, control)
                list.table.setAccessibilityIdentifier(control.id + "_table")
            case "slider":
                // 原版 msctls_trackbar32（タイプ別設定 > ウィンドウ の背景画像の透明度，第 40 步）
                let slider = NSSlider(value: 0, minValue: 0, maxValue: 100, target: self, action: #selector(controlClicked(_:)))
                slider.controlSize = .small
                slider.frame = NSRect(x: frame.minX, y: frame.midY - 10, width: frame.width, height: 20)
                view.addSubview(slider)
                register(slider, control)
            case "hotkey":
                let field = NSTextField(frame: frame)
                field.font = Self.font
                field.controlSize = .small
                field.isEditable = false
                view.addSubview(field)
                register(field, control)
            default:
                continue	// アイコン等
            }
        }

        for (_, radios) in radioGroups.sorted(by: { $0.key < $1.key }) {
            let union = radios.map { $0.1 }.reduce(radios[0].1) { $0.union($1) }
            let container = PropFlippedView(frame: union)
            for (button, frame) in radios {
                button.frame = frame.offsetBy(dx: -union.minX, dy: -union.minY)
                if !button.title.contains("\n") && button.cell?.wraps != true {	// 文字の幅に（チェックボックスと同じ）
                    button.frame.size.width = min(button.frame.width, ceil(button.fittingSize.width) + 2)
                }
                container.addSubview(button)
            }
            view.addSubview(container)
        }

        // それでも文字が入らないボタン（「(1)...」等）は、左隣の入力欄を少し縮めて場所を作る（第 41 步）
        for case let button as NSButton in view.subviews where button.bezelStyle == .rounded && button.fittingSize.width > button.frame.width {
            let shortage = ceil(button.fittingSize.width - button.frame.width)
            guard let field = view.subviews.compactMap({ $0 as? NSTextField }).first(where: {
                $0.isEditable && abs($0.frame.midY - button.frame.midY) < 6 && $0.frame.maxX <= button.frame.minX + 6
                    && button.frame.minX - $0.frame.maxX < 12 && $0.frame.width > shortage * 4 }) else { continue }
            field.frame.size.width -= shortage
            button.frame.origin.x -= shortage
            button.frame.size.width += shortage
        }

        // それでも文字が入らない 1 行の説明（中国語「DLL文件(M)」等）は、右隣の入力欄の左端を右へずらす。
        // 同じ列（左端と幅が同じ）の入力欄も一緒にずらして揃える（第 48 步）
        let fields = view.subviews.compactMap { $0 as? NSTextField }.filter { $0.isEditable }
        for label in view.subviews.compactMap({ $0 as? NSTextField }) where !label.isEditable && !label.isHidden
            && label.cell?.wraps == false && (label.alignment == .left || label.alignment == .natural)
            && label.fittingSize.width > label.frame.width + 0.5 {
            let shortage = ceil(label.fittingSize.width - label.frame.width)
            guard let field = fields.first(where: { abs($0.frame.midY - label.frame.midY) < 6 && $0.frame.minX >= label.frame.maxX - 2
                && $0.frame.minX - label.frame.maxX < 12 && $0.frame.width > shortage * 4 }) else { continue }
            let column = fields.filter { abs($0.frame.minX - field.frame.minX) < 1 && abs($0.frame.width - field.frame.width) < 1 }
            for f in column {
                f.frame.origin.x += shortage
                f.frame.size.width -= shortage
            }
            label.frame.size.width += shortage
        }

        // 横に並んだボタンの間を 4 点以上あける（余白のあるほうを縮める）（第 41 步）
        let pushButtons = view.subviews.compactMap { $0 as? NSButton }.filter { $0.bezelStyle == .rounded }.sorted { $0.frame.minX < $1.frame.minX }
        for (i, left) in pushButtons.enumerated() {
            for right in pushButtons[(i + 1)...] where abs(left.frame.midY - right.frame.midY) < 6 && right.frame.minX >= left.frame.minX {
                let deficit = 4 - (right.frame.minX - left.frame.maxX)
                guard deficit > 0, right.frame.minX - left.frame.maxX < 20 else { continue }
                let rightSlack = right.frame.width - ceil(right.fittingSize.width)
                let leftSlack = left.frame.width - ceil(left.fittingSize.width)
                let fromRight = min(deficit, max(0, rightSlack))
                right.frame.origin.x += fromRight
                right.frame.size.width -= fromRight
                let rest = deficit - fromRight
                if rest > 0 { left.frame.size.width -= min(rest, max(0, leftSlack)) }
            }
        }

        // 上下ボタン（原版は数値の欄の中に描く）に重なった右隣の説明（「ドット」等）は、ボタンの右へずらす（第 41 步）
        for stepper in steppers.values {
            for label in view.subviews.compactMap({ $0 as? NSTextField }) where !label.isEditable && label.frame.intersects(stepper.frame)
                && label.frame.minX > stepper.frame.minX - 8 {
                label.frame.origin.x = stepper.frame.maxX + 2
            }
        }

        // 模板里的初始状态
        for control in definition.controls where control.id != "IDC_STATIC" {
            if control.has("hidden") { controls[control.id]?.isHidden = true }
            if control.has("disabled") { setEnabled(control.id, false) }
        }
        for control in definition.controls where control.id == "IDC_STATIC" && control.has("hidden") {
            if let text = control.key ?? control.text, let label = labels[text] { label.isHidden = true }
        }
    }

    /// 1 行の文字が枠に入らないときは右に広げる（原版の対話框単位は Windows の文字の幅で、Mac の文字は少し広い）。ページの外には出さない
    private func widened(_ frame: NSRect, for control: NSControl, multiline: Bool) -> NSRect {
        guard !multiline else { return frame }
        return widened(frame, original: frame, needed: ceil(control.fittingSize.width))
    }

    /// frame（original は原版の枠）を needed の幅まで広げる。右は同じ高さの右隣の控件の手前・ページの右端まで。
    /// それでも足りないときは、左に空きがあれば左へずらす（ほかの控件と重ならない範囲で）
    private func widened(_ frame: NSRect, original: NSRect, needed: CGFloat) -> NSRect {
        guard needed > frame.width else { return frame }
        var result = frame
        var limit = view.frame.width
        var leftLimit: CGFloat = 0
        if let group = enclosingGroup(original) {
            limit = group.maxX - Self.groupMargin
            leftLimit = group.minX + Self.groupMargin
        }
        for other in definition.controls where other.kind != "group" {
            let r = Self.rect(other.frame)
            guard r != original, r.maxY > original.minY, r.minY < original.maxY else { continue }
            if r.minX >= original.maxX - 1 { limit = min(limit, r.minX - 4) }
            if r.maxX <= original.minX + 1 {
                // 左隣のチェックボックスは文字の幅に縮めてあるので、その右端まで使える（第 48 步：中国語「Tab键(T)」）
                var edge = r.maxX
                if other.kind == "check", let left = controls[other.id], left.superview === view { edge = min(edge, left.frame.maxX) }
                if other.kind == "radio", let left = controls[other.id] as? NSButton, !left.title.contains("\n") {
                    // ラジオボタンも文字の幅に縮める（下の radioGroups）
                    edge = min(edge, r.minX + ceil(left.fittingSize.width) + 2)
                }
                leftLimit = max(leftLimit, edge + 4)
            }
        }
        result.size.width = min(needed, max(frame.width, limit - frame.minX))
        let shortage = needed - result.width
        if shortage > 0 && result.minX > leftLimit {
            let move = min(shortage, result.minX - leftLimit)
            result.origin.x -= move
            result.size.width += move
        }
        return result
    }

    /// 項目を入れた下拉框が全部の項目を見せられるように広げる（第 41 步）
    private func fitPopup(_ id: String) {
        guard let popup = controls[id] as? NSPopUpButton, let control = definition.controls.first(where: { $0.id == id }) else { return }
        // 原版の高さは開いたリストの分まで含むので、分组框・隣の控件は閉じたときの高さで探す（第 48 步：分组框からはみ出さない）
        var original = Self.rect(control.frame)
        original.size.height = min(original.height, popup.frame.height)
        let base = NSRect(x: original.minX, y: popup.frame.minY, width: original.width, height: popup.frame.height)
        popup.frame = widened(base, original: original, needed: ceil(popup.fittingSize.width))
    }

    /// ボタンの左右の余白：4 点まで。同じ高さにある隣の控件との間の半分を超えない
    /// 分组框の枠線と中の控件の間（点）
    static let groupMargin: CGFloat = 6

    /// この枠（原版の位置）を中に含む一番小さい分组框
    private func enclosingGroup(_ original: NSRect) -> NSRect? {
        definition.controls.filter { $0.kind == "group" }.map { Self.rect($0.frame) }
            .filter { $0.contains(original.insetBy(dx: 1, dy: 1)) }
            .min { $0.width * $0.height < $1.width * $1.height }
    }

    private func buttonMargins(_ frame: NSRect, id: String) -> (CGFloat, CGFloat) {
        var left: CGFloat = 4, right: CGFloat = 4
        if let group = enclosingGroup(frame) {
            left = min(left, max(0, frame.minX - (group.minX + Self.groupMargin)))
            right = min(right, max(0, group.maxX - Self.groupMargin - frame.maxX))
        }
        for other in definition.controls where other.id != id && other.kind != "group" {
            let r = Self.rect(other.frame)
            guard r.maxY > frame.minY, r.minY < frame.maxY else { continue }
            // 隣との間は 4 点以上残す
            if r.maxX <= frame.minX { left = min(left, max(0, (frame.minX - r.maxX - 4) / 2)) }
            if r.minX >= frame.maxX { right = min(right, max(0, (r.minX - frame.maxX - 4) / 2)) }
        }
        return (left, right)
    }

    private func setUpButton(_ button: NSButton, multiline: Bool) {
        button.controlSize = .small
        button.font = Self.font
        if multiline {
            button.cell?.wraps = true
            button.cell?.lineBreakMode = .byWordWrapping
        }
    }

    private func register(_ view: NSView, _ control: PropDialogs.Control) {
        guard control.id != "IDC_STATIC" else { return }
        controls[control.id] = view
        view.identifier = NSUserInterfaceItemIdentifier(control.id)
        view.setAccessibilityIdentifier(control.id)
    }

    // MARK: 动作

    @objc private func controlClicked(_ sender: NSView) {
        guard let id = sender.identifier?.rawValue else { return }
        if let button = sender as? NSButton, isRadio(button), button.state == .on { uncheckSiblings(of: button) }
        onChange?(id)
    }

    @objc private func pushButtonClicked(_ sender: NSView) {
        guard let id = sender.identifier?.rawValue else { return }
        // 第 49 步：「ヘルプ」（原版 IDC_BUTTON_HELP → MyWinHelp(HELP_CONTEXT)）
        if id == "IDC_BUTTON_HELP", HelpViewer.show(dialog: definition.dialog) { return }
        onButton?(id)
    }

    /// 控件的说明（第 49 步。原版的 p_helpids + Cshelp.txt）
    func contextHelpText(_ id: String) -> String? {
        HelpBook.shared?.popupText(dialog: definition.dialog, control: id)
    }

    @objc private func stepperClicked(_ sender: NSStepper) {
        guard let id = stepperBuddies[ObjectIdentifier(sender)] else { return }
        setText(id, String(sender.integerValue))
        onChange?(id)
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField, let id = field.identifier?.rawValue else { return }
        if let stepper = steppers[id] { stepper.integerValue = stepperValue(id) }
        onChange?(id)
    }

    private func isRadio(_ button: NSButton) -> Bool {
        button.superview is PropFlippedView && button.superview !== view
    }

    private func uncheckSiblings(of button: NSButton) {
        for case let other as NSButton in button.superview?.subviews ?? [] where other !== button {
            other.state = .off
        }
    }

    // MARK: 原版的 Dlg 函数

    func control(_ id: String) -> NSView? {
        controls[id]
    }

    func label(_ text: String) -> NSTextField? {
        labels[text]
    }

    /// IsDlgButtonChecked
    func isChecked(_ id: String) -> Bool {
        (controls[id] as? NSButton)?.state == .on
    }

    /// CheckDlgButton
    func setChecked(_ id: String, _ on: Bool) {
        guard let button = controls[id] as? NSButton else { return }
        button.state = on ? .on : .off
        if on && isRadio(button) { uncheckSiblings(of: button) }
    }

    /// GetDlgItemInt(…, FALSE)：没有符号的数字。数字以外的文字时是 0
    func int(_ id: String) -> Int {
        let text = self.text(id).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, text.allSatisfy({ $0.isASCII && $0.isNumber }), let value = UInt32(text) else { return 0 }
        return Int(value)
    }

    /// SetDlgItemInt
    func setInt(_ id: String, _ value: Int) {
        setText(id, String(value))
        steppers[id]?.integerValue = value
    }

    /// GetDlgItemText
    func text(_ id: String) -> String {
        (controls[id] as? NSTextField)?.stringValue ?? ""
    }

    /// SetDlgItemText
    func setText(_ id: String, _ text: String) {
        (controls[id] as? NSTextField)?.stringValue = text
    }

    /// GetDlgItemInt(…, TRUE)：有符号的数字。数字以外的文字时是 0
    func signedInt(_ id: String) -> Int {
        let text = self.text(id).trimmingCharacters(in: .whitespaces)
        let digits = text.hasPrefix("-") ? String(text.dropFirst()) : text
        guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }), let value = Int32(text) else { return 0 }
        return Int(value)
    }

    /// 列表（原版 ListView 的 LVS_REPORT。测试也用）
    func tree(_ id: String) -> PropTree? {
        trees[id]
    }

    func list(_ id: String) -> PropList? {
        lists[id]
    }

    /// Combo_ResetContent、Combo_InsertString、Combo_SetCurSel
    func setItems(_ id: String, _ titles: [String], selected: Int) {
        if let box = controls[id] as? NSComboBox {	// 入力できるコンボボックス：一覧だけ入れ替える（文字はそのまま。第 43 步）
            box.removeAllItems()
            box.addItems(withObjectValues: titles)
            return
        }
        guard let popup = controls[id] as? NSPopUpButton else { return }
        popup.removeAllItems()
        popup.addItems(withTitles: titles)
        if titles.indices.contains(selected) { popup.selectItem(at: selected) }
        fitPopup(id)
    }

    /// Combo_GetCurSel
    func selectedIndex(_ id: String) -> Int {
        max(0, (controls[id] as? NSPopUpButton)?.indexOfSelectedItem ?? 0)
    }

    /// Combo_SetCurSel
    func select(_ id: String, _ index: Int) {
        (controls[id] as? NSPopUpButton)?.selectItem(at: index)
    }

    /// 每项带值的组合框（原版 Combo_AddString + Combo_SetItemData）。名字相同的项也都放进去。
    /// selectedValue 的项选上，没有时选 selectIfMissing（nil 时什么也不选）。选上了时 true
    @discardableResult
    func setTaggedItems(_ id: String, _ items: [(value: Int, title: String)], selectedValue: Int?, selectIfMissing: Int? = 0) -> Bool {
        guard let popup = controls[id] as? NSPopUpButton else { return false }
        popup.removeAllItems()
        return appendTaggedItems(id, items, selectedValue: selectedValue, selectIfMissing: selectIfMissing)
    }

    /// 在后面追加带值的项（原版 CCodePage::AddComboCodePages 等）。selectedValue 的项选上了时 true
    @discardableResult
    func appendTaggedItems(_ id: String, _ items: [(value: Int, title: String)], selectedValue: Int?, selectIfMissing: Int? = nil) -> Bool {
        guard let popup = controls[id] as? NSPopUpButton, let menu = popup.menu else { return false }
        var found = false
        for item in items {
            let menuItem = NSMenuItem(title: item.title, action: nil, keyEquivalent: "")
            menuItem.tag = item.value
            menu.addItem(menuItem)
            if !found, let selectedValue, item.value == selectedValue {
                popup.select(menuItem)
                found = true
            }
        }
        if !found, let selectIfMissing, popup.numberOfItems > selectIfMissing {
            popup.selectItem(at: selectIfMissing)
        }
        fitPopup(id)
        return found
    }

    /// 选中的项的值（原版 Combo_GetItemData(Combo_GetCurSel)）。没有选中时 nil
    func selectedTag(_ id: String) -> Int? {
        (controls[id] as? NSPopUpButton)?.selectedItem?.tag
    }

    /// 组合框的项的名字（测试用）
    func itemTitles(_ id: String) -> [String] {
        (controls[id] as? NSPopUpButton)?.itemTitles ?? []
    }

    /// トラックバーの位置（原版 SetTrackBarPos / GetTrackBarPos）
    func sliderValue(_ id: String) -> Int {
        (controls[id] as? NSSlider)?.integerValue ?? 0
    }

    func setSliderValue(_ id: String, _ value: Int) {
        (controls[id] as? NSSlider)?.integerValue = value
    }

    /// トラックバーの範囲（原版 SetTrackBarRange）
    func setSliderRange(_ id: String, _ range: ClosedRange<Int>) {
        guard let slider = controls[id] as? NSSlider else { return }
        slider.minValue = Double(range.lowerBound)
        slider.maxValue = Double(range.upperBound)
    }

    /// 上下按钮的范围（原版 SetUpDownRange）
    func setRange(_ id: String, _ range: ClosedRange<Int>) {
        guard let stepper = steppers[id] else { return }
        stepper.minValue = Double(range.lowerBound)
        stepper.maxValue = Double(range.upperBound)
        if range.lowerBound < 0 { signedFields.insert(id) }
        stepper.integerValue = stepperValue(id)
    }

    private func stepperValue(_ id: String) -> Int {
        signedFields.contains(id) ? signedInt(id) : int(id)
    }

    /// Mac 版不能用的控件：一直变灰
    func setUnavailable(_ ids: Set<String>, reason: String) {
        unavailable.formUnion(ids)
        for id in ids {
            applyEnabled(id, false)
            controls[id]?.toolTip = reason
            labels[id]?.toolTip = reason
        }
    }

    func isUnavailable(_ id: String) -> Bool {
        unavailable.contains(id)
    }

    /// EnableWindow。id 是控件的 ID，或者 IDC_STATIC 的标签的文字
    func setEnabled(_ id: String, _ on: Bool) {
        applyEnabled(id, on && !unavailable.contains(id))
    }

    /// 是否可用（测试用）
    func isEnabled(_ id: String) -> Bool {
        if let control = controls[id] as? NSControl { return control.isEnabled }
        if let scroll = controls[id] as? NSScrollView { return (scroll.documentView as? NSControl)?.isEnabled ?? false }
        if let label = labels[id] { return label.isEnabled }
        return false
    }

    /// 是否显示（测试用）
    func isShown(_ id: String) -> Bool {
        guard let view = controls[id] ?? labels[id] else { return false }
        return !view.isHidden
    }

    /// ShowWindow + EnableWindow（原版 CPropBackup 的 ShowEnable）
    func showEnable(_ id: String, show: Bool, enable: Bool) {
        let target = controls[id] ?? labels[id]
        target?.isHidden = !show
        if let stepper = steppers[id] { stepper.isHidden = !show }
        setEnabled(id, enable && show)
    }

    /// 页里的全部控件变灰（以后的步骤移植的页）
    func disableAll(reason: String) {
        setUnavailable(Set(controls.keys).union(labels.keys), reason: reason)
    }

    private func applyEnabled(_ id: String, _ on: Bool) {
        let target = controls[id] ?? labels[id]
        if let field = target as? NSTextField, !field.isEditable, !field.isBezeled {
            // 标签：文字变灰
            field.isEnabled = on
            field.textColor = on ? .labelColor : .disabledControlTextColor
        } else if let control = target as? NSControl {
            control.isEnabled = on
        } else if let scroll = target as? NSScrollView {
            (scroll.documentView as? NSControl)?.isEnabled = on
        }
        steppers[id]?.isEnabled = on
    }
}

// MARK: - 列表

/// 原版的 ListView（LVS_REPORT | LVS_SINGLESEL）：几列的文字，一次选一行
final class PropList: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    let table = PropTableView()
    /// 每行的文字（列的顺序）
    private(set) var rows: [[String]] = []
    /// 选择变了（原版 LVN_ITEMCHANGED）
    var onSelect: (() -> Void)?
    /// 自己画的格子（原版 LBS_OWNERDRAWFIXED。タイプ別設定 > カラー 的色指定列表等，第 40 步）。nil 时是文字
    var cellView: ((_ row: Int, _ column: Int) -> NSView?)?
    /// 点了格子（原版的 WM_LBUTTONUP）、双击（WM_LBUTTONDBLCLK）、右键（WM_RBUTTONDOWN）
    var onClick: ((_ row: Int, _ column: Int) -> Void)?
    var onDoubleClick: ((_ row: Int, _ column: Int) -> Void)?
    var onRightClick: ((_ row: Int, _ column: Int) -> Void)?
    /// 列の文字の寄せ（原版 LVCFMT_LEFT・CENTER・RIGHT。指定のない列は左）
    var columnAlignments: [NSTextAlignment] = []
    private var notifying = true

    init(header: Bool) {
        super.init()
        if !header { table.headerView = nil }
        table.allowsMultipleSelection = false
        table.allowsEmptySelection = true
        table.rowHeight = 17
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("0"))
        column.title = ""	// 既定の「Field」を出さない（第 48 步）
        table.addTableColumn(column)
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(clicked(_:))
        table.doubleAction = #selector(doubleClicked(_:))
        table.onRightClick = { [weak self] row, column in self?.onRightClick?(row, column) }
    }

    @objc private func clicked(_ sender: Any?) {
        guard table.clickedRow >= 0 else { return }
        onClick?(table.clickedRow, table.clickedColumn)
    }

    @objc private func doubleClicked(_ sender: Any?) {
        guard table.clickedRow >= 0 else { return }
        onDoubleClick?(table.clickedRow, table.clickedColumn)
    }

    /// 一行重画（自己画的格子的内容变了）
    func reloadRow(_ row: Int) {
        guard rows.indices.contains(row) else { return }
        table.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integersIn: 0..<table.numberOfColumns))
    }

    /// 列（原版 ListView_InsertColumn）。widths 是宽度（点）
    func setColumns(_ titles: [String], widths: [CGFloat]) {
        for column in table.tableColumns { table.removeTableColumn(column) }
        for (index, title) in titles.enumerated() {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(String(index)))
            column.title = title
            column.headerCell.font = PropPage.font
            if widths.indices.contains(index) { column.width = widths[index] }
            table.addTableColumn(column)
        }
    }

    /// 换掉全部的行。选择没有了（不通知）
    func setRows(_ rows: [[String]]) {
        self.rows = rows
        notifying = false
        table.reloadData()
        table.deselectAll(nil)
        notifying = true
    }

    /// 选中的行。没有时 -1（原版 ListView_GetNextItem(…, LVNI_SELECTED)）
    var selectedRow: Int { table.selectedRow }

    /// 选这一行（原版 ListView_SetItemState(…, LVIS_SELECTED)）。没有这行时什么也不做
    func select(_ row: Int) {
        guard rows.indices.contains(row) else { return }
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        table.scrollRowToVisible(row)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let column = Int(tableColumn?.identifier.rawValue ?? "0") ?? 0
        if let cellView, let view = cellView(row, column) { return view }
        let text = rows.indices.contains(row) && rows[row].indices.contains(column) ? rows[row][column] : ""
        let label = NSTextField(labelWithString: text)
        label.font = PropPage.font
        label.lineBreakMode = .byClipping	// 原版の ListBox・TreeView は省略記号を付けず切る
        if columnAlignments.indices.contains(column) { label.alignment = columnAlignments[column] }
        return label
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        if notifying { onSelect?() }
    }
}

/// ツリーの一項目（原版 TreeView の HTREEITEM）
class PropTreeNode {
    var title: String
    /// 下位項目を持てる（原版 cChildren：子菜单は空でも開ける）
    var canHaveChildren: Bool
    var children: [PropTreeNode] = []
    weak var parent: PropTreeNode?

    init(title: String, canHaveChildren: Bool) {
        self.title = title
        self.canHaveChildren = canHaveChildren
    }

    /// 同じ階層の兄弟（親が無いときはツリーの最上位）
    func siblings(in tree: PropTree) -> [PropTreeNode] {
        parent?.children ?? tree.roots
    }
}

/// ツリー（原版 SysTreeView32。共通設定 > メインメニュー，第 41 步）
final class PropTree: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
    let outline = PropOutlineView()
    var roots: [PropTreeNode] = []
    /// 選択が変わった（原版 TVN_SELCHANGED）
    var onSelect: (() -> Void)?
    /// ダブルクリック（原版 NM_DBLCLK）
    var onDoubleClick: ((PropTreeNode) -> Void)?
    private var notifying = true

    override init() {
        super.init()
        outline.headerView = nil
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("0"))
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.rowHeight = 17
        outline.allowsMultipleSelection = false
        outline.allowsEmptySelection = true
        outline.dataSource = self
        outline.delegate = self
        outline.target = self
        outline.doubleAction = #selector(doubleClicked(_:))
    }

    @objc private func doubleClicked(_ sender: Any?) {
        guard let node = outline.item(atRow: outline.clickedRow) as? PropTreeNode else { return }
        onDoubleClick?(node)
    }

    /// 全部を描き直す（選択はそのまま、通知しない）
    func reload() {
        let selected = selectedNode
        notifying = false
        outline.reloadData()
        if let selected { select(selected, notify: false) }
        notifying = true
    }

    /// 一項目の表示を更新
    func reloadNode(_ node: PropTreeNode) {
        outline.reloadItem(node, reloadChildren: false)
    }

    var selectedNode: PropTreeNode? {
        outline.item(atRow: outline.selectedRow) as? PropTreeNode
    }

    /// この項目を選ぶ（親を開く）。nil は選択を外す
    func select(_ node: PropTreeNode?, notify: Bool = true) {
        let saved = notifying
        notifying = notify
        defer { notifying = saved }
        guard let node else {
            outline.deselectAll(nil)
            return
        }
        var ancestors: [PropTreeNode] = []
        var parent = node.parent
        while let p = parent {
            ancestors.insert(p, at: 0)
            parent = p.parent
        }
        for ancestor in ancestors { outline.expandItem(ancestor) }
        let row = outline.row(forItem: node)
        guard row >= 0 else { return }
        outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        outline.scrollRowToVisible(row)
    }

    func expand(_ node: PropTreeNode) {
        outline.expandItem(node)
    }

    /// 全開・全閉（原版 TreeView_ExpandAll）
    func expandAll(_ expand: Bool) {
        if expand {
            outline.expandItem(nil, expandChildren: true)
        } else {
            outline.collapseItem(nil, collapseChildren: true)
        }
    }

    func isExpanded(_ node: PropTreeNode) -> Bool {
        outline.isItemExpanded(node)
    }

    /// 見えている項目の題名（テスト用）
    var visibleTitles: [String] {
        (0..<outline.numberOfRows).compactMap { (outline.item(atRow: $0) as? PropTreeNode)?.title }
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        (item as? PropTreeNode)?.children.count ?? roots.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        (item as? PropTreeNode)?.children[index] ?? roots[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? PropTreeNode)?.canHaveChildren ?? false
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let label = NSTextField(labelWithString: (item as? PropTreeNode)?.title ?? "")
        label.font = PropPage.font
        label.lineBreakMode = .byClipping	// 原版の ListBox・TreeView は省略記号を付けず切る
        return label
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        if notifying { onSelect?() }
    }
}

/// キー入力も通知するツリー（原版 CPropMainMenu::TreeViewProc の WM_KEYDOWN）
final class PropOutlineView: NSOutlineView {
    /// 文字キー（アクセスキーの設定）。処理したら true
    var onCharacter: ((String) -> Bool)?
    /// Delete・BackSpace（削除）
    var onDelete: (() -> Void)?
    /// F2（名前の編集）
    var onRename: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .control, .option])
        if flags.isEmpty, let chars = event.charactersIgnoringModifiers, let scalar = chars.unicodeScalars.first {
            switch Int(scalar.value) {
            case NSDeleteCharacter, NSBackspaceCharacter, NSDeleteFunctionKey:
                onDelete?()
                return
            case NSF2FunctionKey:
                onRename?()
                return
            default:
                if scalar.value > 0x20 && scalar.value < 0xF700, let onCharacter, onCharacter(String(scalar).uppercased()) { return }
            }
        }
        super.keyDown(with: event)
    }
}

/// 右键也通知的表（原版的 WM_RBUTTONDOWN）
final class PropTableView: NSTableView {
    var onRightClick: ((_ row: Int, _ column: Int) -> Void)?

    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let row = self.row(at: point), column = self.column(at: point)
        if row >= 0, let onRightClick {
            selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            onRightClick(row, column)
        } else {
            super.rightMouseDown(with: event)
        }
    }
}

// MARK: - 窗口

/// 属性表的窗口（原版 PropertySheet）：左边是页的列表，右边是页，下边是 キャンセル、OK。
/// 共通設定（CommonSettingsWindowController）和タイプ別設定（TypeSettingsWindowController，第 40 步）共用
class PropSheetWindowController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    let dialogs: PropDialogs
    let values: CommonSettingsValues
    /// 辅助功能的标识的前缀（"CommonSettings"、"TypeSettings"）：窗口、OK、キャンセル、页的列表
    let identifierPrefix: String
    private var pages: [PropPage?]
    private var logics: [CommonSettingsPageLogic?]
    private(set) var currentIndex = -1
    private let sidebar = NSTableView()
    private let pageContainer = PropFlippedView()
    private let noteLabel = NSTextField(wrappingLabelWithString: "")

    init?(dialogs: PropDialogs?, values: CommonSettingsValues, title: String, identifierPrefix: String,
          logic: (String) -> CommonSettingsPageLogic?, page: Int) {
        guard let dialogs, !dialogs.pages.isEmpty else { return nil }
        self.dialogs = dialogs
        self.values = values
        self.identifierPrefix = identifierPrefix
        pages = Array(repeating: nil, count: dialogs.pages.count)
        logics = dialogs.pages.map { logic($0.dialog) }

        let pageWidth = PropPage.pointsX(dialogs.pages[0].size[0])
        let pageHeight = PropPage.points(dialogs.pages[0].size[1])
        let margin: CGFloat = 12, sidebarWidth: CGFloat = 150, buttonsHeight: CGFloat = 32
        let width = margin + sidebarWidth + margin + pageWidth + margin
        let height = margin + buttonsHeight + margin + pageHeight + margin
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        window.setAccessibilityIdentifier(identifierPrefix)
        super.init(window: window)
        window.delegate = self

        let content = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        window.contentView = content
        let top = margin + buttonsHeight + margin

        // 左边：页的列表（原版是标签）
        let scroll = NSScrollView(frame: NSRect(x: margin, y: top, width: sidebarWidth, height: pageHeight))
        scroll.borderType = .bezelBorder
        scroll.hasVerticalScroller = true
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("page"))
        column.width = sidebarWidth - 4
        sidebar.addTableColumn(column)
        sidebar.headerView = nil
        sidebar.rowHeight = 20
        sidebar.dataSource = self
        sidebar.delegate = self
        sidebar.setAccessibilityIdentifier(identifierPrefix + "Pages")
        scroll.documentView = sidebar
        content.addSubview(scroll)

        pageContainer.frame = NSRect(x: margin + sidebarWidth + margin, y: top, width: pageWidth, height: pageHeight)
        content.addSubview(pageContainer)

        // 下边：说明、キャンセル、OK（按钮的顺序按 Mac 的习惯：确定在右）
        let okButton = NSButton(title: "OK", target: self, action: #selector(ok(_:)))
        okButton.keyEquivalent = "\r"
        okButton.frame = NSRect(x: width - margin - 90, y: margin, width: 90, height: 28)
        okButton.setAccessibilityIdentifier(identifierPrefix + "OK")
        let cancelButton = NSButton(title: L10n.tr("キャンセル", comment: "共通設定窗口的按钮"), target: self, action: #selector(cancel(_:)))
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.frame = NSRect(x: width - margin - 90 - 8 - 90, y: margin, width: 90, height: 28)
        cancelButton.setAccessibilityIdentifier(identifierPrefix + "Cancel")
        for button in [okButton, cancelButton] {
            button.bezelStyle = .rounded
            content.addSubview(button)
        }
        // 第 49 步：ヘルプ（原版 プロパティシートの「ヘルプ」→ PSN_HELP → CPropCommon::OnHelp、CPropTypes::OnHelp）。
        // Mac の設定ウィンドウの習慣で左下の「?」ボタン
        let helpButton = NSButton(title: "", target: self, action: #selector(showHelp(_:)))
        helpButton.bezelStyle = .helpButton
        helpButton.frame = NSRect(x: margin, y: margin + 2, width: 25, height: 25)
        helpButton.setAccessibilityIdentifier(identifierPrefix + "Help")
        helpButton.toolTip = L10n.tr("ヘルプ", comment: "IDD_FIND")
        content.addSubview(helpButton)
        noteLabel.font = PropPage.font
        noteLabel.textColor = .secondaryLabelColor
        noteLabel.frame = NSRect(x: margin + sidebarWidth + margin, y: margin, width: cancelButton.frame.minX - (margin + sidebarWidth + margin) - 8, height: buttonsHeight)
        noteLabel.setAccessibilityIdentifier(identifierPrefix + "Note")
        content.addSubview(noteLabel)

        sidebar.reloadData()
        showPage(page)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: 子类决定的地方

    /// 显示了这一页（下次从这页开始：原版 m_nPageNum）
    func pageDidShow(_ index: Int) {}

    /// OK 写回以后（changed：有改过的项）。通知各窗口
    func didApply(changed: Bool) {}

    /// 窗口关了
    func didClose() {}

    /// 以后的步骤移植的页的说明
    func laterNote(for dialog: String) -> String {
        L10n.tr("このページは今後のバージョンで対応します。現在の設定を表示しています。", comment: "共通設定：以后的版本移植的页")
    }

    // MARK: 页

    var pageCount: Int { dialogs.pages.count }

    /// 这页（第一次时生成，原版 WM_INITDIALOG + SetData）
    func page(_ index: Int) -> PropPage {
        if let page = pages[index] { return page }
        let page = PropPage(definition: dialogs.pages[index])
        if let logic = logics[index] {
            for (id, range) in logic.ranges { page.setRange(id, range) }
            logic.setData(page, values)
            for (id, range) in logic.ranges { page.setRange(id, range) }
            page.setUnavailable(logic.unavailable, reason: L10n.tr("Mac 版では使用できません。", comment: "共通設定：Mac 版不能用的项目"))
            page.setUnavailable(logic.notYet, reason: L10n.tr("この項目は今後のバージョンで対応します。", comment: "共通設定：以后的版本移植的项目"))
            logic.enable(page)
            page.onChange = { [weak self, weak page] id in
                guard let self, let page else { return }
                logic.changed(id, page, self.values)
                logic.enable(page)
            }
            page.onButton = { [weak self, weak page] id in
                guard let self, let page else { return }
                logic.buttonPressed(id, page, self.values, window: self.window)
                logic.enable(page)
            }
        } else {
            page.disableAll(reason: laterNote(for: dialogs.pages[index].dialog))
        }
        pages[index] = page
        return page
    }

    /// 页的名字（原版的标签）
    func pageName(_ index: Int) -> String {
        dialogs.pages[index].name
    }

    func pageIndex(named name: String) -> Int? {
        dialogs.pages.firstIndex { $0.name == name }
    }

    /// 换页（原版 PSN_KILLACTIVE 时 GetData）
    func showPage(_ index: Int) {
        let index = min(max(0, index), pageCount - 1)
        guard index != currentIndex else { return }
        leaveCurrentPage()
        currentIndex = index
        pageDidShow(index)
        let isNew = pages[index] == nil
        let page = self.page(index)
        if !isNew, let logic = logics[index] {
            logic.activate(page, values)	// 原版 PSN_SETACTIVE
            logic.enable(page)
        }
        pageContainer.subviews.forEach { $0.removeFromSuperview() }
        page.view.frame.origin = .zero
        pageContainer.addSubview(page.view)
        noteLabel.stringValue = logics[index] == nil ? laterNote(for: dialogs.pages[index].dialog) : ""
        if sidebar.selectedRow != index {
            sidebar.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        }
    }

    private func leaveCurrentPage() {
        guard currentIndex >= 0, let page = pages[currentIndex], let logic = logics[currentIndex] else { return }
        logic.getData(page, values)
    }

    // MARK: ヘルプ

    /// 显示着的页的ヘルプ（第 49 步。原版 PSN_HELP）
    @objc func showHelp(_ sender: Any?) {
        guard currentIndex >= 0, HelpViewer.show(dialog: dialogs.pages[currentIndex].dialog) else { return NSSound.beep() }
    }

    // MARK: OK / キャンセル

    /// OK：看过的页的值写回，保存 sakura.ini，通知所有窗口（原版 PSN_APPLY → ApplyData → MYWM_CHANGESETTING）
    @objc func ok(_ sender: Any?) {
        leaveCurrentPage()
        let changed = !values.changes.isEmpty
        let succeeded = values.apply()
        didApply(changed: changed)
        if !succeeded {
            NSSound.beep()
        }
        closeWindow()
    }

    /// キャンセル：什么也不改
    @objc func cancel(_ sender: Any?) {
        closeWindow()
    }

    private func closeWindow() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        didClose()
    }

    // MARK: 页的列表

    func numberOfRows(in tableView: NSTableView) -> Int {
        pageCount
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let label = NSTextField(labelWithString: dialogs.pages[row].title ?? dialogs.pages[row].name)
        label.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        label.setAccessibilityIdentifier("\(identifierPrefix)Page_\(dialogs.pages[row].name)")
        return label
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = sidebar.selectedRow
        if row >= 0 { showPage(row) }
    }
}

/// 共通設定窗口。一次只有一个（原版也是）
final class CommonSettingsWindowController: PropSheetWindowController {
    /// 打开着的窗口
    private(set) static var shared: CommonSettingsWindowController?
    /// 上次的页（原版 CPropCommon::m_nPageNum：下次从这页开始）
    static var lastPage = 0

    /// F_OPTION_*（設定 > 共通設定 的各页）→ 页（原版 CViewCommander::Command_OPTION_* 的 ID_PROPCOM_PAGENUM_*）
    static let pageOfCommand: [Int: Int] = [
        32000: 0,	// F_OPTION_GENERAL 全般
        32001: 1,	// F_OPTION_WINDOW ウィンドウ
        32018: 2,	// F_OPTION_MAINMENU メインメニュー
        32010: 3,	// F_OPTION_TOOLBAR ツールバー
        32015: 4,	// F_OPTION_TAB タブバー
        32016: 5,	// F_OPTION_STATUSBAR ステータスバー
        32002: 6,	// F_OPTION_EDIT 編集
        32003: 7,	// F_OPTION_FILE ファイル
        32014: 8,	// F_OPTION_FNAME ファイル名表示
        32004: 9,	// F_OPTION_BACKUP バックアップ
        32005: 10,	// F_OPTION_FORMAT 書式
        32007: 11,	// F_OPTION_GREP 検索
        32008: 12,	// F_OPTION_KEYBIND キー割り当て
        32009: 13,	// F_OPTION_CUSTMENU カスタムメニュー
        32011: 14,	// F_OPTION_KEYWORD 強調キーワード
        32012: 15,	// F_OPTION_HELPER 支援
        32013: 16,	// F_OPTION_MACRO マクロ
        32017: 17,	// F_OPTION_PLUGIN プラグイン
    ]

    init?(store: CommonSettingsStore = CoreCommonSettingsStore(), page: Int = 0) {
        super.init(dialogs: PropDialogs.load(), values: CommonSettingsValues(store: store),
                   title: L10n.tr("共通設定", comment: "共通設定窗口的标题（原版 STR_PROPCOMMON）"),
                   identifierPrefix: "CommonSettings", logic: CommonSettingsPages.logic(for:), page: page)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// 打开（已经打开时到前面，换到这页）。page 是 nil 时是上次的页
    static func show(page: Int? = nil) {
        if let shared {
            if let page { shared.showPage(page) }
            shared.showWindow(nil)
            return
        }
        guard let controller = CommonSettingsWindowController(page: page ?? lastPage) else {
            NSSound.beep()
            return
        }
        shared = controller
        controller.window?.center()
        controller.showWindow(nil)
    }

    override func pageDidShow(_ index: Int) {
        Self.lastPage = index
    }

    override func didApply(changed: Bool) {
        if changed {
            EditorCore.resetMigemo()	// 第 44 步：Migemo の辞書を次に使うときに読み直す（原版は再起動まで読み直さない）
            NotificationCenter.default.post(name: EditorTextView.commonSettingsDidChangeNotification, object: nil)
        }
        // キー割り当て が変わった：メニューのショートカットを新しい割り当てで（第 41 步）
        if values.appliedSections.contains("KeyBind") {
            KeyCommands.reloadBindings()
            NotificationCenter.default.post(name: MainMenuBuilder.keyBindingsDidChangeNotification, object: nil)
        }
        // メインメニュー が変わった：菜单栏を作り直す（第 41 步）
        if values.appliedSections.contains("MainMenu") {
            NotificationCenter.default.post(name: MainMenuBuilder.mainMenuDidChangeNotification, object: nil)
        }
        // 強調キーワード（とそれを使うタイプ別設定）が変わった：全部の文書を新しい設定で（原版 F_REDRAW）
        if values.appliedSections.contains(where: { $0 == "KeyWords" || $0.hasPrefix("Types(") }) {
            NotificationCenter.default.post(name: TypeSettingsWindowController.didChangeNotification, object: nil, userInfo: ["index": -1])
        }
    }

    override func didClose() {
        if Self.shared === self { Self.shared = nil }
    }

    /// 以后的步骤移植的页的说明
    override func laterNote(for dialog: String) -> String {
        switch dialog {
        case "IDD_PROP_PLUGIN":
            return L10n.tr("Mac 版では DLL のプラグインは使用できません。", comment: "共通設定：プラグイン")
        default:
            return super.laterNote(for: dialog)
        }
    }

}

// MARK: - 菜单的动作

extension NSApplication {
    /// 設定 > 共通設定（F_OPTION）、各页（F_OPTION_GENERAL 等）、App 菜单的「設定…」（第 39 步）
    @objc func showCommonSettings(_ sender: Any?) {
        let code = EditorTextView.commandCode(of: sender) ?? 0
        CommonSettingsWindowController.show(page: CommonSettingsWindowController.pageOfCommand[code])
    }
}

// MARK: - ウィンドウの位置と大きさ

/// ウィンドウの位置と大きさ（原版 CDlgWinSize：共通設定 > ウィンドウ の「位置と大きさの設定」）。
/// 布局是原版的对话框模板 IDD_WINPOSSIZE。「閉じる」でも閉じるボタンでも値を取る（原版 IDOK、IDCANCEL とも GetData）
final class WinSizeDialog: NSObject, NSWindowDelegate {
    /// 原版 DoModal の引数（eSaveWinSize、eSaveWinPos、nWinSizeType、rc）
    struct Values: Equatable {
        /// 大きさ：0 指定しない、1 継承する、2 直接指定（WINSIZEMODE_*）
        var saveSize: Int
        /// 起動時の位置：同上
        var savePosition: Int
        /// 0 普通、2 最大化、1 最小化（SIZE_RESTORED、SIZE_MAXIMIZED、SIZE_MINIMIZED）
        var sizeType: Int
        var width: Int
        var height: Int
        var x: Int
        var y: Int
    }

    let page: PropPage
    let title: String
    private(set) var values: Values
    private var window: NSWindow?

    init?(values: Values) {
        guard let definition = PropDialogs.load()?.dialog("IDD_WINPOSSIZE") else { return nil }
        page = PropPage(definition: definition)
        title = definition.name
        self.values = values
        super.init()
        // 原版 OnInitDialog
        page.setItems("IDC_COMBO_WINTYPE", [L10n.tr("普通", comment: "STR_DLGWINSZ_NORMAL"),
                                            L10n.tr("最大化", comment: "STR_DLGWINSZ_MAXIMIZE"),
                                            L10n.tr("(最小化)", comment: "STR_DLGWINSZ_MINIMIZE")], selected: 0)
        setData()
        page.setRange("IDC_EDIT_SX", 0...30000)
        page.setRange("IDC_EDIT_SY", 0...30000)
        page.setRange("IDC_EDIT_WX", -30000...30000)
        page.setRange("IDC_EDIT_WY", -30000...30000)
        page.onChange = { [weak self] _ in self?.renewItemState() }
        page.onButton = { [weak self] id in
            if id == "IDOK" { self?.close() }
        }
    }

    private static let sizeButtons = ["IDC_RADIO_WINSIZE_DEF", "IDC_RADIO_WINSIZE_SAVE", "IDC_RADIO_WINSIZE_SET"]
    private static let positionButtons = ["IDC_RADIO_WINPOS_DEF", "IDC_RADIO_WINPOS_SAVE", "IDC_RADIO_WINPOS_SET"]

    /// 原版 SetData
    private func setData() {
        page.setChecked(Self.sizeButtons[(1...2).contains(values.saveSize) ? values.saveSize : 0], true)
        page.setChecked(Self.positionButtons[(1...2).contains(values.savePosition) ? values.savePosition : 0], true)
        page.select("IDC_COMBO_WINTYPE", values.sizeType == 1 ? 2 : values.sizeType == 2 ? 1 : 0)
        page.setText("IDC_EDIT_SX", String(values.width))
        page.setText("IDC_EDIT_SY", String(values.height))
        page.setText("IDC_EDIT_WX", String(values.x))
        page.setText("IDC_EDIT_WY", String(values.y))
        renewItemState()
    }

    /// 原版 GetData
    func getData() {
        if let index = Self.sizeButtons.firstIndex(where: page.isChecked) { values.saveSize = index }
        if let index = Self.positionButtons.firstIndex(where: page.isChecked) { values.savePosition = index }
        switch page.selectedIndex("IDC_COMBO_WINTYPE") {
        case 2: values.sizeType = 1	// SIZE_MINIMIZED
        case 1: values.sizeType = 2	// SIZE_MAXIMIZED
        default: values.sizeType = 0	// SIZE_RESTORED
        }
        values.width = page.signedInt("IDC_EDIT_SX")
        values.height = page.signedInt("IDC_EDIT_SY")
        values.x = page.signedInt("IDC_EDIT_WX")
        values.y = page.signedInt("IDC_EDIT_WY")
    }

    /// 原版 RenewItemState：直接指定のときだけ数を変えられる
    func renewItemState() {
        let position = page.isChecked("IDC_RADIO_WINPOS_SET")
        page.setEnabled("IDC_EDIT_WX", position)
        page.setEnabled("IDC_EDIT_WY", position)
        let size = page.isChecked("IDC_RADIO_WINSIZE_SET")
        page.setEnabled("IDC_COMBO_WINTYPE", size)
        page.setEnabled("IDC_EDIT_SX", size)
        page.setEnabled("IDC_EDIT_SY", size)
    }

    /// 「閉じる」
    func close() {
        if let window {
            window.close()	// windowWillClose で GetData
        } else {
            getData()
        }
    }

    /// 閉じるまで待つ（原版 DoModal）
    func runModal(parent: NSWindow?) {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: page.view.frame.size),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = title
        panel.isReleasedWhenClosed = false
        panel.setAccessibilityIdentifier("WinSizeDialog")
        panel.contentView = page.view
        panel.delegate = self
        (page.control("IDOK") as? NSButton)?.keyEquivalent = "\r"
        if let parent {
            panel.setFrameOrigin(NSPoint(x: parent.frame.midX - panel.frame.width / 2, y: parent.frame.midY - panel.frame.height / 2))
        } else {
            panel.center()
        }
        window = panel
        _ = NSApp.runModal(for: panel)
        window = nil
    }

    func windowWillClose(_ notification: Notification) {
        getData()
        NSApp.stopModal()
    }
}

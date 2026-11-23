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
    private var original: [Item: String] = [:]
    private var current: [Item: String] = [:]
    private var order: [Item] = []

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

        func has(_ flag: String) -> Bool { flags?.contains(flag) ?? false }
    }

    struct Page: Decodable {
        let name: String
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
        let bundle = Bundle(for: PropPage.self)
        guard let url = bundle.url(forResource: resource, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PropDialogs.self, from: data)
    }
}

/// 左上是原点的视图（对话框的坐标）
final class PropFlippedView: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - 一页

/// 一页（原版 IDD_PROP_* 的对话框）。控件按 ID（IDC_…）找，与原版的 GetDlgItem 相同
final class PropPage: NSObject, NSTextFieldDelegate {
    /// 对话框单位 → 点
    static let scale: CGFloat = 1.6
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
    /// 负数也可以的数值框（上下按钮的范围的下限是负数）
    private var signedFields: Set<String> = []

    /// 复选框、单选按钮、组合框、数值框变了（原版 WM_COMMAND 的 BN_CLICKED、CBN_SELCHANGE、EN_CHANGE）
    var onChange: ((String) -> Void)?
    /// 按钮按了
    var onButton: ((String) -> Void)?

    init(definition: PropDialogs.Page) {
        self.definition = definition
        view = PropFlippedView(frame: NSRect(x: 0, y: 0,
                                             width: Self.points(definition.size[0]), height: Self.points(definition.size[1])))
        super.init()
        build()
    }

    static func points(_ units: Double) -> CGFloat {
        (CGFloat(units) * scale).rounded()
    }

    private static func rect(_ frame: [Double]) -> NSRect {
        NSRect(x: points(frame[0]), y: points(frame[1]), width: points(frame[2]), height: points(frame[3]))
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
                setUpButton(button, multiline: text.contains("\n"))
                button.frame = frame
                view.addSubview(button)
                register(button, control)
            case "radio":
                let button = NSButton(radioButtonWithTitle: text, target: self, action: #selector(controlClicked(_:)))
                setUpButton(button, multiline: text.contains("\n"))
                radioGroups[group, default: []].append((button, frame))
                register(button, control)
            case "button":
                let button = NSButton(title: text, target: self, action: #selector(pushButtonClicked(_:)))
                button.bezelStyle = .rounded
                button.controlSize = .small
                button.font = Self.font
                // Mac 的按钮比 Windows 高：上下居中
                let height = max(frame.height, 22)
                button.frame = NSRect(x: frame.minX - 4, y: frame.midY - height / 2, width: frame.width + 8, height: height)
                view.addSubview(button)
                register(button, control)
            case "label":
                let label = text.contains("\n") || frame.height > Self.points(12)
                    ? NSTextField(wrappingLabelWithString: text) : NSTextField(labelWithString: text)
                label.font = Self.font
                if control.has("right") { label.alignment = .right }
                if control.has("center") { label.alignment = .center }
                label.frame = frame
                view.addSubview(label)
                register(label, control)
                if !text.isEmpty { labels[text] = label }
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
            case "list", "listview", "tree":
                let scroll = NSScrollView(frame: frame)
                scroll.borderType = .bezelBorder
                scroll.hasVerticalScroller = true
                let list = PropList(header: control.kind == "listview")
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
                container.addSubview(button)
            }
            view.addSubview(container)
        }

        // 模板里的初始状态
        for control in definition.controls where control.id != "IDC_STATIC" {
            if control.has("hidden") { controls[control.id]?.isHidden = true }
            if control.has("disabled") { setEnabled(control.id, false) }
        }
        for control in definition.controls where control.id == "IDC_STATIC" && control.has("hidden") {
            if let text = control.text, let label = labels[text] { label.isHidden = true }
        }
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
        onButton?(id)
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
    func list(_ id: String) -> PropList? {
        lists[id]
    }

    /// Combo_ResetContent、Combo_InsertString、Combo_SetCurSel
    func setItems(_ id: String, _ titles: [String], selected: Int) {
        guard let popup = controls[id] as? NSPopUpButton else { return }
        popup.removeAllItems()
        popup.addItems(withTitles: titles)
        if titles.indices.contains(selected) { popup.selectItem(at: selected) }
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
    private var notifying = true

    init(header: Bool) {
        super.init()
        if !header { table.headerView = nil }
        table.allowsMultipleSelection = false
        table.allowsEmptySelection = true
        table.rowHeight = 17
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("0")))
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
        label.lineBreakMode = .byTruncatingTail
        return label
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        if notifying { onSelect?() }
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

        let pageWidth = PropPage.points(dialogs.pages[0].size[0])
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
        let cancelButton = NSButton(title: NSLocalizedString("キャンセル", comment: "共通設定窗口的按钮"), target: self, action: #selector(cancel(_:)))
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.frame = NSRect(x: width - margin - 90 - 8 - 90, y: margin, width: 90, height: 28)
        cancelButton.setAccessibilityIdentifier(identifierPrefix + "Cancel")
        for button in [okButton, cancelButton] {
            button.bezelStyle = .rounded
            content.addSubview(button)
        }
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
        NSLocalizedString("このページは今後のバージョンで対応します。現在の設定を表示しています。", comment: "共通設定：以后的版本移植的页")
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
            page.setUnavailable(logic.unavailable, reason: NSLocalizedString("Mac 版では使用できません。", comment: "共通設定：Mac 版不能用的项目"))
            page.setUnavailable(logic.notYet, reason: NSLocalizedString("この項目は今後のバージョンで対応します。", comment: "共通設定：以后的版本移植的项目"))
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
        let page = self.page(index)
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
        let label = NSTextField(labelWithString: dialogs.pages[row].name)
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
                   title: NSLocalizedString("共通設定", comment: "共通設定窗口的标题（原版 STR_PROPCOMMON）"),
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
            NotificationCenter.default.post(name: EditorTextView.commonSettingsDidChangeNotification, object: nil)
        }
    }

    override func didClose() {
        if Self.shared === self { Self.shared = nil }
    }

    /// 以后的步骤移植的页的说明
    override func laterNote(for dialog: String) -> String {
        switch dialog {
        case "IDD_PROP_PLUGIN":
            return NSLocalizedString("Mac 版では DLL のプラグインは使用できません。", comment: "共通設定：プラグイン")
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
        page.setItems("IDC_COMBO_WINTYPE", [NSLocalizedString("普通", comment: "STR_DLGWINSZ_NORMAL"),
                                            NSLocalizedString("最大化", comment: "STR_DLGWINSZ_MAXIMIZE"),
                                            NSLocalizedString("(最小化)", comment: "STR_DLGWINSZ_MINIMIZE")], selected: 0)
        page.setUnavailable(["IDC_BUTTON_HELP"], reason: NSLocalizedString("この項目は今後のバージョンで対応します。", comment: "共通設定：以后的版本移植的项目"))
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

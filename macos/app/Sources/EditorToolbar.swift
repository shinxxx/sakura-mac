// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge

/// ツールバー（计划第 38 步。原版 CMainToolBar）。
///
/// - ボタンは共通設定『ツールバー』の並び（sakura.ini の [Toolbar]）。アイコンは原版の mytool.bmp（ToolbarIcons）。
///   ボタンの大きさは原版と同じ 22×22（16×16 のアイコン＋枠）、区切りは隙間と線、「折返」で次の段へ。
/// - 押すと機能を実行する（CommandTable）。使えない機能は薄く、チェック状態の機能（挿入／上書き 等）は押された形
///   （原版 UpdateToolbar：IsFuncEnable・IsFuncChecked。Mac 版はメニューの validateMenuItem と同じ判定）。
/// - ツールチップは機能名と割り当てたキー（原版 GetTooltipText。キーは Mac のショートカットの書き方）。
/// - 「開く(ドロップダウン)」は右の▼で最近使ったファイル・フォルダーのメニュー（原版 CreateFileDropDownMenu）、
///   「検索(ボックス)」は検索文字列のコンボボックス（Enter で次を検索。原版 ProcSearchBox）。
/// - 「フラットツールバーにする」がオフのときはボタンの枠をいつも描く。
/// - 表示するかは共通設定『ウィンドウ』「ツールバーを表示する」（bDispTOOLBAR）と 設定 > ツールバーの表示（F_SHOWTOOLBAR）。
final class EditorToolbarView: NSView, WindowBarSizing {
    /// ボタンの大きさ（原版 cxToolButton・cyToolButton = 枠 1 + 縁 1 + 16 + 縁 1 + 枠 1）
    static let buttonSize: CGFloat = 22
    /// 区切りの幅（Windows のツールバーの TBSTYLE_SEP の既定の幅）
    static let separatorWidth: CGFloat = 8
    /// ツールバーの上下・左の余白
    static let padding: CGFloat = 2
    /// 検索(ボックス) の幅
    static let searchBoxWidth: CGFloat = 160
    static let fileOpenDropDown = 30108	// F_FILEOPEN_DROPDOWN
    static let searchBox = 30908		// F_SEARCH_BOX

    /// ボタン・区切り・折返（並べる前）
    enum Item: Equatable {
        case button(code: Int, icon: Int)
        case separator
        case wrap
    }

    let items: [Item]
    let isFlat: Bool
    weak var textView: EditorTextView?
    private(set) var buttons: [ToolbarButton] = []
    private(set) var searchBox: NSComboBox?
    /// 区切りの位置（線を描く）
    private var separatorRects: [NSRect] = []

    init(items: [Item], flat: Bool) {
        self.items = items
        isFlat = flat
        super.init(frame: NSRect(x: 0, y: 0, width: 400, height: Self.buttonSize + Self.padding * 2))
        setAccessibilityElement(true)
        setAccessibilityIdentifier("toolbar")
        setAccessibilityRole(.toolbar)
        for item in items {
            guard case let .button(code, icon) = item else { continue }
            if code == Self.searchBox {
                let combo = NSComboBox()
                combo.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
                combo.controlSize = .small
                combo.completes = false
                combo.target = self
                combo.action = #selector(searchBoxEntered(_:))
                combo.setAccessibilityIdentifier("toolbar.searchBox")
                addSubview(combo)
                searchBox = combo
                continue
            }
            let button = ToolbarButton(code: code, icon: ToolbarIcons.shared.image(icon), flat: flat,
                                       dropDown: code == Self.fileOpenDropDown)
            button.target = self
            button.action = #selector(buttonPressed(_:))
            addSubview(button)
            buttons.append(button)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool { true }

    /// 共通設定のツールバーの並び（原版 CMainToolBar::CreateToolBar：区切りが続くときは 1 つ、折返の前の区切りは折返に）
    static func currentItems() -> (items: [Item], flat: Bool) {
        guard let editor = EditorCommandSettingsEditor() else { return ([], false) }
        var items: [Item] = []
        for number in editor.toolbarButtons.map(\.intValue) {
            let item: Item
            switch editor.kind(ofToolbarButton: number) {
            case 0: item = .button(code: editor.function(ofToolbarButton: number), icon: editor.icon(ofToolbarButton: number))
            case 1: item = .separator
            case 2: item = .wrap
            default: continue
            }
            // 区切り・折返が続くときは後のもので置き換える（原版：TBSTYLE_SEP が続いたら前のを上書き）
            if item == .separator || item == .wrap, let last = items.last, last == .separator || last == .wrap {
                items[items.count - 1] = item
                continue
            }
            items.append(item)
        }
        return (items, editor.toolbarIsFlat)
    }

    // MARK: - 並べる

    /// 並べた結果（ボタンの位置、区切りの位置、高さ）
    private func arrangement(width: CGFloat) -> (frames: [NSRect], separators: [NSRect], height: CGFloat) {
        var frames: [NSRect] = []
        var separators: [NSRect] = []
        let rowHeight = Self.buttonSize
        var x = Self.padding, y = Self.padding
        for item in items {
            switch item {
            case .wrap:
                x = Self.padding
                y += rowHeight
            case .separator:
                separators.append(NSRect(x: x, y: y, width: Self.separatorWidth, height: rowHeight))
                x += Self.separatorWidth
            case let .button(code, _):
                let w = code == Self.searchBox ? Self.searchBoxWidth : (code == Self.fileOpenDropDown ? Self.buttonSize + ToolbarButton.arrowWidth : Self.buttonSize)
                frames.append(NSRect(x: x, y: y, width: w, height: rowHeight))
                x += w
            }
        }
        return (frames, separators, y + rowHeight + Self.padding)
    }

    func fittingHeight(forWidth width: CGFloat) -> CGFloat {
        arrangement(width: width).height
    }

    override func layout() {
        super.layout()
        arrangeButtons()
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        arrangeButtons()
    }

    func arrangeButtons() {
        let result = arrangement(width: bounds.width)
        separatorRects = result.separators
        let codes = items.compactMap { item -> Int? in
            if case let .button(code, _) = item { return code }
            return nil
        }
        var buttonIndex = 0
        for (code, frame) in zip(codes, result.frames) {
            if code == Self.searchBox, let searchBox {
                let height = searchBox.fittingSize.height
                searchBox.frame = NSRect(x: frame.minX + 1, y: (frame.midY - height / 2).rounded(.down), width: frame.width - 2, height: height)
            } else if buttonIndex < buttons.count {
                buttons[buttonIndex].frame = frame
                buttonIndex += 1
            }
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        // 区切りの線（フラットツールバーの区切りと同じく縦の線）
        NSColor.separatorColor.setFill()
        for r in separatorRects {
            NSRect(x: r.midX.rounded(.down), y: r.minY + 2, width: 1, height: r.height - 4).fill()
        }
        // 下の境界線
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
    }

    // MARK: - 状態（原版 UpdateToolbar）

    /// 使える・チェックの状態をメニューと同じ判定で更新する
    func updateStates() {
        guard let textView else { return }
        for button in buttons {
            let code = button.code == Self.fileOpenDropDown ? 30102 : button.code	// 開く(ドロップダウン) は 開く と同じ
            let state = CommandTable.validate(code, from: textView)
            if button.isEnabled != state.enabled { button.isEnabled = state.enabled }
            if button.isChecked != state.checked { button.isChecked = state.checked }
        }
    }

    // MARK: - 操作

    @objc private func buttonPressed(_ sender: ToolbarButton) {
        guard let textView else { return }
        if sender.code == Self.fileOpenDropDown {
            if sender.arrowPressed {
                showFileDropDown(sender)
                return
            }
            CommandTable.perform(30102, from: textView)	// F_FILEOPEN
            return
        }
        textView.window?.makeFirstResponder(textView)
        CommandTable.perform(sender.code, from: textView)
    }

    /// 開く(ドロップダウン) のメニュー（原版 CEditWnd::CreateFileDropDownMenu：最近使ったファイル、区切り、
    /// 最近使ったフォルダー（なければ灰色）、区切り、履歴の管理、区切り、新規作成・新しいウィンドウを開く・開く）
    func fileDropDownMenu() -> NSMenu {
        let menu = NSMenu()
        let files = Self.fileMenus.files, folders = Self.fileMenus.folders
        files.update()
        for item in files.menu.items { menu.addItem(item.copy() as! NSMenuItem) }
        if !files.menu.items.isEmpty { menu.addItem(.separator()) }
        folders.update()
        let folderItem = NSMenuItem(title: folders.item.title, action: nil, keyEquivalent: "")
        if !folders.menu.items.isEmpty {
            let submenu = NSMenu(title: folders.item.title)
            for item in folders.menu.items { submenu.addItem(item.copy() as! NSMenuItem) }
            folderItem.submenu = submenu
        }
        menu.addItem(folderItem)
        menu.addItem(.separator())
        for code in [31113, 0, 30101, 30110, 30102] {	// F_FAVORITE、区切り、F_FILENEW、F_FILENEW_NEWWINDOW、F_FILEOPEN
            if code == 0 {
                menu.addItem(.separator())
                continue
            }
            let item = NSMenuItem(title: RecentMenu.labelWithoutMnemonic(EditorCore.name(ofCommand: code)),
                                  action: CommandTable.selector(for: code), keyEquivalent: "")
            item.tag = code
            menu.addItem(item)
        }
        return menu
    }

    private func showFileDropDown(_ button: ToolbarButton) {
        fileDropDownMenu().popUp(positioning: nil, at: NSPoint(x: button.frame.minX, y: button.frame.maxY), in: self)
    }

    /// ドロップダウン用の履歴のメニュー（一度だけ作る）
    private static let fileMenus = (files: RecentMenu(kind: .files), folders: RecentMenu(kind: .folders))

    /// 検索(ボックス)：Enter で次を検索（原版 CMainToolBar::ProcSearchBox）
    @objc private func searchBoxEntered(_ sender: NSComboBox) {
        guard let textView else { return }
        let text = sender.stringValue
        guard !text.isEmpty else { return }
        let options = EditorCore.searchSettings.options
        guard EditorTextView.checkRegexpSyntax(text, options: options) else { return }
        if (text as NSString).length < 260 { EditorCore.addSearchKey(text) }
        textView.setSearchKey(text, options: options)
        textView.window?.makeFirstResponder(textView)
        textView.searchNextCommand()
        updateSearchHistory()
    }

    /// 検索(ボックス) の履歴（原版 AcceptSharedSearchKey）
    func updateSearchHistory() {
        guard let searchBox else { return }
        let history = EditorCore.searchKeyHistory
        if searchBox.objectValues as? [String] != history {
            searchBox.removeAllItems()
            searchBox.addItems(withObjectValues: history)
        }
    }
}

/// ツールバーのボタン（原版のツールバーのボタンの見た目：フラットは指したときだけ枠、押すとへこむ、チェックはへこんだまま）
final class ToolbarButton: NSButton {
    static let arrowWidth: CGFloat = 12

    let code: Int
    let isFlat: Bool
    let hasDropDown: Bool
    /// ドロップダウンの▼を押した
    private(set) var arrowPressed = false
    var isChecked = false {
        didSet { needsDisplay = true }
    }
    private var hovering = false {
        didSet { if oldValue != hovering { needsDisplay = true } }
    }
    private var pressing = false {
        didSet { if oldValue != pressing { needsDisplay = true } }
    }
    private var trackingArea: NSTrackingArea?

    init(code: Int, icon: NSImage?, flat: Bool, dropDown: Bool) {
        self.code = code
        isFlat = flat
        hasDropDown = dropDown
        super.init(frame: NSRect(x: 0, y: 0, width: EditorToolbarView.buttonSize, height: EditorToolbarView.buttonSize))
        image = icon
        imagePosition = .imageOnly
        isBordered = false
        title = ""
        (cell as? NSButtonCell)?.imageDimsWhenDisabled = true
        let name = RecentMenu.labelWithoutMnemonic(EditorCore.name(ofCommand: code))
        toolTip = Self.tooltip(code: code, name: name)
        setAccessibilityIdentifier("toolbar.\(code)")
        setAccessibilityLabel(name)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// ツールチップ（原版 GetTooltipText：機能名、改行して割り当てたキー）
    static func tooltip(code: Int, name: String) -> String {
        guard let key = KeyCommands.menuKeyEquivalent(for: code == EditorToolbarView.fileOpenDropDown ? 30102 : code) else { return name }
        return name + "\n        " + shortcutText(key.key, key.modifiers)
    }

    /// ショートカットの書き方（⌃⌥⇧⌘ ＋ キー）
    static func shortcutText(_ key: String, _ modifiers: NSEvent.ModifierFlags) -> String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        let special: [Character: String] = ["\u{F704}": "F1", "\u{F705}": "F2", "\u{F706}": "F3", "\u{F707}": "F4",
                                            "\u{F708}": "F5", "\u{F709}": "F6", "\u{F70A}": "F7", "\u{F70B}": "F8",
                                            "\u{F70C}": "F9", "\u{F70D}": "F10", "\u{F70E}": "F11", "\u{F70F}": "F12",
                                            "\r": "↩", "\t": "⇥", "\u{1B}": "⎋", "\u{8}": "⌫", "\u{7F}": "⌦",
                                            "\u{F700}": "↑", "\u{F701}": "↓", "\u{F702}": "←", "\u{F703}": "→",
                                            "\u{F729}": "↖", "\u{F72B}": "↘", "\u{F72C}": "⇞", "\u{F72D}": "⇟", " ": "Space"]
        if let c = key.first, key.count == 1, let name = special[c] { return text + name }
        return text + key.uppercased()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        let start = convert(event.locationInWindow, from: nil)
        arrowPressed = hasDropDown && start.x >= bounds.width - Self.arrowWidth
        if arrowPressed {
            pressing = true
            _ = sendAction(action, to: target)
            pressing = false
            return
        }
        pressing = true
        var inside = true
        while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            inside = bounds.contains(convert(next.locationInWindow, from: nil))
            pressing = inside
            if next.type == .leftMouseUp { break }
        }
        pressing = false
        if inside { _ = sendAction(action, to: target) }
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let sunken = pressing || isChecked
        let showFrame = !isFlat || (isEnabled && hovering) || sunken
        if showFrame {
            let path = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
            (sunken ? NSColor.controlAccentColor.withAlphaComponent(isChecked && !pressing ? 0.18 : 0.28)
                    : NSColor.controlAccentColor.withAlphaComponent(0.10)).setFill()
            path.fill()
            (sunken ? NSColor.controlAccentColor.withAlphaComponent(0.55) : NSColor.separatorColor).setStroke()
            path.lineWidth = 1
            path.stroke()
        }
        let iconWidth = hasDropDown ? bounds.width - Self.arrowWidth : bounds.width
        if let image {
            let size = NSSize(width: 16, height: 16)
            var origin = NSPoint(x: ((iconWidth - size.width) / 2).rounded(.down), y: ((bounds.height - size.height) / 2).rounded(.down))
            if sunken { origin.x += 1; origin.y += 1 }
            image.draw(in: NSRect(origin: origin, size: size), from: .zero, operation: .sourceOver,
                       fraction: isEnabled ? 1 : 0.35, respectFlipped: true, hints: nil)
        }
        if hasDropDown {
            // ▼（原版 TBSTYLE_EX_DRAWDDARROWS）
            if showFrame {
                NSColor.separatorColor.setFill()
                NSRect(x: iconWidth, y: 3, width: 1, height: bounds.height - 6).fill()
            }
            let cx = iconWidth + Self.arrowWidth / 2, cy = bounds.midY
            let arrow = NSBezierPath()
            arrow.move(to: NSPoint(x: cx - 3, y: cy - 1.5))
            arrow.line(to: NSPoint(x: cx + 3, y: cy - 1.5))
            arrow.line(to: NSPoint(x: cx, y: cy + 1.5))
            arrow.close()
            (isEnabled ? NSColor.labelColor : NSColor.tertiaryLabelColor).setFill()
            arrow.fill()
        }
    }

    override var isFlipped: Bool { true }
}

extension CommandTable {
    /// この機能が使えるか、チェック状態か（原版 IsFuncEnable・IsFuncChecked。Mac 版はメニューの項目と同じ判定）。
    /// responder（編集画面）から応答の鎖をたどり、動作を持つものの validateMenuItem・validateUserInterfaceItem で判定する
    static func validate(_ code: Int, from responder: NSResponder?) -> (enabled: Bool, checked: Bool) {
        guard let selector = selector(for: code) else { return (false, false) }
        let item = NSMenuItem(title: "", action: selector, keyEquivalent: "")
        item.tag = code
        var candidates: [NSObject] = []
        var r = responder
        while let current = r {
            candidates.append(current)
            r = current.nextResponder
        }
        if let window = (responder as? NSView)?.window {
            if let delegate = window.delegate as? NSObject { candidates.append(delegate) }
            if let document = window.windowController?.document as? NSObject { candidates.append(document) }
        }
        candidates.append(NSApp)
        if let delegate = NSApp.delegate as? NSObject { candidates.append(delegate) }
        candidates.append(NSDocumentController.shared)
        guard let target = candidates.first(where: { $0.responds(to: selector) }) else { return (false, false) }
        let enabled: Bool
        if let validation = target as? NSMenuItemValidation {
            enabled = validation.validateMenuItem(item)
        } else if let validation = target as? NSUserInterfaceValidations {
            enabled = validation.validateUserInterfaceItem(item)
        } else {
            enabled = true
        }
        return (enabled, item.state == .on)
    }
}

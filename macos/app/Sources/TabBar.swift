// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge

/// タブバー（计划第 38 步。原版 CTabWnd）。
///
/// - 開いている編集窓口を 1 つずつタブにする（開いた順）。押すとその窓口に切り替える。
/// - 共通設定『タブバー』に従う：表示位置（上・下）、等幅、アイコン、閉じるボタン（なし・常に表示・自動表示）、多段、
///   マウスホイールで切り替え、「ウィンドウをまとめてグループ化する」（bDispTabWndMultiWin の反対）。
/// - まとめるとき（原版の既定）：窓口は 1 つだけ見せ、ほかは同じ位置・大きさで隠す（原版 CTabWnd の ShowHideWindow と同じやり方）。
///   まとめないとき：窓口はそれぞれ表示したまま、どの窓口のタブバーにも全部のタブを出す。
/// - 右端のボタン：▼ タブの一覧、× 今のタブを閉じる（原版 TAB_MARGIN_RIGHT の 2 つのボタン）。
/// - タブバーを表示するときは macOS の窓口のタブ（tabbingMode）は使わない。表示しないときは今までどおり macOS のタブ。
/// - 一段のときに入りきらないタブは幅を最小まで縮め、それでも入らないものは一覧から選ぶ（原版は左右の矢印でずらす）。
final class TabBarView: NSView, WindowBarSizing {
    /// タブの文字の大きさ（原版 lfTabFont の既定：アイコンのタイトルのフォント 9pt）
    static let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
    /// タブの高さ（原版 TAB_ITEM_HEIGHT = 文字の高さ + 7）
    static var itemHeight: CGFloat { ceil(font.ascender - font.descender) + 7 }
    /// 上の余白（原版 TAB_MARGIN_TOP）、左（TAB_MARGIN_LEFT）、右のボタンの分（TAB_MARGIN_RIGHT）
    static let marginTop: CGFloat = 3
    static let marginLeft: CGFloat = 1
    static let marginRight: CGFloat = 47
    /// タブの文字の左右の余白（原版 TabCtrl_SetPadding の 6）
    static let padding: CGFloat = 6
    static let closeButtonSize: CGFloat = 14
    static let iconSize: CGFloat = 16

    /// 設定（原版 CommonSetting_TabBar）
    struct Settings: Equatable {
        var atBottom = false
        var sameWidth = false
        var showIcon = false
        var closeButton = 0		// 0 なし、1 常に表示、2 自動表示（原版 EDispTabClose）
        var multiLine = false
        var wheelSwitch = false
        var group = true		// ウィンドウをまとめてグループ化する
        var maxWidth: CGFloat = 200
        var minWidth: CGFloat = 60
        var minWidthMulti: CGFloat = 100

        static var current: Settings {
            func int(_ key: String, _ fallback: Int = 0) -> Int {
                Int(EditorCore.commonSetting(section: "Common", key: key)?.trimmingCharacters(in: .whitespaces) ?? "") ?? fallback
            }
            var s = Settings()
            s.atBottom = int("eTabPosition") == 1
            s.sameWidth = int("bSameTabWidth") != 0
            s.showIcon = int("bDispTabIcon") != 0
            s.closeButton = int("bDispTabClose")
            s.multiLine = int("bTabMultiLine") != 0
            s.wheelSwitch = int("bChgWndByWheel") != 0
            s.group = int("bDispTabWndMultiWin") == 0
            s.maxWidth = CGFloat(max(1, int("nTabMaxWidth", 200)))
            s.minWidth = CGFloat(max(1, int("nTabMinWidth", 60)))
            s.minWidthMulti = CGFloat(max(1, int("nTabMinWidthOnMulti", 100)))
            return s
        }
    }

    /// 1 つのタブ
    struct Tab: Equatable {
        let id: ObjectIdentifier
        let title: String
        let toolTip: String
        let path: String
    }

    var settings: Settings {
        didSet { if oldValue != settings { relayout() } }
    }
    private(set) var tabs: [Tab] = []
    /// 選んでいるタブ（この窓口）
    private(set) var selectedID: ObjectIdentifier?
    /// タブの位置
    private(set) var tabRects: [NSRect] = []
    private var hoverIndex: Int?
    private var trackingArea: NSTrackingArea?
    /// タブを押した（窓口を切り替える）
    var onSelect: ((ObjectIdentifier) -> Void)?
    /// タブの閉じるボタン（このタブの窓口を閉じる）
    var onClose: ((ObjectIdentifier) -> Void)?
    private let listButton = NSButton()
    private let closeButton = NSButton()

    init(settings: Settings) {
        self.settings = settings
        super.init(frame: NSRect(x: 0, y: 0, width: 400, height: Self.itemHeight + Self.marginTop + 2))
        setAccessibilityIdentifier("tabBar")
        setAccessibilityRole(.tabGroup)
        for (button, title, id, action) in [(listButton, "▼", "tabBar.list", #selector(showList(_:))),
                                            (closeButton, "✕", "tabBar.close", #selector(closeCurrent(_:)))] {
            button.title = title
            button.isBordered = false
            button.font = NSFont.systemFont(ofSize: 9)
            button.target = self
            button.action = action
            button.setAccessibilityIdentifier(id)
            addSubview(button)
        }
        listButton.toolTip = L10n.tr("左クリック: タブ名一覧\n右クリック: パス名一覧", comment: "STR_TABWND_LR_INFO")
        closeButton.toolTip = L10n.tr("タブを閉じる", comment: "STR_TABWND_CLOSETAB")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool { true }

    /// タブを入れ替える
    func setTabs(_ tabs: [Tab], selected: ObjectIdentifier?) {
        guard tabs != self.tabs || selected != selectedID else { return }
        let countChanged = tabs.count != self.tabs.count
        self.tabs = tabs
        selectedID = selected
        if countChanged && settings.multiLine {
            (superview as? EditorContainerView)?.arrange()
        }
        relayout()
        setAccessibilityChildren(nil)
    }

    private func relayout() {
        arrangeTabs()
        needsDisplay = true
    }

    // MARK: - 幅と並び（原版 CTabWnd::LayoutTab）

    private var availableWidth: CGFloat { max(0, bounds.width - Self.marginLeft - Self.marginRight) }

    /// タブの幅（等幅のときは幅を数で割って最小・最大の間、そうでないときは文字の幅＋余白）
    func tabWidths(available: CGFloat) -> [CGFloat] {
        guard !tabs.isEmpty else { return [] }
        let minWidth = settings.multiLine ? settings.minWidthMulti : settings.minWidth
        if settings.sameWidth {
            let w = min(settings.maxWidth, max(minWidth, ((available - 8) / CGFloat(tabs.count)).rounded(.down)))
            return Array(repeating: w, count: tabs.count)
        }
        let extra = (settings.showIcon ? Self.iconSize + 6 : 0) + (settings.closeButton == 1 ? Self.closeButtonSize + 2 : 0)
        var widths = tabs.map { tab in
            min(settings.maxWidth, ceil((tab.title as NSString).size(withAttributes: [.font: Self.font]).width) + Self.padding * 2 + extra)
        }
        if !settings.multiLine {
            // 一段で入りきらないときは縮める（最小の幅まで）
            let total = widths.reduce(0, +)
            if total > available && total > 0 {
                let ratio = available / total
                widths = widths.map { max(min(minWidth, $0), ($0 * ratio).rounded(.down)) }
            }
        }
        return widths
    }

    private func layoutRects(width: CGFloat) -> (rects: [NSRect], rows: Int) {
        let available = max(0, width - Self.marginLeft - Self.marginRight)
        var rects: [NSRect] = []
        var x = Self.marginLeft, row = 0
        for w in tabWidths(available: available) {
            if settings.multiLine && x > Self.marginLeft && x + w > Self.marginLeft + available {
                row += 1
                x = Self.marginLeft
            }
            rects.append(NSRect(x: x, y: Self.marginTop + CGFloat(row) * Self.itemHeight, width: w, height: Self.itemHeight))
            x += w
        }
        return (rects, row + 1)
    }

    func fittingHeight(forWidth width: CGFloat) -> CGFloat {
        CGFloat(layoutRects(width: width).rows) * Self.itemHeight + Self.marginTop + 2
    }

    override func layout() {
        super.layout()
        arrangeTabs()
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        arrangeTabs()
    }

    private func arrangeTabs() {
        tabRects = layoutRects(width: bounds.width).rects
        let size: CGFloat = 18
        let y = Self.marginTop + (Self.itemHeight - size) / 2
        closeButton.frame = NSRect(x: bounds.width - 4 - size, y: y, width: size, height: size)
        listButton.frame = NSRect(x: closeButton.frame.minX - 2 - size, y: y, width: size, height: size)
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    // MARK: - 描画（原版の SysTabControl32：選んでいるタブは背景の色で少し大きく、ほかは一段暗く）

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        // タブの下の線（選んでいるタブのところは開いている）
        NSColor.separatorColor.setFill()
        let baseY = settings.atBottom ? Self.marginTop : bounds.height - 1
        NSRect(x: 0, y: baseY, width: bounds.width, height: 1).fill()
        for (i, tab) in tabs.enumerated() where i < tabRects.count {
            drawTab(tab, in: tabRects[i], selected: tab.id == selectedID, hover: i == hoverIndex)
        }
    }

    private func drawTab(_ tab: Tab, in rect: NSRect, selected: Bool, hover: Bool) {
        var r = rect
        if !selected { r = settings.atBottom ? NSRect(x: r.minX, y: r.minY, width: r.width, height: r.height - 2) : NSRect(x: r.minX, y: r.minY + 2, width: r.width, height: r.height - 2) }
        let path = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
        (selected ? NSColor.controlBackgroundColor : (hover ? NSColor.controlAccentColor.withAlphaComponent(0.12) : NSColor.underPageBackgroundColor.withAlphaComponent(0.6))).setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()
        if selected {
            // タブと下の線のつながり
            NSColor.controlBackgroundColor.setFill()
            let y = settings.atBottom ? r.minY : r.maxY - 1.5
            NSRect(x: r.minX + 1, y: y, width: r.width - 2, height: 2).fill()
        }
        var textLeft = r.minX + Self.padding
        if settings.showIcon {
            let icon = tab.path.isEmpty ? NSImage(named: NSImage.multipleDocumentsName) : NSWorkspace.shared.icon(forFile: tab.path)
            icon?.draw(in: NSRect(x: textLeft, y: r.midY - Self.iconSize / 2, width: Self.iconSize, height: Self.iconSize),
                       from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            textLeft += Self.iconSize + 6
        }
        var textRight = r.maxX - Self.padding
        if showsCloseButton(selected: selected, hover: hover) {
            let c = closeRect(in: r)
            textRight = c.minX - 2
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 9), .foregroundColor: NSColor.secondaryLabelColor]
            let x = "✕" as NSString
            let size = x.size(withAttributes: attrs)
            x.draw(at: NSPoint(x: c.midX - size.width / 2, y: c.midY - size.height / 2), withAttributes: attrs)
        }
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [.font: Self.font, .foregroundColor: NSColor.labelColor, .paragraphStyle: style]
        let height = ceil(Self.font.ascender - Self.font.descender)
        (tab.title as NSString).draw(in: NSRect(x: textLeft, y: r.midY - height / 2, width: max(0, textRight - textLeft), height: height),
                                     withAttributes: attrs)
    }

    private func showsCloseButton(selected: Bool, hover: Bool) -> Bool {
        settings.closeButton == 1 || (settings.closeButton == 2 && (selected || hover))
    }

    private func closeRect(in tabRect: NSRect) -> NSRect {
        NSRect(x: tabRect.maxX - Self.closeButtonSize - 4, y: tabRect.midY - Self.closeButtonSize / 2,
               width: Self.closeButtonSize, height: Self.closeButtonSize)
    }

    // MARK: - マウス

    func tabIndex(at point: NSPoint) -> Int? {
        tabRects.firstIndex { $0.contains(point) }
    }

    override func mouseMoved(with event: NSEvent) {
        let index = tabIndex(at: convert(event.locationInWindow, from: nil))
        if index != hoverIndex {
            hoverIndex = index
            needsDisplay = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        hoverIndex = nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let index = tabIndex(at: point), index < tabs.count else {
            super.mouseDown(with: event)
            return
        }
        let tab = tabs[index]
        if showsCloseButton(selected: tab.id == selectedID, hover: true), closeRect(in: tabRects[index]).contains(point) {
            onClose?(tab.id)
            return
        }
        onSelect?(tab.id)
    }

    override func otherMouseDown(with event: NSEvent) {
        // 中ボタン：タブを閉じる（原版 OnTabMButtonUp）
        if event.buttonNumber == 2, let index = tabIndex(at: convert(event.locationInWindow, from: nil)), index < tabs.count {
            onClose?(tabs[index].id)
            return
        }
        super.otherMouseDown(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        // マウスホイールでウィンドウ切替（原版 m_bChgWndByWheel）
        guard settings.wheelSwitch, !tabs.isEmpty, event.scrollingDeltaY != 0,
              let current = tabs.firstIndex(where: { $0.id == selectedID }) else {
            super.scrollWheel(with: event)
            return
        }
        let next = (current + (event.scrollingDeltaY < 0 ? 1 : -1) + tabs.count) % tabs.count
        onSelect?(tabs[next].id)
    }

    /// タブ一覧（原版 TabListMenu。左クリックはタブ名、右クリックはパス名）
    @objc private func showList(_ sender: Any?) {
        let paths = NSApp.currentEvent?.type == .rightMouseDown
        showListMenu(paths: paths)
    }

    override func rightMouseDown(with event: NSEvent) {
        if listButton.frame.contains(convert(event.locationInWindow, from: nil)) {
            showListMenu(paths: true)
            return
        }
        super.rightMouseDown(with: event)
    }

    func listMenu(paths: Bool) -> NSMenu {
        let menu = NSMenu()
        var entries = tabs
        if EditorCore.commonSetting(section: "Common", key: "bSortTabList") == "1" {
            entries.sort { ($0.title as NSString).localizedStandardCompare($1.title) == .orderedAscending }
        }
        for tab in entries {
            let title = paths && !tab.path.isEmpty ? tab.path : tab.title
            let item = NSMenuItem(title: title, action: #selector(listItemChosen(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = tab.id
            item.state = tab.id == selectedID ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    private func showListMenu(paths: Bool) {
        listMenu(paths: paths).popUp(positioning: nil, at: NSPoint(x: listButton.frame.minX, y: listButton.frame.maxY), in: self)
    }

    @objc private func listItemChosen(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? ObjectIdentifier { onSelect?(id) }
    }

    @objc private func closeCurrent(_ sender: Any?) {
        if let selectedID { onClose?(selectedID) }
    }

    // MARK: - アクセシビリティ（UI テスト：タブ 1 つずつをボタンとして）

    override func accessibilityChildren() -> [Any]? {
        var children: [Any] = [listButton, closeButton]
        for (i, tab) in tabs.enumerated() where i < tabRects.count {
            let element = NSAccessibilityElement()
            element.setAccessibilityRole(.radioButton)
            element.setAccessibilityParent(self)
            element.setAccessibilityLabel(tab.title)
            element.setAccessibilityIdentifier("tabBar.tab.\(i)")
            element.setAccessibilityFrameInParentSpace(tabRects[i])
            element.setAccessibilityValue(tab.id == selectedID ? 1 : 0)
            children.append(element)
        }
        return children
    }
}

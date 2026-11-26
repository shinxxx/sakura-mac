// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge

/// アウトライン解析のドッキング（第 42 步第 3 个 PR。原版 CDlgFuncList のドッキング部分、CEditWnd::EndLayoutBars）。
///
/// 原版はアウトライン解析の対話框を編集窓口の子窓口にして、上・下・左・右に置く（キャプションと分割バーは非クライアント領域に自分で描く）。
/// Mac 版は編集窓口の中身を EditorContainerView にして、編集画面とドッキングした OutlineDockView を並べる。
/// 配置の設定は共通設定か、タイプ別設定（「ドッキング配置をタイプ別継承」）：sakura.ini の項目は原版と同じ。

// MARK: - 配置

/// ドッキング配置（原版 EDockSide。数値も同じ）
enum DockSide: Int {
    case undockable = -1	// ドッキング禁止
    case float = 0			// フローティング
    case left = 1
    case top = 2
    case right = 3
    case bottom = 4

    var isDocking: Bool { rawValue > DockSide.float.rawValue }
    var isHorizontal: Bool { self == .left || self == .right }
}

/// ドッキング配置の設定（原版 ProfDockSet・ProfDockSync・ProfDockDisp・ProfDockSide・ProfDockLeft 等）
enum OutlineDockSettings {
    /// 分割バーの幅（原版 DOCK_SPLITTER_WIDTH）
    static let splitterWidth: CGFloat = 5
    /// ドッキングの最小の幅・高さ（原版 DOCK_MIN_SIZE）
    static let minSize: CGFloat = 60

    static func common(_ key: String) -> String? { EditorCore.commonSetting(section: "Common", key: key) }

    /// ドッキング配置をタイプ別継承（nOutlineDockSet：0 共通、1 タイプ別）
    static var useType: Bool {
        get { (common("nOutlineDockSet") ?? "0") != "0" }
        set { _ = EditorCore.setCommonSetting(newValue ? "1" : "0", section: "Common", key: "nOutlineDockSet") }
    }

    /// ドッキング配置を同期（bOutlineDockSync）
    static var sync: Bool {
        get { (common("bOutlineDockSync") ?? "0") != "0" }
        set { _ = EditorCore.setCommonSetting(newValue ? "1" : "0", section: "Common", key: "bOutlineDockSync") }
    }

    /// 設定の節：共通設定か、このタイプ
    static func section(typeIndex: Int) -> String {
        useType ? "Types(\(typeIndex))" : "Common"
    }

    static func value(_ key: String, typeIndex: Int) -> String? {
        EditorCore.commonSetting(section: section(typeIndex: typeIndex), key: key)
    }

    static func set(_ values: [String: String], typeIndex: Int) {
        _ = EditorCore.setCommonSettings(values, section: section(typeIndex: typeIndex))
    }

    /// アウトライン解析表示の有無（bOutlineDockDisp）
    static func display(typeIndex: Int) -> Bool {
        (value("bOutlineDockDisp", typeIndex: typeIndex) ?? "0") != "0"
    }

    static func setDisplay(_ on: Bool, typeIndex: Int) {
        set(["bOutlineDockDisp": on ? "1" : "0"], typeIndex: typeIndex)
    }

    /// ドッキング配置（eOutlineDockSide）
    static func side(typeIndex: Int) -> DockSide {
        DockSide(rawValue: Int(value("eOutlineDockSide", typeIndex: typeIndex) ?? "") ?? 0) ?? .float
    }

    /// ドッキングの幅・高さ（xyOutlineDock：左の幅、上の高さ、右の幅、下の高さ）。0 は未設定
    static func sizes(typeIndex: Int) -> [Int] {
        let parts = (value("xyOutlineDock", typeIndex: typeIndex) ?? "").split(separator: ",").map { Int($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
        return parts.count == 4 ? parts : [0, 0, 0, 0]
    }

    static func size(_ side: DockSide, typeIndex: Int) -> Int {
        let s = sizes(typeIndex: typeIndex)
        switch side {
        case .left: return s[0]
        case .top: return s[1]
        case .right: return s[2]
        case .bottom: return s[3]
        default: return 0
        }
    }

    static func xyValue(_ sizes: [Int]) -> String {
        sizes.map(String.init).joined(separator: ",")
    }

    static func setSize(_ size: Int, for side: DockSide, typeIndex: Int) {
        var s = sizes(typeIndex: typeIndex)
        switch side {
        case .left: s[0] = size
        case .top: s[1] = size
        case .right: s[2] = size
        case .bottom: s[3] = size
        default: return
        }
        set(["xyOutlineDock": xyValue(s)], typeIndex: typeIndex)
    }

    /// 最後に開いていたアウトラインの種類（nDockOutline：ブックマーク一覧か、アウトライン解析か）
    static func dockOutline(typeIndex: Int) -> Int {
        Int(value("nDockOutline", typeIndex: typeIndex) ?? "") ?? OutlineType.default.rawValue
    }

    static func setDockOutline(_ type: Int, typeIndex: Int) {
        set(["nDockOutline": String(type)], typeIndex: typeIndex)
    }

    /// 初回は 1/3、ドッキング場所から最小の大きさを残す（原版 CDockStretch::GetIdealStretch）
    static func idealStretch(_ stretch: CGFloat, max: CGFloat) -> CGFloat {
        var s = stretch == 0 ? (max / 3).rounded(.down) : stretch
        if s > max - minSize { s = max - minSize }
        if s < minSize { s = minSize }
        return s
    }
}

// MARK: - 編集窓口の中身

/// 編集画面とドッキングしたアウトラインを並べる（原版 CEditWnd::EndLayoutBars：ドッキングの場所を除いた残りが編集画面）
final class EditorContainerView: NSView {
    let editor: NSView
    /// ドッキングしたアウトライン（nil はなし）
    var dock: OutlineDockView? {
        didSet {
            if oldValue !== dock { oldValue?.removeFromSuperview() }
            if let dock, dock.superview !== self { addSubview(dock) }
            arrange()
            needsLayout = true
        }
    }

    init(editor: NSView) {
        self.editor = editor
        super.init(frame: editor.frame)
        addSubview(editor)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool { true }

    /// 大きさが変わったらすぐに並べ直す（表示の前でも編集画面の大きさが正しいように）
    override func resizeSubviews(withOldSize oldSize: NSSize) {
        arrange()
    }

    override func layout() {
        super.layout()
        arrange()
    }

    func arrange() {
        let bounds = self.bounds
        guard let dock, dock.side.isDocking else {
            editor.frame = bounds
            return
        }
        // 分割バーを含む幅・高さ。ドッキング場所から最小の大きさを残す
        let total = dock.side.isHorizontal ? bounds.width : bounds.height
        var size = min(dock.size, total - OutlineDockSettings.minSize)
        size = max(size, min(OutlineDockSettings.minSize, total))
        var dockFrame = bounds, editorFrame = bounds
        switch dock.side {
        case .left:
            dockFrame.size.width = size
            editorFrame.origin.x = size
            editorFrame.size.width = bounds.width - size
        case .right:
            dockFrame.origin.x = bounds.width - size
            dockFrame.size.width = size
            editorFrame.size.width = bounds.width - size
        case .top:
            dockFrame.size.height = size
            editorFrame.origin.y = size
            editorFrame.size.height = bounds.height - size
        case .bottom:
            dockFrame.origin.y = bounds.height - size
            dockFrame.size.height = size
            editorFrame.size.height = bounds.height - size
        default:
            break
        }
        dock.frame = dockFrame
        editor.frame = editorFrame
    }

    /// ドッキングの場所（原版 GetDockSpaceRect：編集画面とアウトラインを合わせた範囲。画面の座標）
    var dockSpaceOnScreen: NSRect {
        guard let window else { return .zero }
        return window.convertToScreen(convert(bounds, to: nil))
    }
}

// MARK: - ドッキングしたアウトライン

/// ドッキングしたアウトライン：キャプション（タイトル、更新・メニュー・閉じるのボタン）、分割バー、対話框の中身
final class OutlineDockView: NSView {
    weak var controller: OutlineWindowController?
    var side: DockSide { didSet { needsLayout = true; needsDisplay = true } }
    /// 分割バーを含む幅（左右）または高さ（上下）
    var size: CGFloat
    let caption = OutlineDockCaption()
    let content: NSView

    /// キャプションの高さ（原版 SM_CYSMCAPTION + 1）
    static let captionHeight: CGFloat = 20

    init(content: NSView, side: DockSide, size: CGFloat, controller: OutlineWindowController) {
        self.content = content
        self.side = side
        self.size = size
        self.controller = controller
        super.init(frame: .zero)
        caption.dockView = self
        addSubview(caption)
        addSubview(content)
        setAccessibilityIdentifier("outlineDock")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool { true }

    /// 分割バーの場所（原版 HitTestSplitter）
    var splitterRect: NSRect {
        let w = OutlineDockSettings.splitterWidth
        switch side {
        case .left: return NSRect(x: bounds.width - w, y: 0, width: w, height: bounds.height)
        case .right: return NSRect(x: 0, y: 0, width: w, height: bounds.height)
        case .top: return NSRect(x: 0, y: bounds.height - w, width: bounds.width, height: w)
        case .bottom: return NSRect(x: 0, y: 0, width: bounds.width, height: w)
        default: return .zero
        }
    }

    /// キャプションと分割バーを除いた部分（原版 OnNcCalcSize）
    var clientRect: NSRect {
        var rect = bounds
        let w = OutlineDockSettings.splitterWidth
        switch side {
        case .left: rect.size.width -= w
        case .right: rect.origin.x += w; rect.size.width -= w
        case .top: rect.size.height -= w
        case .bottom: rect.origin.y += w; rect.size.height -= w
        default: break
        }
        rect.origin.y += Self.captionHeight
        rect.size.height -= Self.captionHeight
        return rect
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        layout()
    }

    override func layout() {
        super.layout()
        let client = clientRect
        caption.frame = NSRect(x: client.minX, y: client.minY - Self.captionHeight, width: client.width, height: Self.captionHeight)
        content.frame = client
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        // 分割線（原版 DrawEdge EDGE_ETCHED）
        let s = splitterRect
        NSColor.separatorColor.setFill()
        switch side {
        case .left: NSRect(x: s.minX, y: 0, width: 1, height: s.height).fill()
        case .right: NSRect(x: s.maxX - 1, y: 0, width: 1, height: s.height).fill()
        case .top: NSRect(x: 0, y: s.minY, width: s.width, height: 1).fill()
        case .bottom: NSRect(x: 0, y: s.maxY - 1, width: s.width, height: 1).fill()
        default: break
        }
    }

    override func resetCursorRects() {
        let cursor: NSCursor = side.isHorizontal ? .resizeLeftRight : .resizeUpDown
        addCursorRect(splitterRect, cursor: cursor)
    }

    /// 分割バーのドラッグで大きさを変える（原版 m_bStretching）
    override func mouseDown(with event: NSEvent) {
        let start = convert(event.locationInWindow, from: nil)
        guard splitterRect.insetBy(dx: -1, dy: -1).contains(start), let container = superview as? EditorContainerView else {
            super.mouseDown(with: event)
            return
        }
        let startSize = size
        let startPoint = container.convert(event.locationInWindow, from: nil)
        let total = side.isHorizontal ? container.bounds.width : container.bounds.height
        while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let p = container.convert(next.locationInWindow, from: nil)
            var delta: CGFloat
            switch side {
            case .left: delta = p.x - startPoint.x
            case .right: delta = startPoint.x - p.x
            case .top: delta = p.y - startPoint.y
            default: delta = startPoint.y - p.y
            }
            var newSize = startSize + delta
            newSize = min(newSize, total - OutlineDockSettings.minSize)
            newSize = max(newSize, OutlineDockSettings.minSize)
            size = newSize.rounded()
            container.arrange()
            if next.type == .leftMouseUp { break }
        }
        controller?.dockSizeChanged(size)
    }
}

/// ドッキングのキャプション：タイトルと、右から「閉じる」「ウィンドウの位置」「更新」のボタン（原版 OnNcPaint）。
/// タイトルをドラッグするとドッキング配置を変えられる（原版 Track）
final class OutlineDockCaption: NSView {
    weak var dockView: OutlineDockView?
    let title = PassthroughLabel(labelWithString: "")
    let closeButton: CaptionButton
    let menuButton: CaptionButton
    let updateButton: CaptionButton
    /// アウトラインにフォーカスがある（キャプションの色を変える）
    var isActive = false { didSet { if oldValue != isActive { needsDisplay = true; updateColors() } } }

    override init(frame: NSRect) {
        func button(_ symbol: String, _ tip: String, _ id: String) -> CaptionButton {
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip) ?? NSImage()
            let b = CaptionButton(image: image, target: nil, action: nil)
            b.isBordered = false
            b.bezelStyle = .smallSquare
            b.imageScaling = .scaleProportionallyDown
            b.toolTip = tip
            b.setAccessibilityIdentifier(id)
            b.setAccessibilityLabel(tip)
            return b
        }
        closeButton = button("xmark", NSLocalizedString("閉じる", comment: "STR_DLGFNCLST_TIP_CLOSE"), "outlineDockClose")
        menuButton = button("chevron.down", NSLocalizedString("ウィンドウの位置", comment: "STR_DLGFNCLST_TIP_WIN"), "outlineDockMenu")
        updateButton = button("arrow.clockwise", NSLocalizedString("更新", comment: "STR_DLGFNCLST_TIP_UPDATE"), "outlineDockUpdate")
        super.init(frame: frame)
        title.font = PropPage.font
        title.lineBreakMode = .byTruncatingTail
        title.setAccessibilityIdentifier("outlineDockTitle")
        addSubview(title)
        for b in [closeButton, menuButton, updateButton] {
            b.target = self
            addSubview(b)
        }
        closeButton.action = #selector(closeClicked(_:))
        menuButton.action = #selector(menuClicked(_:))
        updateButton.action = #selector(updateClicked(_:))
        updateColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        // ボタンは右から「閉じる」「ウィンドウの位置」「更新」（原版 SM_CXSMSIZE 幅）
        let h = bounds.height
        let w: CGFloat = 16
        var x = bounds.width - 2
        for b in [closeButton, menuButton, updateButton] {
            x -= w
            b.frame = NSRect(x: x, y: (h - w) / 2, width: w, height: w)
        }
        title.frame = NSRect(x: 4, y: (h - 15) / 2, width: max(0, x - 6), height: 15)
    }

    func updateColors() {
        title.textColor = isActive ? NSColor.selectedMenuItemTextColor : NSColor.labelColor
        for b in [closeButton, menuButton, updateButton] {
            // マウスが上にあるボタンは強調（原版 COLOR_ACTIVECAPTION で塗り、キャプションの文字色）
            b.contentTintColor = isActive || b.isHovered ? NSColor.selectedMenuItemTextColor : NSColor.secondaryLabelColor
            b.needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        // 原版：フォーカスがあるときは強調の色、ないときは背景の色。上に線
        (isActive ? NSColor.controlAccentColor : NSColor.windowBackgroundColor).setFill()
        bounds.fill()
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
    }

    @objc private func closeClicked(_ sender: Any?) { dockView?.controller?.close() }
    @objc private func updateClicked(_ sender: Any?) { dockView?.controller?.reload() }
    @objc private func menuClicked(_ sender: Any?) {
        guard let controller = dockView?.controller else { return }
        controller.makeMenu(dropDown: true).popUp(positioning: nil, at: NSPoint(x: 0, y: menuButton.frame.height), in: menuButton)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        dockView?.controller?.makeMenu(dropDown: false)
    }

    /// タイトルのドラッグ（原版 OnNcLButtonDown → Track）
    override func mouseDown(with event: NSEvent) {
        dockView?.controller?.track(from: event)
    }
}

// MARK: - ドロップ先の枠（原版 CGraphics::DrawDropRect）

/// ドラッグ中のドロップ先を示す枠（フローティングは太く、ドッキングは細く）
final class DropRectWindow: NSWindow {
    private let frameView = DropRectView()

    init() {
        super.init(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = true
        level = .floating
        hasShadow = false
        contentView = frameView
    }

    func show(_ rect: NSRect, thickness: CGFloat) {
        frameView.thickness = thickness
        setFrame(rect, display: true)
        frameView.needsDisplay = true
        orderFront(nil)
    }
}

final class DropRectView: NSView {
    var thickness: CGFloat = 4

    override func draw(_ dirtyRect: NSRect) {
        NSColor.selectedContentBackgroundColor.withAlphaComponent(0.8).setStroke()
        let path = NSBezierPath(rect: bounds.insetBy(dx: thickness / 2, dy: thickness / 2))
        path.lineWidth = thickness
        path.stroke()
    }
}

// MARK: - アウトライン解析の窓口のドッキング部分

extension OutlineWindowController {
    /// 編集窓口の中身（ドッキングする場所）
    var container: EditorContainerView? {
        var v: NSView? = view
        while let current = v {
            if let c = current as? EditorContainerView { return c }
            v = current.superview
        }
        return nil
    }

    /// ドッキング用にする（原版 OnInitDialog：キャプション・分割バー以外の不要なコントロールを隠し、ツリー・リストは下・右いっぱい）
    func setUpDocking() {
        let keep: Set<String> = ["IDC_STATIC_nSortType", "IDC_COMBO_nSortType", "IDC_LIST_FL", "IDC_TREE_FL"]
        for control in page.definition.controls where control.id != "IDC_STATIC" && !keep.contains(control.id) {
            page.control(control.id)?.isHidden = true
        }
        let bounds = page.view.bounds
        for id in ["IDC_TREE_FL", "IDC_LIST_FL"] {
            guard let v = page.control(id) else { continue }
            v.frame = NSRect(x: v.frame.minX, y: v.frame.minY, width: bounds.width - v.frame.minX, height: bounds.height - v.frame.minY)
        }
        // シングルクリックでジャンプ（原版 NM_CLICK：ドッキングのとき）
        treeView.action = #selector(OutlineTreeView.singleClicked(_:))
        listView.action = #selector(OutlineListView.singleClicked(_:))
        let size = CGFloat(OutlineDockSettings.size(dockSide, typeIndex: view?.document.typeIndex ?? 0))
        dockView = OutlineDockView(content: page.view, side: dockSide, size: size, controller: self)
        NotificationCenter.default.addObserver(self, selector: #selector(focusChanged(_:)),
                                               name: NSWindow.didUpdateNotification, object: nil)
    }

    /// 編集窓口の中に置く
    func showDocked(focus: Bool) {
        guard let dockView, let container else { return }
        if dockView.size == 0 {
            let total = dockSide.isHorizontal ? container.bounds.width : container.bounds.height
            dockView.size = OutlineDockSettings.idealStretch(0, max: total)
        }
        if container.dock !== dockView { container.dock = dockView }
        if focus {
            container.window?.makeFirstResponder(result.isTree ? treeView : listView)
        }
        updateCaption()
    }

    /// キャプションの色（フォーカスがあるときは強調。原版 OnNcPaint の bActive）
    @objc func focusChanged(_ notification: Notification) {
        updateCaption()
    }

    func updateCaption() {
        guard let dockView else { return }
        let responder = dockView.window?.firstResponder as? NSView
        dockView.caption.isActive = dockView.window?.isKeyWindow == true && responder?.isDescendant(of: dockView) == true
    }

    /// ドッキングのとき、ツリー・リストの色は編集画面の文字の色（原版 SyncColor）
    func syncColor() {
        guard isDocking, let view else {
            treeView.textColor = nil
            listView.textColor = nil
            return
        }
        let text = view.color(.text)
        let fore = EditorTextView.nsColor(text.text), back = EditorTextView.nsColor(text.back)
        treeView.backgroundColor = back
        listView.backgroundColor = back
        treeView.textColor = fore
        listView.textColor = fore
    }

    /// ドッキングのときのシングルクリック（原版 NM_CLICK → OnJump(false, false)）
    @objc func singleClicked() {
        guard isDocking else { return }
        jump(checkAutoClose: false)
    }

    /// 分割バーで大きさを変えた（原版 OnLButtonUp：同期ならほかの窓口へ通知）
    func dockSizeChanged(_ size: CGFloat) {
        guard let dockView, let container else { return }
        let total = dockSide.isHorizontal ? container.bounds.width : container.bounds.height
        let clamped = max(OutlineDockSettings.minSize, min(size, total - OutlineDockSettings.minSize)).rounded()
        dockView.size = clamped
        container.arrange()
        OutlineDockSettings.setSize(Int(clamped), for: dockSide, typeIndex: view?.document.typeIndex ?? 0)
        if OutlineDockSettings.sync { view?.notifyOutlineToOthers() }
    }

    func setDockSize(_ size: CGFloat) {
        dockView?.size = size
        container?.arrange()
    }

    // MARK: メニュー（原版 DoMenu）

    /// ドッキング配置を選んだ（原版 nId >= 100 - 1）
    @objc func menuDockSide(_ sender: NSMenuItem) {
        guard let side = DockSide(rawValue: sender.tag) else { return }
        applyDockSide(side, size: nil)
    }

    /// 新しい配置を設定して、自分を配置し直す。size はドロップした大きさ（nil は記憶した大きさ・初回は 1/3）
    func applyDockSide(_ side: DockSide, size: CGFloat?) {
        guard let view else { return }
        let typeIndex = view.document.typeIndex
        if side.isDocking, let container {
            let total = side.isHorizontal ? container.bounds.width : container.bounds.height
            let stretch = size ?? CGFloat(OutlineDockSettings.size(side, typeIndex: typeIndex))
            OutlineDockSettings.setSize(Int(OutlineDockSettings.idealStretch(stretch, max: total)), for: side, typeIndex: typeIndex)
        }
        OutlineDockSettings.set(["bOutlineDockDisp": isOpen ? "1" : "0", "eOutlineDockSide": String(side.rawValue)], typeIndex: typeIndex)
        view.changeOutlineLayout(.foreground)
        if OutlineDockSettings.sync { view.notifyOutlineToOthers() }
    }

    /// ドッキング配置を同期（原版 nId == 200）
    @objc func menuSync(_ sender: NSMenuItem) {
        OutlineDockSettings.sync.toggle()
        view?.changeOutlineLayout(.foreground)
        if OutlineDockSettings.sync { view?.notifyOutlineToOthers() }
    }

    /// ドッキング配置の継承方法（原版 nId == 300, 301）
    @objc func menuInherit(_ sender: NSMenuItem) {
        OutlineDockSettings.useType = sender.tag != 0
        view?.changeOutlineLayout(.foreground)
        if OutlineDockSettings.sync { view?.notifyOutlineToOthers() }
    }

    /// 継承情報を統一（原版 nId == 305）：今の画面の配置を共通設定とすべてのタイプ別設定にコピー
    @objc func menuUnify(_ sender: NSMenuItem) {
        guard let view else { return }
        let message = NSLocalizedString("現在の画面のドッキング配置情報をすべての共通設定・タイプ別設定にコピーして統一します。\n（現在開いている他画面の状態も統一します。）\n",
                                        comment: "STR_DLGFNCLST_UNIFY")
        let ok: Bool
        if let handler = Self.confirmHandler {
            ok = handler(message)
        } else {
            let alert = NSAlert()
            alert.messageText = message
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: NSLocalizedString("キャンセル", comment: "cancel"))
            ok = alert.runModal() == .alertFirstButtonReturn
        }
        guard ok else { return }
        var sizes = OutlineDockSettings.sizes(typeIndex: view.document.typeIndex)
        let side = dockSide
        if isOpen, let dockView {
            switch side {
            case .left: sizes[0] = Int(dockView.size)
            case .top: sizes[1] = Int(dockView.size)
            case .right: sizes[2] = Int(dockView.size)
            case .bottom: sizes[3] = Int(dockView.size)
            default: break
            }
        }
        let values = ["bOutlineDockDisp": isOpen ? "1" : "0", "eOutlineDockSide": String(side.rawValue),
                      "xyOutlineDock": OutlineDockSettings.xyValue(sizes)]
        _ = EditorCore.setCommonSettings(values, section: "Common")
        for type in EditorCore.typeSettings {
            _ = EditorCore.setCommonSettings(values, section: "Types(\(type.index))")
        }
        view.changeOutlineLayout(.foreground)
        view.notifyOutlineToOthers()
    }

    // MARK: ドラッグでドッキング配置を変える（原版 Track、GetDropRect）

    /// ドロップ先（原版 GetDropRect）。画面の座標（左下が原点）
    func dropRect(dragStart: NSPoint, drop: NSPoint, forceFloat: Bool) -> (DockSide, NSRect) {
        guard let container, let view else { return (.float, .zero) }
        let typeIndex = view.document.typeIndex
        // 移動しない（ドッキング中に自分の上）
        if isDocking && !forceFloat, let dockView, let window = dockView.window {
            let rect = window.convertToScreen(dockView.convert(dockView.bounds, to: nil))
            if rect.contains(drop) { return (dockSide, rect) }
        }
        var dock = container.dockSpaceOnScreen
        if !forceFloat && dock.contains(drop) {
            let margin: CGFloat = 32	// 原版 SM_CXCURSOR
            func ideal(_ side: DockSide, _ max: CGFloat) -> CGFloat {
                OutlineDockSettings.idealStretch(CGFloat(OutlineDockSettings.size(side, typeIndex: typeIndex)), max: max)
            }
            if drop.x - dock.minX < margin {
                dock.size.width = ideal(.left, dock.width)
                return (.left, dock)
            } else if dock.maxX - drop.x < margin {
                let w = ideal(.right, dock.width)
                dock.origin.x = dock.maxX - w
                dock.size.width = w
                return (.right, dock)
            } else if dock.maxY - drop.y < margin {
                let h = ideal(.top, dock.height)
                dock.origin.y = dock.maxY - h
                dock.size.height = h
                return (.top, dock)
            } else if drop.y - dock.minY < margin {
                dock.size.height = ideal(.bottom, dock.height)
                return (.bottom, dock)
            }
        }
        // フローティング
        if !isDocking, let panel = window {
            return (.float, panel.frame.offsetBy(dx: drop.x - dragStart.x, dy: drop.y - dragStart.y))
        }
        var size = floatingSize
        size.width = max(size.width, 100)
        let caption: CGFloat = 22
        return (.float, NSRect(x: drop.x - caption * 2, y: drop.y + caption / 2 - size.height, width: size.width, height: size.height))
    }

    /// フローティングにしたときの大きさ：記憶した大きさ、ないときは対話框の大きさ
    var floatingSize: NSSize {
        if Self.commonBool("bRememberOutlineWindowPos"),
           let w = Int(EditorCore.commonSetting(section: "Common", key: "widthOutlineWindow") ?? ""),
           let h = Int(EditorCore.commonSetting(section: "Common", key: "heightOutlineWindow") ?? ""), w > 0, h > 0 {
            return NSSize(width: w, height: h)
        }
        let content = NSSize(width: PropPage.pointsX(page.definition.size[0]), height: PropPage.points(page.definition.size[1]))
        return NSWindow.frameRect(forContentRect: NSRect(origin: .zero, size: content), styleMask: [.titled, .closable, .resizable]).size
    }

    /// ドロップ先を決めて配置を変える
    func drop(side: DockSide, rect: NSRect) {
        let size: CGFloat? = side.isDocking ? (side.isHorizontal ? rect.width : rect.height) : nil
        let wasDocking = isDocking
        applyDockSide(side, size: size)
        // フローティングになった窓口はドロップした場所に
        if !side.isDocking, let panel = view?.outlinePanel?.window, panel.isVisible {
            panel.setFrame(rect, display: true)
        }
        _ = wasDocking
    }

    /// ドッキングのキャプションのドラッグ（原版 Track）。Ctrl を押している間はフローティングに、Esc・右クリックでやめる
    func track(from event: NSEvent) {
        guard let window = dockView?.window else { return }
        let start = NSEvent.mouseLocation
        var dragging = false
        let overlay = DropRectWindow()
        defer { overlay.orderOut(nil) }
        var last: (DockSide, NSRect)?
        func update(_ point: NSPoint, _ flags: NSEvent.ModifierFlags) {
            let result = dropRect(dragStart: start, drop: point, forceFloat: flags.contains(.control))
            last = result
            overlay.show(result.1, thickness: result.0.isDocking ? 4 : 8)
        }
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp, .keyDown, .flagsChanged, .rightMouseDown]) {
            switch next.type {
            case .leftMouseDragged:
                let p = NSEvent.mouseLocation
                if !dragging && (abs(p.x - start.x) >= 4 || abs(p.y - start.y) >= 4) { dragging = true }
                if dragging { update(p, next.modifierFlags) }
            case .flagsChanged:
                if dragging { update(NSEvent.mouseLocation, next.modifierFlags) }
            case .keyDown:
                if next.keyCode == 53 { return }	// Esc：やめる
            case .rightMouseDown:
                return
            case .leftMouseUp:
                guard dragging else { return }
                overlay.orderOut(nil)
                let result = dropRect(dragStart: start, drop: NSEvent.mouseLocation, forceFloat: next.modifierFlags.contains(.control))
                if result.0 != dockSide || !isDocking || result.1 != last?.1 { drop(side: result.0, rect: result.1) }
                return
            default:
                break
            }
        }
    }

    // MARK: フローティングの窓口のドラッグ（原版：タイトルバーのドラッグでもドッキングできる）

    /// タイトルバーでドラッグを始めた：ボタンを離すまでドロップ先の枠を出し、編集窓口の端で離したらドッキング
    func windowWillMove(_ notification: Notification) {
        guard dockSide == .float, let view, !view.outlineChangingLayout else { return }
        let start = NSEvent.mouseLocation
        let overlay = DropRectWindow()
        var last: (DockSide, NSRect)?
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
            guard let self, !self.destroyed else {
                timer.invalidate()
                overlay.orderOut(nil)
                return
            }
            let p = NSEvent.mouseLocation
            if NSEvent.pressedMouseButtons & 1 == 0 {
                timer.invalidate()
                overlay.orderOut(nil)
                // ドロップ先は離した場所で決める（原版と同じ）。前回の 0.05 秒ごとの結果を使うと、
                // 速いドラッグでは最後の位置を取る前にボタンが離され、端で離してもドッキングしなかった
                let result = self.dropRect(dragStart: start, drop: p, forceFloat: NSEvent.modifierFlags.contains(.control))
                if result.0.isDocking { self.drop(side: result.0, rect: result.1) }
                _ = last
                return
            }
            let result = self.dropRect(dragStart: start, drop: p, forceFloat: NSEvent.modifierFlags.contains(.control))
            last = result
            if result.0.isDocking {
                overlay.show(result.1, thickness: 4)
            } else {
                overlay.orderOut(nil)	// フローティングは窓口そのものが動く
            }
        }
    }
}

// MARK: - 編集画面側（原版 ChangeLayout、Refresh、PostOutlineNotifyToAllEditors）

/// ChangeLayout の動作（原版 OUTLINE_LAYOUT_FOREGROUND 等）
enum OutlineLayoutMode {
    case foreground		// 自分自身への変更
    case background		// ほかの窓口からの通知
    case fileChanged	// ファイルを開いた・タイプが変わった
}

extension EditorTextView {
    /// 再解析の種別（原版 GetOutlineTypeRedraw：ブックマーク一覧か、アウトライン解析か）
    private func redrawType(_ type: Int) -> OutlineType {
        type == OutlineType.bookmark.rawValue ? .bookmark : .default
    }

    /// 今の設定に合わせてアウトラインを配置し直す（原版 ChangeLayout）。解析したら true
    @discardableResult
    func changeOutlineLayout(_ mode: OutlineLayoutMode) -> Bool {
        outlineChangingLayout = true
        defer { outlineChangingLayout = false }
        let typeIndex = document.typeIndex
        let display = OutlineDockSettings.display(typeIndex: typeIndex)
        let sideNew = OutlineDockSettings.side(typeIndex: typeIndex)
        guard let panel = outlinePanel, panel.isOpen else {
            guard display else { return false }
            // 裏・ファイル切替ではフローティングは開かない（従来互換）
            if !sideNew.isDocking && mode != .foreground { return false }
            outlineCommand(action: .normal, type: redrawType(OutlineDockSettings.dockOutline(typeIndex: typeIndex)), focus: mode == .foreground)
            return true
        }
        let sideOld = panel.dockSide
        if !display {
            if !sideOld.isDocking {
                if mode == .background { return false }
                if mode == .fileChanged && !sideNew.isDocking { return false }
            }
            panel.close()
            return false
        }
        // ドッキング⇔フローティングは閉じて開く
        if sideOld.isDocking != sideNew.isDocking {
            let type = redrawType(panel.outlineType.rawValue)
            panel.close()
            if !sideNew.isDocking && mode != .foreground { return false }
            outlineCommand(action: .normal, type: type, focus: mode == .foreground)
            return true
        }
        // フローティング→フローティングは現状維持
        if !sideOld.isDocking {
            panel.setDockSideWithoutLayout(sideNew)
            return false
        }
        // ドッキング→ドッキングは配置を合わせる
        panel.setDockSideWithoutLayout(sideNew)
        panel.dockView?.side = sideNew
        let size = CGFloat(OutlineDockSettings.size(sideNew, typeIndex: typeIndex))
        if let container = panel.container {
            let total = sideNew.isHorizontal ? container.bounds.width : container.bounds.height
            panel.setDockSize(OutlineDockSettings.idealStretch(size, max: total))
        }
        return false
    }

    /// ファイルを開いた・タイプが変わった（原版 Refresh）：配置し直して、開いていれば再解析
    func refreshOutline() {
        let analyzed = changeOutlineLayout(.fileChanged)
        if !analyzed, let panel = outlinePanel, panel.isOpen {
            outlineCommand(action: .reload, type: redrawType(panel.outlineType.rawValue), focus: false)
        }
    }

    /// ほかの編集窓口へ配置の変更を通知（原版 PostOutlineNotifyToAllEditors → OnOutlineNotify）
    func notifyOutlineToOthers() {
        for window in NSApp.windows {
            for view in Self.editorViews(in: window.contentView) where view !== self {
                view.changeOutlineLayout(.background)
            }
        }
    }

    private static func editorViews(in view: NSView?) -> [EditorTextView] {
        guard let view else { return [] }
        if let editor = view as? EditorTextView { return [editor] }
        return view.subviews.flatMap { editorViews(in: $0) }
    }
}

/// クリックを下（キャプション）に通す文字（タイトルのドラッグ）
final class PassthroughLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// キャプションのボタン：マウスが上にあるときは強調の色で塗る（原版 OnNcPaint のハイライト）
final class CaptionButton: NSButton {
    private(set) var isHovered = false {
        didSet { if oldValue != isHovered { (superview as? OutlineDockCaption)?.updateColors() } }
    }
    private var trackingArea: NSTrackingArea?

    /// ハイライトの色（キャプションが強調の色のときは少し濃く）
    var hoverColor: NSColor {
        let active = (superview as? OutlineDockCaption)?.isActive ?? false
        return active ? NSColor.controlAccentColor.blended(withFraction: 0.35, of: .black) ?? .controlAccentColor : .controlAccentColor
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func draw(_ dirtyRect: NSRect) {
        if isHovered {
            hoverColor.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 3, yRadius: 3).fill()
        }
        super.draw(dirtyRect)
    }
}

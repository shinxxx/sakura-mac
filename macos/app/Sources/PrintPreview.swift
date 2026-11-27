// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import CoreText
import EditorBridge

// MARK: - ページの描画

/// 印刷・印刷プレビューのページを描く（第 47 步。原版 CPrintPreview::DrawPageText・Print_DrawBlock・DrawHeaderFooter）。
///
/// 排版（文字の位置・送り幅・折り返し・行番号・ヘッダー・フッター）は核心库（PrintLayout）が原版と同じ計算でする。
/// ここは描くだけ：座標は 1/10 mm、用紙の左上から下向き。呼ぶ前に context を下向き・1 単位 = 1/10 mm にしておく。
/// フォントの大きさは原版の lfHeight と同じ（フォント高 = 1/10 mm の単位でのフォントの大きさ。文字幅のキャッシュも同じ大きさで測る）
final class PrintPageRenderer {
    let layout: PrintLayout
    /// 縦線の太さ（1/10 mm）。プレビューは画面の 1 ドット、印刷は 0.1 mm
    var hairline: CGFloat = 1
    /// 線・枠のアンチエイリアス（原版の「滑らか」）。文字はいつもアンチエイリアス
    var smoothLines = false
    private var fonts: [String: CTFont] = [:]

    init(layout: PrintLayout) {
        self.layout = layout
    }

    /// 印刷のフォント（Windows のフォント名を Mac のフォントにする。PrintCore.macFontFace）
    func font(_ face: String, size: CGFloat, bold: Bool = false, italic: Bool = false) -> CTFont {
        let key = "\(face)\u{0}\(size)\u{0}\(bold)\u{0}\(italic)"
        if let font = fonts[key] { return font }
        let font = PrintCore.font(named: face, size: size, bold: bold, italic: italic)
        fonts[key] = font
        return font
    }

    /// 本文のフォント（半角・全角）。大きさはフォント高
    func textFont(zen: Bool, bold: Bool) -> CTFont {
        let setting = layout.setting
        return font(zen ? setting.fontZen : setting.fontHan, size: CGFloat(setting.fontHeight), bold: bold)
    }

    /// 1 ページ（ヘッダー・本文・フッター）を描く
    func draw(_ page: PrintPage, in context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }
        // 下向きの座標なので文字は上下を返す
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        for run in page.runs where !run.text.isEmpty {
            drawRun(run, in: context)
        }
        for text in page.alignedTexts {
            drawAligned(text, in: context)
        }
        if !page.rules.isEmpty {
            context.setShouldAntialias(smoothLines)
            context.setStrokeColor(CGColor(gray: 0, alpha: 1))
            context.setLineWidth(hairline)
            for rule in page.rules {
                // 原版 ::MoveToEx・::LineTo（行番号の区切り線）
                let x = CGFloat(rule.x) + hairline / 2
                context.move(to: CGPoint(x: x, y: CGFloat(rule.top)))
                context.addLine(to: CGPoint(x: x, y: CGFloat(rule.bottom)))
            }
            context.strokePath()
            context.setShouldAntialias(true)
        }
    }

    /// 色
    static func color(_ rgb: UInt32) -> CGColor {
        CGColor(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }

    /// 文字の並び一つ（原版 Print_DrawBlock の ::ExtTextOut：一文字ずつ送り幅 dx の位置に置く）
    private func drawRun(_ run: PrintRun, in context: CGContext) {
        let font = textFont(zen: run.zen, bold: run.bold)
        // 太字がないフォント（ヒラギノ明朝等）は原版の GDI と同じように太らせる
        let fakeBold = run.bold && !CTFontGetSymbolicTraits(font).contains(.traitBold)
        let color = Self.color(run.color)
        context.setFillColor(color)
        let units = Array(run.text.utf16)
        let dx = run.dx.map { CGFloat($0.intValue) }
        var x = CGFloat(run.x)
        let baseline = CGFloat(run.baseline)
        var start = x
        // フォントごとにまとめて描く（ないグリフは代わりのフォント。原版のフォントリンク）
        var batches: [(CTFont, [CGGlyph], [CGPoint])] = []
        var index = 0
        while index < units.count {
            let count = UTF16.isLeadSurrogate(units[index]) && index + 1 < units.count && UTF16.isTrailSurrogate(units[index + 1]) ? 2 : 1
            let advance = (index ..< index + count).reduce(CGFloat(0)) { $0 + (dx.indices.contains($1) ? dx[$1] : 0) }
            if !run.tab, let (glyphFont, glyph) = glyph(for: Array(units[index ..< index + count]), font: font) {
                if let last = batches.indices.last, CFEqual(batches[last].0, glyphFont) {
                    batches[last].1.append(glyph)
                    batches[last].2.append(CGPoint(x: x, y: baseline))
                } else {
                    batches.append((glyphFont, [glyph], [CGPoint(x: x, y: baseline)]))
                }
            }
            if index == 0 { start = x }
            x += advance
            index += count
        }
        if fakeBold {
            context.setTextDrawingMode(.fillStroke)
            context.setStrokeColor(color)
            context.setLineWidth(CTFontGetSize(font) / 30)
        }
        for (glyphFont, glyphs, positions) in batches {
            // CTFontDrawGlyphs の位置は textMatrix の中の座標：上下を返した分 y も返す
            let flipped = positions.map { CGPoint(x: $0.x, y: -$0.y) }
            context.saveGState()
            context.textMatrix = .identity
            context.scaleBy(x: 1, y: -1)
            CTFontDrawGlyphs(glyphFont, glyphs, flipped, glyphs.count, context)
            context.restoreGState()
        }
        if fakeBold { context.setTextDrawingMode(.fill) }
        if run.underline {
            // 原版は下線付きのフォント（lfUnderline）
            let position = CTFontGetUnderlinePosition(font)
            let thickness = max(CTFontGetUnderlineThickness(font), hairline)
            context.fill(CGRect(x: start, y: baseline - position - thickness / 2, width: x - start, height: thickness))
        }
    }

    /// 文字（サロゲートペアは 2 つ）のグリフ。フォントにないときは代わりのフォント
    private func glyph(for units: [UInt16], font: CTFont) -> (CTFont, CGGlyph)? {
        var glyphs = [CGGlyph](repeating: 0, count: units.count)
        if CTFontGetGlyphsForCharacters(font, units, &glyphs, units.count), glyphs[0] != 0 {
            return (font, glyphs[0])
        }
        let string = String(utf16CodeUnits: units, count: units.count) as CFString
        let fallback = CTFontCreateForString(font, string, CFRange(location: 0, length: units.count))
        if CTFontGetGlyphsForCharacters(fallback, units, &glyphs, units.count), glyphs[0] != 0 {
            return (fallback, glyphs[0])
        }
        return nil
    }

    /// フォント指定のヘッダー・フッター（原版 DrawHeaderFooter の bFontSetting：左・中央・右寄せ）
    private func drawAligned(_ text: PrintAlignedText, in context: CGContext) {
        guard !text.text.isEmpty else { return }
        let setting = text.font
        // 原版 lfHeight = -(ポイント × 254 / 720)：1/10 mm
        let size = CGFloat(setting.pointSize * 254 / 720)
        let font = self.font(setting.faceName, size: max(1, size), bold: setting.bold, italic: setting.italic)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1),
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text.text, attributes: attributes))
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        let x: CGFloat
        switch text.align {
        case 1: x = ((CGFloat(text.right) + CGFloat(text.left) - width) / 2).rounded(.down)
        case 2: x = CGFloat(text.right) - width
        default: x = CGFloat(text.left)
        }
        // ヘッダーは上端に文字の上、フッターは下端に文字の下（原版 nY = rect.top / rect.bottom + tmHeight）
        let baseline = text.footer ? CGFloat(text.top) - CTFontGetDescent(font) : CGFloat(text.top) + CTFontGetAscent(font)
        context.textPosition = CGPoint(x: x, y: baseline)
        CTLineDraw(line, context)
    }
}

// MARK: - 印刷プレビューの表示

/// 印刷プレビューの用紙（原版 CPrintPreview::OnPaint）。
///
/// 灰色の地に、ビューの端から 8 mm 空けて白い用紙（黒の枠）、余白の枠（灰色）、ヘッダー・本文・フッター。
/// 倍率 100% は原版と同じ大きさ（Windows の画面 96 dpi：1/10 mm = 96 / 254 ドット）。
/// 手のカーソルでドラッグするとスクロール（原版 OnMouseMove の SetHandCursor・ドラッグ）
final class PrintPreviewView: NSView {
    /// 原版 m_nPreview_ViewMarginLeft・Top（1/10 mm）
    static let viewMargin = 80
    /// 原版の MM_LOMETRIC：画面 96 dpi で 1/10 mm
    static let unitsToPoints: CGFloat = 96.0 / 254.0
    /// 灰色の地（原版 GRAY_BRUSH）
    static let background = NSColor(calibratedWhite: 128.0 / 255.0, alpha: 1)

    var renderer: PrintPageRenderer? {
        didSet { updateSize() }
    }
    var page: PrintPage? {
        didSet { needsDisplay = true }
    }
    /// 倍率（%）
    var zoom = 100 {
        didSet { updateSize() }
    }
    /// 「滑らか」
    var antialias = false {
        didSet { needsDisplay = true }
    }
    weak var controller: PrintPreviewController?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { true }

    /// 1/10 mm → 点
    var scale: CGFloat { Self.unitsToPoints * CGFloat(zoom) / 100 }

    /// 用紙と周りの余白の大きさ（点）
    var contentSize: NSSize {
        guard let layout = renderer?.layout else { return .zero }
        return NSSize(width: ceil(CGFloat(layout.paperWidth + Self.viewMargin * 2 + 1) * scale),
                      height: ceil(CGFloat(layout.paperHeight + Self.viewMargin * 2 + 1) * scale))
    }

    /// 大きさ：用紙が窓より小さいときは窓いっぱい（灰色の地）
    func updateSize() {
        let visible = enclosingScrollView?.contentSize ?? .zero
        let size = contentSize
        setFrameSize(NSSize(width: max(size.width, visible.width), height: max(size.height, visible.height)))
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        Self.background.setFill()
        dirtyRect.fill()
        guard let renderer else { return }
        let layout = renderer.layout
        let setting = layout.setting
        context.saveGState()
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: CGFloat(Self.viewMargin), y: CGFloat(Self.viewMargin))
        let onePixel = 1 / scale
        context.setShouldAntialias(antialias)
        // 用紙（原版 ::Rectangle：黒い枠の白）
        let paper = CGRect(x: 0, y: 0, width: CGFloat(layout.paperWidth + 1), height: CGFloat(layout.paperHeight + 1))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(paper)
        context.setStrokeColor(CGColor(gray: 0, alpha: 1))
        context.setLineWidth(onePixel)
        context.stroke(paper.insetBy(dx: onePixel / 2, dy: onePixel / 2))
        // 余白の枠（原版 RGB(128,128,128) のペン）
        let margin = CGRect(x: CGFloat(setting.marginLeft), y: CGFloat(setting.marginTop),
                            width: CGFloat(layout.paperWidth - setting.marginRight + 1 - setting.marginLeft),
                            height: CGFloat(layout.paperHeight - setting.marginBottom - setting.marginTop))
        context.setStrokeColor(CGColor(gray: 128.0 / 255.0, alpha: 1))
        context.stroke(margin.insetBy(dx: onePixel / 2, dy: onePixel / 2))
        context.setShouldAntialias(true)
        if let page {
            renderer.hairline = onePixel
            renderer.smoothLines = antialias
            renderer.draw(page, in: context)
        }
        context.restoreGState()
    }

    // MARK: 手のカーソルとドラッグ

    private var dragOrigin: NSPoint?

    override func resetCursorRects() {
        addCursorRect(visibleRect, cursor: dragOrigin == nil ? .openHand : .closedHand)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        dragOrigin = event.locationInWindow
        NSCursor.closedHand.set()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let origin = dragOrigin, let clip = enclosingScrollView?.contentView else { return }
        let point = event.locationInWindow
        var bounds = clip.bounds.origin
        bounds.x -= point.x - origin.x
        bounds.y += point.y - origin.y
        scroll(to: bounds)
        dragOrigin = point
    }

    override func mouseUp(with event: NSEvent) {
        dragOrigin = nil
        NSCursor.openHand.set()
        window?.invalidateCursorRects(for: self)
    }

    /// 表示位置を変える（用紙の外にははみ出さない）
    func scroll(to origin: NSPoint) {
        guard let scrollView = enclosingScrollView else { return }
        let clip = scrollView.contentView
        let maxX = max(0, frame.width - clip.bounds.width)
        let maxY = max(0, frame.height - clip.bounds.height)
        clip.scroll(to: NSPoint(x: min(max(0, origin.x), maxX), y: min(max(0, origin.y), maxY)))
        scrollView.reflectScrolledClipView(clip)
    }

    /// 原版 LINE_RANGE_Y・PAGE_RANGE_Y（ドット）
    static let lineStep: CGFloat = 24
    static let pageStep: CGFloat = 160

    // MARK: キー（原版は操作バーのダイアログ：Esc は「戻る」、Enter は「印刷」）

    override func keyDown(with event: NSEvent) {
        let origin = enclosingScrollView?.contentView.bounds.origin ?? .zero
        switch event.keyCode {
        case 53:	// Esc
            controller?.close()
        case 36, 76:	// Return・Enter
            controller?.print()
        case 126:	// ↑
            scroll(to: NSPoint(x: origin.x, y: origin.y - Self.lineStep))
        case 125:	// ↓
            scroll(to: NSPoint(x: origin.x, y: origin.y + Self.lineStep))
        case 123:	// ←
            scroll(to: NSPoint(x: origin.x - Self.lineStep, y: origin.y))
        case 124:	// →
            scroll(to: NSPoint(x: origin.x + Self.lineStep, y: origin.y))
        case 116:	// Page Up
            scroll(to: NSPoint(x: origin.x, y: origin.y - Self.pageStep))
        case 121:	// Page Down
            scroll(to: NSPoint(x: origin.x, y: origin.y + Self.pageStep))
        case 115:	// Home
            scroll(to: NSPoint(x: origin.x, y: 0))
        case 119:	// End
            scroll(to: NSPoint(x: origin.x, y: frame.height))
        default:
            super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        controller?.close()
    }
}

/// 印刷プレビューの窓の中身：上に操作バー、下に用紙
final class PrintPreviewContainerView: NSView {
    let bar: NSView
    let scrollView: NSScrollView

    init(bar: NSView, scrollView: NSScrollView) {
        self.bar = bar
        self.scrollView = scrollView
        super.init(frame: .zero)
        addSubview(bar)
        addSubview(scrollView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool { true }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        arrange()
    }

    override func layout() {
        super.layout()
        arrange()
    }

    func arrange() {
        let barHeight = bar.frame.height
        bar.frame.origin = .zero
        scrollView.frame = NSRect(x: 0, y: barHeight, width: bounds.width, height: max(0, bounds.height - barHeight))
        (scrollView.documentView as? PrintPreviewView)?.updateSize()
    }

    /// 操作バーの地（原版はダイアログの色）
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: bar.frame.height).intersection(dirtyRect).fill()
    }
}

// MARK: - 印刷プレビュー

/// 印刷プレビュー（第 47 步。原版 CPrintPreview と CEditWnd::PrintPreviewModeONOFF）。
///
/// 窓の中身（編集画面・アウトライン）を隠して、操作バー（原版 IDD_PRINTPREVIEWBAR）と用紙を出す。
/// 原版はメニューも消すが、Mac のメニューバーは消せないので、プレビュー中は文書の機能を使えなくする
/// （SakuraDocument.validateUserInterfaceItem。原版 CViewCommander::HandleCommand が F_PRINT_PREVIEW 以外を受け付けない）。
/// 原版はプリンターがないとプレビューできない（STR_ERR_DLGEDITWND14）が、Mac 版はいつも PDF に印刷できるのでプリンターがなくても開く
final class PrintPreviewController: NSObject {
    /// 印刷ページ設定が変わった（原版 MYWM_CHANGESETTING の PM_PRINTSETTING）
    static let settingsDidChangeNotification = Notification.Name("SakuraPrintSettingsDidChange")
    /// 原版 MIN_PREVIEW_ZOOM・MAX_PREVIEW_ZOOM
    static let zoomRange = 10 ... 400

    unowned let windowController: EditorWindowController
    let page: PropPage
    let previewView = PrintPreviewView()
    let scrollView = NSScrollView()
    let container: PrintPreviewContainerView
    /// 隠した窓の中身（戻るときに戻す）
    private let savedContent: NSView?
    private(set) var layout: PrintLayout?
    private var renderer: PrintPageRenderer?
    /// 表示しているページ（0 から。原版 m_nCurPageNum）
    private(set) var currentPage = 0
    /// 印刷中・ダイアログを出している間は設定の変更を後回しにする（原版 m_bLockSetting・m_bDemandUpdateSetting）
    private var lockSetting = false
    private var demandUpdateSetting = false
    private(set) var isClosed = false

    // テストで差し替える
    /// 印刷（NSPrintOperation を実行して、印刷したら true）
    static var runPrintOperation: (_ operation: NSPrintOperation, _ window: NSWindow?, _ completion: @escaping (Bool) -> Void) -> Void = { operation, window, completion in
        if let window {
            PrintOperationRunner.run(operation, for: window, completion: completion)
        } else {
            completion(operation.run())
        }
    }
    /// プリンターの設定（原版 PrintDlg の PD_PRINTSETUP。Mac は用紙設定のパネル）。OK で true
    static var runPageLayout: (_ printInfo: NSPrintInfo, _ window: NSWindow?) -> Bool = { printInfo, _ in
        NSPageLayout().runModal(with: printInfo) == NSApplication.ModalResponse.OK.rawValue
    }
    /// 「印刷ページ設定」（テストは中身を見る）
    static var runPrintSettingDialog: (_ dialog: PrintSettingDialog, _ window: NSWindow?) -> Bool = { dialog, window in
        dialog.runModal(parent: window)
    }

    var document: EditorDocument { windowController.editorDocument }
    var window: NSWindow? { windowController.window }

    init?(windowController: EditorWindowController) {
        guard let definition = PropDialogs.load("PrintDialogs")?.dialog("IDD_PRINTPREVIEWBAR") else { return nil }
        self.windowController = windowController
        page = PropPage(definition: definition)
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = PrintPreviewView.background
        scrollView.documentView = previewView
        scrollView.setAccessibilityIdentifier("PrintPreview")
        previewView.setAccessibilityElement(true)
        previewView.setAccessibilityRole(.image)
        previewView.setAccessibilityIdentifier("PrintPreviewPaper")
        container = PrintPreviewContainerView(bar: page.view, scrollView: scrollView)
        savedContent = windowController.window?.contentView
        super.init()
        previewView.controller = self
        setUpBar()
        NotificationCenter.default.addObserver(self, selector: #selector(settingsDidChange(_:)),
                                               name: Self.settingsDidChangeNotification, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setUpBar() {
        // 原版 WM_INITDIALOG：「滑らか」を使えるようにする
        page.setEnabled("IDC_CHECK_ANTIALIAS", true)
        page.setUnavailable(["IDC_BUTTON_HELP"], reason: NSLocalizedString("Mac 版にはまだヘルプがありません", comment: "help"))
        // プリンターのアイコン（原版 IDI_PRINTER）
        if let icon = page.definition.controls.first(where: { $0.kind == "icon" }) {
            let frame = NSRect(x: PropPage.pointsX(icon.frame[0]), y: PropPage.points(icon.frame[1]) - 2,
                               width: PropPage.points(icon.frame[3]) + 4, height: PropPage.points(icon.frame[3]) + 4)
            let image = NSImageView(frame: frame)
            image.image = NSImage(systemSymbolName: "printer", accessibilityDescription: nil)
            image.imageScaling = .scaleProportionallyUpOrDown
            page.view.addSubview(image)
        }
        // 「印刷」は既定のボタン（原版 IDOK）、「戻る」は Esc（IDCANCEL）
        (page.control("IDOK") as? NSButton)?.keyEquivalent = "\r"
        (page.control("IDCANCEL") as? NSButton)?.keyEquivalent = "\u{1b}"
        page.onButton = { [weak self] id in self?.buttonPressed(id) }
        page.onChange = { [weak self] id in
            if id == "IDC_CHECK_ANTIALIAS" { self?.antialiasChanged() }
        }
    }

    // MARK: 開く・閉じる（原版 PrintPreviewModeONOFF）

    /// プレビューを開く。印字できる場所がないときは開かずに false
    @discardableResult
    func open() -> Bool {
        guard let window else { return false }
        container.frame = window.contentView?.frame ?? .zero
        window.contentView = container
        container.arrange()
        window.makeFirstResponder(previewView)
        changePrintSetting()
        return !isClosed
    }

    /// プレビューを閉じて、編集画面に戻す
    func close() {
        guard !isClosed else { return }
        isClosed = true
        if let window, let savedContent {
            savedContent.frame = container.frame
            window.contentView = savedContent
            window.makeFirstResponder(windowController.textView)
        }
        windowController.printPreviewDidClose(self)
    }

    // MARK: 設定の反映（原版 OnChangePrintSetting）

    /// 他の窓で印刷ページ設定が変わった（原版 OnChangeSetting）
    @objc private func settingsDidChange(_ notification: Notification) {
        guard !isClosed else { return }
        if lockSetting {
            demandUpdateSetting = true
            return
        }
        changePrintSetting()
    }

    /// 今の設定で作り直す
    func changePrintSetting() {
        demandUpdateSetting = false
        let setting = PrintCore.setting(at: document.printSettingIndex)
        let layout = document.makePrintLayout(setting)
        // 印字可能領域がない場合は印刷プレビューを終了する（原版 STR_ERR_DLGPRNPRVW3_1）
        if layout.isEmpty {
            close()
            windowController.textView.sendStatusMessage(
                NSLocalizedString("印刷ページ設定エラー:印字可能領域がありません", comment: "STR_ERR_DLGPRNPRVW3_1"))
            return
        }
        self.layout = layout
        let renderer = PrintPageRenderer(layout: layout)
        self.renderer = renderer
        previewView.renderer = renderer
        if layout.pageCount <= currentPage { currentPage = 0 }
        updatePaperLabels()
        goPage(currentPage)
    }

    /// プリンターと用紙（原版 OnPaint の IDC_STATIC_PRNDEV・IDC_STATIC_PAPER）
    private func updatePaperLabels() {
        guard let setting = layout?.setting else { return }
        page.setText("IDC_STATIC_PRNDEV", Self.printerName(setting))
        let paper = PrintCore.papers.first { $0.paperID == setting.paperSize }?.name ?? ""
        let orientation = setting.orientation == .landscape
            ? NSLocalizedString("横", comment: "STR_ERR_DLGPRNPRVW1") : NSLocalizedString("縦", comment: "STR_ERR_DLGPRNPRVW2")
        page.setText("IDC_STATIC_PAPER", "\(paper)  \(orientation)")
    }

    /// 設定のプリンター。空のときは今のプリンター
    static func printerName(_ setting: PrintSetting) -> String {
        if !setting.printerName.isEmpty { return setting.printerName }
        return NSPrintInfo.shared.printer.name
    }

    // MARK: ページ・倍率（原版 OnPreviewGoPage・OnPreviewZoom）

    var pageCount: Int { layout?.pageCount ?? 0 }

    func goPage(_ number: Int) {
        let count = pageCount
        currentPage = max(0, min(number, count - 1))
        page.setEnabled("IDC_BUTTON_PREVPAGE", currentPage > 0)
        page.setEnabled("IDC_BUTTON_NEXTPAGE", currentPage + 1 < count)
        page.setText("IDC_STATIC_PAGENUM", String(format: NSLocalizedString("%d/%d頁", comment: "STR_ERR_DLGPRNPRVW6"), currentPage + 1, count))
        updateZoomControls()
        if let layout, count > 0 {
            previewView.page = layout.page(currentPage, view: windowController.textView.expandParameterView)
        } else {
            previewView.page = nil
        }
    }

    func zoom(up: Bool) {
        if up {
            previewView.zoom = min(previewView.zoom + 10, Self.zoomRange.upperBound)
        } else {
            // 縮小はスクロール位置を左上に戻す
            previewView.zoom = max(previewView.zoom - 10, Self.zoomRange.lowerBound)
            previewView.scroll(to: .zero)
        }
        updateZoomControls()
    }

    var zoom: Int { previewView.zoom }

    private func updateZoomControls() {
        page.setEnabled("IDC_BUTTON_ZOOMDOWN", previewView.zoom > Self.zoomRange.lowerBound)
        page.setEnabled("IDC_BUTTON_ZOOMUP", previewView.zoom < Self.zoomRange.upperBound)
        page.setText("IDC_STATIC_ZOOM", String(format: "%d %%", previewView.zoom))
    }

    private func antialiasChanged() {
        previewView.antialias = page.isChecked("IDC_CHECK_ANTIALIAS")
    }

    /// 原版 OnPreviewGoDirectPage：ページ番号を入れて移動（数字以外があれば何もしない）
    func goDirectPage() {
        let message = String(format: NSLocalizedString("表示するページ番号を指定してください。(1 - %d)", comment: "STR_ERR_DLGPRNPRVW4"), pageCount)
        guard let text = CommonSettingsPages.input(NSLocalizedString("プレビューページ指定", comment: "STR_ERR_DLGPRNPRVW5"),
                                                   message, 11, String(currentPage + 1)) else { return }
        guard text.allSatisfy({ $0.isASCII && $0.isNumber }) else { return }
        goPage((Int(text) ?? 0) - 1)
    }

    private func buttonPressed(_ id: String) {
        switch id {
        case "IDOK": print()
        case "IDCANCEL": close()
        case "IDC_BUTTON_PREVPAGE": goPage(currentPage - 1)
        case "IDC_BUTTON_NEXTPAGE": goPage(currentPage + 1)
        case "IDC_BUTTON_DIRECTPAGE": goDirectPage()
        case "IDC_BUTTON_ZOOMUP": zoom(up: true)
        case "IDC_BUTTON_ZOOMDOWN": zoom(up: false)
        case "IDC_BUTTON_PRINTSETTING": windowController.showPrintSetting()
        case "IDC_BUTTON_PRINTERSELECT": selectPrinter()
        default: break
        }
        if !isClosed, window?.firstResponder is NSButton { window?.makeFirstResponder(previewView) }
    }

    // MARK: プリンター（原版 IDC_BUTTON_PRINTERSELECT）

    /// 印刷情報（用紙・向き・プリンター）。余白なし：用紙の左上が原点（原版も印刷可能位置を引いて用紙の左上から描く）
    func makePrintInfo() -> NSPrintInfo {
        let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        guard let layout else { return info }
        let setting = layout.setting
        if !setting.printerName.isEmpty, let printer = NSPrinter(name: setting.printerName) {
            info.printer = printer
        }
        info.orientation = setting.orientation == .landscape ? .landscape : .portrait
        info.paperSize = NSSize(width: CGFloat(layout.paperWidth) * PrintPagesView.unitsToPoints,
                                height: CGFloat(layout.paperHeight) * PrintPagesView.unitsToPoints)
        info.topMargin = 0
        info.bottomMargin = 0
        info.leftMargin = 0
        info.rightMargin = 0
        info.horizontalPagination = .clip
        info.verticalPagination = .clip
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        return info
    }

    /// プリンターと用紙・向きを選ぶ（原版 PrintDlg(PD_PRINTSETUP) → m_nPrintPaperSize・m_nPrintPaperOrientation に反映して PM_PRINTSETTING）
    func selectPrinter() {
        let info = makePrintInfo()
        lockSetting = true
        let ok = Self.runPageLayout(info, window)
        lockSetting = false
        guard ok else {
            if demandUpdateSetting { changePrintSetting() }
            return
        }
        let index = document.printSettingIndex
        let setting = PrintCore.setting(at: index)
        let landscape = info.orientation == .landscape
        setting.orientation = landscape ? .landscape : .portrait
        // 用紙の大きさ（点）→ 一番近い原版の用紙
        let size = info.paperSize
        let width = Int((min(size.width, size.height) / PrintPagesView.unitsToPoints).rounded())
        let height = Int((max(size.width, size.height) / PrintPagesView.unitsToPoints).rounded())
        if let paper = Self.nearestPaper(width: width, height: height) {
            setting.paperSize = paper.paperID
        }
        setting.printerName = info.printer.name
        PrintCore.setSetting(setting, at: index)
        NotificationCenter.default.post(name: Self.settingsDidChangeNotification, object: nil)
    }

    /// 大きさ（1/10 mm、縦向き）が一番近い用紙（原版の用紙の一覧 PaperInfo）
    static func nearestPaper(width: Int, height: Int) -> PaperInfo? {
        PrintCore.papers.min { a, b in
            abs(a.width - width) + abs(a.height - height) < abs(b.width - width) + abs(b.height - height)
        }
    }

    // MARK: 印刷（原版 OnPrint）

    /// 印刷のジョブ名（原版：ファイル名、無題は STR_NO_TITLE2）
    var jobName: String {
        document.path.isEmpty ? NSLocalizedString("無題", comment: "STR_NO_TITLE2") : (document.path as NSString).lastPathComponent
    }

    /// 印刷する。印刷したらプレビューを閉じる（原版：印刷が終わったら Preview から抜ける。キャンセルはそのまま）
    func print() {
        guard let layout, let renderer, pageCount > 0 else {
            // 原版 STR_ERR_DLGPRNPRVW7
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = NSLocalizedString("印刷するページがありません。", comment: "STR_ERR_DLGPRNPRVW7")
            if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
            return
        }
        let pages = PrintPagesView(layout: layout, renderer: renderer, view: windowController.textView.expandParameterView)
        let info = makePrintInfo()
        let operation = NSPrintOperation(view: pages, printInfo: info)
        operation.jobTitle = jobName
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        operation.printPanel.options.insert([.showsCopies, .showsPageRange, .showsPaperSize, .showsOrientation, .showsPreview])
        lockSetting = true
        let printerBefore = layout.setting.printerName
        Self.runPrintOperation(operation, window) { [weak self] printed in
            guard let self else { return }
            self.lockSetting = false
            guard printed else {
                if self.demandUpdateSetting { self.changePrintSetting() }
                return
            }
            // プリンターを変えたら覚える（原版 m_mdmDevMode を PM_PRINTSETTING で他の窓へ）
            let printer = operation.printInfo.printer.name
            if printer != printerBefore && !(printerBefore.isEmpty && printer == NSPrintInfo.shared.printer.name) {
                let index = self.document.printSettingIndex
                let setting = PrintCore.setting(at: index)
                setting.printerName = printer
                PrintCore.setSetting(setting, at: index)
                NotificationCenter.default.post(name: Self.settingsDidChangeNotification, object: nil)
            }
            self.close()
        }
    }
}

/// NSPrintOperation の終わりを closure で受ける
private final class PrintOperationRunner: NSObject {
    private static var running: Set<PrintOperationRunner> = []
    private let completion: (Bool) -> Void

    private init(completion: @escaping (Bool) -> Void) {
        self.completion = completion
    }

    static func run(_ operation: NSPrintOperation, for window: NSWindow, completion: @escaping (Bool) -> Void) {
        let runner = PrintOperationRunner(completion: completion)
        running.insert(runner)
        operation.runModal(for: window, delegate: runner,
                           didRun: #selector(printOperationDidRun(_:success:contextInfo:)), contextInfo: nil)
    }

    @objc private func printOperationDidRun(_ operation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        Self.running.remove(self)
        completion(success)
    }
}

/// 印刷するページ（NSPrintOperation に渡す。1 ページ = 用紙 1 枚、余白なし）
final class PrintPagesView: NSView {
    /// 1/10 mm → 点（1/72 インチ）
    static let unitsToPoints: CGFloat = 72.0 / 254.0

    let layout: PrintLayout
    let renderer: PrintPageRenderer
    let expandView: ExpandParameterView

    init(layout: PrintLayout, renderer: PrintPageRenderer, view: ExpandParameterView) {
        self.layout = layout
        self.renderer = renderer
        expandView = view
        super.init(frame: NSRect(x: 0, y: 0, width: CGFloat(layout.paperWidth) * Self.unitsToPoints,
                                 height: CGFloat(layout.paperHeight) * Self.unitsToPoints * CGFloat(max(1, layout.pageCount))))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool { true }

    var pageHeight: CGFloat { CGFloat(layout.paperHeight) * Self.unitsToPoints }

    override func knowsPageRange(_ range: NSRangePointer) -> Bool {
        range.pointee = NSRange(location: 1, length: layout.pageCount)
        return true
    }

    override func rectForPage(_ page: Int) -> NSRect {
        NSRect(x: 0, y: CGFloat(page - 1) * pageHeight, width: bounds.width, height: pageHeight)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let first = max(0, Int(dirtyRect.minY / pageHeight))
        let last = min(layout.pageCount - 1, Int((dirtyRect.maxY - 1) / pageHeight))
        guard first <= last else { return }
        for number in first ... last {
            drawPage(number, in: context, top: CGFloat(number) * pageHeight)
        }
    }

    /// 1 ページを描く（テストも使う）
    func drawPage(_ number: Int, in context: CGContext, top: CGFloat = 0) {
        context.saveGState()
        context.translateBy(x: 0, y: top)
        context.scaleBy(x: Self.unitsToPoints, y: Self.unitsToPoints)
        renderer.hairline = 1
        renderer.smoothLines = true
        renderer.draw(layout.page(number, view: expandView), in: context)
        context.restoreGState()
    }
}

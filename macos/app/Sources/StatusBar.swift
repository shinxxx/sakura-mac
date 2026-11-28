// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge

/// ステータスバー（计划第 38 步。原版 CMainStatusBar、CCaret::ShowCaretPosInfo、CEditWnd::OnSize・OnNotify・WM_DRAWITEM）。
///
/// - 欄は原版と同じ 8 つ：メッセージ、行・桁、入力改行コード、カーソル位置の文字コード、文字コードセット、REC、挿入／上書、フォントの倍率。
///   メッセージ以外の欄の幅は原版と同じく見本の文字列（pszLabel）の幅＋境界の幅で、右から並べる。
/// - ダブルクリック（原版 NM_DBLCLK）：行・桁→指定行へジャンプ、文字コード→各種コードの表示、文字コードセット→文字コードセット指定、
///   REC→キーマクロの記録開始／終了、挿入／上書→挿入／上書きモード切り替え。右クリック（NM_RCLICK）：改行コード→入力改行コード指定のメニュー。
/// - 表示するかは共通設定『ウィンドウ』「ステータスバーを表示する」（bDispSTATUSBAR）と 設定 > ステータスバーの表示（F_SHOWSTATUSBAR）。
/// - ステータスメッセージ（StatusMessage.swift）は表示中ならメッセージ欄に出す（原版 CEditWnd::SendStatusMessage）。
final class StatusBarView: NSView {
    /// 欄（原版の SB_SETTEXT の番号）
    enum Part: Int, CaseIterable {
        case message = 0, rowCol, eol, charCode, encoding, rec, insMode, zoom

        /// UI テスト・アクセシビリティの識別子
        var identifier: String {
            switch self {
            case .message: return "statusBar.message"
            case .rowCol: return "statusBar.rowCol"
            case .eol: return "statusBar.eol"
            case .charCode: return "statusBar.charCode"
            case .encoding: return "statusBar.encoding"
            case .rec: return "statusBar.rec"
            case .insMode: return "statusBar.insMode"
            case .zoom: return "statusBar.zoom"
            }
        }
    }

    /// 高さ（Windows のステータスバーと同じく文字の高さ＋上下の余白）
    static let height: CGFloat = 22
    /// 境界の幅（原版 nBdrWidth = SM_CXSIZEFRAME + SM_CXEDGE * 2）
    static let borderWidth: CGFloat = 8
    /// 右端のサイズボックスの分（原版 nSbxWidth。Mac のウィンドウの角は丸いので文字がかからないように空ける）
    static let sizeBoxWidth: CGFloat = 14
    /// 文字と欄の左端の間
    static let textInset: CGFloat = 4

    static let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)

    private var labels: [NSTextField] = []
    /// 各欄の右端（原版 nStArr）
    private(set) var partRights: [CGFloat] = []

    /// キーマクロの記録中（REC を濃く描く。原版 WM_DRAWITEM）
    var isRecording = false {
        didSet { if oldValue != isRecording { updateRecLabel() } }
    }

    /// ダブルクリック・右クリックで機能を実行する編集画面
    weak var textView: EditorTextView?

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(x: frameRect.minX, y: frameRect.minY, width: frameRect.width, height: Self.height))
        setAccessibilityElement(true)
        setAccessibilityIdentifier("statusBar")
        setAccessibilityRole(.group)
        for part in Part.allCases {
            let label = NSTextField(labelWithString: "")
            label.font = Self.font
            label.lineBreakMode = .byClipping
            label.cell?.truncatesLastVisibleLine = false
            label.textColor = .labelColor
            label.setAccessibilityIdentifier(part.identifier)
            addSubview(label)
            labels.append(label)
        }
        labels[Part.rec.rawValue].stringValue = "REC"
        updateRecLabel()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool { true }

    /// 欄の文字
    func text(_ part: Part) -> String {
        part == .rec ? (isRecording ? "REC" : "") : labels[part.rawValue].stringValue
    }

    /// 欄の文字を変える（同じなら何もしない。原版 CMainStatusBar::SetStatusText）
    func setText(_ part: Part, _ text: String) {
        guard part != .rec else { return }
        let label = labels[part.rawValue]
        if label.stringValue != text { label.stringValue = text }
    }

    private func updateRecLabel() {
        // 原版：記録中は COLOR_BTNTEXT で 1 ドットずらして 2 回描く（太字）、そうでないときは COLOR_3DSHADOW
        let label = labels[Part.rec.rawValue]
        label.font = isRecording ? NSFontManager.shared.convert(Self.font, toHaveTrait: .boldFontMask) : Self.font
        label.textColor = isRecording ? .labelColor : .tertiaryLabelColor
        label.setAccessibilityValue(isRecording ? "REC" : "")
    }

    // MARK: - 欄の幅（原版 CEditWnd::OnSize）

    /// 幅の見本（原版 pszLabel：「99999 行 9999 列」「CRLF」「AAAAAAAAAAAA」「UTF-16 BOM付」「REC」「上書」「9999 %」。
    /// 行・桁、BOM、挿入／上書は表示する言語の文字で測る）
    static func sampleLabels() -> [String] {
        let rowCol = StatusBarText.rowCol(line: 99999, column: 9999)
        let ins = [StatusBarText.insertModeName(true), StatusBarText.insertModeName(false)]
            .max { width(of: $0) < width(of: $1) } ?? ""
        return ["", rowCol, "CRLF", "AAAAAAAAAAAA", "UTF-16" + StatusBarText.bomSuffix, "REC", ins, "9999 %"]
    }

    static func width(of text: String) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    /// 欄の右端を計算する（原版 nStArr。右から、見本の幅＋境界の幅ずつ）
    static func partRights(width: CGFloat, labels: [String] = sampleLabels()) -> [CGFloat] {
        var rights = Array(repeating: CGFloat(0), count: labels.count)
        rights[labels.count - 1] = width - sizeBoxWidth
        for i in stride(from: labels.count - 1, to: 0, by: -1) {
            rights[i - 1] = rights[i] - (Self.width(of: labels[i]) + borderWidth)
        }
        return rights
    }

    /// 欄の範囲
    func rect(of part: Part) -> NSRect {
        guard partRights.count == Part.allCases.count else { return .zero }
        let left = part == .message ? 0 : partRights[part.rawValue - 1]
        return NSRect(x: left, y: 0, width: max(0, partRights[part.rawValue] - left), height: bounds.height)
    }

    override func layout() {
        super.layout()
        arrangeLabels()
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        arrangeLabels()
    }

    func arrangeLabels() {
        partRights = Self.partRights(width: bounds.width)
        let lineHeight = ceil(Self.font.ascender - Self.font.descender + Self.font.leading)
        for part in Part.allCases {
            let r = rect(of: part)
            let label = labels[part.rawValue]
            label.frame = NSRect(x: r.minX + Self.textInset, y: floor((bounds.height - lineHeight) / 2),
                                 width: max(0, r.width - Self.textInset - 1), height: lineHeight)
        }
        needsDisplay = true
    }

    // MARK: - 描画

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        // 上の境界線と、欄の間の区切り線（Windows 10 以降のステータスバーと同じく線だけ）
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
        for part in Part.allCases where part != .message {
            let r = rect(of: part)
            NSRect(x: r.minX, y: 4, width: 1, height: bounds.height - 7).fill()
        }
    }

    // MARK: - マウス（原版 CEditWnd::OnNotify の NM_DBLCLK・NM_RCLICK）

    /// この点の欄
    func part(at point: NSPoint) -> Part? {
        Part.allCases.first { rect(of: $0).contains(point) }
    }

    override func mouseDown(with event: NSEvent) {
        guard event.clickCount == 2, let part = part(at: convert(event.locationInWindow, from: nil)) else {
            super.mouseDown(with: event)
            return
        }
        doubleClicked(part)
    }

    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard part(at: point) == .eol, let menu = eolMenu() else {
            super.rightMouseDown(with: event)
            return
        }
        menu.popUp(positioning: nil, at: point, in: self)
    }

    /// 欄のダブルクリックの機能
    static func command(forDoubleClickOn part: Part) -> Int? {
        switch part {
        case .insMode: return 31001	// F_CHGMOD_INS 上書き/挿入
        case .rec: return 31250		// F_RECKEYMACRO マクロの記録開始・終了
        case .rowCol: return 30920	// F_JUMP_DIALOG 桁位置→行番号ジャンプ
        case .encoding: return 31010	// F_CHG_CHARSET 文字コードセット→文字コードセット指定
        default: return nil
        }
    }

    func doubleClicked(_ part: Part) {
        guard let textView else { return }
        if part == .charCode {
            textView.showCodeBox()	// 文字コード→各種コード
            return
        }
        guard let code = Self.command(forDoubleClickOn: part) else { return }
        textView.window?.makeFirstResponder(textView)
        CommandTable.perform(code, from: textView)
    }

    /// 入力改行モードのメニュー（CRLF・LF・CR、「拡張EOLを有効にする」ときは NEL・LS・PS も）
    func eolMenu() -> NSMenu? {
        guard let textView else { return nil }
        let menu = NSMenu()
        var codes = [31081, 31082, 31083]	// F_CHGMOD_EOL_CRLF、LF、CR
        if EditorCore.commonSetting(section: "Common", key: "bEnableExtEol") == "1" {
            codes += [31084, 31086, 31085]	// F_CHGMOD_EOL_NEL、LS、PS（原版の並び）
        }
        for code in codes {
            let item = NSMenuItem(title: StatusBarText.eolMenuTitle(code), action: #selector(EditorTextView.changeNewLineEol(_:)), keyEquivalent: "")
            item.tag = code
            item.target = textView
            menu.addItem(item)
        }
        return menu
    }
}

/// ステータスバーの文字（原版 CCaret::ShowCaretPosInfo の書式）
enum StatusBarText {
    /// 行・桁（STR_STATUS_ROW_COL "%5d 行 %4d 桁"）
    static func rowCol(line: Int, column: Int) -> String {
        String(format: L10n.tr("%5d 行 %4d 桁", comment: "STR_STATUS_ROW_COL"), Int32(clamping: line), Int32(clamping: column))
    }

    /// 文字コードセットの後ろの BOM（STR_CARET_WITHBOM）
    static var bomSuffix: String { L10n.tr(" BOM付", comment: "STR_CARET_WITHBOM") }

    /// 挿入／上書（STR_INS_MODE_INS、STR_INS_MODE_OVR）
    static func insertModeName(_ insert: Bool) -> String {
        insert ? L10n.tr("挿入", comment: "STR_INS_MODE_INS") : L10n.tr("上書", comment: "STR_INS_MODE_OVR")
    }

    /// フォントの倍率（STR_STATUS_FONTZOOM_0 "%4.0f %%"、5% 未満は STR_STATUS_FONTZOOM_1 "%4.1f %%"）
    static func zoom(_ zoom: Double) -> String {
        let percent = zoom * 100
        return String(format: percent < 5 ? "%4.1f %%" : "%4.0f %%", percent)
    }

    /// 文字コードセット（原版 CCodePage::GetNameNormal ＋ STR_CARET_WITHBOM）
    static func encoding(_ encoding: EditorEncoding, bom: Bool) -> String {
        EditorCore.name(ofEncoding: encoding) + (bom ? bomSuffix : "")
    }

    /// 入力改行モードのメニューの項目（原版は機能名 LS(F_CHGMOD_EOL_CRLF) 等、NEL・LS・PS は STR_EDITWND_MENU_NEL 等）
    static func eolMenuTitle(_ code: Int) -> String {
        switch code {
        case 31084: return "NEL"
        case 31086: return "LS"
        case 31085: return "PS"
        default: return RecentMenu.labelWithoutMnemonic(EditorCore.name(ofCommand: code))
        }
    }
}

// MARK: - 編集画面からの更新

extension EditorTextView {
    /// カーソル位置の排版位置（ステータスバー用。折り返し位置で行末にいるときは上の行の末尾）
    var caretLayoutPositionForStatus: EditorLayoutPosition {
        let c = caretRowAndIndex
        let xs = row(c.row).xs
        guard !xs.isEmpty else { return EditorLayoutPosition(line: c.row, x: 0) }
        return EditorLayoutPosition(line: c.row, x: Int(xs[min(c.index, xs.count - 1)]))
    }

    /// ステータスバーの各欄（原版 CCaret::ShowCaretPosInfo）
    func statusBarTexts(encoding: EditorEncoding, bom: Bool) -> [StatusBarView.Part: String] {
        let status = document.caretStatus(at: caretLayoutPositionForStatus)
        return [
            .rowCol: StatusBarText.rowCol(line: status.line, column: status.column),
            .eol: status.eolName,
            .charCode: status.charCode,
            .encoding: StatusBarText.encoding(encoding, bom: bom),
            .insMode: StatusBarText.insertModeName(document.insertMode),
            .zoom: StatusBarText.zoom(Self.fontZoom),
        ]
    }

    /// 各種コードの表示（原版 ShowCodeBox）。単元テストではダイアログを出さない
    static var presentCodeBox: (EditorTextView, String) -> Void = { view, message in
        let alert = NSAlert()
        alert.messageText = AboutPanel.appName
        alert.informativeText = message
        if let window = view.window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    /// カーソル位置の文字の各種コード（原版 ShowCodeBox、STR_ERR_DLGEDITWND13）。文字がないときは何もしない
    func showCodeBox() {
        guard let codes = document.charCodes(at: caretLayoutPositionForStatus) else { return }
        let format = L10n.tr("文字:\t\t%@ (%@)\n\nSJIS:\t\t%@\nJIS:\t\t%@\nEUC:\t\t%@\nLatin1:\t\t%@\nUTF-16:\t\t%@\nUTF-8:\t\t%@\nCESU-8:\t\t%@",
                             comment: "STR_ERR_DLGEDITWND13")
        let message = String(format: format, codes.character, codes.codePoint, codes.sjis, codes.jis, codes.euc,
                             codes.latin1, codes.utf16, codes.utf8, codes.cesu8)
        Self.presentCodeBox(self, message)
    }
}

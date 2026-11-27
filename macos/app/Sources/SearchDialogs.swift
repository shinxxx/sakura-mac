// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge

/// 查找、置换、指定行へジャンプ的对话框（第 32 步。原版 CDlgFind、CDlgReplace、CDlgJump）。
///
/// 布局按原版 sakura_rc.rc 的 IDD_FIND、IDD_REPLACE、IDD_JUMP（对话框单位 DLU）换算成点。
/// Mac 没有访问键，标签去掉了「(&N)」之类的部分。
/// 查找、置换是非模态的，一个编辑窗口一个（与原版相同）；指定行へジャンプ是模态的（Mac 版用表单）。

/// 上下翻转的视图：控件的位置与原版一样从左上角算
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// 对话框的控件和布局（DLU → 点）
class DialogBuilder: NSObject {
    /// 1 DLU 的点数。原版的字体（9 点）的 DLU 大约是横 1.5〜1.75、纵 1.6〜2 像素，Mac 的小字体换算成这个
    static let scaleX: CGFloat = 1.75
    static let scaleY: CGFloat = 1.85

    let content = FlippedView()

    static func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
        NSRect(x: x * scaleX, y: y * scaleY, width: w * scaleX, height: h * scaleY)
    }

    /// 对话框的大小（DLU）
    static func size(_ w: CGFloat, _ h: CGFloat) -> NSSize {
        NSSize(width: w * scaleX, height: h * scaleY)
    }

    private func place(_ control: NSView, _ frame: NSRect, id: String) {
        control.frame = frame
        control.setAccessibilityIdentifier(id)
        content.addSubview(control)
    }

    private static var font: NSFont { .systemFont(ofSize: NSFont.smallSystemFontSize) }

    @discardableResult
    func label(_ title: String, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat = 10, id: String = "") -> NSTextField {
        let field = NSTextField(labelWithString: title)
        field.font = Self.font
        field.lineBreakMode = .byTruncatingTail
        place(field, Self.rect(x, y, w, h), id: id)
        return field
    }

    @discardableResult
    func combo(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, id: String) -> NSComboBox {
        let box = NSComboBox()
        box.font = Self.font
        box.controlSize = .small
        box.completes = false
        box.usesDataSource = false
        box.numberOfVisibleItems = 15
        var frame = Self.rect(x, y, w, 0)
        frame.size.height = 22
        place(box, frame, id: id)
        return box
    }

    @discardableResult
    func field(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, id: String) -> NSTextField {
        let field = NSTextField()
        field.font = Self.font
        field.controlSize = .small
        var frame = Self.rect(x, y, w, 0)
        frame.size.height = 21
        place(field, frame, id: id)
        return field
    }

    @discardableResult
    func check(_ title: String, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, id: String,
               target: AnyObject? = nil, action: Selector? = nil) -> NSButton {
        let button = NSButton(checkboxWithTitle: title, target: target, action: action)
        button.font = Self.font
        button.controlSize = .small
        place(button, Self.rect(x, y, w, 10), id: id)
        return button
    }

    @discardableResult
    func radio(_ title: String, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, id: String,
               target: AnyObject?, action: Selector?) -> NSButton {
        let button = NSButton(radioButtonWithTitle: title, target: target, action: action)
        button.font = Self.font
        button.controlSize = .small
        place(button, Self.rect(x, y, w, 10), id: id)
        return button
    }

    @discardableResult
    func button(_ title: String, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat = 14, id: String,
                target: AnyObject?, action: Selector?) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.font = Self.font
        button.controlSize = .small
        button.bezelStyle = .rounded
        place(button, Self.rect(x, y, w, h), id: id)
        return button
    }

    func group(_ title: String, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
        let box = NSBox()
        box.title = title
        box.titleFont = Self.font
        box.boxType = .primary
        place(box, Self.rect(x, y, w, h), id: "")
    }
}

/// 查找、置换对话框的共通部分
class SearchPanelBase: NSWindowController, NSWindowDelegate {
    /// App 不是活动的时候隐藏（浮动的面板不盖住别的 App）。单元测试时关掉
    static var hidesOnDeactivate = true
    weak var view: EditorTextView?
    let builder = DialogBuilder()
    /// 对话框打开时的光标（原版 m_ptEscCaretPos_PHY。检索开始位置）
    var escCaret = EditorPosition()
    /// 查找文字（原版 m_strText。关掉对话框后也保留，下次打开时用）
    var text = ""

    init(view: EditorTextView, title: String, size: NSSize) {
        self.view = view
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.titled, .closable], backing: .buffered, defer: true)
        panel.title = title
        panel.isFloatingPanel = true			// 与原版相同，总在编辑窗口的上面
        panel.hidesOnDeactivate = Self.hidesOnDeactivate
        panel.isReleasedWhenClosed = false
        builder.content.frame = NSRect(origin: .zero, size: size)
        panel.contentView = builder.content
        super.init(window: panel)
        panel.delegate = self
        // 编辑窗口关闭时一起关
        if let window = view.window {
            NotificationCenter.default.addObserver(self, selector: #selector(ownerWillClose(_:)),
                                                   name: NSWindow.willCloseNotification, object: window)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func ownerWillClose(_ notification: Notification) {
        close()
    }

    /// 显示在编辑窗口的右上（原版的对话框显示在上次的位置，初次是编辑窗口的中央附近）
    func show() {
        guard let panel = window else { return }
        if let owner = view?.window, !panel.isVisible {
            let frame = owner.frame
            panel.setFrameTopLeftPoint(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.maxY - 60))
        }
        panel.makeKeyAndOrderFront(nil)
    }

    /// 查找文字的历史放进组合框（原版 SetCombosList）
    static func setItems(_ combo: NSComboBox, _ items: [String], text: String) {
        combo.removeAllItems()
        combo.addItems(withObjectValues: items)
        if combo.stringValue != text { combo.stringValue = text }
    }

    /// 检索开始位置的登记（原版：对话框打开后第一次查找时登记）
    func registerSearchStart() {
        guard let view, view.searchState.registerStart else { return }
        view.searchState.startPosition = escCaret
        view.searchState.registerStart = false
    }

    /// 对话框打开时（原版 OnInitDialog）
    func prepareOpen() {
        guard let view else { return }
        escCaret = view.caret
        view.searchState.registerStart = true
    }

    @objc func cancel(_ sender: Any?) {
        close()
    }

    /// キャンセル・Esc で閉じる
    override func cancelOperation(_ sender: Any?) {
        close()
    }

    /// 关掉后焦点回到编辑区
    func windowWillClose(_ notification: Notification) {
        if let owner = view?.window, owner.isVisible {
            owner.makeKeyAndOrderFront(nil)
        }
    }

    static func on(_ button: NSButton) -> Bool { button.state == .on }
}

// MARK: - 検索（IDD_FIND）

final class FindPanelController: SearchPanelBase {
    private var combo: NSComboBox!
    private var wordCheck: NSButton!
    private var caseCheck: NSButton!
    private var regexCheck: NSButton!
    private var versionLabel: NSTextField!
    private var notifyCheck: NSButton!
    private var autoCloseCheck: NSButton!
    private var searchAllCheck: NSButton!

    init(view: EditorTextView) {
        super.init(view: view, title: L10n.tr("検索", comment: "IDD_FIND"), size: DialogBuilder.size(284, 93))
        let b = builder
        b.label(L10n.tr("条件", comment: "IDD_FIND"), 5, 6, 28)
        combo = b.combo(34, 4, 183, id: "findText")
        wordCheck = b.check(L10n.tr("単語単位で探す", comment: "IDD_FIND"), 5, 21, 180, id: "findWord")
        caseCheck = b.check(L10n.tr("英大文字と小文字を区別する", comment: "IDD_FIND"), 5, 32, 180, id: "findCase")
        regexCheck = b.check(L10n.tr("正規表現", comment: "IDD_FIND"), 5, 43, 56, id: "findRegex",
                             target: self, action: #selector(regexChanged(_:)))
        versionLabel = b.label("", 62, 44, 155, id: "findRegexVersion")
        notifyCheck = b.check(L10n.tr("見つからないときにメッセージを表示", comment: "IDD_FIND"), 5, 54, 210, id: "findNotify")
        autoCloseCheck = b.check(L10n.tr("検索ダイアログを自動的に閉じる", comment: "IDD_FIND"), 5, 65, 210, id: "findAutoClose")
        searchAllCheck = b.check(L10n.tr("先頭（末尾）から再検索する", comment: "IDD_FIND"), 5, 76, 210, id: "findSearchAll")
        b.button(L10n.tr("上検索", comment: "IDD_FIND"), 221, 4, 58, id: "findPrev",
                 target: self, action: #selector(searchPrev(_:)))
        let next = b.button(L10n.tr("下検索", comment: "IDD_FIND"), 221, 20, 58, id: "findNext",
                            target: self, action: #selector(searchNext(_:)))
        next.keyEquivalent = "\r"
        // 該当行マーク（第 44 步：ブックマーク）
        b.button(L10n.tr("該当行マーク", comment: "IDD_FIND"), 221, 38, 58, id: "findMark",
                 target: self, action: #selector(markLines(_:)))
        let cancel = b.button(L10n.tr("キャンセル", comment: "IDD_FIND"), 221, 57, 58, id: "findCancel",
                              target: self, action: #selector(cancel(_:)))
        cancel.keyEquivalent = "\u{1b}"
        // ヘルプは HTML ヘルプの移植（後のステップ）まで使えない
        let help = b.button(L10n.tr("ヘルプ", comment: "IDD_FIND"), 221, 73, 58, id: "findHelp", target: nil, action: nil)
        help.isEnabled = false
        window?.initialFirstResponder = combo
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// 打开（原版 Command_SEARCH_DIALOG → DoModeless → SetData）
    func open(text: String) {
        if !text.isEmpty { self.text = text }
        prepareOpen()
        let settings = EditorCore.searchSettings
        let options = settings.options
        caseCheck.state = options.contains(.matchCase) ? .on : .off
        wordCheck.state = options.contains(.wholeWord) ? .on : .off
        regexCheck.state = options.contains(.regularExpression) ? .on : .off
        versionLabel.stringValue = EditorCore.regexpVersion
        notifyCheck.state = settings.notifyNotFound ? .on : .off
        autoCloseCheck.state = settings.autoCloseFind ? .on : .off
        searchAllCheck.state = settings.searchAll ? .on : .off
        Self.setItems(combo, EditorCore.searchKeyHistory, text: self.text)
        updateEnabled()
        show()
        window?.makeFirstResponder(combo)
    }

    /// 已经打开时（原版：アクティブにして、検索文字列を設定）
    func activate(text: String) {
        combo.stringValue = text
        show()
        window?.makeFirstResponder(combo)
    }

    private func updateEnabled() {
        // 正規表現のときは「単語単位で探す」は使えない
        wordCheck.isEnabled = !Self.on(regexCheck)
    }

    @objc private func regexChanged(_ sender: Any?) {
        updateEnabled()
    }

    var options: EditorSearchOptions {
        var options: EditorSearchOptions = []
        if Self.on(caseCheck) { options.insert(.matchCase) }
        if Self.on(wordCheck) { options.insert(.wholeWord) }
        if Self.on(regexCheck) { options.insert(.regularExpression) }
        return options
    }

    /// 对话框的数据（原版 CDlgFind::GetData）。1：可以查找，0：查找文字是空的，-1：正则表达式有错误
    func getData() -> Int {
        let settings = EditorCore.searchSettings
        settings.notifyNotFound = Self.on(notifyCheck)
        settings.autoCloseFind = Self.on(autoCloseCheck)
        settings.searchAll = Self.on(searchAllCheck)
        EditorCore.searchSettings = settings
        text = combo.stringValue
        guard !text.isEmpty else { return 0 }
        let options = self.options
        guard EditorTextView.checkRegexpSyntax(text, options: options) else { return -1 }
        if (text as NSString).length < 260 {
            EditorCore.addSearchKey(text)
            let settings = EditorCore.searchSettings
            settings.options = options
            EditorCore.searchSettings = settings
        }
        view?.setSearchKey(text, options: options)
        Self.setItems(combo, EditorCore.searchKeyHistory, text: text)
        return 1
    }

    @objc func searchPrev(_ sender: Any?) { search(next: false) }
    @objc func searchNext(_ sender: Any?) { search(next: true) }

    /// 該当行マーク（原版 IDC_BUTTON_SETMARK → F_BOOKMARK_PATTERN）。検索ダイアログを自動的に閉じる
    @objc func markLines(_ sender: Any?) {
        guard getData() > 0 else { return }
        view?.recordKeyMacro(MacroHost.Code.bookmarkPattern)	// 第 45 步
        view?.bookmarkPattern(nil)
        if EditorCore.searchSettings.autoCloseFind { close() }
    }

    private func search(next: Bool) {
        let result = getData()
        if result > 0 {
            view?.recordKeyMacro(next ? MacroHost.Code.searchNext : MacroHost.Code.searchPrev)	// 第 45 步
            if next { view?.searchNextCommand() } else { view?.searchPrevCommand() }
            registerSearchStart()
            if EditorCore.searchSettings.autoCloseFind { close() }
        } else if result == 0 {
            EditorTextView.showMessage(L10n.tr("検索条件を指定してください。", comment: "STR_DLGFIND1"))
        }
    }
}

// MARK: - 置換（IDD_REPLACE）

final class ReplacePanelController: SearchPanelBase {
    private var combo: NSComboBox!
    private var combo2: NSComboBox!
    private var pasteCheck: NSButton!
    private var wordCheck: NSButton!
    private var caseCheck: NSButton!
    private var regexCheck: NSButton!
    private var versionLabel: NSTextField!
    private var consecutiveCheck: NSButton!
    private var notifyCheck: NSButton!
    private var autoCloseCheck: NSButton!
    private var searchAllCheck: NSButton!
    private var targetRadios: [NSButton] = []
    private var selectedAreaRadio: NSButton!
    private var allAreaRadio: NSButton!
    private var prevButton: NSButton!
    private var nextButton: NSButton!
    private var replaceButton: NSButton!
    /// 置換後の文字列（原版 m_strText2）と、取得したときの履歴の序号（m_nReplaceKeySequence）
    var text2 = ""
    private var replaceSequence = -1
    /// 最後のすべて置換の数（原版 m_nReplaceCnt）
    private(set) var replaceCount = 0

    init(view: EditorTextView) {
        super.init(view: view, title: L10n.tr("置換", comment: "IDD_REPLACE"), size: DialogBuilder.size(298, 149))
        let b = builder
        b.label(L10n.tr("置換前", comment: "IDD_REPLACE"), 5, 6, 37)
        combo = b.combo(43, 4, 191, id: "replaceText")
        b.label(L10n.tr("置換後", comment: "IDD_REPLACE"), 5, 21, 37)
        combo2 = b.combo(43, 19, 191, id: "replaceText2")
        pasteCheck = b.check(L10n.tr("クリップボードから貼り付ける", comment: "IDD_REPLACE"), 5, 41, 148, id: "replacePaste",
                             target: self, action: #selector(pasteChanged(_:)))
        wordCheck = b.check(L10n.tr("単語単位で探す", comment: "IDD_REPLACE"), 5, 52, 148, id: "replaceWord")
        caseCheck = b.check(L10n.tr("英大文字と小文字を区別する", comment: "IDD_REPLACE"), 5, 63, 148, id: "replaceCase")
        regexCheck = b.check(L10n.tr("正規表現", comment: "IDD_REPLACE"), 5, 74, 148, id: "replaceRegex",
                             target: self, action: #selector(optionChanged(_:)))
        versionLabel = b.label("", 15, 85, 138, id: "replaceRegexVersion")
        consecutiveCheck = b.check(L10n.tr("「すべて置換」は置換の繰返し", comment: "IDD_REPLACE"), 5, 95, 148, id: "replaceConsecutive")
        notifyCheck = b.check(L10n.tr("見つからないときにメッセージを表示", comment: "IDD_REPLACE"), 5, 107, 150, id: "replaceNotify")
        autoCloseCheck = b.check(L10n.tr("置換ダイアログを自動的に閉じる", comment: "IDD_REPLACE"), 5, 118, 150, id: "replaceAutoClose")
        searchAllCheck = b.check(L10n.tr("先頭（末尾）から再検索する", comment: "IDD_REPLACE"), 5, 129, 150, id: "replaceSearchAll")

        b.group(L10n.tr("置換対象", comment: "IDD_REPLACE"), 156, 37, 78, 62)
        let targets = [(L10n.tr("選択文字", comment: "IDD_REPLACE"), "replaceTargetSelection"),
                       (L10n.tr("選択始点挿入", comment: "IDD_REPLACE"), "replaceTargetInsert"),
                       (L10n.tr("選択終点追加", comment: "IDD_REPLACE"), "replaceTargetAdd"),
                       (L10n.tr("行削除", comment: "IDD_REPLACE"), "replaceTargetDeleteLine")]
        for (i, (title, id)) in targets.enumerated() {
            targetRadios.append(b.radio(title, 162, 49 + CGFloat(i) * 12, 68, id: id, target: self, action: #selector(targetChanged(_:))))
        }
        b.group(L10n.tr("範囲", comment: "IDD_REPLACE"), 156, 103, 78, 37)
        selectedAreaRadio = b.radio(L10n.tr("選択範囲", comment: "IDD_REPLACE"), 162, 115, 68, id: "replaceSelectedArea",
                                    target: self, action: #selector(areaChanged(_:)))
        allAreaRadio = b.radio(L10n.tr("ファイル全体", comment: "IDD_REPLACE"), 162, 127, 68, id: "replaceAllArea",
                               target: self, action: #selector(areaChanged(_:)))

        prevButton = b.button(L10n.tr("上検索", comment: "IDD_REPLACE"), 237, 4, 56, id: "replacePrev",
                              target: self, action: #selector(searchPrev(_:)))
        nextButton = b.button(L10n.tr("下検索", comment: "IDD_REPLACE"), 237, 19, 56, id: "replaceNext",
                              target: self, action: #selector(searchNext(_:)))
        nextButton.keyEquivalent = "\r"
        b.button(L10n.tr("該当行マーク", comment: "IDD_REPLACE"), 237, 38, 56, id: "replaceMark",
                 target: self, action: #selector(markLines(_:)))
        replaceButton = b.button(L10n.tr("置換", comment: "IDD_REPLACE"), 237, 57, 56, id: "replaceOne",
                                 target: self, action: #selector(replace(_:)))
        b.button(L10n.tr("すべて置換", comment: "IDD_REPLACE"), 237, 73, 56, id: "replaceAll",
                 target: self, action: #selector(replaceAll(_:)))
        let cancel = b.button(L10n.tr("キャンセル", comment: "IDD_REPLACE"), 237, 110, 56, id: "replaceCancel",
                              target: self, action: #selector(cancel(_:)))
        cancel.keyEquivalent = "\u{1b}"
        let help = b.button(L10n.tr("ヘルプ", comment: "IDD_REPLACE"), 237, 127, 56, id: "replaceHelp", target: nil, action: nil)
        help.isEnabled = false
        window?.initialFirstResponder = combo
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// 打开（原版 Command_REPLACE_DIALOG → DoModeless → OnInitDialog、SetData）。
    /// 置換対象は「選択文字」、「クリップボードから貼り付ける」は外して開く（原版相同）
    func open(text: String, selected: Bool) {
        if !text.isEmpty { self.text = text }
        if let first = EditorCore.replaceKeyHistory.first, replaceSequence < EditorCore.replaceKeySequence {
            text2 = first
        }
        prepareOpen()
        let settings = EditorCore.searchSettings
        let options = settings.options
        caseCheck.state = options.contains(.matchCase) ? .on : .off
        wordCheck.state = options.contains(.wholeWord) ? .on : .off
        regexCheck.state = options.contains(.regularExpression) ? .on : .off
        versionLabel.stringValue = EditorCore.regexpVersion
        consecutiveCheck.state = settings.consecutiveAll ? .on : .off
        notifyCheck.state = settings.notifyNotFound ? .on : .off
        autoCloseCheck.state = settings.autoCloseReplace ? .on : .off
        searchAllCheck.state = settings.searchAll ? .on : .off
        pasteCheck.state = .off
        for (i, radio) in targetRadios.enumerated() { radio.state = i == 0 ? .on : .off }
        selectedAreaRadio.state = selected ? .on : .off
        allAreaRadio.state = selected ? .off : .on
        Self.setItems(combo, EditorCore.searchKeyHistory, text: self.text)
        Self.setItems(combo2, EditorCore.replaceKeyHistory, text: text2)
        updateEnabled()
        show()
        window?.makeFirstResponder(combo)
    }

    func activate(text: String) {
        combo.stringValue = text
        show()
        window?.makeFirstResponder(combo)
    }

    private var target: EditorReplaceTarget {
        let index = targetRadios.firstIndex { $0.state == .on } ?? 0
        return EditorReplaceTarget(rawValue: index) ?? .selection
    }

    /// 控件的有效・无效（原版 OnBnClicked 的各 case）
    private func updateEnabled() {
        let regex = Self.on(regexCheck)
        wordCheck.isEnabled = !regex
        consecutiveCheck.isEnabled = regex
        let deleteLine = target == .deleteLine
        pasteCheck.isEnabled = !deleteLine
        combo2.isEnabled = !deleteLine && !Self.on(pasteCheck)
        let all = Self.on(allAreaRadio)
        prevButton.isEnabled = all
        nextButton.isEnabled = all
        replaceButton.isEnabled = all
    }

    @objc private func optionChanged(_ sender: Any?) { updateEnabled() }
    @objc private func targetChanged(_ sender: NSButton) {
        for radio in targetRadios { radio.state = radio === sender ? .on : .off }
        updateEnabled()
    }
    @objc private func areaChanged(_ sender: NSButton) {
        selectedAreaRadio.state = sender === selectedAreaRadio ? .on : .off
        allAreaRadio.state = sender === allAreaRadio ? .on : .off
        updateEnabled()
    }

    /// 「クリップボードから貼り付ける」：剪贴板是空的时显示消息，不打勾
    @objc private func pasteChanged(_ sender: Any?) {
        if Self.on(pasteCheck) && view?.clipboardText == nil {
            EditorTextView.showMessage(L10n.tr("クリップボードに有効なデータがありません！", comment: "STR_DLGREPLC_CLIPBOARD"))
            pasteCheck.state = .off
        }
        updateEnabled()
    }

    private var searchOptions: EditorSearchOptions {
        var options: EditorSearchOptions = []
        if Self.on(caseCheck) { options.insert(.matchCase) }
        if Self.on(wordCheck) { options.insert(.wholeWord) }
        if Self.on(regexCheck) { options.insert(.regularExpression) }
        return options
    }

    var replaceOptions: EditorReplaceOptions {
        EditorReplaceOptions(search: searchOptions, target: target,
                             paste: Self.on(pasteCheck) && target != .deleteLine,
                             searchAll: Self.on(searchAllCheck), consecutiveAll: Self.on(consecutiveCheck),
                             selectedArea: Self.on(selectedAreaRadio))
    }

    /// 对话框的数据（原版 CDlgReplace::GetData）。1：可以执行，0：置換前が空，-1：正则表达式有错误
    func getData() -> Int {
        let settings = EditorCore.searchSettings
        settings.consecutiveAll = Self.on(consecutiveCheck)
        settings.selectedArea = Self.on(selectedAreaRadio)
        settings.notifyNotFound = Self.on(notifyCheck)
        settings.autoCloseReplace = Self.on(autoCloseCheck)
        settings.searchAll = Self.on(searchAllCheck)
        EditorCore.searchSettings = settings
        text = combo.stringValue
        text2 = target == .deleteLine ? "" : combo2.stringValue
        guard !text.isEmpty else { return 0 }
        let options = searchOptions
        guard EditorTextView.checkRegexpSyntax(text, options: options) else { return -1 }
        if (text as NSString).length < 260 {
            EditorCore.addSearchKey(text)
            let settings = EditorCore.searchSettings
            settings.options = options
            EditorCore.searchSettings = settings
        }
        view?.setSearchKey(text, options: options)
        if (text2 as NSString).length < 260 {
            EditorCore.addReplaceKey(text2)
        }
        replaceSequence = EditorCore.replaceKeySequence
        Self.setItems(combo, EditorCore.searchKeyHistory, text: text)
        Self.setItems(combo2, EditorCore.replaceKeyHistory, text: text2)
        return 1
    }

    @objc func searchPrev(_ sender: Any?) { search(next: false) }
    @objc func searchNext(_ sender: Any?) { search(next: true) }

    /// 該当行マーク（原版 IDC_BUTTON_SETMARK → F_BOOKMARK_PATTERN）
    @objc func markLines(_ sender: Any?) {
        guard getData() > 0 else { return }
        view?.recordKeyMacro(MacroHost.Code.bookmarkPattern)	// 第 45 步
        view?.bookmarkPattern(nil)
    }

    private func search(next: Bool) {
        let result = getData()
        if result > 0 {
            registerSearchStart()
            view?.recordKeyMacro(next ? MacroHost.Code.searchNext : MacroHost.Code.searchPrev)	// 第 45 步
            if next { view?.searchNextCommand() } else { view?.searchPrevCommand() }
        } else if result == 0 {
            EditorTextView.showMessage(L10n.tr("文字列を指定してください。", comment: "STR_DLGREPLC_STR"))
        }
    }

    @objc func replace(_ sender: Any?) {
        let result = getData()
        if result > 0 {
            registerSearchStart()
            view?.recordKeyMacro(MacroHost.Code.replace, replace: (text2, replaceOptions))	// 第 45 步
            if view?.replaceCommand(text2, options: replaceOptions) == false {
                // 剪贴板是空的：「クリップボードから貼り付ける」を外す（原版 Command_REPLACE）
                pasteCheck.state = .off
                updateEnabled()
            }
        } else if result == 0 {
            EditorTextView.showMessage(L10n.tr("文字列を指定してください。", comment: "STR_DLGREPLC_STR"))
        }
    }

    @objc func replaceAll(_ sender: Any?) {
        let result = getData()
        if result > 0 {
            registerSearchStart()
            view?.recordKeyMacro(MacroHost.Code.replaceAll, replace: (text2, replaceOptions))	// 第 45 步
            guard let count = view?.replaceAllCommand(text2, options: replaceOptions) else {
                pasteCheck.state = .off
                updateEnabled()
                return
            }
            replaceCount = count
            EditorTextView.showMessage(String(format: L10n.tr("%d箇所を置換しました。", comment: "STR_DLGREPLC_REPLACE"), count))
            if EditorCore.searchSettings.autoCloseReplace { close() }
        } else if result == 0 {
            EditorTextView.showMessage(L10n.tr("置換条件を指定してください。", comment: "STR_DLGREPLC_REPSTR"))
        }
    }
}

// MARK: - 指定行へジャンプ（IDD_JUMP）

final class JumpDialogController: NSObject {
    /// 原版的 CDlgJump 是 CEditWnd 一个；前回の行番号を保持する。Mac 版是 App 一个（前回の行番号は全ウィンドウ共通）
    static let shared = JumpDialogController()

    /// 前回の行番号（0 は空欄）と PL/SQL の設定（原版 m_nLineNum、m_bPLSQL、m_nPLSQL_E1）
    private(set) var lineNumber = 0
    private(set) var plsql = false
    private(set) var plsqlFirstLine = 1

    private var sheet: NSWindow?
    private weak var view: EditorTextView?
    private var lineField: NSTextField!
    private var layoutRadio: NSButton!
    private var crlfRadio: NSButton!
    private var plsqlCheck: NSButton!
    private var plsqlField: NSTextField!
    private var plsqlLabels: [NSTextField] = []
    private var plsqlBlocks: NSComboBox!

    /// 表单を開く（原版 Command_JUMP_DIALOG → DoModal）
    func begin(for view: EditorTextView, in window: NSWindow) {
        guard sheet == nil else { return }
        self.view = view
        let b = DialogBuilder()
        let size = DialogBuilder.size(252, 121)
        b.content.frame = NSRect(origin: .zero, size: size)
        b.label(L10n.tr("行番号", comment: "IDD_JUMP"), 5, 6, 34)
        lineField = b.field(40, 4, 50, id: "jumpLine")
        layoutRadio = b.radio(L10n.tr("折り返し単位の行番号", comment: "IDD_JUMP"), 94, 5, 100, id: "jumpLayout",
                              target: self, action: #selector(unitChanged(_:)))
        crlfRadio = b.radio(L10n.tr("改行単位の行番号", comment: "IDD_JUMP"), 94, 20, 100, id: "jumpCRLF",
                            target: self, action: #selector(unitChanged(_:)))
        b.group(L10n.tr("PL/SQLコンパイルエラー行", comment: "IDD_JUMP"), 5, 35, 184, 80)
        plsqlCheck = b.check(L10n.tr("PL/SQLコンパイルエラー行を処理する", comment: "IDD_JUMP"), 10, 50, 170, id: "jumpPlsql",
                             target: self, action: #selector(plsqlChanged(_:)))
        plsqlLabels.append(b.label(L10n.tr("テキストの", comment: "IDD_JUMP"), 15, 66, 32))
        plsqlField = b.field(47, 64, 30, id: "jumpPlsqlLine")
        plsqlLabels.append(b.label(L10n.tr("行目をブロックの1行目とする", comment: "IDD_JUMP"), 80, 66, 105))
        plsqlLabels.append(b.label(L10n.tr("検出されたPL/SQLパッケージのブロックから選択", comment: "IDD_JUMP"), 15, 82, 170))
        // PL/SQL のブロック一覧はアウトライン解析（後のステップ）の移植まで空
        plsqlBlocks = b.combo(15, 94, 170, id: "jumpPlsqlBlocks")
        let jump = b.button(L10n.tr("ジャンプ", comment: "IDD_JUMP"), 197, 5, 50, id: "jumpOK",
                            target: self, action: #selector(jump(_:)))
        jump.keyEquivalent = "\r"
        let cancel = b.button(L10n.tr("キャンセル", comment: "IDD_JUMP"), 197, 24, 50, id: "jumpCancel",
                              target: self, action: #selector(cancel(_:)))
        cancel.keyEquivalent = "\u{1b}"
        let help = b.button(L10n.tr("ヘルプ", comment: "IDD_JUMP"), 197, 101, 50, id: "jumpHelp", target: nil, action: nil)
        help.isEnabled = false

        // SetData
        lineField.stringValue = lineNumber == 0 ? "" : String(lineNumber)
        plsqlField.stringValue = String(plsqlFirstLine)
        plsqlCheck.state = plsql ? .on : .off
        let crlf = EditorCore.searchSettings.jumpLineNumIsCRLF
        crlfRadio.state = crlf ? .on : .off
        layoutRadio.state = crlf ? .off : .on
        updateEnabled()

        let panel = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: true)
        panel.title = L10n.tr("指定行へジャンプ", comment: "IDD_JUMP")
        panel.contentView = b.content
        panel.initialFirstResponder = lineField
        sheet = panel
        window.beginSheet(panel) { [weak self] _ in self?.sheet = nil }
        panel.makeFirstResponder(lineField)
    }

    private func updateEnabled() {
        // PL/SQL のときは改行単位（原版 IDC_CHECK_PLSQL）
        let on = plsqlCheck.state == .on
        for label in plsqlLabels { label.textColor = on ? .labelColor : .disabledControlTextColor }
        plsqlField.isEnabled = on
        plsqlBlocks.isEnabled = on
        layoutRadio.isEnabled = !on
        crlfRadio.isEnabled = !on
        if on {
            crlfRadio.state = .on
            layoutRadio.state = .off
        }
    }

    @objc private func unitChanged(_ sender: NSButton) {
        layoutRadio.state = sender === layoutRadio ? .on : .off
        crlfRadio.state = sender === crlfRadio ? .on : .off
    }

    @objc private func plsqlChanged(_ sender: Any?) { updateEnabled() }

    /// 符号なし整数（原版 GetDlgItemInt の bSigned=FALSE）。数字以外は nil
    private static func unsigned(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int(trimmed)
    }

    /// 对话框的数据（原版 CDlgJump::GetData）。行番号が正しくないとき false
    private func getData() -> Bool {
        let settings = EditorCore.searchSettings
        settings.jumpLineNumIsCRLF = crlfRadio.state == .on
        EditorCore.searchSettings = settings
        plsql = plsqlCheck.state == .on
        plsqlFirstLine = Self.unsigned(plsqlField.stringValue) ?? 1
        guard let number = Self.unsigned(lineField.stringValue) else {
            lineNumber = 0
            return false
        }
        lineNumber = number
        return true
    }

    @objc private func jump(_ sender: Any?) {
        if getData() {
            end()
        } else {
            EditorTextView.showMessage(L10n.tr("正しく行番号を入力してください。", comment: "STR_DLGJUMP1"))
        }
        // 原版：行番号が正しくなくても指定行へジャンプは実行する（行番号 0 は 1 行目）
        let options = EditorJumpOptions(lineNumber: lineNumber, lineNumIsCRLF: EditorCore.searchSettings.jumpLineNumIsCRLF,
                                        plsql: plsql, plsqlBlockFirstLine: plsqlFirstLine)
        view?.recordKeyMacro(MacroHost.Code.jump, jump: options)	// 第 45 步
        view?.jumpCommand(options)
    }

    @objc private func cancel(_ sender: Any?) {
        end()
    }

    private func end() {
        guard let sheet, let parent = sheet.sheetParent else { return }
        parent.endSheet(sheet)
    }
}

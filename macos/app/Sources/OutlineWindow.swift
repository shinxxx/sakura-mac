// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge

/// アウトライン解析（第 42 步。原版 CDlgFuncList、CViewCommander_Outline.cpp）。
///
/// 解析和ツリー・リスト的内容在核心库（Document::AnalyzeOutline：原版 Command_FUNCLIST + CDlgFuncList::SetData），
/// 这里是窗口：布局照原版 IDD_FUNCLIST（Resources/OutlineDialogs.json），与原版相同地能改大小，
/// ツリー・リスト跟着变大，下面的按钮、复选框留在下边。
/// 一个编辑窗口一个，非模态（原版 DoModeless）。ドッキング（左・右・上・下）时，对话框的内容放进编辑窗口（OutlineDock.swift）。
final class OutlineWindowController: NSWindowController, NSWindowDelegate {
    /// App 不是活动的时候隐藏（浮动的面板不盖住别的 App）。单元测试时关掉
    static var hidesOnDeactivate = true
    /// 「コピー」の貼り付け先（単体テストでは別のペーストボード）
    static var pasteboard: NSPasteboard = .general

    weak var view: EditorTextView?
    let page: PropPage
    let treeView = OutlineTreeView()
    let listView = OutlineListView()
    private let treeData = OutlineTreeData()
    /// ファイルツリーのデータ（F_FILETREE のときツリーに使う）
    let fileTreeData = FileTreeData()
    private let listData = OutlineListData()

    /// 解析结果（原版 m_pcFuncInfoArr）
    private(set) var result: OutlineResult
    /// アウトライン解析の種別（原版 m_nOutlineType。同じ種別かどうかの判断に使う）
    private(set) var outlineType: OutlineType
    /// 解析结果是最新的（原版 m_bFuncInfoArrIsUpToDate：文档改了以后 false，不再跟着光标选择）
    private(set) var isUpToDate = true
    /// 现在的光标（排版位置 + 1。原版 m_nCurLine、m_nCurCol）
    private var curLine = 1
    private var curColumn = 1
    /// タイプ別設定の番号（原版 m_nDocType）
    private var typeIndex: Int
    /// ドッキング配置（原版 m_eDockSide：開いたときの配置）
    private(set) var dockSide: DockSide
    /// ドッキングしているときの表示（キャプション、分割バー）
    var dockView: OutlineDockView?
    /// ドッキングしている（原版 IsDocking）
    var isDocking: Bool { dockSide.isDocking }
    /// 開いている（フローティングは窓口が見えている、ドッキングは編集窓口の中にある）
    var isOpen: Bool { isDocking ? dockView?.superview != nil : window?.isVisible == true }
    /// 閉じた後（同じものをまた開かない）
    private(set) var destroyed = false

    /// 配置だけ変える（原版 ChangeLayout の m_eDockSide = eDockSideNew）
    func setDockSideWithoutLayout(_ side: DockSide) {
        dockSide = side
    }
    /// 「継承情報を統一」の確認（単体テストで差し替える）。OK なら true
    static var confirmHandler: ((String) -> Bool)?

    static let sortTitles = [
        L10n.tr("デフォルト", comment: "STR_DLGFNCLST_SORTTYPE1"),
        L10n.tr("デフォルト(降順)", comment: "STR_DLGFNCLST_SORTTYPE1_2"),
        L10n.tr("アルファベット順", comment: "STR_DLGFNCLST_SORTTYPE2"),
        L10n.tr("アルファベット(降順)", comment: "STR_DLGFNCLST_SORTTYPE2_2"),
    ]

    init?(view: EditorTextView, result: OutlineResult, outlineType: OutlineType) {
        guard let definition = PropDialogs.load("OutlineDialogs")?.dialog("IDD_FUNCLIST") else { return nil }
        self.view = view
        self.result = result
        self.outlineType = outlineType
        typeIndex = view.document.typeIndex
        dockSide = OutlineDockSettings.side(typeIndex: view.document.typeIndex)
        page = PropPage(definition: definition)
        let size = page.view.frame.size
        let panel = OutlinePanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: true)
        panel.isFloatingPanel = true			// 原版：编辑窗口拥有的窗口，总在编辑窗口的上面
        panel.hidesOnDeactivate = Self.hidesOnDeactivate
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = false
        // 原版 OnMinMaxInfo：最小是原来的宽 1/2、高 1/3，最大是 2 倍
        panel.contentMinSize = NSSize(width: (size.width / 2).rounded(), height: (size.height / 3).rounded())
        panel.contentMaxSize = NSSize(width: size.width * 2, height: size.height * 2)
        panel.contentView = page.view
        super.init(window: panel)
        panel.delegate = self
        panel.controller = self
        setUpControls()
        if isDocking { setUpDocking() }
        if let owner = view.window {
            NotificationCenter.default.addObserver(self, selector: #selector(ownerWillClose(_:)),
                                                   name: NSWindow.willCloseNotification, object: owner)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// 編集窓口が閉じる：一緒に閉じる（表示の設定は変えない。原版は編集窓口が先に見えなくなる）
    private var ownerClosing = false

    @objc private func ownerWillClose(_ notification: Notification) {
        ownerClosing = true
        close()
    }

    // MARK: - 控件

    private func setUpControls() {
        page.view.autoresizesSubviews = true
        // 原版 anchorList：ツリー・リストは四方、下の按钮・复选框は下、順序は上
        for view in page.view.subviews {
            view.autoresizingMask = [.maxXMargin, .maxYMargin]
        }
        for id in ["IDC_TREE_FL", "IDC_LIST_FL"] {
            page.control(id)?.autoresizingMask = [.width, .height]
        }
        for id in ["IDC_BUTTON_MENU", "IDC_BUTTON_WINSIZE", "IDC_BUTTON_COPY", "IDOK", "IDCANCEL", "IDC_BUTTON_HELP",
                   "IDC_CHECK_bAutoCloseDlgFuncList", "IDC_CHECK_bFunclistSetFocusOnJump", "IDC_CHECK_bMarkUpBlankLineEnable"] {
            page.control(id)?.autoresizingMask = [.maxXMargin, .minYMargin]
        }

        // ツリー（原版 IDC_TREE_FL）とリスト（IDC_LIST_FL）
        if let scroll = page.control("IDC_TREE_FL") as? NSScrollView {
            treeView.setUp(data: treeData, controller: self)
            scroll.documentView = treeView
            scroll.hasHorizontalScroller = true
        }
        if let scroll = page.control("IDC_LIST_FL") as? NSScrollView {
            listView.setUp(data: listData, controller: self)
            scroll.documentView = listView
            scroll.hasHorizontalScroller = true
        }

        // ▼（ウィンドウの位置メニュー）と ■（位置と大きさを記憶する。原版 BS_PUSHLIKE のチェックボックス）：
        // 原版は 10×14 の小さなボタン。Mac の角丸ボタンでは「▼」が入らないので、余白のない四角いボタンにする
        for (id, x) in [("IDC_BUTTON_MENU", 1.0), ("IDC_BUTTON_WINSIZE", 12.0)] {
            guard let button = page.control(id) as? NSButton else { continue }
            if id == "IDC_BUTTON_WINSIZE" { button.setButtonType(.pushOnPushOff) }
            button.isBordered = true
            button.bezelStyle = .smallSquare
            button.controlSize = .small
            button.font = PropPage.font
            button.imagePosition = .noImage
            let width = PropPage.pointsX(10)
            let height = PropPage.points(14)
            button.frame = NSRect(x: PropPage.pointsX(x), y: PropPage.points(255), width: width, height: height)
        }
        (page.control("IDOK") as? NSButton)?.keyEquivalent = "\r"		// DEFPUSHBUTTON
        (page.control("IDCANCEL") as? NSButton)?.keyEquivalent = "\u{1b}"
        page.setUnavailable(["IDC_BUTTON_HELP"], reason: L10n.tr("Mac 版にはまだヘルプがありません", comment: "help"))
        page.setItems("IDC_COMBO_nSortType", Self.sortTitles, selected: 0)

        page.onButton = { [weak self] id in self?.buttonClicked(id) }
        page.onChange = { [weak self] id in self?.controlChanged(id) }
    }

    // MARK: - 表示（原版 SetData）

    /// 显示解析结果（原版 DoModeless / Redraw → SetData）
    func setData(result: OutlineResult, outlineType: OutlineType) {
        self.result = result
        self.outlineType = outlineType
        isUpToDate = true
        if let view {
            let p = view.document.layoutPosition(of: view.caret)
            curLine = p.line + 1
            curColumn = p.x + 1
            typeIndex = view.document.typeIndex
        }
        setData()
    }

    /// 今の結果のまま描き直す（色が変わったとき）
    func redraw() {
        setData()
    }

    private func setData() {
        window?.title = result.title
        dockView?.caption.title.stringValue = result.title
        // 最後に開いたアウトラインの種類（原版 DoModeless・Redraw の m_nDockOutline）
        OutlineDockSettings.setDockOutline(outlineType.rawValue, typeIndex: typeIndex)

        // 共通設定の項目（アウトライン ダイアログを自動的に閉じる 等）
        let autoClose = Self.commonBool("bAutoCloseDlgFuncList")
        page.setChecked("IDC_CHECK_bAutoCloseDlgFuncList", autoClose)
        page.setChecked("IDC_CHECK_bMarkUpBlankLineEnable", Self.commonBool("bMarkUpBlankLineEnable"))
        page.setChecked("IDC_CHECK_bFunclistSetFocusOnJump", Self.commonBool("bFunclistSetFocusOnJump"))
        updateWinSizeButton()
        // ダイアログを自動的に閉じるならフォーカス移動オプションは関係ない
        page.setEnabled("IDC_CHECK_bFunclistSetFocusOnJump", !autoClose)
        // 空行をどう扱うかのチェックボックスはブックマーク一覧のときだけ表示する
        page.showEnable("IDC_CHECK_bMarkUpBlankLineEnable", show: result.listType == .bookmark && !isDocking, enable: result.listType == .bookmark)
        // 「設定」ボタンはファイルツリーのときだけ（原版 SetData の OUTLINE_FILETREE）
        page.control("IDC_BUTTON_SETTING")?.isHidden = result.listType != .fileTree
        page.setEnabled("IDC_BUTTON_COPY", true)

        // ツリー表示の時だけソート基準コンボボックスを表示
        let showSort = result.isTree && result.listType != .fileTree
        page.showEnable("IDC_COMBO_nSortType", show: showSort, enable: showSort)
        page.control("IDC_STATIC_nSortType")?.isHidden = !showSort
        page.label(L10n.tr("順序(S)", comment: "IDD_FUNCLIST"))?.isHidden = !showSort
        if showSort { page.select("IDC_COMBO_nSortType", result.sort.rawValue) }

        syncColor()	// 色はツリー・リストを作る前に（作り直すと選択が消える）
        page.control("IDC_TREE_FL")?.isHidden = !result.isTree
        page.control("IDC_LIST_FL")?.isHidden = result.isTree
        if result.listType == .fileTree {
            fileTreeData.window = isDocking ? view?.window : window
            fileTreeData.load(FileTreeDialogController.loadSetting(typeIndex: typeIndex, folder: fileTreeFolder), folder: fileTreeFolder)
            treeView.dataSource = fileTreeData
            treeView.delegate = fileTreeData
            treeView.reloadData()
        } else if result.isTree {
            treeView.dataSource = treeData
            treeView.delegate = treeData
            treeData.load(result.tree)
            treeView.reloadData()
            treeData.expandInitial(treeView)
        } else {
            listData.load(result)
            listView.reload(columnTitles: result.columnTitles)
        }

        // 選択状態更新
        let index = result.item(atLayoutLine: curLine, column: curColumn)
        if index >= 0 { setItemSelection(index, allowExpand: true) }
        let host = isDocking ? view?.window : window
        if host?.isKeyWindow == true, let responder = host?.firstResponder as? NSView, responder.isDescendant(of: page.view) {
            host?.makeFirstResponder(result.isTree ? treeView : listView)
        } else if !isDocking, window?.isKeyWindow == true {
            window?.makeFirstResponder(result.isTree ? treeView : listView)
        }
    }

    static func commonBool(_ key: String) -> Bool {
        (EditorCore.commonSetting(section: "Common", key: key) ?? "0") != "0"
    }

    static func setCommon(_ key: String, _ value: Bool) {
        _ = EditorCore.setCommonSetting(value ? "1" : "0", section: "Common", key: key)
    }

    private func updateWinSizeButton() {
        guard let button = page.control("IDC_BUTTON_WINSIZE") as? NSButton else { return }
        let remember = Self.commonBool("bRememberOutlineWindowPos")
        button.state = remember ? .on : .off
        // ボタンが押されているかはっきりさせる
        button.title = remember ? "■" : "□"
    }

    // MARK: - 選択（原版 SetItemSelection）

    /// この項目を選ぶ。allowExpand が false のときは閉じている親を開かず、見えている一番近い親を選ぶ
    func setItemSelection(_ item: Int, allowExpand: Bool) {
        if result.isTree {
            treeData.select(item: item, in: treeView, path: result.nodePath(forItem: item).map { $0.intValue }, allowExpand: allowExpand)
        } else {
            listData.select(item: item, in: listView)
        }
    }

    /// キャレットの移動を通知（原版 NotifyCaretMovement）
    func notifyCaretMovement(line: Int, column: Int) {
        guard isOpen, isUpToDate else { return }
        guard curLine != line || curColumn != column else { return }
        curLine = line
        curColumn = column
        let index = result.item(atLayoutLine: line, column: column)
        if index >= 0 { setItemSelection(index, allowExpand: false) }
    }

    /// ドキュメントの変更を通知（原版 NotifyDocModification）
    func notifyDocModification() {
        isUpToDate = false
    }

    // MARK: - ボタン（原版 OnBnClicked）

    private func buttonClicked(_ id: String) {
        switch id {
        case "IDC_BUTTON_MENU":
            guard let button = page.control("IDC_BUTTON_MENU") else { return }
            let menu = makeMenu(dropDown: true)
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.frame.height + 2), in: button)
        case "IDOK":
            jump()
        case "IDCANCEL":
            cancel()
        case "IDC_BUTTON_COPY":
            copyToPasteboard()
        case "IDC_BUTTON_SETTING":
            showFileTreeSettings()
        default:
            break
        }
    }

    private func controlChanged(_ id: String) {
        switch id {
        case "IDC_BUTTON_WINSIZE":
            // ウィンドウの位置とサイズを記憶
            let on = (page.control(id) as? NSButton)?.state == .on
            Self.setCommon("bRememberOutlineWindowPos", on)
            updateWinSizeButton()
        case "IDC_CHECK_bAutoCloseDlgFuncList", "IDC_CHECK_bMarkUpBlankLineEnable", "IDC_CHECK_bFunclistSetFocusOnJump":
            let autoClose = page.isChecked("IDC_CHECK_bAutoCloseDlgFuncList")
            Self.setCommon("bAutoCloseDlgFuncList", autoClose)
            Self.setCommon("bMarkUpBlankLineEnable", page.isChecked("IDC_CHECK_bMarkUpBlankLineEnable"))
            Self.setCommon("bFunclistSetFocusOnJump", page.isChecked("IDC_CHECK_bFunclistSetFocusOnJump"))
            page.setEnabled("IDC_CHECK_bFunclistSetFocusOnJump", !autoClose)
            // オプション切替後 List/Tree にフォーカス移動
            window?.makeFirstResponder(result.isTree ? treeView : listView)
        case "IDC_COMBO_nSortType":
            // 原版 OnCbnSelEndOk：順序を変えてタイプ別設定に記憶
            let index = page.selectedIndex(id)
            guard let sort = OutlineSort(rawValue: index), sort != result.sort else { return }
            _ = EditorCore.setCommonSetting(String(index), section: "Types(\(typeIndex))", key: "nOutlineSortType")
            sortTree(sort)
        default:
            break
        }
    }

    /// ツリーの順序を変える（開いている項目、選択はそのまま）
    func sortTree(_ sort: OutlineSort) {
        let expanded = treeData.expandedOrders(treeView)
        let selected = treeData.selectedOrder(treeView)
        result.sortTree(sort)
        treeData.load(result.tree)
        treeView.reloadData()
        treeData.restore(treeView, expanded: expanded, selected: selected)
    }

    /// リストの列名をクリック（原版 LVN_COLUMNCLICK）：同じ列は昇順・降順を切り替え、タイプ別設定に記憶
    func sortList(column: Int) {
        let descending = column == result.sortColumn ? !result.sortDescending : result.sortDescending
        _ = EditorCore.setCommonSettings(["nOutlineSortCol": String(column), "bOutlineSortDesc": descending ? "1" : "0"],
                                         section: "Types(\(typeIndex))")
        let selected = listData.selectedItem(listView)
        result.sortRows(column: column, descending: descending)
        listData.load(result)
        listView.reload(columnTitles: result.columnTitles)
        if let selected { listData.select(item: selected, in: listView) }
    }

    func copyToPasteboard() {
        guard page.isEnabled("IDC_BUTTON_COPY") else { return }
        let pasteboard = Self.pasteboard
        pasteboard.clearContents()
        pasteboard.setString(result.clipText, forType: .string)
    }

    // MARK: - ジャンプ（原版 OnJump）

    /// 選んでいる項目（原版 GetData）。クラス名等の項目は nil
    var selectedItem: OutlineItem? {
        let index = result.isTree ? treeData.selectedItem(treeView) : listData.selectedItem(listView)
        guard let index, result.items.indices.contains(index) else { return nil }
        return result.items[index]
    }

    /// 選んでいる項目へカーソルを移動する。checkAutoClose：「自動的に閉じる」「フォーカスを移す」を見る
    func jump(checkAutoClose: Bool = true) {
        if result.listType == .fileTree {
            jumpToFile(checkAutoClose: checkAutoClose)
            return
        }
        guard let item = selectedItem, let view else { return }
        // 別のファイルの項目（ファイルツリー、タグジャンプ付きのプラグイン）は Mac 版にはまだない
        guard item.fileName.isEmpty else { return }
        view.jumpFromOutline(line: item.line - 1, column: item.column - 1)
        guard checkAutoClose else { return }
        if isDocking {
            // 原版 MYWM_SETACTIVEPANE（PostMessage）：ダブルクリックの処理が終わってから編集画面へ
            if let type = NSApp.currentEvent?.type, type == .leftMouseDown || type == .leftMouseUp {
                focusEditorAfterClick = true
            } else {
                DispatchQueue.main.async { [weak self] in self?.focusEditor() }
            }
        } else if Self.commonBool("bAutoCloseDlgFuncList") {
            close()
            focusEditor()
        } else if Self.commonBool("bFunclistSetFocusOnJump") {
            focusEditor()
        }
    }

    /// クリックの処理（ツリー・リストの mouseDown）が終わったら編集画面へ
    var focusEditorAfterClick = false

    func focusEditor() {
        guard let view, let owner = view.window else { return }
        owner.makeKeyAndOrderFront(nil)
        owner.makeFirstResponder(view)
    }

    // MARK: - キー（原版 Key2Command）

    /// ツリー・リストでのキー入力：割り当てられた機能のうち、再解析・コピーだけ行う。処理したら true
    func handleKey(_ event: NSEvent) -> Bool {
        let code = KeyCommands.command(for: event)
        switch code {
        case 30930, 30931:	// F_OUTLINE、F_OUTLINE_TOGGLE：フォーカスがあるときはリロード
            reload()
            return true
        case 30601, 30602:	// F_CUT、F_COPY
            copyToPasteboard()
            return true
        default:
            return false
        }
    }

    /// 再解析（原版 HandleCommand( F_OUTLINE, true, SHOW_RELOAD )）
    func reload() {
        view?.outlineCommand(action: .reload, type: Self.redrawType(outlineType))
    }

    /// 再表示の種別（原版 GetOutlineTypeRedraw）：ブックマーク・ファイルツリーはそのまま、ほかは標準
    static func redrawType(_ type: OutlineType) -> OutlineType {
        type == .bookmark || type == .fileTree ? type : .default
    }

    // MARK: - ファイルツリー（原版 OnJump の m_sJumpFile、IDC_BUTTON_SETTING）

    /// 相対パスの起点
    var fileTreeFolder: String {
        view?.fileTreeBaseFolder ?? GrepDialogController.homeFolder
    }

    /// ファイルを開く（原版 TagJumpTimer → TagJumpSub：開いていればその窓口、無ければ開く）
    private func jumpToFile(checkAutoClose: Bool) {
        guard let path = fileTreeData.selectedFile(treeView) else { return }
        let folder = (path as NSString).deletingLastPathComponent
        // 「ファイル挿入」で選んだファイルは書签で開ける（開いている間は権限を持ったまま）
        let bookmarked = BookmarkStore.settingFiles.resolve(path: path)?.startAccessingSecurityScopedResource() ?? false
        if !bookmarked, !FolderAccess.shared.startAccess(file: path), !FolderAccess.doesNotExist(folder) {
            guard FolderAccess.shared.ensureAccess(paths: [folder], parent: isDocking ? view?.window : window,
                                                   message: FileTreeData.accessMessage) else { return }
        }
        EditorTextView.openForTagJump(URL(fileURLWithPath: path)) { [weak self] document, error in
            guard let opened = (document as? SakuraDocument)?.editorWindowController?.textView else {
                if let error { NSApp.presentError(error) }
                return
            }
            opened.window?.makeKeyAndOrderFront(nil)
            // 原版 OnTimer：アウトライン ダイアログを自動的に閉じる（フローティングのとき）
            guard let self, checkAutoClose, !self.isDocking, Self.commonBool("bAutoCloseDlgFuncList") else { return }
            self.close()
        }
    }

    /// 「設定」ボタン（原版 IDC_BUTTON_SETTING）：ファイルツリー設定。OK なら読み直す（HandleCommand( F_FILETREE, SHOW_RELOAD )）
    func showFileTreeSettings() {
        guard let view, let dialog = FileTreeDialogController(typeIndex: typeIndex, folder: fileTreeFolder) else { return }
        if dialog.runModal(parent: isDocking ? view.window : window) {
            view.outlineCommand(action: .reload, type: .fileTree)
        }
    }

    // MARK: - メニュー（原版 DoMenu）

    /// dropDown：「▼」ボタン（ウィンドウの位置だけ）。false は右クリック
    func makeMenu(dropDown: Bool) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        var positionMenu = menu
        if !dropDown {
            menu.addItem(item(L10n.tr("更新(U)", comment: "STR_DLGFNCLST_MENU_UPDATE"), #selector(menuUpdate(_:))))
            let copy = item(L10n.tr("コピー(C)", comment: "STR_DLGFNCLST_MENU_COPY"), #selector(menuCopy(_:)))
            copy.isEnabled = page.isEnabled("IDC_BUTTON_COPY")
            menu.addItem(copy)
            if result.isTree {
                menu.addItem(.separator())
                menu.addItem(item(L10n.tr("すべて展開(E)", comment: "STR_DLGFNCLST_MENU_EXPAND"), #selector(menuExpandAll(_:))))
                menu.addItem(item(L10n.tr("すべて縮小(O)", comment: "STR_DLGFNCLST_MENU_COLLAPSE"), #selector(menuCollapseAll(_:))))
            }
            menu.addItem(.separator())
            let position = NSMenuItem(title: L10n.tr("ウィンドウの位置(W)", comment: "STR_DLGFNCLST_MENU_WINPOS"), action: nil, keyEquivalent: "")
            positionMenu = NSMenu()
            positionMenu.autoenablesItems = false
            position.submenu = positionMenu
            menu.addItem(position)
        }
        // ドッキング配置（設定上の配置にチェック）
        let current = OutlineDockSettings.side(typeIndex: typeIndex)
        let sides: [(DockSide, String)] = [
            (.left, L10n.tr("左ドッキング(L)", comment: "STR_DLGFNCLST_MENU_LEFTDOC")),
            (.right, L10n.tr("右ドッキング(R)", comment: "STR_DLGFNCLST_MENU_RIGHTDOC")),
            (.top, L10n.tr("上ドッキング(T)", comment: "STR_DLGFNCLST_MENU_TOPDOC")),
            (.bottom, L10n.tr("下ドッキング(B)", comment: "STR_DLGFNCLST_MENU_BOTDOC")),
            (.float, L10n.tr("フローティング(F)", comment: "STR_DLGFNCLST_MENU_FLOATING")),
            (.undockable, L10n.tr("ドッキング禁止(I)", comment: "STR_DLGFNCLST_MENU_NODOCK")),
        ]
        for (side, title) in sides {
            let sideItem = item(title, #selector(menuDockSide(_:)))
            sideItem.tag = side.rawValue
            sideItem.state = side == current ? .on : .off
            positionMenu.addItem(sideItem)
        }
        positionMenu.addItem(.separator())
        let sync = item(L10n.tr("ドッキング配置を同期(S)", comment: "STR_DLGFNCLST_MENU_SYNC"), #selector(menuSync(_:)))
        sync.state = OutlineDockSettings.sync ? .on : .off
        positionMenu.addItem(sync)
        positionMenu.addItem(.separator())
        let inheritCommon = item(L10n.tr("ドッキング配置を共通継承(C)", comment: "STR_DLGFNCLST_MENU_INHERIT"), #selector(menuInherit(_:)))
        inheritCommon.tag = 0
        let inheritType = item(L10n.tr("ドッキング配置をタイプ別継承(Y)", comment: "STR_DLGFNCLST_MENU_TYPE"), #selector(menuInherit(_:)))
        inheritType.tag = 1
        (OutlineDockSettings.useType ? inheritType : inheritCommon).state = .on
        positionMenu.addItem(inheritCommon)
        positionMenu.addItem(inheritType)
        positionMenu.addItem(.separator())
        positionMenu.addItem(item(L10n.tr("継承情報を統一(U)", comment: "STR_DLGFNCLST_MENU_UNIFY"), #selector(menuUnify(_:))))
        if !dropDown {
            menu.addItem(.separator())
            menu.addItem(item(L10n.tr("閉じる(X)", comment: "STR_DLGFNCLST_MENU_CLOSE"), #selector(menuClose(_:))))
        }
        return menu
    }

    private func item(_ title: String, _ action: Selector?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc func menuUpdate(_ sender: Any?) { reload() }
    @objc func menuCopy(_ sender: Any?) { copyToPasteboard() }
    @objc func menuClose(_ sender: Any?) { close() }
    @objc func menuExpandAll(_ sender: Any?) {
        if result.listType == .fileTree {
            fileTreeData.expandAll(treeView)
        } else {
            treeView.expandItem(nil, expandChildren: true)
        }
    }
    @objc func menuCollapseAll(_ sender: Any?) { treeView.collapseItem(nil, collapseChildren: true) }

    // MARK: - 窗口

    /// 显示（原版 DoModeless）：「位置と大きさを記憶する」时在上次的位置（编辑窗口的左上为基准），否则在编辑窗口的中央
    func show(focus: Bool = true) {
        if !isOpen && !destroyed { opened() }
        if isDocking {
            showDocked(focus: focus)
            return
        }
        guard let panel = window else { return }
        if !panel.isVisible, let owner = view?.window {
            let frame = owner.frame
            if Self.commonBool("bRememberOutlineWindowPos"), let saved = Self.savedFrame(owner: frame) {
                panel.setFrame(saved, display: false)
            } else {
                panel.setFrameTopLeftPoint(NSPoint(x: frame.midX - panel.frame.width / 2,
                                                   y: frame.midY + panel.frame.height / 2))
            }
        }
        if focus {
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(result.isTree ? treeView : listView)
        } else {
            panel.orderFront(nil)
        }
    }

    /// 記憶した位置（共通設定 xOutlineWindowPos 等：编辑窗口左上からの距離と大きさ、点）
    static func savedFrame(owner: NSRect) -> NSRect? {
        func value(_ key: String) -> Int? { Int(EditorCore.commonSetting(section: "Common", key: key) ?? "") }
        guard let x = value("xOutlineWindowPos"), let y = value("yOutlineWindowPos"),
              let width = value("widthOutlineWindow"), let height = value("heightOutlineWindow"),
              width > 0, height > 0 else { return nil }
        return NSRect(x: owner.minX + CGFloat(x), y: owner.maxY - CGFloat(y) - CGFloat(height), width: CGFloat(width), height: CGFloat(height))
    }

    /// 閉じるとき（原版 OnDestroy）：「位置と大きさを記憶する」なら位置と大きさを記憶
    func windowWillClose(_ notification: Notification) {
        guard !isDocking else { return }
        if Self.commonBool("bRememberOutlineWindowPos"), let panel = window, let owner = view?.window {
            let frame = panel.frame, base = owner.frame
            _ = EditorCore.setCommonSettings([
                "xOutlineWindowPos": String(Int((frame.minX - base.minX).rounded())),
                "yOutlineWindowPos": String(Int((base.maxY - frame.maxY).rounded())),
                "widthOutlineWindow": String(Int(frame.width.rounded())),
                "heightOutlineWindow": String(Int(frame.height.rounded())),
            ], section: "Common")
        }
        destroy()
    }

    /// 閉じる（原版 DestroyWindow）
    override func close() {
        guard !destroyed else { return }
        if isDocking {
            dockView?.removeFromSuperview()
            container?.dock = nil
            destroy()
        } else {
            super.close()
            destroy()
        }
    }

    /// Esc・キャンセル（原版 IDCANCEL）：ドッキングは編集画面へ、フローティングは閉じる
    func cancel() {
        if isDocking { focusEditor() } else { close() }
    }

    override func cancelOperation(_ sender: Any?) {
        cancel()
    }

    /// 開いたとき（原版 OnInitDialog）：表示の設定を ON（ChangeLayout の中は変えない）、同期ならほかの窓口へ通知
    private func opened() {
        guard let view, !view.outlineChangingLayout else { return }
        OutlineDockSettings.setDisplay(true, typeIndex: typeIndex)
        if OutlineDockSettings.sync { view.notifyOutlineToOthers() }
    }

    /// 閉じたとき（原版 OnDestroy）：明示的に閉じたときだけ表示の設定を OFF、同期ならほかの窓口へ通知
    private func destroy() {
        guard !destroyed else { return }
        destroyed = true
        guard let view else { return }
        if view.outlinePanel === self { view.outlinePanel = nil }
        if !ownerClosing && view.window?.isVisible == true && !view.outlineChangingLayout {
            OutlineDockSettings.setDisplay(false, typeIndex: typeIndex)
            if OutlineDockSettings.sync { view.notifyOutlineToOthers() }
        }
    }
}

// MARK: - ツリー

/// ツリーの一項目
final class OutlineTreeItem {
    let node: OutlineNode
    let children: [OutlineTreeItem]
    weak var parent: OutlineTreeItem?

    init(_ node: OutlineNode) {
        self.node = node
        children = node.children.map { OutlineTreeItem($0) }
        for child in children { child.parent = self }
    }
}

/// ツリーのデータ（原版 IDC_TREE_FL の項目）
final class OutlineTreeData: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
    private(set) var roots: [OutlineTreeItem] = []

    func load(_ tree: [OutlineNode]) {
        roots = tree.map { OutlineTreeItem($0) }
    }

    /// 最初に開いている項目（原版 SetTreeJava の第一層の TreeView_Expand）
    func expandInitial(_ outline: NSOutlineView) {
        func walk(_ items: [OutlineTreeItem]) {
            for item in items {
                if item.node.expanded { outline.expandItem(item) }
                walk(item.children)
            }
        }
        walk(roots)
    }

    /// パスの項目
    func item(at path: [Int]) -> OutlineTreeItem? {
        var items = roots
        var found: OutlineTreeItem?
        for index in path {
            guard items.indices.contains(index) else { return nil }
            found = items[index]
            items = items[index].children
        }
        return found
    }

    /// この項目を選ぶ（原版 SetItemSelectionForTreeView）。項目がないときは何もしない
    func select(item: Int, in outline: NSOutlineView, path: [Int], allowExpand: Bool) {
        guard let found = self.item(at: path) else { return }
        var ancestors: [OutlineTreeItem] = []
        var parent = found.parent
        while let p = parent {
            ancestors.insert(p, at: 0)
            parent = p.parent
        }
        var target = found
        if allowExpand {
            for ancestor in ancestors { outline.expandItem(ancestor) }
        } else {
            // 未展開のアイテムは勝手に開けないよう、見えている一番近い項目を選ぶ
            for ancestor in ancestors where !outline.isItemExpanded(ancestor) {
                target = ancestor
                break
            }
        }
        let row = outline.row(forItem: target)
        guard row >= 0 else { return }
        outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        outline.scrollRowToVisible(row)
    }

    /// 選んでいる項目の items の番号（クラス名等は nil）
    func selectedItem(_ outline: NSOutlineView) -> Int? {
        guard let item = outline.item(atRow: outline.selectedRow) as? OutlineTreeItem, item.node.item >= 0 else { return nil }
        return item.node.item
    }

    func selectedOrder(_ outline: NSOutlineView) -> Int? {
        (outline.item(atRow: outline.selectedRow) as? OutlineTreeItem)?.node.order
    }

    /// 開いている項目（並べ替えの前後で同じにする）
    func expandedOrders(_ outline: NSOutlineView) -> Set<Int> {
        var result = Set<Int>()
        func walk(_ items: [OutlineTreeItem]) {
            for item in items where !item.children.isEmpty {
                if outline.isItemExpanded(item) { result.insert(item.node.order) }
                walk(item.children)
            }
        }
        walk(roots)
        return result
    }

    func restore(_ outline: NSOutlineView, expanded: Set<Int>, selected: Int?) {
        var selectedItem: OutlineTreeItem?
        func walk(_ items: [OutlineTreeItem]) {
            for item in items {
                if expanded.contains(item.node.order) { outline.expandItem(item) }
                if item.node.order == selected { selectedItem = item }
                walk(item.children)
            }
        }
        walk(roots)
        if let selectedItem {
            let row = outline.row(forItem: selectedItem)
            if row >= 0 {
                outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                outline.scrollRowToVisible(row)
            }
        }
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        (notification.object as? OutlineTreeView)?.fitColumn()
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        (notification.object as? OutlineTreeView)?.fitColumn()
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        (item as? OutlineTreeItem)?.children.count ?? roots.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        (item as? OutlineTreeItem)?.children[index] ?? roots[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        !((item as? OutlineTreeItem)?.children.isEmpty ?? true)
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        OutlineCell(text: (item as? OutlineTreeItem)?.node.label ?? "", color: (outlineView as? OutlineTreeView)?.textColor)
    }

    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        OutlineRowView(back: (outlineView as? OutlineTreeView)?.textColor == nil ? nil : outlineView.backgroundColor)
    }
}

/// アウトラインのツリー（原版 IDC_TREE_FL）
final class OutlineTreeView: NSOutlineView {
    weak var controller: OutlineWindowController?
    /// 文字の色（ドッキングのときは編集画面の色。nil は標準）
    var textColor: NSColor?

    func setUp(data: OutlineTreeData, controller: OutlineWindowController) {
        self.controller = controller
        headerView = nil
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("0"))
        column.minWidth = 40
        column.maxWidth = 10000
        addTableColumn(column)
        outlineTableColumn = column
        columnAutoresizingStyle = .noColumnAutoresizing
        rowHeight = 17
        allowsMultipleSelection = false
        allowsEmptySelection = true
        autoresizesOutlineColumn = false
        dataSource = data
        delegate = data
        target = self
        doubleAction = #selector(doubleClicked(_:))
        setAccessibilityIdentifier("IDC_TREE_FL_outline")
    }

    /// 列の幅を見えている項目の文字が全部入る幅にする（原版の TreeView は横にスクロールして全部見える）
    func fitColumn() {
        guard let column = outlineTableColumn else { return }
        var width: CGFloat = 0
        for row in 0..<numberOfRows {
            guard let label = (item(atRow: row) as? OutlineTreeItem)?.node.label ?? (item(atRow: row) as? FileTreeNode)?.label else { continue }
            let text = label as NSString
            let indent = CGFloat(level(forRow: row) + 1) * indentationPerLevel + 16
            width = max(width, indent + ceil(text.size(withAttributes: [.font: PropPage.font]).width) + 8)
        }
        let visible = enclosingScrollView?.contentSize.width ?? 0
        column.width = max(width, visible - 4)
    }

    override func reloadData() {
        super.reloadData()
        fitColumn()
    }

    override func resize(withOldSuperviewSize oldSize: NSSize) {
        super.resize(withOldSuperviewSize: oldSize)
        fitColumn()
    }

    override func expandItem(_ item: Any?, expandChildren: Bool) {
        super.expandItem(item, expandChildren: expandChildren)
        fitColumn()
    }

    override func collapseItem(_ item: Any?, collapseChildren: Bool) {
        super.collapseItem(item, collapseChildren: collapseChildren)
        fitColumn()
    }

    /// ダブルクリック（原版 NM_DBLCLK）：ジャンプ。ツリーの展開／縮小はしない
    @objc private func doubleClicked(_ sender: Any?) {
        guard clickedRow >= 0 else { return }
        controller?.jump()
    }

    /// シングルクリック（ドッキングのときだけ動作。原版 NM_CLICK）
    @objc func singleClicked(_ sender: Any?) {
        guard clickedRow >= 0 else { return }
        controller?.singleClicked()
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        if let controller, controller.focusEditorAfterClick {
            controller.focusEditorAfterClick = false
            controller.focusEditor()
        }
    }

    override func keyDown(with event: NSEvent) {
        if outlineKeyDown(event, controller: controller) { return }
        super.keyDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let row = self.row(at: convert(event.locationInWindow, from: nil))
        if row >= 0 { selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        return controller?.makeMenu(dropDown: false)
    }

    @objc func copy(_ sender: Any?) { controller?.copyToPasteboard() }
    @objc func cut(_ sender: Any?) { controller?.copyToPasteboard() }
}

/// ツリー・リスト共通のキー（原版 TVN_KEYDOWN / LVN_KEYDOWN）：スペースはジャンプ（自動的に閉じない）、
/// Return はジャンプ（DEFPUSHBUTTON）、その他は割り当てられた機能（Key2Command）
private func outlineKeyDown(_ event: NSEvent, controller: OutlineWindowController?) -> Bool {
    guard let controller else { return false }
    let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
    if flags.isEmpty, event.charactersIgnoringModifiers == " " {
        controller.jump(checkAutoClose: false)
        return true
    }
    if flags.isEmpty, event.charactersIgnoringModifiers == "\r" || event.keyCode == 76 {
        controller.jump()
        return true
    }
    return controller.handleKey(event)
}

// MARK: - リスト

/// リストのデータ（原版 IDC_LIST_FL の行）
final class OutlineListData: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    private(set) var rows: [OutlineRow] = []
    weak var controller: OutlineWindowController?

    func load(_ result: OutlineResult) {
        rows = result.rows
    }

    func select(item: Int, in table: NSTableView) {
        guard let row = rows.firstIndex(where: { $0.item == item }) else { return }
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        table.scrollRowToVisible(row)
    }

    func selectedItem(_ table: NSTableView) -> Int? {
        rows.indices.contains(table.selectedRow) ? rows[table.selectedRow].item : nil
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func text(row: Int, column: Int) -> String {
        guard rows.indices.contains(row) else { return "" }
        let r = rows[row]
        switch column {
        case 0: return String(r.line)
        case 1: return String(r.column)
        case 2: return r.name
        default: return r.remark
        }
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let column = Int(tableColumn?.identifier.rawValue ?? "0") ?? 0
        return OutlineCell(text: text(row: row, column: column), color: (tableView as? OutlineListView)?.textColor)
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        OutlineRowView(back: (tableView as? OutlineListView)?.textColor == nil ? nil : tableView.backgroundColor)
    }

    /// 列名のクリック（原版 LVN_COLUMNCLICK）
    func tableView(_ tableView: NSTableView, didClick tableColumn: NSTableColumn) {
        guard let column = Int(tableColumn.identifier.rawValue) else { return }
        controller?.sortList(column: column)
    }
}

/// アウトラインのリスト（原版 IDC_LIST_FL：LVS_REPORT、1 行選択）
final class OutlineListView: NSTableView {
    weak var controller: OutlineWindowController?
    /// 文字の色（ドッキングのときは編集画面の色。nil は標準）
    var textColor: NSColor?
    private weak var data: OutlineListData?

    func setUp(data: OutlineListData, controller: OutlineWindowController) {
        self.controller = controller
        self.data = data
        data.controller = controller
        for index in 0..<4 {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(String(index)))
            column.headerCell.font = PropPage.font
            column.minWidth = 16
            addTableColumn(column)
        }
        columnAutoresizingStyle = .noColumnAutoresizing
        rowHeight = 17
        allowsMultipleSelection = false
        allowsEmptySelection = true
        allowsColumnReordering = false
        usesAlternatingRowBackgroundColors = false
        dataSource = data
        delegate = data
        target = self
        doubleAction = #selector(doubleClicked(_:))
        setAccessibilityIdentifier("IDC_LIST_FL_table")
    }

    /// 列名と列の幅（原版：LVSCW_AUTOSIZE の幅 + 16）
    func reload(columnTitles: [String]) {
        reloadData()
        guard let data else { return }
        for (index, column) in tableColumns.enumerated() {
            column.title = columnTitles.indices.contains(index) ? columnTitles[index] : ""
            var width: CGFloat = 0
            for row in 0..<data.rows.count {
                let text = data.text(row: row, column: index) as NSString
                width = max(width, ceil(text.size(withAttributes: [.font: PropPage.font]).width))
            }
            column.width = width + 16 + 8
        }
    }

    @objc private func doubleClicked(_ sender: Any?) {
        guard clickedRow >= 0 else { return }
        controller?.jump()
    }

    /// シングルクリック（ドッキングのときだけ動作。原版 NM_CLICK）
    @objc func singleClicked(_ sender: Any?) {
        guard clickedRow >= 0 else { return }
        controller?.singleClicked()
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        if let controller, controller.focusEditorAfterClick {
            controller.focusEditorAfterClick = false
            controller.focusEditor()
        }
    }

    override func keyDown(with event: NSEvent) {
        if outlineKeyDown(event, controller: controller) { return }
        super.keyDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let row = self.row(at: convert(event.locationInWindow, from: nil))
        if row >= 0 { selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        return controller?.makeMenu(dropDown: false)
    }

    @objc func copy(_ sender: Any?) { controller?.copyToPasteboard() }
    @objc func cut(_ sender: Any?) { controller?.copyToPasteboard() }
}

// MARK: - 編集画面のコマンド（原版 CViewCommander_Outline.cpp、Command_FUNCLIST_NEXT/PREV）

extension EditorTextView {
    /// Command_FUNCLIST の nAction
    enum OutlineAction {
        case normal		// SHOW_NORMAL：開いている同じ種別のものはアクティブにするだけ
        case reload		// SHOW_RELOAD：再解析
        case toggle		// SHOW_TOGGLE：開いている同じ種別のものは閉じる
    }

    /// 検索 > アウトライン解析（F_OUTLINE）
    @objc func showOutline(_ sender: Any?) {
        outlineCommand(action: .normal, type: .default)
    }

    /// アウトライン解析(toggle)（F_OUTLINE_TOGGLE）
    @objc func toggleOutline(_ sender: Any?) {
        outlineCommand(action: .toggle, type: .default)
    }

    /// 原版 Command_FUNCLIST
    func outlineCommand(action: OutlineAction, type requested: OutlineType, focus: Bool = true) {
        let type = document.resolveOutlineType(requested)
        if let panel = outlinePanel, panel.isOpen, action != .reload {
            switch action {
            case .normal:
                // 開いているものと種別が同じならActiveにするだけ．異なれば再解析
                if panel.outlineType == type {
                    panel.show(focus: focus)
                    return
                }
            case .toggle:
                // 開いているものと種別が同じなら閉じる．異なれば再解析
                if panel.outlineType == type {
                    panel.close()
                    return
                }
            case .reload:
                break
            }
        }
        // 種別は解析で決まったもの（原版 MakeFuncList_C は C/C++ を C か C++ に変える）
        let result = analyzeOutlineWithAccess(type)
        if let panel = outlinePanel, panel.isOpen {
            panel.setData(result: result, outlineType: result.type)
            panel.show(focus: focus)
        } else {
            guard let panel = OutlineWindowController(view: self, result: result, outlineType: result.type) else { return }
            outlinePanel = panel
            panel.setData(result: result, outlineType: result.type)
            panel.show(focus: focus)
        }
    }

    /// タイプ別設定が変わった（原版 PM_CHANGESETTING_TYPE）：アウトラインを開いていれば、解析方法が変わったときは再解析
    func outlineTypeSettingsChanged() {
        guard let panel = outlinePanel, panel.isOpen else { return }
        let type = document.resolveOutlineType(OutlineWindowController.redrawType(panel.outlineType))
        guard type != panel.outlineType else {
            panel.redraw()	// 描画更新（変更されたカラーの適用）のみ
            return
        }
        panel.setData(result: analyzeOutlineWithAccess(type), outlineType: type)
    }

    /// アウトライン解析。ルールファイルは設定で選んだときの書签で読む（沙盒の外のファイル）
    func analyzeOutlineWithAccess(_ type: OutlineType) -> OutlineResult {
        guard type == .ruleFile,
              let path = EditorCore.commonSetting(section: "Types(\(document.typeIndex))", key: "szOutlineRuleFilename") else {
            return document.analyzeOutline(type)
        }
        return BookmarkStore.settingFiles.withAccess(path: path) { document.analyzeOutline(type) }
    }

    /// アウトラインからのジャンプ（原版 MYWM_SETCARETPOS、PM_SETCARETPOS_KEEPSELECT）：
    /// 選択のロック中は選択しながら移動する。縦のスクロールは画面の 1/6 の余白（_CARETMARGINRATE / 3）
    func jumpFromOutline(line: Int, column: Int) {
        addCurrentLineToHistory()
        let position = EditorPosition(line: line, column: column)
        moveCursorSelecting(position)
        let margin = CGFloat(max(1, viewRowCount / (20 / 3))) * lineHeight
        scrollToVisible(caretRect.insetBy(dx: -8, dy: -margin))
    }

    /// 次の関数リストマークへ（F_FUNCLIST_NEXT）
    @objc func funcListNext(_ sender: Any?) {
        moveToFuncListMark(next: true)
    }

    /// 前の関数リストマークへ（F_FUNCLIST_PREV）
    @objc func funcListPrev(_ sender: Any?) {
        moveToFuncListMark(next: false)
    }

    private func moveToFuncListMark(next: Bool) {
        var wrapped: ObjCBool = false
        let line = document.findFuncListMark(from: caret.line, forward: next, searchAll: EditorCore.searchSettings.searchAll,
                                             wrapped: &wrapped)
        if line >= 0 {
            moveCursorSelecting(EditorPosition(line: line, column: 0))
            if wrapped.boolValue { sendSearchStatus(next: next, wrapped: true) }	// 第 44 步：ステータスメッセージ
            return
        }
        sendSearchStatus(next: next, wrapped: nil)
        Self.alertNotFound(next
            ? L10n.tr("前方(↓) に関数が見つかりません。", comment: "STR_FUCLIST_NEXT_NOT_FOUND")
            : L10n.tr("後方(↑) に関数が見つかりません。", comment: "STR_FUCLIST_PREV_NOT_FOUND"))
    }
}

// MARK: - 項目の表示

/// 一つの項目の文字。色を指定したとき（ドッキング）は、選んだ項目を反転した色で描く（原版 SyncColor の NM_CUSTOMDRAW）
final class OutlineCell: NSTableCellView {
    private let color: NSColor?

    init(text: String, color: NSColor?) {
        self.color = color
        super.init(frame: .zero)
        let label = NSTextField(labelWithString: text)
        label.font = PropPage.font
        label.lineBreakMode = .byClipping	// 原版の TreeView・ListView は省略記号を付けず切る
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        textField = label
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        updateColor()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { updateColor() }
    }

    private func updateColor() {
        guard let color else { return }
        textField?.textColor = backgroundStyle == .emphasized ? OutlineRowView.inverted(color) : color
    }
}

/// 行。色を指定したとき（ドッキング）は、選んだ行の背景を編集画面の背景の反転色で描く
final class OutlineRowView: NSTableRowView {
    private let back: NSColor?

    init(back: NSColor?) {
        self.back = back
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// 原版：色 ^ RGB(255, 255, 255)
    static func inverted(_ color: NSColor) -> NSColor {
        guard let c = color.usingColorSpace(.sRGB) else { return color }
        return NSColor(srgbRed: 1 - c.redComponent, green: 1 - c.greenComponent, blue: 1 - c.blueComponent, alpha: 1)
    }

    override func drawSelection(in dirtyRect: NSRect) {
        guard let back else {
            super.drawSelection(in: dirtyRect)
            return
        }
        Self.inverted(back).setFill()
        bounds.fill()
    }
}

// MARK: - フローティングの窓口

/// アウトライン解析の窓口：タイトルバーの右クリックでメニュー（原版 OnContextMenu：キャプション上なら DoMenu）
final class OutlinePanel: NSPanel {
    weak var controller: OutlineWindowController?
    /// メニューの表示（単体テストで差し替える）
    static var presentMenu: (NSMenu, NSEvent, NSView) -> Void = { menu, event, view in
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .rightMouseDown, event.locationInWindow.y >= contentLayoutRect.maxY,
           let controller, let content = contentView {
            Self.presentMenu(controller.makeMenu(dropDown: false), event, content)
            return
        }
        super.sendEvent(event)
    }
}

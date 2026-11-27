// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge

/// Grep・Grep置換 的对话框（第 43 步。原版 CDlgGrep、CDlgGrepReplace）。
///
/// 布局照原版 IDD_GREP・IDD_GREP_REPLACE（Resources/GrepDialogs.json），控件的动作、OK 时的检查与原版相同。
/// 检查和历史在核心库（GrepCore：原版 CDlgGrep::GetData 的检查、GetPackedGFileString 等）。
/// 与原版不同：沙盒里没有权限的文件夹，OK 时请用户在对话框里授权一次（FolderAccess）。

/// 对话框记着的内容（原版 CEditWnd::m_cDlgGrep・m_cDlgGrepReplace 的成员。一个编辑窗口一个，关了以后也留着）
final class GrepDialogState {
    var text = ""				// 条件（原版 m_strText）
    var setText = false			// 条件设置过（原版 m_bSetText）
    var text2 = ""				// 置換後（原版 m_strText2）
    var replaceKeySequence = -1	// 置換後を取った履歴の番号（原版 m_nReplaceKeySequence）
    var file = ""
    var folder = ""
    var excludeFile = ""
    var excludeFolder = ""
    var fromThisText = false
    // 原版はダイアログのインスタンスのメンバー。Grep置換 の DoModal は共通設定から読まない（コンストラクタの値のまま）
    var fileOnly = false
    var baseFolder = false
    var separateFolder = false
}

final class GrepDialogController: NSObject, NSWindowDelegate {
    /// 模态运行（单元测试换掉：不出窗口，直接调用 handler）
    static var runModal: ((GrepDialogController) -> Bool)?
    /// 消息（单元测试换掉）
    static var showMessage: (String, NSWindow?) -> Void = { text, _ in EditorTextView.showMessage(text, style: .warning) }

    let isReplace: Bool
    let page: PropPage
    let window: NSPanel
    let state: GrepDialogState
    /// 编辑中的文件（原版 m_szCurrentFilePath。新文件时空）
    let currentFilePath: String
    /// 相对路径的起点（原版是当前文件夹：Mac 版是编辑中的文件的文件夹，没有时是主文件夹）
    let baseFolder: String
    /// 「編集中のテキストから検索」的对象（原版 :HWND:%016I64x）
    let sourceToken: String
    /// 剪贴板里有可以粘贴的文字（原版 IsEnablePaste。Grep置換 的「クリップボードの内容で置換」）
    var canPaste: () -> Bool = { NSPasteboard.general.string(forType: .string) != nil }

    /// OK 后的条件
    private(set) var options: GrepOptions?
    private var selectOnceThisText = false
    private var accepted = false

    init?(replace: Bool, state: GrepDialogState, currentFilePath: String, sourceToken: String) {
        guard let definition = PropDialogs.load("GrepDialogs")?.dialog(replace ? "IDD_GREP_REPLACE" : "IDD_GREP") else { return nil }
        isReplace = replace
        self.state = state
        self.currentFilePath = currentFilePath
        self.sourceToken = sourceToken
        baseFolder = currentFilePath.isEmpty ? Self.homeFolder : (currentFilePath as NSString).deletingLastPathComponent
        page = PropPage(definition: definition)
        window = NSPanel(contentRect: NSRect(origin: .zero, size: page.view.frame.size), styleMask: [.titled], backing: .buffered, defer: true)
        window.title = definition.name
        window.contentView = page.view
        window.isReleasedWhenClosed = false
        super.init()
        window.delegate = self
        setUpControls()
        setData()
    }

    /// 用户的主文件夹（沙盒里 NSHomeDirectory 是容器，用真的主文件夹）
    static var homeFolder: String {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir { return String(cString: dir) }
        return NSHomeDirectory()
    }

    // MARK: - 控件

    private func setUpControls() {
        (page.control("IDOK") as? NSButton)?.keyEquivalent = "\r"	// DEFPUSHBUTTON
        (page.control("IDCANCEL") as? NSButton)?.keyEquivalent = "\u{1b}"
        page.setUnavailable(["IDC_BUTTON_HELP"], reason: L10n.tr("Mac 版にはまだヘルプがありません", comment: "help"))
        // 文字コードセット（原版 CCodeTypesForCombobox）
        let choices = EditorCore.encodingChoices.map { (value: $0.encoding, title: $0.name) }
        page.setTaggedItems("IDC_COMBO_CHARSET", choices, selectedValue: nil)
        page.onButton = { [weak self] id in self?.buttonClicked(id) }
        page.onChange = { [weak self] id in self?.controlChanged(id) }
        // 履歴（原版 OnCbnDropDown で入れる）
        page.setItems("IDC_COMBO_TEXT", EditorCore.searchKeyHistory, selected: -1)
        page.setItems("IDC_COMBO_FILE", GrepCore.history(.file), selected: -1)
        page.setItems("IDC_COMBO_FOLDER", GrepCore.history(.folder), selected: -1)
        page.setItems("IDC_COMBO_EXCLUDE_FILE", GrepCore.history(.excludeFile), selected: -1)
        page.setItems("IDC_COMBO_EXCLUDE_FOLDER", GrepCore.history(.excludeFolder), selected: -1)
        if isReplace {
            page.setItems("IDC_COMBO_TEXT2", EditorCore.replaceKeyHistory, selected: -1)
        }
    }

    static func common(_ key: String) -> String { EditorCore.commonSetting(section: "Common", key: key) ?? "0" }
    static func commonInt(_ key: String) -> Int { Int(common(key)) ?? 0 }
    static func commonBool(_ key: String) -> Bool { common(key) != "0" }
    static func setCommon(_ key: String, _ value: Int) { _ = EditorCore.setCommonSetting(String(value), section: "Common", key: key) }
    static func setCommon(_ key: String, _ value: Bool) { setCommon(key, value ? 1 : 0) }

    // MARK: - 表示（原版 DoModal・OnInitDialog・SetData）

    private var subFolder = false
    private var searchOptions: EditorSearchOptions = []
    private var charSet: EditorEncoding = ECEncodingSJIS
    private var outputLineType = 0
    private var outputStyle = 1
    private var exceptFileRegexp = false
    private var backup = false

    private func setData() {
        // DoModal：共通設定の値
        subFolder = Self.commonBool("bGrepSubFolder")
        searchOptions = EditorCore.searchSettings.options
        charSet = Self.commonInt("nGrepCharSet")
        outputLineType = Self.commonInt("bGrepOutputLine")
        outputStyle = Self.commonInt("nGrepOutputStyle")
        exceptFileRegexp = Self.commonBool("bGrepExceptFileRegexp")
        if isReplace {
            backup = Self.commonBool("bGrepBackup")
        } else {
            state.fileOnly = Self.commonBool("bGrepOutputFileOnly")
            state.baseFolder = Self.commonBool("bGrepOutputBaseFolder")
            state.separateFolder = Self.commonBool("bGrepSeparateFolder")
        }
        let defaults = GrepCore.dialogDefaults()
        if state.file.isEmpty { state.file = defaults["file"] ?? "" }
        if state.folder.isEmpty { state.folder = defaults["folder"] ?? "" }
        if state.excludeFile.isEmpty { state.excludeFile = defaults["excludeFile"] ?? "" }
        if state.excludeFolder.isEmpty { state.excludeFolder = defaults["excludeFolder"] ?? "" }

        // OnInitDialog：カレントフォルダーが初期値
        if (state.folder.isEmpty || Self.commonBool("bGrepDefaultFolder")) && !currentFilePath.isEmpty {
            state.folder = (currentFilePath as NSString).deletingLastPathComponent
        }

        page.setText("IDC_COMBO_TEXT", state.text)
        if isReplace {
            page.setText("IDC_COMBO_TEXT2", state.text2)
            page.setChecked("IDC_CHK_BACKUP", backup)
            page.setChecked("IDC_CHK_PASTE", false)
        }
        page.setText("IDC_COMBO_FILE", state.file)
        page.setText("IDC_COMBO_FOLDER", state.folder)
        page.setText("IDC_COMBO_EXCLUDE_FILE", state.excludeFile)
        page.setText("IDC_COMBO_EXCLUDE_FOLDER", state.excludeFolder)
        page.setChecked("IDC_CHK_SUBFOLDER", subFolder)
        page.setChecked("IDC_CHK_FROMTHISTEXT", state.fromThisText)
        setDataFromThisText(state.fromThisText)
        page.setChecked("IDC_CHK_LOHICASE", searchOptions.contains(.matchCase))
        page.setChecked("IDC_CHK_WORD", searchOptions.contains(.wholeWord))

        // 文字コードセット：一覧に無ければ CP を入れてチェック・無効
        if !page.setTaggedItems("IDC_COMBO_CHARSET", EditorCore.encodingChoices.map { (value: $0.encoding, title: $0.name) }, selectedValue: charSet) {
            page.setChecked("IDC_CHECK_CP", true)
            page.setEnabled("IDC_CHECK_CP", false)
            if !page.appendTaggedItems("IDC_COMBO_CHARSET", EditorCore.codePageChoices.map { (value: $0.encoding, title: $0.name) }, selectedValue: charSet) {
                page.select("IDC_COMBO_CHARSET", 0)
            }
        }

        page.setChecked("IDC_RADIO_OUTPUTLINE", outputLineType == 1)
        page.setChecked("IDC_RADIO_NOHIT", outputLineType == 2)
        page.setChecked("IDC_RADIO_OUTPUTMARKED", outputLineType != 1 && outputLineType != 2)
        if isReplace && outputLineType == 2 { page.setChecked("IDC_RADIO_OUTPUTMARKED", true) }	// Grep置換 に否該当行は無い
        page.setEnabled("IDC_CHECK_BASE_PATH", true)
        page.setEnabled("IDC_CHECK_SEP_FOLDER", true)
        switch outputStyle {
        case 2: page.setChecked("IDC_RADIO_OUTPUTSTYLE2", true)
        case 3:
            page.setChecked("IDC_RADIO_OUTPUTSTYLE3", true)
            page.setEnabled("IDC_CHECK_BASE_PATH", false)
            page.setEnabled("IDC_CHECK_SEP_FOLDER", false)
        default: page.setChecked("IDC_RADIO_OUTPUTSTYLE1", true)
        }

        // 正規表現ライブラリのバージョン（原版 CheckRegexpVersion）
        page.setText("IDC_STATIC_JRE32VER", EditorCore.regexpVersion)
        if searchOptions.contains(.regularExpression) {
            page.setChecked("IDC_CHK_REGULAREXP", true)
            page.setEnabled("IDC_CHK_WORD", false)
        } else {
            page.setChecked("IDC_CHK_REGULAREXP", false)
        }
        page.setChecked("IDC_CHECK_FILE_ONLY", state.fileOnly)
        page.setChecked("IDC_CHECK_BASE_PATH", state.baseFolder)
        page.setChecked("IDC_CHECK_SEP_FOLDER", state.separateFolder)
        page.setChecked("IDC_CHK_EXCLUDE_FILE_REGEXP", exceptFileRegexp)
        page.setChecked("IDC_CHK_DEFAULTFOLDER", Self.commonBool("bGrepDefaultFolder"))
        if isReplace {
            page.setEnabled("IDC_CHK_FROMTHISTEXT", false)	// Grep置換 は編集中のテキストを対象にできない
            page.setEnabled("IDC_COMBO_TEXT2", true)
        }
    }

    /// 編集中のテキストから検索（原版 SetDataFromThisText）
    private func setDataFromThisText(_ checked: Bool) {
        var enable = true
        if checked {
            state.file = page.text("IDC_COMBO_FILE")
            state.folder = page.text("IDC_COMBO_FOLDER")
            state.excludeFile = page.text("IDC_COMBO_EXCLUDE_FILE")
            state.excludeFolder = page.text("IDC_COMBO_EXCLUDE_FOLDER")
            page.setText("IDC_COMBO_FILE", L10n.tr("(現在のドキュメント)", comment: "STR_DLGGREP_THISDOC"))
            page.setText("IDC_COMBO_FOLDER", L10n.tr("(現在のドキュメント)", comment: "STR_DLGGREP_THISDOC"))
            page.setText("IDC_COMBO_EXCLUDE_FILE", "")
            page.setText("IDC_COMBO_EXCLUDE_FOLDER", "")
            enable = false
        } else {
            if state.file.hasPrefix(":HWND:") { state.file = "*.*" }
            page.setText("IDC_COMBO_FILE", state.file)
            page.setText("IDC_COMBO_FOLDER", state.folder)
            page.setText("IDC_COMBO_EXCLUDE_FILE", state.excludeFile)
            page.setText("IDC_COMBO_EXCLUDE_FOLDER", state.excludeFolder)
        }
        for id in ["IDC_COMBO_FILE", "IDC_COMBO_FOLDER", "IDC_BUTTON_FOLDER", "IDC_CHK_SUBFOLDER", "IDC_COMBO_EXCLUDE_FILE",
                   "IDC_CHK_EXCLUDE_FILE_REGEXP", "IDC_COMBO_EXCLUDE_FOLDER", "IDC_BUTTON_FOLDER_UP", "IDC_BUTTON_CURRENTFOLDER"] {
            page.setEnabled(id, enable)
        }
        selectOnceThisText = true
    }

    // MARK: - 操作（原版 OnBnClicked）

    private func buttonClicked(_ id: String) {
        switch id {
        case "IDOK": ok()
        case "IDCANCEL": cancel()
        case "IDC_BUTTON_CURRENTFOLDER":
            // 編集中のファイルのフォルダー（新しいファイルのときは原版はカレントディレクトリ：Mac 版は主フォルダー）
            page.setText("IDC_COMBO_FOLDER", baseFolder)
        case "IDC_BUTTON_FOLDER_UP":
            if let up = GrepCore.foldersUp(page.text("IDC_COMBO_FOLDER"), base: baseFolder) {
                page.setText("IDC_COMBO_FOLDER", up)
            }
        case "IDC_BUTTON_FOLDER":
            chooseFolder()
        default:
            break
        }
    }

    private func controlChanged(_ id: String) {
        switch id {
        case "IDC_CHK_FROMTHISTEXT":
            setDataFromThisText(page.isChecked(id))
        case "IDC_CHK_REGULAREXP":
            page.setEnabled("IDC_CHK_WORD", !page.isChecked(id))	// 正規表現のときは単語単位で探せない
        case "IDC_CHECK_CP":
            if page.isChecked(id) {
                page.setEnabled(id, false)
                page.appendTaggedItems("IDC_COMBO_CHARSET", EditorCore.codePageChoices.map { (value: $0.encoding, title: $0.name) }, selectedValue: nil)
            }
        case "IDC_CHK_DEFAULTFOLDER":
            Self.setCommon("bGrepDefaultFolder", page.isChecked(id))
        case "IDC_RADIO_OUTPUTSTYLE3":
            page.setEnabled("IDC_CHECK_BASE_PATH", false)
            page.setEnabled("IDC_CHECK_SEP_FOLDER", false)
        case "IDC_RADIO_OUTPUTSTYLE1", "IDC_RADIO_OUTPUTSTYLE2":
            page.setEnabled("IDC_CHECK_BASE_PATH", true)
            page.setEnabled("IDC_CHECK_SEP_FOLDER", true)
        case "IDC_CHK_PASTE":
            checkPaste()
        default:
            break
        }
    }

    /// クリップボードの内容で置換：貼り付けられないときはチェックを外す（原版 CDlgGrepReplace::OnBnClicked）。止めたら false
    @discardableResult
    private func checkPaste() -> Bool {
        var ok = true
        if page.isChecked("IDC_CHK_PASTE") && !canPaste() {
            Self.showMessage(L10n.tr("クリップボードに有効なデータがありません！", comment: "STR_DLGREPLC_CLIPBOARD"), window)
            page.setChecked("IDC_CHK_PASTE", false)
            ok = false
        }
        page.setEnabled("IDC_COMBO_TEXT2", !page.isChecked("IDC_CHK_PASTE"))
        return ok
    }

    /// 「...」：フォルダーを選ぶ（原版 SelectDir）。選んだフォルダーは沙盒の権限も記憶する
    static var chooseFolderPanel: (_ start: String, _ parent: NSWindow?) -> URL? = { start, parent in
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = L10n.tr("検索するフォルダーを選んでください", comment: "STR_DLGGREP1")
        panel.directoryURL = URL(fileURLWithPath: start, isDirectory: true)
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func chooseFolder() {
        var start = GrepCore.splitFolders(page.text("IDC_COMBO_FOLDER"), base: baseFolder).first ?? ""
        if start.isEmpty { start = baseFolder }
        guard let url = Self.chooseFolderPanel(start, window) else { return }
        FolderAccess.shared.remember(url)
        page.setText("IDC_COMBO_FOLDER", Self.quotedFolder(url.path))
    }

    /// ; を含むフォルダーは引用符で囲む（原版 SetGrepFolder）
    static func quotedFolder(_ path: String) -> String {
        path.contains(";") ? "\"\(path)\"" : path
    }

    // MARK: - OK（原版 GetData）

    private func ok() {
        if isReplace && !checkPaste() { return }
        if getData() {
            accepted = true
            close()
        }
    }

    private func cancel() {
        if selectOnceThisText {
            // 「編集中のテキストから検索」を一度選んだ：記憶を履歴の最初に戻す
            let d = GrepCore.dialogDefaults()
            state.file = GrepCore.history(.file).first ?? state.file
            state.folder = GrepCore.history(.folder).first ?? state.folder
            state.excludeFile = GrepCore.history(.excludeFile).first ?? d["excludeFile"] ?? state.excludeFile
            state.excludeFolder = GrepCore.history(.excludeFolder).first ?? d["excludeFolder"] ?? state.excludeFolder
        }
        accepted = false
        close()
    }

    private func close() {
        if window.isSheet, let parent = window.sheetParent {
            parent.endSheet(window)
        } else if NSApp.modalWindow === window {
            NSApp.stopModal()
        }
        window.orderOut(nil)
    }

    /// 入力を確かめて記憶する。エラーならメッセージを出して false
    func getData() -> Bool {
        let paste = isReplace && page.isChecked("IDC_CHK_PASTE")
        if isReplace {
            state.text2 = page.text("IDC_COMBO_TEXT2")
            if page.text("IDC_COMBO_TEXT").isEmpty {
                Self.showMessage(L10n.tr("置換条件を指定してください。", comment: "STR_DLGREPLC_REPSTR"), window)
                return false
            }
            backup = page.isChecked("IDC_CHK_BACKUP")
            Self.setCommon("bGrepBackup", backup)
        }
        subFolder = page.isChecked("IDC_CHK_SUBFOLDER")
        state.fromThisText = !isReplace && page.isChecked("IDC_CHK_FROMTHISTEXT")
        var options: EditorSearchOptions = []
        if page.isChecked("IDC_CHK_LOHICASE") { options.insert(.matchCase) }
        if page.isChecked("IDC_CHK_WORD") { options.insert(.wholeWord) }
        if page.isChecked("IDC_CHK_REGULAREXP") { options.insert(.regularExpression) }
        searchOptions = options
        charSet = page.selectedTag("IDC_COMBO_CHARSET") ?? charSet
        if page.isChecked("IDC_RADIO_OUTPUTLINE") { outputLineType = 1 }
        else if page.isChecked("IDC_RADIO_NOHIT") { outputLineType = 2 }
        else { outputLineType = 0 }
        if page.isChecked("IDC_RADIO_OUTPUTSTYLE1") { outputStyle = 1 }
        if page.isChecked("IDC_RADIO_OUTPUTSTYLE2") { outputStyle = 2 }
        if page.isChecked("IDC_RADIO_OUTPUTSTYLE3") { outputStyle = 3 }
        state.fileOnly = page.isChecked("IDC_CHECK_FILE_ONLY")
        state.baseFolder = page.isChecked("IDC_CHECK_BASE_PATH")
        state.separateFolder = page.isChecked("IDC_CHECK_SEP_FOLDER")
        exceptFileRegexp = page.isChecked("IDC_CHK_EXCLUDE_FILE_REGEXP")
        state.text = page.text("IDC_COMBO_TEXT")
        state.setText = true

        var file = page.text("IDC_COMBO_FILE")
        if state.fromThisText {
            file = sourceToken
        }
        let folder = page.text("IDC_COMBO_FOLDER")
        let excludeFile = page.text("IDC_COMBO_EXCLUDE_FILE")
        let excludeFolder = page.text("IDC_COMBO_EXCLUDE_FOLDER")
        if !state.fromThisText {
            state.file = file
            state.folder = folder
            state.excludeFile = excludeFile
            state.excludeFolder = excludeFolder
        }

        Self.setCommon("nGrepCharSet", charSet)
        Self.setCommon("bGrepOutputLine", outputLineType)
        Self.setCommon("nGrepOutputStyle", outputStyle)
        if !isReplace {
            Self.setCommon("bGrepOutputFileOnly", state.fileOnly)
            Self.setCommon("bGrepOutputBaseFolder", state.baseFolder)
            Self.setCommon("bGrepSeparateFolder", state.separateFolder)
        }
        Self.setCommon("bGrepExceptFileRegexp", exceptFileRegexp)

        // 沙盒：検索場所の権限（原版には無い。OK の前に、権限の無いフォルダーは許可を求める）
        if !state.fromThisText && !folder.isEmpty {
            let paths = GrepCore.splitFolders(folder, base: baseFolder)
            if !FolderAccess.shared.ensureAccess(paths: paths, parent: window) { return false }
        }
        let check = GrepCore.checkDialog(file: file, excludeFile: state.fromThisText ? "" : excludeFile,
                                         excludeFolder: state.fromThisText ? "" : excludeFolder,
                                         folders: folder, base: baseFolder, fromThisText: state.fromThisText)
        if !check.error.isEmpty {
            Self.showMessage(check.error, window)
            return false
        }
        if !state.fromThisText { state.file = check.file }
        if !state.fromThisText { state.folder = check.folders }

        // 検索文字列
        if !state.text.isEmpty {
            if options.contains(.regularExpression),
               let error = EditorCore.regexpSyntaxError(state.text, matchCase: options.contains(.matchCase)) {
                EditorTextView.showRegexpError(error)
                return false
            }
            if (state.text as NSString).length < 260 {
                EditorCore.addSearchKey(state.text)
                let settings = EditorCore.searchSettings
                settings.options = options
                EditorCore.searchSettings = settings
            }
        } else {
            EditorCore.addSearchKey("")	// 2014.07.01 空キーも登録する
        }
        if !state.fromThisText {
            GrepCore.addHistory(check.file, kind: .file)
            GrepCore.addHistory(check.folders, kind: .folder)
            GrepCore.addHistory(excludeFile, kind: .excludeFile)
            GrepCore.addHistory(excludeFolder, kind: .excludeFolder)
            Self.setCommon("bGrepSubFolder", subFolder)
        }
        if isReplace {
            if (state.text2 as NSString).length < 260 { EditorCore.addReplaceKey(state.text2) }
            state.replaceKeySequence = EditorCore.replaceKeySequence
        }

        // 原版 MakeGrepInfo
        let result = GrepOptions()
        result.key = state.text
        result.files = state.fromThisText ? sourceToken
            : GrepCore.packFiles(check.file, excludeFile: excludeFile, excludeFolder: excludeFolder)
        result.folders = check.folders
        result.regularExpression = options.contains(.regularExpression)
        result.matchCase = options.contains(.matchCase)
        result.wholeWord = options.contains(.wholeWord)
        result.subFolder = subFolder
        result.charSet = charSet
        result.outputStyle = outputStyle
        result.outputLineType = outputLineType
        result.fileOnly = state.fileOnly
        result.baseFolder = state.baseFolder
        result.separateFolder = state.separateFolder
        result.exceptFileRegexp = exceptFileRegexp
        if isReplace {
            result.replace = true
            result.replacement = state.text2
            result.paste = paste
            result.backup = backup
        }
        self.options = result
        return true
    }

    // MARK: - モーダル

    /// 模态显示（原版 DoModal）。OK 时 true
    func run(parent: NSWindow?) -> Bool {
        if let hook = Self.runModal { return hook(self) }
        if let parent {
            let frame = parent.frame
            window.setFrameOrigin(NSPoint(x: frame.midX - window.frame.width / 2, y: frame.midY - window.frame.height / 2))
        } else {
            window.center()
        }
        window.makeFirstResponder(page.control("IDC_COMBO_TEXT"))
        NSApp.runModal(for: window)
        return accepted
    }

    /// 单元测试：按钮（原版 BN_CLICKED）
    func press(_ id: String) {
        if let button = page.control(id) as? NSButton, button.target != nil {
            button.performClick(nil)
        } else {
            buttonClicked(id)
        }
    }

    var isAccepted: Bool { accepted }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        cancel()
        return false
    }
}

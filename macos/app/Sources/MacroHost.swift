// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge

/// マクロの値（原版 VARIANT の VT_I4・VT_BSTR）
enum MacroValue: Equatable {
    case int(Int)
    case string(String)

    /// VT_BSTR として（VariantChangeType）
    var text: String {
        switch self {
        case .int(let n): return String(n)
        case .string(let s): return s
        }
    }

    /// VT_I4 として。数字でない文字列は変換できない（VariantChangeType の失敗）
    var intValue: Int? {
        switch self {
        case .int(let n): return n
        case .string(let s): return Int(s.trimmingCharacters(in: .whitespaces))
        }
    }
}

/// マクロの命令・関数の実行（第 45 步。原版 CMacro::HandleCommand・HandleFunction、CMacro::AddLParam）。
///
/// キーマクロ（KeyMacro.swift）の各行も、JScript マクロ（次の PR）の Editor オブジェクトもここを通る。
/// 命令は原版と同じく、引数を原版の HandleCommand の形に直して Mac 版の機能（CommandTable 等）を呼ぶ。
/// Mac 版にまだない機能は原版の HandleCommand が知らない機能番号のときと同じく何もしない（true を返す）。
/// 関数は値を返す（失敗は nil。原版の HandleFunction の false）。
enum MacroHost {
    // MARK: - 機能番号（Funccode_x.hsrc）

    enum Code {
        static let wchar = 30200, imeChar = 30201, ctrlCode = 30793
        static let paste = 30604, pasteBox = 30605, insText = 30606, addTail = 30607
        static let searchNext = 30902, searchPrev = 30903, replace = 30906, replaceAll = 30907
        static let jump = 30921, bookmarkPattern = 30975
        static let chgCharset = 31010, setFontSize = 31121
        static let recKeyMacro = 31250, saveKeyMacro = 31251, loadKeyMacro = 31252, execKeyMacro = 31253, execExtMacro = 31254
        static let chgmodEol = 32800, setQuoteString = 32801, textWrapMethod = 32805, insBoxText = 32806, moveCursor = 32807, moveCursorLayout = 32808
        static let changeType = 32811
        static let statusMsg = 32809, msgBeep = 32810
        static let commitUndoBuffer = 32813, addRefUndoBuffer = 32814, setUndoBuffer = 32815, appendUndoBufferCursor = 32816
        static let clipboardEmpty = 32817, setViewTop = 32818, setViewLeft = 32819
        // 値を返す関数
        static let getFilename = 40001, getSelected = 40002, expandParameter = 40003, getLineStr = 40004, getLineCount = 40005
        static let chgTabWidth = 40006, isTextSelected = 40007
        static let getSelLineFrom = 40008, getSelColumnFrom = 40009, getSelLineTo = 40010, getSelColumnTo = 40011
        static let isInsMode = 40012, getCharCode = 40013, getLineCode = 40014, isPossibleUndo = 40015, isPossibleRedo = 40016
        static let chgWrapColumn = 40017, getSaveFilename = 40018, isCurTypeExt = 40019, isSameTypeExt = 40020
        static let inputBox = 40021, messageBox = 40023, errorMsg = 40024, warnMsg = 40025, infoMsg = 40026
        static let okCancelBox = 40027, yesNoBox = 40028, compareVersion = 40029, macroSleep = 40030
        static let fileOpenDialog = 40031, fileSaveDialog = 40032, folderDialog = 40033
        static let getClipboard = 40034, setClipboard = 40035
        static let layoutToLogicLineNum = 40036, logicToLayoutLineNum = 40037, lineColumnToIndex = 40038, lineIndexToColumn = 40039
        static let getCookie = 40040, getCookieDefault = 40041, setCookie = 40042, deleteCookie = 40043, getCookieNames = 40044
        static let setDrawSwitch = 40045, getDrawSwitch = 40046, isShownStatus = 40047
        static let isTextSelectingLock = 40055, getViewLines = 40056, getViewColumns = 40057, getViewTop = 40059
    }

    /// 原版 STR_ERR_DLGMACRO02
    static var errorTitle: String { L10n.tr("Macro実行エラー", comment: "STR_ERR_DLGMACRO02") }

    /// エラーのメッセージボックス（原版 MYMESSAGEBOX MB_ICONSTOP）。単体テストで差し替える。引数はタイトル、メッセージ
    static var showError: (String, String) -> Void = { title, message in
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    /// メッセージボックス（原版 ::MessageBox。タイトル「sakura macro」）。単体テストで差し替える。
    /// 引数はメッセージと uType（MB_*）、戻り値は IDOK(1)・IDCANCEL(2)・IDYES(6)・IDNO(7)
    static var messageBox: (String, Int) -> Int = { message, type in
        let alert = NSAlert()
        alert.messageText = "sakura macro"
        alert.informativeText = message
        switch type & 0xF0 {
        case 0x10: alert.alertStyle = .critical			// MB_ICONSTOP
        case 0x30: alert.alertStyle = .warning			// MB_ICONEXCLAMATION
        default: alert.alertStyle = .informational
        }
        switch type & 0x0F {
        case 1:	// MB_OKCANCEL
            alert.addButton(withTitle: L10n.tr("OK", comment: "MB_OK"))
            alert.addButton(withTitle: L10n.tr("キャンセル", comment: "MB_CANCEL"))
            return alert.runModal() == .alertFirstButtonReturn ? 1 : 2
        case 4:	// MB_YESNO
            alert.addButton(withTitle: L10n.tr("はい", comment: "MB_YES"))
            alert.addButton(withTitle: L10n.tr("いいえ", comment: "MB_NO"))
            return alert.runModal() == .alertFirstButtonReturn ? 6 : 7
        default:
            alert.runModal()
            return 1
        }
    }

    /// 入力ダイアログ（原版 CDlgInput1。InputBox）。単体テストで差し替える。引数はメッセージ、既定値、最大長。キャンセルは nil
    static var inputBox: (String, String, Int) -> String? = { message, defaultValue, maxLength in
        let alert = NSAlert()
        alert.messageText = "sakura macro"
        alert.informativeText = message
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 22))
        field.stringValue = defaultValue
        alert.accessoryView = field
        alert.addButton(withTitle: L10n.tr("OK", comment: "IDD_INPUT1"))
        alert.addButton(withTitle: L10n.tr("キャンセル", comment: "IDD_INPUT1"))
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let utf16 = Array(field.stringValue.utf16.prefix(maxLength))
        return String(utf16CodeUnits: utf16, count: utf16.count)
    }

    /// ファイルを開く・保存のダイアログ（FileOpenDialog・FileSaveDialog。単体テストで差し替える）。引数は保存か、既定のファイル名
    static var fileDialog: (Bool, String) -> String? = { save, initial in
        let panel: NSSavePanel = save ? NSSavePanel() : NSOpenPanel()
        if !initial.isEmpty {
            let url = URL(fileURLWithPath: initial)
            panel.directoryURL = initial.hasSuffix("/") ? url : url.deletingLastPathComponent()
            if !initial.hasSuffix("/") { panel.nameFieldStringValue = url.lastPathComponent }
        }
        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    /// 実行中のマクロのファイル（ExpandParameter の $M）
    static var currentMacroPath = ""

    /// マクロの実行中に開いている編集のまとまり（文書ごと）。マクロ全体を一つの取り消し単位にする
    private static var editDepth: [ObjectIdentifier: Int] = [:]

    static func beginMacroEdit(_ document: EditorDocument) {
        editDepth[ObjectIdentifier(document), default: 0] += 1
        document.beginEdit()
    }

    static func endMacroEdit(_ document: EditorDocument) {
        document.endEdit()
        let key = ObjectIdentifier(document)
        editDepth[key, default: 1] -= 1
        if editDepth[key] == 0 { editDepth[key] = nil }
    }

    /// 元に戻す・やり直しはまとまりを閉じてから（原版はマクロの中でも直前までの編集を取り消せる。ヘルプのサンプル SampleIsPossibleUndo）
    private static func undoRedo(_ code: Int, view: EditorTextView) {
        let depth = editDepth[ObjectIdentifier(view.document)] ?? 0
        for _ in 0..<depth { view.document.endEdit() }
        _ = CommandTable.perform(code, from: view)
        for _ in 0..<depth { view.document.beginEdit() }
    }

    // MARK: - 命令（原版 CMacro::HandleCommand）

    /// キーマクロの一行（原版 CMacro::Exec）
    @discardableResult
    static func execute(_ call: MacroCall, view: EditorTextView) -> Bool {
        handleCommand(call.code, call.args.map(\.text), view: view)
    }

    /// 命令を実行する。args は原版の Argument[]（数値も文字列）。false はマクロの中断（引数のエラー）
    @discardableResult
    static func handleCommand(_ code: Int, _ args: [String], view: EditorTextView) -> Bool {
        func arg(_ i: Int) -> String? { i < args.count ? args[i] : nil }
        func int(_ i: Int, _ def: Int = 0) -> Int { arg(i).map(wtoi) ?? def }
        func error(_ message: String) -> Bool {
            showError(errorTitle, message)
            return false
        }

        switch code {
        case Code.wchar, Code.imeChar, Code.ctrlCode:
            guard let a = arg(0) else {
                return error(L10n.tr("挿入すべき文字コードが指定されていません．", comment: "STR_ERR_DLGMACRO03"))
            }
            view.macroInsertCharacter(wtoi(a), code: code)
        case Code.chgmodEol:
            guard let a = arg(0) else {
                return error(L10n.tr("入力改行コードが指定されていません．", comment: "STR_ERR_DLGMACRO03_1"))
            }
            // マクロ引数値 → EOL（原版：1 CRLF、3 LF、4 CR、5 NEL、6 LS、7 PS。それ以外は何もしない）
            let eolCommands = [1: 31081, 3: 31082, 4: 31083, 5: 31084, 6: 31086, 7: 31085]
            if let eolCode = eolCommands[wtoi(a)], view.document.isEnabled(eolCode) { _ = view.document.execute(eolCode) }
        case Code.insText, Code.addTail, Code.insBoxText:
            guard let text = arg(0) else {
                return error(L10n.tr("引数(文字列)が指定されていません．", comment: "STR_ERR_DLGMACRO04"))
            }
            switch code {
            case Code.insText: view.macroInsertText(text)
            case Code.addTail: view.macroAddTail(text)
            default: _ = CommandTable.perform(code, from: view)	// 矩形テキスト挿入は Mac 版にまだない
            }
        case Code.chgCharset:
            // 文字コードセット指定：引数がないか CODE_NONE（-1）ならダイアログ
            let charset = arg(0).flatMap { $0.isEmpty ? nil : wtoi($0) } ?? -1
            if charset == -1 {
                _ = CommandTable.perform(code, from: view)
            } else {
                view.document.setEncoding(EditorEncoding(charset), bom: int(1) != 0)
                view.window?.windowController?.synchronizeWindowTitleWithDocumentName()
            }
        case Code.jump:
            guard let a = arg(0) else {
                return error(L10n.tr("ジャンプ先行番号が指定されていません．", comment: "STR_ERR_DLGMACRO05"))
            }
            let flag = int(1, 1)	// 省略時 1（改行単位）
            let settings = EditorCore.searchSettings
            settings.jumpLineNumIsCRLF = flag & 0x01 != 0	// 原版 m_bLineNumIsCRLF_ForJump
            EditorCore.searchSettings = settings
            view.jumpCommand(EditorJumpOptions(lineNumber: wtoi(a), lineNumIsCRLF: flag & 0x01 != 0,
                                               plsql: flag & 0x02 != 0, plsqlBlockFirstLine: JumpDialogController.shared.plsqlFirstLine))
        case Code.bookmarkPattern, Code.searchNext, Code.searchPrev:
            if code == Code.bookmarkPattern && arg(0) == nil {
                return error(L10n.tr("マーク行のパターンが指定されていません．", comment: "STR_ERR_DLGMACRO06"))
            }
            macroSearch(code, key: arg(0) ?? "", flag: int(1), view: view)
        case Code.replace, Code.replaceAll:
            guard let key = arg(0), !key.isEmpty else {
                return error(L10n.tr("置換元パターンが指定されていません．", comment: "STR_ERR_DLGMACRO09"))
            }
            guard let replacement = arg(1) else {
                return error(L10n.tr("置換先パターンが指定されていません．", comment: "STR_ERR_DLGMACRO10"))
            }
            macroReplace(code, key: key, replacement: replacement, flag: int(2), view: view)
        case Code.moveCursor, Code.moveCursorLayout:
            guard let l = arg(0), let c = arg(1), let o = arg(2) else {
                return error(L10n.tr("数値を指定してください．", comment: "STR_ERR_DLGMACRO16"))
            }
            view.macroMoveCursor(line: wtoi(l) - 1, column: wtoi(c) - 1, option: wtoi(o), layout: code == Code.moveCursorLayout)
        case Code.messageBox, Code.errorMsg, Code.warnMsg, Code.infoMsg, Code.okCancelBox, Code.yesNoBox:
            guard let message = arg(0) else { break }
            var values: [MacroValue] = [.string(message)]
            if code == Code.messageBox { values.append(.int(int(1))) }
            return handleFunction(code, values, view: view) != nil
        case Code.macroSleep, Code.setDrawSwitch:
            return handleFunction(code, [.int(int(0))], view: view) != nil
        case Code.chgTabWidth, Code.chgWrapColumn:
            break	// Mac 版にまだない（タブ幅・折り返し桁の一時変更）。キーマクロは止めない
        case Code.statusMsg:
            guard let message = arg(0) else {
                return error(L10n.tr("引数(文字列)が指定されていません．", comment: "STR_ERR_DLGMACRO07"))
            }
            // 0：ステータスバー、1：ステータスバーがなければメッセージボックス、2：ステータスバーの 2 つ目。Mac 版はどれも編集画面の左下
            view.sendStatusMessage(message)
        case Code.msgBeep:
            if int(0) != -1 { NSSound.beep() }
        case Code.clipboardEmpty:
            view.pasteboard.clearContents()
        case Code.setViewTop:
            guard let a = arg(0), let first = a.unicodeScalars.first, ("0"..."9").contains(first) else { return false }
            view.scrollRow(toTop: max(0, wtoi(a) - 1))
        case Code.setViewLeft:
            guard let a = arg(0), let first = a.unicodeScalars.first, ("0"..."9").contains(first) else { return false }
            let x = CGFloat(max(0, wtoi(a) - 1)) * view.charWidth
            view.scroll(NSPoint(x: x, y: view.visibleRect.minY))
        case Code.commitUndoBuffer, Code.addRefUndoBuffer, Code.setUndoBuffer, Code.appendUndoBufferCursor:
            break	// Mac 版の取り消しは編集のまとまりで管理する（マクロ全体が一つの取り消し単位）
        case Code.setQuoteString:
            // 共通設定: 引用符の設定（原版 Command_SET_QUOTESTRING）
            guard let quote = arg(0) else {
                return error(L10n.tr("引数(文字列)が指定されていません．", comment: "STR_ERR_DLGMACRO04"))
            }
            EditorCore.setCommonSetting(quote, section: "Common", key: "szInyouKigou")
        case Code.textWrapMethod:
            // テキストの折り返し方法：0 折り返さない、1 指定桁、2 右端（原版 WRAP_NO_TEXT_WRAP 等）
            let commands = [0: 31141, 1: 31142, 2: 31143]
            if let c = commands[int(0)] { _ = CommandTable.perform(c, from: view) }
        case Code.changeType:
            // タイプ別設定一時適用（原版 Command_CHANGETYPE：引数は番号 + 1。0 は今のタイプ）
            let n = int(0)
            let index = n == 0 ? view.document.typeIndex : n - 1
            if index >= 0 && index < EditorCore.typeSettings.count && view.document.changeTypeTemporarily(index) {
                view.typeSettingsReloaded()
                view.refreshOutline()
                MacroCommands.runAuto("nMacroOnTypeChanged", view: view)	// 原版 CEditDoc::OnChangeType
            }
        case 30210, 30211:	// F_UNDO、F_REDO
            undoRedo(code, view: view)
        case Code.execExtMacro:
            // 名前を指定してマクロ実行（引数：ファイル名かコード、言語の拡張子）。引数がなければパネル
            if let path = arg(0) { view.execExternalMacro(path: path, type: arg(1)) } else { _ = CommandTable.perform(code, from: view) }
        case Code.recKeyMacro, Code.saveKeyMacro, Code.loadKeyMacro, Code.execKeyMacro:
            _ = CommandTable.perform(code, from: view)
        default:
            // 引数が一つ目だけの命令・引数なしの命令（原版：HandleCommand( Index, true, 0 or Argument[0] )）
            _ = CommandTable.perform(code, from: view)
        }
        return true
    }

    /// 次を検索・前を検索・該当行マーク（原版 HandleCommand の F_SEARCH_NEXT 等）
    private static func macroSearch(_ code: Int, key: String, flag: Int, view: EditorTextView) {
        var options: EditorSearchOptions = []
        if flag & 0x01 != 0 { options.insert(.wholeWord) }
        if flag & 0x02 != 0 { options.insert(.matchCase) }
        if flag & 0x04 != 0 { options.insert(.regularExpression) }
        var addHistory = flag & 0x800 == 0
        let backup = flag & 0x1000 != 0
        let savedSettings = EditorCore.searchSettings
        let savedState = view.searchState
        if backup { addHistory = false }
        if !key.isEmpty {
            if options.contains(.regularExpression) && !EditorTextView.checkRegexpSyntax(key, options: options) { return }
            if (key as NSString).length < 260 && addHistory {
                EditorCore.addSearchKey(key)
                let s = EditorCore.searchSettings
                s.options = options
                EditorCore.searchSettings = s
            }
            view.searchState.key = key
            view.searchState.options = options
            view.searchState.updated = true
            view.searchState.sequence = EditorCore.searchKeySequence
        }
        let s = EditorCore.searchSettings
        s.notifyNotFound = flag & 0x08 != 0
        s.autoCloseFind = flag & 0x10 != 0
        s.searchAll = flag & 0x20 != 0
        EditorCore.searchSettings = s
        switch code {
        case Code.searchNext: view.searchNextCommand()
        case Code.searchPrev: view.searchPrevCommand()
        default: view.bookmarkPattern(nil)
        }
        if backup {
            EditorCore.searchSettings = savedSettings
            view.searchState = savedState
            view.needsDisplay = true
        }
    }

    /// 置換・すべて置換（原版 HandleCommand の F_REPLACE、F_REPLACE_ALL）
    private static func macroReplace(_ code: Int, key: String, replacement: String, flag: Int, view: EditorTextView) {
        var options: EditorSearchOptions = []
        if flag & 0x01 != 0 { options.insert(.wholeWord) }
        if flag & 0x02 != 0 { options.insert(.matchCase) }
        if flag & 0x04 != 0 { options.insert(.regularExpression) }
        var addHistory = flag & 0x800 == 0
        let backup = flag & 0x1000 != 0
        let savedSettings = EditorCore.searchSettings
        let savedState = view.searchState
        if backup { addHistory = false }
        if options.contains(.regularExpression) && !EditorTextView.checkRegexpSyntax(key, options: options) { return }
        if (key as NSString).length < 260 && addHistory {
            EditorCore.addSearchKey(key)
            let s = EditorCore.searchSettings
            s.options = options
            EditorCore.searchSettings = s
        }
        view.searchState.key = key
        view.searchState.options = options
        view.searchState.updated = true
        view.searchState.sequence = EditorCore.searchKeySequence
        if (replacement as NSString).length < 260 && addHistory { EditorCore.addReplaceKey(replacement) }
        let s = EditorCore.searchSettings
        s.notifyNotFound = flag & 0x08 != 0
        s.autoCloseFind = flag & 0x10 != 0
        s.searchAll = flag & 0x20 != 0
        let consecutiveAll = flag & 0x400 != 0
        let selectedArea = code == Code.replaceAll && flag & 0x80 != 0	// 置換する時は選べない
        if addHistory {
            s.consecutiveAll = consecutiveAll
            s.selectedArea = selectedArea
        }
        EditorCore.searchSettings = s
        let replaceOptions = EditorReplaceOptions(search: options, target: EditorReplaceTarget(rawValue: (flag >> 8) & 0x03) ?? .selection,
                                                  paste: flag & 0x40 != 0, searchAll: flag & 0x20 != 0,
                                                  consecutiveAll: consecutiveAll, selectedArea: selectedArea)
        if code == Code.replace {
            view.replaceCommand(replacement, options: replaceOptions)
        } else {
            _ = view.replaceAllCommand(replacement, options: replaceOptions)
        }
        if backup {
            EditorCore.searchSettings = savedSettings
            view.searchState = savedState
            view.needsDisplay = true
        }
    }

    // MARK: - 関数（原版 CMacro::HandleFunction）

    /// 値を返す関数。失敗（引数が足りない・変換できない・Mac 版にない関数）は nil
    static func handleFunction(_ code: Int, _ args: [MacroValue], view: EditorTextView) -> MacroValue? {
        func int(_ i: Int) -> Int? { i < args.count ? args[i].intValue : nil }
        func str(_ i: Int) -> String? { i < args.count ? args[i].text : nil }
        let document = view.document

        switch code {
        case Code.getFilename:
            return .string(document.path)
        case Code.getSaveFilename:
            return .string(MacroCommands.saveFilePath ?? document.path)	// 保存前の自動実行マクロでは保存先
        case Code.getSelected:
            return .string(view.macroSelectedText)
        case Code.expandParameter:
            guard args.count == 1, let source = str(0) else { return nil }
            return .string(document.expandParameter(source, view: view.expandParameterView))
        case Code.getLineStr:
            guard args.count == 1, let n = int(0), n > -1 else { return nil }
            let line = n == 0 ? view.caret.line : n - 1
            guard line < document.lineCount else { return .string("") }
            return .string(document.line(at: line, withEol: true))
        case Code.getLineCount:
            guard args.count == 1, int(0) == 0 else { return nil }
            return .int(document.lineCount)
        case Code.isTextSelected:
            return .int(view.boxRange != nil || (view.isBoxSelection && view.hasSelection) ? 2 : (view.hasSelection ? 1 : 0))
        case Code.getSelLineFrom, Code.getSelColumnFrom, Code.getSelLineTo, Code.getSelColumnTo:
            let sel = view.macroLayoutSelection
            switch code {
            case Code.getSelLineFrom: return .int(sel.from.line + 1)
            case Code.getSelColumnFrom: return .int(sel.from.x + 1)
            case Code.getSelLineTo: return .int(sel.to.line + 1)
            default: return .int(sel.to.x + 1)
            }
        case Code.isInsMode:
            return .int(document.insertMode ? 1 : 0)
        case Code.getCharCode:
            return .int(document.encoding)
        case Code.getLineCode:
            // 原版：0 CRLF、1 CR、2 LF、3 NEL、4 LS、5 PS
            let map: [EditorEol: Int] = [.crlf: 0, .cr: 1, .lf: 2, .nel: 3, .lineSeparator: 4, .paragraphSeparator: 5]
            return .int(map[document.newLineEol] ?? 0)
        case Code.isPossibleUndo:
            return .int(document.canUndo ? 1 : 0)
        case Code.isPossibleRedo:
            return .int(document.canRedo ? 1 : 0)
        case Code.compareVersion:
            guard args.count == 2, let a = str(0), let b = str(1) else { return nil }
            return .int(MacroCore.compareVersion(a, b))
        case Code.messageBox, Code.errorMsg, Code.warnMsg, Code.infoMsg, Code.okCancelBox, Code.yesNoBox:
            guard let message = str(0) else { return nil }
            var type = 0
            switch code {
            case Code.messageBox:
                if args.count >= 2 { guard let t = int(1) else { return nil }; type = t }
            case Code.errorMsg: type = 0x10
            case Code.warnMsg: type = 0x30
            case Code.infoMsg: type = 0x40
            case Code.okCancelBox: type = 0x01 | 0x20
            default: type = 0x04 | 0x20
            }
            return .int(messageBox(message, type))
        case Code.inputBox:
            guard let message = str(0) else { return nil }
            let defaultValue = args.count >= 2 ? (str(1) ?? "") : ""
            var maxLength = 260
            if args.count >= 3 { guard let n = int(2) else { return nil }; if n > 0 { maxLength = n } }
            return .string(inputBox(message, defaultValue, maxLength) ?? "")
        case Code.getClipboard:
            if args.count >= 1, int(0) == nil { return nil }
            return .string(view.clipboardText ?? "")
        case Code.setClipboard:
            var option = 0
            if args.count >= 1 { guard let n = int(0) else { return nil }; option = n }
            let value = args.count >= 2 ? (str(1) ?? "") : ""
            return .int(view.macroSetClipboard(value, column: option & 0x01 != 0, line: option & 0x02 != 0) ? 1 : 0)
        case Code.layoutToLogicLineNum:
            guard let n = int(0) else { return nil }
            let line = n - 1
            if line == document.layoutLineCount { return .int(document.lineCount + 1) }
            guard line >= 0, line < document.layoutLineCount else { return nil }
            return .int(document.logicPosition(of: EditorLayoutPosition(line: line, x: 0)).line + 1)
        case Code.lineColumnToIndex:
            guard args.count >= 2, let l = int(0), let c = int(1), l - 1 >= 0 else { return nil }
            return .int(document.logicPosition(of: EditorLayoutPosition(line: l - 1, x: (c - 1) * view.layoutUnit)).column + 1)
        case Code.logicToLayoutLineNum, Code.lineIndexToColumn:
            guard args.count >= 2, let l = int(0), let c = int(1), l - 1 >= 0 else { return nil }
            let p = document.layoutPosition(of: EditorPosition(line: l - 1, column: c - 1))
            return .int((code == Code.logicToLayoutLineNum ? p.line : p.x / view.layoutUnit) + 1)
        case Code.getCookie:
            guard args.count >= 2 else { return nil }
            return .string(document.cookie(scope: args[0].text, name: args[1].text))
        case Code.getCookieDefault:
            guard args.count >= 3 else { return nil }
            return .string(document.cookie(scope: args[0].text, name: args[1].text, defaultValue: args[2].text))
        case Code.setCookie:
            guard args.count >= 3 else { return nil }
            return .int(document.setCookie(scope: args[0].text, name: args[1].text, value: args[2].text))
        case Code.deleteCookie:
            guard args.count >= 2 else { return nil }
            return .int(document.deleteCookie(scope: args[0].text, name: args[1].text))
        case Code.getCookieNames:
            guard args.count >= 1 else { return nil }
            return .string(document.cookieNames(scope: args[0].text))
        case Code.setDrawSwitch:
            guard args.count >= 1, let n = int(0) else { return nil }
            let old = view.macroDrawSwitch
            view.macroDrawSwitch = n != 0
            return .int(old ? 1 : 0)
        case Code.getDrawSwitch:
            return .int(view.macroDrawSwitch ? 1 : 0)
        case Code.chgWrapColumn:
            // 折り返し桁を取得、設定する（原版：MINLINEKETAS 10 ～ MAXLINEKETAS 10240 なら指定桁で折り返す）
            guard args.count == 1, let n = int(0) else { return nil }
            let current = document.viewSettings.wrapColumns
            if (10...10240).contains(n) {
                _ = document.setWrap(.settingWidth, columns: n)
                view.contentDidChange()
            }
            return .int(current)
        case Code.fileOpenDialog, Code.fileSaveDialog:
            let initial = args.count >= 1 ? (str(0) ?? "") : ""
            if (initial as NSString).length >= 260 { return nil }
            return .string(fileDialog(code == Code.fileSaveDialog, initial) ?? "")
        case Code.folderDialog:
            let message = args.count >= 1 ? (str(0) ?? "") : ""
            let initial = args.count >= 2 ? (str(1) ?? "") : ""
            if (initial as NSString).length >= 260 { return nil }
            return .string(CommonSettingsPages.chooseFolder(message, initial) ?? "")
        case Code.isShownStatus:
            return .int(view.statusBarView != nil ? 1 : 0)	// ステータスバーを表示しているか（第 38 步）
        case Code.isTextSelectingLock:
            return .int(view.selectingLock ? (view.isBoxSelection ? 2 : 1) : 0)
        case Code.getViewLines:
            return .int(view.viewRowCount)
        case Code.getViewColumns:
            return .int(max(1, Int(floor((view.visibleRect.width - view.textOriginX) / view.charWidth))))
        case Code.getViewTop:
            return .int(view.topVisibleRow + 1)
        case Code.macroSleep:
            guard args.count == 1, let ms = int(0), ms >= 0 else { return nil }
            Thread.sleep(forTimeInterval: Double(ms) / 1000)
            return .int(0)
        default:
            return nil
        }
    }

    // MARK: - キーマクロへの記録（原版 CMacro::AddLParam）

    /// 記録する一行の引数。lParam は原版の HandleCommand の lparam1（文字コード等）。
    /// 検索・置換・ジャンプは原版と同じく画面・ダイアログの今の値を記録する（replace はダイアログの置換後文字列と置換の条件）
    static func recordedArgs(_ code: Int, view: EditorTextView, lParam: Int = 0, text: String? = nil,
                             replace: (text: String, options: EditorReplaceOptions)? = nil,
                             jump: EditorJumpOptions? = nil) -> [MacroArg] {
        let boxLockOption = view.document.editSettings.boxSelectLock ? 0x01 : 0x02
        switch code {
        case 30511, 30512, 30513, 30514, 30515, 30516, 30520, 30521, 30550, 30551:
            // F_UP_BOX 等：オプション（0 なら共通設定の「矩形選択移動で選択をロックする」）
            return [.int(lParam == 0 ? boxLockOption : lParam)]
        case 30530, 30532, 30533, 30540, 30541, 30542, 30543:
            // F_GOLINETOP_BOX、F_HalfPageUp_BOX 等：一つ目は数値（ページ系は行数）、二つ目がオプション
            var first = lParam
            if lParam == 0 && (code == 30540 || code == 30541) { first = view.viewRowCount / 2 }
            if lParam == 0 && (code == 30542 || code == 30543) { first = view.viewRowCount - 1 }
            return [.int(first), .int(boxLockOption)]
        case Code.insText, 30102, Code.execExtMacro:	// F_INSTEXT_W、F_FILEOPEN、F_EXECEXTMACRO
            return [.string(text ?? "")]
        case Code.jump:
            let options = jump ?? EditorJumpOptions(lineNumber: 0, lineNumIsCRLF: EditorCore.searchSettings.jumpLineNumIsCRLF,
                                                    plsql: JumpDialogController.shared.plsql, plsqlBlockFirstLine: 1)
            return [.int(options.lineNumber), .int((options.lineNumIsCRLF ? 0x01 : 0) | (options.plsql ? 0x02 : 0))]
        case Code.bookmarkPattern, Code.searchNext, Code.searchPrev:
            return [.string(view.searchState.key), .int(searchFlags(view.searchState.options))]
        case Code.replace, Code.replaceAll:
            let r = replace ?? (text: "", options: EditorReplaceOptions(search: view.searchState.options, target: .selection, paste: false,
                                                                         searchAll: false, consecutiveAll: false, selectedArea: false))
            let s = EditorCore.searchSettings
            var flag = searchFlags(view.searchState.options)
            if r.options.paste { flag |= 0x40 }
            if s.selectedArea { flag |= 0x80 }
            flag |= r.options.target.rawValue << 8
            if s.consecutiveAll { flag |= 0x400 }
            return [.string(view.searchState.key), .string(r.text), .int(flag)]
        case Code.chgmodEol:
            let map: [EditorEol: Int] = [.crlf: 1, .lf: 3, .cr: 4, .nel: 5, .lineSeparator: 6, .paragraphSeparator: 7]
            return [.int(map[EditorEol(rawValue: lParam) ?? .none] ?? 0)]
        case 30340, 30341, 30440, 30441:	// F_HalfPageUp・Down（_Sel）
            return [.int(lParam == 0 ? view.viewRowCount / 2 : lParam)]
        case 30342, 30343, 30442, 30443:	// F_1PageUp・Down（_Sel）
            return [.int(lParam == 0 ? view.viewRowCount - 1 : lParam)]
        default:
            return [.int(lParam)]	// 標準も数値を一つ（F_WCHAR の文字コード等）
        }
    }

    /// 検索の条件 → マクロの引数のフラグ
    private static func searchFlags(_ options: EditorSearchOptions) -> Int {
        let s = EditorCore.searchSettings
        var flag = 0
        if options.contains(.wholeWord) { flag |= 0x01 }
        if options.contains(.matchCase) { flag |= 0x02 }
        if options.contains(.regularExpression) { flag |= 0x04 }
        if s.notifyNotFound { flag |= 0x08 }
        if s.autoCloseFind { flag |= 0x10 }
        if s.searchAll { flag |= 0x20 }
        return flag
    }

    /// _wtoi：先頭の空白・符号・数字だけ読む（数字がなければ 0）
    static func wtoi(_ s: String) -> Int {
        var result = 0
        var sign = 1
        var started = false
        for ch in s.unicodeScalars {
            if !started {
                if ch == " " || ch == "\t" || ch == "\n" || ch == "\r" { continue }
                started = true
                if ch == "-" { sign = -1; continue }
                if ch == "+" { continue }
            }
            guard let d = Int(String(ch)), ("0"..."9").contains(ch) else { break }
            result = result &* 10 &+ d
            if result > Int(Int32.max) { return sign > 0 ? Int(Int32.max) : Int(Int32.min) }
        }
        return Int(Int32(truncatingIfNeeded: result * sign))
    }
}

// MARK: - 編集画面の側（マクロ用の操作）

extension EditorTextView {
    /// 文字入力（原版 Command_WCHAR、Command_IME_CHAR）：CR・LF は改行、TAB は TAB 入力、ほかは一文字入力
    func macroInsertCharacter(_ value: Int, code: Int) {
        var value = value, code = code
        // CharIme の上位バイトが 0 なら Char と同じ（原版 Command_IME_CHAR）
        if code == MacroHost.Code.imeChar && value & 0xff00 == 0 {
            value &= 0xff
            code = MacroHost.Code.wchar
        }
        if code == MacroHost.Code.wchar && (value == 0x0D || value == 0x0A) {
            insertNewline(nil)
            return
        }
        if value == 0x09 && code == MacroHost.Code.wchar {
            insertTab(nil)
            return
        }
        guard let scalar = Unicode.Scalar(UInt32(truncatingIfNeeded: value & 0xFFFF)) ?? Unicode.Scalar(0xFFFD) else { return }
        insertText(String(Character(scalar)), replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    /// テキストを貼り付け（原版 Command_INSTEXT）：選択範囲を置き換え、カーソルは挿入した文字の後
    func macroInsertText(_ text: String) {
        document.beginEdit()
        var at = caret
        if let box = boxRange {
            at = document.deleteBox(box)
        } else if let selection {
            document.delete(selection)
            at = selection.from
        }
        var end = EditorPosition()
        document.replace(EditorRange(from: at, to: at), with: text, newEnd: &end)
        document.endEdit()
        clearSelection()
        setCaret(end)
        textChanged()
    }

    /// 最後にテキストを追加（原版 Command_ADDTAIL）：ファイルの最後に移動して挿入
    func macroAddTail(_ text: String) {
        clearSelection()
        let at = document.endPosition
        var end = EditorPosition()
        document.replace(EditorRange(from: at, to: at), with: text, newEnd: &end)
        setCaret(end)
        textChanged()
    }

    /// カーソル移動（原版 Command_MOVECURSOR・MOVECURSORLAYOUT）。option：0x01 選択、0x02 矩形選択
    func macroMoveCursor(line: Int, column: Int, option: Int, layout: Bool) {
        var target: EditorPosition
        if layout {
            target = document.logicPosition(of: EditorLayoutPosition(line: max(0, line), x: max(0, column) * layoutUnit))
        } else {
            target = EditorPosition(line: max(0, line), column: max(0, column))
        }
        let end = document.endPosition
        if target.line > end.line { target = end }
        target = EditorPosition(line: target.line, column: min(target.column, lineLength(target.line)))
        if option & 0x02 != 0 {
            // 矩形選択（通常選択からも矩形選択に変える）
            if !isBoxSelection { beginBoxSelection(lock: false) }
            extendingSelection = true
            setCaret(target)
            extendingSelection = false
            boxEnd = caretBoxPoint
            needsDisplay = true
        } else if option & 0x01 != 0 {
            modifySelection { setCaret(target) }
        } else {
            if hasSelection { clearSelection() }
            setCaret(target)
        }
    }

    /// 選択範囲の文字（原版 GetSelectedDataSimple。矩形選択は行ごとに改行）
    var macroSelectedText: String {
        if let box = boxRange { return document.boxText(box) }
        if let selection { return document.text(in: selection) }
        return ""
    }

    /// 排版の横位置（点）の半角一桁の幅。マクロの桁は原版と同じく半角単位
    var layoutUnit: Int { max(1, document.charWidth) }

    /// 選択範囲の排版位置（原版 m_sSelect。桁は半角単位。選択がないときはカーソル位置）
    var macroLayoutSelection: (from: EditorLayoutPosition, to: EditorLayoutPosition) {
        func keta(_ p: EditorLayoutPosition) -> EditorLayoutPosition { EditorLayoutPosition(line: p.line, x: p.x / layoutUnit) }
        if let box = boxRange {
            return (keta(EditorLayoutPosition(line: box.top, x: box.left)), keta(EditorLayoutPosition(line: box.bottom, x: box.right)))
        }
        if let selection {
            return (keta(document.layoutPosition(of: selection.from)), keta(document.layoutPosition(of: selection.to)))
        }
        let p = keta(document.layoutPosition(of: caret))
        return (p, p)
    }

    /// クリップボードに設定（原版 MySetClipboardData）
    func macroSetClipboard(_ text: String, column: Bool, line: Bool) -> Bool {
        pasteboard.clearContents()
        var types: [NSPasteboard.PasteboardType] = [.string]
        if column { types.append(Self.columnSelectType) }
        if line { types.append(Self.lineSelectType) }
        pasteboard.declareTypes(types, owner: nil)
        var ok = pasteboard.setString(text, forType: .string)
        if column { ok = pasteboard.setString("", forType: Self.columnSelectType) && ok }
        if line { ok = pasteboard.setString("", forType: Self.lineSelectType) && ok }
        return ok
    }

    /// 再描画スイッチ（原版 SetDrawSwitch。Mac 版は値を覚えるだけ）
    var macroDrawSwitch: Bool {
        get { (objc_getAssociatedObject(self, &MacroDrawSwitchKey.key) as? Bool) ?? true }
        set { objc_setAssociatedObject(self, &MacroDrawSwitchKey.key, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    /// ExpandParameter の画面の側の値
    var expandParameterView: ExpandParameterView {
        let v = ExpandParameterView()
        v.selectedText = hasSelection ? macroSelectedText : currentTextForSearch()
        v.caret = caret
        v.grepMode = sakuraDocument?.isGrepMode ?? false
        v.grepKey = sakuraDocument?.grepKey ?? ""
        v.macroPath = MacroHost.currentMacroPath
        v.recordingKeyMacro = KeyMacroRecorder.shared.isRecording(in: window)
        v.minimized = window?.isMiniaturized ?? false
        let now = Date()
        let common = { (key: String) in EditorCore.commonSetting(section: "Common", key: key) ?? "" }
        v.date = WindowsDateFormat.date(now, type: Int(common("nDateFormatType")) ?? 0, format: common("szDateFormat"))
        v.time = WindowsDateFormat.time(now, type: Int(common("nTimeFormatType")) ?? 0, format: common("szTimeFormat"))
        if !document.path.isEmpty,
           let modified = (try? FileManager.default.attributesOfItem(atPath: document.path))?[.modificationDate] as? Date {
            v.fileDate = WindowsDateFormat.date(modified, type: Int(common("nDateFormatType")) ?? 0, format: common("szDateFormat"))
            v.fileTime = WindowsDateFormat.time(modified, type: Int(common("nTimeFormatType")) ?? 0, format: common("szTimeFormat"))
        }
        v.appName = AboutPanel.appName
        v.appPath = Bundle.main.bundlePath
        v.version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        return v
    }
}

private enum MacroDrawSwitchKey {
    static var key = 0
}

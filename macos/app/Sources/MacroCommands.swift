// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge

/// 登録マクロ（共通設定『マクロ』の一覧）の一つ（原版 MacroRec）
struct MacroEntry: Equatable {
    var name: String
    var file: String
    var reloadWhenExecute: Bool
    /// 原版 MacroRec::IsEnabled：ファイル名があるとき
    var isEnabled: Bool { !file.isEmpty }
}

/// マクロのファイルを実行する命令（第 45 步。原版 CViewCommander_Macro.cpp の Command_EXECEXTMACRO、
/// CViewCommander::HandleCommand の F_USERMACRO_0、CEditDoc::RunAutoMacro、CSMacroMgr の登録マクロ）。
///
/// - 名前を指定してマクロ実行（F_EXECEXTMACRO）：開くパネル（マクロ用フォルダー）で選んだファイルを拡張子で実行する。
///   .mac はキーマクロ、.js は JScript（JSMacro.swift）。原版の .vbs .ppa .py 等は Mac 版で使えないことを知らせる
/// - 登録済みマクロ（F_USERMACRO_0 + n、ツール > 登録済みマクロ）、自動実行（ファイルを開いた後・タイプ変更後・保存前。Shift を押していれば実行しない）
/// - 登録マクロは一度読んだら覚えておき、「実行するたびに読み込みなおす」のときは毎回読む（原版 CSMacroMgr::Exec）。共通設定を変えたら忘れる（原版 UnloadAll）
enum MacroCommands {
    /// 登録マクロの最大数（原版 MAX_CUSTMACRO）
    static let maxCount = 50
    /// 登録マクロの最初の機能番号（F_USERMACRO_0）
    static let userMacroCode = 31600

    /// 原版 [Macro] の項目名（CDataProfile::IOProfileData<MacroRec>）
    static func key(_ prefix: String, _ index: Int) -> String {
        prefix + String(format: "[%03d]", index)
    }

    static func entry(_ index: Int) -> MacroEntry {
        func value(_ prefix: String) -> String { EditorCore.commonSetting(section: "Macro", key: key(prefix, index)) ?? "" }
        return MacroEntry(name: value("Name"), file: value("File"), reloadWhenExecute: value("ReloadWhenExecute") == "1")
    }

    static var entries: [MacroEntry] { (0..<maxCount).map(entry) }

    /// 登録マクロのファイルのフルパス（原版 CShareData::GetMacroFilename：絶対パスかマクロ用フォルダーがなければそのまま）
    static func path(of entry: MacroEntry) -> String {
        let file = entry.file
        if file.isEmpty || file.hasPrefix("/") { return file }
        return (KeyMacroRecorder.macroFolder as NSString).appendingPathComponent(file)
    }

    /// 読み込んだ登録マクロ（原版 m_cSavedKeyMacro）
    private static var loaded: [Int: LoadedMacro] = [:]
    private static var observer: NSObjectProtocol?

    enum LoadedMacro {
        case key([MacroCall])
        case script(String)
    }

    /// 自動実行の再入を防ぐ（原版 RunAutoMacro の bRunning）
    private static var runningAuto = false
    /// 保存前の自動実行マクロの GetSaveFilename（原版 m_cDocFile.SetSaveFilePath）
    static var saveFilePath: String?

    /// 読み込みの結果
    enum Load {
        case success(LoadedMacro)
        case failure
        case encodingError
        case unsupported(String)	// 拡張子
    }

    /// ファイルを読む（原版 CSMacroMgr::Load。拡張子で種類を決める。type はコードの言語の拡張子（ファイルのときは nil））
    static func load(path: String, code: String? = nil, type: String? = nil) -> Load {
        let kindPath = type.map { "macro." + $0 } ?? path
        switch MacroCore.kind(ofPath: kindPath) {
        case .key:
            let result = code.map { MacroCore.parseKeyMacro($0) }
                ?? BookmarkStore.settingFiles.withAccess(path: path) { MacroCore.loadKeyMacroFile(path) }
            switch result.result {
            case .success: return .success(.key(result.calls))
            case .encodingError: return .encodingError
            default:
                if !result.errorMessage.isEmpty { MacroHost.showError(result.errorTitle, result.errorMessage) }
                return .failure
            }
        case .jScript:
            if let code { return .success(.script(code)) }
            var r = MacroLoadResult.failure
            let source = BookmarkStore.settingFiles.withAccess(path: path) { MacroCore.loadSourceFile(path, result: &r) }
            if let source { return .success(.script(source)) }
            return r == .encodingError ? .encodingError : .failure
        case .unsupported:
            return .unsupported((kindPath as NSString).pathExtension)
        default:
            return .failure
        }
    }

    /// 読んだマクロを実行する
    @discardableResult
    static func run(_ macro: LoadedMacro, path: String, view: EditorTextView) -> Bool {
        switch macro {
        case .key(let calls):
            view.runKeyMacro(calls, path: path)
            return true
        case .script(let source):
            return JSMacroRunner(view: view, source: source, path: path).run()
        }
    }

    /// Mac 版で使えない種類のマクロ（.vbs .ppa .py 等）
    static func showUnsupported(_ ext: String, path: String) {
        MacroHost.showError(AboutPanel.appName, String(format: NSLocalizedString(
            "このマクロ（.%@）は Mac 版では実行できません。\nMac 版で使えるのはキーマクロ（.mac）と JScript（.js）です。\n\n%@",
            comment: "マクロの種類（Mac 版）"), ext, path))
    }

    /// 登録マクロを実行する（原版 CSMacroMgr::Exec。読み込み前か「実行するたびに読み込みなおす」なら読む）
    static func execUserMacro(_ index: Int, view: EditorTextView) {
        installObserver()
        let entry = entry(index)
        guard entry.isEnabled else { return }
        let path = path(of: entry)
        var macro = entry.reloadWhenExecute ? nil : loaded[index]
        if macro == nil {
            switch load(path: path) {
            case .success(let m):
                macro = m
                loaded[index] = m
            case .encodingError:
                MacroHost.showError(AboutPanel.appName, String(format: NSLocalizedString(
                    "文字コードの変換に失敗しました。\nBOM付きUTF-8またはShift_JIS等で保存されているか確認してください。\n\n%@", comment: "STR_ERR_MACRO_ENCODING"), entry.file))
                return
            case .unsupported(let ext):
                showUnsupported(ext, path: path)
                return
            case .failure:
                MacroHost.showError(AboutPanel.appName, String(format: NSLocalizedString(
                    "マクロ %d (%@) の実行に失敗しました。", comment: "STR_ERR_MACRO1"), index, entry.file))
                return
            }
        }
        if let macro { run(macro, path: path, view: view) }
    }

    /// 共通設定が変わったら読んだマクロを忘れる
    private static func installObserver() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: EditorTextView.commonSettingsDidChangeNotification, object: nil, queue: .main) { _ in
            loaded.removeAll()
        }
    }

    static func forgetLoaded() { loaded.removeAll() }

    /// 自動実行マクロ（原版 CEditDoc::RunAutoMacro）。key は nMacroOnOpened・nMacroOnTypeChanged・nMacroOnSave
    static func runAuto(_ key: String, view: EditorTextView, savePath: String? = nil) {
        guard !runningAuto, let index = Int(EditorCore.commonSetting(section: "Macro", key: key) ?? ""),
              (0..<maxCount).contains(index), entry(index).isEnabled,
              !NSEvent.modifierFlags.contains(.shift) else { return }	// Shift キーが押されていなければ実行
        runningAuto = true
        saveFilePath = savePath
        KeyMacroRecorder.shared.suppressed += 1	// 自動実行マクロで発行したコマンドはキーマクロに保存しない
        execUserMacro(index, view: view)
        KeyMacroRecorder.shared.suppressed -= 1
        saveFilePath = nil
        runningAuto = false
    }
}

// MARK: - コマンド

extension EditorTextView {
    /// 開くパネル（原版 DoModal_GetOpenFileName、すべてのファイル）。単体テストで差し替える
    static var chooseMacroFile: (String, NSWindow?) -> URL? = { folder, _ in
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: folder, isDirectory: true)
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = NSLocalizedString("名前を指定してマクロ実行", comment: "F_EXECEXTMACRO")
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// ツール > 名前を指定してマクロ実行…（F_EXECEXTMACRO）
    @objc func execExternalMacro(_ sender: Any?) {
        guard let url = Self.chooseMacroFile(KeyMacroRecorder.macroFolder, window) else { return }
        BookmarkStore.settingFiles.remember(url)
        execExternalMacro(path: url.path, type: nil)
    }

    /// 名前を指定してマクロ実行（原版 Command_EXECEXTMACRO）。type が nil でなければ path はマクロのコード、type は言語の拡張子
    func execExternalMacro(path: String, type: String?) {
        // キーマクロ記録中なら、このコマンドを記録して、実行中は記録を止める
        let recorder = KeyMacroRecorder.shared
        if recorder.isRecording(in: window) && recorder.suppressed == 0 {
            recorder.calls.append(MacroCall(code: MacroHost.Code.execExtMacro, args: [.string(path)]))
        }
        recorder.suppressed += 1
        defer { recorder.suppressed -= 1 }
        let isCode = type != nil
        switch MacroCommands.load(path: isCode ? "" : path, code: isCode ? path : nil, type: type) {
        case .success(let macro):
            MacroCommands.run(macro, path: isCode ? "" : path, view: self)
        case .encodingError:
            MacroHost.showError(AboutPanel.appName, String(format: NSLocalizedString(
                "文字コードの変換に失敗しました。\nBOM付きUTF-8またはShift_JIS等で保存されているか確認してください。\n\n%@", comment: "STR_ERR_MACRO_ENCODING"), path))
        case .unsupported(let ext):
            MacroCommands.showUnsupported(ext, path: path)
        case .failure:
            MacroHost.showError(AboutPanel.appName, String(format: NSLocalizedString(
                "マクロの読み込みに失敗しました。\n\n%@", comment: "STR_ERR_MACROERR1"), path))
        }
    }

    /// ツール > 登録済みマクロ の項目（F_USERMACRO_0 + n）
    @objc func userMacro(_ sender: Any?) {
        guard let code = Self.commandCode(of: sender),
              (MacroCommands.userMacroCode..<MacroCommands.userMacroCode + MacroCommands.maxCount).contains(code) else { return }
        MacroCommands.execUserMacro(code - MacroCommands.userMacroCode, view: self)
    }

    /// ファイル > このファイルのパス名・ファイル名・フォルダー名をコピー（原版 Command_COPYPATH・COPYFILENAME・COPYDIRPATH）。
    /// ファイル名がない（無題）ときはビープ
    @objc func copyPathCommand(_ sender: Any?) {
        let path = document.path
        guard !path.isEmpty, let code = Self.commandCode(of: sender) else {
            NSSound.beep()
            return
        }
        let text: String
        switch code {
        case 30622: text = (path as NSString).lastPathComponent			// F_COPYFNAME
        case 30631: text = (path as NSString).deletingLastPathComponent	// F_COPYDIRPATH（末尾の区切りなし）
        default: text = path											// F_COPYPATH
        }
        _ = macroSetClipboard(text, column: false, line: false)
    }
}

/// ツール > 登録済みマクロ の子メニュー（原版 CEditWnd::InitMenu の F_USERMACRO_LIST：名前がなければファイル名）
final class UserMacroMenu: NSObject, NSMenuDelegate {
    static let shared = UserMacroMenu()

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for (i, entry) in MacroCommands.entries.enumerated() where entry.isEnabled {
            let item = NSMenuItem(title: entry.name.isEmpty ? entry.file : entry.name,
                                  action: #selector(EditorTextView.userMacro(_:)), keyEquivalent: "")
            item.tag = MacroCommands.userMacroCode + i
            menu.addItem(item)
        }
    }
}

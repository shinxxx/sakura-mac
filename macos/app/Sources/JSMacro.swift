// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge
import JavaScriptCore

/// JScript マクロ（.js）を JavaScriptCore で実行する（第 45 步。原版 CWSH.cpp、CWSHIfObj.cpp、CWSHManager.cpp、CIfObj.cpp）。
///
/// - 原版は Windows Script Host の JScript エンジンに「Editor」オブジェクトをグローバルメンバー付きで渡す（AddNamedItem SCRIPTITEM_GLOBALMEMBERS）。
///   Mac 版はスクリプト全体を `with (Proxy) { … }` で包み、マクロの命令・関数の名前（大文字小文字を区別しない。原版 GetIDsOfNames の _wcsicmp）を
///   その Proxy で解決する。スクリプトで宣言した名前（var・function）が先。`Editor.Xxx()` も同じ
/// - 括弧のない呼び出し（`GetFilename`、`SelectWord;`）は読み込み時に `()` を足す（MacroCore.prepareJScript。JScript は DISPATCH_PROPERTYGET でも実行する）
/// - 命令の引数は文字列に直して MacroHost.handleCommand（原版 MacroCommand：VariantChangeType VT_BSTR）、戻り値なし。
///   関数は値のまま MacroHost.handleFunction、失敗（原版 E_FAIL）は JavaScript の例外
/// - `new ActiveXObject("WScript.Shell")` の Popup だけ使える（ヘルプのサンプルが使う）。ほかの ProgID は原版の「オブジェクトを作成できません」
/// - スクリプトは別のスレッドで実行し、画面の操作はメインスレッドに頼む。共通設定「キャンセル確認待ち時間」（nMacroCancelTimer）を過ぎると
///   原版 IDD_MACRORUNNING と同じ「マクロ実行中・・・」の窓口を出す。キャンセルすると、次に命令・関数を呼んだところで
///   「マクロの実行を中断しました。」の例外にする。JavaScriptCore には実行中のスクリプトを外から止める公開の方法がないので、
///   命令・関数を呼ばない無限ループは止められない（キャンセルから 2 秒待って戻り、スレッドは放っておく）
/// - エラーは原版 MacroError と同じくメッセージボックス（「[Line n] 説明」）
/// - マクロ全体が一つの取り消し単位。マクロの中の命令はキーマクロに記録しない
final class JSMacroRunner {
    /// キャンセルの窓口を出した（単体テスト用。窓口が出たときに呼ぶ）
    static var cancelPanelDidShow: ((JSMacroRunner) -> Void)?
    /// WScript.Shell の Popup（単体テストで差し替える）。引数は文字、秒（0 は待つ）、タイトル、種類（MB_*）。戻り値はボタン（タイムアウトは -1）
    static var popup: (String, Int, String, Int) -> Int = { text, seconds, title, type in
        let alert = NSAlert()
        alert.messageText = title.isEmpty ? "Windows Script Host" : title
        alert.informativeText = text
        switch type & 0xF0 {
        case 0x10: alert.alertStyle = .critical
        case 0x30: alert.alertStyle = .warning
        default: alert.alertStyle = .informational
        }
        let buttons: [(String, Int)]
        switch type & 0x0F {
        case 1: buttons = [("OK", 1), (L10n.tr("キャンセル", comment: "MB_OKCANCEL"), 2)]
        case 2: buttons = [(L10n.tr("中止", comment: "MB_ABORTRETRYIGNORE"), 3), (L10n.tr("再試行", comment: "MB_ABORTRETRYIGNORE"), 4),
                           (L10n.tr("無視", comment: "MB_ABORTRETRYIGNORE"), 5)]
        case 3: buttons = [(L10n.tr("はい", comment: "MB_YESNOCANCEL"), 6), (L10n.tr("いいえ", comment: "MB_YESNOCANCEL"), 7),
                           (L10n.tr("キャンセル", comment: "MB_YESNOCANCEL"), 2)]
        case 4: buttons = [(L10n.tr("はい", comment: "MB_YESNO"), 6), (L10n.tr("いいえ", comment: "MB_YESNO"), 7)]
        case 5: buttons = [(L10n.tr("再試行", comment: "MB_RETRYCANCEL"), 4), (L10n.tr("キャンセル", comment: "MB_RETRYCANCEL"), 2)]
        default: buttons = [("OK", 1)]
        }
        for b in buttons { alert.addButton(withTitle: b.0) }
        var timer: Timer?
        if seconds > 0 {
            // 秒数が過ぎたら閉じる（-1）
            timer = Timer(timeInterval: TimeInterval(seconds), repeats: false) { _ in NSApp.abortModal() }
            RunLoop.main.add(timer!, forMode: .modalPanel)
        }
        let response = alert.runModal()
        timer?.invalidate()
        if response == .abort { return -1 }
        let index = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        return buttons.indices.contains(index) ? buttons[index].1 : 1
    }

    /// 中断のメッセージ（原版 STR_ERR_CWSH09）
    static var abortMessage: String { L10n.tr("マクロの実行を中断しました。", comment: "STR_ERR_CWSH09") }

    let view: EditorTextView
    let source: String
    let path: String

    private let lock = NSLock()
    /// メインスレッドの実行ループ：スクリプトの頼みが来たら起こす。待っている間もこのモードとパネルのモードで回す
    /// （キャンセルの窓口の操作・アクセシビリティの問い合わせを受け付ける。ほかの窓口の操作は受け付けない。原版も実行中は応答しない）
    private static let waitMode = RunLoop.Mode("SakuraMacroWait")
    private var requests: [() -> Void] = []
    private var finished = false
    private var abandoned = false
    private(set) var canceled = false
    private var error: (title: String, message: String)?
    private var cancelPanel: MacroCancelPanel?

    init(view: EditorTextView, source: String, path: String) {
        self.view = view
        self.source = source
        self.path = path
    }

    /// 実行してエラーがなければ true（メインスレッドで呼ぶ）
    @discardableResult
    func run() -> Bool {
        let prepared = MacroCore.prepareJScript(source)
        let thread = Thread { [self] in
            autoreleasepool { evaluate(prepared) }
            lock.lock()
            finished = true
            lock.unlock()
            wakeMain()
        }
        thread.stackSize = 8 << 20
        thread.name = "SakuraJSMacro"

        let previousPath = MacroHost.currentMacroPath
        MacroHost.currentMacroPath = path
        KeyMacroRecorder.shared.suppressed += 1	// マクロの中の命令は記録しない（原版 FA_NONRECORD）
        MacroHost.beginMacroEdit(view.document)
        thread.start()
        waitForScript()
        MacroHost.endMacroEdit(view.document)
        KeyMacroRecorder.shared.suppressed -= 1
        MacroHost.currentMacroPath = previousPath
        view.contentDidChange(keepCaches: true)
        if let error {
            MacroHost.showError(error.title, error.message)
            return false
        }
        if canceled {	// 命令を呼ばないループを中断した
            MacroHost.showError(L10n.tr("JScript 実行時エラー", comment: "WSH のエラーの種類（Mac 版）"), Self.abortMessage)
            return false
        }
        return !canceled
    }

    /// スクリプトが終わるまで、頼まれた画面の操作を実行する。待ち時間を過ぎたらキャンセルの窓口
    private func waitForScript() {
        let start = Date()
        let timer = max(0, Int(EditorCore.commonSetting(section: "Macro", key: "nMacroCancelTimer") ?? "") ?? 0)
        var session: NSApplication.ModalSession?
        var canceledAt: Date?
        // 実行ループは入力元がないとすぐ戻るので、何もしないタイマーを置く
        let keepAlive = Timer(timeInterval: 1, repeats: true) { _ in }
        RunLoop.current.add(keepAlive, forMode: Self.waitMode)
        defer { keepAlive.invalidate() }
        while true {
            RunLoop.current.run(mode: session == nil ? Self.waitMode : .modalPanel, before: Date().addingTimeInterval(0.05))
            lock.lock()
            let work = requests
            requests.removeAll()
            let done = finished
            lock.unlock()
            for w in work { w() }
            if done { break }
            if timer > 0 && cancelPanel == nil && Date().timeIntervalSince(start) >= TimeInterval(timer) {
                let panel = MacroCancelPanel(documentPath: view.document.path)
                cancelPanel = panel
                session = NSApp.beginModalSession(for: panel.window)
                Self.cancelPanelDidShow?(self)
            }
            if let s = session, let panel = cancelPanel {
                _ = NSApp.runModalSession(s)
                if panel.canceled && !canceled { cancel() }
            }
            if canceled {
                if canceledAt == nil { canceledAt = Date() }
                // 命令・関数を呼ばない無限ループは止められない：待つのをやめる
                if let at = canceledAt, Date().timeIntervalSince(at) > 2 {
                    lock.lock()
                    abandoned = true
                    let rest = requests
                    requests.removeAll()
                    lock.unlock()
                    for w in rest { w() }	// 待っているスレッドを放す（中身は中断済みとして実行しない）
                    break
                }
            }
        }
        if let s = session { NSApp.endModalSession(s) }
        cancelPanel?.close()
        cancelPanel = nil
    }

    /// メインスレッドの実行ループを起こす（待ちのモード・パネルのモードのどちらでも）
    private func wakeMain() {
        let main = CFRunLoopGetMain()
        let modes = [Self.waitMode.rawValue, RunLoop.Mode.modalPanel.rawValue] as CFArray
        CFRunLoopPerformBlock(main, modes) {}
        CFRunLoopWakeUp(main)
    }

    /// キャンセル（原版 CDlgCancel → InterruptScriptThread）
    func cancel() {
        lock.lock()
        canceled = true
        lock.unlock()
        cancelPanel?.close()
    }

    private var isCanceled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return canceled || abandoned
    }

    /// メインスレッドで実行して結果を返す（スクリプトのスレッドから）。中断されたときは nil
    private func onMain<T>(_ body: @escaping () -> T) -> T? {
        if isCanceled { return nil }
        let done = DispatchSemaphore(value: 0)
        var result: T?
        lock.lock()
        if abandoned {
            lock.unlock()
            return nil
        }
        requests.append { [self] in
            if !isCanceled { result = body() }
            done.signal()
        }
        lock.unlock()
        wakeMain()
        done.wait()
        return result
    }

    // MARK: - スクリプトのスレッド

    private func evaluate(_ prepared: String) {
        guard let context = JSContext() else { return }
        var firstError: (title: String, message: String)?
        context.exceptionHandler = { [weak self] _, exception in
            guard firstError == nil, let exception else { return }
            let line = self?.macroLine(of: exception) ?? Int(exception.objectForKeyedSubscript("line")?.toInt32() ?? 0)
            var message = exception.objectForKeyedSubscript("message")?.toString() ?? exception.toString() ?? ""
            if message.isEmpty || message == "undefined" { message = exception.toString() ?? "" }
            let isSyntax = exception.objectForKeyedSubscript("name")?.toString() == "SyntaxError"
            let title = isSyntax ? L10n.tr("JScript コンパイル エラー", comment: "WSH のエラーの種類（Mac 版）")
                : L10n.tr("JScript 実行時エラー", comment: "WSH のエラーの種類（Mac 版）")
            firstError = (title, String(format: "[Line %d] %@", line, message))
            if self?.isCanceled == true {
                firstError = (title, String(format: "[Line %d] %@", line, Self.abortMessage))
            }
        }
        installHost(context)
        // 行番号が変わらないように一行目に続けて包む
        context.evaluateScript("with(__sakuraScope){" + prepared + "\n}", withSourceURL: macroURL)
        lock.lock()
        error = firstError
        lock.unlock()
    }

    /// マクロのファイルの中の行番号（命令・関数の中で投げた例外は、呼び出し元のマクロの行）
    private func macroLine(of exception: JSValue) -> Int? {
        let url = macroURL.absoluteString
        if exception.objectForKeyedSubscript("sourceURL")?.toString() == url {
            return Int(exception.objectForKeyedSubscript("line")?.toInt32() ?? 0)
        }
        // stack：「名前@URL:行:桁」が一行ずつ
        guard let stack = exception.objectForKeyedSubscript("stack")?.toString() else { return nil }
        for frame in stack.split(separator: "\n") {
            guard let range = frame.range(of: url + ":") else { continue }
            let rest = frame[range.upperBound...]
            if let line = Int(rest.prefix { $0.isNumber }) { return line }
        }
        return nil
    }

    private var macroURL: URL { URL(fileURLWithPath: path.isEmpty ? "/macro.js" : path) }

    /// Editor オブジェクト・グローバルの名前・ActiveXObject
    private func installHost(_ context: JSContext) {
        let has: @convention(block) (String) -> Bool = { name in MacroCore.findFunctionIgnoreCase(name) != nil }
        let call: @convention(block) (String) -> Any? = { [weak self] name in
            let args = Array((JSContext.currentArguments() as? [JSValue] ?? []).dropFirst())
            return self?.invoke(name, args)
        }
        let popup: @convention(block) (String, Int, String, Int) -> Any? = { [weak self] text, seconds, title, type in
            guard let self else { return nil }
            guard let r = self.onMain({ Self.popup(text, seconds, title, type) }) else {
                Self.throwError(Self.abortMessage)
                return nil
            }
            return r
        }
        context.setObject(has, forKeyedSubscript: "__sakuraHas" as NSString)
        context.setObject(call, forKeyedSubscript: "__sakuraCall" as NSString)
        context.setObject(popup, forKeyedSubscript: "__sakuraPopup" as NSString)
        context.setObject(L10n.tr("オートメーション サーバーはオブジェクトを作成できません", comment: "JScript 800A01AD"),
                          forKeyedSubscript: "__sakuraNoObject" as NSString)
        context.evaluateScript("""
        var __sakuraScope = (function (g) {
            var has = __sakuraHas, call = __sakuraCall;
            function method(name) {
                return function () { return call.apply(null, [name].concat(Array.prototype.slice.call(arguments))); };
            }
            var editor = new Proxy({}, {
                has: function (t, n) { return typeof n === 'string' && has(n); },
                get: function (t, n) { return (typeof n === 'string' && has(n)) ? method(n) : undefined; }
            });
            g.Editor = editor;
            g.ActiveXObject = function (progId) {
                if (String(progId).toLowerCase() === 'wscript.shell') {
                    this.Popup = function (text, seconds, title, type) {
                        return __sakuraPopup(String(text), seconds | 0, title === undefined ? '' : String(title), type | 0);
                    };
                    return;
                }
                throw new Error(__sakuraNoObject);
            };
            return new Proxy({}, {
                has: function (t, n) { return typeof n === 'string' && !(n in g) && has(n); },
                get: function (t, n) { return typeof n === 'string' ? method(n) : undefined; }
            });
        })(this);
        """, withSourceURL: URL(string: "sakura-macro:prelude"))
    }

    /// 命令・関数を一つ実行する（原版 CWSHIfObj::MacroCommand）
    private func invoke(_ name: String, _ args: [JSValue]) -> Any? {
        guard let info = MacroCore.findFunctionIgnoreCase(name) else { return nil }
        let code = info.code
        if code >= 40000 {	// F_FUNCTION_FIRST 以上は関数
            let values = args.map(Self.macroValue)
            guard let done = onMain({ [view] in MacroHost.handleFunction(code, values, view: view) }) else {
                Self.throwError(Self.abortMessage)
                return nil
            }
            guard let result = done else {
                Self.throwError(L10n.tr("エラーを特定できません", comment: "E_FAIL（JScript のメッセージ）"))
                return nil
            }
            switch result {
            case .int(let n): return n
            case .string(let s): return s
            }
        }
        let strings = args.map(Self.commandArgument)
        if onMain({ [view] in MacroHost.handleCommand(code, strings, view: view) }) == nil {
            Self.throwError(Self.abortMessage)
        }
        return nil
    }

    private static func throwError(_ message: String) {
        guard let context = JSContext.current() else { return }
        context.exception = JSValue(newErrorFromMessage: message, in: context)
    }

    /// 命令の引数：文字列にする（原版 VariantChangeType VT_BSTR。変換できないものは空）
    static func commandArgument(_ v: JSValue) -> String {
        if v.isUndefined || v.isNull { return "" }
        if v.isBoolean { return v.toBool() ? "True" : "False" }
        if v.isNumber {
            let d = v.toDouble()
            if d.rounded() == d, abs(d) < 1e15 { return String(Int(d)) }
            return v.toString() ?? ""
        }
        return v.toString() ?? ""
    }

    /// 関数の引数（原版 VARIANT：数値は VT_I4・VT_R8、文字列は VT_BSTR、真偽は VT_BOOL）
    static func macroValue(_ v: JSValue) -> MacroValue {
        if v.isNumber {
            let d = v.toDouble()
            if d.isFinite, abs(d) < 2_147_483_648 { return .int(Int(d.rounded(.toNearestOrEven))) }
            return .string(v.toString() ?? "")
        }
        if v.isBoolean { return .int(v.toBool() ? -1 : 0) }
        if v.isUndefined || v.isNull { return .string("") }
        return .string(v.toString() ?? "")
    }
}

/// マクロ実行中の窓口（原版 IDD_MACRORUNNING、CDlgCancel）：「マクロ実行中・・・」、ファイル名、キャンセル(X)
final class MacroCancelPanel: NSObject, NSWindowDelegate {
    let window: NSWindow
    private(set) var canceled = false

    init(documentPath: String) {
        // 原版 270×55 ダイアログ単位
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 92), styleMask: [.titled], backing: .buffered, defer: false)
        super.init()
        window.title = CommonSettingsPages.appName
        window.isReleasedWhenClosed = false
        window.setAccessibilityIdentifier("IDD_MACRORUNNING")
        let content = NSView(frame: window.contentRect(forFrameRect: window.frame))
        let label = NSTextField(labelWithString: L10n.tr("マクロ実行中・・・", comment: "IDD_MACRORUNNING"))
        label.frame = NSRect(x: 12, y: 56, width: 300, height: 20)
        let path = NSTextField(wrappingLabelWithString: documentPath)
        path.frame = NSRect(x: 12, y: 8, width: 396, height: 40)
        path.textColor = .secondaryLabelColor
        path.setAccessibilityIdentifier("IDC_STATIC_CMD")
        let button = NSButton(title: L10n.tr("キャンセル", comment: "IDD_MACRORUNNING"), target: nil, action: nil)
        button.frame = NSRect(x: 316, y: 52, width: 96, height: 28)
        button.keyEquivalent = "\u{1b}"
        button.setAccessibilityIdentifier("IDCANCEL")
        content.addSubview(label)
        content.addSubview(path)
        content.addSubview(button)
        window.contentView = content
        button.target = self
        button.action = #selector(cancelPressed(_:))
        window.center()
    }

    @objc func cancelPressed(_ sender: Any?) {
        canceled = true
    }

    func close() {
        window.orderOut(nil)
    }
}

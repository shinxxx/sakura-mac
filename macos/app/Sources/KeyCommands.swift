// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import Carbon.HIToolbox
import EditorBridge

/// 快捷键：按原版的按键分配表（共通設定 > キー割り当て、CKeyBind）执行功能（第 34 步）。
///
/// Mac 的按键先换成 Windows 的虚拟键码和修饰键（Shift / Ctrl / Alt），再查核心库的按键分配表。
/// 有两种方案（設定 > Windows のキー割り当てを使う）：
///
/// - Mac 方案（默认）：⌘ 当作 Ctrl，⌥ 当作 Alt。⌘C コピー、⌘F 検索、⌘R 置換、⌘J 指定行へジャンプ 等与原版的 Ctrl 相同。
///   为了不和 macOS 的习惯冲突：
///   - 方向键、Home/End、PageUp/PageDown、Delete、Return 按 macOS 的文字编辑习惯（⌘← 行头、⌥← 单词等），不查表
///   - ⌃ 组合交给 macOS（Emacs 风格的 ⌃A、⌃E 等）
///   - 只按 ⌥ 的字符键输入特殊字符（⌥A = å），不查表
///   - ⌘Q 終了、⌘H 隠す、⌘M しまう、⌘, 設定 归 macOS；⌘W 是閉じる，⌘G / ⇧⌘G 是次を検索 / 前を検索，
///     ⇧⌘Z やり直し、⇧⌘S 名前を付けて保存 与 Mac 的其它 App 相同（原版的 Ctrl+Q/H/M/W/G 的功能只能从菜单执行）
/// - Windows 方案：⌃ 是 Ctrl，⌥ 是 Alt，全部的键都按原版的表（⌘ 只用于 macOS 的 ⌘Q 等）
///
/// 菜单项上显示的快捷键也从这里来（menuKeyEquivalent）。
enum KeyScheme: String {
    case mac
    case windows

    static let defaultsKey = "SakuraKeyScheme"

    /// 现在的方案（UserDefaults，App 的设置，不在 sakura.ini 里）
    static var current: KeyScheme {
        get { KeyScheme(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .mac }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
    }

    static let didChangeNotification = Notification.Name("SakuraKeySchemeDidChange")
}

/// 一次按键：Windows 的虚拟键码和修饰键（原版 KEYDATA 的键和 m_nFuncCodeArr 的序号）
struct KeyStroke: Hashable {
    var keyCode: Int
    var modifiers: EditorKeyModifiers

    init(_ keyCode: Int, _ modifiers: EditorKeyModifiers = []) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    static func == (a: KeyStroke, b: KeyStroke) -> Bool {
        a.keyCode == b.keyCode && a.modifiers.rawValue == b.modifiers.rawValue
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(keyCode)
        hasher.combine(modifiers.rawValue)
    }
}

enum KeyCommands {
    // MARK: - Windows 的虚拟键码

    enum VK {
        static let back = 8, tab = 9, enter = 13, escape = 27, space = 32
        static let pageUp = 33, pageDown = 34, end = 35, home = 36
        static let left = 37, up = 38, right = 39, down = 40, insert = 45, delete = 46
        static let f1 = 112, f12 = 123
    }

    /// Mac 的键（kVK_*）→ 虚拟键码：与字符无关的键
    private static let functionKeys: [Int: Int] = [
        kVK_Return: VK.enter, kVK_ANSI_KeypadEnter: VK.enter, kVK_Tab: VK.tab, kVK_Space: VK.space,
        kVK_Delete: VK.back, kVK_Escape: VK.escape, kVK_ForwardDelete: VK.delete, kVK_Help: VK.insert,
        kVK_Home: VK.home, kVK_End: VK.end, kVK_PageUp: VK.pageUp, kVK_PageDown: VK.pageDown,
        kVK_LeftArrow: VK.left, kVK_RightArrow: VK.right, kVK_UpArrow: VK.up, kVK_DownArrow: VK.down,
        kVK_F1: 112, kVK_F2: 113, kVK_F3: 114, kVK_F4: 115, kVK_F5: 116, kVK_F6: 117,
        kVK_F7: 118, kVK_F8: 119, kVK_F9: 120, kVK_F10: 121, kVK_F11: 122, kVK_F12: 123,
    ]

    /// 记号键：按键的位置换成 Windows 的 VK_OEM_*。US 键盘和日文（JIS）键盘的 VK 不同（与 Windows 相同）
    private static let ansiSymbolKeys: [Int: Int] = [
        kVK_ANSI_Minus: 0xBD, kVK_ANSI_Equal: 0xBB, kVK_ANSI_LeftBracket: 0xDB, kVK_ANSI_RightBracket: 0xDD,
        kVK_ANSI_Backslash: 0xDC, kVK_ANSI_Semicolon: 0xBA, kVK_ANSI_Quote: 0xDE, kVK_ANSI_Grave: 0xC0,
        kVK_ANSI_Comma: 0xBC, kVK_ANSI_Period: 0xBE, kVK_ANSI_Slash: 0xBF,
    ]
    private static let jisSymbolKeys: [Int: Int] = [
        kVK_ANSI_Minus: 0xBD,			// -
        kVK_ANSI_Equal: 0xDE,			// ^
        kVK_JIS_Yen: 0xDC,				// ￥
        kVK_ANSI_LeftBracket: 0xC0,		// @
        kVK_ANSI_RightBracket: 0xDB,	// [
        kVK_ANSI_Semicolon: 0xBB,		// ;
        kVK_ANSI_Quote: 0xBA,			// :
        kVK_ANSI_Backslash: 0xDD,		// ]
        kVK_ANSI_Comma: 0xBC, kVK_ANSI_Period: 0xBE, kVK_ANSI_Slash: 0xBF,
        kVK_JIS_Underscore: 0xE2,		// _
    ]
    /// 字母、数字键的位置（QWERTY）。字符取不到时用
    private static let letterKeys: [Int: Int] = [
        kVK_ANSI_A: 0x41, kVK_ANSI_B: 0x42, kVK_ANSI_C: 0x43, kVK_ANSI_D: 0x44, kVK_ANSI_E: 0x45,
        kVK_ANSI_F: 0x46, kVK_ANSI_G: 0x47, kVK_ANSI_H: 0x48, kVK_ANSI_I: 0x49, kVK_ANSI_J: 0x4A,
        kVK_ANSI_K: 0x4B, kVK_ANSI_L: 0x4C, kVK_ANSI_M: 0x4D, kVK_ANSI_N: 0x4E, kVK_ANSI_O: 0x4F,
        kVK_ANSI_P: 0x50, kVK_ANSI_Q: 0x51, kVK_ANSI_R: 0x52, kVK_ANSI_S: 0x53, kVK_ANSI_T: 0x54,
        kVK_ANSI_U: 0x55, kVK_ANSI_V: 0x56, kVK_ANSI_W: 0x57, kVK_ANSI_X: 0x58, kVK_ANSI_Y: 0x59,
        kVK_ANSI_Z: 0x5A,
        kVK_ANSI_0: 0x30, kVK_ANSI_1: 0x31, kVK_ANSI_2: 0x32, kVK_ANSI_3: 0x33, kVK_ANSI_4: 0x34,
        kVK_ANSI_5: 0x35, kVK_ANSI_6: 0x36, kVK_ANSI_7: 0x37, kVK_ANSI_8: 0x38, kVK_ANSI_9: 0x39,
    ]

    /// 现在的键盘是不是日文（JIS）键盘
    static var isJISKeyboard: Bool {
        KBGetLayoutType(Int16(LMGetKbdType())) == kKeyboardJIS
    }

    /// Mac 的键 → Windows 的虚拟键码。字母和数字按输入的字符（Dvorak 等也按印着的字母），其它按位置
    static func virtualKey(keyCode: UInt16, charactersIgnoringModifiers: String?, jis: Bool) -> Int? {
        let code = Int(keyCode)
        if let vk = functionKeys[code] { return vk }
        if let c = charactersIgnoringModifiers?.uppercased(), c.count == 1, let scalar = c.unicodeScalars.first,
           ("A"..."Z").contains(scalar) || ("0"..."9").contains(scalar) {
            return Int(scalar.value)
        }
        if let vk = symbolKey(code, jis) { return vk }
        return letterKeys[code]
    }

    private static func symbolKey(_ code: Int, _ jis: Bool) -> Int? {
        jis ? jisSymbolKeys[code] : ansiSymbolKeys[code]
    }

    /// 方向键等：Mac 方案里按 macOS 的文字编辑习惯，不查表
    static let navigationKeys: Set<Int> = [
        VK.left, VK.right, VK.up, VK.down, VK.home, VK.end, VK.pageUp, VK.pageDown, VK.back, VK.delete, VK.enter,
    ]

    static func isFunctionKey(_ vk: Int) -> Bool { (VK.f1...VK.f12).contains(vk) }
    private static func isCharacterKey(_ vk: Int) -> Bool {
        (0x30...0x39).contains(vk) || (0x41...0x5A).contains(vk) || (0xBA...0xE2).contains(vk) || vk == VK.space
    }

    // MARK: - 按键 → 功能

    /// Mac 的按键 → 原版的按键（不查表的键是 nil）
    static func stroke(keyCode: UInt16, charactersIgnoringModifiers: String?, flags: NSEvent.ModifierFlags,
                       scheme: KeyScheme = .current, jis: Bool = isJISKeyboard) -> KeyStroke? {
        guard let vk = virtualKey(keyCode: keyCode, charactersIgnoringModifiers: charactersIgnoringModifiers, jis: jis) else {
            return nil
        }
        let flags = flags.intersection(.deviceIndependentFlagsMask)
        var mods: EditorKeyModifiers = []
        if flags.contains(.shift) { mods.insert(.shift) }
        if flags.contains(.option) { mods.insert(.alt) }
        switch scheme {
        case .mac:
            if flags.contains(.control) || navigationKeys.contains(vk) { return nil }
            if flags.contains(.command) { mods.insert(.ctrl) }
            // 只按 ⌥ 的字符键是输入特殊字符
            if mods.contains(.alt) && !mods.contains(.ctrl) && isCharacterKey(vk) { return nil }
        case .windows:
            if flags.contains(.command) { return nil }
            if flags.contains(.control) { mods.insert(.ctrl) }
        }
        return KeyStroke(vk, mods)
    }

    /// Mac 方案里与 macOS 的习惯一致的键（显示在菜单上，优先于原版的表）
    static let macOverrides: [KeyStroke: Int] = [
        KeyStroke(0x47, .ctrl): 30902,				// ⌘G 次を検索（原版 Ctrl+G 是 Grep）
        KeyStroke(0x47, [.ctrl, .shift]): 30903,	// ⇧⌘G 前を検索
        KeyStroke(0x5A, [.ctrl, .shift]): 30211,	// ⇧⌘Z やり直し（⌘Y 也能用）
        KeyStroke(0x53, [.ctrl, .shift]): 30104,	// ⇧⌘S 名前を付けて保存
        KeyStroke(0x57, .ctrl): 31320,				// ⌘W 閉じる（原版 Ctrl+W 是単語選択）
    ]
    /// Mac 方案里归 macOS 的键（App 菜单、ウィンドウ菜单处理）：⌘Q ⌘H ⌥⌘H ⌘M ⌘,
    static let macReserved: Set<KeyStroke> = [
        KeyStroke(0x51, .ctrl), KeyStroke(0x48, .ctrl), KeyStroke(0x48, [.ctrl, .alt]),
        KeyStroke(0x4D, .ctrl), KeyStroke(0xBC, .ctrl),
    ]

    /// 这个按键执行的功能（没有时是 0）
    static func command(for stroke: KeyStroke, scheme: KeyScheme = .current) -> Int {
        if scheme == .mac {
            if let code = macOverrides[stroke] { return code }
            if macReserved.contains(stroke) { return 0 }
        }
        return EditorCore.command(forKeyCode: stroke.keyCode, modifiers: stroke.modifiers)
    }

    /// 按键事件执行的功能（没有时是 0）
    static func command(for event: NSEvent, scheme: KeyScheme = .current) -> Int {
        guard event.type == .keyDown,
              let stroke = stroke(keyCode: event.keyCode, charactersIgnoringModifiers: event.charactersIgnoringModifiers,
                                  flags: event.modifierFlags, scheme: scheme) else { return 0 }
        return command(for: stroke, scheme: scheme)
    }

    // MARK: - 菜单上显示的快捷键

    /// 这个功能的菜单快捷键（NSMenuItem.keyEquivalent 和修饰键）。
    /// Mac 方案只显示 ⌘ 组合和 F 键，Windows 方案只显示 ⌃ 组合和 F 键；
    /// Tab、Esc、方向键等不放在菜单上（菜单会抢走编辑画面的按键）。没有时是 nil
    static func menuKeyEquivalent(for code: Int, scheme: KeyScheme = .current) -> (key: String, modifiers: NSEvent.ModifierFlags)? {
        guard let stroke = menuStroke(for: code, scheme: scheme) else { return nil }
        return keyEquivalent(stroke, scheme: scheme)
    }

    static func menuStroke(for code: Int, scheme: KeyScheme) -> KeyStroke? {
        if scheme == .mac, let override = macOverrides.first(where: { $0.value == code })?.key {
            return override
        }
        let candidates = bindings(scheme: scheme).filter { $0.command == code }
            .map { KeyStroke($0.keyCode, $0.modifiers) }
            .filter { stroke in
                guard keyEquivalent(stroke, scheme: scheme) != nil else { return false }
                // Mac 方案里被 macOS 和上面的覆盖用掉的键不显示
                if scheme == .mac && (macReserved.contains(stroke) || macOverrides[stroke] != nil) { return false }
                return true
            }
        // Ctrl 组合优先于 F 键（⌘C 比 F8 更像 Mac）
        return candidates.first { $0.modifiers.contains(.ctrl) } ?? candidates.first
    }

    /// 按键表在两种方案之间不变，只读一次（共通設定 > キー割り当て 改了时 reloadBindings，第 41 步）
    private static var cachedBindings: [EditorKeyBinding]?
    private static func bindings(scheme: KeyScheme) -> [EditorKeyBinding] {
        if let cachedBindings { return cachedBindings }
        let list = EditorCore.keyBindings
        cachedBindings = list
        return list
    }

    /// 清掉读过的按键表（共通設定 > キー割り当て 的 OK 以后、单元测试）
    static func reloadBindings() {
        cachedBindings = nil
    }

    private static func keyEquivalent(_ stroke: KeyStroke, scheme: KeyScheme) -> (key: String, modifiers: NSEvent.ModifierFlags)? {
        let vk = stroke.keyCode
        let key: String
        if isFunctionKey(vk) {
            key = String(Character(UnicodeScalar(NSF1FunctionKey + vk - VK.f1)!))
        } else if (0x41...0x5A).contains(vk) || (0x30...0x39).contains(vk) {
            // 字母和数字只在有 Ctrl 时（单独的字母键是输入）
            guard stroke.modifiers.contains(.ctrl) else { return nil }
            key = String(Character(UnicodeScalar(UInt8(vk)))).lowercased()
        } else {
            return nil
        }
        var modifiers: NSEvent.ModifierFlags = []
        if stroke.modifiers.contains(.ctrl) { modifiers.insert(scheme == .mac ? .command : .control) }
        if stroke.modifiers.contains(.shift) { modifiers.insert(.shift) }
        if stroke.modifiers.contains(.alt) { modifiers.insert(.option) }
        return (key, modifiers)
    }
}

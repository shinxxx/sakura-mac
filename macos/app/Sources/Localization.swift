// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import EditorBridge
import Foundation

/// 界面本地化（计划第 48 步）。
///
/// 原版的界面文字有日文（sakura.exe 内置）和语言包（sakura_lang 的英文、简体中文）。Mac 版：
/// - 界面的语言跟随系统（「系统设置 > 通用 > 语言与地区」，也可以按 App 单独选），在日文、英文、简体中文里选最合适的；
/// - 原版的字符串表（菜单的功能名、消息等）由核心库按语言读（`EditorCore.uiLanguage`）；
/// - 对话框的布局和文字是原版各语言的对话框模板（`Resources/<语言>.lproj/*Dialogs.json`）；
/// - Mac 版自己的文字用 `L10n.tr("日文", comment:)` 写，英文、中文的翻译在 `Resources/<语言>.lproj/Localizable.strings`
///   （键是日文。日文时原样返回）。
enum L10n {
    /// 支持的语言（.lproj 的名字）。第一个是开发语言
    static let languages = ["ja", "en", "zh-Hans"]

    /// 当前的界面语言（`languages` 之一）。
    /// App：按系统的语言设置（启动参数 `-AppleLanguages (en)` 也算）。
    /// 单元测试：日文（测试按原版的日文写。语言的测试自己换）
    static var language: String = defaultLanguage() {
        didSet {
            lock.lock()
            tables.removeAll()
            lock.unlock()
        }
    }

    static func defaultLanguage() -> String {
        // 单元测试（App 是测试的宿主时也一样。界面测试启动的 App 里没有 XCTest，按启动参数）
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || NSClassFromString("XCTestCase") != nil {
            return "ja"
        }
        return Bundle.preferredLocalizations(from: languages, forPreferences: nil).first ?? "ja"
    }

    /// 核心库的语言
    static var coreLanguage: EditorUILanguage {
        switch language {
        case "en": return .english
        case "zh-Hans": return .chinese
        default: return .japanese
        }
    }

    /// Mac 版的界面文字的翻译。key 是日文
    static func tr(_ key: String, comment: String) -> String {
        if language == "ja" { return key }
        return table(for: language)[key] ?? key
    }

    /// 这个语言的翻译表（Localizable.strings）
    static func table(for language: String) -> [String: String] {
        lock.lock()
        defer { lock.unlock() }
        if let table = tables[language] { return table }
        var table: [String: String] = [:]
        if let url = resourceURL("Localizable", withExtension: "strings", language: language),
           let dict = NSDictionary(contentsOf: url) as? [String: String] {
            table = dict
        }
        tables[language] = table
        return table
    }

    /// 这个语言的资源文件（`<语言>.lproj/name.ext`）。没有时用日文的
    static func resourceURL(_ name: String, withExtension ext: String, language: String = L10n.language) -> URL? {
        guard let base = bundle.resourceURL else { return nil }
        for lang in [language, "ja"] {
            let url = base.appendingPathComponent("\(lang).lproj/\(name).\(ext)")
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return bundle.url(forResource: name, withExtension: ext)
    }

    /// 资源所在的 bundle（App，或者单元测试的 bundle）
    static var bundle: Bundle { Bundle(for: BundleToken.self) }

    // マクロのスレッドからも使う
    private static let lock = NSLock()
    private static var tables: [String: [String: String]] = [:]
    private final class BundleToken {}
}

// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import Foundation

/// 日付・時刻の書式（原版 CFormatManager::MyGetDateFormat、MyGetTimeFormat。计划第 39 步）。
///
/// 原版用 Windows 的 GetDateFormat / GetTimeFormat 解释共通設定 > 書式 的「カスタム」书式，
/// Mac 版按 Windows 的书式规则（同じ記号）自己解释，结果与 Windows 版相同：
/// - 日付：d dd ddd dddd（日、曜日）、M MM MMM MMMM（月）、y yy yyyy（年。y 是最后一位）、g gg（年号）
/// - 時刻：h hh（12 時間）、H HH（24 時間）、m mm、s ss、t tt（午前/午後）
/// - '…' 里的文字原样输出（'' 是一个 '），其他文字也原样输出
/// 「標準」时：日付是长格式（原版 DATE_LONGDATE），時刻是系统的格式。
/// 曜日、月の名前、午前/午後は界面的语言（第 48 步：日文 ja_JP、英文 en_US、中文 zh_CN。
/// 原版是 Windows 的地区设置，日文版的 Windows 上是日文）。
enum WindowsDateFormat {
    static var locale: Locale {
        switch L10n.language {
        case "en": return Locale(identifier: "en_US")
        case "zh-Hans": return Locale(identifier: "zh_CN")
        default: return Locale(identifier: "ja_JP")
        }
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        return calendar
    }

    /// 日付。type 0 是標準，其他是 format 的书式
    static func date(_ date: Date, type: Int, format: String) -> String {
        if type == 0 {
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.dateStyle = .long
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
        return expand(format, date: date, symbols: "dMyg")
    }

    /// 時刻。type 0 是標準，其他是 format 的书式
    static func time(_ date: Date, type: Int, format: String) -> String {
        if type == 0 {
            // Windows の標準：日本語・中国語は H:mm:ss、英語（米国）は h:mm:ss tt
            return expand(L10n.language == "en" ? "h:mm:ss tt" : "H:mm:ss", date: date, symbols: "hHmst")
        }
        return expand(format, date: date, symbols: "hHmst")
    }

    /// 书式展开。symbols 是这个书式里有意义的字母（日付用的字母在時刻的书式里原样输出，反过来也一样）
    private static func expand(_ format: String, date: Date, symbols: String) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .weekday, .hour, .minute, .second], from: date)
        let chars = Array(format)
        var result = ""
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if ch == "'" {
                // 引用：'' は ' 一文字
                i += 1
                while i < chars.count {
                    if chars[i] == "'" {
                        if i + 1 < chars.count && chars[i + 1] == "'" {
                            result.append("'")
                            i += 2
                            continue
                        }
                        i += 1
                        break
                    }
                    result.append(chars[i])
                    i += 1
                }
                continue
            }
            guard symbols.contains(ch) else {
                result.append(ch)
                i += 1
                continue
            }
            var n = 1
            while i + n < chars.count && chars[i + n] == ch { n += 1 }
            result += field(ch, count: n, components: c, date: date)
            i += n
        }
        return result
    }

    private static func field(_ ch: Character, count n: Int, components c: DateComponents, date: Date) -> String {
        let year = c.year ?? 0, month = c.month ?? 1, day = c.day ?? 1
        let hour = c.hour ?? 0, minute = c.minute ?? 0, second = c.second ?? 0
        func pad(_ v: Int) -> String { v < 10 ? "0\(v)" : "\(v)" }
        switch ch {
        case "d":
            switch n {
            case 1: return "\(day)"
            case 2: return pad(day)
            default:
                let symbols = n == 3 ? calendar.shortWeekdaySymbols : calendar.weekdaySymbols
                return symbols[((c.weekday ?? 1) - 1) % 7]
            }
        case "M":
            switch n {
            case 1: return "\(month)"
            case 2: return pad(month)
            case 3: return calendar.shortMonthSymbols[month - 1]
            default: return calendar.monthSymbols[month - 1]
            }
        case "y":
            switch n {
            case 1: return "\(year % 10)"	// Windows：最后一位
            case 2: return pad(year % 100)
            default: return "\(year)"
            }
        case "g":
            // 年号（日本の暦）
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.calendar = Calendar(identifier: .japanese)
            formatter.dateFormat = "GGGG"
            return formatter.string(from: date)
        case "h":
            let h12 = hour % 12 == 0 ? 12 : hour % 12
            return n == 1 ? "\(h12)" : pad(h12)
        case "H":
            return n == 1 ? "\(hour)" : pad(hour)
        case "m":
            return n == 1 ? "\(minute)" : pad(minute)
        case "s":
            return n == 1 ? "\(second)" : pad(second)
        case "t":
            // 午前/午後（英語は AM/PM、中国語は 上午/下午）
            let marker = hour < 12 ? calendar.amSymbol : calendar.pmSymbol
            return n == 1 ? String(marker.prefix(1)) : marker
        default:
            return String(repeating: ch, count: n)
        }
    }
}

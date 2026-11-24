// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import Foundation
import EditorBridge

/// 「最近使ったファイル」的访问权限（第 31 步：沙盒文件访问）。
///
/// App Store 的 App 在沙盒里运行，只能读写用户在打开、保存对话框里选的文件和拖进来的文件，
/// 而且 App 结束后权限就没有了。原版的「最近使ったファイル」（sakura.ini 的 [MRU]）只记路径，
/// 重启后从菜单打开时沙盒不让读。所以打开、保存成功后，给这个文件建一个安全书签
/// （security-scoped bookmark）记下权限，从历史打开时用书签取回权限。
///
/// 书签存在 sakura.ini 旁边的 bookmarks.plist（路径 → 书签数据）。
/// 只留「最近使ったファイル」里还有的文件（与原版的历史一起变化，不会越来越多）。
final class BookmarkStore {
    /// App 用的：sakura.ini 旁边的 bookmarks.plist（核心库启动后才能用）
    static let shared = BookmarkStore(fileURL: URL(fileURLWithPath: EditorCore.settingsFilePath)
        .deletingLastPathComponent().appendingPathComponent("bookmarks.plist"))

    /// 設定で選んだファイル（ルールファイル、背景画像、単語ファイル、キーワード辞書。第 42 步）：
    /// 設定には路径だけ書くので、重启后も沙盒で読めるように書签を残す。「最近使ったファイル」とは別（履歴で消さない）
    static let settingFiles = BookmarkStore(fileURL: URL(fileURLWithPath: EditorCore.settingsFilePath)
        .deletingLastPathComponent().appendingPathComponent("setting-file-bookmarks.plist"))

    let fileURL: URL
    private var bookmarks: [String: Data]

    init(fileURL: URL) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let list = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Data] {
            bookmarks = list
        } else {
            bookmarks = [:]
        }
    }

    /// 记着书签的文件
    var paths: [String] { bookmarks.keys.sorted() }

    func hasBookmark(forPath path: String) -> Bool { bookmarks[path] != nil }

    /// 给这个文件建书签（现在能访问时才建得了：打开、保存成功后调用）。
    /// 先用安全书签，建不了时（沙盒外运行的单元测试等）用普通书签
    @discardableResult
    func remember(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        let data = (try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil))
            ?? (try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil))
        guard let data else { return false }
        bookmarks[url.path] = data
        save()
        return true
    }

    /// 用书签找回文件的 URL（可以 startAccessingSecurityScopedResource 的）。没有书签、文件不在了时是 nil。
    /// 书签旧了（文件被移动等）时重新建
    func resolve(path: String) -> URL? {
        guard let data = bookmarks[path] else { return nil }
        var stale = false
        let url = (try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale))
            ?? (try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale))
        guard let url else { return nil }
        if stale {
            let accessing = url.startAccessingSecurityScopedResource()
            remember(url)
            if accessing { url.stopAccessingSecurityScopedResource() }
        }
        return url
    }

    /// 这个文件的书签があれば、権限を取り戻している間に body を実行する（書签がない・相対路径はそのまま）
    func withAccess<T>(path: String, _ body: () -> T) -> T {
        guard !path.isEmpty, let url = resolve(path: path) else { return body() }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        return body()
    }

    /// 只留这些路径的书签（「最近使ったファイル」里没有了的删掉）
    func prune(keeping keep: (String) -> Bool) {
        let before = bookmarks.count
        bookmarks = bookmarks.filter { keep($0.key) }
        if bookmarks.count != before { save() }
    }

    /// 只留核心库的历史里还有的文件
    func pruneToRecentFiles() {
        prune { EditorCore.recentFile(path: $0) != nil }
    }

    func removeAll() {
        bookmarks.removeAll()
        save()
    }

    private func save() {
        guard let data = try? PropertyListSerialization.data(fromPropertyList: bookmarks, format: .binary, options: 0) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}

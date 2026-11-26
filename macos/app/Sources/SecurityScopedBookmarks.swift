// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
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

/// 文件夹的访问权限（第 43 步：Grep 的検索場所、ファイルツリー）。
///
/// 沙盒里的 App 只能读用户在对话框里选的文件夹。Grep 的検索場所 由用户用「...」选，
/// 或者输入时没有权限的文件夹在 OK 时请用户在对话框里确认一次（原版没有这一步）。
/// 选过的文件夹记安全书签（folder-bookmarks.plist），重启后从书签取回权限，里面的文件夹、文件都能读写。
/// 取回的权限一直拿着，直到 App 结束（Grep 的结果打开文件、ファイルツリー 都要用）。
final class FolderAccess {
    static let shared = FolderAccess(store: BookmarkStore(fileURL: URL(fileURLWithPath: EditorCore.settingsFilePath)
        .deletingLastPathComponent().appendingPathComponent("folder-bookmarks.plist")))

    let store: BookmarkStore
    /// 拿着权限的文件夹（路径 → URL）
    private var accessing: [String: URL] = [:]

    /// 请用户授权的对话框（单元测试换掉）。路径 → 选了的文件夹（取消时 nil）
    static var choose: (_ path: String, _ message: String, _ parent: NSWindow?) -> URL? = { path, message, parent in
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.message = message
        panel.prompt = NSLocalizedString("許可", comment: "Grep のフォルダーの許可")
        panel.directoryURL = URL(fileURLWithPath: path, isDirectory: true)
        return panel.runModal() == .OK ? panel.url : nil
    }

    init(store: BookmarkStore) {
        self.store = store
    }

    /// 这个文件夹（或上层的文件夹）记着书签时取回权限。取回了、或者本来就能读时 true
    @discardableResult
    func startAccess(path: String) -> Bool {
        let path = Self.normalized(path)
        if accessing.keys.contains(where: { Self.contains($0, path) }) { return true }
        for saved in store.paths where Self.contains(saved, path) {
            if let url = store.resolve(path: saved) {
                if url.startAccessingSecurityScopedResource() || Self.isReadable(path) {
                    accessing[saved] = url
                    return true
                }
            }
        }
        return Self.isReadable(path)
    }

    /// 文件夹能读吗（沙盒外运行的单元测试、界面测试的 App 总是能读）
    static func isReadable(_ path: String) -> Bool {
        (try? FileManager.default.contentsOfDirectory(atPath: path)) != nil
    }

    /// 用户选了的文件夹：记书签，拿着权限
    func remember(_ url: URL) {
        store.remember(url)
        let path = Self.normalized(url.path)
        if accessing[path] == nil {
            _ = url.startAccessingSecurityScopedResource()
            accessing[path] = url
        }
    }

    /// 没有权限的文件夹请用户授权（对话框里显示这个文件夹，用户按「許可」）。都有权限时 true
    /// purpose：对话框的消息（nil 是 Grep 的「検索するには」）
    func ensureAccess(paths: [String], parent: NSWindow?, message purpose: String? = nil) -> Bool {
        for path in paths where !startAccess(path: path) {
            // 無いフォルダーは許可を求めない（OK の確かめで「検索対象フォルダーが正しくありません。」）
            if Self.doesNotExist(path) { continue }
            let format = purpose ?? NSLocalizedString("「%@」を検索するには、このフォルダーへのアクセスを許可してください。", comment: "Grep のフォルダーの許可")
            let message = String(format: format, path)
            guard let url = Self.choose(path, message, parent) else { return false }
            remember(url)
            if !startAccess(path: path) { return false }
        }
        return true
    }

    /// 文件（Grep 的结果、タグジャンプ）所在的文件夹的权限
    @discardableResult
    func startAccess(file: String) -> Bool {
        startAccess(path: (file as NSString).deletingLastPathComponent)
    }

    /// 無いフォルダー（沙盒で読めないだけのときは false）
    static func doesNotExist(_ path: String) -> Bool {
        var st = stat()
        return stat(path, &st) != 0 && errno == ENOENT
    }

    static func normalized(_ path: String) -> String {
        var p = (path as NSString).standardizingPath
        while p.count > 1 && p.hasSuffix("/") { p.removeLast() }
        return p
    }

    /// folder 是 path 本身或上层
    static func contains(_ folder: String, _ path: String) -> Bool {
        let f = normalized(folder), p = normalized(path)
        return p == f || p.hasPrefix(f == "/" ? f : f + "/")
    }
}

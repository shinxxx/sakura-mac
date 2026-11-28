// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge

/// 編集窓口のツールバー・タブバー・ステータスバー（计划第 38 步。原版 CEditWnd::LayoutToolBar・LayoutTabBar・LayoutStatusBar）。
///
/// - 表示するかは共通設定（bDispTOOLBAR、bDispTabWnd、bDispSTATUSBAR）。設定 > ツールバーの表示・タブバーの表示・
///   ステータスバーの表示（F_SHOWTOOLBAR、F_SHOWTAB、F_SHOWSTATUSBAR）で切り替えると全部の窓口が変わる（原版も共通設定を変えて全部の窓口に通知）。
/// - 中身（行・桁、ボタンの状態、タブ）は窓口の更新ごと（NSWindow.didUpdateNotification：イベントを処理した後）に新しくする。
///   原版はキャレットが動くたびの ShowCaretPosInfo とタイマーの UpdateToolbar。
enum WindowBarSettings {
    static let toolbarKey = "bDispTOOLBAR"
    static let statusBarKey = "bDispSTATUSBAR"
    static let tabBarKey = "bDispTabWnd"
    /// 表示の切り替えを全部の窓口に知らせる
    static let didChangeNotification = Notification.Name("SakuraWindowBarsDidChange")

    static func isOn(_ key: String) -> Bool {
        (Int(EditorCore.commonSetting(section: "Common", key: key)?.trimmingCharacters(in: .whitespaces) ?? "") ?? 0) != 0
    }

    static var showsToolbar: Bool { isOn(toolbarKey) }
    static var showsStatusBar: Bool { isOn(statusBarKey) }
    static var showsTabBar: Bool { isOn(tabBarKey) }

    /// 表示を切り替える（原版 Command_SHOWTOOLBAR 等）
    static func toggle(_ key: String) {
        EditorCore.setCommonSetting(isOn(key) ? "0" : "1", section: "Common", key: key)
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    /// 機能番号 → 設定（F_SHOWTOOLBAR、F_SHOWSTATUSBAR、F_SHOWTAB）
    static func key(forCommand code: Int) -> String? {
        switch code {
        case 31100: return toolbarKey
        case 31102: return statusBarKey
        case 31103: return tabBarKey
        default: return nil
        }
    }
}

extension EditorTextView {
    /// ツールバー・ステータスバー・タブバーの表示（F_SHOWTOOLBAR、F_SHOWSTATUSBAR、F_SHOWTAB）
    @objc func toggleWindowBar(_ sender: Any?) {
        guard let code = Self.commandCode(of: sender), let key = WindowBarSettings.key(forCommand: code) else { return }
        WindowBarSettings.toggle(key)
    }

    /// 表示の項目：表示中は打勾（原版 IsFuncChecked）
    func validateWindowBarMenuItem(_ item: NSMenuItem) -> Bool? {
        guard item.action == #selector(toggleWindowBar(_:)) else { return nil }
        if let key = WindowBarSettings.key(forCommand: item.tag) {
            item.state = WindowBarSettings.isOn(key) ? .on : .off
        }
        return true
    }
}

extension EditorWindowController {
    /// 開いている編集窓口（開いた順。原版のタブの順）
    static var allControllers: [EditorWindowController] {
        NSDocumentController.shared.documents.flatMap { $0.windowControllers.compactMap { $0 as? EditorWindowController } }
    }

    /// 窓口を作ったとき（init の最後）
    func setUpWindowBars() {
        let center = NotificationCenter.default
        barObservers.append(center.addObserver(forName: NSWindow.didUpdateNotification, object: window, queue: .main) { [weak self] _ in
            self?.updateWindowBars()
        })
        for name in [WindowBarSettings.didChangeNotification, EditorTextView.commonSettingsDidChangeNotification] {
            barObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.applyWindowBarSettings()
            })
        }
        barObservers.append(center.addObserver(forName: EditorTextView.fontDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.updateWindowBars()
        })
        barObservers.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
            self?.windowBecameKey()
        })
        barObservers.append(center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            self?.windowWillCloseForTabs()
        })
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            barObservers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                guard let self, let window = self.window, window.isVisible, TabGroup.isGrouping else { return }
                TabGroup.frame = window.frame
            })
        }
        applyWindowBarSettings(initial: true)
    }

    /// 設定に合わせてバーを作る・外す（原版 LayoutToolBar・LayoutTabBar・LayoutStatusBar）。
    /// initial：窓口を作ったとき（ほかの窓口のまとめ表示は変えない）
    func applyWindowBarSettings(initial: Bool = false) {
        let container = editorContainer
        // ツールバー（並びが変わったら作り直す）
        if WindowBarSettings.showsToolbar {
            let current = EditorToolbarView.currentItems()
            if let toolbar = toolbarView, toolbar.items == current.items, toolbar.isFlat == current.flat {
                // そのまま
            } else {
                let toolbar = EditorToolbarView(items: current.items, flat: current.flat)
                toolbar.textView = textView
                toolbarView = toolbar
                container.toolbar = toolbar
            }
        } else if toolbarView != nil {
            toolbarView = nil
            container.toolbar = nil
        }
        // タブバー
        if WindowBarSettings.showsTabBar {
            let settings = TabBarView.Settings.current
            if let tabBar = tabBarView {
                tabBar.settings = settings
            } else {
                let tabBar = TabBarView(settings: settings)
                tabBar.onSelect = { id in TabGroup.activate(id) }
                tabBar.onClose = { id in TabGroup.close(id) }
                tabBarView = tabBar
                container.tabBar = tabBar
            }
            container.tabBarAtBottom = settings.atBottom
            // macOS の窓口のタブは使わない
            window?.tabbingMode = .disallowed
            if let window, (window.tabbedWindows?.count ?? 0) > 1 { window.moveTabToNewWindow(nil) }
        } else {
            if tabBarView != nil {
                tabBarView = nil
                container.tabBar = nil
            }
            window?.tabbingMode = .automatic
        }
        // ステータスバー
        if WindowBarSettings.showsStatusBar {
            if statusBar == nil {
                let bar = StatusBarView(frame: .zero)
                bar.textView = textView
                statusBar = bar
                container.statusBar = bar
                // 編集画面の左下に出していたメッセージはステータスバーへ
                if let label = textView.statusLabel, !label.isHidden {
                    label.isHidden = true
                    bar.setText(.message, label.stringValue.trimmingCharacters(in: .whitespaces))
                }
            }
        } else if statusBar != nil {
            let message = statusBar?.text(.message) ?? ""
            statusBar = nil
            container.statusBar = nil
            if !message.isEmpty { textView.sendStatusMessage(message) }
        }
        container.arrange()
        if !initial { TabGroup.settingsChanged() }
        updateWindowBars()
    }

    /// 中身を新しくする（行・桁、ボタンの状態、タブ）
    func updateWindowBars() {
        if let statusBar {
            let texts = textView.statusBarTexts(encoding: editorDocument.encoding, bom: editorDocument.hasBOM)
            for (part, text) in texts { statusBar.setText(part, text) }
            statusBar.isRecording = KeyMacroRecorder.shared.isRecording(in: window)
        }
        if let toolbarView {
            toolbarView.updateStates()
            toolbarView.updateSearchHistory()
        }
        if let tabBarView {
            tabBarView.setTabs(TabGroup.tabs(), selected: ObjectIdentifier(self))
        }
    }

    /// 編集窓口の中身（第 42 步のドッキングの入れ物。印刷プレビュー中も同じもの）
    var editorContainer: EditorContainerView { container }

    // MARK: - タブのまとめ表示（原版 CTabWnd：まとめるときは 1 つだけ見せる）

    fileprivate func windowBecameKey() {
        guard tabBarView != nil else { return }
        TabGroup.windowBecameKey(self)
        // ほかの窓口のタブバーの「選んでいるタブ」は変わらないが、並びの更新のため
        for controller in Self.allControllers where controller !== self { controller.updateWindowBars() }
    }

    fileprivate func windowWillCloseForTabs() {
        guard tabBarView != nil else { return }
        TabGroup.windowWillClose(self)
    }

    /// タブの文字（原版のタブの名前：窓口のタイトルと同じ「ファイル名(更新)」等）
    var tabTitle: String {
        window?.title ?? ""
    }
}

/// タブのまとめ表示（まとめる窓口は同じ位置・大きさにして、選んでいる 1 つだけ見せる）
enum TabGroup {
    /// まとめた窓口の位置・大きさ
    static var frame: NSRect?

    static var isGrouping: Bool {
        WindowBarSettings.showsTabBar && TabBarView.Settings.current.group
    }

    static func tabs() -> [TabBarView.Tab] {
        EditorWindowController.allControllers.map { controller in
            let path = controller.editorDocument.path
            return TabBarView.Tab(id: ObjectIdentifier(controller), title: controller.tabTitle,
                                  toolTip: path.isEmpty ? controller.tabTitle : path, path: path)
        }
    }

    static func controller(_ id: ObjectIdentifier) -> EditorWindowController? {
        EditorWindowController.allControllers.first { ObjectIdentifier($0) == id }
    }

    /// タブを押した：その窓口へ
    static func activate(_ id: ObjectIdentifier) {
        guard let controller = controller(id), let window = controller.window else { return }
        if isGrouping, let frame = frame ?? NSApp.keyWindow?.frame {
            window.setFrame(frame, display: false)
        }
        window.makeKeyAndOrderFront(nil)
    }

    /// タブの閉じるボタン：その窓口を閉じる（保存の確認は普通に閉じるときと同じ）
    static func close(_ id: ObjectIdentifier) {
        controller(id)?.window?.performClose(nil)
    }

    /// 窓口が手前に来た：まとめるときはほかを隠す（原版 ShowHideWindow）
    static func windowBecameKey(_ controller: EditorWindowController) {
        guard isGrouping, let window = controller.window else { return }
        if let frame, window.frame != frame {
            window.setFrame(frame, display: true)
        } else {
            frame = window.frame
        }
        for other in EditorWindowController.allControllers where other !== controller {
            if other.window?.isVisible == true { other.window?.orderOut(nil) }
        }
    }

    /// 窓口を閉じる：まとめているときは隣のタブの窓口を見せる（原版：閉じたタブの次、最後なら前）
    static func windowWillClose(_ controller: EditorWindowController) {
        guard isGrouping, controller.window?.isVisible == true || controller.window?.isKeyWindow == true else { return }
        let all = EditorWindowController.allControllers
        guard let index = all.firstIndex(where: { $0 === controller }) else { return }
        let rest = all.filter { $0 !== controller }
        guard !rest.isEmpty else { return }
        let next = rest[min(index, rest.count - 1)]
        DispatchQueue.main.async { activate(ObjectIdentifier(next)) }
    }

    /// 設定が変わった：まとめるようになったら今の窓口だけ見せる、まとめなくなったら全部見せる
    static func settingsChanged() {
        let all = EditorWindowController.allControllers
        if isGrouping {
            let current = all.first { $0.window?.isKeyWindow == true } ?? all.first { $0.window?.isVisible == true }
            if let current { windowBecameKey(current) }
        } else if WindowBarSettings.showsTabBar || frame != nil {
            frame = nil
            for controller in all where controller.window?.isVisible == false && controller.window?.isMiniaturized == false {
                controller.window?.orderFront(nil)
            }
        }
    }
}

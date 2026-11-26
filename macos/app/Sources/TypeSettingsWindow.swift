// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge

/// タイプ別設定窗口（计划第 40 步。原版 CPropTypes：設定 > タイプ別設定）。
///
/// - 与共通設定窗口相同的做法（PropSheetWindowController）：页的顺序、每页的控件用原版的对话框模板
///   （macos/tools/settings/make_prop_dialogs.py 生成 Resources/TypeSettingsDialogs.json），
///   值按 sakura.ini 的 [Types(N)] 的项目读写（核心库 GetCommonSetting / SetCommonSettings，用原版 ShareData_IO_TypeConfig）。
/// - 原版打开时复制这个类型的设置（CPropTypes::SetTypeData），OK 时写回（CDocTypeManager::SetTypeConfig），
///   然后通知所有窗口（MYWM_CHANGESETTING、PM_CHANGESETTING_TYPE）：这个类型的文档按新的设置重新排版。キャンセル 什么也不改。
/// - 原版是模态的属性表。Mac 版与共通設定相同，是一次只开一个的窗口（OK・キャンセル 的意思相同）。
/// - 各页的 SetData / GetData 移植在 TypeSettingsPages.swift。
final class TypeSettingsWindowController: PropSheetWindowController {
    /// 打开着的窗口
    private(set) static var shared: TypeSettingsWindowController?
    /// 上次的页（原版 CPropertyManager::m_nPropTypePageNum：下次从这页开始）
    static var lastPage = 0

    /// F_TYPE_*（設定 > タイプ別設定 的各页）→ 页（原版 CViewCommander::Command_TYPE_* 的 ID_PROPTYPE_PAGENUM_*）
    static let pageOfCommand: [Int: Int] = [
        31115: 0,	// F_TYPE_SCREEN スクリーン
        31116: 1,	// F_TYPE_COLOR カラー
        31114: 2,	// F_TYPE_WINDOW ウィンドウ
        31117: 3,	// F_TYPE_HELPER 支援
        31118: 4,	// F_TYPE_REGEX_KEYWORD 正規表現キーワード
        31119: 5,	// F_TYPE_KEYHELP キーワードヘルプ
    ]

    /// OK で設定が変わった（userInfo の "index" は変わったタイプの番号）
    static let didChangeNotification = Notification.Name("SakuraTypeSettingsDidChange")
    /// タイプ別設定一覧で一覧（順序・数）が変わった
    static let listDidChangeNotification = Notification.Name("SakuraTypeSettingsListDidChange")

    /// 设置的是第几个类型（sakura.ini 的 Types(N) 的 N）
    let typeIndex: Int

    init?(store: CommonSettingsStore = CoreCommonSettingsStore(), typeIndex: Int, page: Int = 0) {
        self.typeIndex = typeIndex
        super.init(dialogs: PropDialogs.load("TypeSettingsDialogs"),
                   values: CommonSettingsValues(store: store, defaultSection: "Types(\(typeIndex))"),
                   title: NSLocalizedString("タイプ別設定", comment: "タイプ別設定窗口的标题（原版 STR_PROPTYPE）"),
                   identifierPrefix: "TypeSettings", logic: { TypeSettingsPages.logic(for: $0, typeIndex: typeIndex) }, page: page)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// 打开（已经打开时到前面；同じタイプなら このページに換える）。page 是 nil 时是上次的页
    static func show(typeIndex: Int, page: Int? = nil) {
        if let shared {
            if let page, shared.typeIndex == typeIndex { shared.showPage(page) }
            shared.showWindow(nil)
            return
        }
        guard let controller = TypeSettingsWindowController(typeIndex: typeIndex, page: page ?? lastPage) else {
            NSSound.beep()
            return
        }
        shared = controller
        controller.window?.center()
        controller.showWindow(nil)
    }

    override func pageDidShow(_ index: Int) {
        Self.lastPage = index
    }

    /// 原版 CPropertyManager::OpenPropertySheetTypes：OK のあと全部の編集ウィンドウに PM_CHANGESETTING_TYPE
    override func didApply(changed: Bool) {
        if changed {
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil, userInfo: ["index": typeIndex])
        }
    }

    override func didClose() {
        if Self.shared === self { Self.shared = nil }
    }
}

// MARK: - 菜单的动作

extension EditorTextView {
    /// 設定 > タイプ別設定（F_OPTION_TYPE）、各页（F_TYPE_SCREEN 等）：这个文档的类型的设置（第 40 步）
    @objc func showTypeSettings(_ sender: Any?) {
        let code = Self.commandCode(of: sender) ?? 0
        TypeSettingsWindowController.show(typeIndex: document.typeIndex, page: TypeSettingsWindowController.pageOfCommand[code])
    }

    /// 設定 > タイプ別設定一覧（F_TYPE_LIST。原版 Command_TYPE_LIST）：選んだタイプの設定を開くか、この文書に一時適用する。
    /// タイプ別設定の窓口が開いているときは、そちらを前に出す（一覧を変えると番号がずれるため）
    @objc func showTypeList(_ sender: Any?) {
        if let shared = TypeSettingsWindowController.shared {
            shared.showWindow(nil)
            return
        }
        guard let dialog = TypeListDialog(selectedIndex: document.typeIndex, enableTempChange: true) else { return }
        guard TypeSettingsPages.runTypeListDialog(dialog, window), let result = dialog.result else { return }
        if result.temporary {
            if document.changeTypeTemporarily(result.index) {
                typeSettingsReloaded()
                refreshOutline()	// 第 42 步：タイプが変わった（原版 CEditDoc::OnChangeType → Refresh）
                MacroCommands.runAuto("nMacroOnTypeChanged", view: self)	// 第 45 步：タイプ変更後の自動実行マクロ
            }
        } else {
            TypeSettingsWindowController.show(typeIndex: result.index)
        }
    }
}

# 阶段 3：共通設定的 キー割り当て・メインメニュー・ツールバー・カスタムメニュー（计划第 41 步）

原版「設定 > 共通設定」里与命令有关的 4 页（`CPropKeybind`、`CPropMainMenu`、`CPropToolBar`、`CPropCustmenu`）做成 Mac 的页。
完成标志：设置项与原版一一对应（清单在 [common-settings.csv](common-settings.csv)）。

这一步分三个 PR：

1. **第 1 个 PR**：4 页共用的部分（核心库的共通設定的复制、功能的分类和名字），キー割り当て 页。
2. **第 2 个 PR**：メインメニュー 页。
3. **第 3 个 PR**：カスタムメニュー、ツールバー 页。

## 做法

| 部分 | 文件 | 内容 |
|---|---|---|
| 共通設定的复制 | 核心库 `CommandSettingsEditor`（`macos/core/api/SakuraCore.cpp`），App 的 `CommonSettingsValues.commandEditor` | 与原版 `CPropCommon::m_Common` 相同，打开窗口时复制一次，这几页都在这个复制上编辑：在カスタムメニュー 页改的名字，回到キー割り当て 页时「機能」列表里就是新的名字（原版 `PSN_SETACTIVE`）。OK 时各页把复制的 sakura.ini 的值（`IniValues(节)`）里改过的项写进窗口的值，与别的页相同地写回、保存 |
| 功能的分类和名字 | 原版 `func/Funccode.cpp`（分类和一览的表）、`func/CFuncLookup.cpp` 编进核心库 | 「種別」是原版的分类 + 外部マクロ + カスタムメニュー + プラグイン；「機能」与原版 `SetListItem` 相同（没有定义的不要）。カスタムメニュー・外部マクロ的名字用复制里的。Windows 的部分（ComboBox・ListBox 的设置、DLL 插件）用 `#if defined(_WIN32)` 留在原处 |
| 读写 | 核心库 `GetCommonSetting` / `SetCommonSettings` 的节 `KeyBind`、`MainMenu` | 用原版的 `ShareData_IO_KeyBind`（写 sakura.ini 时的写法：`KeyBind[nnn]=键码,8 个功能,键名`）、`ShareData_IO_MainMenu`（`MM[nnn]=层次,种类,功能,アクセスキー,名字`），读入与读 sakura.ini 时相同。メインメニュー 的项目变少时，没有了的 `MM[nnn]` 写空的值 |
| キー割り当て | `macos/app/Sources/KeyBindPage.swift` | 原版 `CPropKeybind` 的移植 |
| メインメニュー | `macos/app/Sources/MainMenuPage.swift`，核心库 `CommandSettingsEditor::MainMenuEntries` / `SetMainMenu` 等 | 原版 `CPropMainMenu` 的移植。ツリー是 `PropTree`（`CommonSettingsWindow.swift`，Mac 的 NSOutlineView）。原版 SetData（复制 → ツリー）和 GetData（ツリー → 复制：种类按功能编号决定、菜单栏最多 20 个、没有「共通設定」时加 auto_add）在核心库 |
| インポート・エクスポート | 核心库 `CommandSettingsEditor::ImportKeyBind` / `ExportKeyBind`（原版 `CImpExpKeybind`）、`ImportMainMenu` / `ExportMainMenu`（`CImpExpMainMenu`） | 文件格式与原版完全相同（*.key、メインメニュー 是 *.ini）。读入的值放进复制，OK 时才写回 |

## キー割り当て（第 1 个 PR）

与原版相同的地方：

- 打开时「種別」选第一个，「キー」列表选第一个（ダブルクリック），显示那个键的功能（未割り当て是「未割当」）。
- Shift・Ctrl・Alt 的勾：「キー」列表的名字前面加「Shift+」「Ctrl+」「Alt+」，选着的行不变（原版 `ChangeKeyList`），「キーに割り当てられている機能」是这个组合的功能。
- 选「機能」时「機能に割り当てられているキー」列出分配了这个功能的全部按键（原版 `CKeyBind::GetKeyStrList`，不包括默认的功能）。
  选那里的一行，「キー」列表和 Shift・Ctrl・Alt 的勾换成那个键。
- 「割当」：键・種別・機能都选了时可以按；「解除」：选了键时可以按（原版 `WM_TIMER` 的判断）。解除是功能 0（未割当）。
- インポート：原版的 3 种格式（KEYBIND_VERSION 的新旧、更旧的文本格式）都能读；读不了时原版的消息。エクスポート 用原版的新格式，功能写成宏的名字。
- OK 以后马上生效：按键用新的分配，菜单上显示的快捷键也换（第 34 步的菜单）。

与原版不同的地方：

- Mac 方案（默认，第 34 步）里原版的 Ctrl 是 ⌘：列表里的名字与原版相同写「Ctrl+」。Mac 方案里 macOS 自己用的键（⌘Q、⌘H、⌘W 等，见 [phase2-menu-keys.md](phase2-menu-keys.md)）
  在这里改了也不生效（与以前相同，按 macOS 的功能）。
- 鼠标的项目（ダブルクリック、右クリック、ホイール等）与原版相同可以改，写进 sakura.ini；Mac 版的编辑画面现在还没有按这些分配执行（第 30 步的鼠标操作是固定的）。
- プラグイン 的分类是空的（Mac 版没有 DLL 插件，偏离项 9）。
- 修正了原版的一个问题：*.key 的インポート 时，文件里没有 `KEYBIND_VERSION` 的话，上一次读入的版本字符串可能还留在内存里（没有初始化），
  格式不对的文件也可能被当作新格式读入。现在初始化为空（`typeprop/CImpExpManager.cpp`）。

## メインメニュー（第 2 个 PR）

与原版相同的地方：

- ツリー：原版的 MainMenu.ini 的层次、名字（命令是功能名，区切線是「――――――――――」，特別機能、子菜单）、アクセスキー显示成「名前(F)」，
  検査 找到的重复的アクセスキー 前面加「>」。「種別」的最后是「特別機能」（最近使ったファイル 等，原版 `pnFuncList_Special`）。
- 按钮的可用（原版 `SetDlgItemsEnableState`）：削除 选了项目时；↑・→ 有前一个时；↓ 有后一个时；← 有父项目时；上⇒・下⇒ 选了项目和功能时；>> 选了功能时。
- 插入的位置：＋・下⇒ 选着子菜单时是它的第一个下位项目，否则是下一个；上⇒・--- 是前面；>> 选着子菜单时是它的最后，否则是同一层的最后；
  什么也没选时加在最上层的最后。插入功能以后「機能」列表选下一个功能（连续插入）。＋ 的名字是「編集してください」。
- ↑↓ 与前后交换；→ 前一个是子菜单时成为它的最后的下位项目；← 移到父项目的下一个。削除 有下位项目时确认，之后选下一个（没有时前一个）。
- アクセスキー：双击（区切線以外）打开「メニューアイテムのアクセスキー設定」，选着项目时直接按文字键也设定（原版 `TreeViewProc`）。
- 検査（原版 `Check_MainMenu`）：同一层里重复的アクセスキー、子菜单和命令没有アクセスキー、没有『共通設定』、菜单栏超过 20 个、全部超过 500 个；
  选第一个有问题的项目。没有问题时「問題ありませんでした。」。
- クリア・初期設定（内置的 MainMenu.ini）有确认。エクスポート 先取页的内容（原版 GetData）。
- OK：没有「共通設定」时在最后加「auto_add」子菜单和「共通設定」（不能再打开设置窗口的话改不回来）。OK 以后菜单栏马上按新的设置重新做。

与原版不同的地方：

- 子菜单的名字：原版在ツリー里直接编辑（F2），Mac 版按 F2 打开输入框（与アクセスキー相同）。空的名字是「編集してください」，改了名字的子菜单变成 F_NODE（与原版相同）。
- 菜单栏：Mac 版前面一直有 App 菜单，「ウィンドウ」里加「しまう」等（第 34 步，偏离项 1）；「アクセスキーを必ず( )付で表示」与アクセスキー一样，Mac 的菜单不显示（值照原版保存）。

## 测试

- 核心库 `macos/core/tests/test-mac-command-settings.cpp`（第 1 个 PR 5 个）：「種別」「機能」（外部マクロ 50 个、カスタムメニュー 的第一个是右クリックメニュー、プラグイン 是空的）、
  键的一览和「機能に割り当てられているキー」、割当・解除只改复制，写回后按键马上用新的功能、保存后重新启动也是、
  インポート・エクスポート（原版的格式、打不开的文件、格式不对的文件）、复制与核心库分开。
- App `macos/app/Tests/KeyBindTests.swift`（第 1 个 PR 7 个）：打开时的选择和按钮的可用、Shift・Ctrl・Alt 和列表的名字、
  機能に割り当てられているキー 选了以后换键和勾、割当・解除 和 OK 只写改过的 `KeyBind[nnn]`（キャンセル 什么也不写）、
  真的核心库的 OK（按键马上变，菜单的快捷键也重新设）、几页共用一个复制、インポート・エクスポート。
- 第 2 个 PR：核心库加 4 个（SetData 的名字和特別機能、GetData 和 auto_add・写回・重新启动、菜单栏 20 个的限制、初期設定・インポート・エクスポート）；
  App `MainMenuSettingsTests` 6 个（ツリーと按钮的可用、插入・移动・删除、アクセスキー・名字・検査、クリア・初期設定・OK 的值、真的核心库、インポート・エクスポート）；
  界面测试 `testMainMenuPage`（删掉「ファイル」按 OK，菜单栏里就没有「ファイル」了）。
- 界面测试 `testKeyBindPage`：共通設定 > キー割り当て 把「選択系 > すべて選択」分配给 F12，OK 后在编辑画面按 F12 全选。

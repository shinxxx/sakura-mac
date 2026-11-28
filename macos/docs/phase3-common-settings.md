# 阶段 3：共通設定窗口（计划第 39 步）

原版的「設定 > 共通設定」（`CPropCommon`，18 页的属性表）做成 Mac 的窗口。完成标志：设置项与原版一一对应。

这一步分两个 PR：

1. **第 1 个 PR**：窗口、18 页的布局，全般・ウィンドウ・タブバー・ステータスバー・編集・ファイル・ファイル名表示・バックアップ・書式・検索・支援 这 11 页的读写和联动。
2. **第 2 个 PR**：剩下的部分：ファイル名表示 的置換リストの編集、タブバー・支援 的フォント、ウィンドウ 的「位置と大きさの設定」。

## 设置项的清单

`macos/tools/settings/list_common_settings.py` 从原版的对话框模板（`sakura_rc.rc` 的 `IDD_PROP_*`）和 `prop/CPropCom*.cpp` 列出每一页的每一个控件、它读写的 `CommonSetting` 成员、sakura.ini 的节和项目、Mac 版的处理，结果在 [common-settings.csv](common-settings.csv)（Excel 可以直接打开）：

| Mac 版 | 意思 | 个数 |
|---|---|---|
| ○ | 与原版相同地读写（強調キーワード 页是第 40 步，见 [phase3-type-settings.md](phase3-type-settings.md)；キー割り当て・メインメニュー・ツールバー・カスタムメニュー 页是第 41 步，见 [phase3-command-settings.md](phase3-command-settings.md)） | 222 |
| × | Mac 版做不到，变灰（值不改） | 30 |
| △ | 显示不同（検索 的正規表現ライブラリのバージョン：显示「組み込みの bregonig」） | 1 |
| 第 45 步 | マクロ 的页 | 14 |
| （空） | 说明文字 | 32 |

Mac 版做不到的（×）：タスクトレイ（偏离项 7）、画面キャッシュ、言語 DLL、Vista スタイルのファイルダイアログ、ファイルの排他制御（macOS 没有 Windows 的共享模式）、正規表現ライブラリ・migemo の DLL と辞書（Mac 版是组装进去的）、外部ヘルプ・外部 HTML ヘルプ（偏离项 9）、プラグイン（DLL）。

## 做法

| 部分 | 文件 | 内容 |
|---|---|---|
| 布局 | `macos/tools/settings/make_prop_dialogs.py` → `macos/app/Resources/CommonSettingsDialogs.json` | 原版对话框模板的每个控件的种类、文字、位置（对话框单位），和从页打开的对话框（`IDD_WINPOSSIZE`）。rc 改了以后重新运行 |
| 窗口 | `macos/app/Sources/CommonSettingsWindow.swift` | 按 JSON 排 Mac 的标准控件（对话框单位 × 1.6 点）。左边是页的列表，下边是 キャンセル、OK（第 40 步起这部分是 `PropSheetWindowController`，タイプ別設定窗口也用）|
| 各页 | `macos/app/Sources/CommonSettingsPages.swift` | 原版各页的 SetData / GetData / Enable…Input 的移植；フォント（`LogFontSetting`、`FontPicker`） |
| 位置と大きさ | `macos/app/Sources/CommonSettingsWindow.swift` 的 `WinSizeDialog` | 原版 `CDlgWinSize` |
| 日付・時刻の書式 | `macos/app/Sources/WindowsDateFormat.swift` | 書式 页的表示例：Windows 的 GetDateFormat / GetTimeFormat 的书式记号 |
| 读写 | 核心库 `GetCommonSetting` / `SetCommonSettings` / `SaveSettings`（`macos/core/api/SakuraCore.cpp`） | 按 sakura.ini 的「节/项目」读写。用原版的 `CShareData_IO`（内存里的 `CDataProfile`），写法和范围限制与读 sakura.ini 时完全相同。OK 时同一节的项一起写（置換リスト的 `ArrNum` 和 `From%02d`、`To%02d` 要一起读入）；有一项不在这一节里时什么也不改 |
| 履歴をクリア | 核心库 `ClearRecentFiles` / `ClearRecentFolders` | 原版 `CMRUFile::ClearAll`、`CMRUFolder::ClearAll` |

与原版相同的地方：

- 页的顺序、每页的控件、文字、位置；`F_OPTION_*`（設定 > 共通設定 的各页）打开那一页，`F_OPTION` 和 App 菜单的「設定…」（⌘,）打开上次的页（原版 `m_nPageNum`）。
- 打开时复制设置，换页时取那一页的值（原版 `PSN_KILLACTIVE`），OK 时把改过的项写回、保存 sakura.ini、通知所有窗口重画（原版 `MYWM_CHANGESETTING`）。没看过的页不改，キャンセル 什么也不改。
- GetData 里的范围限制（例：キーリピート時のスクロール行数 1～10、ファイルの履歴MAX 0～36、ルーラーの高さ 2～32、警告するファイルサイズ 1～2048 MB）、组合框的值的表（`SpecialScrollModeArr` 等）。
- 联动：タブバーを表示する 时才能改其他项、ファンクションキー表示 时才能改位置、バックアップ 的「詳細設定する」时只显示詳細設定的项目（`ShowEnable`）等。
- バックアップ 的 bit 的组合：ファイル名のタイプ（`nBackUpType` 1～6）、日付の部分（`bBackUpType2_Opt1` 的 bit）、世代数（`bBackUpType2_Opt2` 的下位 16 bit，上位的拡張子の文字不变）、自動保存（ファイル 页，`Opt1` 的 `BKUP_AUTO` bit 和 `Opt3`）。詳細設定のファイル名按原版 `UpdateBackupFile` 自动更新。
- 「ウィンドウをまとめてグループ化する」是 `bDispTabWndMultiWin` 的反面。
- ファイル名表示 的置換リスト（原版 `CPropFileName`）：两列（置換前 60%、置換後 35%）；打开时选第一行；选了的行显示在下面的两个框；
  挿入（选中的位置，没选时最后）・追加・更新（列表是空的时候追加）・削除（选同一位置）・先頭・上へ・下へ・最終；置換前是空的时候不登录；
  最多 16 项（`MAX_TRANSFORM_FILENAME`，再多时「これ以上登録できません。」）。OK 时写 `ArrNum` 和 `From%02d`、`To%02d`。
- フォント（原版 `MySelectFont`、`SetFontLabel`）：标签显示「名前(9pt)」（有小数时「名前(9.5pt)」），用那个字体显示（太大的缩小到 16pt）。
  选了字体以后改 sakura.ini 的 LOGFONT 的高さ（96 DPI 的像素）・太さ（700 / 400）・斜体、ポイントサイズ（1/10 pt）、フォント名，LOGFONT 的其他数不变。
- 位置と大きさの設定（原版 `CDlgWinSize`）：起動時の位置・大きさ 各「指定しない・継承する・直接指定」，直接指定时才能改 X・Y 座標、普通／最大化／(最小化)、幅・高さ；
  范围是 幅・高さ 0～30000、座標 -30000～30000。「閉じる」和窗口的关闭按钮都取值（原版 IDOK、IDCANCEL 都 GetData）。

与原版不同的地方（偏离项 4：布局、项目、文字照原版，外观是 Mac 的）：

- 原版的属性表的标签换成左边的列表（18 个标签 Mac 的窗口放不下）。按钮的顺序是 Mac 的习惯（OK 在右）。
- ファイル 页的「更新の監視」：原版只在排他制御「しない」时可用；Mac 版不锁文件，一直可用。
- 窗口不是模态的（Mac 的设置窗口的习惯），但一次只开一个，OK / キャンセル 的意思与原版相同。
- フォント：原版是 Windows 的 ChooseFont 对话框，Mac 版用 Mac 的字体面板，下面加了 キャンセル、OK 按钮，关掉之前等着（与原版相同是模态的）。
- 位置と大きさの設定 的「ヘルプ」：第 49 步起打开原版的那一页（[phase3-help.md](phase3-help.md)）。

## 设置的生效

这一步完成的是「设置窗口与原版一一对应、值与 Windows 版的 sakura.ini 相同地读写」。设置的值存进核心库，核心库里已经移植的部分（光标移动、复制、上書き、查找等）按新的值动作；
App 这边已经有的界面（编辑区）OK 后重新读设置重画。ツールバー、ファンクションキー、タブバーの外観、ステータスバー、バックアップ、自動保存 等 Mac 版还没有的界面，
在做那些界面的步骤里接上这些设置（功能对照表的各命令一样）。

## 测试

- 核心库 `macos/core/tests/test-mac-common-settings.cpp`（7 个）：读出的值与 sakura.ini 的写法相同、改一项不影响别的项、原版的范围限制、没有的项目和不用的节不改、保存后重新启动也是新的值、
  一次改几项（置換リスト的项数变多・变少・最多 16 项）、有一项不行时别的项也不改。
  `test-mac-recent.cpp` 加 1 个：履歴をクリア。
- App `macos/app/Tests/CommonSettingsTests.swift`（25 个）：18 页的顺序和控件与原版的模板相同、各功能打开的页、OK 只写改过的项并保存、キャンセル 不改、换页后的值保留、真的核心库的 OK、
  各页的读写・范围限制・联动（全般、ウィンドウ、タブバー、ステータスバー、編集、ファイル、ファイル名表示、バックアップ、書式、検索）、Mac 版不能用的项目变灰、履歴をクリア、日付・時刻の書式、
  置換リスト的编辑（8 个按钮、选择和框、置換前是空、最多 16 项）、タブバー・支援 的フォント（标签、选了以后的 LOGFONT、キャンセル）、位置と大きさの設定（值、联动、閉じる 以后写回）。
- 界面测试 `testCommonSettingsWindow`：⌘, 打开、换页、改一项按 OK、再打开时是改过的值和上次的页、キャンセル 不改。
  `testCommonSettingsDialogAndList`：「位置と大きさの設定」对话框（模态）的联动和「閉じる」、置換リスト的追加・削除。

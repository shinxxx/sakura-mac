# 阶段 2 第 35 步：导入原版设置

**结论**：在「設定 > Windows 版の設定をインポート…」选 Windows 版的 sakura.ini，App 重新启动后，共通設定、キー割り当て、ツールバー、メインメニュー、タイプ別設定、強調キーワード、印刷設定等都与 Windows 版相同。ini 的格式和读法与 Windows 版是同一份代码（`CShareData_IO`），导入以后再写出的 sakura.ini 除历史的几节以外与导入的文件逐行相同，什么也没有丢。历史（最近使ったファイル等）是这台 Mac 的文件，保留 Mac 的。

## 步骤

1. 「設定 > Windows 版の設定をインポート…」→ 选 sakura.ini
2. 不是サクラエディタ的设置文件（没有 `[Common]` 的 `nCaretType`）、读不了的时候显示错误，什么也不改
3. 确认：说明会换掉哪些设置、历史留 Mac 的、现在的设置的备份位置、导入后重新启动。「インポートして再起動」或「キャンセル」
4. 关闭所有的窗口（修改过的文件确认保存；这里取消时什么也不做）
5. 导入，App 重新启动

## 与原版的对应

| 原版（Windows） | Mac 版 |
| --- | --- |
| 设置搬到别的电脑：复制 sakura.ini，重新启动サクラエディタ | 「Windows 版の設定をインポート…」选 sakura.ini，自动重新启动。读法与 Windows 版相同（同一份 `CShareData_IO`、`CProfile`） |
| ini 里没有的项目（旧版本的 ini）是默认值 | 相同（先建立默认设置再读入） |
| 版本较旧的 ini 读入时做 `.bak` 备份 | 相同 |
| Shift_JIS 的旧 ini（没有 BOM） | 相同（按 Shift_JIS 读） |
| `bIniReadOnly=1`（设定不保存） | 相同：导入的 ini 是这样的话，以后结束时也不写出 |

## 换掉的和保留的

| sakura.ini 的节 | 导入后 |
| --- | --- |
| `[Common]`、`[Toolbar]`、`[CustMenu]`、`[Font]`、`[KeyBind]`、`[Print]`、`[Types(n)]`、`[KeyWords]`、`[Macro]`、`[Statusbar]`、`[MainMenu]`、`[Plugin]`、`[Nickname]`、`[Other]` | 用导入的 |
| `[MRU]`（最近使ったファイル・フォルダー）、`[Keys]`（検索・置換の履歴）、`[Grep]`（Grep の履歴）、`[Folders]`（マクロ、インポートのフォルダー）、`[Cmd]`（外部コマンドの履歴） | 保留 Mac 的（Windows 的路径在 Mac 上打不开） |

导入前的 Mac 的设置复制在 `sakura.ini.before-import`（与 sakura.ini 同一个文件夹，沙盒里在 App 的容器中）。要回到导入前，可以再用「Windows 版の設定をインポート…」选这个文件。

## 和原版不同、或者现在还没有的

- **Windows 的路径、DLL 名**（バックアップの保存先 `C:\…`、`bregonig.dll`、Migemo 的 DLL 等）：原样保留（再导出回 Windows 也一样）。Mac 上用不了的路径，对应的功能移植时再看（例如 Migemo 的词典在第 21 步已经按 ini 的文件夹找）。
- **字体**：Mac 版的编辑区字体是 App 的设置（第 28 步），不用 `[Font]` 的 Windows 字体名（`ＭＳ ゴシック` 等在 Mac 上没有）。`[Font]` 留在 ini 里。
- **键位方案**：导入的キー割り当て在 Mac 方案（⌘ 当作 Ctrl）和 Windows 方案里都用；要与 Windows 完全相同的按法，请在「設定 > Windows のキー割り当てを使う」打勾（第 34 步）。
- **表示言語**（`szLanguageDll`）：Mac 版还没有语言 DLL（第 48 步），导入的值留着不用。
- **个别项目的导入**（原版共通設定的各页的「インポート」：.key、.mnu、.kwd、タイプ別設定の .ini、.col 等）：与设置对话框一起在阶段 3。

## 测试

自动测试（见[自动测试](testing.md)）：

- `macos/core/tests/test-mac-import.cpp`（核心库，5 个）
  - 「Windows 版」的 ini（F8 换成別的功能、テキスト 加扩展名和颜色、メインメニュー 的顺序和快捷字母、`C:\` 的路径、`bregonig.dll`、Windows 的查找历史和マクロ的文件夹）导入 → 重新启动：按键、类型的判定、菜单、共通設定与 Windows 版相同；查找历史和マクロ的文件夹是 Mac 的；再写出的 ini 除历史的几节以外与导入的文件逐行相同
  - 导入前的设置有备份；重新启动之前结束时不写出（导入的文件不变）；写出的格式与 Windows 版相同（UTF-8 带 BOM、CRLF）
  - 旧版本的 Shift_JIS 的 ini：有的设置读入，没有的是默认值，做 `.bak` 备份
  - 不是设置文件（普通文本、タイプ別設定のエクスポート）、没有的文件、文件夹：不导入，设置文件不变
  - 自己的 sakura.ini 也能导入
- `macos/app/Tests/SettingsImportTests.swift`（App）：菜单项；选文件时取消；不是设置文件、读不了时的错误；确认时取消；关闭窗口时取消（可以再执行）；导入后重新启动（窗口关闭以后才导入、导入途中菜单变灰、备份）
- `macos/app/Tests/MenuKeyTests.swift`：「設定」的最后两项
- `macos/app/UITests/SakuraMacUITests.swift`（界面）：「設定 > Windows 版の設定をインポート…」→ 确认 → 结束 → 再启动后 F8 是导入的「すべて選択」（导入前是コピー）

需要在 Mac 上用手确认的：

- 用真的 Windows 版的 sakura.ini（如果手边有）导入一次，看平时用的设置（键、颜色、类型）是否都过来了。自动测试用的是从 Mac 版的 ini 改出来的「Windows 版」ini，格式相同，但真的 ini 里可能有测试没有想到的设置。
- 文件对话框（系统的，自动测试不能选文件）和重新启动（自动测试由测试那边再启动）。

## 这一步改的文件

- 新文件：
  - `macos/app/Sources/SettingsImport.swift`（「Windows 版の設定をインポート…」的步骤）
  - `macos/core/tests/test-mac-import.cpp`
  - `macos/app/Tests/SettingsImportTests.swift`
  - `macos/docs/phase2-import-settings.md`（本文档）
- `macos/core/include/sakura_core/SakuraCore.h`、`macos/core/api/SakuraCore.cpp`：`CheckSettingsFile`、`ImportSettings`、`IsSettingsImportPending`、`SettingsBackupPath`；导入以后 `Shutdown` 不写出设置
- `macos/bridge/include/EditorBridge.h`、`macos/bridge/src/EditorBridge.mm`：`EditorImportResult`、`EditorCore.importSettings` 等
- `macos/app/Sources/MainMenuBuilder.swift`：「設定」的最后加菜单项
- `macos/app/Sources/AppDelegate.swift`：导入途中最后一个窗口关闭也不结束
- `macos/app/Sources/UITesting.swift`：`-SakuraUITestingImportFile`
- `macos/app/Tests/MenuKeyTests.swift`、`macos/app/UITests/SakuraMacUITests.swift`、`macos/app/project.yml`、`macos/core/tests/tests.cmake`、`macos/README.md`

原版的文件（sakura_core）没有改，Windows 版的行为不变。

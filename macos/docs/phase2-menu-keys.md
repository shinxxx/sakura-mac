# 阶段 2 第 34 步：菜单与快捷键

**结论**：菜单栏现在按原版的 `MainMenu.ini`（共通設定 > メインメニュー）生成，顶层菜单、子菜单、分隔线、项目的名字和顺序都与 Windows 版相同；快捷键按原版的按键分配表（共通設定 > キー割り当て）执行。默认是 Mac 方案（⌘ 当作 Ctrl：⌘C コピー、⌘F 検索、⌘R 置換、⌘J 指定行へジャンプ、F3 次を検索、F8 コピー 等），在「設定 > Windows のキー割り当てを使う」可以换成原版的 Windows 键位（⌃ 是 Ctrl）。还没有移植的功能在菜单里变灰。

第 34 步分 3 个 PR：

1. 菜单栏和快捷键的机制
2. 光标、选择、矩形选择的 MVP 命令（単語の左端に移動、半ページ、移動履歴、(選択)／(矩形選択) 的各命令等）
3. 文件、模式、设定的 MVP 命令（各编码で開き直す、閉じて開く、挿入／上書きモード、文字コードセット指定、フォントサイズ、バージョン情報 等）

## 与原版的对应

| 原版（Windows） | Mac 版 |
| --- | --- |
| 菜单栏的构成（`MainMenu.ini`、`CEditWnd::LayoutMainMenu`）：ファイル、編集、変換、検索、ツール、設定、ウィンドウ、ヘルプ和它们的子菜单 | 相同。核心库读同一个表（`sakura::core::MainMenu`），App 按 level 组装 |
| 项目的名字：`MainMenu.ini` 里写了名字用那个名字，否则用功能名（字符串表） | 相同 |
| 最近使ったファイル／フォルダー（29002、29003） | 第 31 步的历史子菜单 |
| ウィンドウ一覧（29001） | macOS 自动列出窗口（`NSApp.windowsMenu`） |
| カスタムメニュー、登録済みマクロ、プラグイン（29004～29006） | 空（阶段 4 以后） |
| 菜单的「&」快捷字母（`m_sKey`） | 不显示（macOS 的菜单没有） |
| 按键分配表（`CKeyBind`，Shift／Ctrl／Alt 的 8 种组合） | 相同的表（`sakura::core::FunctionForKey`），Mac 的按键先换成 Windows 的虚拟键码 |
| 菜单上显示的快捷键（`Ctrl+C` 等） | macOS 的方式显示（Mac 方案 ⌘C，Windows 方案 ⌃C） |
| 不能用的功能变灰（`IsFuncEnable`） | 已移植的功能按状态变灰（例如没有选择时的コピー）；还没有移植的总是灰 |

## 两种键位方案

| | Mac 方案（默认） | Windows 方案 |
| --- | --- | --- |
| 原版的 Ctrl | ⌘ | ⌃ |
| 原版的 Alt | ⌥ | ⌥ |
| 方向键、Home/End、PageUp/PageDown、Delete、Return | macOS 的文字编辑习惯（⌘← 行头、⌥← 单词、⌘↑ 文件开头等） | 原版的表（⌃Home ファイルの先頭、⌃← 単語の左端 等） |
| ⌃ 组合 | macOS（Emacs 风格的 ⌃A、⌃E 等） | 原版的表 |
| 只按 ⌥ 的字符键 | 输入特殊字符（⌥A = å） | 原版的表（⌥A 昇順ソート 等） |
| F 键、Tab、Esc、Space | 原版的表 | 原版的表 |

Mac 方案里为了和 Mac 的其它 App 一致，下面的键与原版不同（原版这些键上的功能只能从菜单执行）：

| 键 | Mac 版 | 原版的 Ctrl+键 |
| --- | --- | --- |
| ⌘Q | 終了（App 菜单） | キー割り当て一覧をコピー |
| ⌘H／⌥⌘H | 隠す／ほかを隠す | カーソル行をウィンドウ中央へ |
| ⌘M | しまう | キーマクロの保存 |
| ⌘W | 閉じる | 現在位置の単語選択 |
| ⌘G／⇧⌘G | 次を検索／前を検索（F3／⇧F3 也能用） | Grep |
| ⇧⌘Z | やり直し（⌘Y 也能用） | （没有） |
| ⇧⌘S | 名前を付けて保存 | （没有） |
| ⌘, | 設定（App 菜单） | （没有） |

第 32 步临时用的 ⌥⌘F 置換、⌘L 指定行へジャンプ 改成原版的 ⌘R、⌘J。

键位方案是 App 的设置（不在 sakura.ini 里），菜单上的快捷键显示也跟着变。按键分配的变更（共通設定 > キー割り当て）在设置对话框的步骤（阶段 3）做；现在可以直接改 sakura.ini 的 `[KeyBind]`。

## 和原版不同、或者现在还没有的

- **还没有移植的功能**：菜单项变灰，分配给它的键按普通的输入处理（例如 Space 的「SPACEインデント」现在是输入空格，与原版没有选择时相同）。第 2、3 个 PR 和后面的步骤里逐步加上（对照表 `macos/docs/feature-matrix.csv`）。
- **App 菜单、ウィンドウ > しまう**：macOS 必备的项目，原版没有（已确认的偏离项 1）。
- **记号键**：按键的位置换成 Windows 的 VK（US 键盘和日文键盘的 VK 不同，与 Windows 相同）。字母、数字键按印着的字母（Dvorak 等也对）；假名输入时按位置。
- **Windows 方案的 ⌃←／⌃→ 等**：macOS 的「调度中心」默认用这些键切换桌面，要用原版的功能时需要在 系统设置 > 键盘 > 键盘快捷键 里关掉。

## 测试

自动测试（见[自动测试](testing.md)）：

- `macos/core/tests/test-mac-menu.cpp`（核心库，8 个）：顶层菜单的名字和顺序、ファイル菜单的顺序和分隔线、子菜单的层次、特殊列表（29001～29006）、名字来自功能名、层次只一层一层地变深、默认的按键分配（Ctrl+C、F3、Home、Alt+← 等）、没有分配的组合、`KeyBindings` 和 `FunctionForKey` 一致。
- `macos/app/Tests/MenuKeyTests.swift`（App）：生成的菜单栏的顶层菜单、项目的 tag 和动作、未移植的没有动作；Mac 的追加（最近使ったファイル、しまう、ウィンドウ一覧、键位方案）；两种方案的菜单快捷键；按键 → 原版按键的变换（US／日文键盘的记号键、Dvorak、假名输入、方向键、⌥ 字符、⌃ 组合）；`keyDown` 执行 F8 コピー、F7 切り取り、F9 貼り付け、Esc、⌘A、Windows 方案的 ⌃Home／⌃End，普通的字符照常输入。
- `macos/app/UITests/SakuraMacUITests.swift`（界面）：菜单栏的顶层菜单、已移植的项目可用、Grep 变灰、インクリメンタルサーチ 子菜单；F8 → Esc → F9；切换到 Windows 方案后 ⌃A すべて選択、切回后不是；第 32 步的测试改用 ⌘R、⌘J。

需要在 Mac 上用手确认的：没有（菜单的外观由界面测试的截图可以看到；快捷键在不同键盘布局下的行为由单元测试按布局分别确认）。

## 这一步改的文件（第 1 个 PR）

- 新文件：`macos/app/Sources/CommandTable.swift`（功能编号 → 动作）、`macos/app/Sources/KeyCommands.swift`（按键 → 功能、键位方案）、`macos/core/tests/test-mac-menu.cpp`、`macos/app/Tests/MenuKeyTests.swift`、`macos/docs/phase2-menu-keys.md`（本文档）
- `macos/core/include/sakura_core/SakuraCore.h`、`macos/core/api/SakuraCore.cpp`：`MainMenu`、`KeyBindings`、`FunctionForKey`
- `macos/bridge/include/EditorBridge.h`、`macos/bridge/src/EditorBridge.mm`：`EditorMenuItem`、`EditorKeyBinding`、`EditorCore.mainMenu` 等
- `macos/app/Sources/MainMenuBuilder.swift`：按原版的表生成菜单栏
- `macos/app/Sources/EditorTextView.swift`：`keyDown` 先查按键分配表
- `macos/app/Sources/UITesting.swift`：界面测试从 Mac 方案开始
- `macos/app/UITests/SakuraMacUITests.swift`、`macos/app/project.yml`、`macos/core/tests/tests.cmake`
- `macos/docs/phase2-search.md`：快捷键改成 ⌘R、⌘J

## 第 2 个 PR：光标、选择、矩形选择

原版 `CViewCommander_Cursor.cpp`、`CViewCommander_Select.cpp` 的 MVP 命令都能从菜单和快捷键执行：

- 移动：単語の左端／右端、２行ごと、半ページ、１ページ（画面也翻一页）、段落、変更行、行頭（先跳过缩进）、論理行頭／行末、ファイルの先頭／最後，每个都有 (範囲選択) 和 (矩形選択) 版
- 选择：範囲選択開始（F6，之后普通的移动扩展选择）、矩形範囲選択開始、現在位置の単語選択、1行選択
- 移動履歴：前へ／次へ／移動履歴をセット（与原版一样最多 30 个；ファイルの先頭／最後、検索、ジャンプ时登记）
- 画面：カーソル行をウィンドウ中央／上部／下部へ、テキストを１行上／下へスクロール、ホイール系
- macOS 的按键（⌥←、⌘↑、⌃A 等）也执行同样的原版命令
- 移到哪里的算法（単語、段落、変更行、缩进）在核心库：`Document::WordMoveTarget`、`ParagraphTarget`、`ModifiedLineTarget`、`IndentEnd`
- 还没有：オートスクロール（与鼠标的设置一起在阶段 3）

## 第 3 个 PR：文件、模式、设定、バージョン情報

| 原版的命令 | Mac 版 |
| --- | --- |
| 閉じて(無題) | 确认保存后，同一个窗口变成新文档（核心库 `Document::CloseToUntitled`） |
| 閉じて開く | 确认保存后出「開く」对话框，选的文件在同一个窗口打开；取消时原来的文件留着；多选时其余的开新窗口 |
| 保存して閉じる | 没有修改就直接关闭；无题时先「名前を付けて保存」 |
| 上書き保存(限定動作)、すべて上書き保存 | 无题的窗口什么也不做；有修改（或者改了文字コードセット）的保存 |
| 新規作成（新しいウインドウで開く） | 与「新規作成」相同（Mac 版是一个进程多个窗口） |
| ○○で開き直す、開き直す | 用指定的编码重新读入，修改过时先问（原版的消息），光标和表示域留着；现在的编码打勾；无题时只设定编码 |
| 挿入／上書きモード切り替え（Insert，Mac 键盘是 Help 键） | 上書き时输入的字换掉光标处的字（「改行は上書きしない」「文字幅に合わせてスペースを詰める」与原版相同），光标变成一个字宽（半透明）；打勾 |
| 文字コードセット指定 | 原版的「文字コードの指定」对话框（编码、CP、BOM）；改了以后关闭前要确认保存 |
| 入力改行コード指定（CRLF/LF/CR/NEL/PS/LS） | 现在的换行符打勾（CRLF/LF/CR，与原版相同） |
| 現在のウィンドウ幅で折り返し | ウィンドウ幅 → 最大値 → 設定値 的切换（原版 `GetWrapMode` 的判断，在核心库） |
| フォントサイズ拡大／縮小 | 原版的倍率表。不保存（原版的一時的な変更）；字体设置改变时回到原来的大小 |
| バージョン情報 | 原版的内容（名字、原作者、版权、Project URL、说明、情報をコピー），另外显示 zlib 许可证全文和「这是改变过的版本，不是官方版」的声明。App 菜单的「について」也打开这里 |

和原版不同的地方：

- **フォントサイズ拡大／縮小**：原版只改这一个窗口；Mac 版的排版字体是所有窗口共用的（第 27 步），所以所有窗口一起变。大小按 1 点取整（原版 0.5 点），因为排版只能用整数点。
- **保存的确认**：用 macOS 的对话框（保存、不保存、取消），内容与原版相同。

## 测试（第 2、3 个 PR）

- `macos/core/tests/test-mac-cursor.cpp`（核心库，8 个）：単語、段落、変更行（绕回）、缩进的目标
- `macos/core/tests/test-mac-mode.cpp`（核心库，13 个）：閉じて(無題)、文字コードセット指定和「変更されている」的判断（新文件、保存后）、挿入モード的切换和共通設定、上書き（普通、行末、改行は上書きしない 关掉时、补充平面字符、TAB、换行、文字幅に合わせてスペースを詰める）、各菜单的打勾、ウィンドウ幅で折り返し 的顺序（普通、极窄、不能改变）、倍率表
- `macos/app/Tests/CursorCommandTests.swift`（App）：各移动、选择、矩形选择、移動履歴、画面滚动
- `macos/app/Tests/FileModeCommandTests.swift`（App）：Insert 切换和上書き输入（撤销一步、光标宽度）、入力改行コード、文字コードセット指定（对话框换成测试用的）、○○で開き直す（确认、取消、光标留着、无题）、閉じて(無題)（同一个窗口、历史登记）、上書き保存(限定動作)、ウィンドウ幅で折り返し、フォントサイズ拡大／縮小、バージョン情報的内容和「情報をコピー」、命令都有动作
- `macos/app/UITests/SakuraMacUITests.swift`（界面）：⌥→ 単語移動 和 F6 範囲選択開始；ヘルプ > バージョン情報 打开和关闭

需要在 Mac 上用手确认的：

- 「閉じて開く」：系统的「開く」对话框是另一个进程，自动测试不能选文件。确认：改一个文件 → ファイル > 閉じて開く → 问保存 → 选别的文件，在同一个窗口打开；取消时原来的文件还在。
- 「保存して閉じる」「閉じて(無題)」修改过时的保存确认对话框：macOS 的标准对话框，自动测试不按它的按钮。

## 这一步改的文件（第 2、3 个 PR）

- 新文件：
  - `macos/app/Sources/CursorCommands.swift`（光标、选择、矩形选择的命令）
  - `macos/app/Sources/FileCommands.swift`（ファイル菜单的命令）
  - `macos/app/Sources/ModeCommands.swift`（模式切换、设定的命令）
  - `macos/app/Sources/AboutPanel.swift`（バージョン情報）
  - `macos/core/tests/test-mac-cursor.cpp`、`macos/core/tests/test-mac-mode.cpp`
  - `macos/app/Tests/CursorCommandTests.swift`、`macos/app/Tests/FileModeCommandTests.swift`
- `macos/core/include/sakura_core/SakuraCore.h`、`macos/core/api/SakuraCore.cpp`、`macos/core/CMakeLists.txt`（加 `sakura_core/util/zoom.cpp`）
- `macos/bridge/include/EditorBridge.h`、`macos/bridge/src/EditorBridge.mm`
- `macos/app/Sources/EditorTextView.swift`、`CommandTable.swift`、`SakuraDocument.swift`、`FileDialogAccessory.swift`、`MainMenuBuilder.swift`、`SearchCommands.swift`
- `macos/app/UITests/SakuraMacUITests.swift`、`macos/app/project.yml`、`macos/core/tests/tests.cmake`

# 阶段 3：Grep・Grep置換（计划第 43 步）

原版「検索 > Grep」「Grep置換」（`CGrepAgent`、`grep/CGrepEnum*.h`、`CDlgGrep`、`CDlgGrepReplace`、`CViewCommander_Grep.cpp`）和
アウトライン解析 的ファイルツリー（`CDlgFuncList::SetTreeFile`、`CDlgFileTree`）做成 Mac 版。
完成标志：用户先授权文件夹，再在其中搜索，结果可跳转；授权记忆在重启后仍然有效；
grep 文件枚举头文件按 Mac 路径规则改写，`test-cgrepenumkeys`、`test-grepenum`、`test-grep-exclude-regex`、`test-grepinfo` 通过；`CGrepAgent` 的 `std::to_wstring` 改掉。

这一步分几个 PR：

1. **第 1 个 PR（#45）**：核心库的 Grep・Grep置換（文件的枚举、原版的 `CGrepAgent::DoGrep` 在 Mac 上运行）、与 Windows 官方版的对照，
   Grep 对话框的数据部分和タグジャンプ（核心库）。
2. **第 2 个 PR**：Grep・Grep置換 的对话框、「Grep実行中」、结果的窗口、タグジャンプ、文件夹的授权。
3. **第 3 个 PR**：ファイルツリー。

## 核心库（第 1 个 PR）

| 部分 | 文件 | 内容 |
|---|---|---|
| 文件的枚举 | 原版 `grep/CGrepEnum*.h` | 原版用 Win32 的 `FindFirstFile`。Mac 版由平台层提供 `FindFirstFileW`・`FindNextFileW`・`FindClose`（`macos/platform/src/file_api.cpp`），头文件只把路径的分隔 `\` 换成 `PATH_DELIMITER`（`util/file.h`，Mac 版是 `/`） |
| 检索 | 原版 `agent/CGrepAgent.cpp` | 原版的 `DoGrep` 用编辑窗口（撤销、光标、绘制、「Grep実行中」对话框、图标）。这些部分用 `#if defined(_WIN32)` 分开，Mac 版的结果的文档是 `IGrepResultView`（`CGrepAgent.h`），检索、标题、结果的格式、置換、文件的写回照原版的代码运行 |
| 接口 | `GrepSession`（`macos/core/api/Grep.cpp`，`SakuraCore.h`） | App 在别的线程运行 `Run`，在界面的线程用 `TakeOutput` 取出结果、`Progress` 显示进度、`Cancel` 中断。代替原版「Grep実行中」对话框（中断的检查间隔 100ms、文件名的显示 15ms 与原版相同）和结果的文档 |
| 編集中のテキストから検索 | `GrepSourceText`、`IGrepSourceDoc` | 原版用 `:HWND:` 向别的窗口要每一行。Mac 版在界面的线程先取出文档的全部行，`:HWND:` 后面是文档的番号（`GrepSourceToken`），结果的格式与原版相同（无题时是 `:HWND:[番号](無題)1(行,桁): …`） |
| 删除・改名 | `DeleteFileW`、`MoveFileW`（平台层） | Grep置換 写回文件（原版 `CWriteData`：写 `.skrnew`，删除或改名成 `.skrold`，再改名）。与 Windows 相同：只读文件不能删除，改名时新的名字已经有文件则失败 |

### 文件的顺序

Windows 的 `FindFirstFile`（NTFS）按名字的大写的 UTF-16 顺序返回，Grep 的结果也是这个顺序。Mac 的文件系统（APFS）的顺序不同，
所以 Mac 版的 `FindFirstFileW` 读完文件夹以后按同样的规则排序（`.`、`..` 在前）。大写的变换做常用的部分：ASCII、Latin-1、希腊文、西里尔文、全角英文字母。
样本里有大小写、记号、数字、日文的名字，结果的顺序与 Windows 官方版相同（下面的对照）。

### 与原版不同的地方

- 当前文件夹：原版 Grep 以后把当前文件夹改成检索的文件夹（不加 `-GOPT=X` 时）。Mac 版的进程里只有一个当前文件夹，不改（总是 X）。
- 标准输出（`-GOPT=U`）、命令行的 Grep（`-GREPMODE`）：Mac 版没有命令行，不用。
- 文件的属性：Mac 没有系统属性；隐藏是名字以 `.` 开头或 Finder 的隐藏标志。Grep 不看属性（原版也是），ファイルツリー 用。
- 正规表现库的版本（结果的标题「(正規表現:…)」）：Mac 版内置 bregonig，Windows 版是 bregonig.dll，文字可能不同。

### 修正的问题

- 大小写不区分的比较（`skr_towlower`・`skr_towupper`，`util/string_ex.cpp`）：Mac 的 `towlower` 在 C 语言环境里只变换 ASCII，
  全角英文字母等在「英大文字と小文字を区別しない」时也找不到（原版的测试 `FullWidthIgnoreCase` 发现）。改成用 UTF-8 语言环境变换，
  256 以下与 Windows 版的变换表相同。这也影响查找・置換（第 32 步），现在与 Windows 版相同。

### 测试

- 原版的测试 `test-cgrepenumkeys`、`test-grepenum`、`test-grep-exclude-regex`、`test-grepinfo` 在 Mac 上运行，全部通过。
  Windows 的绝对路径（`C:\work`）换成 Mac 的（`/work`）、`sub\x.txt` 换成 `sub/x.txt`；`test-grepinfo` 里 `CCommandLine`・`CDlgGrep` 的部分只在 Windows 版
  （Mac 版没有命令行；Grep 对话框的测试在 App，第 2 个 PR）。
- 原版的 `test-grep-cmdline.cpp`（-GREPMODE 的 133 个测试）移到 `macos/core/tests/test-mac-grep.cpp`，测试名与原版相同，经过 `GrepSession`（App 用的同一个接口）：
  结果的文档 → `TakeOutput`，消息框 → `errorMessage`，剪贴板 → `pasteText`，`:HWND:` 的窗口 → `GrepSourceText`，
  不共享地打开的文件 → 没有读的权限（chmod 000），共享读取地打开的文件 → 不能改的文件（chflags uchg）。
  Mac 版没有的（标准输出、改变当前文件夹、`OnBeforeClose`・`OnAfterSave` 是界面层、8.3 形式的短名字）不移。
- 与 Windows 官方版的对照：`macos/core/tests/data/grep/` 的 `tree/`（各种编码、换行、名字的文件，`macos/tools/grep/make_grep_samples.py` 生成）
  用 `cases.txt` 的 23 个条件（结果出力・形式、ベースフォルダー・フォルダー毎、単語単位、大小、正規表現、文字コード 自動選択・固定、除外、ファイル検索、Grep置換 3 个）检索，
  结果与 `expected/` 比较。CI 的 `grep-windows` 用 Windows 官方版 sakura.exe 的 `-GREPMODE`（`-GOPT=U` 的标准输出）检索同样的条件（`macos/tools/grep/windows-grep.ps1`），
  与同一个 `expected/` 比较。比较前两边都把检索的文件夹的绝对路径换成 `{DIR}`（Windows 再把 `\` 换成 `/`），正规表现库的版本换成 `{VERSION}`；
  Grep置換 还比较置換后的全部文件的内容。

## 对话框和结果的窗口（第 2 个 PR）

`macos/app/Sources/GrepDialog.swift`、`GrepRunner.swift`、`TagJump.swift`。布局照原版 IDD_GREP・IDD_GREP_REPLACE・IDD_GREPRUNNING
（`Resources/GrepDialogs.json`，`make_prop_dialogs.py` 生成；入力できるコンボボックス（CBS_DROPDOWN）は NSComboBox）。

与原版相同的地方：

- 命令：検索 > Grep（F_GREP_DIALOG）、Grep置換（F_GREP_REPLACE_DLG）、タグジャンプ（F_TAGJUMP）、タグジャンプバック（F_TAGJUMPBACK）、閉じてタグジャンプ（F_TAGJUMP_CLOSE）。
- 对话框：条件的初始值（选择的文字、光标的单词或历史，原版 GetCurrentTextForSearchDlg）、各组合框的历史、除外 的初始值（历史是空的时候是原版的默认值）、
  共通設定的值（サブフォルダー・文字コードセット・結果出力・形式 等）、カレントフォルダーが初期値、現フォルダー、上階層へ、「...」、
  正規表現 时 単語単位 不能选、結果のみ 时 ベースフォルダー・フォルダー毎 不能选、CP（代码页加到文字コードセット）、
  編集中のテキストから検索（対象・フォルダー显示「(現在のドキュメント)」，Grep置換 不能选）、
  OK 的检查（引用符、ワイルドカード、フルパス、フォルダー、正規表現，消息与原版相同）、历史和共通設定的登记，对话框记着上次的内容（一个窗口一个）。
  Grep置換：置換後（置換後的历史）、クリップボードの内容で置換（剪贴板是空的时候去掉勾）、バックアップ作成、「置換条件を指定してください。」。
- 结果的窗口（原版 Command_GREP）：Grep 的窗口（检索中以外）或没改过的空的无题窗口就用这个窗口，否则开新窗口；类型是扩展名 grepout 的类型；
  标题是条件（32 字以内，长的加「...」）；结束后没有修改，光标在加入之前的行，条件用「検索文字列」的颜色显示。
  关闭时：共通設定「Grepモードで保存確認する」开着时总是确认，关着时不确认（原版 OnFileClose）；检索中不能关闭（「Grepの処理中です。」）；保存后变成普通的窗口。
- 「Grep実行中」：件数、ファイル、フォルダー、リアルタイム表示（共通設定的值开始）、キャンセル（结果里有「中断しました。」）。
- タグジャンプ：Grep 的结果的全部形式（ノーマル・ファイル毎・結果のみ 以外、ベースフォルダー・フォルダー毎）、「ファイル名(行,桁)」的消息；
  Grep 的窗口里 Enter（共通設定「エンターキーでタグジャンプ」，⌃Enter 是閉じてタグジャンプ）、双击（「ダブルクリックでタグジャンプ」）。
  打开着的文件移到那一行，没打开的打开；「編集中のテキストから検索」的结果回到那个窗口。タグジャンプバック 回到跳转之前的窗口和位置。

与原版不同的地方：

- 文件夹的授权（沙盒）：App Store 版只能读用户在对话框里选的文件夹。「...」选的文件夹记安全书签（`FolderAccess`，`folder-bookmarks.plist`）；
  输入的文件夹没有权限时，OK 时出「開く」对话框（显示那个文件夹，按「許可」）。重启后从书签取回权限（上层的文件夹的书签也可以），不再问。
  Grep置換 写回文件也用这个权限（选文件夹的对话框给读写的权限）。
- 相对路径・現フォルダー 的起点：原版是当前文件夹，Mac 版是编辑中的文件的文件夹（新文件时是主文件夹）。
- 进度和中断：原版在编辑窗口的线程检索、一边处理消息；Mac 版在别的线程检索，界面一直能操作（检索中的窗口不能关）。
- 结果的窗口的番号：原版的窗口标题是「$h」（条件），Mac 版的窗口标题只有条件（没有「 - サクラエディタ」等，与 Mac 的其他窗口相同）。
- 状态栏的消息（「タグジャンプできません」等）：Mac 版还没有状态栏，用提示音。
- ヘルプ：Mac 版还没有帮助，变灰。

### 测试

- App `GrepTests`：对话框的外观（文字不截断・不重叠，与 `PropLayoutTests` 相同的检查）、初始值、各控件的联动、OK 的条件・共通設定・历史、OK 的检查的消息、
  編集中のテキストから検索、结果的窗口（哪个窗口、Grep モード、标题、没有修改、光标、検索文字列の色、保存的确认）、检索中不能关闭・保存后不是 Grep 的窗口、
  「Grep実行中」、タグジャンプ（Enter・双击・タグジャンプバック・各形式・编辑中的文档）、Grep置換、貼り付ける文字、文件夹的授权。
- 界面测试 `testGrepAndTagJump`（菜单打开对话框、输入、检索、结果、Enter 打开文件、タグジャンプバック）、
  `testSandboxedGrepFolderAfterRestart`（只在 run-tests.sh：沙盒的 App 检索沙盒外的文件夹，第一次按「許可」，重启后不问就能检索、从结果打开文件）。

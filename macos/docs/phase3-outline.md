# 阶段 3：アウトライン解析（计划第 42 步）

原版「検索 > アウトライン解析」（`CDlgFuncList`、`CViewCommander_Outline.cpp`、各语言的解析 `types/CType_*.cpp`）做成 Mac 版。
完成标志：各内置语言的解析结果与 Windows 版一致。

这一步分三个 PR：

1. **第 1 个 PR（#41）**：核心库的アウトライン解析、与 Windows 官方版的对照。
2. **第 2 个 PR（#42）**：アウトライン解析 的窗口（フローティング）、命令。
3. **第 3 个 PR（#43）**：ドッキング（左・右・上・下）和它的设置。

ブックマークの一覧（F_BOOKMARK_VIEW，同一个窗口的リスト）在移植ブックマーク的步骤，ファイルツリー（F_FILETREE）在 Grep 的步骤（第 43 步：要先有文件夹的授权和 Grep 的文件枚举）。
核心库和窗口已经能处理这两种（`OutlineType::Bookmark`、ブックマーク一覧的「テキスト」列名、「空行を無視する」）。

## 核心库（第 1 个 PR）

| 部分 | 文件 | 内容 |
|---|---|---|
| 解析 | 原版 `doc/CDocOutline.cpp`、`types/CType_*.cpp`（不改） | 原版的解析函数用 `m_pcDocRef`（CEditDoc）的行数据、排版、类型别设置、文件名、输入改行。Mac 版没有 CEditDoc，`CDocOutline.h` 在 Mac 上用只有这些成员的 `COutlineDocRef`（成员名与 CEditDoc 相同，解析的代码照原样编译） |
| 解析的命令 | `Document::AnalyzeOutline`（`macos/core/api/SakuraCore.cpp`） | 原版 `Command_FUNCLIST` 的解析部分：类型别设置的解析方法，C/C++ 按扩展名是 C 或 C++，ルールファイル（相对路径从 sakura.ini 的文件夹），没有的方法用テキスト（Mac 版没有 DLL 插件的解析）。同时设置関数リストマーク（原版 `SetDocLineFuncList`） |
| ツリー・リスト | `macos/core/api/OutlineView.cpp` | 原版 `CDlgFuncList::SetData` 的数据部分：`SetTreeJava`（「クラス名::」「\」分出クラス的项目、グローバル）、`SetTree`（按层次）、`SetListVB`・リスト（第 4 列的「関数」「宣言」等），窗口标题，「コピー」的文字。TreeView 的「加在前面（デフォルト(降順)）・后面」、按名字找已有的クラス项目，照原版的顺序做 |
| 順序・並べ替え | `SortOutlineTree`、`SortOutlineRows`、`OutlineItemAt` | 原版 `SortTree`（`lstrcmpi`，同名按加入的顺序）、`SortListView`（`ListView_SortItems` 是稳定的排序）、`GetFuncInfoIndex` |
| 関数リストマーク | `Document::FindFuncListMark` | 原版 `Command_FUNCLIST_NEXT/PREV` 的查找（`CFuncListManager`），「先頭（末尾）から再検索する」时绕回 |

### 与 Windows 版的对照

`macos/core/tests/data/outline/` 有 22 个样本：内置的全部解析方法（C、C++、C/C++ 的头文件、PL/SQL、テキスト、Java、COBOL、アセンブラ、Perl、Visual Basic、
WZ階層付テキスト、HTML、TeX、Python、Erlang、XML）、ルールファイル（通常、正規表現置換）、ツリー的「順序」3 种、リスト的「関数名」降順。

- Mac：核心库测试 `test-mac-outline.cpp` 打开这些文件解析，把窗口标题、ツリー（层次、展开状态、选着的项目）或リスト（列名、各行、选着的行）、「コピー」的文字写成文字，
  与 `expected/` 的文件比较。
- Windows：CI 的 `outline-windows` 下载官方发布版 sakura.exe（v2.4.3），追加与 Mac 测试相同的类型（`sakura.ini` 的 `Types(N)`），
  用宏 `Editor.FileOpen`・`Editor.Outline(0)` 打开对话框，从对话框读出同样的内容（TreeView・ListView 的消息，`macos/tools/outline/windows-outline.ps1`），
  按「コピー」读剪贴板，与同样的 `expected/` 比较。

两边都与 `expected/` 相同，就是 Mac 版与 Windows 版的结果逐字节相同。22 个全部相同。

做的过程中发现并修正的：アルファベット順 用的比较原来跟着用户的语言（日文环境下汉字排在英文的前面），改成固定的照合（英语：英文、假名、汉字的顺序，与 Windows 相同）。

与原版不同的地方：

- アルファベット順：原版是 Windows 的 `lstrcmpi`（单词排序），Mac 版用 Core Foundation 的照合（英语）近似（不区分大小写，
  ハイフン・アポストロフィ只在其他都相同时比较）。普通的名字顺序相同（样本的 C++・テキスト 与 Windows 相同），特殊的记号、全角半角混在时可能不同。
- 「行」「桁」：タイプ別設定「行番号の表示」是「折り返し単位」时，原版「桁」是排版的横向位置（Windows 的点）+1，Mac 版也是排版的横向位置（Mac 的点）+1，数值随字体不同。

## 窗口和命令（第 2 个 PR）

`macos/app/Sources/OutlineWindow.swift`。布局照原版 IDD_FUNCLIST（`Resources/OutlineDialogs.json`，`macos/tools/settings/make_prop_dialogs.py` 生成，与设置窗口相同的 `PropPage` 摆放，`PropLayoutTests` 的检查也适用）。

与原版相同的地方：

- 命令：検索 > アウトライン解析（F_OUTLINE）：已经开着同じ种类时只拿到前面，种类不同时再解析；アウトライン解析(トグル)（F_OUTLINE_TOGGLE）：同じ种类时关闭。
  次の関数リストマークへ／前の関数リストマークへ（F_FUNCLIST_NEXT/PREV）：移到上次解析的项目的行，「先頭（末尾）から再検索する」时绕回，找不到时「前方(↓) に関数が見つかりません。」。
- 窗口：非模态，一个编辑窗口一个，打开时在编辑窗口的中央（「位置と大きさを記憶する」■ 时在上次的位置和大小）。改大小时ツリー・リスト变大，下面的按钮・复选框跟着下边（原版 anchorList），最小・最大的大小也照原版。
- 窗口标题、ツリー・リスト、第一层展开（C++・Java 等）、光标所在的项目被选中（上层展开），光标移动时选择跟着移动（关着的上层不展开，选能看见的上层），编辑以后不再跟着（原版 NotifyDocModification）。
- ジャンプ：按钮・Return・双击，空格是不关闭的ジャンプ；选择锁定中边选边移（原版 PM_SETCARETPOS_KEEPSELECT），纵向滚动留画面 1/6 的余白（原版 _CARETMARGINRATE / 3）。
  「自動的に閉じる」时关闭，「フォーカスを移す」时回到编辑画面（自動的に閉じる 时这个勾不能改）。クラス名・グローバル 等的项目不跳转。
- 「順序」改了马上排序，记在タイプ別設定（nOutlineSortType）；リスト点列名排序，再点降序，记在タイプ別設定（nOutlineSortCol・bOutlineSortDesc）。
- コピー：原版的「コピー」的文字（タグジャンプ的格式）。在列表里按分配了 コピー・切り取り 的键也复制，分配了 アウトライン解析 的键是更新。
- 右键菜单：更新、コピー、すべて展開・すべて縮小（ツリー）、ウィンドウの位置、閉じる；▼ 是ウィンドウの位置 的菜单。
- タイプ別設定的解析方法改了时，开着的アウトライン 再解析。

与原版不同的地方：

- ▼・■ 按钮：原版 10×14 的小按钮，Mac 的圆角按钮放不下「▼」，用没有余白的方形按钮（位置、大小照原版）。
- 访问键：标签的「(C)」等照原版写，Mac 没有 Alt 的访问键。
- ヘルプ：Mac 版还没有帮助，变灰。
- ツリー的连接线：Mac 的 NSOutlineView 用三角形表示展开，没有原版的点线。

## ドッキング（第 3 个 PR）

`macos/app/Sources/OutlineDock.swift`。编辑窗口的内容换成 `EditorContainerView`（编辑画面 + 停靠的アウトライン），原版是把对话框变成编辑窗口的子窗口（`CEditWnd::EndLayoutBars`）。

与原版相同的地方：

- ▼（和右键的ウィンドウの位置）：左・右・上・下ドッキング、フローティング、ドッキング禁止、ドッキング配置を同期、共通継承・タイプ別継承、継承情報を統一（确认后复制到共通設定和全部タイプ別設定）。
  设置项与原版的 sakura.ini 相同（`nOutlineDockSet`、`bOutlineDockSync`、`bOutlineDockDisp`、`eOutlineDockSide`、`xyOutlineDock`、`nDockOutline`，タイプ別継承 时是 `Types(N)` 的项目）。
- 停靠时：上面是标题栏（标题，右边是 更新・ウィンドウの位置・閉じる 的按钮，焦点在アウトライン 时变成强调色），里边有分割バー（拖动改大小，最小 60，记在 xyOutlineDock）；
  下面的按钮・复选框隐藏，ツリー・リスト到底；颜色是编辑画面的文字色・背景色，选中的项目反色（原版 SyncColor）。
  单击项目就跳转（焦点留在アウトライン），双击・Return 跳转并回到编辑画面，Esc 回到编辑画面。初次的大小是编辑区域的 1/3。
- 拖动标题栏改配置（原版 Track）：拖到编辑窗口的边上（光标的大小以内）停靠，别的地方是フローティング，按着 Ctrl 一直是フローティング，Esc・右键取消；拖动中显示放下的位置的框。
  フローティング的窗口拖动标题栏到编辑窗口的边上松开也停靠（ドッキング禁止 时不停靠）。
- 打开文件、新窗口、重新读入、タイプ一時適用时（原版 Refresh / ChangeLayout）：设置是「表示」并且停靠时自动打开アウトライン；フローティング 不自动打开（原版相同）。
  「同期」时一个窗口改了配置、大小、开关，别的窗口也跟着改。

与原版不同的地方：

- 标题栏的按钮：原版用 Marlett・Webdings 字体的记号，Mac 用 SF Symbols（×、∨、↻），提示文字与原版相同。
- 拖动フローティング的窗口：Mac 的窗口移动由系统处理，松开鼠标时在编辑窗口的边上才停靠；拖动中显示停靠位置的框。

## 核对后的补充（第 4 个 PR）

- ルールファイル：タイプ別設定的「参照」选的文件记下安全书签（`BookmarkStore.settingFiles`，`setting-file-bookmarks.plist`，与「最近使ったファイル」分开），
  解析时用书签取回权限，App Store 版（沙盒）重启后也能读。背景画像・単語ファイル・キーワード辞書 用同一个「参照」，书签也记下了（读那些文件的功能在以后的步骤接上）。
- ルールファイル 不是 BOM 付き UTF-8、又不能当 Shift_JIS 读时：原版会抛出没人接的异常（`CError_TextEncoding`），Mac 版与读不到时相同，项目为空（不崩溃）。
- 浮动窗口的标题栏右键也出菜单（原版 OnContextMenu）。
- 停靠的标题栏按钮：鼠标在上面时用强调色涂（原版 OnNcPaint 的高亮）；按钮宽 16 点，默认的 1/3 宽度下标题不被截断（自动测试检查）。

## 测试

- 核心库 `test-mac-outline.cpp` 28 个（含 22 个样本与 Windows 版相同的结果）；CI `outline-windows`（Windows 官方版的结果）。
- App `OutlineTests` 19 个、`OutlineDockTests` 11 个（含停靠外观：标题不截断・不与按钮重叠、编辑画面的颜色、反色的选择）；`PropLayoutTests` 也检查 IDD_FUNCLIST。
- 界面测试 `testOutlineWindow`（菜单打开、双击跳转、自動的に閉じる）、`testOutlineDocking`（左ドッキング、单击・双击跳转、× 关闭）、
  `testOutlineDockingByDrag`（拖动停靠・浮动）、`testSandboxedRuleFileAfterRestart`（沙盒的 App 选沙盒外的ルールファイル，重启后解析读得到；去掉书签时这个测试失败，已确认）。
- 在 Mac 上截图核对：フローティング（C++ ツリー、VB リスト、右键菜单、▼、順序）、ドッキング（左・右・上・下、单击跳转后的反色选择）。

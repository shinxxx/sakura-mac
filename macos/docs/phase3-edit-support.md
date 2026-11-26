# 阶段 3：编辑辅助功能（计划第 44 步）

原版「検索」「ツール」菜单里的编辑辅助功能：対括弧、ブックマーク、インクリメンタルサーチ、DIFF差分表示・ファイル内容比較、
入力補完・キーワードヘルプ、tags 文件的タグジャンプ 做成 Mac 版。
完成标志：功能对照表中这一类全部有结论（下面的「结论表」）。

这一步分三个 PR：

1. **第 1 个 PR（#50）**：対括弧の検索・強調表示、ブックマーク。新的 CI `edit-support-windows`（与 Windows 官方版对照）。
2. **第 2 个 PR（#51）**：インクリメンタルサーチ（含 MIGEMO）、ステータスメッセージ、DIFF差分表示・ファイル内容比較、入力補完・キーワードヘルプ。
3. **第 3 个 PR**：tags 文件的タグジャンプ（ダイレクトタグジャンプ、キーワードを指定してタグジャンプ、タグジャンプ一覧），タグファイルの作成 的结论。

## 结论表

「Mac 版」一列：✅ 与原版相同；🔶 做了，有与原版不同的地方（写在后面）；⏭ 在以后的步骤；✖ Mac 版没有（写明原因和替代）。

| 命令 | 编号 | 原版 | Mac 版 | 说明 |
|---|---|---|---|---|
| F_BRACKETPAIR | 30960 | 対括弧の検索 | ✅ | 对应表 18 组、嵌套、光标前面的字、跳过补充平面字符。选择锁定中扩展选择 |
| （颜色「対括弧」） | — | 対括弧の強調表示 | ✅ | タイプ別設定『カラー』的「対括弧」打开时（原版默认关），光标处和对应的括弧用这个颜色。选择中、没有焦点、对应的括弧在画面外时不显示 |
| F_BOOKMARK_SET | 30970 | ブックマーク設定・解除 | ✅ | 多行选择时选择范围的每行反转（选择的末尾行也包括） |
| F_BOOKMARK_NEXT | 30971 | 次のブックマークへ | ✅ | 「先頭（末尾）から再検索する」、找不到时的消息 |
| F_BOOKMARK_PREV | 30972 | 前のブックマークへ | ✅ | 同上 |
| F_BOOKMARK_RESET | 30973 | ブックマークの全解除 | ✅ | |
| F_BOOKMARK_VIEW | 30974 | ブックマークの一覧 | ✅ | アウトライン解析的窗口（第 42 步）显示ブックマーク的一覧 |
| F_BOOKMARK_PATTERN | 30975 | パターンに一致する行をマーク | ✅ | 现在的检索文字和条件。検索・置換对话框的「該当行マーク」 |
| （ブックマーク的保存） | — | 最近使ったファイル 里记ブックマーク | ✅ | 关闭时记到历史，打开时按共通設定「ブックマークを復元する」恢复。格式与原版相同（`:0…`） |
| F_ISEARCH_NEXT | 30981 | 前方インクリメンタルサーチ | 🔶 | 原版的状态显示在状态栏，Mac 版显示在编辑区左下的标签 |
| F_ISEARCH_PREV | 30982 | 後方インクリメンタルサーチ | 🔶 | 同上 |
| F_ISEARCH_REGEXP_NEXT | 30983 | 前方正規表現インクリメンタルサーチ | 🔶 | 同上 |
| F_ISEARCH_REGEXP_PREV | 30984 | 後方正規表現インクリメンタルサーチ | 🔶 | 同上 |
| F_ISEARCH_MIGEMO_NEXT | 30985 | 前方MIGEMOインクリメンタルサーチ | 🔶 | 引擎（C/Migemo，MIT）内置；词典是 GPL，不附带，用户在共通設定『支援』的「辞書」指定（2026-11-09 决定）。没有词典时「MIGEMOは使用できません。」 |
| F_ISEARCH_MIGEMO_PREV | 30986 | 後方MIGEMOインクリメンタルサーチ | 🔶 | 同上 |
| F_DIFF_DIALOG | 30976 | DIFF差分表示... | 🔶 | 原版调用 GNU diff（GPL）。Mac 版不附带，自己实现差分（zlib），结果与 GNU diff 对照（下面） |
| F_DIFF | 30977 | DIFF差分表示（文件名的参数） | ⏭ | 只能从宏执行（参数是文件名和选项），第 45 步（宏）。核心库的 `Document::ApplyDiff` 已经可以用 |
| F_DIFF_NEXT | 30978 | 次の差分へ | ✅ | 差分を表示していないときは使えない（原版 IsFuncEnable） |
| F_DIFF_PREV | 30979 | 前の差分へ | ✅ | 同上 |
| F_DIFF_RESET | 30980 | 差分の全解除 | ✅ | 同上 |
| F_COMPARE | 30950 | ファイル内容比較... | 🔶 | 原版与别的进程的窗口比较，Mac 版与同一个 App 的窗口比较。「左右に表示」把两个窗口放在画面的左右一半 |
| F_HOKAN | 31430 | 入力補完 | 🔶 | 補完ファイル・編集中データ・強調キーワード。原版默认键 Ctrl+Space 在 Mac 方案是 ⌘Space（Spotlight 占用），用菜单「ツール > 入力補完」、Windows 键方案的 ⌃Space 或自己分配的键 |
| F_TOGGLE_KEY_SEARCH | 31431 | キーワードヘルプ自動表示 | ✅ | 菜单打勾。设置不保存（原版也不保存，启动时关） |
| （キーワードヘルプ） | — | 辞書 Tip | ✅ | タイプ別設定『キーワードヘルプ』的辞書。鼠标停 300ms，用选择范围或光标处的单词。补完窗口的候补也显示。双击 Tip 打开辞書的那一行 |
| F_TAGJUMP | 30940 | タグジャンプ | ✅ | 第 43 步（Grep 的结果）。文件名没有的行用 tags 文件找（第 44 步） |
| F_TAGJUMP_CLOSE | 30945 | 閉じてタグジャンプ | ✅ | 同上 |
| F_DIRECT_TAGJUMP | 30944 | ダイレクトタグジャンプ | 🔶 | 编辑中的文件的文件夹往上找 tags。沙盒：要文件夹的许可（第 43 步的 FolderAccess，选上层的文件夹时下面的 tags 都能读） |
| F_TAGJUMP_KEYWORD | 30946 | キーワードを指定してタグジャンプ... | 🔶 | 同上 |
| F_TAGJUMP_LIST | 30942 | タグジャンプリスト | ✖ | 原版也没有处理（`HandleCommand` 里没有这个功能，`Funccode_x.hsrc` 是「？」）。タグジャンプ一覧的对话框由ダイレクトタグジャンプ（候补多个时）和キーワードを指定してタグジャンプ 打开 |
| F_TAGS_MAKE | 30943 | タグファイルの作成... | ✖ | 原版调用 ctags.exe（universal-ctags，GPL）。与 Migemo 词典相同，GPL 与 App Store 的条款有冲突的风险，不附带（2026-11-26 shin 确认），菜单变灰。用别处（Homebrew 的 universal-ctags 等）生成的 tags 文件 |
| F_SEARCH_BOX | 30908 | 検索(ボックス) | ⏭ | 原版是工具栏里的检索框，Mac 版还没有工具栏（第 41 步只做了设置）。代替：検索ダイアログ（⌘F）、インクリメンタルサーチ |

不在这一步的（功能对照表的其他类）：F_COMPAREVERSION（宏函数，第 45 步）、F_GREP・F_GREP_REPLACE（宏专用，第 45 步）、F_OPEN_HfromtoC（ファイル操作）。

## 与 Windows 官方版的对照（CI `edit-support-windows`）

`macos/tools/editsupport/windows-edit-support.js` 是官方版 sakura.exe 的宏，`windows-edit-support.ps1` 运行它。
Mac 版的核心库测试（`test-mac-edit-support.cpp`）做同样的操作，结果写成同样的格式，两边都与 `macos/core/tests/data/editsupport/expected/` 比较。

| 文件 | 内容 |
|---|---|
| `bracket.txt` | `brackets.txt` 的每一行的每个位置执行対括弧の検索后的光标（对应表全部、嵌套、注释和字符串中、补充平面字符、没有对应） |
| `bookmark.txt` | `bookmarks.txt` 上：设置・选择范围反转・次・前（再検索する・しない）・全解除・パターン（大小・単語・正規表現） |
| `diff.txt` | GNU diff（GnuWin32 2.8.7，原版的安装程序附带的版本）直接比较 `diff/<名字>/old.txt`・`new.txt` 的塊の見出し，17 组样本 × 7 种选项 |
| `diffmark.txt` | 官方版 sakura.exe 的宏 `Diff()` 以后各行的差分标记（`GetLineAttribute(y, 3)`），17 × 7 × 编辑中的文件是新・旧 |

差分没有时原版一定弹出「DIFF差分は見つかりませんでした。」的消息框（`ViewDiffInfo` 把选项变量改写成了执行选项，0x40 总是有效），宏会停住。
所以 GNU diff 没有输出的组合宏不执行 `Diff()`，直接读标记（全部 0）。

对照中发现、已改成与 GNU diff 2.8.7 相同的地方：-b・-w 时不区分最后一行有没有换行；-B 同时有 -b・-w 时只有空白的行也算空行。

インクリメンタルサーチ、入力補完、キーワードヘルプ、タグジャンプ 不能用宏执行（原版的宏没有这些命令，或者会出模态的对话框），
由核心库测试按原版的算法确认（检索用第 32 步的同一个 CSearchAgent；辞書・補完 用原版的 CDicMgr；tags 的检索是原版 CDlgTagJumpList 的移植）。

## 与原版不同的地方

- **ステータスメッセージ**：Mac 版还没有状态栏。原版在状态栏（没有状态栏时在菜单栏）显示的消息，Mac 版显示在编辑区左下的小标签里：
  I-Search 中一直显示，「▼先頭から再検索しました」「▽見つかりませんでした」「タグジャンプできません」等几秒后消失（検索・ブックマーク・差分・関数リスト・変更行 共用）。
- **差分的计算**：GNU diff 不附带，Mac 版自己实现（`macos/core/api/Diff.cpp`：Myers 的 O(ND) 算法，再把变更的块移到与 diff 相同的位置）。
  行的分法与 Windows 版的 diff 相同（LF 分行，CR LF 的 CR 不算），没有换行的最后一行与有换行的行不同（-b・-w 时相同）。
  17 组样本 × 7 种选项的结果与 GNU diff 2.8.7 完全相同（CI 的 edit-support-windows）。
  -i 只对 ASCII（与 diff 相同），-t 不影响结果（diff 的输出选项）。
  原版比较临时文件（编码是 UTF-8，两边都是 Shift_JIS 时是 Shift_JIS）；Mac 版比较 Unicode 的文字，Shift_JIS 表示不了的字的比较不会因为变成「?」而相同。
- **ファイル内容比較**：同一个 App 的窗口（Mac 版一个 App 管理所有窗口）。
- **DIFF 的相手**：「他の編集中のファイル」的一览是这个 App 的窗口，标签格式与原版相同（`1 路径 *  [UTF-8]`）。外部ファイル 没有读的权限时请用户许可那个文件夹。
- **入力補完の窓口**：不抢焦点的小窗口（原版也是 MA_NOACTIVATE），位置在单词的下面，大小可以改，记到 App 结束。候补的顺序与原版的 LBS_SORT 相同（不区分大小写）。
- **MIGEMO 的词典**：共通設定『支援』的「辞書」从这一步可以用（第 39 步变灰）。用「参照」选文件夹时记许可，重启后也能读。改了设置以后下次检索时重新读词典（原版要重启）。
- **tags 文件**：原版用 ANSI（日文 Windows 是 Shift_JIS）读，Mac 版用 UTF-8（Mac 的 ANSI，ctags 的输出也是 UTF-8）。路径的分隔是 `/`。
  无题的文件的基准是主文件夹（原版是当前文件夹）。
- **ヘルプ** 按钮：Mac 版还没有帮助，变灰（第 49 步）。

## 测试

- 核心库 `test-mac-edit-support.cpp`（34 个）：対括弧（各种情况、表示領域）、ブックマーク（设置、次・前、パターン、保存的格式、历史的恢复）、
  I-Search 的检索（开始位置、後方の再検索、MIGEMO）、差分（塊、选项、标记、次・前）、ファイル内容比較、入力補完（GetLeftWord、候补）、キーワードヘルプ、
  タグジャンプ一覧（上层的 tags、タグジャンプモード、二分・线形检索、前方・部分一致、页、最近的候补、!_TAG_S_SEARCH_NEXT・S_FILE_BASEDIR、历史），
  以及与 Windows 对照的 4 个。
- App：`BracketPairTests`、`BookmarkTests`、`ISearchTests`、`DiffTests`、`HokanTests`、`TagJumpListTests`；外观 `PropLayoutTests`（IDD_DIFF・IDD_COMPARE・IDD_TAGJUMPLIST）、
  截图 `DialogScreenshotTests`。
- 界面测试：`testBracketPair`、`testBookmarks`、`testIncrementalSearch`、`testDiff`、`testInputCompletion`、`testDirectTagJump`。

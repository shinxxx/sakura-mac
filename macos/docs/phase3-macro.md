# 阶段 3：宏（计划第 45 步）

原版「ツール」菜单的キーマクロ和マクロ（JScript）做成 Mac 版。这一步分几个 PR：

1. **核心库（commit 3f5a72a）**：原版 CSMacroMgr 的関数表、CKeyMacroMgr 的キーマクロ文件（.mac）的读写、CSakuraEnvironment::ExpandParameter、
   CCookieManager、JScript 的前处理，移到 `macos/core/api/Macro.cpp`；桥接层 `MacroCore`、`MacroCall`、`ExpandParameterView` 等。
2. **PR A（#54）**：キーマクロ的记录・保存・读取・执行，宏命令和函数的执行（`MacroHost.swift`）。
3. **PR B**：JScript 宏（JavaScriptCore，`JSMacro.swift`），名前を指定してマクロ実行・登録済みマクロ・自動実行（`MacroCommands.swift`），
   共通設定『マクロ』页。Editor 对象用同一个 `MacroHost`。

## キーマクロ（PR A）

| 命令 | 编号 | 原版 | Mac 版 | 说明 |
|---|---|---|---|---|
| F_RECKEYMACRO | 31250 | キーマクロの記録開始／終了 | 🔶 | 记录中窗口标题加「【キーマクロの記録中】」（原版默认的标题格式 `${M?  【キーマクロの記録中】$}`）。原版状态栏的「REC」：Mac 版没有状态栏，没有。停止时保存到マクロ用フォルダー的 `RecKey.mac`，成为「キーマクロの実行」的文件 |
| F_SAVEKEYMACRO | 31251 | キーマクロの保存 | 🔶 | NSSavePanel（初始位置是マクロ用フォルダー，类型 .mac）。记录中时停止记录（不写 RecKey.mac），与原版相同 |
| F_LOADKEYMACRO | 31252 | キーマクロの読み込み | 🔶 | NSOpenPanel。与原版相同只记文件名，执行时再读。选的文件记安全书签（`setting-file-bookmarks.plist`），沙盒里也能读 |
| F_EXECKEYMACRO | 31253 | キーマクロの実行 | ✅ | 记录中时先停止记录（保存 RecKey.mac）再执行。全体是一个撤销单位（原版 ExecKeyMacroAfter）。文法错误时先显示原版的「Macro読み込みエラー」，再显示「ファイルを開けませんでした。」，一行也不执行 |

- 菜单的名字与原版相同，记录中变成「キーマクロの記録終了」「キーマクロの記録終了&保存」等（原版 SetMenuFuncSel）；记录中只有记录中的窗口可以用（原版 IsFuncEnable）。
- マクロ用フォルダー：共通設定 `Folders` 的 `szMACROFOLDER`。相对路径从设置文件的文件夹算（原版 GetInidirOrExedir），空的或者是 Windows 的路径（导入的设置）时用设置文件的文件夹。
- 关闭记录中的窗口时停止记录，不保存（原版 WM_DESTROY）。

### 记录（原版 CViewCommander::HandleCommand 的记录部分、CMacro::AddLParam）

原版所有的操作都经过 HandleCommand，记录在那里。Mac 版在这些地方记录（只记录 `MacroCore.canRecord` 的功能，原版 CanFuncIsKeyMacro）：

| 操作 | 记录的地方 | 记录的行 |
|---|---|---|
| 按键分配表的键（KeyCommands） | `CommandTable.perform` | 功能编号，参数按 AddLParam |
| 菜单 | `NSMenu.willSendActionNotification`（项目的 tag 是功能编号，动作与 CommandTable 相同） | 同上 |
| 输入的文字 | `insertText` | `Char(文字コード)` 一个字一行；输入法确定的文字是 `CharIme`；补充平面的字是 `InsText` |
| macOS 的按键（方向键、Return、BackSpace、Delete、Tab 等，Mac 键方案不查表的键） | `doCommand(by:)` 的选择子 → 原版默认键分配的功能（`keyMacroSelectorCodes`） | 例如 ← 是 `Left(0)`，Return 是 `Char(13)`，BackSpace 是 `DeleteBack(0)` |
| 検索・置換・指定行へジャンプ 对话框 | 对话框的按钮 | `SearchNext('key', flags)`、`ReplaceAll('key', 'rep', flags)`、`Jump(line, flags)` 等，flags 与原版相同 |

参数（AddLParam）：矩形选择移动的选项（0 时按共通設定「矩形選択移動で選択をロックする」）、半页・一页移动的行数（画面的行数）、
检索・置换的 flags（单词 0x01、大小写 0x02、正则 0x04、見つからないとき 0x08、自動的に閉じる 0x10、先頭から再検索 0x20、
クリップボードから 0x40、選択範囲 0x80、置換対象 ×0x100、置換の繰返し 0x400），其它都是一个数值 0。

### MacroHost（原版 CMacro::HandleCommand・HandleFunction）

キーマクロ的每一行和以后的 JScript 宏的 Editor 对象都经过 `MacroHost`。命令把参数换成原版 HandleCommand 的形式调用 Mac 版的功能；
Mac 版还没有的命令与原版对不认识的功能编号相同，什么也不做（返回成功，宏继续）。参数错误时显示原版的「Macro実行エラー」和消息，宏停止。

**命令：按原版的参数处理的**

Char、CharIme、CtrlCode、InsText、AddTail、ChgmodEOL（1/3/4/5/6/7）、CHG_CHARSET（有参数时直接设置）、Jump、SearchNext、SearchPrev、
BookmarkPattern、Replace、ReplaceAll（flags 的 0x800 不登记历史、0x1000 恢复检索条件）、MoveCursor、MoveCursorLayout、
MessageBox・ErrorMsg・WarnMsg・InfoMsg・OkCancelBox・YesNoBox、StatusMsg（编辑区左下的标签）、MsgBeep、ClipboardEmpty、SetViewTop、SetViewLeft、MacroSleep、SetDrawSwitch。
其它命令按功能编号执行（CommandTable：移动、选择、编辑、检索、模式、设置等已经移植的全部），参数不用。

**命令：没有处理的（什么也不做，宏继续）**

InsBoxText、SetFontSize，以及还没有移植的功能（印刷、外部命令 ExecCommand、TraceOut、PutFile・InsFile、FileOpen2・FileSaveAs、Grep・GrepReplace、Diff、
TopMost 等）、ChgTabWidth・ChgWrapColumn（作为命令）、
COMMITUNDOBUFFER・ADDREFUNDOBUFFER・SETUNDOBUFFER・APPENDUNDOBUFFERCURSOR（Mac 版的撤销按编辑的组管理，整个宏是一个撤销单位）、
（PR B 补上了：TextWrapMethod、SetMsgQuoteStr、ChangeType、ExecExternalMacro、CopyPath・CopyFilename・CopyDirPath。）

**函数（返回值）**

GetFilename、GetSaveFilename、GetSelectedString、ExpandParameter、GetLineStr、GetLineCount、IsTextSelected、
GetSelectLineFrom・GetSelectColumnFrom・GetSelectLineTo・GetSelectColumnTo、IsInsMode、GetCharCode、GetLineCode、IsPossibleUndo・IsPossibleRedo、
CompareVersion、MessageBox 系、InputBox、GetClipboard、SetClipboard、LayoutToLogicLineNum・LogicToLayoutLineNum・LineColumnToIndex・LineIndexToColumn、
GetCookie・GetCookieDefault・SetCookie・DeleteCookie・GetCookieNames、SetDrawSwitch・GetDrawSwitch、IsShownStatus（Mac 版没有状态栏，总是 0）、
IsTextSelectingLock、GetViewLines、GetViewColumns、GetViewTop、MacroSleep；PR B：ChangeWrapColumn、FileOpenDialog・FileSaveDialog（过滤器不用）・FolderDialog。
桁（列）与原版相同是半角单位（Mac 版的排版位置是点，除以半角一字的宽度）。

**函数：还没有的（失败）**：ChangeTabWidth（核心库还没有临时改 TAB 幅的接口）、IsCurTypeExt・IsSameTypeExt（还没有按扩展名找类型的接口）、
GetStrWidth・GetStrLayoutLength・GetDefaultCharLength、GetLineAttribute、CreateMenu（宏里的弹出菜单）、ChangeInsSpace：以后。
IsIncludeClipboardFormat・GetClipboardByFormat・SetClipboardByFormat：不支持（Windows 剪贴板格式的名字）。

## JScript 宏（PR B）

原版用 Windows Script Host 的 JScript 引擎，把「Editor」对象作为全局成员加进去（AddNamedItem SCRIPTITEM_GLOBALMEMBERS），
所以 `InsText('a')` 和 `Editor.InsText('a')` 都能用，名字不分大小写（GetIDsOfNames 的 _wcsicmp）。Mac 版用 JavaScriptCore（`JSMacro.swift`）：

| 项目 | Mac 版 | 说明 |
|---|---|---|
| 读入 | ✅ | `MacroCore.loadSourceFile`（BOM 付き UTF-8・UTF-8・Shift_JIS 等，与原版相同），再 `MacroCore.prepareJScript` 给没有括号的调用（`GetFilename`、`SelectWord;`、`while (IsPossibleUndo)`）加 `()`（JScript 的 DISPATCH_PROPERTYGET 也执行） |
| 全局的名字 | 🔶 | JavaScriptCore 的全局对象不能换原型，所以把脚本整个包在 `with (Proxy) { … }` 里（同一行开始，行号不变）。Proxy 用 `MacroCore.findFunctionIgnoreCase` 查名字。脚本自己声明的名字（var、function）优先 |
| 命令 | ✅ | 参数全部变成字符串（原版 VariantChangeType VT_BSTR：整数、`1.5`、`True`/`False`、null・undefined 是空），交给 MacroHost.handleCommand，返回 undefined |
| 函数 | ✅ | 数值・字符串・真假（-1/0）交给 MacroHost.handleFunction。失败（原版 E_FAIL）是 JavaScript 的例外「エラーを特定できません」 |
| 错误 | 🔶 | 原版 MacroError 的消息框「[Line n] 说明」。标题是「JScript 実行時エラー」「JScript コンパイル エラー」（原版是 Microsoft JScript 的）；说明是 JavaScriptCore 的英文（例：Can't find variable: Foo），原版是 JScript 的日文 |
| ActiveXObject | 🔶 | 只有 `WScript.Shell` 的 `Popup(文字, 秒, 标题, 种类)`（帮助的样例用）：NSAlert，秒数到了返回 -1。其它 ProgID（FileSystemObject 等）是「オートメーション サーバーはオブジェクトを作成できません」 |
| 取消 | 🔶 | 脚本在别的线程运行，编辑的操作在主线程。超过共通設定「キャンセル確認待ち時間」显示原版 IDD_MACRORUNNING 的「マクロ実行中・・・」窗口，按キャンセル（Esc）以后，下一次调用命令・函数时是「マクロの実行を中断しました。」的例外。JavaScriptCore 没有从外面停止脚本的公开方法，不调用命令・函数的死循环停不了（按キャンセル 2 秒后放弃等待，线程留着） |
| 撤销 | ✅ | 整个宏是一个撤销单位。宏里的 Undo 先结束这个单位再撤销（帮助的样例 SampleIsPossibleUndo） |
| 记录 | ✅ | 键盘宏记录中，宏里的命令不记录（原版 FA_NONRECORD），名前を指定してマクロ実行 本身记录为 `ExecExternalMacro('路径')` |

### 名前を指定してマクロ実行・登録済みマクロ・自動実行（`MacroCommands.swift`）

| 命令 | 编号 | Mac 版 | 说明 |
|---|---|---|---|
| F_EXECEXTMACRO | 31254 | 🔶 | NSOpenPanel（マクロ用フォルダー）。按扩展名：.mac 键盘宏、.js JScript；.vbs .vbe .jse .wsf .wsc .pls .ppa .py 显示「このマクロ（.vbs）は Mac 版では実行できません。」（VBScript・PPA 依赖 Windows；Python 宏不做，项目负责人决定）。宏里 `ExecExternalMacro(代码, 'js')` 也可以 |
| F_USERMACRO_0+n | 31600～31649 | ✅ | ツール > 登録済みマクロ（名字，没有名字时文件名）。读过的宏记住，「マクロを実行するたびにファイルを読み込みなおす」时每次读；改了共通設定时忘掉（原版 UnloadAll）。读不了时「マクロ n (文件) の実行に失敗しました。」 |
| 自動実行 | — | ✅ | 新規／開ファイル後（窗口第一次显示时）、タイプ変更後（タイプ別設定一覧 的一時適用、ChangeType、另存为后类型变了）、ファイル保存前（GetSaveFilename 是保存的路径）。按着 Shift 时不执行，自动执行里的命令不记录 |
| F_COPYPATH・F_COPYFNAME・F_COPYDIRPATH | 30620・30622・30631 | ✅ | tools/macro/CopyDirPath 用（无题时蜂鸣） |

### 共通設定『マクロ』（原版 CPropComMacro）

布局按原版 IDD_PROP_MACRO。一览总是 50 行（番号、マクロ名、ファイル名、実行時に読み込み on/off、自動実行 O・T・S），选一行时下面的名前・File・Id・复选框跟着变，
［設定(A)］把下面的内容放进 Id 的那一行（自動実行 各只有一个宏）。File 的候选是マクロフォルダー里的文件。OK 时写 sakura.ini 的
`[Macro]` `Name[000]`・`File[000]`・`ReloadWhenExecute[000]`・`nMacroOnOpened`・`nMacroOnTypeChanged`・`nMacroOnSave`・`nMacroCancelTimer` 和 `[Folders]` `szMACROFOLDER`（末尾加 `/`）。
Python フォルダー 变灰（Python 宏不做）。列宽按原版的比例，但让 5 列都能看见（原版的「実行時に読み込み」标题也是截断的）。

### 帮助的样例（完成标志）

`help/macro/source/sample/*.html` 的 JScript 部分（12 个，放在 `macos/app/Tests/MacroSamples/`）和 `tools/macro/CopyDirPath/CopyDirPath.js` 都在 App 单元测试 `JSMacroTests` 里执行并确认结果：
SampleChar、SampleExpandParameter、SampleGetCharCode、SampleGetFilename、SampleGetLineCode、SampleGetLineCount、SampleGetLineStr、SampleGetSelectedString、
SampleGetSelectxxx、SampleIsInsMode、SampleIsPossibleUndo、SampleIsTextSelected、CopyDirPath。
其余样例是 VBScript・PPA（SampleBookmarkPattern、SampleChangeTabWidth、SampleFileSaveAs、SampleGrep、SampleReplaceAll、SampleSearchNext）或键盘宏（SampleGoLineTop），Mac 版不用 VBScript・PPA。

## 测试

见 [testing.md](testing.md) 的「マクロ（第 45 步）」。

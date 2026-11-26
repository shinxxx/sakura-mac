# 阶段 3：宏（计划第 45 步）

原版「ツール」菜单的キーマクロ和マクロ（JScript）做成 Mac 版。这一步分几个 PR：

1. **核心库（commit 3f5a72a）**：原版 CSMacroMgr 的関数表、CKeyMacroMgr 的キーマクロ文件（.mac）的读写、CSakuraEnvironment::ExpandParameter、
   CCookieManager、JScript 的前处理，移到 `macos/core/api/Macro.cpp`；桥接层 `MacroCore`、`MacroCall`、`ExpandParameterView` 等。
2. **PR A（这个 PR）**：キーマクロ的记录・保存・读取・执行，宏命令和函数的执行（`MacroHost.swift`）。
3. **PR B（以后）**：JScript 宏（JavaScriptCore），Editor 对象用同一个 `MacroHost`。

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

InsBoxText、SetFontSize、TextWrapMethod，以及还没有移植的功能（印刷、外部命令 ExecCommand、TraceOut、PutFile・InsFile、FileOpen2・FileSaveAs、Grep・GrepReplace、Diff、
SetQuoteString、TopMost、ChangeType 等）、ChgTabWidth・ChgWrapColumn（作为命令）、
COMMITUNDOBUFFER・ADDREFUNDOBUFFER・SETUNDOBUFFER・APPENDUNDOBUFFERCURSOR（Mac 版的撤销按编辑的组管理，整个宏是一个撤销单位）、
ExecExternalMacro（PR B）。

**函数（返回值）**

GetFilename、GetSaveFilename、GetSelectedString、ExpandParameter、GetLineStr、GetLineCount、IsTextSelected、
GetSelectLineFrom・GetSelectColumnFrom・GetSelectLineTo・GetSelectColumnTo、IsInsMode、GetCharCode、GetLineCode、IsPossibleUndo・IsPossibleRedo、
CompareVersion、MessageBox 系、InputBox、GetClipboard、SetClipboard、LayoutToLogicLineNum・LogicToLayoutLineNum・LineColumnToIndex・LineIndexToColumn、
GetCookie・GetCookieDefault・SetCookie・DeleteCookie・GetCookieNames、SetDrawSwitch・GetDrawSwitch、IsShownStatus（Mac 版没有状态栏，总是 0）、
IsTextSelectingLock、GetViewLines、GetViewColumns、GetViewTop、MacroSleep。
桁（列）与原版相同是半角单位（Mac 版的排版位置是点，除以半角一字的宽度）。

**函数：还没有的（失败）**：ChangeTabWidth、ChangeWrapColumn、IsCurTypeExt、IsSameTypeExt、FileOpenDialog・FileSaveDialog・FolderDialog、
GetStrWidth・GetStrLayoutLength・GetDefaultCharLength、IsIncludeClipboardFormat・GetClipboardByFormat・SetClipboardByFormat、GetLineAttribute、CreateMenu、ChangeInsSpace。
（JScript 宏用得多的会在 PR B 补上。）

## 测试

见 [testing.md](testing.md) 的「マクロ（第 45 步）」。

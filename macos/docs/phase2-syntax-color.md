# 阶段 2 第 33 步：语法高亮

**结论**：注释、字符串、强调关键字、半角数字、URL、正規表現キーワード、ヒアドキュメント的颜色（原版的「色分け」）现在会显示了。判断哪里是什么颜色，用的就是原版的代码（`view/colors` 的 `CColor_Comment`、`CColor_Quote`、`CColor_KeywordSet` 等，原样编进核心库），按原版画面的顺序调用（`CEditView::DrawLogicLine`）。颜色、粗体、下划线读的是原版的类型别设置，所以内置类型的效果与 Windows 版一致。完成标志由核心库测试逐类型确认（全部 17 种内置类型），App 测试把画面画到位图上确认颜色和下划线，界面测试截取实际 App 的画面确认 URL 是蓝色。

## 与原版的对应

| 原版（Windows） | Mac 版 |
| --- | --- |
| 色分け的种类和优先顺序：正規表現キーワード → ヒアドキュメント → ブロックコメント1・2 → 行コメント → シングル／ダブルクォーテーション → URL → 半角数値 → 強調キーワード | 相同（原版的 `CColorStrategyPool`） |
| 跨行的块注释、字符串：排版时记下每行开头的状态（`CLayout::GetColorTypePrev`），编辑后后面的行跟着变 | 相同（原版的 `CLayoutMgr`） |
| 各内置类型的设置：C/C++ 的 `//`、`/* */`、`#if 0`～`#endif`，SQL 的 `--`，Pascal 的 `{ }`、`(* *)` 等；テキスト不给引号、数字着色 | 相同（原版的 `types/CType_*.cpp`） |
| 「文字列は行内のみ」「文字列は行末まで」、转义（`\"`）、メールアドレス | 相同 |
| 颜色、太字、下線（类型别设置「カラー」页），背景色与文字的背景色相同时透過 | 相同 |
| 検索文字列的颜色比语法颜色优先，选择范围叠在上面（30% 混合） | 相同 |
| 所有色分け都不显示的设置时跳过判断（`IsSkipBeforeLayout`） | 相同 |
| sakura.ini 的类型别设置（`C[CMT]`、`RxKey[000]` 等） | 相同的格式，读写都可以 |

## 和原版不同、或者现在还没有的

- **类型别设置的「カラー」页**（改颜色、开关色分け、正規表現キーワード的编辑）：在设置对话框的步骤做。现在可以直接改 sakura.ini（App 沙盒容器里的 `Library/Application Support/sakura/sakura.ini`，见[设置](phase1-env.md)）。
- **対括弧の強調**（光标旁边的括号）、**カーソル位置縦線**、**ノート線**、**DIFF 差分**、**ブックマーク**的颜色：在各自的步骤做（颜色的种类已经全部可以取得）。
- **ミニマップ**：原版的小地图在后面的步骤做。
- **Mac 版的实现方式**：原版一个进程只有一个文档，色分け从「现在的文档」取设置。Mac 版一个进程开多个文档，所以排版和取颜色之前先切到那个文档的设置（`macos/core/src/color_support.cpp`）。效果相同。

## 测试

自动测试（见[自动测试](testing.md)）：

- `macos/core/tests/test-mac-syntax-color.cpp`（核心库，12 个）：C/C++、テキスト和其他 14 种内置类型（HTML、SQL、COBOL、Java、アセンブラ、AWK、MS-DOS バッチ、Pascal、TeX、Perl、Python、Visual Basic、リッチテキスト、設定ファイル）逐字的颜色，「基本」在下面的 sakura.ini 测试里；插入 `/*` 后后面的行变成注释、撤销后复原；折り返し的行；多个不同类型的文档交替编辑；「名前を付けて保存」换扩展名后颜色跟着变；颜色的默认值；sakura.ini 的正規表現キーワード（包括行首 `^`）、ヒアドキュメント、全部不显示的设置。
- `macos/app/Tests/SyntaxColorTests.swift`（App）：每个字的颜色、テキスト类型、编辑后重新取得、検索文字列优先；把视图画到位图上，确认关键字是蓝、注释是绿、普通文字是黑、URL 有蓝色的下划线。
- `macos/app/UITests/SakuraMacUITests.swift`（界面）：实际的 App 里输入 URL，截取画面确认蓝色的像素增加。

需要在 Mac 上用眼睛看的只有一项：粗体的样子（默认设置里没有用粗体的语法颜色；粗体的设置能读到由单元测试确认，字形是否变粗由每 3～5 步一次的手动确认看）。

## 这一步改的文件

- 原版代码（Windows 版不变，Mac 专用的部分用 `#if !defined(_WIN32)` 区分）：`sakura_core/view/colors/CColorStrategy.h`、`CColorStrategy.cpp`、`CColor_Comment.h`、`CColor_Comment.cpp`、`CColor_Quote.cpp`、`CColor_Heredoc.cpp`、`CColor_Url.cpp`、`CColor_Numeric.cpp`、`CColor_KeywordSet.cpp`、`CColor_RegexKeyword.cpp`
- 新文件：`macos/core/src/color_support.h`、`macos/core/src/color_support.cpp`（色分け的对象文档）、`macos/core/tests/test-mac-syntax-color.cpp`、`macos/app/Tests/SyntaxColorTests.swift`、`macos/docs/phase2-syntax-color.md`（本文档）
- `macos/core/src/layout_support.cpp`：删掉第 27 步的空的 `CColorStrategyPool`
- `macos/core/include/sakura_core/SakuraCore.h`、`macos/core/api/SakuraCore.cpp`：`Document::SyntaxColors`、颜色种类加到 `PageView`
- `macos/bridge/include/EditorBridge.h`、`macos/bridge/src/EditorBridge.mm`：`syntaxColors(line:)`
- `macos/app/Sources/EditorTextView.swift`：按语法颜色画文字、粗体、下划线

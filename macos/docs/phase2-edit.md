# 阶段 2 第 29 步：基本编辑

**结论**：对照表里属于 MVP 的编辑命令都能用了：输入、删除、撤销重做、切り取り・コピー・貼り付け、矩形貼り付け、TAB 缩进和逆缩进。处理方式照原版：没有选择时「コピー」复制光标所在的一行，贴付时贴在行首；矩形选择复制的文字贴付时自动按矩形贴；矩形选择中输入文字时每行都插入；Enter 会接着上一行的缩进（オートインデント）。处理本身移植在核心库里（与原版 `CViewCommander`、`CEditView` 的同名处理相同），视图只负责选择范围、光标和剪贴板。

## 与原版的对应

| 原版（Windows） | Mac 版 |
| --- | --- |
| 文字输入（F_WCHAR）、输入法（F_IME_CHAR） | 相同。有选择时替换；矩形选择时每行插入 |
| 元に戻す / やり直し（Ctrl+Z / Ctrl+Y） | Cmd+Z / Shift+Cmd+Z。每个命令是撤销的一步（矩形删除、矩形贴付、多行缩进也是一步） |
| 削除（Delete）、カーソル前を削除（BackSpace） | Mac 的 fn+Delete 和 Delete（⌫）。有选择时删除选择范围，矩形选择时删除每行的矩形部分 |
| 切り取り / コピー / 貼り付け（Ctrl+X / C / V） | Cmd+X / C / V |
| 没有选择时コピー、切り取り：光标所在的一行（「選択なしでコピーを可能にする」，默认开） | 相同。贴付时贴在光标所在行的行首，光标留在原来的位置（「ラインモード貼り付け」，默认开） |
| 矩形选择的复制：每行后面加 CRLF，剪贴板里带「矩形」的标记（MSDEVColumnSelect） | 相同（Mac 剪贴板里带同样意思的标记）。贴付时自动按矩形贴付（「矩形コピーのテキストは常に矩形貼り付け」，默认开） |
| 矩形貼り付け（F_PASTEBOX） | 「編集」>「矩形貼り付け」：剪贴板的每行贴在同一横向位置，行短时用空白填到那个位置 |
| 矩形选择中输入：插在每行选择范围的前面，选择范围往右移（不删除选中的文字） | 相同。宽度 0 的矩形（Option+竖着拖动）就是在几行的同一位置同时输入 |
| TAB：多行选择时每行行首插入 TAB（F_INDENT_TAB），Shift+TAB 删除一个 TAB 或 TAB 幅以内的空白（F_UNINDENT_TAB） | 相同。空行不插入；之后整行被选中 |
| 矩形选择中按 TAB：每行插入 TAB；宽度 0 时先把右端扩展到最大 | 相同 |
| 类型别「スペースの挿入」：TAB 键插入到下一个 TAB 位置的空白 | 相同（默认关） |
| Enter：输入换行符，接着上一行开头的空白（「オートインデント」，默认开；「日本語空白もインデント」默认开） | 相同 |
| 「改行コードを変換して貼り付ける」「コピーしたら選択解除」「折り返し行に改行を付けてコピー」 | 相同（默认都关），在第 39 步的共通设置窗口里可以改 |

菜单：「編集」里按原版 MainMenu.ini 的顺序加了「切り取り」「コピー」「貼り付け」「削除」、「矩形貼り付け」「カーソル前を削除」、子菜单「高度な操作」里的「TABインデント」「逆TABインデント」。这些新加的文字写成了可以翻译的形式（`NSLocalizedString`），第 48 步加中文、英文时直接用。

## 和原版不同、或者现在还没有的

- 没有选择时按 Shift+TAB：原版当作 TAB 输入，并在状态栏提示「逆インデントは選択時のみ有効です」。Mac 版也当作 TAB 输入；Mac 版还没有状态栏，做状态栏时再加这个提示。
- 上書きモード（Insert 键，F_CHGMOD_INS）：第 34 步和按键分配一起做。现在一直是插入模式。
- C/C++ 的スマートインデント（`{` `}` 的自动缩进）、「改行時に末尾の空白を削除」（默认关）：第 33 步和类型别的语法处理一起做。
- 撤销、重做之后光标的位置还是简单的处理（留在原来的位置），以后照原版移植（原版移到被撤销的地方）。
- 原版的「矩形貼り付け」只在等宽字体时能用；Mac 版的排版本来就按半角宽度的桁对齐，所以一直能用。
- 剪贴板里 NUL 字符（原版的 SAKURAClipW 形式）：现在不支持，以后需要时再加。

## 请你确认

在终端里逐条运行：

```sh
cd /Users/shenzhe/sakura-mac/sakura-mac
git checkout macos
git pull
git submodule update --init externals/Onigmo externals/bregonig externals/cmigemo
cd macos/app
xcodegen generate
open SakuraMac.xcodeproj
```

Xcode 打开后按 Cmd+R 运行，然后试：

1. 输入几行文字，选中一部分，Cmd+C、Cmd+V；Cmd+X 剪切。然后 Cmd+Z 撤销。
2. 什么也不选，在第 2 行按 Cmd+C，再把光标放到第 1 行中间按 Cmd+V：第 2 行整行贴到第 1 行的上面。
3. 按住 Option 拖出一个矩形，Cmd+C；把光标放到别处 Cmd+V：按矩形贴进去。
4. 按住 Option 从第 1 行竖着拖到第 3 行（不往右拖），然后输入文字：3 行同时输入。
5. 选中几行按 TAB：每行前面加了 TAB；Shift+TAB 去掉。
6. 在行首按 TAB 后输入文字，再按 Enter：新的一行也以 TAB 开头。
7. 从别的 App（例如备忘录）复制文字，在这里贴付；在这里复制的文字也能贴到别的 App。

## 测试

`macos/core/tests/test-mac-edit.cpp`（核心库，19 个）：默认设置、复制用的文字（换行符、折り返し）、矩形的复制・删除・贴付・输入、行末之后插入时填空白、TAB 和 SPACE 的矩形缩进、多行缩进和逆缩进、「スペースの挿入」、オートインデント（包括「その他のインデント対象文字」）、换行符的转换、行删除。每个处理都确认可以一步撤销。

`macos/app/Tests/EditorEditTests.swift`（App，10 个）：选择范围的复制・贴付・剪切、没有选择时的一行复制和行首贴付、矩形的复制・贴付・矩形貼り付け・剪切・删除、矩形选择中的输入（包括输入法）、多行和矩形的 TAB、Enter 的オートインデント、菜单的可用状态。剪贴板用测试专用的，不碰你自己的剪贴板。

以前的测试照旧通过。

## 文件

新建：

- `macos/core/tests/test-mac-edit.cpp`：核心库的编辑测试
- `macos/app/Tests/EditorEditTests.swift`：App 的编辑测试
- `macos/docs/phase2-edit.md`：本文档

修改：

- `macos/core/include/sakura_core/SakuraCore.h`、`macos/core/api/SakuraCore.cpp`：编辑命令的接口（矩形、缩进、复制用的文字、オートインデント等）
- `macos/core/tests/tests.cmake`、`macos/core/tests/core-api-link-check.cpp`：测试
- `macos/bridge/include/EditorBridge.h`、`macos/bridge/src/EditorBridge.mm`：桥接层
- `macos/app/Sources/EditorTextView.swift`：剪贴板、删除、TAB、Enter、矩形选择的编辑
- `macos/app/Sources/MainMenuBuilder.swift`：「編集」菜单
- `macos/docs/phase2-drawing.md`：去掉“第 29 步再做”的说明
- `macos/README.md`：链接本文档

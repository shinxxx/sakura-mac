# 阶段 2 第 27 步：排版

**结论**：原版的排版代码（`sakura_core/doc/layout/` 的 `CLayoutMgr`）原样编进了 Mac 版的核心库，自动换行、制表符、全角空格和换行符的记号、行号都按它的结果显示。文字宽度用 Core Text 测，换算成「桁」的规则与原版相同（半角宽度 = 英文字母平均宽度，比半角宽的字算 2 桁），所以同一个文件、同样的折り返し桁数，换行位置与 Windows 版一致。第 20 步留下的 `LogicToLayout` 占位已经换成真的。核心库新增测试 18 个（合计 975 个），App 新增测试若干，全部通过。

## 与原版的对应

| 原版（Windows） | Mac 版 |
| --- | --- |
| `CLayoutMgr`（折り返し、TAB 展开、禁則、ぶら下げ、英文ワードラップ） | 同一份代码，没有改逻辑 |
| 文字宽度：GDI 的 `GetTextExtentPoint32`（`CCharWidthCache`） | Core Text 测宽度，接到同一个 `CCharWidthCache` |
| 「折り返し方法」：折り返さない／指定桁で折り返す／右端で折り返す | 「設定」菜单 >「折り返し方法」，现在的方法打勾 |
| 打开文件时回到类型别设置的折り返し方法（`CLoadAgent::OnAfterLoad`） | 相同 |
| 行号：宽度 = 位数 + 2，右对齐，右边一条竖线；改行単位时折り返した行没有行号 | 相同 |
| TAB 记号（文字／短い矢印／長い矢印）、全角空格 □、半角空格、改行記号、折り返し記号「<」、[EOF] | 相同的形状和位置，开关跟类型别设置 |
| 光标上下移动、Home／End 按排版行 | 相同 |

## 原版代码的修改

都用 `#if defined(_WIN32)` 隔开，Windows 版不受影响：

- `CLayoutMgr.h`：Mac 版还没有 `CEditDoc`，现在的折り返し方法暂时放在 `CLayoutMgr` 里（`m_nTextWrapMethodCurMac`）。
- `CLayoutMgr.cpp`：半角宽度的测量不用 GDI 的 DC，改用平台的测宽函数。
- `CLayoutMgr_DoLayout.cpp`：不引用 `CEditView.h`，折り返し方法从上面的成员读。

## 暂时的替代（`macos/core/src/layout_support.cpp`）

- 色分け（`CColorStrategyPool`）：排版时只问「这里是不是注释、字符串」，现在一律回答「不是」。第 33 步移植色分け后删掉。
- `DpiScaleX`／`DpiScaleY`：Mac 的坐标已经是点，不需要换算。
- `BlockingHook`：原版排版大文件时处理窗口消息，Mac 版不需要。

## 现在还没有的

- 文字颜色、背景颜色、深色模式，字体的选择（第 28 步）。现在字体固定为 Menlo 13 点。
- 注释、字符串里的禁則和ぶら下げ的区别（第 33 步，色分け）。
- 类型别设置窗口里改折り返し桁数等（第 40 步左右）。现在用的是默认值：「基本」不折り返す，可以在菜单里临时切换。

## 请你确认（可选）

在终端里逐条运行（第一次构建要几分钟）：

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

1. 左边有行号。输入几行文字，行号跟着增加。
2. 输入一个很长的行，然后选「設定」>「折り返し方法」>「右端で折り返す」：长行在窗口右边折返；拉宽或拉窄窗口，折返的位置跟着变。
3. 打开一个有长行的 .txt 文件，选「指定桁で折り返す」：在第 120 桁折返（「テキスト」类型的默认值；新建文档是「基本」类型，默认 10240 桁，基本看不出折返）。选「折り返さない」：不折返，可以横向滚动。
4. 输入 TAB 键、全角空格（日文输入法的空格）、换行：能看到 TAB 的箭头、全角空格的 □、行末的换行记号，最后一行后面有 [EOF]。
5. 在折返的行上按 ↑↓，光标一个排版行一个排版行地移动；按 End 到这一段的末尾，不会跳到下一行。

## 测试

`macos/core/tests/test-mac-layout.cpp` 的 18 个测试（核心库）：

- 折り返し桁数、全角字、正好占满一行时的换行符、改行文字をぶら下げる。
- TAB 的展开和折返、补充平面字符（𠮟）。
- 英文ワードラップ、行頭禁則、行末禁則、句読点ぶら下げ。
- 折り返さない、右端で折り返す的桁数、位置的换算。
- 编辑后的排版（插入、删除、撤销、重做）与全部重新排版的结果相同。
- 重新打开文件时回到类型别设置。

`macos/app/Tests/EditorLayoutTests.swift`（App）：Core Text 的宽度、桥接层的排版、视图的行、折返行里的上下移动和 Home／End、点击、输入法候选窗口的位置、折り返し方法菜单、窗口大小改变时的折返。

以前的测试照旧通过。

## 文件

新建：

- `macos/core/src/layout_support.cpp`：排版用到的暂时替代
- `macos/core/tests/test-mac-layout.cpp`：核心库的排版测试
- `macos/app/Tests/EditorLayoutTests.swift`：App 的排版测试
- `macos/docs/phase2-layout.md`：本文档

删除：

- `macos/core/src/layout_stub.cpp`：第 20 步的 `LogicToLayout` 占位

修改：

- `sakura_core/doc/layout/CLayoutMgr.h`、`CLayoutMgr.cpp`、`CLayoutMgr_DoLayout.cpp`：见上
- `macos/core/CMakeLists.txt`、`macos/core/tests/tests.cmake`：编进 `doc/layout` 和测试
- `macos/core/include/sakura_core/SakuraCore.h`、`macos/core/api/SakuraCore.cpp`：排版的接口
- `macos/core/tests/core-api-link-check.cpp`：链接检查加上排版
- `macos/bridge/include/EditorBridge.h`、`macos/bridge/src/EditorBridge.mm`：桥接层，Core Text 测宽度
- `macos/app/Sources/EditorTextView.swift`：按排版显示、记号、行号、光标移动
- `macos/app/Sources/MainMenuBuilder.swift`：「設定」>「折り返し方法」
- `macos/app/Sources/AppDelegate.swift`、`macos/app/Tests/TestCore.swift`：启动时设置测宽函数和字体
- `macos/app/project.yml`：链接 CoreText
- `macos/README.md`：文档链接

# 阶段 2 第 28 步：绘制、颜色、选择

**结论**：编辑区按类型别设置的颜色绘制，默认颜色与原版相同（米色背景、蓝色行号、灰色的 TAB 记号、蓝色的换行记号、紫色的折り返し記号等）。深色模式按你选的方案处理：**编辑区照原版用设置里的颜色**，菜单、标题栏、滚动条跟随系统。光标会闪烁，输入法打开时变成红色（原版的「IMEキャレット」）。光标所在行下面有蓝色的下划线（原版的「カーソル行アンダーライン」）。可以用 Shift+方向键、拖动、Shift+点击选择，用 Option+拖动做矩形选择；选择范围的颜色按原版的规则混合。「設定」菜单里可以改字体。

## 与原版的对应

| 原版（Windows） | Mac 版 |
| --- | --- |
| 类型别设置「カラー」页的颜色（`ColorInfo`），默认值在 `CDocTypeSetting.cpp` | 同一份设置，核心库提供给视图（`Document::GetColor`） |
| 选择范围的颜色：文字色和背景色相同时按 30% 半透明叠上去（`GetTextColorByColorInfo2`） | 相同的计算 |
| 行号：「行番号」的颜色，修改过的行用「行番号（変更行）」（粗体） | 相同（`Document::IsLineModified`，撤销回到保存时的内容后恢复） |
| 行号区域右边的竖线：行号的文字色 | 相同 |
| [EOF]：浅蓝字、黑底 | 相同 |
| 光标：「キャレット」的颜色，输入法打开时「IMEキャレット」 | 相同；闪烁的速度按 macOS 的设置 |
| 「カーソル行アンダーライン」「カーソル行背景色」「奇数行の背景色」「カーソル位置縦線」 | 相同（后三个默认关闭，与原版一样） |
| Shift+移动、拖动选择、Shift+点击 | 相同 |
| 矩形选择：Alt+拖动 | **Option+拖动**（Mac 上 Option 相当于 Alt） |
| 有选择时输入：替换选择范围 | 相同 |
| すべて選択（Ctrl+A） | 「編集」>「すべて選択」（Cmd+A） |
| フォント設定（共通设置的字体） | 「設定」>「フォント設定…」打开 macOS 的字体面板，所有窗口一起重新排版 |
| 深色模式：编辑区按设置的颜色，窗口外框跟随系统 | 相同（你选的方案） |

默认字体：原版是「ＭＳ ゴシック」10 点，Mac 版用系统自带的等宽字体 Menlo 13 点（大小相近）。日文 Menlo 里没有，由系统换成其他字体显示，宽度按全角 2 桁排，所以对齐不乱。

## 现在还没有的

- 语法颜色（注释、字符串、关键字等）：第 33 步。
- 复制、剪切、粘贴，矩形选择的编辑（每行插入、删除）：第 29 步已经做了（见[基本编辑](phase2-edit.md)）。
- 键盘的矩形选择（原版 Alt+Shift+方向键）、双击选择单词：第 34 步（菜单与快捷键）。
- ルーラー（编辑区上面的刻度尺，原版默认显示）：打算在第 34 步和「ルーラー表示」菜单一起做。
- 指定桁縦線、ノート線（原版默认不显示）：以后和类型别设置窗口一起做。
- 字体设置现在暂时存在 macOS 的偏好里，第 39 步做共通设置窗口时改成原版的设置文件。颜色的修改在第 40 步（类型别设置窗口）。

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

1. 编辑区是米色的背景，行号是蓝色，光标所在行下面有一条蓝线。把 Mac 切到深色模式（系统设置 > 外观），编辑区不变，菜单和标题栏变深。
2. 输入几行文字，按住 Shift 按方向键，或者用鼠标拖动：选中的部分变成浅蓝色。这时输入文字，选中的部分被替换。
3. 按住 Option 拖动：出现矩形的选择范围。
4. Cmd+A 全部选择；按 Esc 取消。
5. 切换到日文输入法，光标变成红色。
6. 「設定」>「フォント設定…」，在字体面板里改大小，文字和行高跟着变。

## 测试

`macos/core/tests/test-mac-view.cpp`（核心库，3 个）：默认颜色与原版相同；编辑过的行、撤销后、打开和保存后的「変更行」。

`macos/app/Tests/EditorDrawingTests.swift`（App）：默认颜色、浅色和深色模式下编辑区的颜色、选择范围颜色的混合、画出来的颜色（背景、行号、选择范围）、Shift+方向键、有选择时输入、すべて選択和 Esc、鼠标的拖动和 Shift+点击和 Option+拖动、改字体后重新排版。

以前的测试照旧通过。

## 文件

新建：

- `macos/core/tests/test-mac-view.cpp`：核心库的颜色测试
- `macos/app/Tests/EditorDrawingTests.swift`：App 的绘制、选择测试
- `macos/docs/phase2-drawing.md`：本文档

修改：

- `macos/core/include/sakura_core/SakuraCore.h`、`macos/core/api/SakuraCore.cpp`：颜色、変更行的接口
- `macos/core/tests/tests.cmake`、`macos/core/tests/core-api-link-check.cpp`：测试
- `macos/bridge/include/EditorBridge.h`、`macos/bridge/src/EditorBridge.mm`：桥接层
- `macos/app/Sources/EditorTextView.swift`：按颜色绘制、光标、选择、字体
- `macos/app/Sources/MainMenuBuilder.swift`：「すべて選択」「フォント設定…」
- `macos/app/Tests/TestCore.swift`：测试用默认字体
- `macos/README.md`：文档链接

原版 `sakura_core` 的文件这一步没有修改。

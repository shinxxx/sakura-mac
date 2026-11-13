# 阶段 2 第 26 步：窗口框架

**结论**：编辑窗口改由 AppKit 的文档框架（`NSDocument`）管理。一个文件一个窗口，所有窗口都在同一个进程里。能同时打开多个文件，用「ウィンドウ」菜单、Cmd+\`、窗口标签切换。同一个文件不会被打开两次。修改过的文件关闭时会问是否保存，也可以「上書き保存」和「名前を付けて保存」。自动测试 6 个全部通过（合计 24 个）。

## 与原版的对应

| 原版（Windows） | Mac 版 |
| --- | --- |
| 一个编辑窗口一个进程（`CNormalProcess`），由控制进程（`CControlProcess`）管理共通设置 | 一个进程。共通设置由核心库在启动时读入（第 24 步），所有窗口共用 |
| 编辑窗口 `CEditWnd` | `EditorWindowController`（一个文件一个） |
| 文档 `CEditDoc` | `SakuraDocument`（`NSDocument` 的子类），内容在核心库的文档里 |
| 已经打开的文件再打开时，切换到那个窗口 | 相同（`NSDocumentController` 处理） |
| 标题「ファイル名 (更新)」、无题时「(無題)」 | 相同。副标题显示编码 |
| 关闭修改过的文件时询问是否保存 | 相同（macOS 标准的对话框） |
| 「タブまとめ表示」 | macOS 的窗口标签。默认按系统设置（「打开文稿时首选标签页」），在「ウィンドウ」菜单里可以合并全部窗口、显示标签栏 |
| 「次のウィンドウ」「前のウィンドウ」 | 「ウィンドウ」菜单里，按打开的顺序切换（标签也算一个窗口） |
| 最后一个窗口关闭后，控制进程留在任务托盘 | 最后一个窗口关闭时 App 退出（第 9 步已确认的偏离项） |

## 这一步加进来的功能

- **新建**（Cmd+N）、**打开**（Cmd+O，可以多选）：打开对话框、Finder 的「打开方式」、拖到 Dock 图标都走同一个处理。Finder 的「打开方式」里会列出这个 App，但不会抢走默认的打开程序。
- **保存**：「上書き保存」（Cmd+S）、「名前を付けて保存」（Shift+Cmd+S）。用核心库直接写进目标文件（与原版相同，不经过临时文件），沿用打开时的编码和 BOM。保存对话框里选编码、换行符在第 30 步加入。原版没有自动保存到原文件和版本浏览，这里也关掉了。
- **修改标记**：是否修改以核心库为准，撤销回到保存时的内容就不算修改（与原版相同），标题的「(更新)」和关闭按钮上的圆点一起变。
- **窗口标签**：所有编辑窗口可以合并成标签，标签之间可以切换和拖开。

## 两处宽字符用法的处理

阶段 1 的字符类型方案（`phase1-char-type.md`）里，有两处 `char16_t` 用不了的标准库写法留到这一步：

- `_main/CCommandLine.cpp`（`std::wregex`）：解析启动参数（文件名、`-R`、`-CODE=` 等）。Mac 的 App 由 Finder、Dock、`open` 命令用 Apple Event 打开文件，不经过这个命令行，所以 **Mac 版不编译这个文件**。以后如果要做命令行工具（例如在终端里 `sakura 文件名`），再用 Onigmo 改写这一处。
- `util/window.cpp`（`std::wostringstream`）：整个文件是 Win32 窗口和对话框的辅助函数（字体、DPI、对话框控件），Mac 版的窗口用 AppKit，**不编译**。

两个文件都没有修改，Windows 版不受影响。

## 现在还没有的

- 原版的设置「タブまとめ表示」等还没有接到 macOS 的标签上（第 39 步，共通设置窗口）。
- 「最近使ったファイル」菜单、重启后的权限保留（第 31 步，沙盒文件访问）。
- 保存时选编码、换行符，SJIS 表示不了的字符的警告（第 30 步）。
- 原版的 Grep 结果窗口、大纲窗口等辅助窗口（阶段 3）。

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

1. Cmd+O 打开两三个文件（可以在对话框里按住 Cmd 多选），每个文件一个窗口，标题是文件名。
2. 「ウィンドウ」菜单里有打开的窗口一览，点一下就切换；「次のウィンドウ」「前のウィンドウ」也能切换。
3. 「ウィンドウ」菜单里选「すべてのウインドウを結合」（macOS 自动加的项目），窗口变成标签。
4. 在一个窗口里输入几个字，标题出现「(更新)」；Cmd+W 关闭时问是否保存。
5. 再打开一次已经打开的文件，不会多出一个窗口，而是切换到原来的窗口。

## 测试

`macos/app/Tests/SakuraDocumentTests.swift` 的 6 个测试：

- **同时打开多个文件并切换**（完成标志）：两个文件各自一个窗口，标题是文件名，类型按扩展名；切换到哪个窗口，输入就进哪个文件。
- 窗口合并成标签，标签之间切换。
- 修改后标题加「(更新)」，撤销后去掉，关闭按钮的标记一起变。
- 新建的文档是「(無題)」；另存为、覆盖保存的字节正确，按扩展名换类型。
- SJIS 的文件保存后还是 SJIS，字节不变。
- 打开不存在的文件报错。

以前的 18 个测试（桥接层、输入法）照旧通过。

## 文件

新建：

- `macos/app/Sources/SakuraDocument.swift`：文档（`NSDocument`）
- `macos/app/Tests/SakuraDocumentTests.swift`：测试
- `macos/docs/phase2-windows.md`：本文档

修改：

- `macos/app/Sources/EditorWindowController.swift`：由文档管理，窗口标签、标题
- `macos/app/Sources/AppDelegate.swift`：启动顺序（在打开文件之前启动核心库），次／前のウィンドウ
- `macos/app/Sources/MainMenuBuilder.swift`：新規作成、開く、上書き保存、名前を付けて保存、次／前のウィンドウ
- `macos/app/Config/Info.plist`：文档类型（任何文件都能打开）
- `macos/app/project.yml`：测试编入文档和窗口的源文件
- `macos/docs/phase1-char-type.md`：两处宽字符用法的结论
- `macos/README.md`：文档链接

原版 `sakura_core` 的文件和核心库这一步没有修改。

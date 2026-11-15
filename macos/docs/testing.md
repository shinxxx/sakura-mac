# 自动测试

2026-11-15 起，每一步都用自动测试确认，不再每一步都在 Mac 上手动确认：

- **逻辑的步骤**（编码、排版、编辑命令等）：单元测试全部通过就算完成。
- **每 3～5 步**项目负责人在 Mac 上集中手动确认一次（看画面、手感这类测试看不出来的地方）。
- 每一步的测试由 Claude 通过 Remote Control 在项目负责人的 Mac 上运行 `macos/tools/run-tests.sh`，只报告结果和失败时的截图。

## 三层测试

| 测试 | 位置 | 确认什么 | 在哪里运行 |
|---|---|---|---|
| 核心库测试（C++、GoogleTest） | `macos/core/tests/` | 原版代码在 Mac 上的行为：编码转换、排版、编辑命令 | CI（`core-tests-macos`）、本机 |
| App 单元测试（Swift、XCTest） | `macos/app/Tests/` | 桥接层、编辑区视图、文档的读写（不显示窗口，直接调用） | CI（`build` 的 `Test bridge`）、本机 |
| 界面测试（XCUITest） | `macos/app/UITests/` | 真的启动 App，用键盘和菜单操作一遍主要功能 | CI（`build` 的 `UI tests`）、本机 |

界面测试只走用户实际的操作路线，细节（各种边界情况）由前两层确认。
鼠标拖动的矩形选择这类坐标容易变的操作不放在界面测试里，由 App 单元测试确认。

## 在 Mac 上运行

```sh
cd /Users/shenzhe/sakura-mac/sakura-mac
git checkout macos
git pull
macos/tools/run-tests.sh            # 全部
macos/tools/run-tests.sh --no-ui    # 不跑界面测试
```

需要 Xcode、CMake、XcodeGen（`brew install xcodegen cmake`）。不需要开发者账号：测试用本机签名（ad-hoc）。
界面测试运行时会真的打开窗口、操作键盘，这期间不要动鼠标和键盘。
第一次运行界面测试时，macOS 可能要求允许 Xcode 控制电脑（「辅助功能」或「自动化」），点允许即可。

结果放在 `macos/app/build/test-results/<时间>/`：

- `summary.txt`：结果摘要（屏幕上打印的内容）
- `app.xcresult`：Xcode 的完整结果，双击用 Xcode 打开
- `failures/`：失败的界面测试当时的截图
- `*.log`：各阶段的完整日志

全部通过时脚本返回 0，有失败时返回 1。

## 界面测试模式

界面测试用 `-SakuraUITesting YES` 启动 App（`macos/app/Sources/UITesting.swift`），这时：

- 设置文件放在临时目录，退出时不保存设置，不影响自己平时用的设置；
- 复制、粘贴用测试专用的剪贴板，不影响系统剪贴板；
- 编辑区只用英文输入，不被中文、日文输入法影响。

编辑区把全部文字作为辅助功能的值（`accessibilityValue`）公开，标识是 `editor`，测试用 `app.textViews["editor"].value` 读出文字来比较。

## 加测试

- 每一步加新功能时，在对应的层加测试；界面测试只加用户会走的主要操作。
- 核心库加了测试文件后要重新运行 `cmake -S macos/core -B build/mac-core`。
- App 的测试文件放进 `Tests/` 或 `UITests/` 后重新运行 `xcodegen generate`。

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
`xcode-select` 指向 Command Line Tools 时，脚本自动改用 `/Applications` 里的 Xcode（只在这次运行里，不改系统设置）。
界面测试运行时会真的打开窗口、操作键盘，这期间不要动鼠标和键盘。
App 编完后还确认 App、桥接层框架、核心库只含 arm64（`macos/tools/check-arch.sh`，Mac 版只支持 Apple 芯片；结果里的「架构：只含 arm64」）。

`testSandboxedFileReopensFromRecentFilesAfterRestart`（第 31 步）只在 run-tests.sh 里运行（CI 上跳过）：
为界面测试编译的 App 被 Xcode 加了「整个磁盘可以读」的沙盒例外（`temporary-exception.files.absolute-path.read-only = /`），
所以 run-tests.sh 复制一份 App 到 `macos/app/build/sandbox-test/`，去掉这个例外、换一个 bundle ID 重新签名，测试用这一份。
它在测试程序自己的容器（测试程序也在沙盒里）的 `SakuraMacUITest/` 放一个文件（对 App 来说是沙盒外），先确认不经过对话框打不开（App 真的在沙盒里），
再用「開く」对话框选它打开，退出重开后从「最近使ったファイル」打开，确认安全书签有效。测试完删掉文件。
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

## 性能测试（第 36 步）

- 核心库的 `MacPerfTest.*`、App 的 `PerformanceTests` 在普通的测试里一起运行（Debug，上限定得宽，只防止明显变慢）。
- CI 的 `core-perf-macos` 用 Release 构建量核心库的时间，`perf-windows` 在 Windows 上用官方版的宏量同样的操作，
  两边的时间写在各自 job 的 Summary 里。详见 [phase2-performance.md](phase2-performance.md)。

## 共通設定窗口（第 39 步）

- App 的 `CommonSettingsTests` 大多用假的设置（没写过的项从核心库读，写的值留在测试里），不改测试进程的设置；`testOKAppliesToCore` 用真的核心库，结束时改回去。
- 确认对话框、文件夹的选择换成测试用的、字体的选择、「ウィンドウの位置と大きさ」对话框换成测试用的（`CommonSettingsPages.confirm`、`inform`、`chooseFolder`、`chooseFont`、`runWinSizeDialog`），不出模态窗口。详见 [phase3-common-settings.md](phase3-common-settings.md)。

## タイプ別設定窗口（第 40 步）

- App 的 `TypeSettingsTests` 与共通設定相同，大多用假的设置（`CommonSettingsTests.FakeStore`，节是 `Types(N)`）；
  `testOKAppliesToCoreAndOpenEditors` 用真的核心库，结束时改回去。
- 文件的选择、编辑画面的字体、颜色的选择、文字色統一・強調キーワード 的对话框、消息换成测试用的（`TypeSettingsPages.chooseFile`、`editorFont`、
  `chooseColor`、`runSameColorDialog`、`runKeywordSelectDialog`、`chooseImportFile`、`chooseExportFile`、`showMessage`），不出模态窗口。详见 [phase3-type-settings.md](phase3-type-settings.md)。

## キー割り当て・メニュー的设置（第 41 步）

- App 的 `KeyBindTests`、`MainMenuSettingsTests`、`CustomMenuToolbarTests` 与共通設定相同，大多用假的设置（节是 `KeyBind`、`MainMenu`、`CustMenu`、`Toolbar`）；`testOKAppliesToCore` 用真的核心库，结束时改回去。
- 文件的选择、消息换成测试用的（`TypeSettingsPages.chooseImportFile`、`chooseExportFile`、`showMessage`）。详见 [phase3-command-settings.md](phase3-command-settings.md)。
- 设置窗口的外观：`PropLayoutTests` 确认所有设置页和对话框里没有被截断的文字、字号没有缩小、控件不重叠。

## 编辑辅助功能（第 44 步）

- 核心库 `test-mac-edit-support.cpp` 的 `*WindowsComparison` 把结果写成文字，与 `data/editsupport/expected/` 比较；CI 的 `edit-support-windows`
  在 Windows 上用官方版 sakura.exe 的宏和 GNU diff 做同样的操作，与同一个 `expected/` 比较。`SAKURA_EDITSUPPORT_UPDATE=1` 时写出 `expected/`（改了样本以后）。
- 差分的样本由 `macos/tools/editsupport/make_diff_samples.py` 生成。
- App 的 `ISearchTests.testMigemo` 用仓库里的测试用词典（`externals/cmigemo-dict` 的 zip，App 不附带）。
- 对话框（DIFF差分表示、ファイル内容比較、タグジャンプ一覧）、ファイル的选择换成测试用的（`DiffDialogController.runModal`・`chooseFile`、
  `CompareDialogController.runModal`、`TagJumpListDialogController.runModal`），比较的对象窗口换成测试用的（`EditingDocument.all`）。

## マクロ（第 45 步）

- 核心库 `test-mac-macro.cpp`：関数表、キーマクロ（.mac）の読み書き（原版の書式、エスケープ、読み込みエラーのメッセージ）、ExpandParameter、Cookie、JScript の前処理。
- App 的 `KeyMacroTests`：記録（入力・矢印キー等の選択子・キー割り当て・ダイアログ）→ RecKey.mac → 実行（一つの取り消し単位）、保存・読み込み、
  読み込みエラーのメッセージ、記録する引数（原版 AddLParam）、MacroHost の命令・関数。
  ファイルの選択・エラーとメッセージボックスは換えてある（`EditorTextView.chooseKeyMacroSaveURL`・`chooseKeyMacroOpenURL`、`MacroHost.showError`・`messageBox`・`inputBox`）。
  RecKey.mac はテストの設定フォルダー（マクロ用フォルダーの既定）に書いて、終わったら消す。
- 界面测试 `testKeyMacroRecordAndExecute`：メニューで記録開始 → 入力・矢印キー → 記録終了 → 実行 → 一回の ⌘Z で戻る。タイトルの【キーマクロの記録中】も確かめる。詳しくは [phase3-macro.md](phase3-macro.md)。

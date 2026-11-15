# 阶段 2 第 31 步：沙盒文件访问

**结论**：「ファイル」菜单里加了原版的「最近使ったファイル」「最近使ったフォルダー」。App Store 的 App 在沙盒里，重启后本来不能再读上次打开的文件；现在打开、保存成功时给文件建一个安全书签记下权限，重启后从「最近使ったファイル」选，直接就能打开，光标回到上次的位置。从 Finder 拖文件到编辑区也能打开。完成标志（重启后最近文件仍能直接打开）由界面测试确认：App 结束后再启动，从菜单打开，光标在上次的位置。

## 与原版的对应

| 原版（Windows） | Mac 版 |
| --- | --- |
| 历史存在 sakura.ini 的 [MRU]（`CMRUFile`、`CMRUFolder`），「ファイルの履歴MAX」个显示在菜单里 | 相同（原版的代码直接编进核心库） |
| 打开、保存后、关闭前登记到历史（`CMruListener`）；文件夹也登记 | 相同。App 结束时还开着的文件也登记 |
| 菜单的文字「&1 路径  [编码]」 | 相同，只是 macOS 菜单没有「&」快捷字母，去掉。鼠标停在项目上显示完整路径 |
| 历史是空的时「最近使ったファイル」变灰 | 相同 |
| 从历史打开：用上次的编码打开 | 相同 |
| 从「最近使ったフォルダー」：在那个文件夹打开「開く」对话框 | 相同 |
| 打开时恢复上次的光标位置和表示域（「カーソル位置を復元する」，默认开）；位置超过文件末尾时移到末尾 | 相同 |
| 编码与上次不同时问「前回と同じ文字コードを使いますか？」（「前回と異なる文字コードの時に問い合わせを行う」，默认开） | 相同（はい＝上次的编码，いいえ＝这次的编码） |
| 文件拖到编辑区打开 | 相同。一个文件一个窗口（已经打开的只是显示出来） |

## Mac 版另外做的：安全书签

沙盒里 App 只能读写用户在对话框里选的、拖进来的文件，App 结束后权限就没有了。原版的历史只有路径，Mac 版另外：

- 打开、保存成功后给这个文件建安全书签（security-scoped bookmark），存在 sakura.ini 旁边的 `bookmarks.plist`
- 从「最近使ったファイル」打开时用书签取回权限，文件关闭时还回去
- 只留历史里还有的文件的书签，不会越来越多
- 书签能跟着被移动的文件走（文件改名、移动后也找得到）

## 和原版不同、或者现在还没有的

- 「お気に入り」的标记、历史的管理对话框（「履歴の管理」）、「履歴をすべて削除」：与共通设置一起在阶段 3 做。
- 拖放的选项（Ctrl 拖放插入路径等）、拖放文字：与拖放编辑一起在后面的步骤做。
- 书签（ブックマーク，行的标记）跟历史一起保存：书签功能移植时一起做。
- macOS 自带的「最近使用的项目」（Dock 的右键菜单等）照常由系统管理，菜单里不另外放「最近使用」。

## 测试

自动测试（见[自动测试](testing.md)）：

- `macos/core/tests/test-mac-recent.cpp`（核心库，9 个）：登记、上次的编码和类型、询问、光标恢复、超过末尾、**核心库重启（Shutdown → Startup）后历史还在**。
- `macos/app/Tests/RecentFilesTests.swift`（App）：**书签存进文件、新的实例（相当于重启）读回来能打开**、移动后的文件也找得到、整理、打开时记下书签和历史、光标和表示域的恢复、编码的询问、菜单的内容和变灰、拖放。
- `macos/app/UITests/SakuraMacUITests.swift` 的 `testReopenFromRecentFilesAfterRestart`：**真的结束 App 再启动，从「最近使ったファイル」打开，光标在上次的位置**。

- 同一个文件里的 `testSandboxedFileReopensFromRecentFilesAfterRestart`（只在自己的 Mac 上用 run-tests.sh 运行）：**沙盒外的文件**用「開く」对话框选了打开，退出再启动后从「最近使ったファイル」还能打开。先确认不经过对话框打不开，证明 App 真的在沙盒里。文件放在 `~/SakuraMacUITest/` 而不是「文稿」：测试程序访问「文稿」时系统会弹出权限确认，测试会停住；对 App 来说两处都是沙盒外，书签的机制相同。

## 文件

新建：

- `macos/app/Sources/SecurityScopedBookmarks.swift`：安全书签
- `macos/app/Sources/RecentMenu.swift`：「最近使ったファイル」「最近使ったフォルダー」菜单
- `macos/app/Tests/RecentFilesTests.swift`：App 的测试
- `macos/core/tests/test-mac-recent.cpp`：核心库的测试
- `macos/docs/phase2-sandbox-files.md`：本文档

修改：

- `sakura_core/recent/CMRUFile.cpp/.h`、`CMRUFolder.cpp/.h`、`sakura_core/env/CFileNameManager.cpp`：Windows 专用的部分用 `#if defined(_WIN32)` 围起来（Windows 版不变）
- `macos/core/include/sakura_core/SakuraCore.h`、`macos/core/api/SakuraCore.cpp`、`macos/core/CMakeLists.txt`、测试的设置
- `macos/bridge/include/EditorBridge.h`、`macos/bridge/src/EditorBridge.mm`：桥接层
- `macos/app/Sources/SakuraDocument.swift`、`SakuraDocumentController.swift`、`EditorTextView.swift`、`MainMenuBuilder.swift`、`AppDelegate.swift`、`UITesting.swift`
- `macos/app/UITests/SakuraMacUITests.swift`、`macos/app/project.yml`

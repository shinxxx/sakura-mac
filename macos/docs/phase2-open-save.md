# 阶段 2 第 30 步：打开与保存

**结论**：打开、保存对话框下面加了原版的「文字コードセット」「CP」「BOM」「改行コード」，可以手动指定编码打开、换编码和换行符保存。保存前与原版一样检查：换行符混在时问要不要统一，有字符不能用这个编码表示时告诉你第几行第几桁的哪个字，问要不要继续。完成标志已经由自动测试确认：第 18 步的 80 多个样本文件在 App 里打开再保存，字节完全不变。

## 与原版的对应

| 原版（Windows） | Mac 版 |
| --- | --- |
| 打开对话框「文字コードセット」：自動選択、SJIS、JIS、EUC-JP、Latin1、UTF-16、UTF-16BE、UTF-8、CESU-8、UTF-7 | 相同（顺序、名字都相同）。选「自動選択」以外时用这个编码打开，不自动识别 |
| 「CP」：勾选后列表里追加 CP_ACP、CP_OEM 和系统的代码页（UTF-32 也在这里），之后不能取消 | 相同。代码页的列表是第 17 步从 Windows 导出的表 |
| 保存对话框：「文字コードセット」（没有自動選択）、「BOM」、「改行コード」（変換なし、CR+LF、LF (UNIX)、CR (Mac)） | 相同。一开始是文档现在的编码和 BOM，换行符「変換なし」 |
| BOM：能加 BOM 的编码（UTF-8、UTF-16 等）才能勾选；换成别的编码时 UTF-16 默认勾选、UTF-8 默认不勾选；换回原来的编码时回到原来的状态 | 相同 |
| 「改行コード」选了 CR+LF 等：保存前统一全部换行符（可以撤销），之后输入的换行符也换成这个 | 相同 |
| 保存前：换行符混在时「改行コードが混在しています。現在の入力改行コード … に統一しますか？」（类型别设置「保存時に改行コードの混在を警告する」，默认开） | 相同。はい＝统一后保存，いいえ＝照样保存，キャンセル＝不保存 |
| 保存前：有字符会丢失时「文字エンコード … で保存しようとしていますが…」，显示最初的位置（行、桁、那个字和代码） | 相同。はい＝继续保存，いいえ＝不保存，キャンセル＝不保存并把光标移到那个位置 |
| 保存、读入后有字符丢失：「一部の文字情報が、セーブ時（ロード時）の変換により失われました」 | 相同 |
| 上書き保存（Ctrl+S） | Cmd+S：用现在的编码、BOM，不转换换行符；保存前同样检查 |

对话框里的文字、消息都写成了可以翻译的形式（`NSLocalizedString`），第 48 步加中文、英文时直接用。原版的「&C」这类快捷字母 Mac 没有，去掉了。

## 和原版不同、或者现在还没有的

- 打开对话框的「読み取り専用」（ビューモード）、最近的文件和文件夹的下拉列表：与ビューモード一起移植（履歴的菜单第 31 步已经做了）。
- 「ファイル」>「開き直す」（换编码重新打开）：第 34 步菜单时加。现在已经打开的文件再从打开对话框指定编码打开，只会切换到那个窗口（macOS 的做法）。
- 从 Finder 打开时自动识别。从「最近使ったファイル」打开时用上次的编码：第 31 步已经做了（见[沙盒文件访问](phase2-sandbox-files.md)）。
- 代码页的 BOM：原版按 U+FEFF 能不能转换成这个代码页决定能否勾选 BOM，Mac 版相同，所以有的代码页也能勾选 BOM（与 Windows 版的表一致）。

## 测试

自动测试（2026-11-15 起每一步都用自动测试确认，见[自动测试](testing.md)）：

`macos/core/tests/test-mac-save.cpp`（核心库，11 个）：编码列表的顺序和名字、代码页的列表、BOM 能否勾选和默认值、换行符混在的检查（类型别设置关掉时不检查、指定换行符时不检查）、丢失字符的位置（普通编码、代码页、代理对）、**全部样本文件用核心库打开再保存字节不变**。

`macos/app/Tests/OpenSaveTests.swift`（App，9 个）：**全部样本文件在 App 里（SakuraDocument）打开再保存字节不变**（能自动识别的用「自動選択」，其他的指定编码）、指定编码打开、指定编码・BOM・换行符保存（之后的上書き保存沿用）、没有问题时保存前检查直接通过、对话框的编码列表・CP・BOM 的状态・换行符的选项。

保存前询问的对话框（换行符混在、丢失字符）需要人点按钮，没有放进自动测试，在集中手动确认时看。

## 文件

新建：

- `macos/app/Sources/FileDialogAccessory.swift`：打开、保存对话框下面追加的部分
- `macos/app/Sources/SakuraDocumentController.swift`：打开对话框加「文字コードセット」
- `macos/app/Tests/OpenSaveTests.swift`：App 的打开与保存测试
- `macos/core/tests/test-mac-save.cpp`：核心库的测试
- `macos/docs/phase2-open-save.md`：本文档

修改：

- `macos/core/include/sakura_core/SakuraCore.h`、`macos/core/api/SakuraCore.cpp`：编码列表、BOM、保存前的检查（`Document::CheckSave`，原版 `CCodeChecker` 的检查部分）
- `macos/core/tests/tests.cmake`、`macos/core/CMakeLists.txt`（注释）
- `macos/bridge/include/EditorBridge.h`、`macos/bridge/src/EditorBridge.mm`：桥接层
- `macos/app/Sources/SakuraDocument.swift`：指定编码打开、保存对话框、保存前的检查和消息
- `macos/app/Sources/main.swift`：使用 SakuraDocumentController
- `macos/app/project.yml`：测试里加入样本文件

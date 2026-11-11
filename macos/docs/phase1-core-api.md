# 阶段 1 第 22 步：整理核心库接口

**结论**：给核心库加了一个对外接口 `macos/core/include/sakura_core/SakuraCore.h`。界面层（第 24 步起的 Objective-C++ 桥接层和 Swift）只通过它使用核心库，可以打开、编辑、保存、查找和执行命令。这个头文件只引用 C++ 标准库的 5 个头文件（`<cstdint>`、`<memory>`、`<optional>`、`<string>`、`<vector>`），不引用 Windows 的头文件、平台抽象层和 `sakura_core` 的头文件。构建时有一个专门的目标确认这一点。Mac 核心库的全部 956 个测试通过（第 21 步是 937 个）。

## 接口的内容

| 分类 | 函数 | 对应的原版代码 |
| --- | --- | --- |
| 启动和结束 | `Startup`、`Shutdown`、`SettingsFilePath` | `CControlProcess` 的启动顺序（建立共通设置 → 读入 sakura.ini → 读不到时写出默认设置 → 刷新字符串）和结束时写出设置 |
| 打开 | `Document::Open` | `CReadManager`：按文件名选类型别设置，自动识别编码，决定 BOM，用 `CFileLoad` 逐行读入 |
| 保存 | `Document::SaveAs`、`Save` | `CWriteManager`：第一行前加 BOM，逐行转换编码；换行符的统一与 `CDocVisitor::SetAllEol` 相同（可以撤销） |
| 内容 | `LineCount`、`GetLine`、`GetLineEol`、`GetText`、`EndPosition` | `CDocLineMgr`、`CDocLine` |
| 编辑 | `Replace`、`Insert`、`Delete`、`BeginEdit`/`EndEdit` | `CEditView::ReplaceData_CEditView3` 的逻辑位置部分：`CSearchAgent::ReplaceData` 加上 `CReplaceOpe` 的记录 |
| 撤销 | `Undo`、`Redo`、`CanUndo`、`CanRedo`、`IsModified` | `CViewCommander::Command_UNDO`、`Command_REDO` 中 `OPE_REPLACE` 的处理，`COpeBuf` |
| 查找 | `Find`、`FindAll` | `CSearchAgent::SearchWord`、`CLineMatchFinder` |
| 全部替换 | `ReplaceAll` | `CViewCommander::Command_REPLACE_ALL` 的一括置换（整个文档；正则表达式按行用 `optGlobal` 替换） |
| 命令 | `ExecuteCommand`、`IsCommandEnabled`、`IsCommandSupported`、`CommandName` | `EFunctionCode` 的编号、`IsFuncEnable`、菜单里的功能名（`sakura_rc.rc`） |

设计上的约定：

- 文字一律是 UTF-16（`std::u16string`），与原版内部的宽字符相同，不用转换。
- 位置是逻辑位置：行号和行内的 UTF-16 下标，都从 0 开始（原版的 `CLogicPoint`）。自动换行后的排版位置在第 27 步之后另外提供。
- 编码、换行符、功能编号的数值与原版完全相同（`ECodeType`、`EEolType`、`EFunctionCode`）。实现文件里用 `static_assert` 逐个确认，所以 sakura.ini、按键分配、宏里的编号可以直接使用。
- 光标、选择范围、排版、绘制属于编辑画面，不在这一层，分别在第 27～30 步加入。

## 现在能执行的命令

`ExecuteCommand` 只能执行不需要编辑画面的命令：上書き保存（`F_FILESAVE`）、撤销（`F_UNDO`）、重做（`F_REDO`）、输入换行符的切换（`F_CHGMOD_EOL_*`，6 个）。

其余命令（光标移动、选择、剪贴板、各种转换等）在原版里由 `CViewCommander` 执行，需要编辑画面（`CEditView`、光标、排版）。这些命令对现在的接口返回 `NotSupported`，`IsCommandSupported` 返回 `false`。第 30 步（基本编辑）和第 35 步（菜单与快捷键）把 `CViewCommander` 移植过来后，再接到 `ExecuteCommand` 上，接口本身不用改。

## 与原版不同的地方

- **读入用一个线程**：原版 `CReadManager` 按 CPU 个数分段并行读入，并显示进度条。这里在一个线程里从头读到尾。第 18 步的往返测试确认过分段读入和一次读入的结果相同。`CReadManager` 本身（带进度显示）在第 29 步编入时换过去。
- **无修改的编辑不记入撤销**：`Replace` 的范围为空且文字也为空时，什么也不做，也不记入撤销缓冲。原版从界面上也不会产生这样的操作。

## 怎样确认“不引用平台头文件”

1. CMake 目标 `sakura_core_api_header_check` 编译 `macos/core/api/header_check.cpp`。它的包含路径只有 `macos/core/include`，找不到平台层、`sakura_core` 和 Windows SDK 替身的头文件，并且打开全部警告、把警告当作错误。这个文件还检查 `WCHAR`、`TRUE`、`MAX_PATH` 等 Win32 的宏没有被带进来，并且只用接口头文件写了一遍界面层要做的事（打开、编辑、查找、撤销、保存）。核心库接口 `sakura_core_api` 依赖这个目标，所以每次构建都会检查。
2. 测试 `CoreApiHeader.IncludesOnlyStandardHeaders` 逐行读取头文件，确认 `#include` 只有上面 5 个标准库头文件，也没有出现 `WCHAR`、`_WIN32`。

试着在头文件里加一行 `#include "StdAfx.h"`，构建在第 1 步就失败了，说明检查有效。

## 文件

新建：

- `macos/core/include/sakura_core/SakuraCore.h`：接口头文件
- `macos/core/api/SakuraCore.cpp`：接口的实现（静态库 `sakura_core_api`）
- `macos/core/api/header_check.cpp`：头文件独立性的编译检查
- `macos/core/tests/test-mac-core-api.cpp`：19 个测试
- `macos/docs/phase1-core-api.md`：本文档

修改：

- `macos/core/CMakeLists.txt`：加入 `sakura_core_api` 和 `sakura_core_api_header_check` 两个目标，测试程序链接 `sakura_core_api`
- `macos/core/tests/tests.cmake`：加入 `test-mac-core-api.cpp`
- `macos/README.md`：目录结构和文档链接

原版 `sakura_core` 的文件这一步没有修改。

## 测试

`macos/core/tests/test-mac-core-api.cpp` 的 19 个测试，只通过接口头文件使用核心库：

- **启动和结束**：没有 sakura.ini 时写出默认设置；结束时按参数写出或不写出；启动前不能建立文档。
- **编辑**：插入、跨行替换、删除换行符、文档末尾的位置；超出范围、指向换行符中间、反向的范围都被拒绝，内容不变。
- **撤销**：撤销到最初时修改标记清除；撤销后再编辑，重做的部分丢弃；随机做 200 次插入、删除、替换（包括 CR、LF、CRLF、日文、补充平面字符），逐个撤销能回到每一步的内容，再逐个重做也一致；`BeginEdit`/`EndEdit` 嵌套时合成一步。
- **打开、保存**：SJIS、UTF-8（带 BOM 和不带）、UTF-16LE、EUC-JP 自动识别正确，用 `F_FILESAVE` 覆盖保存后字节不变；指定编码打开；按扩展名选类型（`.cpp` 是 C/C++，另存为 `.txt` 后变成“テキスト”）；另存为 UTF-16BE 带 BOM 并统一成 LF，字节正确，统一换行符可以撤销；SJIS 表示不了的字符返回 `LostSome`；空文档带 BOM 保存时只有 BOM。
- **查找**：向前、向后、区分大小写、单词单位、正则表达式；包括换行符的匹配；正则表达式有错误时返回原因。
- **全部替换**：一次撤销恢复；替换后的文字含有查找的词也不会无限替换；替换成多行文字；正则表达式的 `$1`、行末 `$`。
- **命令**：功能名与原版菜单相同（「元に戻す」「やり直し」「上書き保存」）；编码名（SJIS、UTF-8、CP1252）；撤销、重做、输入换行符的命令和能否执行；编辑画面的命令（例如 `F_SELECTALL`）返回 `NotSupported`。
- **头文件**：只引用标准库头文件。

# 阶段 1 第 20 步：移植文档模型和语法类型

**结论**：文档的逻辑部分（`doc/logic` 的行管理、撤销缓冲 `cmd/COpe*`、差异和修改标记、大纲数据、文件读取 `io/CFile`、`io/CFileLoad`）和全部 17 种内置语法类型（`types`）编进了 Mac 版核心库。Mac 核心库的全部 837 个测试通过（第 19 步是 695 个），原版的 test-cdocline、test-cdoclinemgr、test-cfuncinfoarr、test-csearchagent、test-detectindentationstyle、test-docoutline 都在 Mac 上跑通。

## 编进核心库的部分

| 目录 / 文件 | 内容 |
| --- | --- |
| `doc/logic`（整个目录） | `CDocLine`、`CDocLineMgr`，逻辑行的存储 |
| `types`（除 `CTypeSupport.cpp`） | 各语言的类型定义和大纲解析 |
| `cmd/COpe`、`COpeBlk`、`COpeBuf` | 撤销 / 重做 |
| `doc/CBlockComment`、`CLineComment`、`CDocTypeSetting`、`CDocReader`、`CDocFile`、`CDocOutline`、`CDocListener` | 文档相关的逻辑类 |
| `outline/CFuncInfo`、`CFuncInfoArr` | 大纲数据 |
| `agent/CSearchAgent` | 文档内查找 |
| `docplus/CDiffManager`、`CModifyManager` | 差异标记、修改标记 |
| `io/CFile`、`CFileLoad` | 文件读取（编码判断、BOM、换行） |
| `_main/global.cpp`、`env/CKeyWordSetMgr.cpp`、`util/relation_tool.cpp`、`extmodule/CBregexp.cpp` 的 `InitRegexp` 和 `CheckRegexpSyntax` | 上面这些用到的公共部分 |

## 留到后面的

| 内容 | 步骤 |
| --- | --- |
| `doc/layout`（布局行）、大纲跳转用的 `CLayoutMgr::LogicToLayout` | 第 27 步 |
| `CEditDoc`、`CDocEditor`、`CDocFileOperation` 等窗口相关的类 | 第 26、29 步 |
| `CTypeSupport`、`CDiffManager` 的颜色和标记绘制 | 第 28、32 步 |
| `CSearchAgent` 的进度对话框 | 第 31 步 |
| `CType_Cpp` 的智能缩进（依赖 `CEditView`） | 第 26 步以后 |
| `DLLSHAREDATA`、`CheckEXT`、`InitFileTree` 的正式实现 | 第 21 步 |
| 文件共享模式（`FILE_SHARE_*`）：Mac 版目前忽略，改用 `NSFileCoordinator` 处理 | 第 29 步 |

## 平台层新增

| 文件 | 内容 |
| --- | --- |
| `macos/platform/src/file_api.cpp`（新） | 用 POSIX 实现 `CreateFileW`、`CloseHandle`、`GetFileSize`、`GetFileTime`、`CreateFileMappingW`、`MapViewOfFile`（mmap）、`UnmapViewOfFile` |
| `macos/platform/src/ole_types.cpp`（新） | `BSTR`（4 字节长度前缀）和 `SysAllocString` 等，`VARIANT` 的 `VariantInit`、`VariantClear`、`VariantCopy`、`VariantCopyInd` |
| `macos/platform/src/win32_api.cpp` | `VirtualAlloc`、`VirtualFree`（mmap）、`_waccess` |
| `macos/platform/src/ui_bridge.cpp` | `Wrap_MessageBox` |
| `macos/platform/include/sakura_platform.h` | 上面这些的声明；`LONGLONG` 等改成与 Windows 相同的 `long long`；MSVC 风格的 `_countof`；`PRINTDLG`、`LPDATAOBJECT` 的不透明类型；一些错误码和常量 |

## 原版代码的改动

都用 `#if defined(_WIN32)` 隔开，或者在 Windows 上行为不变：

| 文件 | 改动 |
| --- | --- |
| `util/wchar16.h` | 在 `SAKURA_WCHAR_IS_CHAR16` 部分（只在 Mac 生效）补上带缓冲区大小的 `wcsncpy_s` 等和数组版 `_snwprintf_s` |
| `util/window.h` | `apiwrap` 到 `GetSystemAccentColor` 只在 Windows 编译 |
| `types/CType_Cpp.cpp` | 智能缩进部分只在 Windows 编译 |
| `types/CType_Erlang.cpp` | `constexpr auto` 改为 `const auto`（clang 不接受成员数组的 constexpr） |
| `io/CFile.cpp`、`io/CFileLoad.cpp` | `CEditWnd` 的 include 只在 Windows；Mac 版警告框的父窗口为 `nullptr` |
| `io/CFileLoad.h` | `m_nReadOffset2`、`m_nTempResult` 加初始值（见下面“上游的 bug”） |
| `agent/CSearchAgent.cpp` | 进度对话框只在 Windows |
| `docplus/CDiffManager.cpp` | 绘制部分只在 Windows |
| `extmodule/CBregexp.cpp` | `InitRegexp`、`CheckRegexpSyntax` 在 Mac 上启用，只有 `CheckRegexpVersion` 还隔开 |
| `_main/global.cpp` | 进程和窗口相关部分只在 Windows |
| `env/CKeyWordSetMgr.cpp` | `wcscmp`、`wcsncmp` 的函数指针加类型转换（Mac 上有重载） |
| `parse/DetectIndentationStyle.cpp` | 不用 `path.wstring()`，直接传 path |
| 6 个原版测试 | 用 `macos/tools/convert_wchar.py` 转换 `L""` 字面量；`test-csearchagent.cpp` 在 Mac 上 include 临时的共享数据 |

## 测试

- `macos/core/tests/test-mac-doc.cpp`（新）：19 个测试。文件 API、`CFile`、`CFileLoad`（空文件、不存在的文件、日文路径、BOM、三种换行）、撤销 / 重做、差异和修改标记、17 种内置类型的名称和扩展名、`BSTR` / `VARIANT`。
- `macos/core/tests/test-mac-roundtrip.cpp`：读取改为走真正的 `CFileLoad`，并模仿 `CReadManager` 分 2、3、7 段读取。
- `macos/core/tests/mac-share-data.hpp`、`mac-share-data.cpp`（新，**临时**）：在第 21 步（env）之前代替 `DLLSHAREDATA`、`CheckEXT`、`InitFileTree`，`LogicToLayout` 是调用就失败的占位。第 21 步删掉。

## 上游的 bug（第 53 步之前告诉上游）

`CFileLoad` 用默认构造加 `Prepare` 分段读取 UTF-7 文件时，`m_nReadOffset2` 没有初始化，可能读错位置或崩溃。Mac 版在 `io/CFileLoad.h` 加了成员初始值修好了。Windows 版也受影响。

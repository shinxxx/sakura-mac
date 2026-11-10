# 阶段 1 第 21 步：改造设置模块 env

**结论**：设置模块 `env`（共通设置、类型别设置、sakura.ini 的读写）编进了 Mac 版核心库。设置数据不再放在进程间共享内存里，而是放在进程内的一块内存中，`DLLSHAREDATA` 的结构和 sakura.ini 的格式都不变。默认设置写出 → 读入 → 再写出，sakura.ini 逐字节相同；带有 Windows 版特有值（`C:\` 路径、Windows 字体名）的 ini 读入后再写出，也逐字节相同。Mac 核心库的全部 937 个测试通过（第 20 步是 837 个）。第 20 步临时用的 `macos/core/tests/mac-share-data.*` 已删除，测试改用真正的 `CShareData::InitShareData`。

## 设计

| 项目 | Windows 版 | Mac 版 |
| --- | --- | --- |
| 共通设置 `DLLSHAREDATA` 放在哪里 | 命名的文件映射（多个进程共享） | 进程内的一块清零内存，用 placement new 建立（`env/CShareData.cpp`）。Mac 版是单进程（多窗口在第 26 步处理），不需要跨进程共享 |
| 结构 | `DLLSHAREDATA` | 完全相同，不改字段 |
| sakura.ini 的位置 | exe 旁边，或“用户别设置”时的 `%APPDATA%\sakura` | `~/Library/Application Support/sakura/sakura.ini`。App Store 版在沙盒里，`HOME` 指向应用容器，自动落在容器里。相当于 Windows 版的“用户别设置”，没有“exe 旁边的 ini”（`.app` 里不能写） |
| sakura.ini 的格式 | UTF-8 带 BOM、CRLF | 相同（同一份 `CProfile` 代码） |
| 写出 ini | 先写临时文件再替换 | 写 `sakura.ini.tmp` 再 `rename`（同样不会写坏一半） |
| 路径分隔符 | `\` | `/`。`util/file.cpp` 的路径函数都有 Mac 分支 |
| 命名互斥锁 `CMutex` | Win32 命名 Mutex（跨进程） | 进程内按名字共享的 `std::recursive_timed_mutex`。同名的 `CMutex` 对象共享同一把锁，`Lock` / `Unlock` 的语义与 Windows 版相同 |
| 版本号 | 资源里的版本信息 | 构建时由 `src/main/cmake/version.cmake` 生成 `version.h`（与 Windows 版同一个脚本），ini 的 `szVersion` 相同 |
| `MainMenu.ini`（主菜单的默认定义） | exe 的资源 | `macos/tools/rc_strings.py` 把它和字符串表一起嵌进程序，`FindResourceW` 等由 `macos/platform/src/resources.cpp` 提供 |
| 字体大小换算（磅 ↔ 像素） | 按屏幕 DPI | 固定按 96 DPI 换算，使 ini 里的值与 Windows 版（100% 缩放）相同。屏幕上的实际大小在第 28 步处理 |
| 语言 DLL | 非日文 Windows 首次启动时切换到英文 DLL | 不用语言 DLL（界面多语言化在第 48 步） |
| 类型别设置的读写 | 通过任务栏托盘窗口的消息（`MYWM_GET_TYPESETTING` 等） | 单进程，`CDocTypeManager` 直接读写类型设置列表（与 `CControlTray::OnGetTypeSetting` 等的处理相同）。追加、删除类型只在类型一览对话框里用，与对话框一起移植 |

## 编进核心库的部分

| 目录 / 文件 | 内容 |
| --- | --- |
| `env`（整个目录，除下表“留到后面的”） | `CShareData`（默认值）、`CShareData_IO`（ini 读写）、`CProfile`、`CDataProfile`、`CDocTypeManager`、`CFileNameManager`、`CommonSetting`、`DLLSHAREDATA`、关键字 / 辞书 / 标签跳转 / 查找关键字等 |
| `recent`（除菜单部分） | 最近使用的文件、文件夹、查找关键字等的历史 |
| `grep` | `GrepMessageFormat`（Grep 结果的格式化） |
| `util/file.cpp` | 路径函数（Mac 分支） |
| `_main/CMutex.cpp` | 命名互斥锁 |
| `func/CKeyBind.cpp` | 按键分配的默认值和查找（Windows 的加速键表不用） |
| `print/CPrint.cpp` | 只用打印设置的默认值和用纸表 |
| `uiparts/CMenuDrawer.cpp` | 只用工具栏按钮表（共通设置的工具栏项目） |
| `macro/CSMacroMgr.cpp` | 只用宏函数名表（按键分配写进 ini 时用函数名） |
| `view/colors/CColorStrategy.cpp` | 只用颜色名表（ini 的 `C[TXT]=...`） |
| `extmodule/CMigemo.cpp` | 用共通设置里的 DLL 名和词典路径（词典的相对路径按 ini 所在文件夹解释） |

## 留到后面的

| 内容 | 步骤 |
| --- | --- |
| `env/CAppNodeManager`（编辑窗口列表和切换） | 第 26 步（窗口框架） |
| `env/CReadManager`、`CWriteManager`、`CCodeChecker`（依赖编辑画面） | 第 29 步（打开与保存） |
| `recent/CMruListener` | 第 29 步 |
| `recent/CMRUFile`、`CMRUFolder`（“最近的文件”菜单） | 菜单的步骤 |
| `env/CHokanMgr`（输入补全窗口）、`env/CPropertyManager`（打开设置对话框） | 对应的界面步骤 |
| `env/CFormatManager`（插入日期 / 时间的格式）、`env/CSakuraEnvironment`（`$F` 等宏参数的展开） | 与插入日期命令、标题栏、打印页眉一起移植 |
| `CFileNameManager` 按显示宽度省略路径（`GetShortViewPath`） | 第 28 步（需要测量文字宽度） |
| 默认的“文件名简易表示”（`%DeskTop%\` 等）是 Windows 的写法 | 保持与 Windows 版相同的默认值；Mac 上 `%Personal%` 等对应 `~/Documents` 等（`CFileNameManager` 的 Mac 分支）。是否另设 Mac 的默认值，到标题栏的步骤再决定 |
| `CKeyBind::CreateKeyBindList`（键分配一览） | 与功能名查找 `CFuncLookup` 一起移植 |
| 打印本身（`CPrint` 的其余部分） | 打印的步骤 |
| 宏的读入和执行（`CSMacroMgr` 的其余部分） | 第 45 步 |
| 键盘输入（`GetKeyState` 现在总是“没按下”） | 键盘的步骤 |
| 多个配置文件（`-PROF` 选项） | 第 26 步（命令行） |

## 平台层新增

| 文件 | 内容 |
| --- | --- |
| `macos/platform/src/resources.cpp`（新） | `FindResourceW`、`LoadResource`、`LockResource`、`SizeofResource`，从嵌入的资源表查找 |
| `macos/tools/rc_strings.py` | 除字符串表外，也把 `sakura_rc.rc` 里用户定义类型的资源（`MainMenu.ini`）嵌进去 |
| `macos/platform/src/win32_api.cpp` | `GlobalAlloc` 等、`PathMatchSpecW`（类型别扩展名的通配符） |
| `macos/platform/src/ui_bridge.cpp` | `GetKeyState`、`IsVisualStyle`、`DpiPointsToPixels` / `DpiPixelsToPoints`（96 DPI）、`CSelectLang::InitializeLanguageEnvironment` |
| `macos/platform/include/sakura_platform.h` | 上面这些的声明；`VK_*`、`DMPAPER_*`、`HOTKEYF_*`、`TBBUTTON` 等与 Windows 相同的值（保存在 ini 里，必须相同）；`CGraphics.h` 用到的 GDI 函数的声明（第 28 步实现） |
| `util/wchar16.h`（Mac 部分） | `swscanf_s`、`_wsplitpath_s`、`lstrcpyW`、`_totlower`、`sakura::to_wstring` |

## 原版代码的改动

都用 `#if defined(_WIN32)` 隔开，或者在 Windows 上结果不变：

| 文件 | 改动 |
| --- | --- |
| `env/CShareData.cpp`、`CShareData.h` | 共享内存改为进程内内存；ini 路径；`lfIconTitle` 的字体在 Mac 上是 Hiragino Sans（Windows 版从系统取得）；任务栏、进程相关部分隔开；MRU 的清空直接调用历史类 |
| `env/CShareData_IO.cpp` | ini 路径固定为用户位置；语言 DLL 部分隔开；`CopyFileW` 换成 `std::filesystem::copy_file`；`std::to_wstring` 换成 `sakura::to_wstring` |
| `env/CProfile.cpp` | 写出时的临时文件和替换；路径转换 |
| `env/CDataProfile.h` | `std::to_wstring` 换成 `sakura::to_wstring`（Windows 上就是 `std::to_wstring`） |
| `env/CDocTypeManager.cpp` | 类型设置的读写直接访问列表 |
| `env/CFileNameManager.cpp` | `%MYDOC%` 等对应到 `~/Documents` 等；环境变量；路径分隔符 |
| `env/DLLSHAREDATA.cpp` | 界面部分隔开 |
| `util/file.cpp` | 路径函数的 Mac 分支；`std::wregex` 换成普通的盘符判断（Windows 上结果相同）；`GetLastWriteTime` 用 `stat` |
| `util/string_ex2.h` | Mac 上 `long long` 和 `int64_t` 可能是不同的类型，补上通用的 `int2dec_destBufferSufficientLength` |
| `_main/CMutex.*`、`_main/global.cpp` | 进程内互斥锁；`G_AppInstance` 在 Mac 上返回 `nullptr` |
| `func/CKeyBind.cpp`、`print/CPrint.cpp`、`uiparts/CMenuDrawer.cpp`、`macro/CSMacroMgr.cpp`、`view/colors/CColorStrategy.cpp`、`plugin/CPlugin.h` | 只编译设置模块用到的部分，其余隔开 |
| `recent/CRecentImp.cpp`、`CRecentEditNode.cpp` | 与 MinGW 相同的重复实例化处理；`HWND` 比较 |
| `io/CTextStream.cpp` | 去掉第 20 步加的隔离（`CTextInputStream_AbsIni` 现在可用） |
| 4 个原版测试 | `test-cdoctypemanager`、`test-cprofile`、`test-grepmessageformat` 用 `macos/tools/convert_wchar.py` 转换字面量；`test-cprofile` 里 Windows 路径的两处、`test-grepmessageformat` 和 `test-csearchagent` 的测试夹具在 Mac 上换成 `mac-editor-test-suite.hpp` |

## 测试

- 新加入的原版测试：`test-cfileext`、`test-cdoctypemanager`、`test-grepmessageformat`、`test-cprofile`，以及原版的 `env/ShareDataTestSuite.cpp`（测试用的共通设置）。
- `macos/core/tests/test-mac-env.cpp`（新）：20 个测试。
  - **ini 往返**：按原版控制进程的启动顺序（建立共通设置 → 读入 → 读不到时写出默认值 → 刷新字符串）启动、结束、再启动，写出的 sakura.ini 逐字节相同。UTF-8 带 BOM、全部 CRLF、各节都在。
  - **Windows 的值**：把 ini 改成 Windows 版的值（`C:\Users\さくら\...`、`Yu Gothic UI`、`C:\Program Files\sakura\migemo.dll`）后读入再写出，逐字节相同。
  - 版本较旧的 ini 读入时做 `.bak` 备份；共通设置的默认值（主菜单、按键分配、打印设置、类型）；`CDocTypeManager` 的读写和通配符。
  - 路径函数（Mac 路径）、`CTextInputStream_AbsIni`（相对路径按 ini 文件夹）、更新时间、临时文件。
  - `swscanf_s`、`_wsplitpath_s`、`PathMatchSpec`、嵌入的 `MainMenu.ini` 与源文件相同、命名互斥锁跨线程。
  - C/Migemo：原版 `CMigemoTest` 的三个测试（没有词典、UTF-8 词典相对路径、cp932 词典绝对路径）；`InitRegexp` 用共通设置的 DLL 名。
- `macos/core/tests/mac-test-home.cpp`（新）：测试程序启动时把 `HOME` 换成临时文件夹，不会碰到运行测试的人自己的设置。
- `macos/core/tests/mac-editor-test-suite.hpp`（新）：原版 `EditorTestSuite`、`TrayWndTestSuite` 的 Mac 版，只建立共通设置（还没有窗口）。
- `macos/core/tests/mac-layout-stub.cpp`（新）：从 `mac-share-data.cpp` 留下的 `LogicToLayout` 占位，第 27 步删除。

### 与计划的验收标准不同的地方

计划要求 `test-file` 通过。原版 `test-file.cpp` 的大部分测试是 Windows 的文件 API（`MockKernel32`、文件属性、`C:\` 路径、注册表位置的 ini），不能在 Mac 上编译。其中与平台无关的项目（文件名的非法字符、文件名部分、目录深度、`FileMatchScoreSepExt`、`CheckEXT`、ini 文件夹、`CTextInputStream_AbsIni`）按 Mac 的路径在 `test-mac-env.cpp` 里重写了。

## 原版的行为（不是 bug，记录下来）

第一次启动时写出的 sakura.ini 与之后写出的不完全相同，Windows 版也一样：

1. 首次启动时 ini 在刷新字符串资源之前写出，3 个键名（`^(英語')`、`@(英語`)`、`アプリキー`）是空的；结束时写出的文件里才有。
2. `[Font]` 的 `nPointSize` 首次是 0，下一次读入时由像素数算出（9.8 磅），之后写出 98。

从第二次启动起，读入再写出逐字节相同。测试里也确认了这两处差异正好如此。

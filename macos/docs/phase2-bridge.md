# 阶段 2 第 24 步：桥接层

**结论**：新建了桥接层 `macos/bridge/`。它用 Objective-C++ 把核心库接口（`SakuraCore.h`，C++）包装成框架 `EditorBridge`，Swift 写 `import EditorBridge` 就能打开、编辑、查找、保存文件。Swift 的单元测试（XCTest）通过桥接层打开 UTF-8 和 SJIS 文件，读到的文字与文件内容一致，满足这一步的完成标志。App 也接上了：启动时启动核心库，「ファイル > 開く…」（Cmd+O）可以打开文件，窗口里只读显示文件内容，标题是文件名，副标题是编码。

## 结构

```
Swift（macos/app/Sources、Tests）
   │  import EditorBridge
   ▼
EditorBridge.framework（macos/bridge，Objective-C++）
   │  #include "sakura_core/SakuraCore.h"
   ▼
核心库的静态库（macos/core，CMake 构建）
   libsakura_core_api.a、libsakura_core.a、libbregonig.a、libonigmo.a、libcmigemo.a
```

- `macos/bridge/include/EditorBridge.h`：公开头文件，只引用 Foundation。Swift 看到的就是这个文件。
- `macos/bridge/src/EditorBridge.mm`：实现。每个方法只是调用对应的 `sakura::core` 函数。

核心库的静态库由 Xcode 在构建桥接层框架之前运行 `macos/app/Scripts/build-core.sh` 用 CMake 构建，放在仓库根目录的 `build/xcode-core/<Debug|Release>/`。架构和最低系统版本按 Xcode 的设置（Release 是 `arm64`、`x86_64` 通用二进制）。脚本也可以单独运行。

## Swift 里的样子

| Objective-C | Swift | 对应的核心库 |
| --- | --- | --- |
| `ECCore` | `EditorCore.startup()`、`shutdown(savingSettings:)`、`name(ofEncoding:)`、`name(ofCommand:)` | `Startup`、`Shutdown`、`EncodingName`、`CommandName` |
| `ECDocument` | `EditorDocument()`、`open(path:)`、`save(to:encoding:bom:eol:)`、`text`、`line(at:)`、`replace(_:with:)`、`undo()`、`find(_:from:backward:options:range:)`、`replaceAll(_:with:options:)`、`execute(_:)` | `Document` |
| `ECResult` | `EditorResult`（`.success`、`.failed`、`.invalidArgument` 等） | `Result` |
| `ECEol` | `EditorEol`（`.crlf`、`.lf` 等） | `Eol` |
| `ECPosition`、`ECRange` | `EditorPosition`、`EditorRange` | `Position`、`Range` |
| `ECSearchOptions` | `EditorSearchOptions`（`.regularExpression`、`.matchCase`、`.wholeWord`） | `SearchOptions` |
| `ECEncodingUTF8` 等 | 同名的整数常量 | `encoding::UTF8` 等 |
| `ECCommandUndo` 等 | 同名的整数常量 | `command::Undo` 等 |

约定：

- 文字：`NSString` 和核心库的 `std::u16string` 都是 UTF-16，逐个 UTF-16 单位复制，不转换编码。位置的列号也是 UTF-16 下标（Swift 的 `String.utf16` 的下标、`NSString` 的 `length`）。
- 数值：编码、换行符、功能编号与原版相同。实现文件里用 `static_assert` 逐个确认与核心库一致。
- Swift 的 `Int` 是 64 位，核心库的位置是 32 位。超出 32 位的值当作无效的位置（返回 `.invalidArgument`），不截断。
- `EditorDocument()` 在核心库没有启动时返回 `nil`。

## App 的变化

- 启动时调用 `EditorCore.startup()`（读入 sakura.ini，没有时写出默认设置）；结束时调用 `EditorCore.shutdown(savingSettings: true)` 写出设置，与原版的控制进程相同。沙盒里设置文件在 App 的容器中（`~/Library/Containers/com.hanagumo.texteditor/Data/Library/Application Support/sakura/sakura.ini`）。
- 「ファイル」菜单加了「開く…」（Cmd+O），用文件面板选择文件，可以一次选多个。从 Finder 拖到 Dock 图标上打开也走同一个处理。
- 编辑窗口持有一个 `EditorDocument`，占位视图逐行显示内容、行号和 `[EOF]`，可以滚动。只能看，不能编辑；编辑画面在第 27～30 步移植原版的 `CEditView`。
- 标题显示文件名（无题时是「(無題)」），副标题显示编码（例如「SJIS」「UTF-8 BOM」）。

## 核心库的小改动

- **`LogicToLayout` 的占位移进核心库**：只链接核心库（不链接测试程序）时，`types/CType_*.cpp` 用到的 `CLayoutMgr::LogicToLayout` 找不到定义，链接失败。这个占位原来在测试里（`macos/core/tests/mac-layout-stub.cpp`），现在移到 `macos/core/src/layout_stub.cpp`，编进 `sakura_core`。内容不变（不换行，排版位置等于逻辑位置），第 27 步移植排版时删除。
- **链接检查**：新加 `macos/core/tests/core-api-link-check.cpp`，一个不用 GoogleTest 的小程序，与 App 一样只链接 `sakura_core_api`，启动、插入、查找后结束。`ctest` 里的名字是 `CoreApiLinkCheck`。以后核心库缺少函数时，在 CMake 构建阶段就能发现，不用等 Xcode。

## 测试

- 核心库：`ctest` 957 个通过（原来的 956 个加 `CoreApiLinkCheck`）。
- 桥接层：`macos/app/Tests/EditorBridgeTests.swift`，6 个测试：
  - 核心库已启动，设置文件已写出。
  - **打开 UTF-8 文件读到文字**（完成标志）：全文、行数、行内容（含日文和补充平面字符）、换行符、编码、类型（`.cpp` 是「C/C++」）。
  - 打开 SJIS（CRLF）文件，自动识别编码，读到日文。
  - 打开不存在的文件返回 `.failed`。
  - 编辑、查找（补充平面字符算 2 个 UTF-16 单位）、正则全部替换、撤销和重做、超出范围的位置被拒绝（包括超出 32 位）、另存为 UTF-16LE 带 BOM 并统一成 CRLF，字节正确。
  - 命令：功能名「元に戻す」、能否执行、执行撤销和换行符切换。
- CI（`build-macos.yml` 的 `build`）：取子模块，`xcodebuild test`（Debug）运行上面的测试；Release 构建后确认 App 里嵌入了 `EditorBridge.framework`，并且是 `arm64`、`x86_64` 通用二进制；启动检查不变。

## 在 Mac 上构建的前提

比第 9 步多了两样：

```sh
brew install cmake
git submodule update --init externals/Onigmo externals/bregonig externals/cmigemo
```

## 文件

新建：

- `macos/bridge/include/EditorBridge.h`：桥接层的公开头文件
- `macos/bridge/src/EditorBridge.mm`：桥接层的实现
- `macos/app/Scripts/build-core.sh`：Xcode 构建时用 CMake 构建核心库
- `macos/app/Tests/EditorBridgeTests.swift`：桥接层的单元测试
- `macos/core/tests/core-api-link-check.cpp`：只链接核心库的检查程序
- `macos/docs/phase2-bridge.md`：本文档

移动：

- `macos/core/tests/mac-layout-stub.cpp` → `macos/core/src/layout_stub.cpp`

修改：

- `macos/app/project.yml`：加入框架 `EditorBridge` 和测试 `SakuraMacTests`，App 依赖并嵌入框架
- `macos/app/Sources/AppDelegate.swift`、`EditorWindowController.swift`、`MainMenuBuilder.swift`：启动和结束核心库、打开文件、显示内容
- `macos/core/CMakeLists.txt`、`macos/core/tests/tests.cmake`：占位的位置、链接检查
- `.github/workflows/build-macos.yml`：子模块、桥接层测试、框架检查
- `macos/README.md`：目录结构、构建前提、文档链接

原版 `sakura_core` 的文件这一步没有修改。

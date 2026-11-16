# 阶段 2：性能（计划第 36 步）

大文件和超长行的打开、滚动、查找。完成标志：不慢于 Windows 版。

## 测试用的文件

`macos/tools/perf/make_perf_files.py` 做两个文件（核心库的测试、App 的测试里做的与它逐字节相同）：

| 文件 | 内容 |
|---|---|
| `large.txt` | 20 万行、约 17 MB。日文和英文、TAB、`//` 注释，CRLF，最后一行 `needle at the end` |
| `long.txt` | 一行 200 万字（`abcdefghi ` 的重复），最后是 `needle`，没有换行 |

## 三种测试

| 测试 | 位置 | 量什么 |
|---|---|---|
| 核心库 `MacPerfTest.LargeFile` / `LongLine` | `macos/core/tests/test-mac-perf.cpp` | 打开、查找（前后、正则）、全部查找、跳到末尾、改折り返し桁数、全部替换、超长行的颜色 |
| App `PerformanceTests` | `macos/app/Tests/PerformanceTests.swift` | 打开 → 视图准备 → 画 → 跳到末尾 → 一页一页滚动（每次画）→ 查找 → 末尾和开头的输入法一轮 → 打字 |
| Windows 版 | `macos/tools/perf/windows-bench.js`（CI 的 `perf-windows`） | 官方最新版 sakura.exe 用宏做同样的操作：打开、前后查找、跳到末尾、插入和撤销、改折り返し桁数、全部替换 |

每个时间输出成 `[PERF] 名字: N ms (limit L ms)`。普通的测试（Debug）的上限定得宽，只防止明显变慢；
CI 的 `core-perf-macos`（Release）和 `perf-windows` 把两边的时间写进各自 job 的 Summary，用来比较。

注意：官方发布版只有 Win32（32 位）的 exe，Windows 的时间是 32 位版的。CI 的 macOS（Apple Silicon）和 Windows 的机器不同，时间只能看大概（同一个量级、没有哪一项慢很多）。
Windows 版的时间包括宏的解释和画面的更新，Mac 的核心库测试不画画面。

## 本机（Linux clang -O2）的核心库的时间

| 操作 | 时间 |
|---|---|
| 打开 17 MB / 20 万行 | 334 ms |
| 查找（到末尾） | 25 ms |
| 正则查找 | 81 ms |
| 全部查找（20 万个） | 53 ms |
| 改折り返し桁数（重新排版） | 260 ms |
| 全部替换（20 万处） | 1216 ms |
| 超长行（200 万字）打开 | 49 ms |
| 超长行的颜色 | 141 ms |

核心库是 Windows 版的原样代码（排版在 1000 行以上时多线程），速度与 Windows 版相同。

## 找到并修好的问题

1. **输入法的调用随文件大小变慢（App）**。NSTextInputClient 的每次调用（`selectedRange`、`attributedSubstring` 等）
   以前会把整个文档的文字做一遍，位置换算（`offset(of:)`、`position(ofOffset:)`）也会逐行复制文字。
   17 MB 的文件里每打一个字要等很久。现在：
   - 核心库加了 `Document::TextLength`、`OffsetOf`、`PositionAtOffset`（逐行只加长度，不复制），桥接层 `textLength`、`offset(of:)`、`position(atOffset:)`。
   - `attributedSubstring` 只取需要的几行（`documentSubstring`），不做整个文档的文字。
2. **超长行的画面、光标移动、输入慢（App。CI 的 App 性能测试发现：翻一页约 1 秒，输入法一轮约 8 秒）**。
   - 排版行（「折り返さない」时最多 10240 桁）的全部文字都排、都画。现在只画看得见的横向范围（`visibleIndices`）。
   - 每个排版行都取出整个逻辑行再切。现在只取出这一段（`document.text(in:)`）。
   - 每次移动光标、输入法的未确定文字变了都清除行和颜色的缓存（整行的色分け重新计算）。
     核心库加了 `ChangeCount`（编辑、撤销、重新排版时增加），文档没变时留着缓存。
   - 光标移动、BackSpace/Delete 为了行的长度、一个字的范围取出整行。核心库加了 `LineLength`，一个字的范围只取前后的文字（`composedCharacterRange`）。
   - 输入法要求的一段文字（`attributedSubstring`）只取那一段。
   - 点→文字位置（`characterIndex`）逐字找、每个字都重新算光标的画面位置。改成二分查找，光标的画面位置在光标和文档没变时留着。
3. **优化构建时排版异常终了（原版代码）**。`CLayoutMgr::CreateLayout` 用 `allocate(sizeof(CLayout))` 向内存池要内存，
   对齐用默认值（`alignof(max_align_t)` = 16），但内存池的节点只对齐到 8。-O2 时编译器按 16 字节对齐优化，
   在 CLayout 的构造里异常终了。改成 `allocate(sizeof(CLayout), alignof(CLayout))`。
   原版的内存池不看对齐的参数，Windows 版的行为不变。

## 「折り返さない」

与原版相同，「折り返さない」也在最大 10240 桁折り返す。超长行在 Mac 上也是这样显示。

## 文件

- `macos/core/tests/test-mac-perf.cpp`（新）
- `macos/app/Tests/PerformanceTests.swift`（新）
- `macos/tools/perf/make_perf_files.py`、`macos/tools/perf/windows-bench.js`（新）
- `.github/workflows/build-macos.yml`：`core-perf-macos`、`perf-windows`
- `macos/core/include/sakura_core/SakuraCore.h`、`macos/core/api/SakuraCore.cpp`、`macos/bridge/`、`macos/app/Sources/EditorTextView.swift`
- `sakura_core/doc/layout/CLayoutMgr.cpp`（对齐）

## 手动确认（集中确认时）

- 打开几十 MB 的日志文件，拖滚动条、按 Page Down，看是否卡。
- 在大文件的末尾用输入法打日文，看候选窗口的位置和反应。
- 打开一行很长的文件（压缩过的 JSON、JS），左右滚动、查找。

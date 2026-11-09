# 阶段 1 第 19 步：换掉 DLL

**结论**：正则（Onigmo + bregonig）和 C/Migemo 作为源码编进 Mac 版核心库，原版加载 DLL 的代码（`sakura_core/extmodule`）几乎不改就能用。uchardet 与 Windows 官方版一样不附带。正则、Migemo、编码自动识别的测试都通过，Mac 核心库的全部 695 个测试通过。

## 内置范围（2026-11-09 项目负责人决定）

| 模块 | Windows 官方版 | Mac 版 |
| --- | --- | --- |
| 正则 bregonig.dll（bregonig 4.20 + Onigmo） | 附带 | 内置，同一份源码 |
| C/Migemo（migemo.dll + 词典） | 不附带，用户自己放 | 内置引擎；词典见下面“许可证” |
| uchardet.dll | 不附带，用户自己放 | 不内置。编码自动识别只用 Sakura 自己的判断，结果与官方版相同 |

## 做法

原版用 `CDllImp`（`extmodule/CDllHandler.cpp`）调用 `LoadLibraryW` 加载 DLL，再用 `GetProcAddress` 按函数名取得地址。Mac 版保留这套代码，在 `macos/platform/src/static_modules.cpp` 里实现这三个函数：

- `LoadLibraryW`：按文件名（不区分大小写，忽略目录）在登记表里找，找到就返回表的地址作为句柄。只登记 `bregonig.dll` 和 `migemo.dll`，其他名字（包括 `uchardet.dll`）返回 `nullptr`，和 Windows 上找不到 DLL 时一样。
- `GetProcAddress`：在该模块的函数表里按名字找。
- `FreeLibrary`：静态链接，没有要释放的。
- `bregonig.dll` 第一次加载时调用一次 bregonig 的 `DllMain(DLL_PROCESS_ATTACH)`，与 Windows 加载 DLL 时一样初始化 Perl 兼容语法。

原版代码的改动只有两处，都用 `#if defined(_WIN32)` 隔开，Windows 版编译结果不变：

| 文件 | 改动 |
| --- | --- |
| `extmodule/CDllHandler.cpp` | Mac 版不在 exe 所在目录前面加路径，直接用名字加载 |
| `extmodule/CBregexp.cpp` | `InitRegexp`、`CheckRegexpVersion`、`CheckRegexpSyntax` 用到共通设置和消息框，Mac 版在第 21 步（env）之后启用 |

## 第三方源码的编译

| 库 | 源码 | Mac 版补充的文件 | 编译 |
| --- | --- | --- | --- |
| Onigmo | `externals/Onigmo`（子模块） | `macos/thirdparty/onigmo/config.h`（只支持 64 位） | C，`onigmo` 静态库 |
| bregonig | `externals/bregonig`（子模块） | `macos/thirdparty/bregonig/bregonig_mac.h`（编译时强制包含，补上 TCHAR 等 Windows 定义） | C++17，与原版 DLL 一样每个文件编译 UNICODE 版和多字节版两次，`bregonig` 静态库 |
| C/Migemo | `externals/cmigemo`（子模块） | 无 | C，`cmigemo` 静态库 |

构建前要取得子模块：`git submodule update --init externals/Onigmo externals/bregonig externals/cmigemo`。CI（`build-macos.yml` 的 core-tests-macos）也加了这一步。

## 测试

`macos/core/tests/test-mac-extmodule.cpp`（原版 `test-extmodules.cpp` 依赖共通设置和资源里的 zip，Mac 版还不能直接编译，这里改写了不依赖它们的部分）：

| 测试 | 内容 |
| --- | --- |
| `StaticModules.*` | 登记表：大小写、目录、不存在的名字、不存在的函数 |
| `LoadTest.*` | 原版同名测试：DLL 找不到、函数对不上时 `IsAvailable()` 为 false |
| `CBregexpTest.test001`、`MatchConcurrentlyWithSeparateObjects` | 原版同名测试 |
| `CBregexpTest.RepresentativePatterns` | 14 个有代表性的查找和替换：日文、半角假名、`\p{Han}`、后行断言、命名组、BMP 以外的字符、全角字母不区分大小写、`$1` 替换、`\U` 大写化、`\r\n` 替换 |
| `CMigemoTest.QueryWithUtf8Dictionary` | 用原版测试同样的 UTF-8 词典，查询“さくらえでぃt”的结果与原版 `CMigemoTest.test002` 的期望值完全相同 |
| `CUchardetTest.NotBundled` | uchardet 加载失败（与官方版相同） |

另外，第 18 步留下的编码自动识别检查加进了 `test-mac-roundtrip.cpp`：SJIS、JIS、EUC、UTF-8（有/无 BOM）、UTF-16LE/BE（有 BOM）的样本都识别正确。

## 留到后面的

- `CMigemo` 本身（DLL 名和词典路径来自共通设置）、`InitRegexp` 等：第 21 步（env）。
- 原版 `CDllImpLoadPathTest`（exe 所在目录、当前目录）：Mac 版不从文件加载，不适用。
- Migemo 词典放进 App：阶段 2 以后，按下面的许可证结论处理。

## 许可证（第 51 步“关于窗口和致谢页”要写）

| 库 | 许可证 |
| --- | --- |
| Onigmo | BSD 2-Clause |
| bregonig | GPL 或 Artistic License（二选一），App Store 版选 Artistic License |
| C/Migemo（引擎） | MIT |
| C/Migemo 词典（`externals/cmigemo-dict`，SKK 词典） | **GPL** |

**需要决定**：Migemo 词典是 GPL。GPL 与 App Store 的使用条款被普遍认为不兼容（自由软件基金会的立场，过去有 App 因此被下架），把词典打包进 App Store 版有风险。可选做法：不附带词典，让用户像 Windows 版一样自己指定词典文件夹（引擎内置）；或者另找许可证宽松的词典。测试只在构建时使用仓库里的词典，不受影响。

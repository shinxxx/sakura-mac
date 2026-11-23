# 阶段 3：タイプ別設定窗口（计划第 40 步）

原版的「設定 > タイプ別設定」（`CPropTypes`，6 页的属性表）做成 Mac 的窗口。完成标志：设置项与原版一一对应。

这一步分三个 PR：

1. **第 1 个 PR**：窗口（与共通設定窗口共用框架）、核心库的读写、スクリーン・ウィンドウ・支援 这 3 页的读写和联动、打开着的文档跟着变。
2. **第 2 个 PR**：カラー（色指定的列表、文字色統一・背景色統一、強調キーワード 2～10 的选择、インポート・エクスポート）、正規表現キーワード、キーワードヘルプ。
3. **第 3 个 PR**：タイプ別設定一覧（原版 `CDlgTypeList`：追加・複製・削除・順序、インポート・エクスポート）、共通設定的 強調キーワード 页。

## 设置项的清单

`macos/tools/settings/list_type_settings.py` 从原版的对话框模板（`sakura_rc.rc` 的 `IDD_PROP_SCREEN` 等）和 `typeprop/CPropTypes*.cpp` 列出每一页的每一个控件、
它读写的 `STypeConfig` 成员、sakura.ini 的 `[Types(N)]` 的项目、Mac 版的处理，结果在 [type-settings.csv](type-settings.csv)（Excel 可以直接打开）。

第 1 个 PR 的 3 页：

| Mac 版 | 意思 | 个数 |
|---|---|---|
| ○ | 与原版相同地读写 | 70 |
| × | Mac 版做不到，变灰（值不改） | 6 |
| （空） | 说明文字 | 1 |
| 第 40 步（第 2 个 PR） | カラー、正規表現キーワード、キーワードヘルプ 页 | 76 |

Mac 版做不到的（×）：支援 页的補完種別（只有 DLL 的プラグイン 才会加，偏离项 9）、外部ヘルプ・外部 HTML ヘルプ（Windows 的帮助，偏离项 9）。

## 做法

| 部分 | 文件 | 内容 |
|---|---|---|
| 布局 | `macos/tools/settings/make_prop_dialogs.py` → `macos/app/Resources/TypeSettingsDialogs.json` | 与共通設定相同，原版对话框模板的每个控件。新加了トラックバー（背景画像の透明度）|
| 窗口 | `macos/app/Sources/TypeSettingsWindow.swift` | `TypeSettingsWindowController`。左边的页的列表、OK・キャンセル 与共通設定窗口共用 `PropSheetWindowController`（`CommonSettingsWindow.swift`）|
| 各页 | `macos/app/Sources/TypeSettingsPages.swift` | 原版 `CPropTypesScreen`・`CPropTypesWindow`・`CPropTypesSupport` 的 SetData / GetData 的移植 |
| 读写 | 核心库 `GetCommonSetting` / `SetCommonSettings`（节是 `Types(N)`）、`TypeSettings()` | 用原版的 `ShareData_IO_TypeConfig`，写法和范围限制与读 sakura.ini 时完全相同。读入后与原版 OK 时相同地 `CDocTypeManager::SetTypeConfig`（一览的名字・拡張子・文字コード、「基本」的 `m_TypeBasis` 也换）|
| 打开着的文档 | 核心库 `Document::ApplyTypeSettingChange`，`EditorTextView` | 原版 `MYWM_CHANGESETTING`（`PM_CHANGESETTING_TYPE`）→ `CEditDoc::OnChangeSetting`：这个类型的文档按文件名重新决定类型、读新的设置、重新排版、重画 |

与原版相同的地方：

- 页的顺序、每页的控件、文字、位置；`F_OPTION_TYPE`（設定 > タイプ別設定）打开这个文档的类型的设置、上次的页（原版 `m_nPropTypePageNum`），
  `F_TYPE_SCREEN` 等打开那一页。无题的文档是「基本」。
- 打开时复制设置，换页时取那一页的值，OK 时把改过的项写回、保存 sakura.ini、通知所有窗口。キャンセル 什么也不改。
- `nInts`（逗号分隔的 12 个数：折り返し桁数・文字の間隔・TAB幅・行番号を改行単位・行番号区切り・英文ワードラップ・TSV モード等）只改这一页的数，别的数不变。
- GetData 里的范围限制：折り返し桁数 10～10240、文字の間隔 0～64、行の間隔 -128～128、TAB幅 1～64、行番号の最小桁数 2～11、透明度 0～255。
  读入时的限制（TAB幅 ≤ 折り返し桁数 - 2 等）由核心库按原版做。
- スクリーン：「基本」的名字和拡張子不能改；TAB表示 是矢印时文字不能改；TAB表示文字列 按原版 8 个字（「^」和 7 个空白里从头放入输入的字，到 TAB・改行为止）；
  アウトライン解析 的標準ルール／ルールファイル 的联动（选標準ルール 时列表选第一项）；タイプ別フォント（选了字体就「使用する」，取消勾选后不能再勾，
  标签显示「名前(9pt)」）；ぶら下げを隠す 只在改行ぶら下げ・句読点ぶら下げ 时可用。
- ウィンドウ：起動時のIME 的下位 2 bit 是 ON/OFF、上面是入力モード；デフォルトの文字コード 的列表（`CCodeTypeName::CanDefault`），
  不在列表里的（代码页）时勾上「CP」加上代码页；「CP」按了以后不能再按；换了文字コード 时 BOM 是那个编码的默认值，不能加 BOM 的编码 BOM 变灰；
  行番号区切り 是「任意」时才能改文字；背景画像の透明度 的数字和トラックバー联动（不透明度 = 255 - 透明度）。
- 打开着的文档：原版 `PM_CHANGESETTING_TYPE` 的条件（文档的类型或按文件名决定的类型是改了的类型），拡張子改了时文档换到新的类型。
  折り返し方法的临时设置（F_TMPWRAP* 等）：类型没变、设置的折り返し方法也没变时保留；与新的设置相同时解除（原版 `m_bTextWrapMethodCurTemp`）。

与原版不同的地方（偏离项 4：布局、项目、文字照原版，外观是 Mac 的）：

- 原版的属性表的标签换成左边的列表（与共通設定窗口相同）。原版是模态的，Mac 版与共通設定相同是一次只开一个的窗口；
  已经打开时再执行 タイプ別設定 只把它拿到前面（不换类型）。
- タイプ別フォント 不使用时选字体：原版从共通設定的字体开始，Mac 版从编辑画面现在的字体开始（Mac 版的编辑字体在「フォント設定」里）。
- 文件的选择（ルールファイル、背景画像、単語ファイル）用 Mac 的打开面板。原版可以写相对路径（从设置文件的文件夹），Mac 版选择后是绝对路径（手动输入相对路径照样保存）。

## 设置的生效

与共通設定相同，这一步完成的是「设置窗口与原版一一对应、值与 Windows 版的 sakura.ini 相同地读写」。OK 后这个类型的文档马上按新的设置重新排版、重画，
核心库已经移植的部分（折り返し、TAB 幅、文字・行の間隔、行番号、禁則、SPACEの挿入、オートインデント、保存时的改行コード混在警告等）按新的值动作。
Mac 版还没有的界面在做那些界面的步骤里接上：タイプ別フォント（编辑画面的字体现在是共通的一个）、背景画像、起動時のIME、文書アイコン、
アウトライン解析、入力補完、C/C++ のスマートインデント。

## 测试

- 核心库 `macos/core/tests/test-mac-type-settings.cpp`（9 个）：一览的顺序、读出的值与 sakura.ini 的写法相同（`nInts`、タイプ別フォント的项目）、
  改一个类型不影响别的类型、「基本」也换 `m_TypeBasis`（新文档用）、原版的范围限制、没有的项目和类型不改、
  打开着的文档跟着变（别的类型的文档不变）、拡張子改了时换类型、折り返し方法的临时设置、保存后重新启动也是新的值。
  `test-mac-common-settings.cpp`：`Types(999)` 这样没有的类型不改。
- App `macos/app/Tests/TypeSettingsTests.swift`（17 个）：6 页的顺序和控件与原版的模板相同、各功能打开的页、编辑画面打开这个文档的类型、
  OK 只写改过的项（节是 Types(N)）、キャンセル 不改、真的核心库的 OK 和打开着的编辑画面（这个类型的跟着变，别的类型的不变）、
  スクリーン（nInts 的各个数、范围、TAB表示、「基本」的名字、アウトライン解析、禁則、タイプ別フォント）、ウィンドウ（IME 的 bit、行番号、透明度的联动、
  デフォルトの文字コード 的列表・BOM・CP、背景画像）、支援（Mac 版不能用的项目变灰、值不改、単語ファイル）、以后移植的页只显示。
- 界面测试 `testTypeSettingsWindow`：設定 > タイプ別設定 打开（无题是「基本」，名字不能改）、勾上「SPACEの挿入」按 OK 后 TAB 键输入空白，
  再打开时是改过的值和上次的页，取消勾选后 TAB 键输入 TAB。

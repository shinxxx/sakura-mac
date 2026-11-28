# 阶段 3：ヘルプ（计划第 49 步）

原版的帮助是 Windows 的 HTML Help（`sakura.chm`，源文件在 `help/sakura`；マクロリファレンス `macro.chm` 在 `help/macro`，合并进目次）。
macOS 没有 HTML Help，Mac 版把原版的 HTML 原样收进 App，用自己的ヘルプ窗口显示。帮助的内容是日文，与原版相同（原版的英文・中文语言包也没有翻译帮助）。

## 决定

| 原版 | Mac 版 |
|---|---|
| HTML Help 的窗口（目次・キーワード・検索、非表示・戻る・進む・ホーム・印刷） | ヘルプ窗口（`Sources/HelpWindow.swift`，WKWebView）：同样的三个标签和按钮，目次随页自动同步。模态的对话框打开时也能用 |
| ヘルプ > ヘルプ目次（F_HELP_CONTENTS）・キーワード検索（F_HELP_SEARCH） | 打开ヘルプ窗口的目次・キーワード |
| ヘルプ > コマンド一覧（F_MENU_ALLFUNC） | 弹出「種別」ごとのサブメニュー（原版 CFuncLookup），选了就执行；Mac 版没有的功能是灰色 |
| 对话框的「ヘルプ」按钮、设置窗口（プロパティシート）的「ヘルプ」 | 打开原版的那一页（`HelpTopics.dialogFunctions`：原版 `FuncID_To_HelpContextID`／`HLP*`）。设置窗口加 macOS 的「?」按钮 |
| 控件上按右键／? 按钮再点控件（HELP_CONTEXTMENU、HELP_WM_HELP：Cshelp.txt 的弹出说明） | 右键（触控板两指点按）显示同样的说明（NSPopover） |
| 菜单上按 F1 打开那个命令的页 | macOS 的菜单打开时 App 收不到按键，做不到。代替：macOS 帮助菜单的搜索栏也搜帮助的キーワード |
| 帮助里指向网页的链接 | 用默认浏览器打开 |
| 外部ヘルプ１・外部HTMLヘルプ（F_EXTHELP1、F_EXTHTMLHELP） | 仍然灰色（偏离项 9） |

- 目次的先头加 Mac 版的页「Mac 版について」（`Resources/HelpMac.html`：与 Windows 版不同的地方）。
- Mac 版的注记：页的开头插入「Mac 版：…」的框（WKUserScript，不改原版的 HTML）。
  - Mac 版没有的功能（菜单里变灰）的页：自动加「Mac 版にはこの機能はありません」。
  - 其他（动作环境、sakura.ini 的位置、键、プラグイン、マクロ等）：`macos/tools/help/mac_notes.json` 里手写。
- プラグイン（plugin.chm）、PPA、Windows Script（script56）的帮助：原版也是另外的文件，Mac 版没有这些功能，不收。

## 数据

`macos/tools/help/make_help_data.py` 从原版的帮助生成 `macos/app/Resources/HelpTopics.json`：

| 键 | 来源 |
|---|---|
| toc（目次） | `sakura.hhc`（`Merge` 的位置合并 `macro.hhc`） |
| index（キーワード） | `sakura.hhk`、`macro.hhk`。App 里按原版一样排序 |
| topics（话题编号 → 页） | `sakura.hhp` 的 [ALIAS]、`src/main/resources/sakura.hh` |
| popups、controls（控件的说明） | `help/sakura/Cshelp.txt`，各对话框的 `p_helpids`（`sakura_core`）、`sakura.hh` 的 HIDC* |
| notes、noteLabel、unavailableNote | `mac_notes.json` |

改了原版的帮助（合并上游的更新）或 `mac_notes.json` 后：

```sh
python3 macos/tools/help/make_help_data.py   # CI 用 --check 确认与提交的一致
```

HTML、CSS、图片不复制：`project.yml` 把 `help/sakura`、`help/macro` 作为文件夹引用放进 App 的 Resources。

## 测试

见 [testing.md](testing.md) 的「ヘルプ（第 49 步）」。

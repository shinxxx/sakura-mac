# 阶段 3：界面本地化（计划第 48 步）

原版的界面有日文（sakura.exe 内置，`sakura_core/sakura_rc.rc`）和语言包 DLL（`sakura_lang/` 的英文 `sakura_lang_en_US.dll`、简体中文 `sakura_lang_zh_CN.dll`），
在共通設定『ウィンドウ』的「言語」里选。Mac 版用同样的文字，做成三种语言。

## 选择语言的方式（决定）

- **跟随系统的语言**（系统设置 > 通用 > 语言与地区，也可以按 App 单独设置）：在 日文・英文・简体中文 里选最合适的，其他语言时是日文。
  这是 Mac App 的通常做法，换语言后重新启动 App 生效。
- 共通設定的「言語」组合框保持不可用（Mac 版不用 DLL）。
- sakura.ini 的 `Common/szLanguageDll` 写原版对应的 DLL 名（日文为空），与 Windows 版互换。
  启动时的语言与 sakura.ini 不同时，像原版换语言时一样（`CShareData::ConvertLangValues`）把设置里的默认文字
  （タイプ名「基本」、日付・時刻書式、印刷設定名、键分配的名字等）换成新的语言。

## 文字的来源

| 文字 | 日文 | 英文・中文 |
|---|---|---|
| 原版的字符串表（`LS()`：功能名、菜单、消息） | `sakura_rc.rc` | 语言包 `sakura_rc_en-US.rc`・`sakura_rc_zh-CN.rc`，缺的由 `macos/tools/l10n/rc_supplement.json` 补 |
| 对话框的布局和文字 | `Resources/ja.lproj/*Dialogs.json` | `Resources/en.lproj/`・`Resources/zh-Hans.lproj/`（语言包的对话框模板，`make_prop_dialogs.py` 生成） |
| Mac 版自己的文字（`L10n.tr("日文", comment:)`） | 键本身 | `Resources/<语言>.lproj/Localizable.strings`（`macos/tools/l10n/make_strings.py` 生成：先用 `translations.json`，再用原版字符串表里相同文字的翻译） |
| 日付・時刻（曜日、月名、午前/午後） | ja_JP | en_US・zh_CN |

核心库：`rc_strings.py` 生成三种语言的字符串表，`CSelectLang::ChangeLang` 按 DLL 名切换，找不到的编号用日文。
App：`Sources/Localization.swift`（`L10n`），启动时 `EditorCore.uiLanguage = L10n.coreLanguage`。

## 改了文字以后

```sh
python3 macos/tools/settings/make_prop_dialogs.py   # 对话框
python3 macos/tools/l10n/make_strings.py            # Localizable.strings（缺翻译时失败，在 translations.json 里加）
```

## 测试

见 [testing.md](testing.md) 的「界面本地化（第 48 步）」。

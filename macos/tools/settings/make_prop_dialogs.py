#!/usr/bin/env python3
# Copyright (C) 2026, Sakura Editor Organization
#
# SPDX-License-Identifier: Zlib
"""共通設定窗口（计划第 39 步）、タイプ別設定窗口（第 40 步）的各页的布局。

从 sakura_core/sakura_rc.rc 的对话框模板（IDD_PROP_*，和从各页打开的对话框 DIALOGS）取出每个控件的种类、文字、位置（对话框单位），
写成 JSON，App 按它摆放控件（布局、项目、顺序、文字照原版，控件用 Mac 的）。
原版的 rc 改了以后重新运行：python3 make_prop_dialogs.py
（输出 macos/app/Resources/ja.lproj/CommonSettingsDialogs.json、TypeSettingsDialogs.json、
第 42 步的アウトライン解析 OutlineDialogs.json、第 43 步的 Grep GrepDialogs.json、
第 44 步的编辑辅助功能 EditSupportDialogs.json、第 46 步的ファイルの更新 FileSafetyDialogs.json、
第 47 步的印刷 PrintDialogs.json）

第 48 步（界面本地化）：同样从原版的语言包 sakura_lang/sakura_rc_en-US.rc、sakura_rc_zh-CN.rc 生成英文、中文的布局，
写到 Resources/en.lproj/、Resources/zh-Hans.lproj/（日文是 Resources/ja.lproj/，App 的开发语言）。
页的 "title" 是原版属性表的页名（CPropCommon、CPropTypes 的 STR_PROPCOMMON_*、STR_PROPTYPE_*，各语言的字符串表），
"name" 是固定的日文名（App 里找页、辅助功能标识用）。
"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
from list_common_settings import PAGES, ROOT, CONTROL_RE, read_rc  # noqa: E402
from list_type_settings import TYPE_PAGES  # noqa: E402

RESOURCES = os.path.join(ROOT, "macos", "app", "Resources")

# 第 48 步：各语言的资源文件和输出的子文件夹（Mac 的 .lproj）
LANGUAGES = [
    ("sakura_core/sakura_rc.rc", "ja.lproj"),
    ("sakura_lang/sakura_rc_en-US.rc", "en.lproj"),
    ("sakura_lang/sakura_rc_zh-CN.rc", "zh-Hans.lproj"),
]

# 页 → 原版的页名的字符串（CPropCommon::DoPropertySheet、CPropTypes::DoPropertySheet）
PAGE_TITLES = {
    "IDD_PROP_GENERAL": "STR_PROPCOMMON_GENERAL", "IDD_PROP_WIN": "STR_PROPCOMMON_WINDOW",
    "IDD_PROP_MAINMENU": "STR_PROPCOMMON_MAINMENU", "IDD_PROP_TOOLBAR": "STR_PROPCOMMON_TOOLBAR",
    "IDD_PROP_TAB": "STR_PROPCOMMON_TABS", "IDD_PROP_STATUSBAR": "STR_PROPCOMMON_STATBAR",
    "IDD_PROP_EDIT": "STR_PROPCOMMON_EDITING", "IDD_PROP_FILE": "STR_PROPCOMMON_FILE",
    "IDD_PROP_FNAME": "STR_PROPCOMMON_FILENAME", "IDD_PROP_BACKUP": "STR_PROPCOMMON_BACKUP",
    "IDD_PROP_FORMAT": "STR_PROPCOMMON_FORMAT", "IDD_PROP_GREP": "STR_PROPCOMMON_SEARCH",
    "IDD_PROP_KEYBIND": "STR_PROPCOMMON_KEYS", "IDD_PROP_CUSTMENU": "STR_PROPCOMMON_CUSTMENU",
    "IDD_PROP_KEYWORD": "STR_PROPCOMMON_KEYWORD", "IDD_PROP_HELPER": "STR_PROPCOMMON_SUPPORT",
    "IDD_PROP_MACRO": "STR_PROPCOMMON_MACRO", "IDD_PROP_PLUGIN": "STR_PROPCOMMON_PLUGIN",
    "IDD_PROP_SCREEN": "STR_PROPTYPE_SCREEN", "IDD_PROP_COLOR": "STR_PROPTYPE_COLOR",
    "IDD_PROP_WINDOW": "STR_PROPTYPE_WINDOW", "IDD_PROP_SUPPORT": "STR_PROPTYPE_SUPPORT",
    "IDD_PROP_REGEX": "STR_PROPTYPE_REGEX_KEYWORD", "IDD_PROP_KEYHELP": "STR_PROPTYPE_KEYWORD_HELP",
}

# 从共通設定的页打开的对话框（第 39 步）。名字是模板的 CAPTION
DIALOGS = [
    "IDD_WINPOSSIZE",	# ウィンドウ > 位置と大きさの設定（原版 CDlgWinSize）
]

# アウトライン解析（第 42 步。原版 CDlgFuncList）
OUTLINE_DIALOGS = [
    "IDD_FUNCLIST",
    "IDD_FILETREE",	# ファイルツリー設定（第 43 步。原版 CDlgFileTree）
]

# Grep・Grep置換（第 43 步。原版 CDlgGrep、CDlgGrepReplace、CDlgGrepRunning）
GREP_DIALOGS = [
    "IDD_GREP",
    "IDD_GREP_REPLACE",
    "IDD_GREPRUNNING",
]

# 编辑辅助功能（第 44 步。原版 CDlgDiff、CDlgCompare、CDlgTagJumpList）
EDIT_SUPPORT_DIALOGS = [
    "IDD_DIFF",
    "IDD_COMPARE",
    "IDD_TAGJUMPLIST",
]

# ファイルの安全機能（第 46 步。原版 CDlgFileUpdateQuery）
FILE_SAFETY_DIALOGS = [
    "IDD_FILEUPDATEQUERY",
]

# 印刷（第 47 步。原版 CDlgPrintSetting、CPrintPreview の操作バー、印刷中の CDlgCancel）
PRINT_DIALOGS = [
    "IDD_PRINTSETTING",
    "IDD_PRINTPREVIEWBAR",
    "IDD_PRINTING",
]

# 从タイプ別設定的页打开的对话框（第 40 步）
TYPE_DIALOGS = [
    "IDD_SAMECOLOR",				# カラー > 文字色統一・背景色統一（原版 CDlgSameColor）
    "IDD_DIALOG_KEYWORD_SELECT",	# カラー > 強調キーワード 2～10（原版 CDlgKeywordSelect）
    "IDD_TYPELIST",				# 設定 > タイプ別設定一覧（原版 CDlgTypeList）
    "IDD_TYPE_ASCERTAIN",			# タイプ別設定一覧 > インポート の確認（原版 CDlgTypeAscertain）
]


def text_of(raw):
    """rc 的文字 → 显示的文字：&X 的 & 去掉（&& 是 &），\\n、\\r 是换行，\\\\ 是一个 \\（第 48 步）"""
    s = raw.replace('""', '"').replace("&&", "\0").replace("&", "").replace("\0", "&")
    s = s.replace("\\\\", "\x01")
    s = s.replace("\\r\\n", "\n").replace("\\n", "\n").replace("\\r", "\n").replace("\\t", "\t")
    return s.replace("\x01", "\\")


def kind_of(word, cls, style):
    """控件的种类（App 里用的名字）"""
    if word == "CONTROL":
        if cls == "Button":
            if "RADIO" in style:
                return "radio"
            if "CHECKBOX" in style:
                return "check"
            if "GROUPBOX" in style:
                return "group"
            return "button"
        return {
            "msctls_updown32": "spin", "msctls_hotkey32": "hotkey", "SysListView32": "listview",
            "SysTreeView32": "tree", "Static": "label", "msctls_trackbar32": "slider", "Edit": "edit", "ComboBox": "combo", "ListBox": "list",
        }.get(cls, "unknown")
    return {
        "GROUPBOX": "group", "LTEXT": "label", "RTEXT": "label", "CTEXT": "label", "EDITTEXT": "edit",
        "COMBOBOX": "combo", "LISTBOX": "list", "PUSHBUTTON": "button", "DEFPUSHBUTTON": "button",
        "AUTOCHECKBOX": "check", "CHECKBOX": "check", "AUTORADIOBUTTON": "radio", "RADIOBUTTON": "radio",
        "ICON": "icon",
    }.get(word, "unknown")


def controls(lines, dialog):
    start = next(i for i, l in enumerate(lines) if re.match(rf"^{dialog}\s+DIALOG(?:EX)?\b", l))
    size = [int(v) for v in re.findall(r"\d+", lines[start])[-2:]]
    i = start
    while lines[i].strip() != "BEGIN":
        i += 1
    i += 1
    result = []
    while lines[i].strip() != "END":
        line = lines[i]
        while line.rstrip().endswith((",", "|")):
            i += 1
            line = line.rstrip() + " " + lines[i].strip()
        i += 1
        m = CONTROL_RE.match(line)
        if not m:
            continue
        word, raw, cid, rest = m.groups()
        cls = ""
        if word == "CONTROL":
            mc = re.match(r'\s*"(\w+)"\s*,(.*)$', rest)
            cls, rest = (mc.group(1), mc.group(2)) if mc else ("", rest)
        parts = [p.strip() for p in rest.split(",")]
        if word == "ICON" and not raw and parts and not re.fullmatch(r"-?\d+", parts[0]):
            # ICON 图标名,ID,x,y,…（第 47 步的 IDI_PRINTER）：文字是图标的名字
            raw, cid, parts = cid, parts[0], parts[1:]
        # 样式在前（CONTROL），位置是 4 个数；LTEXT 等是位置在前，后面是样式
        nums = [p for p in parts if re.fullmatch(r"-?\d+", p)]
        if len(nums) < 4:
            continue
        if word == "CONTROL":
            style = parts[0]
            x, y, w, h = (int(v) for v in parts[1:5])
        else:
            x, y, w, h = (int(v) for v in parts[:4])
            style = " ".join(parts[4:])
        kind = kind_of(word, cls, style + " " + word)
        if kind == "unknown":
            continue
        c = {"id": cid, "kind": kind, "frame": [x, y, w, h]}
        if raw:
            c["text"] = text_of(raw)
        flags = []
        if word == "RTEXT" or "SS_RIGHT" in style or "ES_RIGHT" in style:
            flags.append("right")
        if word == "CTEXT" or "SS_CENTER" in style:
            flags.append("center")
        if "ES_NUMBER" in style:
            flags.append("number")
        if "ES_MULTILINE" in style or "BS_MULTILINE" in style:
            flags.append("multiline")
        if "ES_READONLY" in style:
            flags.append("readonly")
        if "NOT WS_VISIBLE" in style:
            flags.append("hidden")
        if "WS_DISABLED" in style:
            flags.append("disabled")
        if "WS_GROUP" in style and "NOT WS_GROUP" not in style:
            flags.append("group")
        if "SS_SUNKEN" in style or "WS_BORDER" in style and kind == "label":
            flags.append("sunken")
        if "CBS_DROPDOWNLIST" in style:
            flags.append("dropdownlist")
        if "BS_PUSHLIKE" in style:
            flags.append("pushlike")
        if flags:
            c["flags"] = flags
        result.append(c)
    return size, result


def caption(lines, dialog):
    start = next(i for i, l in enumerate(lines) if re.match(rf"^{dialog}\s+DIALOG(?:EX)?\b", l))
    for line in lines[start:]:
        m = re.match(r'^CAPTION\s+"(.*)"', line)
        if m:
            return text_of(m.group(1))
        if line.strip() == "BEGIN":
            break
    return dialog


def dump(pages):
    """一个控件一行（差分好看）"""
    out_lines = []
    for n, page in enumerate(pages):
        head = {k: v for k, v in page.items() if k != "controls"}
        out_lines.append(" " + json.dumps(head, ensure_ascii=False)[:-1] + ', "controls": [')
        rows = [json.dumps(c, ensure_ascii=False) for c in page["controls"]]
        out_lines += ["  " + r + ("," if i + 1 < len(rows) else "") for i, r in enumerate(rows)]
        out_lines.append(" ]}" + ("," if n + 1 < len(pages) else ""))
    return out_lines


# 语言包的对话框里缺少的控件（原版的语言包没有更新）：从日文的模板复制位置，文字用这里的
MISSING_CONTROL_TEXT = {
    "sakura_lang/sakura_rc_zh-CN.rc": {
        # IDD_PROP_KEYWORD 的「OK」「キャンセル」（タイプ別設定から一時適用で開いたときだけ表示。原版 zh-CN は未追加）
        ("IDD_PROP_KEYWORD", "IDOK"): "确定",
        ("IDD_PROP_KEYWORD", "IDCANCEL"): "取消(X)",
    },
}
JA_LINES = None


def add_keys(source, dialog, items):
    """IDC_STATIC 的标签在 App 里按文字找（PropPage.label、setEnabled）：英文、中文的加上日文的文字 "key"。
    控件的顺序与日文相同（ID 的顺序在 LocalizationTests 里确认）"""
    if source == "sakura_core/sakura_rc.rc":
        return items
    _, ja_items = controls(read_rc(), dialog)
    for c, j in zip(items, ja_items):
        if c["id"] == "IDC_STATIC" and j["id"] == "IDC_STATIC" and j.get("text") and j.get("text") != c.get("text"):
            c["key"] = j["text"]
    return items


def fill_missing(source, dialog, items):
    """日文的模板有、语言包没有的控件补上（位置照日文）。没有准备文字时报错"""
    global JA_LINES
    if source == "sakura_core/sakura_rc.rc":
        return items
    if JA_LINES is None:
        JA_LINES = read_rc()
    _, ja_items = controls(JA_LINES, dialog)
    have = {(c["id"], c["kind"]) for c in items}
    result = list(items)
    for n, c in enumerate(ja_items):
        if (c["id"], c["kind"]) in have:
            continue
        key = (dialog, c["id"])
        texts = MISSING_CONTROL_TEXT.get(source, {})
        if key not in texts:
            raise SystemExit(f"{source}: {dialog} に {c['id']} がない（MISSING_CONTROL_TEXT に文字を追加すること）")
        copy = dict(c)
        copy["text"] = texts[key]
        result.insert(min(n, len(result)), copy)
    return result


def strings(lines):
    """STRINGTABLE 的字符串（名字 → 显示的文字）"""
    result = {}
    inside = False
    for line in lines:
        if line.strip() == "STRINGTABLE":
            inside = True
            continue
        if inside and line.strip() == "END":
            inside = False
            continue
        if inside:
            m = re.match(r'^\s*(\w+)\s*,?\s*"((?:[^"]|"")*)"', line)
            if m:
                result[m.group(1)] = text_of(m.group(2))
    return result


def write(lines, pages_def, dialog_names, out, source="sakura_core/sakura_rc.rc"):
    table = strings(lines)
    pages = []
    for name, dialog, _ in pages_def:
        size, items = controls(lines, dialog)
        items = add_keys(source, dialog, fill_missing(source, dialog, items))
        title = table.get(PAGE_TITLES.get(dialog, ""), name)
        pages.append({"name": name, "title": title, "dialog": dialog, "size": size, "controls": items})
    dialogs = []
    for dialog in dialog_names:
        size, items = controls(lines, dialog)
        items = add_keys(source, dialog, fill_missing(source, dialog, items))
        dialogs.append({"name": caption(lines, dialog), "dialog": dialog, "size": size, "controls": items})
    out_lines = ['{"source": "' + source + '", "pages": [']
    out_lines += dump(pages)
    out_lines.append('], "dialogs": [')
    out_lines += dump(dialogs)
    out_lines.append("]}")
    data = "\n".join(out_lines)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w", encoding="utf-8", newline="\n") as f:
        f.write(data + "\n")


def main():
    base_dir = sys.argv[1] if len(sys.argv) > 1 else RESOURCES
    for source, sub in LANGUAGES:
        with open(os.path.join(ROOT, source), "rb") as f:
            lines = f.read().decode("utf-16").splitlines()
        out_dir = os.path.join(base_dir, sub) if sub else base_dir
        write(lines, PAGES, DIALOGS, os.path.join(out_dir, "CommonSettingsDialogs.json"), source)
        write(lines, TYPE_PAGES, TYPE_DIALOGS, os.path.join(out_dir, "TypeSettingsDialogs.json"), source)
        write(lines, [], OUTLINE_DIALOGS, os.path.join(out_dir, "OutlineDialogs.json"), source)
        write(lines, [], GREP_DIALOGS, os.path.join(out_dir, "GrepDialogs.json"), source)
        write(lines, [], EDIT_SUPPORT_DIALOGS, os.path.join(out_dir, "EditSupportDialogs.json"), source)
        write(lines, [], FILE_SAFETY_DIALOGS, os.path.join(out_dir, "FileSafetyDialogs.json"), source)
        write(lines, [], PRINT_DIALOGS, os.path.join(out_dir, "PrintDialogs.json"), source)


if __name__ == "__main__":
    main()

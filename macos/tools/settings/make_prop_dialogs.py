#!/usr/bin/env python3
# Copyright (C) 2026, Sakura Editor Organization
#
# SPDX-License-Identifier: Zlib
"""共通設定窗口（计划第 39 步）、タイプ別設定窗口（第 40 步）的各页的布局。

从 sakura_core/sakura_rc.rc 的对话框模板（IDD_PROP_*，和从各页打开的对话框 DIALOGS）取出每个控件的种类、文字、位置（对话框单位），
写成 JSON，App 按它摆放控件（布局、项目、顺序、文字照原版，控件用 Mac 的）。
原版的 rc 改了以后重新运行：python3 make_prop_dialogs.py
（输出 macos/app/Resources/CommonSettingsDialogs.json、TypeSettingsDialogs.json、
第 42 步的アウトライン解析 OutlineDialogs.json、第 43 步的 Grep GrepDialogs.json）
"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
from list_common_settings import PAGES, ROOT, CONTROL_RE, read_rc  # noqa: E402
from list_type_settings import TYPE_PAGES  # noqa: E402

RESOURCES = os.path.join(ROOT, "macos", "app", "Resources")

# 从共通設定的页打开的对话框（第 39 步）。名字是模板的 CAPTION
DIALOGS = [
    "IDD_WINPOSSIZE",	# ウィンドウ > 位置と大きさの設定（原版 CDlgWinSize）
]

# アウトライン解析（第 42 步。原版 CDlgFuncList）
OUTLINE_DIALOGS = [
    "IDD_FUNCLIST",
]

# Grep・Grep置換（第 43 步。原版 CDlgGrep、CDlgGrepReplace、CDlgGrepRunning）
GREP_DIALOGS = [
    "IDD_GREP",
    "IDD_GREP_REPLACE",
    "IDD_GREPRUNNING",
]

# 从タイプ別設定的页打开的对话框（第 40 步）
TYPE_DIALOGS = [
    "IDD_SAMECOLOR",				# カラー > 文字色統一・背景色統一（原版 CDlgSameColor）
    "IDD_DIALOG_KEYWORD_SELECT",	# カラー > 強調キーワード 2～10（原版 CDlgKeywordSelect）
    "IDD_TYPELIST",				# 設定 > タイプ別設定一覧（原版 CDlgTypeList）
    "IDD_TYPE_ASCERTAIN",			# タイプ別設定一覧 > インポート の確認（原版 CDlgTypeAscertain）
]


def text_of(raw):
    """rc 的文字 → 显示的文字：&X 的 & 去掉（&& 是 &），\\n、\\r 是换行"""
    s = raw.replace('""', '"').replace("&&", "\0").replace("&", "").replace("\0", "&")
    s = s.replace("\\r\\n", "\n").replace("\\n", "\n").replace("\\r", "\n").replace("\\t", "\t")
    return s


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


def write(lines, pages_def, dialog_names, out):
    pages = []
    for name, dialog, _ in pages_def:
        size, items = controls(lines, dialog)
        pages.append({"name": name, "dialog": dialog, "size": size, "controls": items})
    dialogs = []
    for dialog in dialog_names:
        size, items = controls(lines, dialog)
        dialogs.append({"name": caption(lines, dialog), "dialog": dialog, "size": size, "controls": items})
    out_lines = ['{"source": "sakura_core/sakura_rc.rc", "pages": [']
    out_lines += dump(pages)
    out_lines.append('], "dialogs": [')
    out_lines += dump(dialogs)
    out_lines.append("]}")
    data = "\n".join(out_lines)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w", encoding="utf-8", newline="\n") as f:
        f.write(data + "\n")


def main():
    lines = read_rc()
    out_dir = sys.argv[1] if len(sys.argv) > 1 else RESOURCES
    write(lines, PAGES, DIALOGS, os.path.join(out_dir, "CommonSettingsDialogs.json"))
    write(lines, TYPE_PAGES, TYPE_DIALOGS, os.path.join(out_dir, "TypeSettingsDialogs.json"))
    write(lines, [], OUTLINE_DIALOGS, os.path.join(out_dir, "OutlineDialogs.json"))
    write(lines, [], GREP_DIALOGS, os.path.join(out_dir, "GrepDialogs.json"))


if __name__ == "__main__":
    main()

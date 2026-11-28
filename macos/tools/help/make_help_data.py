#!/usr/bin/env python3
# Copyright (C) 2026, Sakura Editor Organization
#
# SPDX-License-Identifier: Zlib
"""帮助（计划第 49 步）：从原版的 HTML 帮助的工程文件生成 App 用的数据 macos/app/Resources/HelpTopics.json。

原版的 help/sakura（sakura.chm）和 help/macro（macro.chm）的 HTML 原样放进 App（project.yml 的文件夹引用），
这个工具只把 HTML Help Workshop 的工程文件转换成 JSON：

- toc：目次（sakura.hhc。原版用 Merge 合并的 macro.chm 的目次 macro.hhc 放在同样的位置；
  plugin.chm 是 Mac 版没有的プラグイン，ppa.chm、script56.chm 不在原版的仓库里，不合并）
- index：キーワード（sakura.hhk、macro.hhk）
- topics：话题编号 → 页（sakura.hhp 的 [ALIAS] + [MAP] 的 sakura.hh。原版 MyWinHelp 的 HELP_CONTEXT）
- popups：控件的说明（Cshelp.txt 的 .topic。原版 MyWinHelp 的 HELP_CONTEXTMENU、HELP_WM_HELP）
- controls：各对话框的控件 → 说明的编号（原版各对话框的 p_helpids）
- notes：Mac 版的注记（mac_notes.json，手写），App 显示页时插在页的开头

原版的帮助或代码改了以后重新运行：python3 make_help_data.py
--check：只比较，与仓库里的 HelpTopics.json 不同时返回 1（CI）
"""
import html
import json
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
OUTPUT = os.path.join(ROOT, "macos", "app", "Resources", "HelpTopics.json")
NOTES = os.path.join(os.path.dirname(__file__), "mac_notes.json")

# App 里的文件夹（project.yml 的文件夹引用）→ 原版的文件夹
BOOKS = {
    "sakura": "help/sakura",
    "macro": "help/macro",
}
# Mac 版自己的页（Resources/HelpMac.html）。放在目次的开头
MAC_PAGE = "HelpMac.html"
MAC_PAGE_TITLE = "Mac 版について"

# 原版的 p_helpids 所在的文件 → 对话框（sakura_rc.rc 的 IDD_*。Mac 版的布局 JSON 的 "dialog"）
HELPID_FILES = {
    "sakura_core/dlg/CDlgExec.cpp": "IDD_EXEC",
    "sakura_core/dlg/CDlgProfileMgr.cpp": "IDD_PROFILEMGR",
    "sakura_core/dlg/CDlgFavorite.cpp": "IDD_FAVORITE",
    "sakura_core/dlg/CDlgProperty.cpp": "IDD_PROPERTY_FILE",
    "sakura_core/dlg/CDlgCtrlCode.cpp": "IDD_CTRLCODE",
    "sakura_core/dlg/CDlgGrepReplace.cpp": "IDD_GREP_REPLACE",
    "sakura_core/dlg/CDlgOpenFile_CommonFileDialog.cpp": "IDD_FILEOPEN",
    "sakura_core/dlg/CDlgWindowList.cpp": "IDD_WINLIST",
    "sakura_core/dlg/CDlgInput1.cpp": "IDD_INPUT1",
    "sakura_core/dlg/CDlgFind.cpp": "IDD_FIND",
    "sakura_core/dlg/CDlgPluginOption.cpp": "IDD_PLUGIN_OPTION",
    "sakura_core/dlg/CDlgDiff.cpp": "IDD_DIFF",
    "sakura_core/dlg/CDlgPrintSetting.cpp": "IDD_PRINTSETTING",
    "sakura_core/dlg/CDlgSetCharSet.cpp": "IDD_SETCHARSET",
    "sakura_core/dlg/CDlgWinSize.cpp": "IDD_WINPOSSIZE",
    "sakura_core/dlg/CDlgGrep.cpp": "IDD_GREP",
    "sakura_core/dlg/CDlgJump.cpp": "IDD_JUMP",
    "sakura_core/dlg/CDlgAbout.cpp": "IDD_ABOUT",
    "sakura_core/dlg/CDlgCompare.cpp": "IDD_COMPARE",
    "sakura_core/dlg/CDlgTagsMake.cpp": "IDD_TAG_MAKE",
    "sakura_core/dlg/CDlgReplace.cpp": "IDD_REPLACE",
    "sakura_core/dlg/CDlgTagJumpList.cpp": "IDD_TAGJUMPLIST",
    "sakura_core/typeprop/CPropTypesColor.cpp": "IDD_PROP_COLOR",
    "sakura_core/typeprop/CPropTypesSupport.cpp": "IDD_PROP_SUPPORT",
    "sakura_core/typeprop/CPropTypesKeyHelp.cpp": "IDD_PROP_KEYHELP",
    "sakura_core/typeprop/CDlgTypeAscertain.cpp": "IDD_TYPE_ASCERTAIN",
    "sakura_core/typeprop/CDlgKeywordSelect.cpp": "IDD_DIALOG_KEYWORD_SELECT",
    "sakura_core/typeprop/CPropTypesScreen.cpp": "IDD_PROP_SCREEN",
    "sakura_core/typeprop/CPropTypesWindow.cpp": "IDD_PROP_WINDOW",
    "sakura_core/typeprop/CDlgTypeList.cpp": "IDD_TYPELIST",
    "sakura_core/typeprop/CDlgSameColor.cpp": "IDD_SAMECOLOR",
    "sakura_core/typeprop/CPropTypesRegex.cpp": "IDD_PROP_REGEX",
    "sakura_core/outline/CDlgFuncList.cpp": "IDD_FUNCLIST",
    "sakura_core/outline/CDlgFileTree.cpp": "IDD_FILETREE",
    "sakura_core/prop/CPropComMainMenu.cpp": "IDD_PROP_MAINMENU",
    "sakura_core/prop/CPropComCustmenu.cpp": "IDD_PROP_CUSTMENU",
    "sakura_core/prop/CPropComEdit.cpp": "IDD_PROP_EDIT",
    "sakura_core/prop/CPropComStatusbar.cpp": "IDD_PROP_STATUSBAR",
    "sakura_core/prop/CPropComPlugin.cpp": "IDD_PROP_PLUGIN",
    "sakura_core/prop/CPropComToolbar.cpp": "IDD_PROP_TOOLBAR",
    "sakura_core/prop/CPropComTab.cpp": "IDD_PROP_TAB",
    "sakura_core/prop/CPropComBackup.cpp": "IDD_PROP_BACKUP",
    "sakura_core/prop/CPropComHelper.cpp": "IDD_PROP_HELPER",
    "sakura_core/prop/CPropComFormat.cpp": "IDD_PROP_FORMAT",
    "sakura_core/prop/CPropComGeneral.cpp": "IDD_PROP_GENERAL",
    "sakura_core/prop/CPropComGrep.cpp": "IDD_PROP_GREP",
    "sakura_core/prop/CPropComWin.cpp": "IDD_PROP_WIN",
    "sakura_core/prop/CPropComFileName.cpp": "IDD_PROP_FNAME",
    "sakura_core/prop/CPropComMacro.cpp": "IDD_PROP_MACRO",
    "sakura_core/prop/CPropComFile.cpp": "IDD_PROP_FILE",
    "sakura_core/prop/CPropComKeyword.cpp": "IDD_PROP_KEYWORD",
    "sakura_core/prop/CPropComKeybind.cpp": "IDD_PROP_KEYBIND",
}


def read(path):
    with open(os.path.join(ROOT, path), encoding="utf-8-sig") as f:
        return f.read()


def book_path(book, local):
    """hhc・hhk・hhp 的 Local（res\\HLP000001.html#c901）→ App 里的路径（sakura/res/HLP000001.html#c901）"""
    return book + "/" + local.replace("\\", "/")


# ----- 目次・キーワード（HTML Help Workshop 的 sitemap 格式）-----

TOKEN_RE = re.compile(r"<\s*(/?)\s*(ul|li|object)\b([^>]*)>|<\s*param\b([^>]*)>", re.I)
ATTR_RE = re.compile(r'(\w+)\s*=\s*"([^"]*)"')


def parse_sitemap(text):
    """sitemap → 树：[{"params": [(name, value), ...], "children": [...]}]。
    原版的文件里有缺少 </OBJECT> 的项目：下一个 <LI>、<UL>、</UL> 也结束项目（与 HTML Help 相同）"""
    root = []
    stack = [root]
    current = None	# 读着的 OBJECT 的项目
    last = None		# 这一层最后的项目（下一个 <UL> 是它的子项目）
    for m in TOKEN_RE.finditer(text):
        closing, tag, attrs, param = m.group(1), (m.group(2) or "").lower(), m.group(3), m.group(4)
        if param is not None:
            if current is not None:
                a = dict((k.lower(), html.unescape(v)) for k, v in ATTR_RE.findall(param))
                if "name" in a and "value" in a:
                    current["params"].append((a["name"], a["value"]))
            continue
        if tag == "object":
            if closing:
                current = None
            else:
                a = dict((k.lower(), v) for k, v in ATTR_RE.findall(attrs))
                if a.get("type", "").lower() == "text/sitemap":
                    current = {"params": [], "children": []}
                    stack[-1].append(current)
                    last = current
                else:
                    current = None	# text/site properties
            continue
        current = None
        if tag == "ul":
            if closing:
                if len(stack) > 1:
                    stack.pop()
                last = None
            else:
                parent = last["children"] if last is not None else stack[-1]
                stack.append(parent)
                last = None
    return root


def values(item, name):
    return [v for k, v in item["params"] if k.lower() == name.lower()]


def toc_nodes(items, book, merges):
    nodes = []
    for item in items:
        merge = values(item, "Merge")
        if merge:
            nodes.extend(merges.get(merge[0].split("::")[0].lower(), []))
            continue
        names, locals_ = values(item, "Name"), values(item, "Local")
        node = {"t": names[0] if names else ""}
        if locals_:
            node["p"] = book_path(book, locals_[0])
        children = toc_nodes(item["children"], book, merges)
        if children:
            node["c"] = children
        nodes.append(node)
    return nodes


def index_entries(items, book, level=0):
    entries = []
    for item in items:
        names, locals_ = values(item, "Name"), values(item, "Local")
        if not names:
            continue
        # 一个关键字有几个话题时：Name（关键字）, Name（话题的名字）, Local, Name, Local, …
        if len(names) == len(locals_) + 1:
            topics = [[n, book_path(book, p)] for n, p in zip(names[1:], locals_)]
        else:
            topics = [[names[0], book_path(book, p)] for p in locals_]
        entry = {"k": names[0], "p": topics}
        if level:
            entry["l"] = level
        entries.append(entry)
        entries.extend(index_entries(item["children"], book, level + 1))
    return entries


# ----- 话题编号・控件的说明 -----

def help_defines():
    """sakura.hh：HLP000001 等 → 编号"""
    defines = {}
    for m in re.finditer(r"^\s*#define\s+(\w+)\s+(\d+)", read("src/main/resources/sakura.hh"), re.M):
        defines[m.group(1)] = int(m.group(2))
    return defines


def topics(defines):
    text = read(BOOKS["sakura"] + "/sakura.hhp")
    alias = re.search(r"^\[ALIAS\]\s*$(.*?)^\[", text, re.M | re.S).group(1)
    result = {}
    for m in re.finditer(r"^\s*(\w+)\s*=\s*(\S+)\s*$", alias, re.M):
        if m.group(1) in defines:
            result[str(defines[m.group(1)])] = book_path("sakura", m.group(2))
    # [ALIAS] にない話題（HLP000339 等。原版の F1 はオンラインヘルプ HLP%06d.html に代わる）：同じ名前のページ
    for name, number in defines.items():
        page = f"res\\{name}.html"
        if re.fullmatch(r"HLP\d{6}", name) and str(number) not in result and os.path.exists(os.path.join(BOOKS["sakura"], page.replace("\\", "/"))):
            result[str(number)] = book_path("sakura", page)
    return dict(sorted(result.items(), key=lambda kv: int(kv[0])))


def popups():
    """Cshelp.txt：.topic 编号 + 文字（下一个 .topic 之前）"""
    result = {}
    parts = re.split(r"^\.topic\s+(\d+)\s*$", read(BOOKS["sakura"] + "/Cshelp.txt"), flags=re.M)
    for number, body in zip(parts[1::2], parts[2::2]):
        result[number] = body.strip("\r\n").replace("\r\n", "\n").rstrip()
    return dict(sorted(result.items(), key=lambda kv: int(kv[0])))


def controls(defines):
    result = {}
    for path, dialog in HELPID_FILES.items():
        text = read(path)
        tables = re.findall(r"DWORD\s+\w*helpids\w*\s*\[\s*\]\s*=\s*\{(.*?)\};", text, re.S | re.I)
        if len(tables) != 1:
            raise SystemExit(f"{path}: p_helpids が {len(tables)} 個")
        table = {}
        # 先去掉行注释（//…）
        body = re.sub(r"//[^\n]*", "", tables[0])
        for idc, hid in re.findall(r"\b(ID\w+)\s*,\s*(HID\w+)\s*,", body):
            if hid in defines:
                table[idc] = defines[hid]
        result[dialog] = table
    return dict(sorted(result.items()))


def build():
    merges = {}
    for book in ("macro",):
        merges[book + ".chm"] = toc_nodes(parse_sitemap(read(BOOKS[book] + f"/{book}.hhc")), book, {})
    toc = [{"t": MAC_PAGE_TITLE, "p": MAC_PAGE}]
    toc += toc_nodes(parse_sitemap(read(BOOKS["sakura"] + "/sakura.hhc")), "sakura", merges)
    index = []
    for book in ("sakura", "macro"):
        index += index_entries(parse_sitemap(read(BOOKS[book] + f"/{book}.hhk")), book)
    index.append({"k": MAC_PAGE_TITLE, "p": [[MAC_PAGE_TITLE, MAC_PAGE]]})
    defines = help_defines()
    with open(NOTES, encoding="utf-8") as f:
        notes = json.load(f)
    return {
        "source": "help/sakura, help/macro, src/main/resources/sakura.hh, sakura_core（p_helpids）, macos/tools/help/mac_notes.json",
        "title": "サクラエディタ ヘルプ",
        "home": book_path("sakura", "res\\HLP000001.html"),
        "toc": toc,
        "index": index,
        "topics": topics(defines),
        "popups": popups(),
        "controls": controls(defines),
        "notes": {k: v for k, v in notes.items() if not k.startswith("_")},
        "noteLabel": notes["_label"],
        "unavailableNote": notes["_unavailable"],
    }


def main():
    text = json.dumps(build(), ensure_ascii=False, indent=0, separators=(",", ":")) + "\n"
    if "--check" in sys.argv:
        with open(OUTPUT, encoding="utf-8") as f:
            if f.read() != text:
                print("HelpTopics.json は make_help_data.py の結果と違います。python3 macos/tools/help/make_help_data.py を実行してください")
                return 1
        return 0
    with open(OUTPUT, "w", encoding="utf-8") as f:
        f.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())

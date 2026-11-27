#!/usr/bin/env python3
# Copyright (C) 2026, Sakura Editor Organization
# SPDX-License-Identifier: Zlib
"""Mac 版自己的界面文字的翻译（计划第 48 步）。

App 的 Swift 源代码里 `L10n.tr("日文", comment: "…")` 的文字（键是日文），
生成英文、简体中文的 macos/app/Resources/{en,zh-Hans}.lproj/Localizable.strings。翻译按下面的顺序找：
1. macos/tools/l10n/translations.json（Mac 版自己的翻译，和要改原版语言包的译文时）
2. 原版的语言包：日文的资源文件（sakura_core/sakura_rc.rc）里有同样文字的字符串、对话框的控件、菜单，
   用语言包（sakura_lang/sakura_rc_en-US.rc、sakura_rc_zh-CN.rc）的同一个地方的文字
找不到翻译的键列出来，返回 1（LocalizationTests 也确认没有遗漏）。

用法: python3 macos/tools/l10n/make_strings.py [--check]
  --check：不写文件，只确认生成的结果与仓库里的相同
"""
import json
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
SOURCES = os.path.join(ROOT, "macos", "app", "Sources")
RESOURCES = os.path.join(ROOT, "macos", "app", "Resources")
TRANSLATIONS = os.path.join(os.path.dirname(__file__), "translations.json")
LANGS = [("en", "sakura_lang/sakura_rc_en-US.rc", "en.lproj"), ("zh", "sakura_lang/sakura_rc_zh-CN.rc", "zh-Hans.lproj")]

SWIFT_STRING = r'"((?:[^"\\]|\\.)*)"'
CALL_RE = re.compile(r'L10n\.tr\(\s*' + SWIFT_STRING + r'\s*,\s*comment:\s*' + SWIFT_STRING + r'\s*\)', re.S)


def swift_unescape(s):
    out, i = [], 0
    simple = {"n": "\n", "t": "\t", "r": "\r", "\\": "\\", '"': '"', "'": "'", "0": "\0"}
    while i < len(s):
        if s[i] == "\\" and i + 1 < len(s):
            n = s[i + 1]
            if n in simple:
                out.append(simple[n]); i += 2; continue
            if n == "u":
                m = re.match(r"\{([0-9A-Fa-f]+)\}", s[i + 2:])
                if m:
                    out.append(chr(int(m.group(1), 16))); i += 2 + len(m.group(0)); continue
            raise ValueError("unsupported escape in " + s)
        out.append(s[i]); i += 1
    return "".join(out)


def keys_in_sources():
    """键 → 第一个注释"""
    keys = {}
    for name in sorted(os.listdir(SOURCES)):
        if not name.endswith(".swift") or name == "Localization.swift":
            continue
        text = open(os.path.join(SOURCES, name), encoding="utf-8").read()
        for m in CALL_RE.finditer(text):
            if "\\(" in m.group(1):
                raise SystemExit(f"{name}: L10n.tr の文字に \\( は使えない: {m.group(1)}")
            keys.setdefault(swift_unescape(m.group(1)), swift_unescape(m.group(2)))
        if text.count("L10n.tr(") != len(CALL_RE.findall(text)):
            raise SystemExit(f"{name}: L10n.tr の引数は文字列リテラルと comment: の文字列リテラルにすること")
    return keys


def read_rc(path):
    raw = open(os.path.join(ROOT, path), "rb").read()
    return raw.decode("utf-16").replace("\r\n", "\n")


def rc_unescape(s):
    s = s.replace('""', '"')
    return s.replace("\\r\\n", "\n").replace("\\n", "\n").replace("\\r", "\n").replace("\\t", "\t").replace("\\\\", "\\")


def display(s):
    """& 的快捷字母去掉（&& 是 &），与 make_prop_dialogs.py 的 text_of 相同。语言包里的 \\< \\> 是 < >"""
    return s.replace("&&", "\0").replace("&", "").replace("\0", "&").replace("\\<", "<").replace("\\>", ">")


def rc_entries(text):
    """位置 → 文字：STRINGTABLE（S:名字）、对话框的控件（D:对话框:ID:序号）、标题（C:对话框）、菜单（M:菜单:序号）"""
    result = {}
    for block in re.findall(r"^STRINGTABLE\b[^\n]*\nBEGIN\n(.*?)^END", text, re.M | re.S):
        for m in re.finditer(r'^\s*(\w+)\s*,?\s*"((?:[^"]|"")*)"', block, re.M):
            result["S:" + m.group(1)] = rc_unescape(m.group(2))
    for m in re.finditer(r"^(\w+)\s+DIALOG(?:EX)?\b[^\n]*\n(.*?)^BEGIN\n(.*?)^END", text, re.M | re.S):
        name, head, body = m.groups()
        c = re.search(r'^CAPTION\s+"((?:[^"]|"")*)"', head, re.M)
        if c:
            result["C:" + name] = rc_unescape(c.group(1))
        body = re.sub(r"[,|]\s*\n\s*", ", ", body)
        for n, cm in enumerate(re.finditer(r'^\s*\w+\s+"((?:[^"]|"")*)"\s*,\s*(\w+)', body, re.M)):
            result[f"D:{name}:{cm.group(2)}:{n}"] = rc_unescape(cm.group(1))
    for m in re.finditer(r"^(\w+)\s+MENU(?:EX)?\b[^\n]*\n(BEGIN\n.*?^END)\s*$", text, re.M | re.S):
        for n, im in enumerate(re.finditer(r'(?:POPUP|MENUITEM)\s+"((?:[^"]|"")*)"', m.group(2))):
            result[f"M:{m.group(1)}:{n}"] = rc_unescape(im.group(1))
    return result


MNEMONIC = re.compile(r"\((?:&)?[A-Za-z]\)(?=\s*(?:\.\.\.|…|:|：)?\s*$)")


def loose(s):
    """比较用：快捷字母「(X)」、「...」、前后的空白不算"""
    s = re.sub(r"\((?:&)?[A-Za-z0-9]\)", "", s)
    return s.replace("...", "").replace("…", "").strip()


def rc_map(lang_path):
    ja = rc_entries(read_rc("sakura_core/sakura_rc.rc"))
    other = rc_entries(read_rc(lang_path))
    exact, approx = {}, {}
    for pos, text in ja.items():
        if pos not in other or not text.strip():
            continue
        exact.setdefault(display(text), display(other[pos]))
        approx.setdefault(loose(display(text)), display(other[pos]))
    return exact, approx


def strings_escape(s):
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\t", "\\t")


def translate(keys):
    manual = json.load(open(TRANSLATIONS, encoding="utf-8")) if os.path.exists(TRANSLATIONS) else {}
    results, missing = {}, []
    for lang, path, _ in LANGS:
        exact, approx = rc_map(path)
        table = {}
        for key in keys:
            value = manual.get(key, {}).get(lang)
            if value is None:
                value = exact.get(key)
            if value is None and loose(key) in approx:
                value = approx[loose(key)]
                # 快捷字母：日文的键有「(X)」时中文也加（英文的习惯是没有）
            if value is None:
                missing.append((lang, key))
                continue
            if not MNEMONIC.search(key):
                # 日文的键没有快捷字母「(X)」时，翻译也不要（语言包的同じ文字の別の場所には付いている）
                value = MNEMONIC.sub("", value)
            table[key] = value
        results[lang] = table
    return results, missing


def render(table, keys):
    lines = ["/* 由 macos/tools/l10n/make_strings.py 生成（第 48 步）。键是 App 的日文，翻译改 translations.json 后重新生成 */", ""]
    for key in sorted(table):
        lines.append(f'/* {keys[key]} */')
        lines.append(f'"{strings_escape(key)}" = "{strings_escape(table[key])}";')
    return "\n".join(lines) + "\n"


def main():
    check = "--check" in sys.argv
    keys = keys_in_sources()
    results, missing = translate(keys)
    for lang, key in missing:
        print(f"翻訳がない（{lang}）: {key!r}", file=sys.stderr)
    status = 1 if missing else 0
    for lang, _, sub in LANGS:
        out = os.path.join(RESOURCES, sub, "Localizable.strings")
        data = render(results[lang], keys)
        if check:
            old = open(out, encoding="utf-8").read() if os.path.exists(out) else ""
            if old != data:
                print(f"{out} が古い（make_strings.py を実行すること）", file=sys.stderr)
                status = 1
        else:
            with open(out, "w", encoding="utf-8", newline="\n") as f:
                f.write(data)
    print(f"{len(keys)} 個の文字列")
    return status


if __name__ == "__main__":
    sys.exit(main())

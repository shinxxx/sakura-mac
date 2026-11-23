#!/usr/bin/env python3
# Copyright (C) 2026, Sakura Editor Organization
#
# SPDX-License-Identifier: Zlib
"""原版「タイプ別設定」各页的设置项清单（计划第 40 步）。

从 sakura_core/sakura_rc.rc 的对话框模板（IDD_PROP_SCREEN 等）取出每个控件和它的文字，
再从 sakura_core/typeprop/CPropTypes*.cpp 找出这个控件读写的 STypeConfig 成员（m_Types.m_xxx），
从 CShareData_IO.cpp 的 ShareData_IO_TypeConfig 找出 sakura.ini 的项目（节是 [Types(N)]）。
输出 CSV（UTF-8 BOM，Excel 能直接打开）：页、控件 ID、种类、文字、成员、sakura.ini 的项目、Mac 版的处理。
结果放在 macos/docs/type-settings.csv。

用法：python3 list_type_settings.py [输出文件]（默认输出到标准输出）
"""
import csv
import io
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
from list_common_settings import ROOT, dialog_controls, read_rc  # noqa: E402

# 原版 CPropTypes::DoPropertySheet 的页的顺序：(页名, 对话框, 源文件)
TYPE_PAGES = [
    ("スクリーン", "IDD_PROP_SCREEN", "CPropTypesScreen.cpp"),
    ("カラー", "IDD_PROP_COLOR", "CPropTypesColor.cpp"),
    ("ウィンドウ", "IDD_PROP_WINDOW", "CPropTypesWindow.cpp"),
    ("支援", "IDD_PROP_SUPPORT", "CPropTypesSupport.cpp"),
    ("正規表現キーワード", "IDD_PROP_REGEX", "CPropTypesRegex.cpp"),
    ("キーワードヘルプ", "IDD_PROP_KEYHELP", "CPropTypesKeyHelp.cpp"),
]

MEMBER_RE = re.compile(r"m_Types\.((?:m_\w+\.)*m_\w+)")
IO_RE = re.compile(r'LTEXT\("(\w+)"\)\s*,\s*(?:StringBufferW\()?\s*types\.((?:m_\w+\.)*m_\w+)')

# nInts（ShareData_IO_TypeInts：逗号分隔的 12 个数）
NINTS = ["m_nIdx", "m_nMaxLineKetas", "m_nColumnSpace", "m_nTabSpace", "m_nKeyWordSetIdx[0]", "m_nKeyWordSetIdx[1]",
         "m_nStringType", "m_bLineNumIsCRLF", "m_nLineTermType", "m_bWordWrap", "m_nCurrentPrintSetting", "m_nTsvMode"]

# 成员的名字找不到 sakura.ini 的项目的控件（组合框、单选按钮、用别的函数读写的）：按 CShareData_IO.cpp 手工补上
INI_OVERRIDES = {
    # スクリーン
    "IDC_EDIT_TYPENAME": "szTypeName", "IDC_EDIT_TABVIEWSTRING": "szTabViewString", "IDC_CHECK_KINSOKUHIDE": "bKinsokuHide",
    "IDC_COMBO_WRAPMETHOD": "nTextWrapMethod",
    "IDC_EDIT_MAXLINELEN": "nInts（2 番目）", "IDC_EDIT_CHARSPACE": "nInts（3 番目）", "IDC_EDIT_TABSPACE": "nInts（4 番目）",
    "IDC_EDIT_LINESPACE": "nLineSpace", "IDC_CHECK_TAB_ARROW": "bTabArrow", "IDC_COMBO_TSV_MODE": "nInts（12 番目）",
    "IDC_COMBO_SMARTINDENT": "nSmartIndent", "IDC_COMBO_INDENTLAYOUT": "nIndentLayout",
    "IDC_RADIO_OUTLINEDEFAULT": "nDefaultOutline", "IDC_RADIO_OUTLINERULEFILE": "nDefaultOutline",
    "IDC_COMBO_OUTLINES": "nDefaultOutline", "IDC_CHECK_WORDWRAP": "nInts（10 番目）",
    "IDC_STATIC_TYPEFONT": "lf, nPointSize, lfFaceName", "IDC_BUTTON_TYPEFONT": "lf, nPointSize, lfFaceName",
    "IDC_CHECK_USETYPEFONT": "bUseTypeFont",
    # ウィンドウ
    "IDC_COMBO_IMESWITCH": "nImeState（下位 2 ビット）", "IDC_COMBO_IMESTATE": "nImeState（上位）",
    "IDC_COMBO_DEFAULT_CODETYPE": "eDefaultCodetype", "IDC_CHECK_CP": "eDefaultCodetype",
    "IDC_COMBO_DEFAULT_EOLTYPE": "eDefaultEoltype", "IDC_CHECK_DEFAULT_BOM": "bDefaultBom",
    "IDC_CHECK_PRIOR_CESU8": "bPriorCesu8",
    "IDC_RADIO_LINENUM_LAYOUT": "nInts（8 番目）", "IDC_RADIO_LINENUM_CRLF": "nInts（8 番目）",
    "IDC_RADIO_LINETERMTYPE0": "nInts（9 番目）", "IDC_RADIO_LINETERMTYPE1": "nInts（9 番目）",
    "IDC_RADIO_LINETERMTYPE2": "nInts（9 番目）", "IDC_EDIT_LINETERMCHAR": "cLineTermChar",
    "IDC_EDIT_LINENUMWIDTH": "nLineNumWidth",
    "IDC_COMBO_BACKIMG_POS": "bgImgPos", "IDC_EDIT_BACKIMG_OFFSET_X": "bgImgPosOffsetX",
    "IDC_EDIT_BACKIMG_OFFSET_Y": "bgImgPosOffsetY", "IDC_EDIT_BACKIMG_TRANSPARENCY": "bgImgOpacity",
    "IDC_TRACKBAR_BACKIMG_TRANSPARENCY": "bgImgOpacity",
    # 支援
    "IDC_COMBO_HOKAN_TYPE": "nHokanType",
    # カラー（第 2 个 PR）
    "IDC_LIST_COLORS": "C[TXT]～（表示,太字,文字色,背景色,下線）", "IDC_CHECK_DISP": "C[…]（表示）", "IDC_CHECK_BOLD": "C[…]（太字）",
    "IDC_CHECK_UNDERLINE": "C[…]（下線）", "IDC_BUTTON_TEXTCOLOR": "C[…]（文字色）", "IDC_BUTTON_BACKCOLOR": "C[…]（背景色）",
    "IDC_BUTTON_SAMETEXTCOLOR": "C[…]（文字色）", "IDC_BUTTON_SAMEBKCOLOR": "C[…]（背景色）",
    "IDC_BUTTON_IMPORT": "C[…]（*.col）", "IDC_BUTTON_EXPORT": "C[…]（*.col）",
    "IDC_COMBO_SET": "nInts（5 番目）", "IDC_BUTTON_KEYWORD_SELECT": "nInts（5・6 番目）, nKeywordSelect3～10",
    "IDC_BUTTON_EDITKEYWORD": "KeyWords/…（共通設定 > 強調キーワード をその場で書く）",
    "IDC_EDIT_BLOCKCOMMENT_FROM": "szBlockCommentFrom", "IDC_EDIT_BLOCKCOMMENT_TO": "szBlockCommentTo",
    "IDC_EDIT_BLOCKCOMMENT_FROM2": "szBlockCommentFrom2", "IDC_EDIT_BLOCKCOMMENT_TO2": "szBlockCommentTo2",
    "IDC_EDIT_LINECOMMENT": "szLineComment", "IDC_CHECK_LCPOS": "nLineCommentColumn", "IDC_EDIT_LINECOMMENTPOS": "nLineCommentColumn",
    "IDC_EDIT_LINECOMMENT2": "szLineComment2", "IDC_CHECK_LCPOS2": "nLineCommentColumn2", "IDC_EDIT_LINECOMMENTPOS2": "nLineCommentColumn2",
    "IDC_EDIT_LINECOMMENT3": "szLineComment3", "IDC_CHECK_LCPOS3": "nLineCommentColumn3", "IDC_EDIT_LINECOMMENTPOS3": "nLineCommentColumn3",
    "IDC_COMBO_STRINGLITERAL": "nInts（7 番目）", "IDC_CHECK_STRINGLINEONLY": "bStringLineOnly", "IDC_CHECK_STRINGENDLINE": "bStringEndLine",
    "IDC_EDIT_VERTLINE": "nVertLineIdx1～",
    # 正規表現キーワード
    "IDC_CHECK_REGEX": "bUseRegexKeyword", "IDC_LIST_REGEX": "RxKey[000]～（色の名前,キーワード）",
    "IDC_EDIT_REGEX": "RxKey[nnn]", "IDC_COMBO_REGEX_COLOR": "RxKey[nnn]",
    "IDC_BUTTON_REGEX_IMPORT": "RxKey[…]（*.rkw）", "IDC_BUTTON_REGEX_EXPORT": "RxKey[…]（*.rkw）",
    # キーワードヘルプ
    "IDC_CHECK_KEYHELP": "bUseKeyWordHelp", "IDC_LIST_KEYHELP": "KDct[00]～（使う,辞書の説明,パス）",
    "IDC_EDIT_KEYHELP": "KDct[nn]", "IDC_CHECK_KEYHELP_ALLSEARCH": "bUseKeyHelpAllSearch",
    "IDC_CHECK_KEYHELP_KEYDISP": "bUseKeyHelpKeyDisp", "IDC_CHECK_KEYHELP_PREFIX": "bUseKeyHelpPrefix",
    "IDC_COMBO_MENU": "nKeyHelpRMenuShowType",
    "IDC_BUTTON_KEYHELP_IMPORT": "KDct[…]（*.txt）", "IDC_BUTTON_KEYHELP_EXPORT": "KDct[…]（*.txt）",
}

# 前面的说明文字不是这个控件的名字的（说明文字在后面、没有说明文字的）
CAPTION_OVERRIDES = {
    "IDC_COMBO_TSV_MODE": "TSVモード（通常・TSV・CSV）", "IDC_COMBO_OUTLINES": "標準ルール",
    "IDC_EDIT_OUTLINERULEFILE": "ルールファイル", "IDC_STATIC_TYPEFONT": "タイプ別フォント（フォント名とサイズ）",
    "IDC_EDIT_KINSOKUKUTO": "句読点ぶら下げ（文字）", "IDC_EDIT_KINSOKUHEAD": "行頭禁則（文字）",
    "IDC_EDIT_KINSOKUTAIL": "行末禁則（文字）", "IDC_EDIT_BACKIMG_PATH": "背景画像", "IDC_BUTTON_BACKIMG_PATH_SEL": "背景画像（参照）",
    "IDC_COMBO_HOKAN_TYPE": "補完種別", "IDC_COMBO_SET": "強調キーワード1", "IDC_COMBO_STRINGLITERAL": "文字列エスケープ",
    "IDC_EDIT_VERTLINE": "縦線桁指定", "IDC_LIST_COLORS": "色指定", "IDC_LIST_REGEX": "正規表現キーワード", "IDC_LIST_KEYHELP": "辞書ファイル一覧", "IDC_EDIT_TYPEEXTHELP": "外部ヘルプ", "IDC_EDIT_TYPEEXTHTMLHELP": "外部HTMLヘルプ",
    "IDC_CHECK_BACKIMG_REP_X": "Repeat X", "IDC_CHECK_BACKIMG_REP_Y": "Repeat Y",
    "IDC_CHECK_BACKIMG_SCR_X": "Scroll X", "IDC_CHECK_BACKIMG_SCR_Y": "Scroll Y",
    "IDC_EDIT_BACKIMG_OFFSET_X": "Offset X", "IDC_EDIT_BACKIMG_OFFSET_Y": "Offset Y",
}

# Mac 版的处理（第 40 步）。没写的：这一步移植的页的项目是「○」（与原版相同地读写）
LATER_PAGES = {}
MAC_DECISIONS = {
    "IDC_COMBO_HOKAN_TYPE": "×（補完種別はプラグインが追加する。DLL のプラグインは Mac 版では使えない。偏离项 9）",
    "IDC_EDIT_TYPEEXTHELP": "×（Windows のヘルプ。偏离项 9）", "IDC_BUTTON_TYPEOPENHELP": "×（同上）",
    "IDC_EDIT_TYPEEXTHTMLHELP": "×（同上）", "IDC_BUTTON_TYPEOPENEXTHTMLHELP": "×（同上）",
    "IDC_CHECK_TYPEHTMLHELPISSINGLE": "×（同上）",
    "IDC_STATIC_TYPEFONT": "○",
    "IDC_LABEL_REGEX_VERSION": "△（組み込みの正規表現ライブラリを表示）",
    "IDC_LABEL_KEYHELP_ABOUT": "○", "IDC_LABEL_KEYHELP_TITLE": "",
}


def mac_decision(page, cid, kind):
    if page in LATER_PAGES:
        return LATER_PAGES[page]
    if cid in MAC_DECISIONS:
        return MAC_DECISIONS[cid]
    if kind in ("LTEXT", "RTEXT", "CTEXT", "GROUPBOX"):
        return ""
    return "○"


def ini_keys():
    """ShareData_IO_TypeConfig：STypeConfig 成员 → sakura.ini 的项目"""
    keys = {name: f"nInts（{i + 1} 番目）" for i, name in enumerate(NINTS)}
    keys.update({"m_nLineSpace": "nLineSpace", "m_nLineNumWidth": "nLineNumWidth", "m_nIdx": "nInts（1 番目）",
                 "m_lf": "lf, lfFaceName", "m_nPointSize": "nPointSize"})
    with open(os.path.join(ROOT, "sakura_core", "env", "CShareData_IO.cpp"), encoding="utf-8-sig", errors="replace") as f:
        text = f.read()
    body = text[text.index("void ShareData_IO_TypeConfig("):]
    body = body[:body.index("\n}\n")]
    for m in IO_RE.finditer(body):
        keys.setdefault(m.group(2), m.group(1))
    return keys


def members_for(source, cid):
    """源文件里这个控件附近读写的 STypeConfig 成员"""
    found = []

    def add(text):
        for m in MEMBER_RE.finditer(text):
            if m.group(1) not in found:
                found.append(m.group(1))
    for i, line in enumerate(source):
        if not re.search(rf"\b{cid}\b", line):
            continue
        if MEMBER_RE.search(line):
            add(line)
            continue
        for j in (i - 1, i + 1):
            if 0 <= j < len(source) and not re.search(r"\bIDC_\w+", source[j]):
                add(source[j])
    return found


def main():
    lines = read_rc()
    keys = ini_keys()
    rows = []
    for page, dialog, src in TYPE_PAGES:
        with open(os.path.join(ROOT, "sakura_core", "typeprop", src), encoding="utf-8-sig", errors="replace") as f:
            source = f.read().splitlines()
        label = ""
        for kind, text, cid in dialog_controls(lines, dialog):
            if kind == "msctls_updown32" or cid in ("IDC_STATIC", "-1") and kind == "Static":
                continue	# 输入框的上下箭头（与输入框是一项）、分隔线
            if kind in ("LTEXT", "RTEXT", "CTEXT", "GROUPBOX"):
                if text:
                    label = text
                if cid in ("IDC_STATIC", "-1"):
                    continue
            members = members_for(source, cid)
            caption = CAPTION_OVERRIDES.get(cid) or (text if text else label)
            ini = INI_OVERRIDES.get(cid) or ", ".join(dict.fromkeys(keys[m] for m in members if m in keys))
            rows.append([page, cid, kind, caption.replace("&", "").replace("\\n", ""), " ".join(members), ini,
                         mac_decision(page, cid, kind)])
    out = io.StringIO()
    w = csv.writer(out, lineterminator="\n")
    w.writerow(["页", "控件", "种类", "文字", "STypeConfig 成员", "sakura.ini（[Types(N)] 的项目）", "Mac 版"])
    w.writerows(rows)
    data = "﻿" + out.getvalue()
    if len(sys.argv) > 1:
        with open(sys.argv[1], "w", encoding="utf-8", newline="") as f:
            f.write(data)
    else:
        sys.stdout.write(data)


if __name__ == "__main__":
    main()

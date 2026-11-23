#!/usr/bin/env python3
# Copyright (C) 2026, Sakura Editor Organization
#
# SPDX-License-Identifier: Zlib
"""原版「共通設定」各页的设置项清单（计划第 39 步）。

从 sakura_core/sakura_rc.rc 的对话框模板（IDD_PROP_*）取出每个控件和它的文字，
再从 sakura_core/prop/CPropCom*.cpp 找出这个控件读写的 CommonSetting 成员（m_Common.m_sXxx.m_yyy）。
输出 CSV（UTF-8 BOM，Excel 能直接打开）：页、控件 ID、种类、文字、成员、sakura.ini 的节和项目、Mac 版的处理
（○ 与原版相同地读写、× Mac 版做不到（变灰）、第 N 步 以后移植）。
结果放在 macos/docs/common-settings.csv。

用法：python3 list_common_settings.py [输出文件]（默认输出到标准输出）
"""
import csv
import io
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))

# 原版 CPropCommon::DoPropertySheet 的页的顺序：(页名, 对话框, 源文件)
PAGES = [
    ("全般", "IDD_PROP_GENERAL", "CPropComGeneral.cpp"),
    ("ウィンドウ", "IDD_PROP_WIN", "CPropComWin.cpp"),
    ("メインメニュー", "IDD_PROP_MAINMENU", "CPropComMainMenu.cpp"),
    ("ツールバー", "IDD_PROP_TOOLBAR", "CPropComToolbar.cpp"),
    ("タブバー", "IDD_PROP_TAB", "CPropComTab.cpp"),
    ("ステータスバー", "IDD_PROP_STATUSBAR", "CPropComStatusbar.cpp"),
    ("編集", "IDD_PROP_EDIT", "CPropComEdit.cpp"),
    ("ファイル", "IDD_PROP_FILE", "CPropComFile.cpp"),
    ("ファイル名表示", "IDD_PROP_FNAME", "CPropComFileName.cpp"),
    ("バックアップ", "IDD_PROP_BACKUP", "CPropComBackup.cpp"),
    ("書式", "IDD_PROP_FORMAT", "CPropComFormat.cpp"),
    ("検索", "IDD_PROP_GREP", "CPropComGrep.cpp"),
    ("キー割り当て", "IDD_PROP_KEYBIND", "CPropComKeybind.cpp"),
    ("カスタムメニュー", "IDD_PROP_CUSTMENU", "CPropComCustmenu.cpp"),
    ("強調キーワード", "IDD_PROP_KEYWORD", "CPropComKeyword.cpp"),
    ("支援", "IDD_PROP_HELPER", "CPropComHelper.cpp"),
    ("マクロ", "IDD_PROP_MACRO", "CPropComMacro.cpp"),
    ("プラグイン", "IDD_PROP_PLUGIN", "CPropComPlugin.cpp"),
]

# 控件的行：种类 "文字", ID, ...  或  CONTROL "文字", ID, "类名", 样式, ...
CONTROL_RE = re.compile(r'^\s*(\w+)\s+(?:"((?:[^"]|"")*)"\s*,\s*)?(\w+)\s*,(.*)$')
MEMBER_RE = re.compile(r"m_Common\.(m_s\w+)\.(m_\w+|\w+\(\))")


IO_RE = re.compile(r'IOProfileData\(\s*(pszSecName|LTEXT\("(\w+)"\))\s*,\s*LTEXT\("(\w+)"\)\s*,\s*(?:StringBufferW\()?\s*'
                   r'(?:common|pShare->m_Common|pShareData->m_Common)\.(m_s\w+)\.(m_\w+)')


# 成员的名字找不到 sakura.ini 的项目的控件（组合框、用访问函数的、单选按钮的第二个以后、[Statusbar] 节）：
# 按 CShareData_IO.cpp 手工补上（Mac 版 CommonSettingsPages.swift 读写的也是这些项目）
INI_OVERRIDES = {
    "IDC_RADIO_CARETTYPE0": "Common/nCaretType", "IDC_RADIO_CARETTYPE1": "Common/nCaretType",
    "IDC_COMBO_WHEEL_PAGESCROLL": "Common/nPageScrollByWheel", "IDC_COMBO_WHEEL_HSCROLL": "Common/nHorizontalScrollByWheel",
    "IDC_COMBO_LANGUAGE": "Common/szLanguageDll",
    "IDC_CHECK_DispTabClose": "Common/bDispTabClose", "IDC_COMBO_TAB_POSITION": "Common/eTabPosition",
    "IDC_STATIC_TABFONT": "Common/lfTabFont, lfTabFontPs, lfTabFaceName",
    "IDC_BUTTON_WINSIZE": "Common/bSaveWindowSize, nSaveWindowPos, nWinSizeType, nWinSizeCX, nWinSizeCY, nWinPosX, nWinPosY",
    "IDC_CHECK_DISP_UNICODE_IN_SJIS": "Statusbar/DispUnicodeInSjis", "IDC_CHECK_DISP_UNICODE_IN_JIS": "Statusbar/DispUnicodeInJis",
    "IDC_CHECK_DISP_UNICODE_IN_EUC": "Statusbar/DispUnicodeInEuc", "IDC_CHECK_DISP_UTF8_CODEPOINT": "Statusbar/DispUtf8Codepoint",
    "IDC_CHECK_DISP_SP_CODEPOINT": "Statusbar/DispSurrogatePairCodepoint",
    "IDC_CHECK_DISP_SELCOUNT_BY_BYTE": "Statusbar/DispSelectCountByByte", "IDC_CHECK_DISP_COL_BY_CHAR": "Statusbar/DispColByChar",
    "IDC_COMBO_FILESHAREMODE": "Common/nFileShareMode",
    "IDC_CHECK_AUTOSAVE": "Common/bBackUpType2_Opt1（BKUP_AUTO ビット）", "IDC_EDIT_AUTOBACKUP_INTERVAL": "Common/bBackUpType2_Opt3",
    "IDC_CHECK_RestoreCurPosition": "Common/m_bRestoreCurPosition", "IDC_CHECK_RestoreBookmarks": "Common/m_bRestoreBookmarks",
    "IDC_CHECK_AutoMIMEDecode": "Common/bAutoMIMEdecode", "IDC_CHECK_QueryIfCodeChange": "Common/bQueryIfCodeChange",
    "IDC_CHECK_AlertIfFileNotExist": "Common/bAlertIfFileNotExist",
    "IDC_LIST_FNAME": "Nickname/ArrNum, From%02d, To%02d",
    "IDC_RADIO_BACKUP_TYPE1": "Common/nBackUpType", "IDC_RADIO_BACKUP_TYPE3": "Common/nBackUpType",
    "IDC_RADIO_BACKUP_DATETYPE1": "Common/nBackUpType", "IDC_RADIO_BACKUP_DATETYPE2": "Common/nBackUpType",
    "IDC_CHECK_BACKUP_RETAINEXT": "Common/nBackUpType", "IDC_EDIT_BACKUP_3": "Common/bBackUpType2_Opt2（下位 16 ビット）",
    "IDC_CHECK_BACKUP_YEAR": "Common/bBackUpType2_Opt1（BKUP_YEAR）", "IDC_CHECK_BACKUP_MONTH": "Common/bBackUpType2_Opt1（BKUP_MONTH）",
    "IDC_CHECK_BACKUP_DAY": "Common/bBackUpType2_Opt1（BKUP_DAY）", "IDC_CHECK_BACKUP_HOUR": "Common/bBackUpType2_Opt1（BKUP_HOUR）",
    "IDC_CHECK_BACKUP_MIN": "Common/bBackUpType2_Opt1（BKUP_MIN）", "IDC_CHECK_BACKUP_SEC": "Common/bBackUpType2_Opt1（BKUP_SEC）",
    "IDC_RADIO_BACKUP_DATETYPE1A": "Common/bBackUpType2_Opt4", "IDC_RADIO_BACKUP_DATETYPE2A": "Common/bBackUpType2_Opt4",
    "IDC_EDIT_BACKUPFOLDER": "Common/szBackUpFolder",
    "IDC_RADIO_DFORM_1": "Common/nDateFormatType", "IDC_RADIO_TFORM_1": "Common/nTimeFormatType",
    "IDC_COMBO_TAGJUMP": "Common/nTagJumpMode", "IDC_COMBO_KEYWORD_TAGJUMP": "Common/nTagJumpModeKeyword",
    "IDC_STATIC_KEYWORDHELPFONT": "Common/khlf, khps, khlfFaceName",
    # 強調キーワード（第 40 步）：[KeyWords] 節（ShareData_IO_KeyWords）
    "IDC_COMBO_SET": "KeyWords/nCurrentKeyWordSetIdx, nKeyWordSetNum, szSN[nn]",
    "IDC_BUTTON_ADDSET": "KeyWords/nKeyWordSetNum, szSN[nn]", "IDC_BUTTON_DELSET": "KeyWords/…、Types(N)/nInts, nKeywordSelect3～10",
    "IDC_BUTTON_KEYSETRENAME": "KeyWords/szSN[nn]", "IDC_LIST_KEYWORD": "KeyWords/nKWN[nn], szKW[nn]",
    "IDC_BUTTON_ADDKEYWORD": "KeyWords/szKW[nn]", "IDC_BUTTON_EDITKEYWORD": "KeyWords/szKW[nn]",
    "IDC_BUTTON_DELKEYWORD": "KeyWords/szKW[nn]", "IDC_BUTTON_KEYCLEAN": "KeyWords/szKW[nn]",
    "IDC_CHECK_KEYWORDCASE": "KeyWords/nCASE[nn]", "IDC_BUTTON_IMPORT": "KeyWords/szKW[nn]（*.kwd）",
    "IDC_BUTTON_EXPORT": "KeyWords/szKW[nn]（*.kwd）", "IDOK": "（タイプ別設定から開いたとき）", "IDCANCEL": "（同上）",
}

# 同じ ID が別のページにもある控件（インポート・エクスポート等）：ページごとの sakura.ini の項目（第 41 步）
PAGE_INI_OVERRIDES = {
    ("キー割り当て", "IDC_COMBO_FUNCKIND"): "", ("キー割り当て", "IDC_LIST_FUNC"): "",
    ("キー割り当て", "IDC_LIST_KEY"): "KeyBind/KeyBind[nnn]", ("キー割り当て", "IDC_BUTTON_ASSIGN"): "KeyBind/KeyBind[nnn]",
    ("キー割り当て", "IDC_BUTTON_RELEASE"): "KeyBind/KeyBind[nnn]",
    ("キー割り当て", "IDC_BUTTON_IMPORT"): "KeyBind/KeyBind[nnn]（*.key）", ("キー割り当て", "IDC_BUTTON_EXPORT"): "（*.key）",
    ("メインメニュー", "IDC_BUTTON_IMPORT"): "MainMenu/nMainMenuNum, MM[nnn]（*.ini）", ("メインメニュー", "IDC_BUTTON_EXPORT"): "（*.ini）",
    ("メインメニュー", "IDC_TREE_RES"): "MainMenu/nMainMenuNum, MM[nnn]",
    ("メインメニュー", "IDC_CHECK_KEY_PARENTHESES"): "MainMenu/bKeyParentheses",
    **{("メインメニュー", f"IDC_BUTTON_{b}"): "MainMenu/MM[nnn]" for b in
       ("DELETE", "INSERT_NODE", "INSERTSEPARATOR", "INSERT", "INSERT_A", "ADD", "UP", "DOWN", "RIGHT", "LEFT", "CLEAR", "INITIALIZE")},
    ("メインメニュー", "IDC_COMBO_FUNCKIND"): "", ("メインメニュー", "IDC_LIST_FUNC"): "",
    ("カスタムメニュー", "IDC_BUTTON_IMPORT"): "CustMenu/szCMN[nn], bCMPOP[nn], nCMIN[nn], nCMIF[nn][nn], nCMIK[nn][nn]（*.mnu）",
    ("カスタムメニュー", "IDC_BUTTON_EXPORT"): "（*.mnu）",
    ("カスタムメニュー", "IDC_COMBO_FUNCKIND"): "", ("カスタムメニュー", "IDC_LIST_FUNC"): "", ("カスタムメニュー", "IDC_COMBO_MENU"): "",
    ("カスタムメニュー", "IDC_EDIT_MENUNAME"): "CustMenu/szCMN[nn]", ("カスタムメニュー", "IDC_BUTTON_MENUNAME"): "CustMenu/szCMN[nn]",
    ("カスタムメニュー", "IDC_CHECK_SUBMENU"): "CustMenu/bCMPOP[nn]",
    ("カスタムメニュー", "IDC_LIST_RES"): "CustMenu/nCMIN[nn], nCMIF[nn][nn], nCMIK[nn][nn]",
    **{("カスタムメニュー", f"IDC_BUTTON_{b}"): "CustMenu/nCMIN[nn], nCMIF[nn][nn], nCMIK[nn][nn]" for b in
       ("DELETE", "INSERTSEPARATOR", "INSERT", "ADD", "UP", "DOWN")},
    ("ツールバー", "IDC_COMBO_FUNCKIND"): "", ("ツールバー", "IDC_LIST_FUNC"): "",
    ("ツールバー", "IDC_CHECK_TOOLBARISFLAT"): "Toolbar/bToolBarIsFlat",
    ("ツールバー", "IDC_LIST_RES"): "Toolbar/nToolBarButtonNum, nTBB[nnn]",
    **{("ツールバー", f"IDC_BUTTON_{b}"): "Toolbar/nToolBarButtonNum, nTBB[nnn]" for b in
       ("DELETE", "INSERTSEPARATOR", "INSERT", "ADD", "UP", "DOWN", "INSERTWRAP")},
}

# Mac 版的处理（第 39 步）。没写的：这一步移植的页的项目是「○」（与原版相同地读写）
LATER_PAGES = {
    "マクロ": "第 45 步", "プラグイン": "×（DLL のプラグインは Mac 版では使えない）",
}
MAC_DECISIONS = {
    "IDC_CHECK_USETRAYICON": "×（タスクトレイがない。偏离项 7）", "IDC_CHECK_STAYTASKTRAY": "×（同上）",
    "IDC_HOTKEY_TRAYMENU": "×（同上）", "IDC_CHECK_MEMDC": "×（Windows の描画方式）",
    "IDC_COMBO_LANGUAGE": "×（言語 DLL。Mac 版はシステムの言語）",
    "IDC_CHECK_VISTA_STYLE_FILEDIALOG": "×（Windows のダイアログの種類）",
    "IDC_COMBO_FILESHAREMODE": "×（Windows の共有モード。偏离项 9）",
    "IDC_EDIT_REGEXPLIB": "×（正規表現は組み込みの bregonig。偏离项 9）", "IDC_LABEL_REGEXP": "×（同上）",
    "IDC_LABEL_REGEXP_VER": "△（組み込みのライブラリを表示）",
    "IDC_EDIT_EXTHELP1": "×（Windows のヘルプ）", "IDC_BUTTON_OPENHELP1": "×（同上）",
    "IDC_EDIT_EXTHTMLHELP": "×（同上）", "IDC_BUTTON_OPENEXTHTMLHELP": "×（同上）", "IDC_CHECK_HTMLHELPISSINGLE": "×（同上）",
    "IDC_EDIT_MIGEMO_DLL": "×（migemo は組み込み。偏离项 9）", "IDC_BUTTON_OPENMDLL": "×（同上）",
    "IDC_EDIT_MIGEMO_DICT": "×（同上）", "IDC_BUTTON_OPENMDICT": "×（同上）",
    # フォント名とサイズの表示（RTEXT だが値を表示する）
    "IDC_STATIC_TABFONT": "○", "IDC_STATIC_KEYWORDHELPFONT": "○",
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
    """CShareData_IO.cpp：CommonSetting 成员 → sakura.ini 的「节/项目」"""
    keys = {}
    section = ""
    with open(os.path.join(ROOT, "sakura_core", "env", "CShareData_IO.cpp"), encoding="utf-8-sig", errors="replace") as f:
        for line in f:
            m = re.search(r'pszSecName\s*=\s*LTEXT\("(\w+)"\)', line)
            if m:
                section = m.group(1)
            for m in IO_RE.finditer(line):
                sec = section if m.group(1) == "pszSecName" else m.group(2)
                keys.setdefault(f"{m.group(4)}.{m.group(5)}", f"{sec}/{m.group(3)}")
    return keys


def read_rc():
    with open(os.path.join(ROOT, "sakura_core", "sakura_rc.rc"), "rb") as f:
        return f.read().decode("utf-16").splitlines()


def dialog_controls(lines, dialog):
    """对话框模板里的控件：(种类, 文字, ID)"""
    start = None
    for i, line in enumerate(lines):
        if re.match(rf"^{dialog}\s+DIALOGEX\b", line):
            start = i
            break
    if start is None:
        return []
    controls = []
    i = start
    while i < len(lines) and lines[i].strip() != "BEGIN":
        i += 1
    i += 1
    while i < len(lines) and lines[i].strip() != "END":
        line = lines[i]
        # 一个控件写成几行时（行末是逗号、竖线），接上下一行
        while line.rstrip().endswith((",", "|")) and i + 1 < len(lines):
            i += 1
            line = line.rstrip() + " " + lines[i].strip()
        m = CONTROL_RE.match(line)
        if m:
            kind, text, cid, rest = m.groups()
            text = (text or "").replace('""', '"')
            if kind == "CONTROL":
                cls = re.search(r'"(\w+)"', rest)
                style = rest
                kind = cls.group(1) if cls else "CONTROL"
                if kind == "Button":
                    kind = "AUTORADIOBUTTON" if "RADIO" in style else "AUTOCHECKBOX" if "CHECK" in style else "PUSHBUTTON"
            controls.append((kind, text, cid))
        i += 1
    return controls


def members_for(source, cid):
    """源文件里这个控件附近读写的 CommonSetting 成员"""
    found = []
    def add(text):
        for m in MEMBER_RE.finditer(text):
            name = f"{m.group(1)}.{m.group(2)}"
            if name not in found:
                found.append(name)
    for i, line in enumerate(source):
        if not re.search(rf"\b{cid}\b", line):
            continue
        if MEMBER_RE.search(line):
            add(line)
            continue
        # 同一行没有时看前后一行（那一行没有别的控件时）
        for j in (i - 1, i + 1):
            if 0 <= j < len(source) and not re.search(r"\bIDC_\w+", source[j]):
                add(source[j])
    return found


def main():
    lines = read_rc()
    keys = ini_keys()
    rows = []
    for page, dialog, src in PAGES:
        with open(os.path.join(ROOT, "sakura_core", "prop", src), encoding="utf-8-sig", errors="replace") as f:
            source = f.read().splitlines()
        label = ""
        for kind, text, cid in dialog_controls(lines, dialog):
            # 说明文字：下一个输入框、列表的名字
            if kind == "msctls_updown32":
                continue	# 输入框的上下箭头（与输入框是一项）
            if kind in ("LTEXT", "RTEXT", "CTEXT", "GROUPBOX"):
                if text:
                    label = text
                if cid in ("IDC_STATIC", "-1"):
                    continue
            members = members_for(source, cid)
            # 复选框、按钮等用自己的文字；输入框、列表用前面的说明文字
            caption = text if text else label
            if (page, cid) in PAGE_INI_OVERRIDES:
                ini = PAGE_INI_OVERRIDES[(page, cid)]
            else:
                ini = INI_OVERRIDES.get(cid) or " ".join(keys[m] for m in members if m in keys)
            rows.append([page, cid, kind, caption.replace("&", "").replace("\\n", ""), " ".join(members), ini,
                         mac_decision(page, cid, kind)])
    out = io.StringIO()
    w = csv.writer(out, lineterminator="\n")
    w.writerow(["页", "控件", "种类", "文字", "CommonSetting 成员", "sakura.ini（节/项目）", "Mac 版"])
    w.writerows(rows)
    data = "﻿" + out.getvalue()
    if len(sys.argv) > 1:
        with open(sys.argv[1], "w", encoding="utf-8", newline="") as f:
            f.write(data)
    else:
        sys.stdout.write(data)


if __name__ == "__main__":
    main()

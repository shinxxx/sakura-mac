#!/usr/bin/env python3
# Copyright (C) 2026, Sakura Editor Organization
#
# SPDX-License-Identifier: Zlib
"""Grep 与 Windows 版对照用的样本（计划第 43 步）。

写出 macos/core/tests/data/grep/tree/（检索的文件夹）。文件的编码、换行符各种各样，
文件名的顺序（大小写、记号、数字、日文）也用来确认枚举的顺序与 Windows（NTFS）相同。
样本改了以后重新运行：python3 make_grep_samples.py，再更新 expected（见 test-mac-grep.cpp 的 GrepWindowsComparison）。
"""
import os
import shutil

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
TREE = os.path.join(ROOT, "core", "tests", "data", "grep", "tree")

FILES = {
    "a.txt": "HIT x hit\r\nnone\r\nテスト HIT\r\nHITHIT\r\n".encode("utf-8"),
    "b.txt": "テストの文章です。HIT\r\n日本語のファイルを検索します。\r\n".encode("cp932"),
    "c.log": b"HIT\r\n",
    "日本語.txt": b"\xef\xbb\xbf" + "テスト\r\nHit me\r\n".encode("utf-8"),
    "utf16.txt": b"\xff\xfe" + "HIT utf16\r\nテスト\r\n".encode("utf-16-le"),
    "euc.txt": "テストの文章です。日本語のファイルを検索します。\r\nHIT euc\r\n".encode("euc_jp"),
    "mixed.txt": b"HIT\nx\rHIT\r\nend HIT",
    "Zeta.txt": b"zeta HIT\r\n",
    "alpha.txt": b"alpha HIT\r\n",
    "_u.txt": b"under HIT\r\n",
    "1.txt": b"one HIT\r\n",
    "empty.txt": b"",
    "Sub/d.txt": b"HIT d\r\n",
    "Sub/deep/e.txt": b"e HIT\r\n",
    "Sub/x.bak": b"HIT bak\r\n",
    "obj/f.txt": b"HIT f\r\n",
}


def main():
    shutil.rmtree(TREE, ignore_errors=True)
    for name, data in FILES.items():
        path = os.path.join(TREE, *name.split("/"))
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as f:
            f.write(data)


if __name__ == "__main__":
    main()

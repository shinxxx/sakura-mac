#!/usr/bin/env python3
# Copyright (C) 2026, Sakura Editor Organization
#
# SPDX-License-Identifier: Zlib
"""DIFF差分表示（计划第 44 步）的样本：macos/core/tests/data/editsupport/diff/<名字>/old.txt・new.txt。

Mac 版自己实现的差分（macos/core/api/Diff.cpp）和 Windows 上的 GNU diff（原版 DIFF差分表示 用的 diff.exe）
对同样的样本比较结果（CI 的 edit-support-windows）。样本是 UTF-8（无 BOM）。
重新生成：python3 make_diff_samples.py
"""
import os
import random

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
OUT = os.path.join(ROOT, "macos", "core", "tests", "data", "editsupport", "diff")


def lines(*xs):
    return "".join(x + "\n" for x in xs)


def big_pair():
    """300 行の文章を決まった乱数で編集（追加・削除・変更・入れ替え）"""
    rnd = random.Random(44)
    words = ["alpha", "beta", "gamma", "delta", "{", "}", "", "return x;", "int i = 0;", "end", "さくら", "  "]
    old = [" ".join(rnd.choice(words) for _ in range(rnd.randint(0, 3))) for _ in range(300)]
    new = list(old)
    for _ in range(40):
        op = rnd.randint(0, 3)
        i = rnd.randrange(len(new))
        if op == 0:
            new.insert(i, rnd.choice(words))
        elif op == 1 and len(new) > 1:
            del new[i]
        elif op == 2:
            new[i] = new[i] + " " + rnd.choice(words)
        else:
            j = rnd.randrange(len(new))
            new[i], new[j] = new[j], new[i]
    return lines(*old), lines(*new)


CASES = {
    "insert": (lines("a", "b", "c"), lines("a", "X", "b", "c")),
    "delete": (lines("a", "b", "c", "d"), lines("a", "d")),
    "change": (lines("a", "b", "c"), lines("a", "B", "c")),
    "multi": (lines("1", "2", "3", "4", "5", "6", "7", "8", "9"), lines("0", "1", "3", "4", "X", "Y", "6", "8", "9", "10")),
    "repeat": (lines("a", "b", "a", "b", "a", "b"), lines("a", "b", "a", "b")),
    "run": (lines("x", "a", "a", "a", "y"), lines("x", "a", "a", "y")),
    "braces": (lines("int f() {", "  return 1;", "}", "", "int g() {", "  return 2;", "}"),
               lines("int f() {", "  return 1;", "}", "", "int h() {", "  return 3;", "}", "", "int g() {", "  return 2;", "}")),
    "blank": (lines("a", "", "b", "c", "", ""), lines("a", "b", "", "", "c", "x")),
    "space": (lines("a b", "a  b", "ab", "x\t y", "tail  ", " lead"), lines("a  b", "a b", "a b", "x y", "tail", "lead")),
    "case": (lines("Hello", "WORLD", "MiXeD"), lines("hello", "world", "mixed")),
    "eol": ("a\r\nb\r\nc\r\n", "a\nb\nc\n"),
    "noeol": ("a\nb", "a\nb\n"),
    "japanese": (lines("さくらエディタ", "日本語の行", "全角　空白"), lines("さくらエディタ", "日本語を変えた行", "全角 空白", "追加")),
    "empty": ("", lines("a", "b")),
    "different": (lines("1", "2", "3"), lines("a", "b", "c", "d")),
    "move": (lines("a", "b", "c", "d", "e", "f"), lines("d", "e", "f", "a", "b", "c")),
    "big": big_pair(),
}


def main():
    for name, (old, new) in CASES.items():
        d = os.path.join(OUT, name)
        os.makedirs(d, exist_ok=True)
        for fname, text in (("old.txt", old), ("new.txt", new)):
            with open(os.path.join(d, fname), "wb") as f:
                f.write(text.encode("utf-8"))


if __name__ == "__main__":
    main()

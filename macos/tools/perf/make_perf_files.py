#!/usr/bin/env python3
# Copyright (C) 2026, Sakura Editor Organization
#
# SPDX-License-Identifier: Zlib
"""性能测试用的文件（计划第 36 步）。

与 macos/core/tests/test-mac-perf.cpp 里做的文件逐字节相同，Windows 版的测试（windows-bench.js）用同样的文件：
- large.txt：20 万行、约 17 MB（日文和英文、TAB、C 风格的注释），CRLF，最后一行是 "needle at the end"
- long.txt：一行 200 万字（"abcdefghi " 的重复），最后是 "needle"，没有换行

用法：python3 make_perf_files.py 输出文件夹
"""
import os
import sys

LARGE_LINES = 200000
LONG_CHARS = 2000000


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    os.makedirs(out, exist_ok=True)
    with open(os.path.join(out, "large.txt"), "wb") as f:
        jump = "ジャンプ"  # ジャンプ
        for i in range(LARGE_LINES):
            f.write(f"{i:07d}: The quick brown fox {jump} over the lazy dog\tint x = {i}; // comment\r\n".encode("utf-8"))
        f.write(b"needle at the end\r\n")
    with open(os.path.join(out, "long.txt"), "wb") as f:
        chunk = b"abcdefghi "
        f.write(chunk * (LONG_CHARS // len(chunk)))
        f.write(b"needle")


if __name__ == "__main__":
    main()

# Copyright (C) 2026, Sakura Editor Organization
#
# SPDX-License-Identifier: Zlib
"""Windows 版の印刷（print_pdf_chars.py の出力）と Mac 版の expected.txt の比較（计划第 47 步）。

使い方: python compare_print.py <expected.txt> <windows.txt> [許容差(1/10 mm)=2]
ページ数、各ページの文字の数・順番・文字、位置（許容差まで）が同じなら 0 で終わる。
PDF から文字が取れないとき（(cid:N)）は位置だけ比べる。
"""
import sys


def load(path):
    cases = {}
    name = page = None
    with open(path, encoding='utf-8') as f:
        for line in f:
            line = line.rstrip('\n')
            if line.startswith('== '):
                name = line[3:-3]
                cases[name] = {'pages': 0, 'chars': {}}
            elif line.startswith('pages '):
                cases[name]['pages'] = int(line[6:])
            elif line.startswith('-- '):
                page = int(line[3:-3])
                cases[name]['chars'][page] = []
            elif line:
                x, y, t = line.split(' ', 2)
                cases[name]['chars'][page].append((int(x), int(y), t))
    return cases


def main():
    expected = load(sys.argv[1])
    actual = load(sys.argv[2])
    tol = int(sys.argv[3]) if len(sys.argv) > 3 else 2
    ng = 0
    for name, e in expected.items():
        a = actual.get(name)
        if a is None:
            print(f'NG {name}: Windows の結果がない')
            ng += 1
            continue
        if e['pages'] != a['pages']:
            print(f'NG {name}: ページ数 Mac {e["pages"]} Windows {a["pages"]}')
            ng += 1
            continue
        maxd = 0
        for page in range(1, e['pages'] + 1):
            ec = e['chars'].get(page, [])
            ac = a['chars'].get(page, [])
            if len(ec) != len(ac):
                print(f'NG {name} p{page}: 文字数 Mac {len(ec)} Windows {len(ac)}')
                # 最初に違う所
                for i, (m, w) in enumerate(zip(ec, ac)):
                    if m[2] != w[2] and not w[2].startswith('(cid:') or abs(m[0] - w[0]) > tol or abs(m[1] - w[1]) > tol:
                        print(f'   #{i}: Mac {m} Windows {w}')
                        break
                ng += 1
                continue
            bad = 0
            for m, w in zip(ec, ac):
                d = max(abs(m[0] - w[0]), abs(m[1] - w[1]))
                maxd = max(maxd, d)
                if d > tol or (m[2] != w[2] and not w[2].startswith('(cid:')):
                    if bad < 5:
                        print(f'NG {name} p{page}: Mac {m} Windows {w}')
                    bad += 1
            if bad:
                ng += 1
        print(f'{"OK" if ng == 0 else "--"} {name}: {e["pages"]} ページ、位置の差は最大 {maxd}')
    for name in actual:
        if name not in expected:
            print(f'NG {name}: expected.txt にない')
            ng += 1
    return 1 if ng else 0


if __name__ == '__main__':
    sys.exit(main())

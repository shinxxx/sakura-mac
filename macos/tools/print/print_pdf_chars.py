# Copyright (C) 2026, Sakura Editor Organization
#
# SPDX-License-Identifier: Zlib
"""PDF の文字の位置（计划第 47 步：Windows 版の印刷と Mac 版の比較）。

使い方: python print_pdf_chars.py <名前>=<PDF> ... > print.txt
出力（UTF-8、LF）:
  == 名前 ==
  pages N
  -- ページ番号 --
  x y 文字        ← 1/10 mm。x は文字の左端、y は用紙の上からベースラインまで。空白は出さない。y、x の順
pdfminer.six が必要。
"""
import sys

from pdfminer.high_level import extract_pages
from pdfminer.layout import LAParams, LTChar, LTContainer

MM10_PER_PT = 254.0 / 72.0


def chars(obj):
    if isinstance(obj, LTChar):
        yield obj
    elif isinstance(obj, LTContainer):
        for child in obj:
            yield from chars(child)


def main(args):
    out = []
    for arg in args:
        name, path = arg.split('=', 1)
        pages = list(extract_pages(path, laparams=LAParams(char_margin=0.0, line_margin=0.0, all_texts=True)))
        fonts = sorted({c.fontname for page in pages for c in chars(page)})
        sys.stderr.write(f'{name}: fonts {fonts}\n')
        out.append(f'== {name} ==')
        out.append(f'pages {len(pages)}')
        for no, page in enumerate(pages, 1):
            out.append(f'-- {no} --')
            height = page.height
            items = []
            for c in chars(page):
                text = c.get_text()
                if text.strip() == '':
                    continue
                x = round(c.matrix[4] * MM10_PER_PT)
                y = round((height - c.matrix[5]) * MM10_PER_PT)
                items.append((y, x, text))
            items.sort()
            out.extend(f'{x} {y} {t}' for y, x, t in items)
    sys.stdout.buffer.write(('\n'.join(out) + '\n').encode('utf-8'))


if __name__ == '__main__':
    main(sys.argv[1:])

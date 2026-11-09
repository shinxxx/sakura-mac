# Copyright (C) 2026, Sakura Editor Organization
# SPDX-License-Identifier: Zlib
"""编码往返测试（计划第 18 步）的样本文件生成器。

用 Python 自带的编码器（与 Sakura、Windows 无关的独立实现）把同一批多语言文本
写成各种编码的样本文件，供 macos/core/tests/test-mac-roundtrip.cpp 使用：
  1. 读入：Mac 版把样本解码，结果必须与期望文本完全相同（独立验证解码）；
  2. 写出：再按原版保存文件的方式（CWriteManager：BOM + 逐行转换）编码，字节必须与样本完全相同。

样本的写法模仿原版保存文件：每一行（含换行符）单独编码后连接，所以 ISO-2022 等
有状态的编码在每行开头重新指定字符集。换行符轮流使用 CRLF、LF、CR，最后一行没有换行符。

  python3 macos/tools/make_roundtrip_samples.py            # 重新生成 macos/core/tests/data/roundtrip/
  python3 macos/tools/make_roundtrip_samples.py --check    # 只检查仓库里的样本是否与生成结果一致

Python 的编码器与 Windows 在个别字符上有差异，所以每种编码只用 Python 能严格编码的文本行，
并避开已知有差异的字符（波浪号“～”、全角减号等）。样本只在需要时重新生成，生成后要在
Mac 上跑测试确认，Python 版本变化导致的差异不应混进来。
"""
import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.normpath(os.path.join(HERE, '..', 'core', 'tests', 'data', 'roundtrip'))

# 文本池：(标签, 文本)。每种编码取其中能严格编码的行
TEXTS = [
    ('en', 'The quick brown fox jumps over the lazy dog 0123456789'),
    ('sym', 'Symbols !"#$%&\'()*+,-./:;<=>?@[\\]^_`{|}~'),
    ('we', 'Français déjà vu, Ærøskøbing, ¿Qué tal? Straße 12,50'),
    ('euro', 'Euro sign € 9,99'),
    ('ce', 'Příliš žluťoučký kůň úpěl ďábelské ódy. Zażółć gęślą jaźń'),
    ('ru', 'Съешь же ещё этих мягких французских булок, да выпей чаю'),
    ('gr', 'Ξεσκεπάζω την ψυχοφθόρα βδελυγμία'),
    ('tr', 'Pijamalı hasta yağız şoföre çabucak güvendi'),
    ('lt', 'Įlinkdama fechtuotojo špaga sublykčiojusi pragręžė apvalų arbūzą'),
    ('he', 'דג סקרן שט בים מאוכזב'),
    ('ar', 'نص حكيم له سر قاطع'),
    ('th', 'เป็นมนุษย์สุดประเสริฐ'),
    ('ja', 'いろはにほへと ちりぬるを カタカナ 漢字テスト 日本語。'),
    ('jahalf', 'ﾊﾝｶｸｶﾀｶﾅ'),
    ('zhs', '我能吞下玻璃而不伤身体'),
    ('zht', '我能吞下玻璃而不傷身體'),
    ('ko', '다람쥐 헌 쳇바퀴에 타고파'),
    ('nonbmp', 'Non-BMP \U0001F600 \U00020BB7'),
]
EOLS = ['\r\n', '\n', '\r']


def cesu8(s):
    out = bytearray()
    data = s.encode('utf-16-le', 'surrogatepass')
    for i in range(0, len(data), 2):
        u = data[i] | (data[i + 1] << 8)
        if u < 0x80:
            out.append(u)
        elif u < 0x800:
            out += bytes([0xC0 | (u >> 6), 0x80 | (u & 0x3F)])
        else:
            out += bytes([0xE0 | (u >> 12), 0x80 | ((u >> 6) & 0x3F), 0x80 | (u & 0x3F)])
    return bytes(out)


UTF7_DIRECT = set('ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789' "'(),-./:? \t\r\n")


def utf7_always_terminated(s):
    """UTF-7（RFC 2152）。Python 的编码器在 base64 段后面不是 base64 字符时省略结束符“-”，
    Windows 和原版 Sakura 总是写“-”。两种写法解码结果相同，这里按 Windows 的写法生成。"""
    import base64
    out = []
    i = 0
    while i < len(s):
        c = s[i]
        if c in UTF7_DIRECT:
            out.append(c)
            i += 1
        elif c == '+':
            out.append('+-')
            i += 1
        else:
            j = i
            while j < len(s) and s[j] not in UTF7_DIRECT and s[j] != '+':
                j += 1
            b64 = base64.b64encode(s[i:j].encode('utf-16-be', 'surrogatepass')).decode('ascii').rstrip('=')
            out.append('+' + b64 + '-')
            i = j
    data = ''.join(out).encode('ascii')
    assert data.decode('utf-7') == s, s     # 用 Python 的解码器确认
    return data


def encoder(codec):
    if codec == 'cesu-8':
        return cesu8
    if codec == 'utf-7':
        return utf7_always_terminated
    return lambda s: s.encode(codec, 'strict')


def strict_ok(codec, text):
    enc = encoder(codec)
    try:
        b = enc(text)
    except UnicodeEncodeError:
        return False
    if codec in ('cesu-8', 'utf-7'):
        return True
    try:
        return b.decode(codec, 'strict') == text
    except UnicodeDecodeError:
        return False


# (文件名, Sakura 的 ECodeType 或代码页, Python 编码, BOM, 只用这些文本（None 为全部能编码的）, 自动识别的期望结果)
# 自动识别期望结果：None 表示不检查（代码页只能手动指定）
SAMPLES = [
    ('sjis',          0, 'cp932',     False, ['en', 'sym', 'ja', 'jahalf'], 0),
    ('jis',           1, 'iso2022_jp', False, ['en', 'sym', 'ja'], 1),
    ('euc',           2, 'euc_jp',    False, ['en', 'sym', 'ja', 'jahalf'], 2),
    ('utf16le',       3, 'utf-16-le', False, None, None),
    ('utf16le_bom',   3, 'utf-16-le', True,  None, 3),
    ('utf8',          4, 'utf-8',     False, None, 4),
    ('utf8_bom',      4, 'utf-8',     True,  None, 4),
    ('utf7',          5, 'utf-7',     False, ['en', 'we', 'ru', 'ja', 'ko', 'nonbmp'], None),
    ('utf16be',       6, 'utf-16-be', False, None, None),
    ('utf16be_bom',   6, 'utf-16-be', True,  None, 6),
    ('cesu8',         7, 'cesu-8',    False, None, None),
    ('latin1',        8, 'cp1252',    False, ['en', 'sym', 'we', 'euro'], None),
    ('utf32le_bom', 12000, 'utf-32-le', True, None, None),
    ('utf32be_bom', 12001, 'utf-32-be', True, None, None),
]

# Windows 代码页 → Python 编码（只列 Python 有对应实现的）
CODEPAGES = {
    37: 'cp037', 437: 'cp437', 500: 'cp500', 720: 'cp720', 737: 'cp737', 775: 'cp775',
    850: 'cp850', 852: 'cp852', 855: 'cp855', 857: 'cp857', 858: 'cp858', 860: 'cp860',
    861: 'cp861', 862: 'cp862', 863: 'cp863', 864: 'cp864', 865: 'cp865', 866: 'cp866',
    869: 'cp869', 874: 'cp874', 875: 'cp875', 932: 'cp932', 936: 'gbk', 949: 'cp949',
    950: 'cp950', 1026: 'cp1026', 1140: 'cp1140',
    1250: 'cp1250', 1251: 'cp1251', 1252: 'cp1252', 1253: 'cp1253', 1254: 'cp1254',
    1255: 'cp1255', 1256: 'cp1256', 1257: 'cp1257', 1258: 'cp1258', 1361: 'johab',
    10000: 'mac_roman', 10006: 'mac_greek', 10007: 'mac_cyrillic', 10010: 'mac_romanian',
    10029: 'mac_latin2', 10079: 'mac_iceland', 10081: 'mac_turkish', 10082: 'mac_croatian',
    20127: 'ascii', 20273: 'cp273', 20424: 'cp424', 20866: 'koi8_r', 20932: 'euc_jp',
    20936: 'gb2312', 21866: 'koi8_u',
    28591: 'latin_1', 28592: 'iso8859_2', 28593: 'iso8859_3', 28594: 'iso8859_4',
    28595: 'iso8859_5', 28596: 'iso8859_6', 28597: 'iso8859_7', 28598: 'iso8859_8',
    28599: 'iso8859_9', 28603: 'iso8859_13', 28605: 'iso8859_15', 38598: 'iso8859_8',
    50220: 'iso2022_jp', 50221: 'iso2022_jp', 50222: 'iso2022_jp', 50225: 'iso2022_kr',
    51949: 'euc_kr', 52936: 'hz', 54936: 'gb18030', 65000: 'utf-7', 65001: 'utf-8',
}
# Python 与 Windows 映射不同、不能用来对照的文本。Windows 一侧以第 17 步在 Windows 上导出的转换表为准
MAC_OLD_CURRENCY = ['euro']   # 旧版 Apple 映射：Windows 的 Mac 系代码页把该位置映射为 ¤（U+00A4），Python 为 €
EXCLUDE = {
    950: ['ja'],                # Windows 950 把 Big5 的日文假名区（C6A1〜C7FC）映射到私用区，Python 映射到假名
    10006: MAC_OLD_CURRENCY, 10007: MAC_OLD_CURRENCY, 10010: MAC_OLD_CURRENCY,
    10079: MAC_OLD_CURRENCY, 10082: MAC_OLD_CURRENCY,
    20932: ['we', 'ce', 'tr', 'lt', 'gr'],  # Windows 20932 不支持 JIS X 0212（8F 开头的 3 字节），Python 的 euc_jp 支持
    28597: ['euro'],            # Windows 28597 没有 €（ISO-8859-7:2003 才加入），Python 有
}
for cp, codec in CODEPAGES.items():
    only = None
    if codec == 'utf-7':     # Set O 的符号（!"#$%& 等）Windows 是否直接写出没有确认，不用
        only = ['en', 'we', 'ru', 'ja', 'ko', 'nonbmp']
    if cp in EXCLUDE:
        only = [tag for tag, _ in TEXTS if tag not in EXCLUDE[cp]]
    SAMPLES.append(('cp%d' % cp, cp, codec, False, only, None))


def build(codec, bom, only):
    lines = [t for tag, t in TEXTS if (only is None or tag in only) and strict_ok(codec, t)]
    if not lines:
        return None, None
    text_lines = [line + EOLS[i % len(EOLS)] for i, line in enumerate(lines)]
    text_lines[-1] = lines[-1]          # 最后一行没有换行符
    enc = encoder(codec)
    data = bytearray()
    for i, line in enumerate(text_lines):
        data += enc(('﻿' if (bom and i == 0) else '') + line)
    return bytes(data), ''.join(text_lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--check', action='store_true')
    args = ap.parse_args()
    files = {}
    manifest = ['# 名前\tECodeType/代码页\tPython 编码\tBOM\t自动识别期望（-1 为不检查）\t文本行']
    for name, code, codec, bom, only, detect in SAMPLES:
        data, text = build(codec, bom, only)
        if data is None:
            print('skip %s: no text' % name, file=sys.stderr)
            continue
        files[name + '.bin'] = data
        files[name + '.txt'] = text.encode('utf-8')
        tags = [tag for tag, t in TEXTS if (only is None or tag in only) and strict_ok(codec, t)]
        manifest.append('%s\t%d\t%s\t%d\t%d\t%s' % (name, code, codec, 1 if bom else 0,
                                                   -1 if detect is None else detect, ','.join(tags)))
    files['manifest.tsv'] = ('\n'.join(manifest) + '\n').encode('utf-8')

    if args.check:
        bad = [n for n, d in files.items()
               if not os.path.exists(os.path.join(OUT_DIR, n)) or open(os.path.join(OUT_DIR, n), 'rb').read() != d]
        for n in bad:
            print('differs: %s' % n)
        return 1 if bad else 0
    os.makedirs(OUT_DIR, exist_ok=True)
    for n, d in files.items():
        with open(os.path.join(OUT_DIR, n), 'wb') as f:
            f.write(d)
    print('%d samples written to %s' % (len(manifest) - 1, OUT_DIR))
    return 0


if __name__ == '__main__':
    sys.exit(main())

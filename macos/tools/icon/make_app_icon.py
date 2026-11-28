#!/usr/bin/env python3
"""第 37 步：从原版的图标（src/main/resources/images/icon_std.ico，32×32）生成 Mac 版 App 的图标。

Mac App Store 要求 App 带 1024×1024 的图标。原版只有 32×32 和 16×16 的点阵图标，
所以把 32×32 的图案按整数倍放大（不模糊，保持点阵的样子），放在 macOS 图标规格的圆角方块上
（1024 画布里 824×824、四周留 100 的透明边，和 Apple 的图标模板相同），再缩小出各个尺寸。

  python3 macos/tools/icon/make_app_icon.py           生成 macos/app/Resources/Assets.xcassets/AppIcon.appiconset
  python3 macos/tools/icon/make_app_icon.py --check   只检查仓库里的图标和生成结果相同（CI 用）

只用 Python 标准库（CI 的 macOS 上没有 Pillow）。
"""
import json
import os
import struct
import sys
import zlib

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
ICO = os.path.join(ROOT, "src", "main", "resources", "images", "icon_std.ico")
OUT = os.path.join(ROOT, "macos", "app", "Resources", "Assets.xcassets", "AppIcon.appiconset")

CANVAS = 1024
BODY = 824            # 圆角方块的边长（Apple 的 macOS 图标模板）
MARGIN = (CANVAS - BODY) // 2
RADIUS = 185          # 圆角半径（同上）
SCALE = 20            # 32×32 的图案放大 20 倍 = 640×640，放在方块中央
TOP = (255, 255, 255)
BOTTOM = (226, 230, 236)

# (文件名, 像素, 在 Contents.json 里的 size, scale)
SIZES = [
    ("icon_16x16.png", 16, "16x16", "1x"),
    ("icon_16x16@2x.png", 32, "16x16", "2x"),
    ("icon_32x32.png", 32, "32x32", "1x"),
    ("icon_32x32@2x.png", 64, "32x32", "2x"),
    ("icon_128x128.png", 128, "128x128", "1x"),
    ("icon_128x128@2x.png", 256, "128x128", "2x"),
    ("icon_256x256.png", 256, "256x256", "1x"),
    ("icon_256x256@2x.png", 512, "256x256", "2x"),
    ("icon_512x512.png", 512, "512x512", "1x"),
    ("icon_512x512@2x.png", 1024, "512x512", "2x"),
]


def read_ico(path, want=32):
    """ICO 里指定大小的图像 → [[(r,g,b,a)]]（行从上到下）。只处理原版用的 BMP 格式（1/4/8/24/32 位）。"""
    data = open(path, "rb").read()
    count = struct.unpack_from("<H", data, 4)[0]
    for i in range(count):
        w, h, _, _, _, _, size, off = struct.unpack_from("<BBBBHHII", data, 6 + 16 * i)
        if (w or 256) == want:
            break
    else:
        raise SystemExit(f"{path} 里没有 {want}×{want} 的图像")
    hdr = struct.unpack_from("<IiiHHIIiiII", data, off)
    hsize, width, height2, _, bpp, _, _, _, _, used, _ = hdr
    height = height2 // 2
    pos = off + hsize
    palette = []
    if bpp <= 8:
        n = used or (1 << bpp)
        for k in range(n):
            b, g, r, _ = struct.unpack_from("<BBBB", data, pos + 4 * k)
            palette.append((r, g, b))
        pos += 4 * n
    stride = ((width * bpp + 31) // 32) * 4
    mask_stride = ((width + 31) // 32) * 4
    xor = pos
    andm = xor + stride * height
    rows = []
    for y in range(height):
        src = height - 1 - y           # BMP 是从下往上
        row = []
        for x in range(width):
            if bpp == 32:
                b, g, r, a = struct.unpack_from("<BBBB", data, xor + src * stride + 4 * x)
                row.append((r, g, b, a))
                continue
            if bpp == 24:
                b, g, r = struct.unpack_from("<BBB", data, xor + src * stride + 3 * x)
                rgb = (r, g, b)
            else:
                bit = x * bpp
                byte = data[xor + src * stride + bit // 8]
                idx = (byte >> (8 - bpp - bit % 8)) & ((1 << bpp) - 1)
                rgb = palette[idx]
            m = (data[andm + src * mask_stride + x // 8] >> (7 - x % 8)) & 1
            row.append(rgb + (0 if m else 255,))
        rows.append(row)
    return rows


def coverage(px, py):
    """像素 (px,py) 被圆角方块覆盖的比例（4×4 次采样）。"""
    lo, hi = MARGIN, MARGIN + BODY
    if px + 1 <= lo or px >= hi or py + 1 <= lo or py >= hi:
        return 0.0
    inner_lo, inner_hi = lo + RADIUS, hi - RADIUS
    if inner_lo <= px and px + 1 <= inner_hi or inner_lo <= py and py + 1 <= inner_hi:
        if lo <= px and px + 1 <= hi and lo <= py and py + 1 <= hi:
            return 1.0
    hit = 0
    for sy in range(4):
        for sx in range(4):
            x = px + (sx + 0.5) / 4
            y = py + (sy + 0.5) / 4
            if not (lo <= x <= hi and lo <= y <= hi):
                continue
            cx = min(max(x, inner_lo), inner_hi)
            cy = min(max(y, inner_lo), inner_hi)
            if (x - cx) ** 2 + (y - cy) ** 2 <= RADIUS * RADIUS:
                hit += 1
    return hit / 16


def render_master(art):
    """1024×1024 的 RGBA（预乘之前的普通 RGBA，浮点）。"""
    n = len(art)
    off = (CANVAS - n * SCALE) // 2
    img = []
    for y in range(CANVAS):
        t = (y - MARGIN) / BODY
        t = min(max(t, 0.0), 1.0)
        bg = tuple(TOP[i] + (BOTTOM[i] - TOP[i]) * t for i in range(3))
        row = []
        for x in range(CANVAS):
            a = coverage(x, y)
            r, g, b = bg
            ax, ay = (x - off) // SCALE, (y - off) // SCALE
            if a > 0 and 0 <= ax < n and 0 <= ay < n:
                pr, pg, pb, pa = art[ay][ax]
                if pa:
                    r, g, b = pr, pg, pb
            row.append((r, g, b, a * 255))
        img.append(row)
    return img


def downsample(img, size):
    """面积平均缩小（按 alpha 加权，边缘不发黑）。"""
    f = CANVAS // size
    out = []
    for y in range(size):
        row = []
        for x in range(size):
            sr = sg = sb = sa = 0.0
            for yy in range(y * f, (y + 1) * f):
                line = img[yy]
                for xx in range(x * f, (x + 1) * f):
                    r, g, b, a = line[xx]
                    sr += r * a
                    sg += g * a
                    sb += b * a
                    sa += a
            if sa:
                px = (round(sr / sa), round(sg / sa), round(sb / sa), round(sa / (f * f)))
            else:
                px = (0, 0, 0, 0)
            row.append(px)
        out.append(row)
    return out


def png_bytes(pixels):
    h = len(pixels)
    w = len(pixels[0])
    raw = bytearray()
    for row in pixels:
        raw.append(0)
        for r, g, b, a in row:
            raw += bytes((r, g, b, a))

    def chunk(kind, body):
        c = struct.pack(">I", len(body)) + kind + body
        return c + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b"")


def contents_json():
    images = [{"filename": f, "idiom": "mac", "scale": s, "size": sz} for f, _, sz, s in SIZES]
    return json.dumps({"images": images, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n"


def build():
    art = read_ico(ICO, 32)
    master = render_master(art)
    files = {}
    cache = {}
    for name, px, _, _ in SIZES:
        if px not in cache:
            if px == CANVAS:
                cache[px] = png_bytes([[tuple(int(round(c)) for c in p) for p in row] for row in master])
            else:
                cache[px] = png_bytes(downsample(master, px))
        files[name] = cache[px]
    files["Contents.json"] = contents_json().encode()
    return files


def png_pixels(data):
    """PNG 的 IHDR 和解压后的像素数据（不同的 zlib 压缩结果可能不同，比较时只比像素）。"""
    if not data.startswith(b"\x89PNG"):
        return data
    pos, ihdr, idat = 8, b"", b""
    while pos < len(data):
        n = struct.unpack_from(">I", data, pos)[0]
        kind = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + n]
        if kind == b"IHDR":
            ihdr = body
        elif kind == b"IDAT":
            idat += body
        pos += 12 + n
    return ihdr + zlib.decompress(idat)


def main():
    check = "--check" in sys.argv[1:]
    files = build()
    catalog = os.path.dirname(OUT)
    catalog_json = json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n"
    expected = {os.path.join(OUT, k): v for k, v in files.items()}
    expected[os.path.join(catalog, "Contents.json")] = catalog_json.encode()
    if check:
        bad = [p for p, v in expected.items()
               if not os.path.exists(p) or png_pixels(open(p, "rb").read()) != png_pixels(v)]
        extra = [os.path.join(OUT, f) for f in os.listdir(OUT) if os.path.join(OUT, f) not in expected] if os.path.isdir(OUT) else []
        for p in bad:
            print(f"与生成结果不同：{os.path.relpath(p, ROOT)}")
        for p in extra:
            print(f"多余的文件：{os.path.relpath(p, ROOT)}")
        if bad or extra:
            print("请运行 python3 macos/tools/icon/make_app_icon.py 重新生成")
            return 1
        print(f"App 图标与生成结果相同（{len(SIZES)} 个尺寸）")
        return 0
    os.makedirs(OUT, exist_ok=True)
    for p, v in expected.items():
        with open(p, "wb") as fp:
            fp.write(v)
    print(f"已生成 {os.path.relpath(OUT, ROOT)}（{len(SIZES)} 个尺寸）")
    return 0


if __name__ == "__main__":
    sys.exit(main())

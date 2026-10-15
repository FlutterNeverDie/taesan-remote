#!/usr/bin/env python3
"""태산 원격지원 앱 아이콘 생성기.

태산크루 로고(흰 배경 PNG)에서 글자 위의 심볼만 잘라 흰 둥근 사각형 가운데에 둔다.
수신 전용 빌드는 오른쪽 아래에 남색 원 + ↓(받기) 배지를 더한다(32px 이상). --variant incoming 은 배지가
들어가는 파일(Windows ico, Android 런처)만 res/taesan-variant/incoming-icons/ 에 같은 상대 경로로 쓰고,
수신 전용 빌드가 빌드 전에 res/taesan-variant/apply_icons.py 로 덮어쓴다.
PNG 는 루트 .gitignore 의 *png 에 걸리므로 새로 만든 파일은 git add -f 로 넣는다.

사용(저장소 루트에서):
  python3 res/taesan-icon/gen_icons.py --logo <태산크루-흰배경.png>
  python3 res/taesan-icon/gen_icons.py --logo <태산크루-흰배경.png> --variant incoming
필요: Pillow, macOS 에서는 iconutil(.icns)
"""

import argparse
import os
import shutil
import subprocess
import sys
import tempfile

from PIL import Image, ImageChops, ImageDraw

BG = (255, 255, 255, 255)
BADGE = (0x0D, 0x47, 0xA1, 255)  # 로고 글자 남색
CORNER = 0.18  # 둥근 모서리 반지름(한 변 대비)
PAD = 0.14  # 심볼 둘레 여백(한 변 대비)
INCOMING_DIR = os.path.join("res", "taesan-variant", "incoming-icons")
ANDROID_DPI = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}


def load_symbol(path):
    """로고에서 심볼(글자 위 부분)만 잘라 투명 배경 RGBA 로 돌려준다."""
    img = Image.open(path).convert("RGBA")
    rgb = img.convert("RGB")
    # 흰 배경과 다른 픽셀 = 잉크
    diff = ImageChops.difference(rgb, Image.new("RGB", rgb.size, (255, 255, 255))).convert("L")
    ink = diff.point(lambda v: 255 if v > 24 else 0)
    w, h = ink.size
    rows = [any(ink.getpixel((x, y)) for x in range(0, w, 2)) for y in range(h)]
    # 위에서부터 첫 잉크 덩어리(심볼)의 끝 = 그 뒤 처음 나오는 빈 줄의 긴 구간
    top = rows.index(True)
    y = top
    while y < h and not all(not r for r in rows[y:y + max(8, h // 50)]):
        y += 1
    bottom = y
    sym = img.crop((0, top, w, bottom))
    mask = ink.crop((0, top, w, bottom))
    sym.putalpha(diff.crop((0, top, w, bottom)).point(lambda v: min(255, v * 3)))
    box = mask.getbbox()
    if not box:
        sys.exit("심볼을 찾지 못했다")
    sym = sym.crop(box)
    # 반투명 가장자리를 원래 색으로 되돌린다(흰 배경과 섞인 색 → 진한 색 + 알파)
    return unmatte(sym)


def unmatte(img):
    px = img.load()
    for yy in range(img.size[1]):
        for xx in range(img.size[0]):
            r, g, b, a = px[xx, yy]
            if 0 < a < 255:
                f = a / 255
                px[xx, yy] = tuple(max(0, min(255, round((c - 255 * (1 - f)) / f))) for c in (r, g, b)) + (a,)
    return img


def fit(sym, size, pad):
    inner = round(size * (1 - 2 * pad))
    s = sym.copy()
    s.thumbnail((inner, inner), Image.LANCZOS)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.alpha_composite(s, ((size - s.size[0]) // 2, (size - s.size[1]) // 2))
    return out


def rounded(size, radius, color):
    big = size * 4
    m = Image.new("L", (big, big), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, big - 1, big - 1), radius=radius * 4, fill=255)
    out = Image.new("RGBA", (size, size), color)
    out.putalpha(m.resize((size, size), Image.LANCZOS))
    return out


def badge(img):
    size = img.size[0]
    if size < 32:
        return img
    big = size * 4
    layer = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    r = big * 0.2
    cx, cy = big - r - big * 0.02, big - r - big * 0.02
    d.ellipse((cx - r - big * 0.02, cy - r - big * 0.02, cx + r + big * 0.02, cy + r + big * 0.02), fill=BG)
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=BADGE)
    w = r * 0.16
    d.rectangle((cx - w, cy - r * 0.55, cx + w, cy + r * 0.1), fill=BG)
    d.polygon([(cx - r * 0.5, cy + r * 0.0), (cx + r * 0.5, cy + r * 0.0), (cx, cy + r * 0.6)], fill=BG)
    out = img.copy()
    out.alpha_composite(layer.resize((size, size), Image.LANCZOS))
    return out


def render(sym, size, with_bg=True, incoming=False):
    if with_bg:
        img = rounded(size, round(size * CORNER), BG)
        img.alpha_composite(fit(sym, size, PAD))
    else:
        img = fit(sym, size, PAD)
    return badge(img) if incoming else img


def silhouette(sym, size, pad=0.08, color=(255, 255, 255)):
    s = fit(sym, size, pad)
    out = Image.new("RGBA", (size, size), color + (0,))
    out.putalpha(s.getchannel("A"))
    return out


def save_ico(path, sym, incoming=False):
    sizes = (16, 24, 32, 48, 64, 128, 256)
    imgs = [render(sym, s, incoming=incoming) for s in sizes]
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    imgs[-1].save(path, format="ICO", sizes=[(s, s) for s in sizes], append_images=imgs[:-1], bitmap_format="bmp")


def save_icns(path, sym):
    if shutil.which("iconutil") is None:
        print("iconutil 이 없어 .icns 는 건너뛴다(macOS 전용)")
        return
    with tempfile.TemporaryDirectory() as tmp:
        iconset = os.path.join(tmp, "AppIcon.iconset")
        os.makedirs(iconset)
        for px, name in [(16, "16x16"), (32, "16x16@2x"), (32, "32x32"), (64, "32x32@2x"), (128, "128x128"),
                         (256, "128x128@2x"), (256, "256x256"), (512, "256x256@2x"), (512, "512x512"),
                         (1024, "512x512@2x")]:
            body = round(px * 824 / 1024)
            img = Image.new("RGBA", (px, px), (0, 0, 0, 0))
            img.alpha_composite(render(sym, body), ((px - body) // 2, (px - body) // 2))
            img.save(os.path.join(iconset, f"icon_{name}.png"))
        subprocess.run(["iconutil", "-c", "icns", iconset, "-o", path], check=True)


def android(root, sym, incoming=False):
    res = os.path.join(root, "flutter/android/app/src/main/res")
    for dpi, f in ANDROID_DPI.items():
        d = os.path.join(res, f"mipmap-{dpi}")
        os.makedirs(d, exist_ok=True)
        legacy = render(sym, round(48 * f), incoming=incoming)
        legacy.save(os.path.join(d, "ic_launcher.png"))
        legacy.save(os.path.join(d, "ic_launcher_round.png"))
        # 적응형 아이콘 전경: 108dp 캔버스, 안전 영역 66dp 안에 심볼
        fg = Image.new("RGBA", (round(108 * f),) * 2, (0, 0, 0, 0))
        s = fit(sym, round(66 * f), 0.04)
        fg.alpha_composite(s, ((fg.size[0] - s.size[0]) // 2,) * 2)
        if incoming:
            fg = badge(fg)
        fg.save(os.path.join(d, "ic_launcher_foreground.png"))
        if not incoming:
            silhouette(sym, round(24 * f)).convert("LA").save(os.path.join(d, "ic_stat_logo.png"))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--logo", required=True)
    ap.add_argument("--root", default=".")
    ap.add_argument("--variant", choices=["bidirectional", "incoming"], default="bidirectional")
    a = ap.parse_args()
    sym = load_symbol(a.logo)
    r = lambda *p: os.path.join(a.root, *p)

    if a.variant == "incoming":
        base = os.path.join(a.root, INCOMING_DIR)
        ico = os.path.join(base, "flutter/windows/runner/resources/app_icon.ico")
        save_ico(ico, sym, incoming=True)
        os.makedirs(os.path.join(base, "res"), exist_ok=True)
        shutil.copyfile(ico, os.path.join(base, "res/icon.ico"))
        os.makedirs(os.path.join(base, "flutter/assets"), exist_ok=True)
        shutil.copyfile(ico, os.path.join(base, "flutter/assets/icon.ico"))
        android(base, sym, incoming=True)
        return

    save_icns(r("flutter/macos/Runner/AppIcon.icns"), sym)
    save_ico(r("flutter/windows/runner/resources/app_icon.ico"), sym)
    shutil.copyfile(r("flutter/windows/runner/resources/app_icon.ico"), r("res/icon.ico"))
    shutil.copyfile(r("flutter/windows/runner/resources/app_icon.ico"), r("flutter/assets/icon.ico"))
    render(sym, 64).save(r("flutter/assets/icon.png"))
    silhouette(sym, 40, color=(0, 0, 0)).save(r("res/mac-tray-dark-x2.png"))
    for name, size in [("32x32.png", 32), ("64x64.png", 64), ("128x128.png", 128), ("128x128@2x.png", 256),
                       ("icon.png", 256)]:
        if os.path.exists(r("res", name)):
            render(sym, size).save(r("res", name))
    android(a.root, sym)


if __name__ == "__main__":
    main()

"""生成 PWA 图标（原创几何图形，不使用任何第三方素材）。

设计：深建筑蓝底 + 三条递减的金色横条（呼应「地产 + 资质等级」），
配色取自工程自身的 UITheme（Primary #26547C / Accent #916623）。

用法：python tools/build_icons.py
"""
import os
import cv2
import numpy as np

OUT_DIR = r"D:\2026\ai\2\地产风云_web\vendor\icons"

PRIMARY = (0x7C, 0x54, 0x26)   # BGR of #26547C
ACCENT = (0x23, 0x66, 0x91)    # BGR of #916623
LIGHT = (0xFC, 0xFA, 0xF8)     # BGR of #F8FAFC


def imwrite_unicode(path, img):
    ok, buf = cv2.imencode(os.path.splitext(path)[1], img)
    if ok:
        with open(path, "wb") as fp:
            fp.write(buf.tobytes())
    return ok


def make_icon(size):
    img = np.zeros((size, size, 3), dtype=np.uint8)
    img[:] = PRIMARY

    # 圆角：四角涂成透明会让 PNG 有 alpha 通道，这里直接用底色方形更省事，
    # 需要圆角的地方交给系统（maskable 图标本来就会被裁）。
    margin = int(size * 0.18)
    bar_h = int(size * 0.10)
    gap = int(size * 0.075)
    widths = [1.0, 0.72, 0.44]
    colors = [LIGHT, ACCENT, LIGHT]

    total = len(widths) * bar_h + (len(widths) - 1) * gap
    y = (size - total) // 2
    for w_ratio, color in zip(widths, colors):
        w = int((size - margin * 2) * w_ratio)
        x = (size - w) // 2
        cv2.rectangle(img, (x, y), (x + w, y + bar_h), color, -1)
        y += bar_h + gap

    return img


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for size in (192, 512):
        dst = os.path.join(OUT_DIR, f"icon-{size}.png")
        imwrite_unicode(dst, make_icon(size))
        print(f"  {os.path.basename(dst)}  {os.path.getsize(dst)} bytes")


if __name__ == "__main__":
    main()

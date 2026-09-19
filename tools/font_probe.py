"""字体取证：把参考帧里的文字区域裁出来放大，并用工程自带的两种字体渲染同样文字做对照，
用于判定引擎的默认字体族到底是 NotoSansSC 还是 FusionPixel 像素字体。"""
import os
import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont

REF = r"D:\2026\ai\2\地产风云_web\.out\reference"
FRAMES = os.path.join(REF, "frames")
FONTS = r"D:\2026\ai\2\地产风云\src\Fonts"
OUT = os.path.join(REF, "font_probe")
os.makedirs(OUT, exist_ok=True)


def imwrite_unicode(path, img):
    ext = os.path.splitext(path)[1]
    ok, buf = cv2.imencode(ext, img)
    if ok:
        with open(path, "wb") as fp:
            fp.write(buf.tobytes())


def imread_unicode(path):
    """cv2.imread 在 Windows 上无法处理含中文的路径"""
    data = np.fromfile(path, dtype=np.uint8)
    if data.size == 0:
        return None
    return cv2.imdecode(data, cv2.IMREAD_COLOR)


def crop_zoom(src, box, scale, dst):
    """box = (x1,y1,x2,y2)"""
    img = imread_unicode(src)
    if img is None:
        print("读不到 " + src)
        return
    x1, y1, x2, y2 = box
    sub = img[y1:y2, x1:x2]
    big = cv2.resize(sub, None, fx=scale, fy=scale, interpolation=cv2.INTER_NEAREST)
    imwrite_unicode(dst, big)
    print(f"{os.path.basename(dst)}  {sub.shape[1]}x{sub.shape[0]} -> {big.shape[1]}x{big.shape[0]}")


def render_fonts(text, size, dst, label):
    faces = [
        ("NotoSansSC-Regular", os.path.join(FONTS, "NotoSansSC-Regular.ttf")),
        ("FusionPixel-Prop", os.path.join(FONTS, "FusionPixel-12px-Prop-zh_hans.ttf")),
        ("FusionPixel-Mono", os.path.join(FONTS, "FusionPixel-12px-Mono-zh_hans.ttf")),
    ]
    pad = 12
    rows = []
    for name, path in faces:
        if not os.path.exists(path):
            continue
        font = ImageFont.truetype(path, size)
        tmp = Image.new("RGB", (10, 10), (255, 255, 255))
        d = ImageDraw.Draw(tmp)
        bbox = d.textbbox((0, 0), text, font=font)
        w = bbox[2] - bbox[0] + pad * 2
        h = bbox[3] - bbox[1] + pad * 2
        img = Image.new("RGB", (max(w, 420), max(h, size + pad * 2)), (255, 255, 255))
        d = ImageDraw.Draw(img)
        d.text((pad, pad - bbox[1]), text, font=font, fill=(20, 30, 40))
        rows.append((name, img))

    if not rows:
        return
    W = max(r[1].width for r in rows) + 260
    H = sum(r[1].height for r in rows)
    canvas = Image.new("RGB", (W, H), (245, 247, 250))
    y = 0
    d = ImageDraw.Draw(canvas)
    lbl_font = ImageFont.truetype(os.path.join(FONTS, "NotoSansSC-Regular.ttf"), 14)
    for name, img in rows:
        canvas.paste(img, (250, y))
        d.text((10, y + img.height // 2 - 8), name, font=lbl_font, fill=(80, 90, 100))
        d.line([(0, y), (W, y)], fill=(210, 216, 222))
        y += img.height
    canvas.save(dst)
    print(f"{os.path.basename(dst)}  {canvas.width}x{canvas.height}  ({label})")


# 1) 参考帧里的文字区域（f00300 = dashboard 总览）
crop_zoom(os.path.join(FRAMES, "f00300.jpg"), (700, 305, 1070, 350), 3,
          os.path.join(OUT, "ref_row_text.png"))
crop_zoom(os.path.join(FRAMES, "f00300.jpg"), (30, 215, 300, 255), 4,
          os.path.join(OUT, "ref_section_title.png"))
crop_zoom(os.path.join(FRAMES, "f00300.jpg"), (30, 425, 240, 500), 4,
          os.path.join(OUT, "ref_stat_label.png"))
crop_zoom(os.path.join(FRAMES, "f00090.jpg"), (30, 10, 420, 60), 4,
          os.path.join(OUT, "ref_h1.png"))
# 顶栏数字行：现金 1.00亿 / 总资产 1.00亿 / 负债 0万
crop_zoom(os.path.join(FRAMES, "f00300.jpg"), (60, 95, 1060, 145), 3,
          os.path.join(OUT, "ref_topbar_stats.png"))
# 日期行
crop_zoom(os.path.join(FRAMES, "f00300.jpg"), (10, 45, 300, 75), 5,
          os.path.join(OUT, "ref_date.png"))
# 底部导航文字
crop_zoom(os.path.join(FRAMES, "f00300.jpg"), (40, 800, 380, 890), 4,
          os.path.join(OUT, "ref_nav.png"))

# 2) 用工程自带字体渲染同样的文字
render_fonts("有限责任公司 · 股份有限公司", 24, os.path.join(OUT, "cmp_body.png"), "body 24px")
render_fonts("创立房地产公司", 30, os.path.join(OUT, "cmp_h1.png"), "h1 30px")
render_fonts("现金 总资产 负债率", 20, os.path.join(OUT, "cmp_stat.png"), "stat 20px")
render_fonts("地产风云：完全模拟现实 2001年01月01日 1.00亿 0万 70分", 22,
             os.path.join(OUT, "cmp_mix.png"), "mix 22px")

"""字体子集化：把工程自带的 4 个 TTF 压成 WOFF2，并生成 css/fonts.css。

字符集策略：
  1. 工程全部 .lua 源码里出现过的字符（游戏自身文案，精确覆盖）
  2. ASCII 可打印 + CJK 标点 + 全角符号 + 游戏用到的几何符号/箭头
  3. GB2312 一二级汉字（6763 字）——覆盖玩家自己输入的公司名等任意中文
未覆盖的生僻字由系统字体兜底（字体栈里排在后面）。

用法：python tools/build_fonts.py
"""
import os
import sys
import glob
import subprocess

WEB = r"D:\2026\ai\2\地产风云_web"
SRC = r"D:\2026\ai\2\地产风云\src"
FONTS_SRC = os.path.join(SRC, "Fonts")
OUT_DIR = os.path.join(WEB, "vendor", "fonts")
CSS_OUT = os.path.join(WEB, "css", "fonts.css")

# 工程实际用到的符号（来自 UITheme.NavItems 与各屏文案）
EXTRA_SYMBOLS = "■▲△★◎◆◇○☆⚙⏸▶◀←→↑↓▸▍·•…—–、。，！？：；“”‘’（）《》【】"

FACES = [
    # (输出名, 源文件, 说明)
    ("NotoSansSC", "NotoSansSC-Regular.ttf", "正文默认字体（Bold 与 Regular 字节相同，只出一份）"),
    ("FusionPixelProp", "FusionPixel-12px-Prop-zh_hans.ttf", "像素比例字体"),
    ("FusionPixelPropBold", "FusionPixel-12px-Prop-zh_hans-Bold.ttf", "像素比例粗体"),
    ("FusionPixelMono", "FusionPixel-12px-Mono-zh_hans.ttf", "像素等宽字体"),
]


def collect_chars():
    chars = set()
    files = 0
    for path in glob.glob(os.path.join(SRC, "**", "*.lua"), recursive=True):
        files += 1
        with open(path, "r", encoding="utf-8", errors="ignore") as fp:
            chars.update(fp.read())
    # ASCII 可打印
    chars.update(chr(c) for c in range(0x20, 0x7F))
    chars.update("\t\n")
    # CJK 标点 / 全角 / 常用符号区
    for lo, hi in [(0x3000, 0x303F), (0xFF00, 0xFFEF), (0x2000, 0x206F),
                   (0x25A0, 0x25FF), (0x2190, 0x21FF), (0x2460, 0x24FF)]:
        chars.update(chr(c) for c in range(lo, hi + 1))
    chars.update(EXTRA_SYMBOLS)
    # GB2312 一二级汉字（6763 字），覆盖玩家自由输入
    gb = 0
    for hi in range(0xB0, 0xF8):
        for lo in range(0xA1, 0xFF):
            try:
                ch = bytes([hi, lo]).decode("gb2312")
            except UnicodeDecodeError:
                continue
            if len(ch) == 1:
                chars.add(ch)
                gb += 1
    chars.discard("\x00")
    return "".join(sorted(chars)), files, gb


def main():
    if not os.path.isdir(FONTS_SRC):
        print("找不到字体目录: " + FONTS_SRC)
        sys.exit(1)
    os.makedirs(OUT_DIR, exist_ok=True)

    text, files, gb = collect_chars()
    print(f"扫描 {files} 个 lua 文件；字符集共 {len(text)} 个字符（其中 GB2312 汉字 {gb} 个）")

    txt_path = os.path.join(OUT_DIR, "_charset.txt")
    with open(txt_path, "w", encoding="utf-8") as fp:
        fp.write(text)

    css_blocks = []
    total_before = 0
    total_after = 0
    built = {}

    for name, src_name, note in FACES:
        src = os.path.join(FONTS_SRC, src_name)
        if not os.path.exists(src):
            print(f"  跳过（不存在）: {src_name}")
            continue
        before = os.path.getsize(src)
        total_before += before
        dst = os.path.join(OUT_DIR, name + ".woff2")
        cmd = [
            sys.executable, "-m", "fontTools.subset", src,
            f"--text-file={txt_path}",
            "--flavor=woff2",
            "--layout-features=*",
            "--no-hinting",
            "--desubroutinize",
            f"--output-file={dst}",
        ]
        r = subprocess.run(cmd, capture_output=True, text=True)
        if r.returncode != 0 or not os.path.exists(dst):
            print(f"  失败 {name}: {r.stderr.strip()[:300]}")
            continue
        after = os.path.getsize(dst)
        total_after += after
        built[name] = dst
        print(f"  {name:22} {before/1024/1024:6.2f} MB -> {after/1024:7.1f} KB  ({note})")

    def face(family, weight, file_name):
        return (
            "@font-face {\n"
            f"  font-family: \"{family}\";\n"
            "  font-style: normal;\n"
            f"  font-weight: {weight};\n"
            "  font-display: swap;\n"
            f"  src: url(\"../vendor/fonts/{file_name}.woff2\") format(\"woff2\");\n"
            "}"
        )

    if "NotoSansSC" in built:
        # 忠实模式：700 也指向同一份字形 —— 与原包一致（原包 Bold 与 Regular 字节相同，粗体不生效）
        css_blocks.append(face("NotoSansSCF", 400, "NotoSansSC"))
        css_blocks.append(face("NotoSansSCF", 700, "NotoSansSC"))
        # 合成粗体模式：只声明 400，700 交给浏览器合成
        css_blocks.append(face("NotoSansSC", 400, "NotoSansSC"))
    if "FusionPixelProp" in built:
        css_blocks.append(face("FusionPixelProp", 400, "FusionPixelProp"))
    if "FusionPixelPropBold" in built:
        css_blocks.append(face("FusionPixelProp", 700, "FusionPixelPropBold"))
    if "FusionPixelMono" in built:
        css_blocks.append(face("FusionPixelMono", 400, "FusionPixelMono"))

    header = (
        "/* 由 tools/build_fonts.py 自动生成，请勿手改。\n"
        f"   子集字符数 {len(text)}（含 GB2312 一二级汉字 {gb}，覆盖玩家自由输入的中文），"
        f"{total_before/1024/1024:.1f} MB TTF -> {total_after/1024:.0f} KB WOFF2。\n"
        "   未覆盖的生僻字由字体栈后面的系统字体兜底。\n"
        "   NotoSansSC-Bold 与 Regular 在原始包内字节完全相同（MD5 一致），\n"
        "   所以默认使用 NotoSansSCF：两档字重指向同一套字形，粗体不会真的变粗——与引擎行为一致。\n"
        "   若要改用浏览器合成粗体（视觉更接近 fontWeight=\"bold\" 的意图），\n"
        "   给 <html> 加 class=\"synth-bold\" 即可（见 css/app.css）。*/\n\n"
    )
    with open(CSS_OUT, "w", encoding="utf-8") as fp:
        fp.write(header + "\n\n".join(css_blocks) + "\n")

    print(f"\nCSS 已写出: {CSS_OUT}")
    print(f"合计 {total_before/1024/1024:.1f} MB -> {total_after/1024:.0f} KB")

    # 覆盖率自检：子集字体必须覆盖字符集里的每一个字
    try:
        from fontTools.ttLib import TTFont
    except ImportError:
        return
    print("\n=== 覆盖率自检 ===")
    for name, dst in built.items():
        font = TTFont(dst)
        cmap = set()
        for table in font["cmap"].tables:
            cmap.update(table.cmap.keys())
        missing = [c for c in set(text) if ord(c) not in cmap and c not in "\t\n"]
        status = "OK" if not missing else f"缺 {len(missing)} 个: {''.join(missing[:20])}"
        print(f"  {name:22} 覆盖 {len(cmap)} 码位  {status}")


if __name__ == "__main__":
    main()

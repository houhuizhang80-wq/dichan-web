"""检查「UI 实际会显示的文案」是否被字体子集完整覆盖。

区分三类字符：
  1. 注释里的字符 —— 不影响渲染
  2. 字符串字面量里的字符 —— 可能渲染
  3. 真正作为 text/title/label/placeholder 传入的字符 —— 一定会渲染
"""
import os
import re
import glob
import sys
from fontTools.ttLib import TTFont

SRC = r"D:\2026\ai\2\地产风云\src"
WEB = r"D:\2026\ai\2\地产风云_web"

TOKEN_RE = re.compile(
    r'(?P<comment>--\[\[.*?\]\]|--[^\n]*)'
    r'|(?P<longstr>\[\[.*?\]\]|\[=\[.*?\]=\])'
    r'|(?P<str>"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\')',
    re.DOTALL,
)

# 明确作为可见文案传入的键
TEXT_KEYS = re.compile(
    r'\b(?:text|title|label|placeholder|subtitle|name|desc|note|message|msg)\s*=\s*'
    r'("(?:\\.|[^"\\])*")',
    re.DOTALL,
)


def load_cmap(path):
    font = TTFont(path)
    cmap = set()
    for table in font["cmap"].tables:
        cmap.update(table.cmap.keys())
    return cmap


def main():
    literal_chars = set()
    text_chars = set()
    comment_chars = set()
    text_samples = {}

    for path in glob.glob(os.path.join(SRC, "**", "*.lua"), recursive=True):
        with open(path, "r", encoding="utf-8", errors="ignore") as fp:
            src = fp.read()
        for m in TOKEN_RE.finditer(src):
            kind = m.lastgroup
            val = m.group()
            if kind == "comment":
                comment_chars.update(val)
            else:
                literal_chars.update(val)
        for m in TEXT_KEYS.finditer(src):
            # 直接取原文（源文件是 UTF-8）；不要用 unicode_escape，否则中文会被二次解码成乱码
            s = m.group(1)[1:-1]
            s = s.replace("\\n", "\n").replace("\\t", "\t")
            text_chars.update(s)
            for ch in s:
                text_samples.setdefault(ch, os.path.basename(path))

    for label, chars in [("字符串字面量", literal_chars),
                         ("可见文案(text/title/label/placeholder)", text_chars)]:
        print(f"\n=== {label}：{len(chars)} 个字符 ===")

    cmap = load_cmap(os.path.join(WEB, "vendor", "fonts", "NotoSansSC.woff2"))
    missing_text = sorted(c for c in text_chars if ord(c) not in cmap and c not in "\t\n")
    missing_lit = sorted(c for c in literal_chars if ord(c) not in cmap and c not in "\t\n")

    print(f"\nNotoSansSC 子集覆盖 {len(cmap)} 码位")
    print(f"可见文案缺字 {len(missing_text)} 个: " + "".join(missing_text[:80]))
    print(f"字面量缺字   {len(missing_lit)} 个: " + "".join(missing_lit[:80]))

    if missing_text:
        print("\n可见文案缺字明细：")
        for c in missing_text:
            print(f"  U+{ord(c):04X} {c!r}  <- {text_samples.get(c, '?')}")

    # 注释里出现但文案里没有的字符，属于扫描噪声
    noise = sorted((comment_chars - text_chars))
    print(f"\n（注释中的字符 {len(comment_chars)} 个，其中 {len(noise)} 个不出现在文案里，属扫描噪声）")


if __name__ == "__main__":
    main()

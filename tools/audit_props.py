"""扫描工程里所有 UI.<控件>{...} 调用点，抽取 props 键名，核对渲染层映射覆盖率。

要点：必须真正做词法分析——props 表里嵌着 function() ... end 闭包，
闭包体内的 `local ok, msg = ...` 不是 props 键（早期版本的正则实现会误收 31 个这种键）。

用法：python tools/audit_props.py
"""
import os
import re
import sys
import json
from collections import Counter, defaultdict

SRC = r"D:\2026\ai\2\地产风云\src"
OUT_DIR = os.path.dirname(os.path.abspath(__file__))

WIDGETS = ["Panel", "Layout", "Label", "Button", "TextField", "ScrollView", "Checkbox", "Slider"]

# 渲染层已明确处理的键（与 js/bridge.js 的 CSS_MAP / 特殊处理保持一致）
HANDLED_CSS = {
    "flexDirection", "flexWrap", "justifyContent", "alignItems", "alignSelf", "alignContent",
    "flexGrow", "flexShrink", "flexBasis", "flex", "gap", "rowGap", "columnGap",
    "padding", "paddingHorizontal", "paddingVertical", "paddingTop", "paddingBottom",
    "paddingLeft", "paddingRight",
    "margin", "marginHorizontal", "marginVertical", "marginTop", "marginBottom",
    "marginLeft", "marginRight",
    "width", "height", "minWidth", "maxWidth", "minHeight", "maxHeight",
    "left", "top", "right", "bottom",
    "backgroundColor", "borderWidth", "borderColor", "borderTopWidth", "borderBottomWidth",
    "borderLeftWidth", "borderRightWidth",
    "borderRadius", "opacity", "overflow", "zIndex",
    "fontSize", "fontColor", "fontWeight", "fontFamily", "textAlign", "lineHeight",
    "textDecorationLine",
}
HANDLED_SPECIAL = {
    "text", "children", "id", "onClick", "onChange", "disabled",
    "whiteSpace", "maxLines", "verticalAlign", "positionType", "boxShadow",
    "scrollY", "scrollX", "value", "placeholder", "keyboardType", "maxLength",
    "checked", "label", "min", "max", "step", "variant", "dot",
}

TOKEN_RE = re.compile(
    r"""
    (?P<ws>\s+)
  | (?P<comment>--\[\[.*?\]\]|--[^\n]*)
  | (?P<longstr>\[\[.*?\]\]|\[=\[.*?\]=\])
  | (?P<str>"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')
  | (?P<num>\d+\.?\d*(?:[eE][+-]?\d+)?|0[xX][0-9a-fA-F]+)
  | (?P<name>[A-Za-z_]\w*)
  | (?P<op>\.\.\.|\.\.|==|~=|<=|>=|//|<<|>>|::|[-+*/%^#<>=(){}\[\];:,.])
    """,
    re.VERBOSE | re.DOTALL,
)

# 块级关键字（会消耗一个 end）
BLOCK_OPENERS = {"function", "if", "for", "while", "do"}


def tokenize(text):
    """产出 (kind, value, offset) 序列"""
    pos = 0
    line = 1
    out = []
    while pos < len(text):
        m = TOKEN_RE.match(text, pos)
        if not m:
            pos += 1
            continue
        kind = m.lastgroup
        val = m.group()
        out.append((kind, val, pos, line))
        line += val.count("\n")
        pos = m.end()
    return out


def find_widget_calls(tokens):
    """找出 UI.<Widget> { 的位置，返回 [(widget, brace_index, line)]"""
    calls = []
    for i in range(len(tokens) - 3):
        k0, v0, _, line = tokens[i]
        if k0 != "name" or v0 != "UI":
            continue
        k1, v1 = tokens[i + 1][0], tokens[i + 1][1]
        if k1 != "op" or v1 != ".":
            continue
        k2, v2 = tokens[i + 2][0], tokens[i + 2][1]
        if k2 != "name" or v2 not in WIDGETS:
            continue
        k3, v3 = tokens[i + 3][0], tokens[i + 3][1]
        if k3 == "op" and v3 == "{":
            calls.append((v2, i + 3, line))
    return calls


def extract_keys(tokens, brace_idx):
    """从 { 开始提取 props 键：仅取 table 深度 == 1 且不在任何 function/if/loop 块内、不在括号内的标识符= """
    keys = []
    depth = 0          # {} 深度
    blocks = 0         # function/if/for/while/do 嵌套
    parens = 0
    prev_kw = None
    i = brace_idx
    n = len(tokens)

    while i < n:
        kind, val, _, _ = tokens[i]
        if kind in ("ws", "comment"):
            i += 1
            continue

        if kind == "op":
            if val == "{":
                depth += 1
            elif val == "}":
                depth -= 1
                if depth == 0:
                    break
            elif val == "(":
                parens += 1
            elif val == ")":
                parens -= 1
            elif val == "[":
                parens += 1
            elif val == "]":
                parens -= 1
            elif val == "=" and depth == 1 and blocks == 0 and parens == 0:
                # 回看：前一个 token 必须是标识符
                j = i - 1
                while j >= 0 and tokens[j][0] in ("ws", "comment"):
                    j -= 1
                if j >= 0 and tokens[j][0] == "name":
                    name = tokens[j][1]
                    # 排除 `a == b`（已由 op 匹配排除）与 `local x =`（在 table 里不会出现）
                    keys.append((name, tokens[j][3]))
            i += 1
            prev_kw = None
            continue

        if kind == "name":
            if val in BLOCK_OPENERS:
                if val == "do" and prev_kw in ("for", "while"):
                    pass  # for/while 的 do 不额外开块
                else:
                    blocks += 1
            elif val == "end":
                blocks -= 1
            elif val == "until":
                blocks -= 1
            prev_kw = val
            i += 1
            continue

        prev_kw = None
        i += 1

    return keys


def main():
    if not os.path.isdir(SRC):
        print("找不到源码目录: " + SRC)
        sys.exit(1)

    per_widget = defaultdict(Counter)
    all_keys = Counter()
    unknown = Counter()
    unknown_sites = defaultdict(list)
    files = 0
    calls = 0
    key_lines = defaultdict(list)

    for root, _dirs, names in os.walk(SRC):
        for name in sorted(names):
            if not name.endswith(".lua"):
                continue
            files += 1
            path = os.path.join(root, name)
            with open(path, "r", encoding="utf-8") as fp:
                text = fp.read()
            rel = os.path.relpath(path, SRC)
            tokens = tokenize(text)
            # 去掉空白与注释，便于结构化匹配（行号仍保留在 token 里）
            tokens = [t for t in tokens if t[0] not in ("ws", "comment")]
            for widget, brace_idx, _line in find_widget_calls(tokens):
                calls += 1
                seen = set()
                for key, line in extract_keys(tokens, brace_idx):
                    if key in seen:
                        continue
                    seen.add(key)
                    per_widget[widget][key] += 1
                    all_keys[key] += 1
                    key_lines[key].append(f"{rel}:{line}")
                    if key not in HANDLED_CSS and key not in HANDLED_SPECIAL:
                        unknown[key] += 1
                        if len(unknown_sites[key]) < 4:
                            unknown_sites[key].append(f"{rel}:{line}")

    print(f"扫描 {files} 个 lua 文件，{calls} 处 UI.<控件>{{}} 调用点\n")
    print("=== 每个控件用到的 props ===")
    for w in WIDGETS:
        if not per_widget[w]:
            continue
        items = ", ".join(f"{k}×{v}" for k, v in per_widget[w].most_common())
        print(f"\n[{w}] {len(per_widget[w])} 种\n  {items}")

    print(f"\n=== 全部 props 键：{len(all_keys)} 种 ===")
    print(", ".join(f"{k}({v})" for k, v in all_keys.most_common()))

    print(f"\n=== 渲染层未覆盖的键：{len(unknown)} 种 ===")
    if unknown:
        for k, v in unknown.most_common():
            print(f"  {k:22} ×{v:<4} 例: {unknown_sites[k][0]}")
    else:
        print("  （无）")

    with open(os.path.join(OUT_DIR, "props_report.json"), "w", encoding="utf-8") as fp:
        json.dump({
            "calls": calls,
            "all": dict(all_keys),
            "perWidget": {w: dict(per_widget[w]) for w in WIDGETS},
            "uncovered": dict(unknown),
            "uncoveredSites": {k: v for k, v in unknown_sites.items()},
        }, fp, ensure_ascii=False, indent=2)
    print("\n已写出 tools/props_report.json")


if __name__ == "__main__":
    main()

// ============================================================================
// js/audit.js —— 真实浏览器内的布局体检（?audit=1）
// 在浏览器里逐屏渲染，量测每个节点的几何与计算样式，找出：
//   · 横向溢出 / 被父容器裁掉
//   · 有文字但尺寸为 0
//   · 文字被裁（scrollWidth/Height 超出可视区）
//   · 实际用到的字号 / 边框宽度 / 文字颜色集合（用于与 UITheme 令牌核对）
// 结果写进 <pre id="audit-report">，由 tools/browser-audit.mjs 用 --dump-dom 取回。
// ============================================================================

export const SCREENS = [
  'start', 'changelog', 'companyCreate', 'city', 'dashboard', 'invest', 'auction',
  'project', 'sales', 'asset', 'capital', 'brand', 'personal', 'personalLife',
  'personalFinance', 'governance', 'group', 'international',
  'groupDiversification', 'settings', 'ledger', 'inheritance',
];

function kindOf(el) {
  return el.getAttribute('data-kind') || el.tagName.toLowerCase();
}

/** 从根到该节点的控件路径，便于定位问题（如 Panel>Panel>Button） */
function pathOf(el) {
  const parts = [];
  let cur = el;
  while (cur && cur.id !== 'app') {
    const k = kindOf(cur);
    const id = cur.getAttribute('data-ui-id');
    parts.unshift(id ? `${k}#${id}` : k);
    cur = cur.parentElement;
  }
  return parts.join('>');
}

/** 取节点自身的文字（不含子节点） */
function ownText(el) {
  let s = '';
  for (const n of el.childNodes) {
    if (n.nodeType === 3) s += n.nodeValue;
  }
  return s.trim();
}

/**
 * 横向越界量测：找出「子元素右边缘超出父容器内容盒」的所有节点。
 *
 * 注意：不要用 `scrollWidth > clientWidth` 来判断——对 `overflow: visible` 的容器
 * 这个值并不可靠（Chrome 会钳到 padding box），实测会漏掉 invest 屏那张
 * 超出 106px 的 StatCard。直接比较父子 getBoundingClientRect 才稳。
 */
export function measureOverflow(doc, root) {
  const rows = [];
  const walk = (el) => {
    const r = el.getBoundingClientRect();
    const p = el.parentElement;
    if (p && p.id !== 'app') {
      const pr = p.getBoundingClientRect();
      const pcs = doc.defaultView.getComputedStyle(p);
      const right = pr.right - parseFloat(pcs.borderRightWidth || 0) - parseFloat(pcs.paddingRight || 0);
      const left = pr.left + parseFloat(pcs.borderLeftWidth || 0) + parseFloat(pcs.paddingLeft || 0);
      const overRight = r.right - right;
      const overLeft = left - r.left;
      if (overRight > 0.5 || overLeft > 0.5) {
        rows.push({
          kind: el.getAttribute('data-kind') || el.tagName.toLowerCase(),
          path: pathOf(el),
          id: el.getAttribute('data-ui-id') || '',
          over: Math.round(Math.max(overRight, overLeft) * 10) / 10,
          w: Math.round(r.width),
          parentW: Math.round(pr.width),
          parentOverflow: pcs.overflowX,
          text: (el.textContent || '').replace(/\s+/g, ' ').trim().slice(0, 20),
        });
      }
    }
    for (const c of el.children) walk(c);
  };
  if (root) walk(root);
  return rows;
}

export function auditScreen(doc, screen) {
  const app = doc.getElementById('app');
  const root = app && app.firstElementChild;
  const out = {
    screen,
    nodes: 0,
    maxDepth: 0,
    overflowX: [],
    overflowY: [],
    outOfParent: [],
    zeroSizeText: [],
    clippedText: [],
    fontSizes: {},
    borderWidths: {},
    textColors: {},
    kinds: {},
  };
  if (!root) {
    out.error = '未渲染任何节点';
    return out;
  }

  const walk = (el, depth) => {
    out.nodes++;
    if (depth > out.maxDepth) out.maxDepth = depth;
    const kind = kindOf(el);
    out.kinds[kind] = (out.kinds[kind] || 0) + 1;

    const r = el.getBoundingClientRect();
    const cs = doc.defaultView.getComputedStyle(el);

    // 字号 / 文字颜色统计（只统计有直接文字的节点）
    const text = ownText(el);
    if (text) {
      out.fontSizes[cs.fontSize] = (out.fontSizes[cs.fontSize] || 0) + 1;
      out.textColors[cs.color] = (out.textColors[cs.color] || 0) + 1;
    }

    // 横向溢出
    if (el.scrollWidth > el.clientWidth + 1 && el.clientWidth > 0) {
      out.overflowX.push({
        kind,
        path: pathOf(el),
        id: el.getAttribute('data-ui-id') || '',
        client: el.clientWidth,
        scroll: el.scrollWidth,
        text: text.slice(0, 24),
      });
    }
    if (el.scrollHeight > el.clientHeight + 1 && el.clientHeight > 0 &&
        cs.overflowY !== 'auto' && cs.overflowY !== 'scroll') {
      out.overflowY.push({
        kind,
        path: pathOf(el),
        id: el.getAttribute('data-ui-id') || '',
        client: el.clientHeight,
        scroll: el.scrollHeight,
        text: text.slice(0, 24),
      });
    }

    // 超出父容器可视范围
    const parent = el.parentElement;
    if (parent && parent.id !== 'app') {
      const pr = parent.getBoundingClientRect();
      const pcs = doc.defaultView.getComputedStyle(parent);
      const right = pr.right - parseFloat(pcs.borderRightWidth || 0) - parseFloat(pcs.paddingRight || 0);
      const bottom = pr.bottom - parseFloat(pcs.borderBottomWidth || 0) - parseFloat(pcs.paddingBottom || 0);
      if (r.right > right + 1.5 || r.left < pr.left - 1.5) {
        out.outOfParent.push({
          kind,
          path: pathOf(el),
          id: el.getAttribute('data-ui-id') || '',
          overflowPx: Math.round(Math.max(r.right - right, pr.left - r.left)),
          text: text.slice(0, 24),
        });
      }
      if (r.bottom > bottom + 1.5 && pcs.overflowY === 'visible') {
        out.outOfParent.push({
          kind,
          path: pathOf(el),
          id: el.getAttribute('data-ui-id') || '',
          overflowPx: Math.round(r.bottom - bottom),
          axis: 'y',
          text: text.slice(0, 24),
        });
      }
    }

    // 有文字但尺寸为 0
    if (text && (r.width < 1 || r.height < 1)) {
      out.zeroSizeText.push({
        kind, path: pathOf(el), text: text.slice(0, 24),
        w: Math.round(r.width), h: Math.round(r.height),
      });
    }

    // 边框抽样：记录带边框的节点（用于核对 UITheme 的 DividerWidth / 按钮 borderWidth）
    if ((kind === 'Panel' || kind === 'Button') && cs.borderTopWidth !== '0px') {
      const key = `${cs.borderTopWidth} ${cs.borderTopColor}`;
      out.borderWidths[key] = (out.borderWidths[key] || 0) + 1;
    }

    for (const child of el.children) walk(child, depth + 1);
  };

  walk(root, 1);

  // 用可靠的父子包围盒比较覆盖一次「横向越界」结果
  out.outOfParent = measureOverflow(doc, root);

  // 明细只保留前若干条，避免报告过大
  const cap = (arr, n = 6) => arr.slice(0, n);
  out.overflowX = cap(out.overflowX);
  out.overflowY = cap(out.overflowY);
  out.outOfParent = cap(out.outOfParent);
  out.zeroSizeText = cap(out.zeroSizeText);
  return out;
}

export function runAudit(doc, lua) {
  const results = [];
  for (const screen of SCREENS) {
    try {
      lua.global.get('__webNavigate')(screen);
      results.push(auditScreen(doc, screen));
    } catch (e) {
      results.push({ screen, error: String(e && e.message ? e.message : e) });
    }
  }
  const pre = doc.createElement('pre');
  pre.id = 'audit-report';
  pre.textContent = JSON.stringify({ screens: results, ua: navigator.userAgent }, null, 1);
  doc.body.appendChild(pre);
  return results;
}

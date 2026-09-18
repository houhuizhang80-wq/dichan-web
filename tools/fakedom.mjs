// ============================================================================
// tools/fakedom.mjs —— 无头测试用的极简 DOM（只实现渲染层实际用到的接口）
// ============================================================================

class El {
  constructor(tag) {
    this.tagName = String(tag).toUpperCase();
    this.style = {};
    this.attributes = {};
    this.children = [];
    this.listeners = {};
    this._text = '';
    this._scrollTop = 0;
    this._scrollLeft = 0;
  }

  set textContent(v) {
    this._text = String(v);
    this.children = [];
  }
  get textContent() {
    return this._text;
  }

  appendChild(child) {
    this.children.push(child);
    return child;
  }

  replaceChildren(...nodes) {
    this.children = nodes;
  }

  setAttribute(k, v) {
    this.attributes[k] = String(v);
  }
  getAttribute(k) {
    return this.attributes[k];
  }

  addEventListener(type, fn) {
    (this.listeners[type] = this.listeners[type] || []).push(fn);
  }

  dispatch(type, ev) {
    const fns = this.listeners[type] || [];
    for (const fn of fns) fn(ev || { preventDefault() {}, stopPropagation() {} });
    return fns.length;
  }

  get scrollTop() {
    return this._scrollTop;
  }
  set scrollTop(v) {
    this._scrollTop = v;
  }
  get scrollLeft() {
    return this._scrollLeft;
  }
  set scrollLeft(v) {
    this._scrollLeft = v;
  }
}

export function createFakeDOM() {
  const app = new El('div');

  const walk = (el, fn) => {
    fn(el);
    for (const c of el.children || []) walk(c, fn);
  };

  const doc = {
    title: '',
    createElement: (tag) => new El(tag),
    getElementById: (id) => (id === 'app' ? app : null),
    querySelector: (sel) => {
      const m = /^\[data-(uid|ui-id)="(.*)"\]$/.exec(sel);
      if (!m) return null;
      const key = m[1] === 'uid' ? 'data-uid' : 'data-ui-id';
      let hit = null;
      walk(app, (el) => {
        if (!hit && el.attributes[key] === m[2]) hit = el;
      });
      return hit;
    },
  };

  return {
    doc,
    app,
    walk,
    /** 收集整棵树的文本（用于断言渲染结果） */    texts: () => {
      const out = [];
      walk(app, (el) => {
        const t = (el.textContent || '').trim();
        if (t) out.push(t);
      });
      return out;
    },
    /** 统计节点数 */
    count: () => {
      let n = 0;
      walk(app, () => n++);
      return n;
    },
    /** 按文本查找元素 */
    findByText: (text) => {
      let hit = null;
      walk(app, (el) => {
        if (!hit && el._text === text) hit = el;
      });
      return hit;
    },
    /** 找所有含 onClick 监听的元素（按钮） */
    clickables: () => {
      const out = [];
      walk(app, (el) => {
        if ((el.listeners.click || []).length) out.push(el);
      });
      return out;
    },
    serialize: (el) => serialize(el || app),
  };
}

// ---------------------------------------------------------------------------
// 序列化为 HTML（用于离线快照审阅渲染结果）
// ---------------------------------------------------------------------------
const escapeText = (s) =>
  String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const escapeAttr = (s) =>
  String(s).replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;');

export function serialize(el, indent = 0) {
  const pad = '  '.repeat(indent);
  const tag = el.tagName.toLowerCase();
  const style = Object.entries(el.style || {})
    .filter(([, v]) => v !== undefined && v !== null && v !== '')
    .map(([k, v]) => `${k}:${v}`)
    .join(';');

  const attrs = [];
  if (style) attrs.push(`style="${escapeAttr(style)}"`);
  if (el.attributes && el.attributes['data-ui-id']) {
    attrs.push(`data-ui-id="${escapeAttr(el.attributes['data-ui-id'])}"`);
  }

  if (tag === 'input') {
    attrs.push(`type="${escapeAttr(el.type || 'text')}"`);
    if (el.placeholder !== undefined) attrs.push(`placeholder="${escapeAttr(el.placeholder)}"`);
    if (el.value !== undefined) attrs.push(`value="${escapeAttr(el.value)}"`);
    if (el.checked) attrs.push('checked');
    if (el.min !== undefined) attrs.push(`min="${escapeAttr(el.min)}"`);
    if (el.max !== undefined) attrs.push(`max="${escapeAttr(el.max)}"`);
    if (el.step !== undefined) attrs.push(`step="${escapeAttr(el.step)}"`);
    return `${pad}<${tag} ${attrs.join(' ')} />`;
  }

  const text = escapeText(el.textContent || '');
  const kids = (el.children || []).map((c) => serialize(c, indent + 1)).join('\n');
  if (!kids && !text) return `${pad}<${tag} ${attrs.join(' ')}></${tag}>`;
  return `${pad}<${tag} ${attrs.join(' ')}>${text}${kids ? '\n' + kids + '\n' + pad : ''}</${tag}>`;
}

// ============================================================================
// js/bridge.js —— urhox-libs/UI 的浏览器渲染层 + WebBridge 宿主接口
// 浏览器与 Node（无头测试）通用：DOM 与存储均由外部注入。
//
// props 覆盖情况由 tools/audit_props.py 全量核对：
//   工程共 2571 处 UI.<控件>{} 调用点、68 种 props 键，全部在此映射或有意忽略。
// ============================================================================

// ---------------------------------------------------------------------------
// props -> CSS
// ---------------------------------------------------------------------------
const CSS_MAP = {
  // flex 容器
  flexDirection: 'flex-direction',
  flexWrap: 'flex-wrap',
  justifyContent: 'justify-content',
  alignItems: 'align-items',
  alignSelf: 'align-self',
  alignContent: 'align-content',
  flexGrow: 'flex-grow',
  flexShrink: 'flex-shrink',
  flexBasis: 'flex-basis',
  flex: 'flex',
  gap: 'gap',
  rowGap: 'row-gap',
  columnGap: 'column-gap',
  // 盒模型
  padding: 'padding',
  paddingHorizontal: ['padding-left', 'padding-right'],
  paddingVertical: ['padding-top', 'padding-bottom'],
  paddingTop: 'padding-top',
  paddingBottom: 'padding-bottom',
  paddingLeft: 'padding-left',
  paddingRight: 'padding-right',
  margin: 'margin',
  marginHorizontal: ['margin-left', 'margin-right'],
  marginVertical: ['margin-top', 'margin-bottom'],
  marginTop: 'margin-top',
  marginBottom: 'margin-bottom',
  marginLeft: 'margin-left',
  marginRight: 'margin-right',
  width: 'width',
  height: 'height',
  minWidth: 'min-width',
  maxWidth: 'max-width',
  minHeight: 'min-height',
  maxHeight: 'max-height',
  // 定位
  left: 'left',
  top: 'top',
  right: 'right',
  bottom: 'bottom',
  // 外观
  backgroundColor: 'background-color',
  borderWidth: 'border-width',
  borderColor: 'border-color',
  borderTopWidth: 'border-top-width',
  borderBottomWidth: 'border-bottom-width',
  borderLeftWidth: 'border-left-width',
  borderRightWidth: 'border-right-width',
  borderRadius: 'border-radius',
  opacity: 'opacity',
  overflow: 'overflow',
  zIndex: 'z-index',
  // 文字
  fontSize: 'font-size',
  fontColor: 'color',
  fontWeight: 'font-weight',
  fontFamily: 'font-family',
  textAlign: 'text-align',
  lineHeight: 'line-height',
  textDecorationLine: 'text-decoration-line',
};

// 不需要加 px 的属性
const UNITLESS = new Set(['flexGrow', 'flexShrink', 'opacity', 'zIndex', 'fontWeight', 'lineHeight', 'flex']);

// 颜色类属性（值是 {r,g,b,a} 数组）
const COLOR_PROPS = new Set(['backgroundColor', 'borderColor', 'fontColor']);

// 由渲染层专门处理、不进 CSS_MAP 的键
const SPECIAL = new Set([
  'text', 'children', 'id', '__type', '__uid', '_className',
  'onClick', 'onChange', 'onSubmit', 'disabled',
  'whiteSpace', 'maxLines', 'verticalAlign', 'positionType', 'boxShadow',
  'scrollY', 'scrollX', 'value', 'placeholder', 'keyboardType', 'maxLength',
  'checked', 'label', 'min', 'max', 'step', 'variant', 'dot', 'size',
]);

// 主题里那些不是 CSS 的自定义令牌（渲染时忽略，避免污染 style）
const THEME_ONLY = new Set([
  'hoverBorderColor', 'focusBorderColor', 'disabledBorderColor',
  'headerBgColor', 'headerBorderWidth', 'footerBorderWidth', 'contentPadding',
  'contentGap', 'titleFontWeight', 'cellTextColor', 'rowOddBgColor',
  'rowEvenBgColor', 'rowHoverBgColor', 'rowBorderWidth', 'trackBgColor',
  'trackFillColor', 'thumbColor', 'thumbBorderColor', 'thumbBorderWidth',
  'activeBorderColor', 'inactiveTextColor', 'activeFontWeight', 'tabGap',
  'arrowColor', 'itemHoverBgColor', 'itemHoverTextColor', 'showIcon',
]);

const rgba = (c) => {
  if (typeof c === 'string') return c;
  if (!Array.isArray(c) || c.length < 3) return undefined;
  const a = c.length > 3 ? c[3] / 255 : 1;
  return `rgba(${c[0]},${c[1]},${c[2]},${Math.round(a * 1000) / 1000})`;
};

function toCssValue(prop, v) {
  if (prop === 'flexBasis' && v === 0) return '0%';
  if (typeof v === 'number') {
    if (UNITLESS.has(prop)) return String(v);
    return v + 'px';
  }
  return v;
}

// ---------------------------------------------------------------------------
// 按钮 variant / size（引擎内置的按钮变体，主题里没有直接给出，按主题色令牌推导）
// ---------------------------------------------------------------------------
const VARIANT_COLOR_KEYS = {
  primary: { bg: 'primary', fg: 'textInverse', border: 'primaryDeep' },
  secondary: { bg: 'secondary', fg: 'textInverse', border: 'secondaryDeep' },
  danger: { bg: 'danger', fg: 'textInverse', border: 'dangerPressed' },
  error: { bg: 'error', fg: 'textInverse', border: 'errorPressed' },
  success: { bg: 'success', fg: 'textInverse', border: 'successPressed' },
  warning: { bg: 'warning', fg: 'textInverse', border: 'warningPressed' },
  info: { bg: 'info', fg: 'textInverse', border: 'primaryDeep' },
  accent: { bg: 'accent', fg: 'textInverse', border: 'primaryDeep' },
  outline: { bg: 'transparent', fg: 'primary', border: 'primary' },
  ghost: { bg: 'transparent', fg: 'primary', border: 'transparent' },
};

const SIZE_PRESETS = {
  sm: { height: 32, fontSize: 11, paddingHorizontal: 10 },
  md: { height: 44, fontSize: 12, paddingHorizontal: 16 },
  lg: { height: 52, fontSize: 14, paddingHorizontal: 20 },
};

/**
 * 合并出「有效 props」：主题组件默认值 -> variant 配色 -> size 尺寸 -> 显式 props。
 * 显式 props 永远最后覆盖，保证工程里写死的颜色不被推导值改写。
 */
function resolveProps(node, theme) {
  const kind = node.__type;
  const out = {};

  const defaults = (theme && theme.components && theme.components[kind]) || null;
  if (defaults) {
    for (const [k, v] of Object.entries(defaults)) {
      if (THEME_ONLY.has(k)) continue;
      out[k] = v;
    }
  }

  if (kind === 'Button' && node.variant) {
    const colors = (theme && theme.colors) || {};
    const spec = VARIANT_COLOR_KEYS[String(node.variant)];
    if (spec) {
      const bg = colors[spec.bg] || (spec.bg === 'accent' ? [145, 102, 35, 255] : undefined);
      if (bg) out.backgroundColor = bg;
      if (colors[spec.fg]) out.fontColor = colors[spec.fg];
      if (colors[spec.border]) out.borderColor = colors[spec.border];
    }
  }

  if (kind === 'Button' && node.size && SIZE_PRESETS[String(node.size)]) {
    Object.assign(out, SIZE_PRESETS[String(node.size)]);
  }

  for (const [k, v] of Object.entries(node)) {
    if (v === undefined || v === null) continue;
    if (k === 'children') continue;
    out[k] = v;
  }
  return out;
}

function buildStyle(node, theme) {
  const kind = node.__type;
  const props = resolveProps(node, theme);
  const style = {};

  // Yoga 默认值：flex-direction: column、flex-shrink: 0、相对定位
  style.display = 'flex';
  style['flex-direction'] = 'column';
  style['flex-shrink'] = '0';
  style.position = 'relative';
  style['box-sizing'] = 'border-box';
  // 关键：CSS 默认 border-style: none，只设 border-width/color 是画不出边框的
  // （引擎里 borderWidth 直接就生效）。同时必须显式给 border-width: 0，
  // 否则 border-style: solid 会让 border-width 取初值 medium(=3px)、border-color 取 currentColor，
  // 于是每个节点都会凭空多出一圈 3px 的文字色边框。
  style['border-style'] = 'solid';
  style['border-width'] = '0';

  for (const [k, v] of Object.entries(props)) {
    if (SPECIAL.has(k)) continue;
    const css = CSS_MAP[k];
    if (!css) continue;
    const value = COLOR_PROPS.has(k) ? (rgba(v) ?? v) : toCssValue(k, v);
    if (Array.isArray(css)) css.forEach((c) => (style[c] = value));
    else style[css] = value;
  }

  // 阴影（值是数组：[{x,y,blur,color}]）
  const shadow = node.boxShadow;
  if (Array.isArray(shadow) && shadow.length) {
    style['box-shadow'] = shadow
      .map((s) => `${s.x || 0}px ${s.y || 0}px ${s.blur || 0}px ${rgba(s.color) || 'rgba(0,0,0,.2)'}`)
      .join(', ');
  }

  // 文字换行 / 行数限制
  // 引擎默认允许换行：CompanyCreateScreen 里 "以认缴出资额为限承担责任，决策灵活，适合中小企业"
  // 这个 Label 既没有 whiteSpace 也没有 maxLines，在官方演示视频里是折成两行显示的。
  if (kind === 'Label') {
    style['white-space'] = 'pre-wrap'; // 保留 \n 硬换行（工程里 4 处文案依赖它）
    style['word-break'] = 'break-word';
    if (node.maxLines) {
      style.display = '-webkit-box';
      style['-webkit-line-clamp'] = String(node.maxLines);
      style['-webkit-box-orient'] = 'vertical';
      style.overflow = 'hidden';
    }
    if (node.verticalAlign === 'center' || node.verticalAlign === 'bottom') {
      style.display = 'flex';
      style.flexDirection = 'column';
      style.justifyContent = node.verticalAlign === 'center' ? 'center' : 'flex-end';
      if (node.maxLines) {
        style.display = '-webkit-box';
        style['-webkit-box-orient'] = 'vertical';
      }
    }
  }

  // 滚动容器：交给浏览器原生滚动（惯性/回弹由 UA 实现）
  if (node.scrollY || node.scrollX) {
    if (node.scrollY) {
      style['overflow-y'] = 'auto';
      style['overflow-x'] = 'hidden';
    }
    if (node.scrollX) {
      style['overflow-x'] = 'auto';
      style['overflow-y'] = 'hidden';
    }
    style['-webkit-overflow-scrolling'] = 'touch';
    style['min-height'] = '0';
    style['overscroll-behavior'] = 'contain';
  }

  if (node.positionType === 'absolute') style.position = 'absolute';

  return style;
}

// ---------------------------------------------------------------------------
// 渲染器
// ---------------------------------------------------------------------------
export function createRenderer(doc, getTheme) {
  const TAG = {
    Panel: 'div',
    Layout: 'div',
    ScrollView: 'div',
    Label: 'div',
    Button: 'button',
    TextField: 'input',
  };

  function renderNode(node, ctx) {
    const kind = node.__type || 'Panel';
    const theme = getTheme();

    if (kind === 'Checkbox') return renderCheckbox(node, ctx, theme);
    if (kind === 'Slider') return renderSlider(node, ctx, theme);

    const el = doc.createElement(TAG[kind] || 'div');
    Object.assign(el.style, buildStyle(node, theme));

    if (node.__uid !== undefined) el.setAttribute('data-uid', String(node.__uid));
    if (node.id !== undefined) el.setAttribute('data-ui-id', String(node.id));
    el.setAttribute('data-kind', kind);

    if (kind === 'Button') {
      el.type = 'button';
      el.style.alignItems = el.style.alignItems || 'center';
      el.style.justifyContent = el.style.justifyContent || 'center';
      el.style.cursor = 'pointer';
      el.style.fontFamily = 'inherit';
      if (!el.style.padding) el.style.padding = '0';
      el.style.textAlign = el.style.textAlign || 'center';
    }

    if (kind === 'TextField') {
      el.type = 'text';
      if (node.value !== undefined) el.value = node.value;
      if (node.placeholder !== undefined) el.placeholder = node.placeholder;
      if (node.maxLength !== undefined) el.maxLength = node.maxLength;
      if (node.keyboardType === 'number' || node.keyboardType === 'decimal') el.inputMode = 'decimal';
      else if (node.keyboardType) el.inputMode = String(node.keyboardType);
      el.style.display = 'block';
      el.style.fontFamily = 'inherit';
      el.style.outline = 'none';
    } else if (node.text !== undefined && node.text !== null) {
      el.textContent = String(node.text);
    }

    if (node.disabled) {
      el.disabled = true;
      el.style.pointerEvents = 'none';
      el.style.opacity = el.style.opacity || '0.55';
    }

    wireEvents(el, node, kind, ctx);

    if (kind !== 'TextField') {
      const kids = node.children || [];
      for (let i = 0; i < kids.length; i++) el.appendChild(renderNode(kids[i], ctx));
    }

    return el;
  }

  function renderCheckbox(node, ctx, theme) {
    const wrap = doc.createElement('label');
    Object.assign(wrap.style, buildStyle(node, theme));
    wrap.style.flexDirection = 'row';
    wrap.style.alignItems = 'center';
    wrap.style.gap = '8px';
    wrap.style.cursor = 'pointer';
    if (node.__uid !== undefined) wrap.setAttribute('data-uid', String(node.__uid));
    if (node.id !== undefined) wrap.setAttribute('data-ui-id', String(node.id));
    wrap.setAttribute('data-kind', 'Checkbox');

    const input = doc.createElement('input');
    input.type = 'checkbox';
    input.checked = !!node.checked;
    input.style.flexShrink = '0';
    input.style.width = '16px';
    input.style.height = '16px';
    input.style.accentColor = rgba((theme && theme.colors && theme.colors.primary) || [38, 84, 124, 255]);

    const span = doc.createElement('span');
    span.textContent = node.label === undefined ? '' : String(node.label);
    span.style['word-break'] = 'break-word';
    span.style['white-space'] = 'pre-wrap';
    span.style.fontSize = 'inherit';

    wrap.appendChild(input);
    wrap.appendChild(span);

    const cb = node.onChange;
    if (cb && cb.__cb) input.addEventListener('change', () => ctx.invoke(cb.__cb, input.checked));
    input.addEventListener('focus', () => ctx.setFocus('Checkbox'));
    input.addEventListener('blur', () => ctx.setFocus(null));
    return wrap;
  }

  function renderSlider(node, ctx, theme) {
    const el = doc.createElement('input');
    el.type = 'range';
    Object.assign(el.style, buildStyle(node, theme));
    el.style.display = 'block';
    el.min = node.min !== undefined ? node.min : 0;
    el.max = node.max !== undefined ? node.max : 100;
    el.step = node.step !== undefined ? node.step : 1;
    el.value = node.value !== undefined ? node.value : el.min;
    const colors = (theme && theme.colors) || {};
    el.style.accentColor = rgba(colors.primary || [38, 84, 124, 255]);
    if (node.__uid !== undefined) el.setAttribute('data-uid', String(node.__uid));
    if (node.id !== undefined) el.setAttribute('data-ui-id', String(node.id));
    el.setAttribute('data-kind', 'Slider');

    const cb = node.onChange;
    if (cb && cb.__cb) el.addEventListener('input', () => ctx.invoke(cb.__cb, parseFloat(el.value)));
    el.addEventListener('focus', () => ctx.setFocus('Slider'));
    el.addEventListener('blur', () => ctx.setFocus(null));
    return el;
  }

  function wireEvents(el, node, kind, ctx) {
    const click = node.onClick;
    if (click && click.__cb) {
      el.addEventListener('click', (e) => {
        if (e && e.preventDefault) e.preventDefault();
        ctx.invoke(click.__cb);
      });
    }

    const change = node.onChange;
    if (change && change.__cb) {
      if (kind === 'TextField') el.addEventListener('input', () => ctx.invoke(change.__cb, el.value));
      else if (kind === 'Slider') el.addEventListener('input', () => ctx.invoke(change.__cb, parseFloat(el.value)));
    }

    // 输入框回车提交：工程里 3 处 TextField 用了 onSubmit
    const submit = node.onSubmit;
    if (kind === 'TextField' && submit && submit.__cb) {
      el.addEventListener('keydown', (e) => {
        if (e.key === 'Enter' || e.keyCode === 13) {
          e.preventDefault();
          ctx.invoke(submit.__cb, el.value);
        }
      });
    }

    // 焦点跟踪：UI.GetFocus() 会读 _className（main.lua 用它判断是否正在输入框里打字）
    if (kind === 'TextField' || kind === 'Button') {
      el.addEventListener('focus', () => ctx.setFocus(kind));
      el.addEventListener('blur', () => ctx.setFocus(null));
    }
  }

  return { renderNode };
}

// ---------------------------------------------------------------------------
// 虚拟文件系统
// ---------------------------------------------------------------------------
export function createVFS(adapter) {
  const norm = (p) => String(p).replace(/\\/g, '/').replace(/^\.\//, '');
  return {
    read: (p) => adapter.read(norm(p)),
    write: (p, t) => adapter.write(norm(p), t),
    exists: (p) => adapter.exists(norm(p)),
    del: (p) => adapter.del(norm(p)),
    mkdir: (p) => adapter.mkdir(norm(p)),
  };
}

// ---------------------------------------------------------------------------
// WebBridge：Lua 侧唯一宿主接口
// ---------------------------------------------------------------------------
export function createWebBridge({ doc, vfs, readModule, log, initialScreen, invokeRef, audio }) {
  const audioAdapter = audio || { play: () => 0, setGain: () => {} };
  let theme = null;
  let focusClass = null;
  let renderer = null;

  const find = (sel) => (doc.querySelector ? doc.querySelector(sel) : null);

  const applyDocumentDefaults = () => {
    const container = doc.getElementById('app');
    if (!container || !theme) return;
    const colors = theme.colors || {};
    if (colors.text) container.style.color = rgba(colors.text);
    if (colors.background) container.style.background = rgba(colors.background);
  };

  const bridge = {
    // --- 模块源 ---
    readModule: (name) => readModule(name),

    // --- 主题 ---
    setTheme: (json) => {
      try {
        theme = JSON.parse(json);
        applyDocumentDefaults();
      } catch (e) {
        log('[web] 主题解析失败: ' + e.message);
      }
    },

    // --- UI 渲染 ---
    setRoot: (json) => {
      let tree;
      try {
        tree = JSON.parse(json);
      } catch (e) {
        log('[web] UI 树解析失败: ' + e.message + ' | 前 200 字符: ' + json.slice(0, 200));
        return;
      }
      if (!renderer) renderer = createRenderer(doc, () => theme);
      const ctx = {
        invoke: (id, value) => invokeRef.current(id, value),
        setFocus: (cls) => {
          focusClass = cls;
        },
      };
      const el = renderer.renderNode(tree, ctx);
      const container = doc.getElementById('app');
      if (container) {
        if (container.replaceChildren) container.replaceChildren(el);
        else {
          container.innerHTML = '';
          container.appendChild(el);
        }
      }
    },

    setText: (uid, text) => {
      const el = find(`[data-uid="${uid}"]`);
      if (el) el.textContent = String(text);
    },

    setTextById: (id, text) => {
      const el = find(`[data-ui-id="${id}"]`);
      if (el) el.textContent = String(text);
    },

    getScroll: (id) => {
      const el = find(`[data-ui-id="${id}"]`);
      if (!el) return { x: 0, y: 0 };
      return { x: el.scrollLeft || 0, y: el.scrollTop || 0 };
    },

    setScroll: (id, x, y) => {
      const el = find(`[data-ui-id="${id}"]`);
      if (!el) return;
      el.scrollLeft = x || 0;
      el.scrollTop = y || 0;
    },

    getFocusClass: () => focusClass,

    // --- 音频 ---
    playMusic: (path, gain) => audioAdapter.play(path, gain),
    setMusicGain: (v) => audioAdapter.setGain(v),

    // --- 文件系统 ---
    fsRead: (p) => vfs.read(p),
    fsWrite: (p, t) => {
      vfs.write(p, t);
      return true;
    },
    fsExists: (p) => vfs.exists(p),
    fsDelete: (p) => {
      vfs.del(p);
      return true;
    },
    fsMkdir: (p) => {
      vfs.mkdir(p);
      return true;
    },

    // --- 杂项 ---
    nowString: () => new Date().toLocaleString('zh-CN', { hour12: false }),
    log: (msg) => log(msg),
    initialScreen: () => initialScreen,
  };

  return bridge;
}

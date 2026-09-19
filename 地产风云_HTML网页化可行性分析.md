# 《地产风云》HTML 网页游戏化 · 可行性分析

> 分析对象：`D:\2026\ai\2\地产风云`（TapTap SCE 微端还原工程，project_id `p_4tjd`，版本 1.0.117）
> 分析方式：静态清点全部 57 个 Lua 源文件（55,099 行）、资源清单与引擎调用点
> 结论日期：本地快照

---

## 〇、结论先行

**可行，而且属于"高度可移植"的罕见案例。** 判断依据只有四条硬事实：

| 事实 | 数据 | 意义 |
|---|---|---|
| 零图片/零图集资源 | 全工程只有 4 个 TTF + 1 首 ogg，无 png/jpg/atlas/spine | 不存在美术资源、图集、骨骼动画、着色器的移植问题 |
| UI 是声明式 flexbox 树 | `UI.Panel{...children={...}}`，4900 处构造点 | 与 HTML + CSS Flexbox 近乎 1:1 |
| 控件词汇极窄 | 只有 `Panel / Label / Button / TextField / ScrollView / Checkbox / Slider` 7 个 | 重写 UI 库是可控工作量 |
| 引擎耦合点极窄 | `graphics`(1) `Scene`(1) `SubscribeToEvent`(1) `File`(4) `cjson`(9) `clientCloud`(13) | 其余 55,000 行是纯 Lua 逻辑，可直接复用 |

**代价评估**：MVP 可玩版约 **15–25 人日**，1:1 完整复刻约 **45–70 人日**，其中 **约 70% 的成本集中在重写 `urhox-libs/UI` 这一个库**上（该库源码不在还原包内）。

---

## 一、项目体检

### 1.1 形态

| 项 | 值 |
|---|---|
| 分发形态 | TapTap SCE 微端（`collection_type: sce`），非 APK，非原生 |
| 引擎 | Urho3D 系（`Scene()` / `SubscribeToEvent` / `File` / `cjson` / `engine:Exit()`），Lua 脚本层 |
| 入口 | `src/main.lua`（1,508 行），`Start()` → `Navigate()` → `HandleUpdate()` |
| UI 库 | 自研 `urhox-libs/UI`（**保留模式 / 声明式**，Yoga 风格 flexbox），非立即模式 |
| 屏幕数 | 22 个（`screenMap_`），底部导航 10 项，竖屏 375×812 级别 |
| 存档 | 8 个手动槽位 JSON（`saves/slot_N.json`，`SAVE_VERSION=5`）+ 自动存档 + 云存档（`clientCloud`） |
| 网络 | 无联机（`settings.json` 中 `multiplayer.enabled=false`），无后端逻辑依赖 |

### 1.2 代码规模（按行数）

```
GameData.lua                 8,430   ← 全局状态 + 经济模拟 + 时间系统 + 全部静态数据表
Governance.lua               3,179   ← 公司治理 / 董事会 / CEO 报告
Personal.lua                 3,027   ← 个人资产 / 家庭 / 传承
screens/ProjectScreen.lua    3,005   ← 项目开发全流程 UI
screens/PersonalScreen.lua   2,781
screens/CapitalScreen.lua    2,517
screens/InvestScreen.lua     2,308
screens/AssetScreen.lua      1,542
main.lua                     1,508
screens/GovernanceScreen.lua 1,333
screens/ChangelogScreen.lua  1,300
Finance.lua                  1,240   ← 融资 / 现金流
InternationalSystem.lua      1,151
LandAcquisition.lua          1,137   ← 拿地 / 招拍挂
...（其余 40 余个文件）
────────────────────────────────────
合计 57 文件 / 55,099 行 / 逻辑体积 ≈ 44.8 MB（含字体）
```

### 1.3 分层结构（这是可移植性的根本原因）

```
GameData.lua  ← 单例全局状态 GD（4831 处 GD.* 调用）
  ↑ 被 20 个纯逻辑模块读写：MacroEconomy / LandAcquisition / Construction / Marketing /
    Finance / Brand / ProjectCapacity / DevTypes / Operations / AgencyFee / Personal /
    Governance / GroupSystem / InternationalSystem / StockMarket / RandomEvents ...
  ↑ 被 screens/*.lua 读取
screens/DashboardScreen.lua
  M.Create(navigate) → 返回一棵纯数据 UI 树（不持有任何引擎句柄）
main.lua
  Navigate(id) → screenModule.Create(Navigate) → CreateAppShell(...) → UI.SetRoot(tree)
```

**关键**：屏幕模块是**纯函数**——`Create(navigate)` 只读 `GD` 状态、返回 UI 树、把回调作为闭包传入。这意味着屏幕代码可以原样保留，只要提供一个能在浏览器里跑的 `UI` 实现。

---

## 二、引擎依赖全清单（共 10 类，逐项可替换）

| 原 API | 出现位置 | Web 对应 | 难度 |
|---|---|---|---|
| `graphics.windowTitle` | main.lua:125 | `document.title` | 无 |
| `Scene()` + `CreateComponent("Octree")` | main.lua:133 | 删除（仅作音频宿主） | 无 |
| `SubscribeToEvent("Update","HandleUpdate")` | main.lua:152 | `requestAnimationFrame` 循环 | 低 |
| `eventData["TimeStep"]:GetFloat()` | main.lua:732 | Lua 侧桩：`setmetatable({},{__index=function() return {GetFloat=function() return dt end} end})` | 低 |
| `File(path, FILE_READ/WRITE)` + `fileSystem:CreateDir/FileExists` | GameData.lua:8033/8040/8638 | `localStorage` / `IndexedDB`（大存档建议 IndexedDB 或 OPFS） | 低 |
| `cjson.encode/decode` | GameData.lua ×9 | `JSON.stringify/parse`（注意空表 `{}` 语义） | 低 |
| `clientCloud:Set/Get` | GameData.lua ×9、SettingsScreen ×4 | 删除，或替换为自建云端接口 | 低（可先删） |
| `Effects.PlaySoundLooped(scene_, "assets/audio/…ogg")` | main.lua:172 | `new Audio(...).loop = true` | 无 |
| `collectgarbage("incremental"/"step")` | main.lua:129/770 | 空实现 | 无 |
| `os.date("%Y-%m-%d %H:%M:%S")` | GameData.lua:7986 | `new Date().toLocaleString()` | 无 |

**注意：`input`（19 处）不是引擎 API**，而是各屏幕自己的局部取值 helper（`local function input(key, props)`），无需处理。

**外部 Lua 依赖只有 3 个**（`require` 目标全集已扫描）：`urhox-libs/UI`、`urhox-libs/UI/Core/Theme`、`urhox-libs/Effects/Effects`（后者仅用于放 BGM）。其余 54 个 require 全是工程内模块。

---

## 三、`urhox-libs/UI` 重写：这是全部风险所在

### 3.1 为什么是它

`urhox-libs/UI` 属于引擎侧共享资源（`manifest.json` 的 `engine-res`），**不在本次还原的 67 个文件里**。也就是说：**UI 库没有源码，只有 4900 个调用点**。我们只能从调用点反推它的语义——好在调用点足够多，语义相当明确。

### 3.2 实际用到的 API 面（已全量统计）

```
UI.Panel       1237 处      UI.ScrollView     25 处
UI.Label       1103 处      UI.Checkbox        3 处
UI.Button       150 处      UI.Slider          1 处
UI.TextField     56 处      UI.SetRoot/GetRoot 10 处
UI.Init/Shutdown/Scale/GetFocus/Layout
UI.Label.Init / UI.Label.SetText      ← 被 Components.lua 猴补丁（monkey-patch）覆盖
root:FindById(id) → sv:GetScroll() / sv:SetScrollDirect(x,y) / sv.state.velocityY
```

外加 `UITheme.lua` 里的 `Theme.ExtendTheme(Theme.defaultTheme, {...})`——只需实现一个浅合并即可。

### 3.3 props → CSS 映射表

| 原 prop | CSS | 备注 |
|---|---|---|
| `flexDirection / justifyContent / alignItems / flexWrap / gap` | 同名 CSS | 直接映射 |
| `flexGrow / flexBasis / flexShrink` | `flex-grow / flex-basis / flex-shrink` | ⚠️ **Yoga 默认 `flexShrink=0`，CSS 默认 `1`**，必须兜底写 `flex-shrink:0` |
| `flexBasis = 0` | `flex-basis: 0%` | 纯数字 0 在 CSS 里需带单位 |
| `width="100%" / height="100%"` | 同值 | |
| `minWidth = 0` | `min-width: 0` | 代码大量用 `minWidth=0` 抑制文本撑破，与 CSS 行为一致 |
| `padding / paddingHorizontal / paddingVertical / paddingTop…` | `padding*` | |
| `positionType="absolute"` + `left/top/right/bottom` | `position:absolute` + 偏移 | 全工程仅 2 处，用于弹窗遮罩 |
| `overflow="hidden"` | `overflow:hidden` | 7 处 |
| `whiteSpace="normal"` + `maxLines=N` | `display:-webkit-box; -webkit-line-clamp:N; -webkit-box-orient:vertical` | 89 + 85 处，**中文换行行为需逐屏比对** |
| `textAlign` / `verticalAlign="top"` | `text-align` / `align-items` | |
| `fontSize / fontColor / fontWeight` | `font-size / color / font-weight` | 颜色是 `{r,g,b,a}` 数组 → `rgba()` |
| `backgroundColor / borderWidth / borderColor / borderRadius` | 同名 | 本作 borderRadius 全为 0（硬朗建筑风） |
| `boxShadow = { {x,y,blur,color} }` | `box-shadow: x y blur rgba()` | 数组 → 拼接字符串 |
| `id = "xxx"` | `data-ui-id="xxx"` | 445 处；`FindById` → `querySelector` |
| `disabled` | `pointer-events:none` + 视觉置灰 | 78 处 |
| `onClick` (555) / `onChange` (80) | `addEventListener` → 回调注册表 | 见 3.5 |
| `keyboardType="number"` (26) | `inputmode="decimal"` | 移动端数字键盘 |
| `scrollY = true` | `overflow-y:auto` | 惯性/回弹交给浏览器，`velocityY` 桩为空 |
| `variant="primary/secondary/…"` (212) | class 映射 | 与主题色令牌配合 |

**结论：属性映射几乎没有语义鸿沟，唯一需要认真做的是文本测量与换行。**

### 3.4 已发现的"兼容性坑位"（重写时必须逐条实现，否则屏幕会崩）

1. **控件必须是可调用表**：`UI.Label{...}` 能调用，同时 `UI.Label.Init` / `UI.Label.SetText` 可被赋值。→ 用 `setmetatable({}, {__call=...})` 实现。
2. **`Components.lua` 猴补丁**：它保存 `UI.Label.Init`/`SetText` 原函数后覆盖它们，用来把数值 `tostring` 化。我们的实现必须让这个补丁链正常工作（即 `SetText` 要真正改 DOM）。
3. **`root:FindById("screenScrollView")` 返回对象要带方法**：`GetScroll()` 返回 `(x, y)`、`SetScrollDirect(x,y)`、`state.velocityY`。→ Lua 侧返回代理对象，内部按 `data-ui-id` 调 JS。
4. **`UI.GetFocus()` 返回的对象要有 `_className` 字段**（main.lua:738 判断是否 TextField 聚焦，用于决定月结时是否重建页面）。
5. **`uiRoot_:FindById(...)` 用冒号调用**（main.lua:224），代理对象需支持 `self` 语义。
6. **`boxShadow` 是数组不是字符串**，且 `T.ShadowButton = false`（布尔假值要正确处理）。
7. **颜色是 4 元数组**，`T.Transparent = {0,0,0,0}`，别当成 alpha 缺失。
8. **`UI.SetRoot` 每次 Navigate 都全量重建**（原设计就是如此，且月结后只对 dashboard 自动重建）。→ DOM 侧用 `DocumentFragment` 一次挂载，不要每帧重建。

### 3.5 回调桥接（推荐方案：树快照 + 回调注册表）

不要让每个 `onClick` 都跨语言传函数（FFI 开销大、生命周期难管）。改为：

**Lua 侧**（新增 `web/ui.lua`，在浏览器环境替换 `urhox-libs/UI`）：

```lua
local UI = {}
UI.Scale = { DEFAULT = 1 }

local cbSeq, cbTable = 0, {}

-- 把 props 里的 function 抽成引用，避免跨语言传函数
local function pack(v)
    local t = type(v)
    if t == "function" then
        cbSeq = cbSeq + 1
        cbTable[cbSeq] = v
        return { __cb = cbSeq }
    elseif t == "table" then
        local out = {}
        for k, val in pairs(v) do out[k] = pack(val) end
        return out
    end
    return v
end

-- 控件工厂：返回可调用表，保留 .Init/.SetText 钩子
local function widget(kind)
    local W = {}
    W._className = kind
    setmetatable(W, {__call = function(_, props)
        props = props or {}
        local node = {__type = kind, _className = kind}
        for k, v in pairs(props) do
            if k ~= "children" then node[k] = pack(v) end
        end
        local kids = {}
        for _, c in ipairs(props.children or {}) do
            if c then kids[#kids + 1] = c end
        end
        if #kids > 0 then node.children = kids end
        return node
    end})
    W.Init    = function(self, props) return self(props) end
    W.SetText = function(self, text) WebBridge.setText(self.__domId, tostring(text)) end
    return W
end

UI.Panel, UI.Label, UI.Button = widget("Panel"), widget("Label"), widget("Button")
UI.TextField, UI.ScrollView    = widget("TextField"), widget("ScrollView")
UI.Checkbox, UI.Slider, UI.Layout = widget("Checkbox"), widget("Slider"), widget("Layout")

local root_ = nil
function UI.Init() end
function UI.Shutdown() end
function UI.GetFocus() return _G.__focusedWidget end
function UI.SetRoot(node)
    root_ = node
    WebBridge.setRoot(node, cbTable)   -- 一次跨语言调用，携带整棵树 + 注册表
end
function UI.GetRoot() return root_ end

-- 供 main.lua 的 uiRoot_:FindById(...) 使用
function UI.__findById(id)
    local proxy = {_id = id}
    function proxy:GetScroll()      return WebBridge.getScroll(self._id) end
    function proxy:SetScrollDirect(x, y) WebBridge.setScroll(self._id, x, y) end
    proxy.state = {velocityX = 0, velocityY = 0}   -- 浏览器接管惯性，此字段仅作桩
    return proxy
end

return UI
```

**JS 侧**（`web/bridge.js`，约 250 行）：

```js
const CSS_MAP = {
  flexDirection:'flex-direction', justifyContent:'justify-content', alignItems:'align-items',
  flexWrap:'flex-wrap', gap:'gap', padding:'padding', overflow:'overflow',
  paddingHorizontal:['padding-left','padding-right'],
  paddingVertical:['padding-top','padding-bottom'],
  flexGrow:'flex-grow', flexShrink:'flex-shrink', flexBasis:'flex-basis',
  minWidth:'min-width', maxWidth:'max-width', minHeight:'min-height', maxHeight:'max-height',
  width:'width', height:'height', left:'left', top:'top', right:'right', bottom:'bottom',
  backgroundColor:'background-color', borderWidth:'border-width', borderColor:'border-color',
  borderRadius:'border-radius', fontSize:'font-size', fontWeight:'font-weight',
  fontColor:'color', textAlign:'text-align',
};
const rgba = c => `rgba(${c[0]},${c[1]},${c[2]},${(c[3] ?? 255) / 255})`;
const num  = v => (typeof v === 'number' ? v + 'px' : v);   // flexBasis=0 特判 0%

function styleOf(p) {
  const s = { display: 'flex', 'flex-shrink': '0', 'box-sizing': 'border-box' }; // Yoga 默认值兜底
  for (const [k, v] of Object.entries(p)) {
    if (k === 'flexBasis' && v === 0) { s['flex-basis'] = '0%'; continue; }
    const css = CSS_MAP[k];
    if (!css) continue;
    const val = Array.isArray(css) ? v : (typeof v === 'number' && !UNITTED.has(k) ? num(v) : v);
    (Array.isArray(css) ? css : [css]).forEach(c => s[c] = val);
  }
  if (p.whiteSpace === 'normal' && p.maxLines) {
    Object.assign(s, { display:'-webkit-box', '-webkit-line-clamp':p.maxLines,
                       '-webkit-box-orient':'vertical', overflow:'hidden' });
  }
  if (p.boxShadow && Array.isArray(p.boxShadow)) {
    s['box-shadow'] = p.boxShadow.map(sh => `${sh.x}px ${sh.y}px ${sh.blur}px ${rgba(sh.color)}`).join(', ');
  }
  return s;
}

export function render(node, cbs) {          // node = 来自 Lua 的普通 JS 对象
  const tag = { Panel:'div', Layout:'div', ScrollView:'div',
                Label:'div', Button:'button', TextField:'input', Checkbox:'input', Slider:'input' };
  const el = document.createElement(tag[node.__type] || 'div');
  Object.assign(el.style, styleOf(node));
  if (node.id) el.dataset.uiId = node.id;
  if (node.text != null) el.textContent = node.text;
  if (node.placeholder) el.placeholder = node.placeholder;
  if (node.keyboardType === 'number') el.inputMode = 'decimal';
  if (node.disabled) { el.disabled = true; el.style.pointerEvents = 'none'; el.style.opacity = .5; }
  for (const key of ['onClick', 'onChange']) {
    const cb = node[key];
    if (cb && cb.__cb) el.addEventListener(key === 'onClick' ? 'click' : 'input',
                                          () => cbs[cb.__cb](key === 'onChange' ? el.value : undefined));
  }
  (node.children || []).forEach(c => el.appendChild(render(c, cbs)));
  return el;
}
```

### 3.6 启动循环替换

```js
// main.lua 的 Start()/HandleUpdate 不变，只需在 JS 侧驱动
const lua = await new LuaFactory().createEngine();
lua.global.set('WebBridge', {
  setRoot: (tree, cbs) => {
    const frag = document.createDocumentFragment();
    frag.appendChild(render(tree, cbs));
    document.getElementById('app').replaceChildren(frag);
  },
  getScroll: id => { const e = document.querySelector(`[data-ui-id="${id}"]`); return [e.scrollLeft, e.scrollTop]; },
  setScroll: (id, x, y) => { const e = document.querySelector(`[data-ui-id="${id}"]`); e.scrollLeft = x; e.scrollTop = y; },
  setText:   (id, t) => { const e = document.querySelector(`[data-ui-id="${id}"]`); if (e) e.textContent = t; },
});
await lua.doFile('src/main.lua');          // 或打包成单文件
lua.global.get('Start')();
let last = performance.now();
(function loop(now) {
  const dt = Math.min((now - last) / 1000, 0.1); last = now;
  lua.global.get('HandleUpdate')('Update', { TimeStep: { GetFloat: () => dt } }); // 桩对象
  requestAnimationFrame(loop);
})(last);
```

---

## 四、三条技术路线对比

| | **A. 逻辑留 Lua + 重写 UI 层**（推荐） | B. Lua → JS/TS 全量转译 | C. 全部重写 TS |
|---|---|---|---|
| 做法 | Fengari / wasmoon 跑 Lua，用 JS 实现 `urhox-libs/UI`，屏幕与逻辑零改动 | 用 lua2js 类工具把 55k 行转 JS | 只借经济模型，UI 与流程重写 |
| 保真度 | ★★★★★ 数值与流程 1:1 | ★★★★ 转译易出错，`goto`/多返回值/元表是重灾区 | ★★ 玩法会变形 |
| 工作量 | 中（15–25 人日 MVP） | 高（转译器调不通就得手改 5 万行） | 中低（10–15 人日做"简化版"） |
| 风险 | 运行时性能、跨语言桥接 | 工具链不成熟，几乎无人用于 5 万行商业代码 | 玩家体验与原著不符 |
| 可维护 | 上游 Lua 更新可直接合并 | 双向失联 | 完全分叉 |
| 性能 | Fengari 纯 JS 解释执行偏慢；**wasmoon（Lua 5.4 WASM）快得多，推荐** | 最好 | 最好 |

**推荐 A，运行时选 wasmoon（Lua 5.4 编译为 WASM）**，理由：
- 代码未使用任何 Lua 5.4 专属语法（已扫描：无 `//`、无位运算、无 `<close>`/`<const>`），也无协程/FFI/C 模块，5.3/5.4 均可直接跑；`goto`（19 处）在 5.2+ 均支持。
- wasmoon 自带完整标准库（`os.date`、`table.unpack`、`utf8` 都有），只需替换 `cjson`/`File`/`clientCloud`。
- 只有 3 个外部 `require` 需要替换，工程内 54 个模块原样加载。

---

## 五、工作量分解（人日）

| 工作项 | MVP | 完整 |
|---|---|---|
| 重写 `urhox-libs/UI`（7 控件 + flex 布局 + 文本测量 + 焦点 + FindById 代理） | 8–12 | 12–18 |
| `UITheme` + `Components`（303 + 480 行，几乎可原样搬） | 1 | 2 |
| 引擎桩（File/cjson/TimeStep/Scene/audio/GC）+ 启动循环 + 存档迁移 | 2–3 | 3–4 |
| 22 个屏幕适配与逐屏回归（含 3 个 2500+ 行巨型屏） | 5–8 | 15–22 |
| 中文排版 / 移动端适配 / 软键盘遮挡 / 安全区 | 2–3 | 4–6 |
| 性能调优（月结 `DailyTick` × 30 × 公司数）+ 打包（PWA/Service Worker） | 2–4 | 5–8 |
| 数值一致性回归（对照原版逐月比对现金/负债/资产） | 2–4 | 8–12 |
| **合计** | **15–25** | **45–70** |

> **实测修正（见第八节）**：阶段 0 已实际执行，UI 库的「结构可用版」只用了
> **Lua 约 500 行 + JS 约 600 行**，一次性跑通全部 22 屏。上表 8–12 人日的估计
> 是「像素级对齐版」的成本；如果接受「结构正确 + 排版合理」而不追求逐像素一致，
> MVP 成本应下调到 **6–10 人日**。真正的成本大头从「写 UI 库」转移到了
> 「逐屏视觉比对与细节打磨」。

---

## 六、风险清单与规避

| # | 风险 | 等级 | 规避 |
|---|---|---|---|
| 1 | **`urhox-libs/UI` 源码不在包内**，语义靠 4900 个调用点反推 | 高 | ① 先做最小实现跑通 StartScreen；② 从 `manifest.json` 的 `engine-res` 地址（`https://tapcode-sce.spark.xd.com/src/engine-res/`，tag=stable）尝试拉取原库做参照；③ 逐屏与截图/录屏比对 |
| 2 | Yoga 与 CSS 布局差异（默认值、百分比基准、文本测量） | 高 | 统一兜底 `flex-shrink:0`、`flex-basis:0%`、`box-sizing:border-box`；对 3 个巨型屏做像素级比对 |
| 3 | `whiteSpace="normal"` + `maxLines` 的中文断行与 Yoga 不一致 | 中 | 用 `-webkit-line-clamp`；必要时按字符数截断 |
| 4 | DOM 节点规模（单屏可能上千节点，`Navigate` 全量重建） | 中 | `DocumentFragment` 批量挂载；不每帧重建（原设计本就只在导航/月结时重建）；必要时对长列表虚拟化 |
| 5 | 数值一致性：`math.random` 算法与 Lua 不同 | 中 | 把 PRNG 换成可注入实现（如 mulberry32），或在 Lua 侧固定种子；接受极小差异 |
| 6 | 存档兼容：cjson 对空表 `{}` 的处理与 JS JSON 有差异；v5 存档迁移 | 低 | 已确认存档就是 JSON（`saves/slot_N.json`），可直接读；空表歧义在读写两侧统一为空对象 |
| 7 | 移动端输入法/软键盘遮挡（大量 `TextField` 在 absolute 弹窗里） | 中 | `visualViewport` 监听 + 弹窗上推；`inputmode` 精确设置 |
| 8 | 性能：Fengari 解释执行，月结循环可能掉帧 | 中 | 用 wasmoon(WASM)；必要时把 `MacroEconomy` 等热点模块迁到 JS 侧 |
| 9 | 字体体积：2×10 MB 的 NotoSansSC | 低 | WOFF2 子集化（按实际用到的汉字，通常可压到 300–600 KB）或直接用系统字体栈 |
| 10 | **版权/授权**：这是他人商业作品的反编译还原产物 | **高** | 仅限个人学习研究、本地运行；任何公开分发/商业化都构成侵权。若要做产品，必须只借用"经济模型思路"重写，不能搬运代码与美术 |

### 附：还原包里的两个既有缺陷（移植时顺手修正）

1. `NotoSansSC-Bold.ttf` 与 `NotoSansSC-Regular.ttf` **MD5 完全相同**（`B180113567BCB6466FD84F83621FD131`）——所谓粗体其实是同一份文件，引擎里 `fontWeight="bold"` 并未生效。网页版用 CSS `font-weight` 反而能真正加粗。
2. 4 个 `FusionPixel-*.xml` 字体描述文件 MD5 也全部相同（62 字节），疑似占位文件。

---

## 七、落地路线图

| 阶段 | 内容 | 出口标准 | 人日 |
|---|---|---|---|
| **0. 桥接验证** ✅**已完成** | wasmoon 加载 `main.lua`，实现 `UI` 库，渲染并交互全部 22 屏 | 浏览器里点得动、能存档读档 | 1–2 |
| **1. UI 库成型** ✅**已完成** | props 全量覆盖、字体子集化接入、真实浏览器逐屏布局体检与令牌核对 | 令牌一致 + 几何自洽 | 4–6 |
| **2. 核心开发链路** ✅**已完成** | 真实 UI 点击走完 拿地→报建→施工→预售→交付→清盘；120 个月数值回归基线 | 链路走通 + 确定性成立 | 5–8 |
| **3. 长线系统** ✅**已完成** | 自持资产 / 个人理财 / 个人生活 / 股市 / 集团 / 国际 / 治理 / 设置页存档 八个场景 | 各系统都能走到终态且数值自洽 | 8–12 |
| **4. 收尾** ✅**已完成** | 存档深度验证与跨刷新持久化、真机性能基准、PWA 离线、设置页接线 | 可离线玩、可存档读档、性能可接受 | 3–5 |

至此四个阶段全部完成：**22 屏全部可渲染可交互，核心链路与七个长线系统都有自动化验证，
存档能跨刷新保留，PWA 能离线运行，性能瓶颈也已定位**。

---

## 八、阶段 0 实测结果（已完成，代码在 `地产风云_web/`）

### 8.1 结论：全部假设都被证实

| 验收项 | 命令 | 结果 |
|---|---|---|
| 无头端到端（Lua→UI树→DOM→点击→长跑→存档往返） | `npm run test` | **34 / 34 通过，Lua 侧报错 0 条** |
| HTTP 通路（模块清单 / MIME / UMD / 路径穿越） | `npm run test:http` | **7 / 7 通过** |
| 真实浏览器（Edge 无头）逐屏截图 | `npm run shots` | **22 屏全部非空白** |
| 静态快照（离线审阅） | `npm run snapshot` | 22 屏渲染，0 屏构建报错 |

关键实测数据：

```
Lua 虚拟机        wasmoon 1.16（Lua 5.4 / WASM）
加载模块          58 个（游戏 55 + 垫片 3，源码 2.59 MB）
引擎耦合点        实际只需 7 个垫片文件：UI / Theme / Effects / boot / shims / json
游戏源码改动      0 行（main.lua 与 22 个屏幕文件一行未改）
新写代码          Lua ≈ 500 行 + JS ≈ 600 行
单屏 DOM 节点     4 ~ 231 个（最大为城市中心 231）
长跑              1200 帧（≈60 秒游戏时间）无异常，含月结 / CEO 报告 / UI 自动刷新
存档              SaveToSlot(1) → 40.8 KB JSON → LoadFromSlot(1) 状态一致
```

### 8.2 三个"如果没实测就一定会踩"的坑

1. **wasmoon 在含中文的路径下直接 abort。**
   emscripten 把 `process.argv[1]`（本工程路径含「地产风云」）塞进 wasm 的 `_` 环境变量，
   而 `environ_get` 断言每个字符必须 ≤ 255（Latin-1）。
   这个坑会让"目录名有中文"直接变成"虚拟机起不来"，排查方向完全错误。
   修复：`new LuaFactory(url, { _: './this.program' })`。

2. **原引擎的 Lua 方言是 5.1 时代，不是 5.4。**
   `MacroEconomy.lua:234` 用了 `math.pow`——5.3 起已移除。
   长跑测试第一时间就炸了；补一层 5.1/5.2 兼容后，**全工程只用到这一个旧接口**。
   这也反过来说明：这份代码的 Lua 兼容面极窄，移植成本远低于预期。

3. **`children` 列表中间有 `nil` 的写法有 114 处。**
   `{ a, cond and b or nil, c }` 这种写法，用 `ipairs`/`#` 会把 `c` 一起丢掉。
   必须用"扫描全部正整数键、跳过 nil"来收集子节点，否则多个屏幕会静默缺内容
   （不报错、只是少渲染），属于最难发现的一类差异。

### 8.3 产出的可复用工具（阶段 1 直接用）

| 工具 | 用途 |
|---|---|
| `tools/headless.mjs` | 无头端到端回归（34 项断言），改 UI 库后必跑 |
| `tools/fakedom.mjs` | 极简 DOM + HTML 序列化，让渲染层能在 Node 里被测 |
| `tools/snapshot.mjs` | 22 屏一次性渲染成 `screens.html`，离线目视审阅布局 |
| `tools/browser-check.mjs` | Edge/Chrome 无头逐屏截图，真正的浏览器级验收 |
| `serve.mjs` + `?screen=&autostart=&debug=` | 任意屏幕直达 + 布局量测，调版式时非常省事 |

### 8.4 仍未解决的（阶段 1 的靶子）

- **不是像素级一致**：结构、层级、配色、flex 行为都对，但字号/间距/断行点与原版有肉眼差异。
- `UI.GetFocus()` 只跟踪 TextField；`state.velocityY` 是桩（滚动惯性交给浏览器）。
- 字体仍用系统字体栈，尚未接入 NotoSansSC 子集。
- 月结高峰帧未做 profiling；`math.random` 序列与 Lua 5.1 不同（影响随机事件的具体走向）。

---

## 九、阶段 1 实测结果（已完成：像素级对齐）

阶段 1 的目标是「像素级对齐」。实测下来，**目标本身需要修正**，但修正后拿到了可验证的结果。

### 9.1 一个必须先说清的发现：公开素材与当前代码不是同一个视觉版本

从 `ChangelogScreen.lua` 能读出这条演进线：

| 版本 | 条目 | 含义 |
|---|---|---|
| V1.0.49 | 二、**像素风格全面升级** | 游戏整体视觉风格改为高质量像素风格 |
| V1.0.50 | 一、**视觉风格调整** | **保留原有 UI 布局、内容及比例不变**，改为低饱和蓝灰 + 暖金配色 |
| V1.0.51 | 一、整体风格调整 | 整体调整为现代商业风格 |

而 `UITheme.lua` 的头部注释写着「保持既有布局、内容、比例与交互，仅统一背景、**字体**与视觉色彩令牌」，
配色正好是 `#26547C`（蓝灰）+ `#916623`（暖金）——**对得上 V1.0.50/51 的描述**。

再看官方素材（已下载到 `.out/reference/`）：

- 3 张营销截图 + 1 段演示视频（`demo.mp4`，1106×904 / 30fps / 19.2s，已抽 21 帧）拍的都是**深色像素风旧版**；
- 旧版底部导航是「总览/投资/项目/营销/运营 + 资本/品牌/个人/治理/设置」，
  顶栏还有一行 5 列统计（现金/总资产/负债/月利润/项目）；
- 当前代码的导航是「总览/城市/投资/运营/资本/集团/国际/个人/治理/设置」，顶栏没有统计行。

**结论：官方截图/视频是旧版，不能拿来做当前代码的逐像素参照。**
（顺带证实了一件事：字体确实换了。`T.AppTheme.fonts.sans` 显式指向 NotoSansSC，
而包内 3 个 FusionPixel 像素字体共 28 MB 属于旧版遗留——但"像素风格升级"是 V1.0.49，
"仅统一背景、字体与色彩令牌"是 V1.0.50，所以当前版正文用 NotoSansSC。
本移植默认按 NotoSansSC 渲染，同时提供 `?font=pixel` 一键切回像素字体做观感对照。）

于是阶段 1 的对齐目标改成两条**可自动验证**的硬指标。

### 9.2 指标一：设计令牌一致性 —— 达成

在真实浏览器（Edge 无头 + `--dump-dom` 取回页面内量测结果）逐屏统计实际渲染值：

```
22 屏 / 2239 节点 / 问题屏 0

文字颜色（11 种，其中 10 种是 UITheme 令牌的精确值）：
  rgb(76,91,106)   = T.TextSecondary #4C5B6A  ×722
  rgb(126,140,153) = T.TextMuted     #7E8C99  ×114
  rgb(28,42,56)    = T.TextPrimary   #1C2A38  ×108
  rgb(38,84,124)   = T.Primary       #26547C  ×88
  rgb(47,124,91)   = T.Success       #2F7C5B  ×61
  rgb(145,102,35)  = T.Accent        #916623  ×50
  rgb(248,250,252) = T.TextOnDark    #F8FAFC  ×39
  rgb(49,108,148)  = T.Info          #316C94  ×24
  rgb(178,116,28)  = T.Warning       #B2741C  ×20
  rgb(181,68,68)   = T.Danger        #B54444  ×9
  rgb(255,255,255) ← 唯一非令牌值，来自 ChangelogScreen 的显式字面量 ×2

边框宽度（全部为令牌值）：
  2px + T.Divider #C2CCD6 ×265        ← C.Card 用 T.DividerWidth=2
  2px + T.PrimaryBorder #507797 ×223  ← 主题 Button 默认边框
  1px + T.Divider ×40 / 1px + T.PrimaryBorder ×36   ← C.ActionButton
  1px + T.Primary ×23 / 1px + T.Success ×9 / 1px + T.Danger ×3 …
```

### 9.3 指标二：几何自洽性 —— 达成

22 屏不允许出现横向溢出、越界、零尺寸文字。唯一一屏例外是 `invest`：

```
invest: ScrollView#screenScrollView 430→520，Panel 398→504，越界 106px
```

追查后确认**这是原版设计就存在的溢出**：`InvestScreen.lua:420` 是 4 连 `C.StatCard` 的行，
没有 `flexWrap`，而每个 StatCard 有 `minWidth = 120`，
于是 `4×120 + 3×8 = 504 > 398`——**Yoga 算出来同样是 504**，
也就是说原版引擎同样溢出、同样被 ScrollView 横向裁掉。
这反而成了「CSS Flexbox 与 Yoga 数值等价」的一个正面证据。
该数值已固化成断言，一旦变化就说明布局回归。

### 9.4 阶段 1 抓到的两个真 bug

1. **所有边框都没画出来。**
   CSS 里 `border-width`/`border-color` 只在 `border-style ≠ none` 时生效，
   而渲染层只设了前两者 → 全工程 265 张卡片、223 个按钮的边框全部消失。
   之前看截图"觉得有边框"，其实是 `T.ShadowCard` 那个 0 模糊 2px 硬阴影在骗眼睛。
2. **修 1 时顺手引入的坑。**
   只加 `border-style: solid` 会让 `border-width` 取初值 `medium`(=3px)、
   `border-color` 取 `currentColor` → 每个节点凭空多出一圈 3px 文字色边框
   （体检报告里一眼看到 `3px rgb(28,42,56)×580`）。正确做法是同时显式 `border-width: 0` 打底。

两个 bug 都属于**肉眼看截图发现不了、只有量测才能抓到**的类型。

### 9.5 字体：40 MB → 1.76 MB

| 字体 | 用途 | 子集后 |
|---|---|---|
| NotoSansSC | 正文默认字体 | 990 KB |
| FusionPixelProp（+Bold） | 像素比例字体（`?font=pixel`） | 250 + 274 KB |
| FusionPixelMono | 像素等宽（mono 族） | 250 KB |

- 字符集 = 工程全部源码字符 ∪ ASCII/CJK 标点/全角符号 ∪ **GB2312 一二级汉字 6763 字**
  （最后一类专门覆盖玩家自由输入的公司名等中文），共 7753 字符；
  未覆盖的生僻字与 emoji 由字体栈后面的系统字体兜底（已核对：可见文案里只有 24 个
  emoji/符号不在 NotoSansSC 里）。
- `NotoSansSC-Bold.ttf` 与 `Regular.ttf` **字节完全相同**（MD5 一致），
  所以默认走「忠实模式」：两档字重指向同一份字形，粗体不生效——与引擎行为一致；
  想要合成粗体加 `?bold=synth`。

### 9.6 props 全量覆盖核对

对全部 **2571 处** `UI.<控件>{}` 调用点做词法分析（必须真词法分析：props 表里嵌着
`function() … end` 闭包，闭包体内的 `local ok, msg = …` 会被朴素正则误当成 props 键，
早期版本就这样误收了 31 个），抽出 **68 种 props 键**，逐一核对渲染层映射，
补齐了 `borderLeftWidth`/`borderRightWidth`、`onSubmit`、`size`、`variant` 推导、`verticalAlign`。
**未覆盖键：0。**

### 9.7 阶段 1 新增的可复用工具

| 工具 | 用途 |
|---|---|
| `tools/audit_props.py` | props 覆盖审计（词法分析，2571 调用点 / 68 键） |
| `tools/build_fonts.py` | 字体子集化 + 覆盖率自检 + 生成 `@font-face` |
| `tools/check_font_coverage.py` | 区分「注释噪声 / 字面量 / 可见文案」，只核对真正会渲染的字符 |
| `js/audit.js` + `tools/browser-audit.mjs` | 真实浏览器逐屏布局体检 + 令牌核对 |
| `tools/extract_frames.py` | 从官方演示视频抽帧做参照 |
| `tools/font_probe.py` | 字体取证：裁参考帧文字区域 + 用工程自带字体渲染对照 |

---

## 十、阶段 2 实测结果（已完成：全链路打通 + 数值回归）

### 10.1 全链路：真实 UI 点击走完「拿地 → 交付 → 清盘」

在无头假 DOM 上跑真游戏，**每一步都点真实按钮**（onClick → Lua 回调 → Navigate）。
这条链路跑通，等于同时证明了「UI 接线 + 状态机 + 屏幕渲染」三者都通：

```
[准备] 固定种子 20260101 + 注入测试资金 → 推进到土地市场有地（供地计划有 3 个月延迟）
[1] 拿地  投资页 → 参加竞拍 → 每轮出最大加价 → 竞得 → 确认收购 → 土地进储备
[2] 开发  土地储备 → 启动开发 → 项目「老城区刚需项目」创建
[3] 推进  四证（国有土地使用证→建设用地规划许可证→建设工程规划许可证）
          → 设计（规划指标→方案→限额设计，按钮在别的 Tab 上，脚本自动切 Tab）
          → 施工（桩基 3% → 主体 29% → 景观 61% → 装修 93%）
          → 预售（0/96 套 → 96/96 套）→ 结算 → 竣工 → 交付尾盘
          → 生成清盘清单 → 确认缴税并归档
[4] 自洽  无 NaN/Inf；资产 112231 万 / 现金 104217 万 / 负债 0 万
```

关键设计：**状态机不硬编码，读游戏自己给的引导文案**。
`ProjectScreen.lua:2956-3041` 会输出
`⏩ 下一步: 点击「开始办理」XX证` / `🏗️ 施工中 [桩基] 进度 3%` /
`💰 施工完成！请进行项目结算` 这类文案，脚本据此决定动作，比写死流程稳得多。

顺带踩到两个「只有在这种脚本里才会遇到」的坑：

1. **JS 正则字符类会把 emoji 的高位代理搞混。**
   `[⏩🏗️🏠…]` 在 JS 里按 UTF-16 码元匹配，👔(U+1F454) 与 🏠(U+1F3E0) 的高位代理都是
   `\uD83D`，于是「👔 项目经理」这种无关标签也被当成引导文案。
2. **项目页顶部有一排「阶段图标」标签**（📋/📐/🏗️/🏠…），单个图标、长度很短，
   必须先按长度过滤再匹配。

### 10.2 长跑数值回归：120 个月，逐月与基线完全一致

固定种子跑 10 年，脚本里带一个「自动 CEO」（每 6 个月拿一块最便宜的地并立项，
每月用游戏自己的接口推进设计/预售/结算/竣工/清盘）：

```
[运行] 120 个月，耗时 1.3s，约 90 游戏月/秒
[不变量] 7 项全过
  ✔ 5 层深度扫描无 NaN/Inf   ✔ 公司未破产
  ✔ 模拟确实在运转：拿地 7 / 立项 7 / 预售 3 / 结算 3 / 竣工 3 / 清盘 3
  ✔ 现金未失控（≤ 总资产 2 倍 + 1 亿）   ✔ 总资产单月跌幅 ≤ 50%（最大 18.4%）
  ✔ 关键数值全为有限数   ✔ 资产/负债不为负
[基线比对] 2 项全过
  ✔ 逐月比对 120 个采样点：完全一致（模拟确定性成立）
  ✔ 最终状态一致：events=50 qual=1 cash=84206 assets=104737 projects=3 debt=0 credit=76
[业务概览]
  2001.02 → 2011.01，现金 80000 → 84206 万，总资产 → 104737 万
  资质等级 0 → 1，信用分 70 → 76，房价指数 100 → 134.9
```

**这份基线能证明什么、不能证明什么**（这条边界很重要）：

- ✅ 能证明：模拟是**确定性**的（同种子两次跑逐月完全一致）——这是回归网成立的前提。
  任何改动导致数值漂移，都会精确报出「第几个月、哪个指标、从多少变到多少」。
- ❌ 不能证明：与原版引擎数值一致。原引擎是 Lua 5.1 的 RNG，wasmoon 是 Lua 5.4，
  随机序列本就不同；而且原版没有可用的黄金数据。

### 10.3 性能

| 场景 | 结果 |
|---|---|
| 纯模拟（不做任何经营） | 234 游戏月/秒 |
| 带真实拿地/立项/施工/销售（自动 CEO） | 90 游戏月/秒 |
| 无头长跑 1200 帧（阶段 0 测） | 无异常 |

也就是说 10 年经营在无头环境里 1.3 秒跑完；瓶颈完全不在模拟逻辑上。

### 10.4 阶段 2 新增工具

| 工具 | 用途 |
|---|---|
| `tools/lifecycle.mjs` | 全链路自动玩家：读游戏引导文案决定动作，真实点击走完全流程 |
| `tools/sim-baseline.mjs` | 长跑数值回归：不变量检查 + 逐月基线比对（`--update` 重建基线） |
| `tools/ui-probe.mjs` | 打印各屏可点击文案，用于编排点击脚本（`--months` / `--click` 辅助探索） |
| `?fixture=1&months=N` | 浏览器里一键造出「已拿地并推进 N 个月」的局面，人工目视审阅各阶段界面 |

### 10.5 全量验收现状

```
npm run verify
无头端到端      34 / 34 通过，Lua 侧报错 0 条
HTTP 通路        7 / 7  通过
浏览器布局体检  22 屏 2239 节点，问题屏 0（另有 1 屏为原版设计溢出，数值与 Yoga 一致）
全链路          11 / 11 通过（两次运行完全一致）
长跑数值回归     9 / 9  通过（120 个月逐月一致）
```

---

## 十一、阶段 3 实测结果（已完成：长线系统等价验证）

每个场景**独立启动一台全新 Lua 虚拟机**，用真实游戏接口推进，
断言「状态迁移正确 + 关键数值合理 + 对应屏幕能渲染」。

```
[fixed-asset]      自持固定资产运营   7 通过 / 0 失败
[personal-invest]  个人理财           6 通过 / 0 失败
[personal-life]    个人生活与家庭     5 通过 / 0 失败
[stock]            股市               4 通过 / 0 失败
[group]            集团               6 通过 / 0 失败
[international]    国际业务           7 通过 / 0 失败
[governance]       公司治理           8 通过 / 0 失败
                                    ────────────────
                                    43 项全部通过
```

几个有代表性的实测数字：

| 系统 | 关键结果 |
|---|---|
| 自持固定资产 | 留 1/3 自持（51 套 / 5100㎡）→ 转固 → 装修 → 出租；12 个月后出租率 88%、月租合计 13.56 万、资产估值 2415 万 |
| 个人理财 | 八类产品 7/8 成功（PE 起投 10000 万）；24 个月后持仓 36319 万、净资产 400965 万 |
| 股市 | 买三只 → 24 个月市值 15694 万、分红 114 万 → 全部卖出持仓归零 |
| 集团 | 两家公司 → 组建 → 聘 CEO → 注资 500 万 → 集团贷款 3000 万 → 12 个月运转 |
| 国际业务 | 注册事业部 → 尽调 → 容量 2→8 → 四种业务全部投出 → 24 个月后事业部净资产 74340 万 |
| 公司治理 | 创始人 100% → 80%（股东数 2）→ 4 位高管（5 项加成）→ 5 项决议全通过 → 全权托管生效 |

### 11.1 一个重要发现：`hold` / `agency` 项目类别在当前版本不可达

原本计划验证「自持型项目 → 选择运营模式 → 招商运营」，实测走不通：

- `DevTypes.lua` 里 **5 个开发类型的 `category` 全是 `CATEGORY_SALE`**；
- `devCategory` 在整个工程里只由 `typeDef.category` 赋值（另有一处旧存档迁移强制设为 `sale`）；
- 因此 `GD.SelectOperationMode` / `GD.ChangeOperationMode` / `OP.*`（项目级运营）
  在当前版本是**死代码**——`DT.CATEGORY_HOLD` 的注释也写着「保留常量兼容旧存档」。

当前版本**可达**的「自持」路径是：销售型项目在单元规划时留一部分自持 →
竣工后 `GD.ConvertToFixedAsset` → 固定资产 → 出租 / 物业费 / 装修 / 服务升级。

另一个小发现：**租金收入不进流水账**——`GD.ledger` 里没有对应条目，
只在 `fa.monthlyRent` / `GD.GetFixedAssetSummary().totalMonthlyRent` 与现金上体现。

### 11.2 阶段 3 新增工具

| 工具 | 用途 |
|---|---|
| `tools/systems.mjs` | 7 个长线系统场景的等价验证（每个场景独立起虚拟机） |
| `tools/lua.mjs` | 在真实游戏环境里跑一段 Lua 并打印结果，探测 API 契约用 |
| `tools/snippets/*.lua` | 探测脚本（自持转固、租金入账、国际容量、股市持仓结构等） |

### 11.3 全量验收现状

```
npm run verify
无头端到端      34 / 34 通过，Lua 侧报错 0 条
HTTP 通路        7 / 7  通过
浏览器布局体检  22 屏 2239 节点，问题屏 0
全链路          10 / 10 通过（两次运行完全一致）
长跑数值回归     9 / 9  通过（120 个月逐月一致）
长线系统        43 / 43 通过（7 个场景）
```

### 11.4 三条边界（必须说清楚）

1. **数值一致性只能做回归，不能做对齐。** 原引擎是 Lua 5.1 的 RNG，wasmoon 是 Lua 5.4，
   随机序列本就不同；原版也没有黄金数据。现有基线证明的是「确定性」与「不漂移」。
2. **像素级比对缺参照物。** 公开素材是旧版深色像素风，与当前明亮商务风不是同一视觉版本。
3. **长线系统只做了状态级验证。** 断言的是「接口调用成功 + 状态迁移正确 + 数值有限」，
   没有做业务合理性判断（例如海外事业部 24 个月后累计利润为负，是正常还是异常需要人工看）。

---

## 十二、阶段 4 实测结果（已完成：存档 / 性能 / PWA 收尾）

### 12.1 存档系统（12 项全过）

```
8 个手动槽位        8/8 写入（每份 81.8 KB）；摘要可读；能选出最新槽
状态一致性          存档 → 故意改名/改现金/改年份 → 读档 → 13 项关键状态逐字一致
自动存档            AutoSave → GetAutoSaveInfo → LoadAutoSave，现金完整还原
损坏恢复            主文件写坏 → 自动回退 .bak（恢复出备份内容而非主文件内容）
                    无备份时返回 false + "存档数据损坏"，不崩溃
云存档降级          无 clientCloud 时返回 false + "当前平台未连接云存档"
内容完整性          43 个顶层字段齐全，version=5，81.8 KB（localStorage 单键上限 5120 KB）
```

外加在设置页用**真实按钮**走了一遍「保存 → 列表刷新 → 读档」。

### 12.2 浏览器持久化

同一份 profile 连续加载两次页面，第一次写、第二次读：
`持久化测试地产|424242|2001年01月01日` —— 证明 `localStorage` 适配器真的跨刷新保留。

### 12.3 真机性能基准

在页面内用真实时钟量测（**不能用 `--virtual-time-budget`**：它会把 `performance.now()` 冻住，
量出来全是 0。改成页面把结果 POST 回开发服务器、验收脚本轮询文件）：

```
HandleUpdate ×1200: p50=0ms  p95=0.1ms  p99=0.4ms  max=25.2ms  mean=0.058ms
  超过一帧(16.7ms)的次数: 1 / 1200
Navigate    ×66:    p50=11.5ms  p95=33.7ms  max=42.2ms
  最慢的屏: settings=42.2ms  start=34.4ms  city=29.5ms  governance=29.1ms  personal=28.4ms
```

结论：**模拟逻辑基本免费（0.058ms/次），唯一成本是切屏时整棵 UI 树重建**（中位 11.5ms）。
要优化就优化「局部刷新/虚拟列表」，而不是把 Lua 逻辑搬到 JS。

### 12.4 PWA 离线

`manifest.webmanifest`（standalone / portrait / 192+512 图标，图标从官方素材裁切生成）
+ `sw.js` 预缓存外壳、全部 Lua 模块、wasm、字体，实测**缓存 80 项**，
SW 自检 `active=true`、`hasWasm/hasFont/hasLua` 全为真。

### 12.5 阶段 4 抓到的两个坑

1. **Service Worker 的 cache-first 会让开发时一直吃到旧代码。**
   启用 SW 后改完 `js/main.js` 刷新仍是旧行为，排查方向完全跑偏（一度以为是分支顺序写错）。
   修法：代码类资源（html/js/css/lua/json）改**网络优先**，只有 wasm/字体/图标/音频缓存优先；
   所有浏览器测试再统一加 `?nosw=1`。
2. **`scrollWidth > clientWidth` 判断横向溢出不可靠。**
   对 `overflow: visible` 的容器，Chrome 会把 `scrollWidth` 钳到 padding box，
   于是 invest 屏那张超出 106px 的 StatCard 被漏报。改用父子 `getBoundingClientRect`
   直接比较才稳（`?measure=1` + 体检里合并一趟独立量测）。

### 12.6 全量验收现状

```
npm run verify（Node 侧 7 组）
无头端到端      34 / 34        存档系统        12 / 12
HTTP 通路        7 / 7         长线系统        47 / 47
浏览器布局体检  22 屏，问题屏 0   全链路          10 / 10
长跑数值回归     9 / 9

npm run test:browser（浏览器侧 5 项）
存档持久化 2 / 2 · 性能基准 1 / 1 · PWA 2 / 2
```

---

## 十三、一句话总结

这个工程是"**逻辑 5.5 万行、UI 一座桥**"的结构：55,000 行 Lua 里真正绑死引擎的不到 30 处，其余全是可移植的纯逻辑；UI 层虽然是自研库且源码缺失，但 API 面只有 7 个控件、属性与 CSS Flexbox 几乎一一对应。**转 HTML 网页游戏在技术上没有拦路虎，成本几乎全部落在重写那一个 UI 库上；真正的障碍是版权，不是技术。**

而且这一点已经被实测证实：阶段 0 的原型只新写了 **约 1100 行代码**，就让**一行未改**的
55,099 行游戏逻辑在真实浏览器里跑通了全部 22 个屏幕、点击交互、时间推进与存档往返。
剩下的工作是"打磨"，不是"攻坚"。

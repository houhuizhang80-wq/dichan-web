# 地产风云 · HTML 网页移植

把一份 TapTap SCE 微端（Urho3D 系引擎 + 55,099 行 Lua）游戏
**原封不动**地跑在浏览器里：Lua 逻辑与全部 22 个屏幕代码一行未改，
只用 JS 重新实现了引擎的 `urhox-libs/UI` 声明式 UI 库和少量引擎全局桩。

## ⚠️ 这个仓库里没有游戏本体

**本仓库只包含「移植引擎」，不含任何游戏源码 / 美术 / 音频。**
游戏本体是第三方开发者的商业作品（TapTap 上架），需要你**自备一份合法获得的副本**。

```bash
git clone <本仓库>
cd dichan-web
npm install
mkdir game-src && cp -r /path/to/your/game/src/* game-src/   # 需含 main.lua
npm run dist          # 构建静态站点（会带上 game-src/）
npm run preview:dist  # 本地预览
npm run serve         # 或者用开发服务器（读 ../地产风云/src，见下）
```

`game-src/` 已在 `.gitignore` 里，默认不会被提交。
详细的权利说明见 [NOTICE.md](./NOTICE.md)。

### 部署到 GitHub Pages

```bash
npm run deploy:pages                 # 用 game-src/ 构建并推到 gh-pages 分支
npm run deploy:pages -- --from=/path/to/game/src
```

首次推送后到仓库 **Settings → Pages** 把 Source 选成 `gh-pages` 分支即可。

> 说明：开发服务器 `serve.mjs` 默认读同级目录的 `../地产风云/src`（原作者本机的布局）。
> 换机器时用 `GAME_SRC=/path/to/src npm run serve` 覆盖，或者直接用 `npm run dist` 走静态包。

| 阶段 | 状态 | 内容 |
|---|---|---|
| **阶段 0** | ✅ 完成 | 桥接验证：Lua 加载、UI 树渲染、点击回传、长跑、存档往返 |
| **阶段 1** | ✅ 完成 | 像素级对齐：字体子集化接入、props 全量覆盖、真实浏览器逐屏布局体检 |
| **阶段 2** | ✅ 完成 | 全链路打通：真实 UI 点击走完「拿地→交付→清盘」；长跑数值回归基线 |
| **阶段 3** | ✅ 完成 | 长线系统等价验证：自持资产 / 个人理财 / 个人生活 / 股市 / 集团 / 国际 / 治理 |
| **阶段 4** | ✅ 完成 | 收尾：存档深度验证与浏览器持久化、真机性能基准、PWA 离线 |

---

## 快速开始

```bash
cd D:\2026\ai\2\地产风云_web
npm install          # 只依赖 wasmoon
npm run serve        # http://127.0.0.1:5173/
```

调试参数：

| URL | 作用 |
|---|---|
| `/?screen=dashboard` | 启动后直接进入指定屏幕（22 屏任意） |
| `/?autostart=1&screen=capital` | 先自动开一局（直接调 `GD.InitCompany`），再进入指定屏幕 |
| `/?fixture=1&months=14&screen=project` | 自动开一局 → 拿地 → 立项 → 推进 14 个月，用来看「报建/施工/预售/交付」各阶段的真实界面 |
| `/?audit=1` | 逐屏布局体检，结果写进页面里的 `#audit-report` |
| `/?debug=1` | 右下角显示布局量测（viewport / `#app` 尺寸） |
| `/?font=pixel` | 改用 FusionPixel 像素字体（与官方演示视频对比用） |
| `/?bold=synth` | 改用浏览器合成粗体（默认是忠实模式：粗体不生效，与原包一致） |

## 验收命令

```bash
npm run verify        # 全部 7 组验收（Node 侧），一把跑完
npm run verify:all    # 再追加浏览器侧的持久化 / 性能 / PWA 验收
npm run verify:ui     # 无头 34 项 + HTTP 7 项 + 浏览器布局体检
npm run verify:game   # 全链路 10 + 数值回归 9 + 长线系统 47 + 存档 12

npm run test          # 无头端到端：Lua→UI树→DOM→点击→长跑→存档往返
npm run test:http     # HTTP 通路：模块清单 / MIME / UMD / 路径穿越
npm run test:audit    # 真实浏览器逐屏布局体检（溢出/越界/零尺寸/令牌核对）
npm run test:lifecycle# 全链路：真实 UI 点击走完 拿地→报建→施工→预售→交付→清盘
npm run test:sim      # 长跑 120 个月的数值回归基线比对
npm run test:systems  # 8 个长线系统场景的等价验证
npm run test:save     # 存档系统：8 槽位 / 自动存档 / 损坏回退 / 云存档降级
npm run test:browser  # 浏览器：跨刷新持久化 + 性能基准 + PWA（需要 Edge/Chrome）
npm run shots         # 真实浏览器逐屏截图 → .out/shots/*.png
npm run snapshot      # 22 屏渲染成静态 HTML → .out/screens.html
npm run probe         # 打印各屏可点击文案（编排点击脚本用）
npm run lua -- "<code>"  # 在真实游戏环境里跑一段 Lua（探测用）
npm run props         # 全量核对 UI props 覆盖（2571 处调用点）
npm run fonts         # 重新生成字体子集（WOFF2）
npm run icons         # 从官方图标生成 PWA 图标
npm run sim:update    # 重新生成数值基线（改动游戏逻辑后需要）
```

当前状态（本机实测）：

```
无头端到端      34 / 34 通过，Lua 侧报错 0 条
HTTP 通路        7 / 7  通过
浏览器布局体检  22 屏 2239 节点，问题屏 0（另有 1 屏为原版设计溢出，106px，数值与 Yoga 一致）
全链路          10 / 10 通过（两次运行完全一致）
长跑数值回归     9 / 9  通过（120 个月，逐月 15 项指标与基线完全一致）
长线系统        47 / 47 通过（8 个场景，各自独立起一台虚拟机）
存档系统        12 / 12 通过（8 槽位 / 自动存档 / .bak 回退 / 云存档降级）
浏览器持久化     2 / 2  通过（同一 profile 两次加载，localStorage 跨刷新保留）
性能基准        HandleUpdate p95=0.1ms（1200 次里只有 1 次超过一帧）
                Navigate p50=11.5ms / p95=33.7ms（最慢的屏 42ms）
PWA             80 项预缓存（wasm / 字体 / Lua 源码），可离线运行
字体            29.9 MB TTF -> 1.76 MB WOFF2（7753 字符，含 GB2312 一二级汉字）
```

---

## 目录结构

```
地产风云_web/
├── index.html            页面外壳（只有 #stage / #app，视觉全部由 Lua 侧 props 驱动）
├── serve.mjs             开发服务器（双根：本目录 + ../地产风云/src）
├── css/
│   ├── fonts.css         由 tools/build_fonts.py 生成（@font-face）
│   └── app.css           容器 + 字体栈 + 手机框 + 滚动条
├── js/
│   ├── bridge.js         ★ props→CSS 渲染层 + WebBridge（Lua 侧唯一宿主接口）
│   ├── host.js           浏览器/Node 共用启动流程（wasmoon 引擎 + 帧循环）
│   ├── main.js           浏览器入口（模块拉取、localStorage 存档、音频、URL 参数）
│   └── audit.js          浏览器内布局体检（?audit=1）├── lua/
│   ├── urhox-libs/UI.lua             ★ urhox-libs/UI 的网页实现
│   ├── urhox-libs/UI/Core/Theme.lua  主题深合并
│   ├── urhox-libs/Effects/Effects.lua 背景音乐
│   └── web/
│       ├── boot.lua      替换 require、装引擎桩、加载 main.lua
│       ├── shims.lua     File / fileSystem / cjson / graphics / Scene / Lua5.1 兼容层
│       └── json.lua      纯 Lua JSON（替代引擎内置 cjson）
├── vendor/
│   ├── wasmoon/          Lua 5.4 → WebAssembly
│   └── fonts/            子集化后的 WOFF2
└── tools/                审计、子集化、截图、体检工具
```

★ = 真正新写的核心，合计 **Lua 约 550 行 + JS 约 900 行**。

---

## 工作原理

```
        ┌─────────────────── 浏览器 ───────────────────┐
        │  main.js  →  host.js  →  wasmoon(Lua 5.4)     │
        │      │                        │               │
        │      │              require("screens/…")      │
        │      │                        ↓               │
        │      │         UI.Panel{…}  ← 原游戏屏幕代码   │
        │      │                        ↓               │
        │      │        UI.SetRoot(tree) → JSON 字符串   │
        │      ↓                        ↓               │
        │  bridge.js  ←── WebBridge.setRoot(json) ──────┘
        │      ↓                                        │
        │  props→CSS → 真实 DOM                         │
        │      ↓                                        │
        │  点击 → WebBridge.__webInvoke(cbId, value) → Lua 回调
        └───────────────────────────────────────────────┘
```

### 四个关键设计决定

1. **UI 树走 JSON 字符串，不走逐节点 FFI。**
   `UI.SetRoot` 在 Lua 侧把整棵树序列化成 JSON，一次跨语言调用交给 JS。
2. **回调用「引用 id + 两代注册表」。**
   构建期 `props` 里的 function 抽成 `{__cb = id}` 登记到 `pendingCbs`；
   `UI.SetRoot` 时提升为 `currentCbs`，上一屏回调整体丢弃 → 无泄漏、无跨屏串号。
3. **每个节点分配 `__uid` 写入 `data-uid`。**
   工程里只有 445 处 `id=`，但 `SetText`/`GetScroll` 需要精确定位。
4. **Yoga 语义靠 CSS 兜底还原。**
   默认 `display:flex; flex-direction:column; flex-shrink:0; position:relative; box-sizing:border-box`
   （对应 Yoga 默认值），`flexBasis=0` → `0%`，`maxLines` → `-webkit-line-clamp`。

### 子节点收集：一个必须知道的坑

工程里有 **114 处** `children = { a, cond and b or nil, c }` 这种「列表中间有 nil」的写法。
Lua 的 `#`/`ipairs` 遇到中间空洞会截断，导致后面的元素全部丢失。
本实现用「扫描全部正整数键、跳过 nil」的策略（`UI.__childrenMode = "max"`）。

---

## 阶段 1：像素级对齐做了什么

### 1. 字体：40 MB TTF → 1.76 MB WOFF2

| 字体 | 用途 | 子集后 |
|---|---|---|
| NotoSansSC | **正文默认字体** | 990 KB |
| FusionPixelProp (+Bold) | 像素比例字体（`?font=pixel`） | 250 + 274 KB |
| FusionPixelMono | 像素等宽（mono 族） | 250 KB |

- 字符集 = 工程全部源码字符 ∪ ASCII/CJK 标点/全角符号 ∪ **GB2312 一二级汉字 6763 字**
  （最后一类专门用于覆盖玩家自由输入的公司名等中文），共 7753 字符；
  未覆盖的生僻字与 emoji 由字体栈后面的系统字体兜底。
- `NotoSansSC-Bold.ttf` 与 `Regular.ttf` 在原始包内**字节完全相同**（MD5 一致），
  所以默认走「忠实模式」：两档字重指向同一份字形，**粗体不会真的变粗**——与引擎行为一致。
  想启用合成粗体加 `?bold=synth`。

### 2. props 全量覆盖核对（`npm run props`）

对全部 **2571 处** `UI.<控件>{}` 调用点做词法分析（必须真词法分析：
props 表里嵌着 `function() … end` 闭包，闭包体内的 `local ok, msg = …` 不是 props 键），
抽出 **68 种 props 键**，逐一核对渲染层映射：

- 补齐 `borderLeftWidth` / `borderRightWidth`
- 补齐 `onSubmit`（输入框回车提交，工程里 3 处）
- 补齐 `size`（按钮 sm/md/lg 尺寸档）
- 补齐 `variant` 推导（primary/secondary/danger/success/warning/info/accent/outline/ghost，
  仅在未显式给颜色时生效，显式 props 永远优先）
- 补齐 `verticalAlign`
- **未覆盖键：0**

### 3. 真实浏览器逐屏布局体检（`npm run test:audit`）

用 Edge 无头 + `--dump-dom` 把页面内的量测结果取回，逐屏统计溢出/越界/零尺寸文字，
并把「实际用到的字号 / 边框宽度 / 文字颜色」与 `UITheme.lua` 的令牌核对：

```
22 屏 2239 节点，问题屏 0

文字颜色（11 种，其中 10 种是 UITheme 令牌的精确值）：
  rgb(76,91,106)  = T.TextSecondary #4C5B6A   ×722
  rgb(126,140,153)= T.TextMuted     #7E8C99   ×114
  rgb(28,42,56)   = T.TextPrimary   #1C2A38   ×108
  rgb(38,84,124)  = T.Primary       #26547C   ×88
  rgb(47,124,91)  = T.Success       #2F7C5B   ×61
  rgb(145,102,35) = T.Accent        #916623   ×50
  rgb(248,250,252)= T.TextOnDark    #F8FAFC   ×39
  rgb(49,108,148) = T.Info          #316C94   ×24
  rgb(178,116,28) = T.Warning       #B2741C   ×20
  rgb(181,68,68)  = T.Danger        #B54444   ×9
  rgb(255,255,255) ← 唯一一个非令牌值，来自 ChangelogScreen 里的显式字面量 ×2

边框宽度（全部为令牌值）：
  2px + T.Divider #C2CCD6 ×265     （C.Card 的 T.DividerWidth=2）
  2px + T.PrimaryBorder #507797 ×223（主题 Button 默认边框）
  1px + T.Divider ×40 / 1px + T.PrimaryBorder ×36（C.ActionButton）
  1px + T.Primary ×23（outline/ghost variant）…
```

### 4. 阶段 1 抓到的两个真 bug

1. **所有边框都没画出来。** CSS 里 `border-width` / `border-color` 只有在
   `border-style` 不为 `none` 时才生效，而渲染层只设了前两者 →
   全工程 265 张卡片、223 个按钮的边框全部消失（之前看起来"有边框"，
   其实是 `T.ShadowCard` 那个 0 模糊 2px 的硬阴影在骗眼睛）。
2. **修 1 的时候顺手引入的坑**：只加 `border-style: solid` 会让 `border-width` 取初值
   `medium`(=3px)、`border-color` 取 `currentColor`，于是每个节点凭空多出一圈
   3px 文字色边框（体检报告里一眼看出 `3px rgb(28,42,56)×580`）。
   正确做法是同时显式给 `border-width: 0` 打底。

这两个 bug 都是**肉眼看截图发现不了、只有量测才能抓到**的类型——这正是布局体检的价值。

### 5. 关于「像素级对齐」的目标修正

原本打算拿官方截图/演示视频做像素比对，实测后发现**不能直接比**：

- 从 `ChangelogScreen.lua` 可以读到版本演进：
  **V1.0.49「像素风格全面升级」**（改为高质量像素风格）→
  **V1.0.50「视觉风格调整」**（保留原有 UI 布局、内容及比例不变，改为低饱和蓝灰 + 暖金配色）→
  **V1.0.51「整体风格调整」**（现代商业风格）。
- 官方营销截图与演示视频（`demo.mp4`，19.2s / 30fps，已抽 21 帧）拍的是**深色像素风旧版**：
  底部导航是「总览/投资/项目/营销/运营 + 资本/品牌/个人/治理/设置」，
  顶栏还有一行 5 列统计（现金/总资产/负债/月利润/项目）。
- 而当前代码（v1.0.117）是**明亮现代商务风**：`UITheme.lua` 的注释写着
  「仅统一背景、**字体**与视觉色彩令牌」，底部导航已改为
  「总览/城市/投资/运营/资本/集团/国际/个人/治理/设置」，顶栏不再有统计行。

**结论：公开素材与当前代码不是同一个视觉版本，无法逐像素比对。**
因此阶段 1 的对齐目标改成可验证的两条：
1. **令牌一致性** —— 渲染出来的字号/边框/颜色必须能对上 `UITheme.lua` 的声明值（已达成，见上表）；
2. **几何自洽性** —— 22 屏不允许出现横向溢出、越界、零尺寸文字（已达成）。

参考素材仍保留在 `.out/reference/`（官方截图 7 张 + 演示视频 + 抽帧 + 字体取证图），
像素字体模式 `?font=pixel` 可用于与旧版视频做观感对照。

---

## 移植中踩到的坑（都已解决）

| # | 现象 | 根因 | 处理 |
|---|---|---|---|
| 1 | wasmoon 启动即 `Aborted(Assertion failed)` | emscripten 把 `process.argv[1]`（路径含中文）塞进 wasm 的 `_` 环境变量，而 `environ_get` 断言每字符 ≤ 255（Latin-1） | `new LuaFactory(url, { _: './this.program' })` |
| 2 | `MacroEconomy:234: attempt to call a nil value (field 'pow')` | 原引擎 Lua 方言是 **5.1 时代**，wasmoon 是 5.4 | `shims.lua` 加 5.1/5.2 兼容层（实测全工程只需 `math.pow`） |
| 3 | `main.lua:500: attempt to call a nil value (method 'FindById')` | 节点 metatable 缺 `__index` | `NodeMT.__index = NodeMT` |
| 4 | `main.lua:134: attempt to call a nil value (method 'CreateComponent')` | `Scene()` 桩返回裸表 | 补 `CreateComponent` 空实现 |
| 5 | `collectgarbage("incremental", …)` | 5.4 专属模式 | 包一层 pcall，不支持则降级 `restart` |
| 6 | `Components.lua` 的猴补丁失效 | 要求控件是**可调用表**且带 `.Init`/`.SetText` | `setmetatable({}, {__call=…})` + `W.Init(self, props)` |
| 7 | **所有边框不显示** | 缺 `border-style` | 默认 `border-style: solid; border-width: 0` |
| 8 | 存档 float→int | JSON 往返把 `2000.0` 变成 `2000` | 与原版 `lua-cjson` 行为一致，属正常 |
| 9 | OpenCV 读不到中文路径的图片 | `cv2.imread/imwrite` 在 Windows 上用 ANSI 路径 | 改用 `imdecode`/`imencode` + 文件读写 |

---

## 阶段 2：全链路打通 + 数值回归

### 1. 全链路（`npm run test:lifecycle`）

在无头假 DOM 上跑真游戏，**每一步都点真实按钮**（onClick → Lua 回调 → Navigate），
因此这条链路跑通就等于证明「UI 接线 + 状态机 + 屏幕渲染」三者都通：

```
[准备] 初始化公司（固定种子 20260101）+ 注入测试资金
       └ 推进到土地市场有地（供地计划有 3 个月延迟，LAND_SUPPLY_PLAN_DELAY=3）

[1] 拿地   投资页 → 参加竞拍 → 每轮出最大加价 → 竞得 → 确认收购 → 土地进储备
[2] 开发   土地储备 → 启动开发 → 项目「老城区刚需项目」创建
[3] 自动推进（读 ProjectScreen 自己给出的引导文案决定下一步）
       四证：国有土地使用证 → 建设用地规划许可证 → 建设工程规划许可证
       设计：规划指标 → 方案设计 → 限额设计（按钮在别的 Tab 上，脚本会自动切 Tab）
       施工：桩基 3% → 主体 29% → 景观 61% → 装修 93%
       预售：营销页「开始预售」→ 0/96 套 → 96/96 套
       结算 → 竣工 → 交付（尾盘）→ 生成清盘清单 → 确认缴税并归档
[4] 数值自洽：无 NaN/Inf；资产 112231 万 / 现金 104217 万 / 负债 0 万
```

关键点：**状态机是游戏自己给的**。`ProjectScreen.lua:2956-3041` 会输出
`⏩ 下一步: 点击「开始办理」XX证` / `🏗️ 施工中 [桩基] 进度 3%` / `💰 施工完成！请进行项目结算`
这类引导文案，脚本直接读它来决定动作——比硬编码流程稳得多。

顺带踩到两个「只在这种脚本里才会遇到」的坑：

1. **JS 正则字符类会把 emoji 的高位代理搞混。**
   `[⏩🏗️🏠…]` 在 JS 里是按 UTF-16 码元匹配的，👔(U+1F454) 与 🏠(U+1F3E0) 的高位代理都是
   `\uD83D`，于是「👔 项目经理」这种无关标签也被当成引导文案。
   改成显式前缀数组 + `startsWith` 才对。
2. **项目页顶部有一排「阶段图标」标签**（📋/📐/🏗️/🏠…），它们是单个图标、长度很短，
   必须先按长度过滤再匹配，否则永远取到图标而不是引导句。

### 2. 长跑数值回归（`npm run test:sim`）

固定种子跑 120 个月（10 年），脚本里带一个「自动 CEO」：
每 6 个月拿一块最便宜的地并立项，每月用游戏自己的接口推进设计/预售/结算/竣工/清盘。

```
[运行] 120 个月，耗时 1.3s，120 个采样点，约 90 游戏月/秒
[不变量]
  ✔ 模拟过程中没有 NaN / Inf（对公司/个人/项目/贷款做 5 层深度扫描）
  ✔ 公司未破产
  ✔ 模拟确实在运转：拿地 7 / 立项 7 / 预售 3 / 结算 3 / 竣工 3 / 清盘 3
  ✔ 现金没有失控（始终不超过总资产的 2 倍 + 1 亿）
  ✔ 总资产单月跌幅不超过 50%（最大 18.4%，第 18 月）
  ✔ 所有月份的关键数值都是有限数
  ✔ 资产不为负、负债不为负
[基线比对]
  ✔ 逐月比对 120 个采样点：完全一致（模拟确定性成立）
  ✔ 最终状态一致：events=50 qual=1 cash=84206 assets=104737 projects=3 debt=0 credit=76
[业务概览]
  2001.02 → 2011.01，现金 80000 → 84206 万，总资产 → 104737 万
  资质等级 0 → 1，信用分 70 → 76，房价指数 100 → 134.9
```

**这份基线能证明什么、不能证明什么**（重要）：

- ✅ 能证明：模拟是**确定性**的（同种子两次跑逐月完全一致）——这是回归网成立的前提；
  任何改动导致数值漂移，都会精确报出「第几个月、哪个指标、从多少变到多少」。
- ❌ 不能证明：与原版引擎数值一致。原引擎是 Lua 5.1 的 RNG，wasmoon 是 Lua 5.4，
  随机序列本就不同；而且原版没有可用的黄金数据。

### 3. 阶段 2 新增工具

| 工具 | 用途 |
|---|---|
| `tools/lifecycle.mjs` | 全链路自动玩家：读游戏引导文案决定动作，真实点击走完全流程 |
| `tools/sim-baseline.mjs` | 长跑数值回归：不变量检查 + 逐月基线比对（`--update` 重建基线） |
| `tools/ui-probe.mjs` | 打印各屏可点击文案，用来编排点击脚本（`--months` / `--click` 辅助探索） |
| `?fixture=1&months=N` | 浏览器里一键造出「已拿地并推进 N 个月」的局面，人工目视审阅各阶段界面 |

---

## 阶段 3：长线系统等价验证（`npm run test:systems`）

每个场景**独立启动一台全新 Lua 虚拟机**（避免场景间状态污染），用真实游戏接口推进，
断言「状态迁移正确 + 关键数值合理 + 对应屏幕能渲染」。

```
[fixed-asset]      自持固定资产运营   7 通过 / 0 失败
  竣工项目留 1/3 自持（51 套 / 5100㎡）→ 转固定资产 → 装修升级 → 挂牌出租（企业租户）
  → 推进 12 个月：出租率 88%、月租合计 13.56 万、资产估值 2415 万
  → 物业费率 / 服务等级 / 物业人员可调

[personal-invest]  个人理财           6 通过 / 0 失败
  八类产品买入（存款/货基/债券/指数/股票/信托/PE/REITs）7/8 成功
  （PE 起投 10000 万，夹具只给了 5000）→ 24 个月后持仓 36319 万、净资产 400965 万
  → 赎回 → 策略组合 + 再平衡 + 年度报告 → 个人信用贷款

[personal-life]    个人生活与家庭     5 通过 / 0 失败
  按揭购房 → 出租 → 生活方式资产 → 社交身份 + 净资产 + 个税试算

[stock]            股市               4 通过 / 0 失败
  买入三只（SH000002/HK002007/SH601988）→ 24 个月后市值 15694 万、分红 114 万
  → 全部卖出，持仓归零

[group]            集团               6 通过 / 0 失败
  两家公司 → 组建集团 → 聘用 CEO → 个人注资 500 万 → 集团贷款 3000 万 → 12 个月运转

[international]    国际业务           7 通过 / 0 失败
  （需先成立集团）注册海外事业部 → 国别尽调 → 注资 + 升级业务部容量 2→8
  → 四种业务全部投出（直投土地/并购资产/合资公司/基金）→ 汇率对冲 + 国际银行存款
  → 24 个月后事业部净资产 74340 万

[governance]       公司治理           8 通过 / 0 失败
  股权融资（创始人 100% → 80%，股东数 2）→ 董事会席位 → 聘用 4 位高管（5 项加成）
  → 5 项股东决议全部通过 → CEO 月度报告开关 → 全权托管生效
```

### 一个重要发现：`hold` / `agency` 项目类别在当前版本不可达

原本计划验证「自持型项目 → 选择运营模式 → 招商运营」，实测发现走不通：

- `DevTypes.lua` 里 **5 个开发类型的 `category` 全是 `CATEGORY_SALE`**；
- `devCategory` 在整个工程里只由 `typeDef.category` 赋值（另有一处旧存档迁移强制设为 `sale`）；
- 因此 `GD.SelectOperationMode` / `GD.ChangeOperationMode` / `OP.*`（项目级运营）
  在当前版本是**死代码**，`DT.CATEGORY_HOLD` 的注释也写着「保留常量兼容旧存档」。

当前版本**可达**的「自持」路径是：销售型项目在单元规划时留一部分自持 →
竣工后 `GD.ConvertToFixedAsset` → 固定资产 → 出租 / 物业费 / 装修 / 服务升级（即上面的 fixed-asset 场景）。

另一个小发现：**租金收入不进流水账**（`GD.ledger` 里没有对应条目），
只在 `fa.monthlyRent` / `GD.GetFixedAssetSummary().totalMonthlyRent` 与现金上体现。

---

## 阶段 4：存档 / 性能 / PWA

### 1. 存档系统深度验证（`npm run test:save`，12 项）

```
[1] 8 个手动槽位        8/8 写入成功（每份 81.7~81.9 KB）；GetSlotInfo 全部可读；
                        GetLatestSlotInfoWithAuto 能正确选出最新槽
[2] 状态一致性          存档 → 故意把公司改名/改现金/改年份 → 读档 → 13 项关键状态逐字比对一致
[3] 自动存档            AutoSave → GetAutoSaveInfo → LoadAutoSave，现金 88888 完整还原
[4] 损坏恢复            主文件写坏 → 自动回退 .bak（恢复出的是备份里的 123456，不是主文件的 654321）
                        无备份时优雅返回 false + "存档数据损坏"，不崩溃
                        读不存在的槽位返回 false + "存档不存在"，不崩溃
[5] 云存档降级          无 clientCloud 时返回 false + "当前平台未连接云存档"
[6] 内容完整性          43 个顶层字段齐全，version=5，最大 81.8 KB（localStorage 单键上限 5120 KB）
```

另外在设置页用**真实按钮**走了一遍「保存 → 列表刷新 → 读档」（`test:systems` 的 `settings-save` 场景）。

### 2. 浏览器持久化（`npm run test:browser`）

同一份浏览器 profile 连续加载两次页面：第一次写存档，第二次读存档。

```
✔ 第一次加载：写入存档槽位 1        true||持久化测试地产|424242
✔ 第二次加载：读到上一次写的存档     持久化测试地产|424242|2001年01月01日
```

证明 `localStorage` 适配器真的跨刷新保留（而不是只在内存里转一圈）。

### 3. 真机性能基准

在页面内用真实时钟量测（**不能用 `--virtual-time-budget`**——它会把 `performance.now()`
冻住，量出来全是 0；改成页面把结果 POST 回开发服务器，验收脚本轮询文件）：

```
游戏时间推进到: 2002年3月
HandleUpdate ×1200: p50=0ms  p95=0.1ms  p99=0.4ms  max=25.2ms  mean=0.058ms
  超过一帧(16.7ms)的次数: 1 / 1200
Navigate    ×66:    p50=11.5ms  p95=33.7ms  max=42.2ms
  最慢的屏: settings=42.2ms  start=34.4ms  city=29.5ms  governance=29.1ms  personal=28.4ms
```

结论很清楚：**模拟逻辑基本免费（每次 0.058ms），唯一的成本是屏幕切换时的整棵 UI 树重建**
（中位 11.5ms，最慢 42ms）。也就是说如果要优化，方向是「局部刷新/虚拟列表」，
而不是「把 Lua 逻辑搬到 JS」。

### 4. PWA 离线

- `manifest.webmanifest`：standalone、portrait、主题色、192/512 图标（从官方图标裁切生成）
- `sw.js`：install 时预缓存外壳 + 全部 Lua 模块 + wasm + 字体；实测**缓存 80 项**
- 自检结果：`scope=http://127.0.0.1:5176/`，`active=true`，`hasWasm/hasFont/hasLua` 全为真

### 5. 阶段 4 抓到的两个坑

1. **Service Worker 的 cache-first 会让开发时一直吃到旧代码。**
   启用 SW 后，改完 `js/main.js` 刷新页面仍然是旧行为，排查方向完全跑偏
   （一度以为是分支顺序写错了）。修法：**代码类资源（html/js/css/lua/json）走网络优先**，
   只有 wasm / 字体 / 图标 / 音频这类大静态资源才缓存优先；所有浏览器测试再统一加 `?nosw=1`。
2. **`scrollWidth > clientWidth` 判断横向溢出不可靠。**
   对 `overflow: visible` 的容器，Chrome 会把 `scrollWidth` 钳到 padding box，
   于是 invest 屏那张超出 106px 的 StatCard 被漏报。改用父子 `getBoundingClientRect`
   直接比较才稳（`?measure=1` + 体检里合并一趟独立量测）。

## 手机 / 局域网访问

开发服务器默认绑 `0.0.0.0`，同一 WiFi 下手机可以直接打开：

```bash
npm run serve
# [web] 本机    : http://127.0.0.1:5173/
# [web] 局域网（手机同一 WiFi 下直接打开）:
# [web]   http://192.168.1.135:5173/   (以太网)
```

只想给本机用：`HOST=127.0.0.1 npm run serve`（PowerShell 里写 `$env:HOST='127.0.0.1'; npm run serve`）。

### 手机打不开时才需要动防火墙

**本机实测：不需要做任何事，扫码直接就能玩。**
（这台机器的防火墙是 **GPO 托管**的 —— `netsh advfirewall show publicprofile` 里
`LocalFirewallRules = N/A (GPO-store only)`，本地规则读不到也改不了，
但策略里并没有拦 node/5173，所以入站是通的。之前我误判成"被拦"，
是因为查询命令本身报错了，把"查不到"当成了"没有规则"。）

只有在**别的机器上**手机连不上时才需要放行端口。用管理员 PowerShell 执行一次：

```powershell
New-NetFirewallRule -DisplayName "dichan-web 5173" -Direction Inbound -Protocol TCP -LocalPort 5173 -Action Allow -Profile Any
```

删掉这条规则：

```powershell
Remove-NetFirewallRule -DisplayName "dichan-web 5173"
```

若放行后仍连不上，检查路由器是否开了 **AP 隔离 / 客户端隔离**（同一 WiFi 内设备互相不可见）。

### 手机上会有什么差异

| 项 | 说明 |
|---|---|
| **离线缓存（PWA）** | 局域网 `http://` 下 **Service Worker 不会注册**——浏览器只在 `https` 或 `localhost` 下把页面当安全上下文。所以手机上能玩，但没有离线缓存。想要离线得挂个 https（自签证书也行，需在手机上信任）。 |
| **字体** | 子集化的 NotoSansSC 是 1 MB，局域网首屏多等 1~2 秒，之后走浏览器缓存。 |
| **布局** | `#app` 是 `width:100%; max-width:430px`，手机上全屏铺满；桌面预览才收成 430px 手机框。顶栏预留了 56px（原工程硬编码的刘海安全区），在真机上正好。 |
| **音频** | 浏览器禁止自动播放，BGM 会在你第一次点屏幕后开始。 |
| **输入框** | `keyboardType="number"` 已映射成 `inputmode="decimal"`，手机上会弹数字键盘。 |
| **性能** | 桌面无头 Edge 实测 `HandleUpdate` p95 = 0.1ms、`Navigate` p50 = 11.5ms；手机 CPU 大概慢 3~5 倍，切屏会有一次轻微卡顿，但模拟逻辑仍然可以忽略。 |

---

## 已知差距（后续阶段）

- **像素级比对缺参照物**：公开素材是旧版深色像素风，无法与当前明亮商务风逐像素对齐；
  需要真机截图才能做真正的 diff。
- **数值一致性只能做回归，不能做对齐**：原引擎 Lua 5.1 的 RNG 与 wasmoon 的 Lua 5.4 不同，
  且原版没有黄金数据；现有基线证明的是「确定性」与「不漂移」，不是「与原版一致」。
- **文本换行点**：`maxLines` 用 `-webkit-line-clamp` 实现，断行点与 Yoga 的文本测量
  可能差一两个字。
- `UI.GetFocus()` 只跟踪 TextField / Button / Checkbox / Slider，其余控件未跟踪。
- `state.velocityY` 只是桩（滚动惯性交给浏览器原生实现）。
- 音频只接了 BGM，`SOUND_*` 其他音效未实现；浏览器自动播放需用户首次交互解锁。
- 存档用 `localStorage`（单键上限 5 MB，实测 40 KB，够用）；云存档 `clientCloud` 未实现。
- **只覆盖了「销售型」项目**：`hold` / `agency` 类别在当前版本不可达（见阶段 3 的发现），
  所以项目级「运营模式」链路无法验证；自持是通过「转固定资产」走的。
- **治理/集团/国际只做了状态级验证**：断言的是「接口调用成功 + 状态迁移正确 + 数值有限」，
  没有做业务合理性判断（例如海外事业部 24 个月后累计利润为负是正常还是异常，需要人工看）。
- **性能只测了桌面无头 Edge**：真机（手机浏览器）的帧率、内存占用、发热没量过；
  `Navigate` 最慢 42ms 意味着切屏时会有一次轻微卡顿，还没做局部刷新优化。
- **没有做多语言/无障碍**：界面文案全部来自原工程的中文字面量。
- **PWA 只在本地 http 下验证**：`localhost` 被视为安全上下文，SW 能注册；
  真部署到 https 域名还需要复核缓存策略与版本更新流程。

---

## 版权声明

`../地产风云/src` 是他人商业作品（TapTap app_id 856514）的反编译还原产物。
本移植工程**仅用于本地学习与研究**，不得公开分发、不得商用。
若要产品化，必须只借鉴经济模型思路重新实现，不能搬运其代码与美术资源。

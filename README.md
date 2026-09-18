# dichanfengyun —— 《地产风云》HTML 网页移植（完整自包含包）

这个文件夹是本次会话的**全部成果**，**自带游戏源码**，解压即跑，
运行效果与 `http://127.0.0.1:5173/` 完全一致。

---

## 一、怎么跑

```bash
cd dichanfengyun
npm run serve          # 打开 http://127.0.0.1:5173/
```

`node_modules` 已经一并打包（只有 wasmoon 一个依赖），所以**不需要 `npm install`**。
如果想重新装：`npm install` 即可。

手机同一 WiFi 下直接打开服务启动时打印的局域网地址（默认已绑 `0.0.0.0`）。

### 常用调试参数

| URL | 作用 |
|---|---|
| `/?screen=dashboard` | 直接进指定屏幕（22 屏任意） |
| `/?autostart=1&screen=capital` | 自动开一局再进指定屏 |
| `/?fixture=1&months=14&screen=project` | 自动拿地立项并推进 14 个月，看「报建/施工/预售」各阶段 |
| `/?font=pixel` | 切换成像素字体（对照旧版素材用） |
| `/?bold=synth` | 启用浏览器合成粗体 |
| `/?audit=1` / `?perf=1` / `?measure=1` | 布局体检 / 性能基准 / 越界量测 |
| `?nosw=1` | 不注册 Service Worker（调试时避免吃到缓存） |

---

## 二、目录结构

```
dichanfengyun/
├── index.html                 页面外壳（只有 #stage / #app，视觉全由 Lua 侧 props 驱动）
├── serve.mjs                  开发服务器（双根：本目录 + game-src/）
├── sw.js  manifest.webmanifest  PWA（离线缓存 + 安装）
├── css/                       字体栈与容器样式（fonts.css 由脚本生成）
├── js/                        ★ 移植引擎的浏览器侧
│   ├── bridge.js              props→CSS 渲染层 + WebBridge 宿主接口
│   ├── host.js                wasmoon 启动流程与帧循环
│   ├── main.js                入口：模块拉取、存档、音频、URL 参数
│   └── audit.js               浏览器内布局体检
├── lua/                       ★ 移植引擎的 Lua 侧
│   ├── urhox-libs/UI.lua      引擎声明式 UI 库的网页实现
│   ├── urhox-libs/UI/Core/Theme.lua
│   ├── urhox-libs/Effects/Effects.lua
│   └── web/                   boot.lua / shims.lua（引擎全局桩）/ json.lua（纯 Lua JSON）
├── game-src/                  ← 游戏源码（自带，57 个 Lua 文件 + 字体 + 音频）
├── vendor/
│   ├── wasmoon/               Lua 5.4 → WebAssembly 运行时
│   ├── fonts/                 子集化后的 WOFF2（40 MB TTF → 1.76 MB）
│   └── icons/                 PWA 图标（原创几何图形）
├── tools/                     全部工具（审计、构建、验收、截图…）
├── reference/                 官方素材与演示视频抽帧（对照用）
├── reports/                   本次会话的验收报告与截图
├── README-引擎文档.md          引擎的完整开发文档（分阶段记录、踩坑、性能数据）
├── 地产风云_HTML网页化可行性分析.md   可行性分析报告（含四阶段实测结果）
└── NOTICE.md                  权利与许可说明
```

---

## 三、验收状态（本包实测）

```bash
npm run verify        # Node 侧 7 组
npm run verify:all    # 再追加浏览器侧 3 组（需要 Edge/Chrome）
```

```
无头端到端      34 / 34 通过，Lua 侧报错 0 条
HTTP 通路        7 / 7  通过
浏览器布局体检  22 屏 2239 节点，问题屏 0（另有 1 屏为原版设计溢出 106px）
全链路          10 / 10 通过（真实 UI 点击走完 拿地→交付→清盘，两次运行完全一致）
长跑数值回归     9 / 9  通过（120 个月逐月与基线一致）
长线系统        47 / 47 通过（自持资产/个人理财/个人生活/股市/集团/国际/治理/设置页存档）
存档系统        12 / 12 通过（8 槽位 / 自动存档 / .bak 回退 / 云存档降级）
浏览器持久化     2 / 2  通过（跨刷新保留）
性能基准        HandleUpdate p95=0.1ms；Navigate p50=11.5ms
PWA             80 项预缓存（wasm / 字体 / Lua 源码），可离线
```

> 注意：`npm run verify` 里的「浏览器布局体检 / 浏览器持久化」需要本机有 Edge 或 Chrome。

---

## 四、这是什么、以及不是什么

**是**：一套让原本跑在 TapTap SCE 微端（Urho3D 系引擎）上的 Lua 游戏，
能**一行不改**跑在浏览器里的适配层 —— Lua 5.4（WASM）承载全部游戏逻辑与 22 个屏幕代码，
JS 侧只负责把声明式 UI 树渲染成 DOM。

**不是**：不是游戏本体的发行版。`game-src/` 是为了让这个包自包含而附带的本地副本，
`NOTICE.md` 里写明了权利边界；若要公开分发，请只分发引擎部分（不含 `game-src/`），
由使用者自备游戏文件。

---

## 五、重新构建 / 部署

```bash
npm run dist                    # 产出纯静态 dist/（相对路径，可放子目录）
npm run preview:dist            # 本地预览静态包
npm run deploy:pages            # 构建并推送到 gh-pages 分支（GitHub Pages）
npm run shots                   # 真实浏览器逐屏截图
npm run props                   # 核对 UI props 覆盖率（2571 处调用点）
npm run fonts                   # 重新生成字体子集
npm run sim:update              # 改动游戏逻辑后重建数值基线
```

---

## 六、已知边界

- **数值一致性只能做回归，不能与原版对齐**：原引擎是 Lua 5.1 的 RNG，wasmoon 是 Lua 5.4，
  随机序列本就不同，且原版没有黄金数据。现有基线证明的是「确定性」与「不漂移」。
- **像素级比对缺参照物**：公开素材是旧版深色像素风，与当前明亮商务风不是同一视觉版本。
- **`hold` / `agency` 项目类别在当前版本不可达**（5 个开发类型全是 `sale`），
  项目级「运营模式」是死代码；可达的自持路径是「转固定资产」。
- **性能只测了桌面无头 Edge**：手机真机帧率、内存、发热未量测；
  `Navigate` 最慢 42ms，切屏会有一次轻微卡顿（局部刷新优化未做）。
- 治理/集团/国际只做了状态级验证，未做业务合理性判断。

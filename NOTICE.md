# 说明与声明

## 这个仓库是什么

**《地产风云》的 HTML 网页移植引擎** —— 一套让原本跑在 TapTap SCE 微端（Urho3D 系引擎）
上的 Lua 游戏，能原封不动跑在浏览器里的适配层。

仓库里**只有移植引擎本身**，包含：

| 目录 | 内容 | 作者 |
|---|---|---|
| `lua/urhox-libs/` | 引擎 `urhox-libs/UI` 声明式 UI 库的网页实现 | 本项目原创 |
| `lua/web/` | 引擎全局桩（File / cjson / Scene / 音频）+ 纯 Lua JSON | 本项目原创 |
| `js/` | props→CSS 渲染层、WebBridge 宿主接口、启动流程、布局体检 | 本项目原创 |
| `css/`、`index.html`、`manifest.webmanifest`、`sw.js` | 页面外壳与 PWA | 本项目原创 |
| `tools/` | 审计、字体子集化、截图、性能基准、自动化验收工具 | 本项目原创 |
| `vendor/wasmoon/` | Lua 5.4 → WebAssembly 运行时 | [wasmoon](https://github.com/ceifa/wasmoon)，MIT |
| `vendor/fonts/` | 子集化后的字体 | Noto Sans SC（SIL OFL 1.1）、Fusion Pixel Font（见下） |
| `vendor/icons/` | PWA 图标 | 本项目原创几何图形 |

## 不包含什么

**本仓库不包含《地产风云》的游戏源码、美术、音频等任何游戏本体内容。**

游戏本体是第三方开发者的商业作品（TapTap 上架，`app_id 856514`）。
本仓库按「模拟器 / 移植项目」的通行做法，只提供引擎，
使用者需要**自备一份合法获得的游戏文件**才能运行：

```bash
# 把你自己的一份游戏源码放到仓库根目录的 game-src/ 下
mkdir game-src
# 复制 src/ 的内容进去（需包含 main.lua）
npm run dist          # 构建静态站点（会带上 game-src/）
npx serve dist        # 本地预览
```

`game-src/` 已在 `.gitignore` 中，默认不会被提交。

## 第三方字体

- **Noto Sans SC** — Google，SIL Open Font License 1.1，允许子集化与再分发。
- **Fusion Pixel Font（缝合像素字体）** — 作者 TakWolf，采用
  SIL Open Font License 1.1（详见上游仓库的 LICENSE）。
  若上游许可有变更，请以 <https://github.com/TakWolf/fusion-pixel-font> 为准。

字体仅做了**子集化**（按工程实际用到的字符裁剪）与 TTF→WOFF2 格式转换，未修改字形。

## 免责

本项目仅用于学习与研究。使用者在运行/分发时需自行确保对游戏本体拥有相应权利。

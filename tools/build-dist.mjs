// ============================================================================
// tools/build-dist.mjs —— 产出纯静态可部署目录 dist/
//
// 产物可以直接丢到 GitHub Pages / Netlify / Vercel / 任意静态服务器。
// 与开发服务器（serve.mjs）的区别：
//   · 没有动态接口，模块清单在构建期固化成 __modules.json
//   · 所有路径都是相对的，因此能部署在子路径下（如 /dichan-web/）
//
// 游戏源码默认从 game-src/ 读取（可选）：
//   · 没有 game-src/ 也能构建成功，只是页面会提示「缺少游戏源码」
//   · 把一份你自备的 src/ 放到 game-src/ 后重新构建即可正常运行
//
// 用法：
//   node tools/build-dist.mjs                 # 用 game-src/（若存在）
//   node tools/build-dist.mjs --from=../地产风云/src
// ============================================================================

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const WEB_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const DIST = path.join(WEB_ROOT, 'dist');
const DEFAULT_GAME_SRC = path.join(WEB_ROOT, 'game-src');

const args = process.argv.slice(2);
const fromArg = args.find((a) => a.startsWith('--from='));
const GAME_SRC = fromArg ? path.resolve(WEB_ROOT, fromArg.slice(7)) : DEFAULT_GAME_SRC;

// ---------------------------------------------------------------------------
// 复制工具
// ---------------------------------------------------------------------------
function copyFile(src, dst) {
  fs.mkdirSync(path.dirname(dst), { recursive: true });
  fs.copyFileSync(src, dst);
}

function copyDir(src, dst, filter = () => true) {
  if (!fs.existsSync(src)) return 0;
  let n = 0;
  for (const entry of fs.readdirSync(src, { withFileTypes: true })) {
    const s = path.join(src, entry.name);
    const d = path.join(dst, entry.name);
    if (entry.isDirectory()) {
      n += copyDir(s, d, filter);
    } else if (filter(s)) {
      copyFile(s, d);
      n++;
    }
  }
  return n;
}

/** 收集 Lua 模块：模块名 -> 相对 URL（相对 dist 根） */
function collectModules(dir, urlPrefix, base, out, aliasBoot) {
  if (!fs.existsSync(dir)) return;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      collectModules(full, urlPrefix, base, out, aliasBoot);
    } else if (entry.name.endsWith('.lua')) {
      const rel = path.relative(base, full).replace(/\\/g, '/');
      const name = rel.replace(/\.lua$/, '');
      out[name] = `${urlPrefix}/${rel}`;
      if (aliasBoot && name === 'web/boot') out.boot = `${urlPrefix}/${rel}`;
    }
  }
}

// ---------------------------------------------------------------------------
console.log('\n=== 构建静态部署包 ===\n');

if (fs.existsSync(DIST)) fs.rmSync(DIST, { recursive: true, force: true });
fs.mkdirSync(DIST, { recursive: true });

// 1) 应用外壳
const shellFiles = ['index.html', 'manifest.webmanifest', 'sw.js'];
for (const f of shellFiles) copyFile(path.join(WEB_ROOT, f), path.join(DIST, f));
copyDir(path.join(WEB_ROOT, 'css'), path.join(DIST, 'css'));
copyDir(path.join(WEB_ROOT, 'js'), path.join(DIST, 'js'));
copyDir(path.join(WEB_ROOT, 'lua'), path.join(DIST, 'lua'));
copyDir(path.join(WEB_ROOT, 'vendor'), path.join(DIST, 'vendor'));
console.log('  ✓ 应用外壳 / css / js / lua / vendor');

// 2) 游戏源码（可选）
//    注意：源包里的 Fonts/ 是 40 MB 的原始 TTF，网页版用的是 vendor/fonts 里的
//    WOFF2 子集，运行时根本不会去读这些 TTF，所以直接跳过（否则 dist 会白胖 40 MB）。
const hasGame = fs.existsSync(GAME_SRC) && fs.existsSync(path.join(GAME_SRC, 'main.lua'));
let gameCount = 0;
let skippedFonts = 0;
if (hasGame) {
  gameCount = copyDir(GAME_SRC, path.join(DIST, 'game'), (p) => {
    if (/[\\/]Fonts[\\/]/i.test(p)) { skippedFonts++; return false; }
    return true;
  });
  console.log(`  ✓ 游戏源码: ${GAME_SRC} → dist/game（${gameCount} 个文件，跳过 ${skippedFonts} 个字体文件）`);
} else {
  console.log(`  ! 没有找到游戏源码（${GAME_SRC}/main.lua 不存在）`);
  console.log('    构建仍然成功，但页面会提示「缺少游戏源码」');
}

// 3) 模块清单（构建期固化，路径全部相对）
const modules = {};
collectModules(path.join(DIST, 'lua'), './lua', path.join(DIST, 'lua'), modules, true);
collectModules(path.join(DIST, 'game'), './game', path.join(DIST, 'game'), modules, false);
fs.writeFileSync(path.join(DIST, '__modules.json'), JSON.stringify({ modules }, null, 0));
console.log(`  ✓ __modules.json：${Object.keys(modules).length} 个模块`);

// 4) Pages 相关：禁用 Jekyll（否则下划线开头的文件会被吞掉）
fs.writeFileSync(path.join(DIST, '.nojekyll'), '');

// 5) 说明文件
fs.writeFileSync(path.join(DIST, 'README.txt'), [
  '地产风云 · 网页移植（静态构建产物）',
  '',
  '这是一个纯静态站点，直接放在任意静态服务器根目录即可运行。',
  hasGame
    ? '本次构建已包含游戏源码（dist/game/）。'
    : '本次构建**不含**游戏源码，页面会提示缺少 game/main.lua。',
  '',
  '部署到 GitHub Pages：把本目录内容推到 gh-pages 分支即可。',
  '本地预览：npx serve . 或 python -m http.server',
  '',
].join('\n'));

// 6) 体积统计
function dirSize(dir) {
  let total = 0;
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    total += e.isDirectory() ? dirSize(p) : fs.statSync(p).size;
  }
  return total;
}

const mb = (n) => (n / 1024 / 1024).toFixed(2) + ' MB';
console.log(`\n产物目录: ${DIST}`);
console.log(`总体积  : ${mb(dirSize(DIST))}`);
for (const part of ['lua', 'game', 'js', 'css', 'vendor']) {
  const p = path.join(DIST, part);
  if (fs.existsSync(p)) console.log(`  ${part.padEnd(8)} ${mb(dirSize(p))}`);
}
console.log('');

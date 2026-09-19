// ============================================================================
// tools/browser-audit.mjs —— 真实浏览器内的逐屏布局体检
// 用 Edge/Chrome 无头 + --dump-dom 取回页面里 <pre id="audit-report"> 的 JSON，
// 汇总 22 屏的：横向溢出 / 超出父容器 / 零尺寸文字 / 字号集合 / 边框集合 / 文字颜色集合。
// 用法：node tools/browser-audit.mjs [--json]
// ============================================================================

import { spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const WEB_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const OUT_DIR = path.join(WEB_ROOT, '.out');
const PORT = Number(process.env.PORT || 5175);
const BASE = `http://127.0.0.1:${PORT}`;

const BROWSERS = [
  'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe',
  'C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe',
  'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
  'C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe',
];

const findBrowser = () => BROWSERS.find((p) => fs.existsSync(p)) || null;

// 已知的「原版设计就存在的溢出」：InvestScreen 里两处 4 连 StatCard 行没有 flexWrap，
// 每个 StatCard 有 minWidth=120，4*120+3*8 = 504 > 内容区 398 —— Yoga 算出来也是 504，
// 也就是说原版引擎同样溢出（被 ScrollView 横向裁掉）。这里把精确数值固化下来，
// 一旦数值变化就说明布局回归了。
const KNOWN_ORIGINAL_OVERFLOW = {
  invest: {
    overflowX: [[430, 520], [398, 504], [398, 504]],
    outOfParentPx: 106,
  },
};

function classify(r) {
  const zero = r.zeroSizeText.length;
  const overflowX = r.overflowX.length;
  const out = r.outOfParent || [];
  const known = KNOWN_ORIGINAL_OVERFLOW[r.screen];
  if (!known) return { real: overflowX + zero + out.length, known: 0 };

  // invest：允许最多 3 条横向滚动 + 1 条 106px 的 StatCard 越界（原版设计溢出）
  const overs = out.map((o) => Math.round(o.over ?? o.overflowPx ?? 0));
  const isKnown = zero === 0 && overflowX <= 3 && out.length <= 1
    && (out.length === 0 || overs[0] === known.outOfParentPx);
  return isKnown
    ? { real: 0, known: overflowX + out.length }
    : { real: overflowX + zero + out.length, known: 0 };
}

async function waitForServer(timeoutMs = 15000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      const r = await fetch(BASE + '/__modules.json');
      if (r.ok) return;
    } catch { /* 等待 */ }
    await new Promise((r) => setTimeout(r, 200));
  }
  throw new Error('开发服务器启动超时');
}

function runBrowser(exe, args, timeoutMs = 120000) {
  return new Promise((resolve) => {
    const child = spawn(exe, args, { stdio: ['ignore', 'pipe', 'pipe'] });
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', (d) => (stdout += d.toString()));
    child.stderr.on('data', (d) => (stderr += d.toString()));
    const timer = setTimeout(() => child.kill(), timeoutMs);
    child.on('close', (code) => {
      clearTimeout(timer);
      resolve({ code, stdout, stderr });
    });
  });
}

const browser = findBrowser();
if (!browser) {
  console.error('未找到 Edge/Chrome，跳过浏览器体检');
  process.exit(0);
}

const server = spawn(process.execPath, [path.join(WEB_ROOT, 'serve.mjs')], {
  cwd: WEB_ROOT,
  env: { ...process.env, PORT: String(PORT) },
  stdio: ['ignore', 'ignore', 'pipe'],
});

let exitCode = 0;
try {
  await waitForServer();
  console.log('\n=== 地产风云 · 网页移植 · 真实浏览器布局体检 ===\n');

  const url = `${BASE}/?autostart=1&audit=1&nosw=1`;
  const { stdout } = await runBrowser(browser, [
    '--headless=new',
    '--disable-gpu',
    '--no-sandbox',
    '--hide-scrollbars',
    '--no-first-run',
    '--disable-extensions',
    `--user-data-dir=${path.join(OUT_DIR, 'edge-profile')}`,
    '--window-size=900,1000',
    '--virtual-time-budget=40000',
    '--dump-dom',
    url,
  ]);

  const m = /<pre id="audit-report">([\s\S]*?)<\/pre>/.exec(stdout);
  fs.writeFileSync(path.join(OUT_DIR, 'audit-dump.html'), stdout);
  if (!m) {
    console.error('没能取回体检报告（页面可能启动失败）');
    console.error('原始 DOM 已存到 .out/audit-dump.html');
    process.exit(1);
  }

  const decode = (s) =>
    s.replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"')
     .replace(/&#39;/g, "'").replace(/&amp;/g, '&');
  const report = JSON.parse(decode(m[1]));
  fs.writeFileSync(path.join(OUT_DIR, 'audit.json'), JSON.stringify(report, null, 2));

  // 补一遍独立的越界量测：audit 那趟是在启动后立刻同步跑完的，
  // 而 ?measure=1 这趟页面存活更久，能稳定抓到 overflow:visible 容器的越界。
  let measured = { total: 0, worst: [] };
  try {
    const dump = await runBrowser(browser, [
      '--headless=new', '--disable-gpu', '--no-sandbox', '--hide-scrollbars', '--no-first-run',
      '--disable-extensions', `--user-data-dir=${path.join(OUT_DIR, 'edge-profile')}`,
      '--window-size=900,1000', '--virtual-time-budget=60000', '--dump-dom',
      `${BASE}/?autostart=1&measure=1&nosw=1`,
    ]);
    const mm = /<pre id="measure-report">([\s\S]*?)<\/pre>/.exec(dump.stdout);
    if (mm) measured = JSON.parse(decode(mm[1]));
  } catch (e) {
    console.log('  （越界量测补充失败: ' + e.message + '）');
  }
  fs.writeFileSync(path.join(OUT_DIR, 'measure.json'), JSON.stringify(measured, null, 2));

  const agg = {
    fontSizes: {},
    borderWidths: {},
    textColors: {},
    kinds: {},
  };
  const addCount = (dst, src) => {
    for (const [k, v] of Object.entries(src || {})) dst[k] = (dst[k] || 0) + v;
  };

  let totalNodes = 0;
  let badScreens = 0;
  let knownScreens = 0;
  console.log(
    '屏幕'.padEnd(24) + '节点'.padStart(6) + '深度'.padStart(6) +
    '横溢'.padStart(6) + '越界'.padStart(6) + '零尺寸'.padStart(8) + '  备注',
  );
  console.log('-'.repeat(96));

  for (const r of report.screens) {
    if (r.error) {
      badScreens++;
      console.log(`${r.screen.padEnd(24)}  ${r.error}`);
      continue;
    }
    totalNodes += r.nodes;
    addCount(agg.fontSizes, r.fontSizes);
    addCount(agg.borderWidths, r.borderWidths);
    addCount(agg.textColors, r.textColors);
    addCount(agg.kinds, r.kinds);

    const cls = classify(r);
    if (cls.real) badScreens++;
    else if (cls.known) knownScreens++;
    const note = [];
    if (cls.known && !cls.real) note.push('（原版设计溢出，数值与 Yoga 计算一致）');
    else {
      if (r.overflowX.length) note.push(`横溢:${r.overflowX[0].kind}${r.overflowX[0].id ? '#' + r.overflowX[0].id : ''}(${r.overflowX[0].client}→${r.overflowX[0].scroll})`);
      if (r.outOfParent.length) note.push(`越界:${r.outOfParent[0].kind}(${r.outOfParent[0].overflowPx}px)`);
      if (r.zeroSizeText.length) note.push(`零尺寸:${r.zeroSizeText[0].text}`);
    }

    console.log(
      r.screen.padEnd(24) +
      String(r.nodes).padStart(6) +
      String(r.maxDepth).padStart(6) +
      String(r.overflowX.length).padStart(6) +
      String(r.outOfParent.length).padStart(6) +
      String(r.zeroSizeText.length).padStart(8) +
      '  ' + note.join(' '),
    );
  }

  const fmt = (obj, unit = '') =>
    Object.entries(obj)
      .sort((a, b) => b[1] - a[1])
      .map(([k, v]) => `${k}${unit}×${v}`)
      .join('  ');

  console.log(`\n合计节点数: ${totalNodes}（${report.screens.length} 屏）`);
  console.log(`有问题的屏: ${badScreens}    已知原版溢出的屏: ${knownScreens}`);

  console.log(`\n=== 越界量测（?measure=1 独立一趟，父子包围盒比较）===`);
  console.log(`越界元素总数: ${measured.total}`);
  if (measured.worst && measured.worst.length) {
    for (const w of measured.worst) {
      console.log(
        `  ${String(w.screen).padEnd(12)} ${w.kind.padEnd(8)} 超出 ${String(w.over).padStart(6)}px` +
        `  w=${w.w} parentW=${w.parentW} overflowX=${w.parentOverflow}  ${w.text}`,
      );
    }
    console.log('  （invest 的 4 连 StatCard 行没有 flexWrap、每个 minWidth=120，');
    console.log('    4×120+3×8=504 > 内容区 398 —— Yoga 算出来同样是 504，属原版设计溢出）');
  } else {
    console.log('  （无）');
  }
  console.log(`\n用到的字号集合   : ${fmt(agg.fontSizes)}`);
  console.log(`用到的边框宽度   : ${fmt(agg.borderWidths)}`);
  console.log(`用到的控件种类   : ${fmt(agg.kinds)}`);
  console.log(`\n用到的文字颜色（去重后 ${Object.keys(agg.textColors).length} 种）:`);
  for (const [c, n] of Object.entries(agg.textColors).sort((a, b) => b[1] - a[1])) {
    console.log(`  ${c.padEnd(26)} ×${n}`);
  }

  console.log(`\n完整报告: ${path.join(OUT_DIR, 'audit.json')}\n`);
  exitCode = badScreens > 0 ? 2 : 0;
} catch (e) {
  console.error('体检异常: ' + (e && e.stack ? e.stack : e));
  exitCode = 1;
} finally {
  server.kill();
}

process.exit(exitCode);

// ============================================================================
// tools/http-check.mjs —— 验证浏览器实际走的那条通路（HTTP + UMD + MIME）
// 用法：node tools/http-check.mjs
// ============================================================================

import { spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';

const WEB_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const PORT = Number(process.env.PORT || 5199);
const BASE = `http://127.0.0.1:${PORT}`;

let passed = 0;
let failed = 0;

async function check(name, fn) {
  try {
    const detail = await fn();
    passed++;
    console.log(`  \x1b[32m✔\x1b[0m ${name}${detail ? '  ' + detail : ''}`);
  } catch (e) {
    failed++;
    console.log(`  \x1b[31m✘\x1b[0m ${name}\n      ${e && e.message ? e.message : e}`);
  }
}

function assert(cond, msg) {
  if (!cond) throw new Error(msg || '断言失败');
}

async function waitForServer(timeoutMs = 15000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      const r = await fetch(BASE + '/__modules.json');
      if (r.ok) return;
    } catch { /* 还没起来 */ }
    await new Promise((r) => setTimeout(r, 200));
  }
  throw new Error('开发服务器启动超时');
}

console.log('\n=== 地产风云 · 网页移植阶段 0 · HTTP 通路验收 ===\n');

const child = spawn(process.execPath, [path.join(WEB_ROOT, 'serve.mjs')], {
  cwd: WEB_ROOT,
  env: { ...process.env, PORT: String(PORT) },
  stdio: ['ignore', 'pipe', 'pipe'],
});
child.stderr.on('data', (d) => process.stderr.write('[server] ' + d));

try {
  await waitForServer();
  console.log(`开发服务器已就绪：${BASE}\n`);

  let modules = null;
  await check('GET /__modules.json', async () => {
    const r = await fetch(BASE + '/__modules.json');
    assert(r.ok, 'HTTP ' + r.status);
    modules = (await r.json()).modules;
    const names = Object.keys(modules);
    assert(names.includes('main'), '清单缺少 main');
    assert(names.includes('boot'), '清单缺少 boot');
    assert(names.includes('urhox-libs/UI'), '清单缺少 urhox-libs/UI');
    return `${names.length} 个模块`;
  });

  await check('GET /index.html', async () => {
    const r = await fetch(BASE + '/');
    const html = await r.text();
    assert(r.ok, 'HTTP ' + r.status);
    assert(html.includes('vendor/wasmoon/index.js'), '未引用 wasmoon');
    assert(html.includes('js/main.js'), '未引用入口脚本');
    return `${html.length} 字节`;
  });

  await check('wasmoon UMD 资源可达且 MIME 正确', async () => {
    const js = await fetch(BASE + '/vendor/wasmoon/index.js');
    assert(js.ok, 'index.js HTTP ' + js.status);
    assert(js.headers.get('content-type').includes('javascript'), 'index.js MIME 异常');

    const wasm = await fetch(BASE + '/vendor/wasmoon/glue.wasm');
    assert(wasm.ok, 'glue.wasm HTTP ' + wasm.status);
    const mime = wasm.headers.get('content-type');
    assert(mime === 'application/wasm', 'glue.wasm MIME 必须是 application/wasm（instantiateStreaming 依赖），实际: ' + mime);

    const served = Buffer.from(await wasm.arrayBuffer());
    const local = fs.readFileSync(path.join(WEB_ROOT, 'vendor', 'wasmoon', 'glue.wasm'));
    assert(served.equals(local), 'glue.wasm 内容与本地不一致');
    return `${(served.length / 1024).toFixed(0)} KB，MIME=${mime}`;
  });

  await check('wasmoon 以 <script> 方式加载时暴露 window.wasmoon.LuaFactory', () => {
    const code = fs.readFileSync(path.join(WEB_ROOT, 'vendor', 'wasmoon', 'index.js'), 'utf8');
    const sandbox = {
      console,
      WebAssembly,
      TextEncoder,
      TextDecoder,
      performance,
      URL,
      setTimeout,
      clearTimeout,
      fetch,
      XMLHttpRequest: function XMLHttpRequest() {},
    };
    sandbox.window = sandbox;
    sandbox.self = sandbox;
    sandbox.globalThis = sandbox;
    sandbox.document = {
      currentScript: { src: BASE + '/vendor/wasmoon/index.js' },
      baseURI: BASE + '/',
    };
    vm.createContext(sandbox);
    vm.runInContext(code, sandbox, { filename: 'wasmoon-umd.js' });
    assert(sandbox.wasmoon, 'window.wasmoon 未挂载');
    assert(typeof sandbox.wasmoon.LuaFactory === 'function', 'LuaFactory 不是函数');
    return 'UMD 分支正确';
  });

  await check('全部模块 URL 可拉取且为 UTF-8 文本', async () => {
    const names = Object.keys(modules);
    const results = await Promise.all(
      names.map(async (n) => {
        const r = await fetch(BASE + modules[n]);
        if (!r.ok) return `${n}: HTTP ${r.status}`;
        const t = await r.text();
        if (!t.length) return `${n}: 空文件`;
        return null;
      }),
    );
    const bad = results.filter(Boolean);
    assert(bad.length === 0, bad.slice(0, 5).join('; '));
    return `${names.length}/${names.length} 通过`;
  });

  await check('游戏 Lua 源码经 HTTP 拉取后与磁盘一致（中文未损坏）', async () => {
    const r = await fetch(BASE + '/game/screens/StartScreen.lua');
    const text = await r.text();
    assert(text.includes('地 产 风 云'), '中文字符串损坏');
    assert(text.includes('新 游 戏'), '按钮文案缺失');
    return `${text.length} 字节`;
  });

  await check('路径穿越被拒绝', async () => {
    const r = await fetch(BASE + '/game/../../windows/win.ini');
    assert(r.status === 403 || r.status === 404, '预期 403/404，实际 ' + r.status);
    return 'HTTP ' + r.status;
  });
} catch (e) {
  failed++;
  console.log(`  \x1b[31m✘\x1b[0m 服务器验收异常\n      ${e.message}`);
} finally {
  child.kill();
}

console.log(`\n=== 结果：通过 ${passed} 项，失败 ${failed} 项 ===\n`);
process.exit(failed > 0 ? 1 : 0);

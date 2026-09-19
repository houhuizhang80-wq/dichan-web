// ============================================================================
// tools/headless.mjs —— 阶段 0 无头验收
// 覆盖：Lua 加载 → UI 树渲染 → 点击回传 → 引擎桩 → 长跑推进 → 存档往返 → 全屏切换
// 用法：node tools/headless.mjs
// ============================================================================

import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';

import { WEB_ROOT, buildModuleMap, loadSources } from './modules.mjs';
import { createFakeDOM } from './fakedom.mjs';
import { bootGame } from '../js/host.js';

const require = createRequire(import.meta.url);
const { LuaFactory } = require('wasmoon');

const SAVE_DIR = path.join(WEB_ROOT, '.saves');

let passed = 0;
let failed = 0;

function check(name, fn) {
  try {
    const detail = fn();
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

function createNodeAdapter() {
  const full = (p) => path.join(SAVE_DIR, p.replace(/[:*?"<>|]/g, '_'));
  return {
    read: (p) => {
      try {
        return fs.readFileSync(full(p), 'utf8');
      } catch {
        return null;
      }
    },
    write: (p, t) => {
      fs.mkdirSync(path.dirname(full(p)), { recursive: true });
      fs.writeFileSync(full(p), t);
    },
    exists: (p) => fs.existsSync(full(p)),
    del: (p) => {
      try {
        fs.unlinkSync(full(p));
      } catch { /* 忽略 */ }
    },
    mkdir: (p) => fs.mkdirSync(full(p), { recursive: true }),
  };
}

const SCREENS = [
  'start', 'changelog', 'companyCreate', 'city', 'dashboard', 'invest', 'auction',
  'project', 'sales', 'asset', 'capital', 'brand', 'personal', 'personalLife',
  'personalFinance', 'governance', 'group', 'international',
  'groupDiversification', 'settings', 'ledger', 'inheritance',
];

const EXPECT = {
  start: '地 产 风 云',
  changelog: '更新日志',
  companyCreate: '创立房地产公司',
  dashboard: '公司组合总览',
};

const luaLogs = [];

(async () => {
  console.log('\n=== 地产风云 · 网页移植阶段 0 · 无头验收 ===\n');

  const map = buildModuleMap();
  const sources = loadSources(map);
  const shimCount = Object.keys(map).filter((n) => map[n].startsWith(path.join(WEB_ROOT, 'lua'))).length;
  console.log(`模块清单: ${Object.keys(map).length} 个（游戏 ${Object.keys(map).length - shimCount} / 垫片 ${shimCount}）`);
  console.log(`源码体积: ${(Object.values(sources).reduce((a, s) => a + s.length, 0) / 1024 / 1024).toFixed(2)} MB\n`);

  const dom = createFakeDOM();

  console.log('[1] 启动 Lua 虚拟机并加载 main.lua');
  let app;
  try {
    app = await bootGame({
      LuaFactory,
      sources,
      doc: dom.doc,
      vfsAdapter: createNodeAdapter(),
      audio: { play: () => 1, setGain: () => {} },
      log: (m) => luaLogs.push(m),
      initialScreen: 'start',
      raf: null,
    });
  } catch (e) {
    console.error('\x1b[31m启动失败\x1b[0m');
    console.error(e && e.stack ? e.stack : e);
    luaLogs.forEach((l) => console.log('  ' + l));
    process.exit(1);
  }
  check('Lua 5.4 虚拟机启动 + 58 个模块加载', () => {
    const stats = app.lua.global.get('__webStats')();
    assert(stats.modules >= 50, '模块数异常: ' + stats.modules);
    return `模块数 ${stats.modules}`;
  });

  console.log('\n[2] 开场页渲染');
  const startTexts = dom.texts();
  check('UI 树已渲染为 DOM', () => `节点数 ${dom.count()}`);
  check('开场页内容正确', () => {
    assert(startTexts.includes('地 产 风 云'), '缺少主标题');
    assert(startTexts.includes('新 游 戏'), '缺少新游戏按钮');
    return startTexts.slice(0, 5).join(' | ');
  });

  console.log('\n[3] 交互链路：点击「新 游 戏」→ Lua 回调 → Navigate');
  const before = dom.count();
  const btn = dom.findByText('新 游 戏');
  check('按钮带回调并已注册到 DOM', () => {
    assert(btn, '未找到按钮');
    assert(btn.getAttribute('data-uid'), '按钮缺少 data-uid');
    return `data-uid=${btn.getAttribute('data-uid')}`;
  });
  btn.dispatch('click');
  check('屏幕已切换且无构建报错', () => {
    const texts = dom.texts();
    const err = texts.find((t) => t.includes('页面加载出错'));
    assert(!err, '构建报错: ' + texts[texts.indexOf(err) + 1]);
    assert(dom.count() !== before, 'DOM 未重建');
    assert(texts.includes('创立房地产公司'), '未进入公司注册页');
    return `${before} → ${dom.count()} 节点`;
  });

  console.log('\n[4] 引擎桩：File / fileSystem / cjson 往返');
  check('存档读写链路可用', () => {
    const r = app.lua.doStringSync(`
      local payload = { version = 5, name = "测试公司", nums = {1,2,3}, nested = { cash = 1234.5 } }
      local text = cjson.encode(payload)
      local f = File("saves/selftest.json", FILE_WRITE)
      if not f:IsOpen() then return "write-open-failed" end
      f:WriteString(text); f:Close()
      if not fileSystem:FileExists("saves/selftest.json") then return "not-exists" end
      local r = File("saves/selftest.json", FILE_READ)
      if not r:IsOpen() then return "read-open-failed" end
      local raw = r:ReadString(); r:Close()
      local back = cjson.decode(raw)
      if back.version ~= 5 then return "version-mismatch" end
      if back.name ~= "测试公司" then return "utf8-mismatch" end
      if back.nums[3] ~= 3 then return "array-mismatch" end
      if math.abs(back.nested.cash - 1234.5) > 1e-9 then return "number-mismatch" end
      return "ok:" .. tostring(#raw)
    `);
    assert(String(r).startsWith('ok:'), '失败: ' + r);
    return `JSON ${String(r).slice(3)} 字节`;
  });
  check('JSON 转义 / 空表 / 布尔 / 深嵌套', () => {
    const r = app.lua.doStringSync(`
      local s = cjson.encode({ q = '引号"反斜杠\\\\换行\\n制表\\t', t = true, f = false,
                               empty = {}, deep = { a = { b = { c = { 1, 2 } } } } })
      local b = cjson.decode(s)
      if b.q ~= '引号"反斜杠\\\\换行\\n制表\\t' then return "escape-fail" end
      if b.t ~= true or b.f ~= false then return "bool-fail" end
      if type(b.empty) ~= "table" then return "empty-fail" end
      if b.deep.a.b.c[2] ~= 2 then return "deep-fail" end
      return "ok"
    `);
    assert(r === 'ok', '失败: ' + r);
    return '通过';
  });

  console.log('\n[5] 开局（直接调用 GD.InitCompany，绕过 UI 表单）');
  check('公司创建成功', () => {
    const r = app.lua.doStringSync(`
      local GD = require("GameData")
      local ok, msg = GD.InitCompany("网页移植测试地产", "private", "balanced", 2000, GD.cities[1].name)
      GD.paused = true
      return tostring(ok) .. "|" .. tostring(msg or "") .. "|" .. tostring(GD.company.cash)
    `);
    assert(String(r).startsWith('true|'), '创建失败: ' + r);
    return `公司现金 ${String(r).split('|')[2]} 万`;
  });

  console.log('\n[6] 全屏遍历（22 个屏幕）');
  for (const screen of SCREENS) {
    check(`Navigate("${screen}")`, () => {
      const ok = app.lua.global.get('__webNavigate')(screen);
      assert(ok, 'Navigate 返回 false');
      const texts = dom.texts();
      const errIdx = texts.findIndex((t) => t.includes('页面加载出错') || t.includes('AppShell加载出错'));
      if (errIdx >= 0) throw new Error('构建报错: ' + (texts[errIdx + 1] || '').slice(0, 200));
      assert(dom.count() >= 4, '节点数过少: ' + dom.count());
      if (EXPECT[screen]) {
        assert(texts.some((t) => t.includes(EXPECT[screen])), `缺少预期文案「${EXPECT[screen]}」`);
      }
      return `${dom.count()} 节点 · ${texts.filter((t) => t.length > 1).slice(0, 2).join(' | ').slice(0, 46)}`;
    });
  }

  console.log('\n[7] 长跑：连续推进游戏时间（含月结 + CEO 报告 + UI 自动刷新）');
  check('模拟循环无异常', () => {
    const beforeLogs = luaLogs.length;
    app.lua.doStringSync(`
      local GD = require("GameData")
      GD.gameSpeed = 6
      GD.paused = false
      return true
    `);
    for (let i = 0; i < 1200; i++) app.pump(0.05);
    const newLogs = luaLogs.slice(beforeLogs).filter((l) => l.includes('出错') || l.includes('失败'));
    assert(newLogs.length === 0, newLogs.slice(0, 3).join(' / '));
    const stats = app.lua.global.get('__webStats')();
    assert(stats.year > 2001 || stats.month > 1, `时间未推进: ${stats.year}-${stats.month}`);
    return `推进到 ${stats.year}年${String(stats.month).padStart(2, '0')}月`;
  });

  console.log('\n[8] 存档往返（buildSaveData → cjson → File → VFS → 读回还原）');
  check('SaveToSlot(1) 成功', () => {
    const r = app.lua.doStringSync(`
      local GD = require("GameData")
      local ok, err = GD.SaveToSlot(1)
      return tostring(ok) .. "|" .. tostring(err or "")
    `);
    assert(String(r).startsWith('true|'), '存档失败: ' + r);
    const file = path.join(SAVE_DIR, 'saves/slot_1.json');
    assert(fs.existsSync(file), '存档文件未生成');
    const size = fs.statSync(file).size;
    assert(size > 1000, '存档体积异常: ' + size);
    return `${(size / 1024).toFixed(1)} KB`;
  });
  check('存档内容可被 cjson 解析且字段完整', () => {
    const raw = fs.readFileSync(path.join(SAVE_DIR, 'saves/slot_1.json'), 'utf8');
    const data = JSON.parse(raw);
    for (const k of ['version', 'company', 'companyPortfolio', 'player', 'projects', 'landMarket']) {
      assert(data[k] !== undefined, '缺少字段 ' + k);
    }
    assert(data.company.name === '网页移植测试地产', '公司名不匹配: ' + data.company.name);
    return `version=${data.version} · ${data.year}年${data.month}月 · 公司「${data.company.name}」`;
  });
  check('LoadFromSlot(1) 还原成功', () => {
    const r = app.lua.doStringSync(`
      local GD = require("GameData")
      local beforeCash, beforeName = GD.company.cash, GD.company.name
      local ok, err = GD.LoadFromSlot(1)
      if not ok then return "load-failed:" .. tostring(err) end
      -- 注意：JSON 往返会把 2000.0 变成整数 2000（cjson 同样如此），因此按数值比较
      return table.concat({ "ok", tostring(beforeCash), tostring(GD.company.cash),
                            tostring(beforeName), tostring(GD.company.name) }, "|")
    `);
    const [, beforeCash, afterCash, beforeName, afterName] = String(r).split('|');
    assert(String(r).startsWith('ok|'), '读档失败: ' + r);
    assert(beforeName === afterName, `公司名不一致: ${beforeName} → ${afterName}`);
    assert(Math.abs(Number(beforeCash) - Number(afterCash)) < 1e-6, `现金不一致: ${beforeCash} → ${afterCash}`);
    return `${afterName} @ ${afterCash} 万（读档前后一致）`;
  });

  console.log('\n--- Lua 侧日志 ---');
  const errLogs = luaLogs.filter((l) => l.includes('出错') || l.includes('失败'));
  if (!luaLogs.length) console.log('  （无）');
  luaLogs.slice(0, 30).forEach((l) => console.log('  ' + l));
  if (luaLogs.length > 30) console.log(`  … 其余 ${luaLogs.length - 30} 条省略`);

  console.log(`\n=== 结果：通过 ${passed} 项，失败 ${failed} 项（Lua 侧报错 ${errLogs.length} 条）===\n`);
  process.exit(failed > 0 ? 1 : 0);
})();

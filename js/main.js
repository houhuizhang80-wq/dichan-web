// ============================================================================
// js/main.js —— 浏览器入口
//
// URL 参数：
//   ?screen=xxx            启动后直接进入指定屏幕
//   ?autostart=1           先自动开一局
//   ?fixture=1&months=N    开一局 → 拿地 → 立项 → 推进 N 个月（人工审阅各阶段）
//   ?audit=1               逐屏布局体检，结果写入 #audit-report
//   ?perf=1                性能基准，结果写入 #perf-report
//   ?savecheck=1|2         存档持久化检查（1=写，2=读），结果写入 #save-report
//   ?debug=1               右下角显示布局量测
//   ?font=pixel            改用像素字体   ?bold=synth 改用合成粗体   ?nosw=1 不注册 SW
// ============================================================================

import { bootGame } from './host.js';

const WASM_URL = './vendor/wasmoon/glue.wasm';
// 全部用相对路径：这样部署在子路径下（GitHub Pages 的 /<repo>/）也能跑
const GAME_ASSET_PREFIX = './game/';
const SCREENS = [
  'start', 'changelog', 'companyCreate', 'city', 'dashboard', 'invest', 'auction',
  'project', 'sales', 'asset', 'capital', 'brand', 'personal', 'personalLife',
  'personalFinance', 'governance', 'group', 'international',
  'groupDiversification', 'settings', 'ledger', 'inheritance',
];

const params = new URLSearchParams(location.search);
const mode = {
  audit: params.get('audit') === '1',
  perf: params.get('perf') === '1',
  savecheck: params.get('savecheck'),
  swcheck: params.get('swcheck') === '1',
  debug: params.get('debug') === '1',
};
const needsManualFrames = mode.audit || mode.perf || Boolean(mode.savecheck);

// ---------------------------------------------------------------------------
// 音频：替换引擎的 Effects.PlaySoundLooped
// ---------------------------------------------------------------------------
function clamp01(v) {
  const n = Number(v);
  if (!Number.isFinite(n)) return 1;
  return Math.max(0, Math.min(1, n));
}

function createAudio() {
  let el = null;
  return {
    play(path, gain) {
      try {
        const url = String(path).replace(/^assets\//, GAME_ASSET_PREFIX);
        el = new Audio(url);
        el.loop = true;
        el.volume = clamp01(gain);
        // 浏览器自动播放策略：首次交互后再补播
        el.play().catch(() => {
          const unlock = () => {
            el && el.play().catch(() => {});
            window.removeEventListener('pointerdown', unlock);
            window.removeEventListener('keydown', unlock);
          };
          window.addEventListener('pointerdown', unlock, { once: true });
          window.addEventListener('keydown', unlock, { once: true });
        });
      } catch (e) {
        console.warn('[web] 音频初始化失败', e);
      }
      return 1;
    },
    setGain(v) {
      if (el) el.volume = clamp01(v);
    },
  };
}

// ---------------------------------------------------------------------------
// 虚拟文件系统：localStorage
// ---------------------------------------------------------------------------
function createStorageAdapter(prefix = 'estate_vfs:') {
  return {
    read: (p) => localStorage.getItem(prefix + p),
    write: (p, t) => localStorage.setItem(prefix + p, t),
    exists: (p) => localStorage.getItem(prefix + p) !== null,
    del: (p) => localStorage.removeItem(prefix + p),
    mkdir: () => {},
  };
}

// ---------------------------------------------------------------------------
// 状态提示
// ---------------------------------------------------------------------------
const statusEl = document.getElementById('boot-status');

function setStatus(text, isError) {
  if (!statusEl) return;
  statusEl.textContent = text;
  statusEl.style.color = isError ? '#b54444' : '#4c5b6a';
}

function report(id, obj) {
  const pre = document.createElement('pre');
  pre.id = id;
  pre.textContent = typeof obj === 'string' ? obj : JSON.stringify(obj, null, 1);
  document.body.appendChild(pre);
  // 同时回传给开发服务器（无头验收用：不开 virtual-time 时取不到 DOM dump）。
  // 静态部署下这个接口不存在，fetch 会 404，已 catch 掉。
  try {
    fetch(`./__report?name=${id}`, { method: 'POST', body: pre.textContent }).catch(() => {});
  } catch { /* 忽略 */ }
}

// ---------------------------------------------------------------------------
// 模块拉取
// ---------------------------------------------------------------------------
async function loadSources() {
  const res = await fetch('./__modules.json');
  if (!res.ok) throw new Error('无法获取模块清单: HTTP ' + res.status);
  const { modules } = await res.json();

  const names = Object.keys(modules);
  const sources = {};
  await Promise.all(
    names.map(async (name) => {
      const r = await fetch(modules[name]);
      if (!r.ok) throw new Error(`模块 ${name} 拉取失败: HTTP ${r.status}`);
      sources[name] = await r.text();
    }),
  );
  return sources;
}

// ---------------------------------------------------------------------------
// 各模式共用的夹具：造出「已拿地并推进 N 个月」的局面
// ---------------------------------------------------------------------------
function fixtureLua(months) {
  return `
    local GD = require("GameData")
    local DT = require("DevTypes")
    math.randomseed(20260101)
    if not GD.gameStarted then
      GD.InitCompany("演示地产", "private", "balanced", 2000, GD.cities[1].name)
    end
    GD.company.cash = 100000
    GD.player.cash = 100000
    GD.company.totalAssets = 100000

    GD.paused = false
    local guard = 0
    while #GD.landMarket == 0 and guard < 400 do GD.DailyTick(); guard = guard + 1 end

    local best, bi
    for i, l in ipairs(GD.landMarket) do
      if not best or (tonumber(l.startPrice) or math.huge) < (tonumber(best.startPrice) or math.huge) then
        best, bi = l, i
      end
    end
    if best then
      local price = tonumber(best.startPrice) or 0
      GD.company.cash = GD.company.cash - price
      best.price = price
      best.status = "sold"
      best.acquiredMonth = GD.totalMonths
      best.ownerType = "player_company"
      best.ownerCompanyId = GD.activeCompanyId
      table.insert(GD.landReserve, best)
      table.remove(GD.landMarket, bi)
      local types = DT.GetTypesForLandUse(best.landUse)
      local devTypeId = types and types[1] and (types[1].id or types[1].key)
      if devTypeId then pcall(GD.StartDevelopment, best.id, devTypeId, nil, "basic") end
    end

    for _ = 1, ${months} do
      local p = GD.projects[1]
      if p then
        if GD.AutoConfirmScheme then pcall(GD.AutoConfirmScheme, p) end
        if GD.AutoConfirmCostCap then pcall(GD.AutoConfirmCostCap, p) end
        if p.sales and p.sales.canPresale and not p.sales.canSell then pcall(GD.StartPresale, p) end
        if p.status == "pending_settlement" then pcall(GD.SettleProject, p) end
        if p.status == "pending_completion" then pcall(GD.ConfirmCompletion, p) end
      end
      local target = GD.totalMonths + 1
      local g = 0
      while GD.totalMonths < target and g < 40 do GD.DailyTick(); g = g + 1 end
    end
    GD.paused = true
    return true
  `;
}

// ---------------------------------------------------------------------------
// 性能基准
// ---------------------------------------------------------------------------
function percentile(sorted, p) {
  if (!sorted.length) return 0;
  const idx = Math.min(sorted.length - 1, Math.max(0, Math.round((p / 100) * (sorted.length - 1))));
  return sorted[idx];
}

function perfReport(lua) {
  const tick = lua.global.get('__webTick');
  const nav = lua.global.get('__webNavigate');
  const round = (v) => Math.round(v * 1000) / 1000;

  // 预热
  for (let i = 0; i < 120; i++) tick(0.016);

  // ① 模拟步进（HandleUpdate，含月结/UI 自动刷新）
  const tickMs = [];
  for (let i = 0; i < 1200; i++) {
    const a = performance.now();
    tick(0.016);
    tickMs.push(performance.now() - a);
  }

  // ② 屏幕切换（Lua 构建 UI 树 → JSON → DOM 重建）
  const navMs = [];
  const perScreen = {};
  for (let r = 0; r < 3; r++) {
    for (const s of SCREENS) {
      const a = performance.now();
      nav(s);
      const d = performance.now() - a;
      navMs.push(d);
      perScreen[s] = Math.max(perScreen[s] || 0, d);
    }
  }

  const tickSorted = [...tickMs].sort((x, y) => x - y);
  const navSorted = [...navMs].sort((x, y) => x - y);
  const over16 = tickMs.filter((v) => v > 16.7).length;
  const over33 = tickMs.filter((v) => v > 33.3).length;

  const stats = lua.global.get('__webStats')();
  return {
    screen: `${stats.year}年${stats.month}月`,
    tick: {
      samples: tickMs.length,
      p50: round(percentile(tickSorted, 50)),
      p95: round(percentile(tickSorted, 95)),
      p99: round(percentile(tickSorted, 99)),
      max: round(tickSorted[tickSorted.length - 1] || 0),
      mean: round(tickMs.reduce((a, b) => a + b, 0) / tickMs.length),
      over16ms: over16,
      over33ms: over33,
    },
    navigate: {
      samples: navMs.length,
      p50: round(percentile(navSorted, 50)),
      p95: round(percentile(navSorted, 95)),
      max: round(navSorted[navSorted.length - 1] || 0),
      slowest: Object.entries(perScreen).sort((a, b) => b[1] - a[1]).slice(0, 5)
        .map(([k, v]) => `${k}=${round(v)}ms`),
    },
  };
}

// ---------------------------------------------------------------------------
// 启动
// ---------------------------------------------------------------------------
(async () => {
  try {
    // ---- Service Worker 自检（不需要加载游戏）----
    if (mode.swcheck) {
      const out = { supported: 'serviceWorker' in navigator, secure: window.isSecureContext };
      if (out.supported) {
        try {
          const reg = await navigator.serviceWorker.ready;
          out.scope = reg.scope;
          out.active = !!reg.active;
          out.controller = !!navigator.serviceWorker.controller;
          const keys = await caches.keys();
          out.caches = keys;
          if (keys.length) {
            const cache = await caches.open(keys[0]);
            const reqs = await cache.keys();
            out.cachedCount = reqs.length;
            out.hasWasm = reqs.some((r) => r.url.includes('glue.wasm'));
            out.hasFont = reqs.some((r) => r.url.includes('NotoSansSC'));
            out.hasLua = reqs.some((r) => r.url.includes('/game/'));
          }
        } catch (e) {
          out.error = String(e && e.message ? e.message : e);
        }
      }
      report('sw-report', out);
      return;
    }

    if (!window.wasmoon || !window.wasmoon.LuaFactory) {
      throw new Error('wasmoon 未加载（vendor/wasmoon/index.js）');
    }

    setStatus('正在拉取 Lua 模块…');
    const sources = await loadSources();
    if (!sources.main) {
      throw new Error(
        '缺少游戏源码（game/main.lua）。\n' +
        '本仓库只包含移植引擎，需要你自备一份游戏源码：\n' +
        '把 src/ 放到仓库根目录的 game-src/ 下，然后重新构建。',
      );
    }
    setStatus(`已加载 ${Object.keys(sources).length} 个模块，正在启动 Lua 虚拟机…`);

    const { lua } = await bootGame({
      LuaFactory: window.wasmoon.LuaFactory,
      wasmUrl: WASM_URL,
      sources,
      doc: document,
      vfsAdapter: createStorageAdapter(),
      audio: createAudio(),
      log: (m) => console.log(m),
      initialScreen: 'start',
      // 体检 / 基准 / 存档检查需要独占控制帧循环，这里不启动 rAF
      raf: needsManualFrames ? null : requestAnimationFrame.bind(window),
    });

    setStatus('');
    if (statusEl) statusEl.remove();

    window.__game = { lua, navigate: (s) => lua.global.get('__webNavigate')(s) };

    // ---- 通用状态准备（体检/性能/存档检查各自另有夹具，这里排除）----
    if (!mode.savecheck && !mode.perf) {
      if (params.get('autostart') === '1') {
        lua.doStringSync(`
          local GD = require("GameData")
          if not GD.gameStarted then
            GD.InitCompany("网页移植测试地产", "private", "balanced", 2000, GD.cities[1].name)
          end
          GD.paused = true
          return true
        `);
      }
      if (params.get('fixture') === '1') {
        const months = Math.max(0, Math.min(60, Number(params.get('months') || 0)));
        lua.doStringSync(fixtureLua(months));
      }
      const screen = params.get('screen');
      if (screen) lua.global.get('__webNavigate')(screen);
    }

    // ---- 布局体检 ----
    if (mode.audit) {
      const { runAudit } = await import('./audit.js');
      const results = runAudit(document, lua);
      const bad = results.filter(
        (r) => r.error || r.overflowX.length || r.outOfParent.length || r.zeroSizeText.length,
      );
      console.log(`[audit] ${results.length} 屏，其中 ${bad.length} 屏存在问题`);
      return;
    }

    // ---- 存档持久化检查 ----
    if (mode.savecheck) {
      let result;
      if (mode.savecheck === '1') {
        result = lua.doStringSync(`
          local GD = require("GameData")
          if not GD.gameStarted then
            GD.InitCompany("持久化测试地产", "private", "balanced", 2000, GD.cities[1].name)
          end
          GD.company.cash = 424242
          GD.AddEvent("持久化标记事件", "info")
          local ok, err = GD.SaveToSlot(1)
          local info = GD.GetSlotInfo(1)
          return tostring(ok) .. "|" .. tostring(err or "") .. "|" ..
                 tostring(info and info.name) .. "|" ..
                 string.format("%.0f", (info and info.cash) or -1)
        `);
      } else {
        result = lua.doStringSync(`
          local GD = require("GameData")
          local info = GD.GetSlotInfo(1)
          if not info then return "no-save" end
          return tostring(info.name) .. "|" .. string.format("%.0f", info.cash) .. "|" .. tostring(info.date)
        `);
      }
      report('save-report', { mode: mode.savecheck, result });
      return;
    }

    // ---- 性能基准 ----
    if (mode.perf) {
      lua.doStringSync(fixtureLua(10));
      lua.doStringSync('local GD = require("GameData") GD.gameSpeed = 6 GD.paused = false return true');
      report('perf-report', perfReport(lua));
      return;
    }

    // ---- 布局量测：找出「子元素右边缘超出父容器内容盒」最严重的前若干项 ----
    if (params.get('measure') === '1') {
      const rows = [];
      const walk = (el) => {
        const r = el.getBoundingClientRect();
        const p = el.parentElement;
        if (p && p.id !== 'app') {
          const pr = p.getBoundingClientRect();
          const pcs = getComputedStyle(p);
          const right = pr.right - parseFloat(pcs.borderRightWidth || 0) - parseFloat(pcs.paddingRight || 0);
          const over = r.right - right;
          if (over > 0.5) {
            rows.push({
              kind: el.getAttribute('data-kind') || el.tagName,
              id: el.getAttribute('data-ui-id') || '',
              over: Math.round(over * 10) / 10,
              w: Math.round(r.width),
              parentW: Math.round(pr.width),
              parentOverflow: pcs.overflowX,
              text: (el.textContent || '').replace(/\s+/g, ' ').trim().slice(0, 20),
            });
          }
        }
        for (const c of el.children) walk(c);
      };
      for (const s of SCREENS) {
        lua.global.get('__webNavigate')(s);
        const before = rows.length;
        walk(document.getElementById('app'));
        if (rows.length > before) {
          for (let i = before; i < rows.length; i++) rows[i].screen = s;
        }
      }
      rows.sort((a, b) => b.over - a.over);
      report('measure-report', { total: rows.length, worst: rows.slice(0, 15) });
      return;
    }

    // ---- 普通游玩模式（debug 量测）----
    if (mode.debug) {
      const app = document.getElementById('app');
      const stage = document.getElementById('stage');
      const r = app.getBoundingClientRect();
      const info = document.createElement('pre');
      info.style.cssText =
        'position:fixed;left:0;bottom:0;z-index:99999;background:#000;color:#0f0;' +
        'font-size:11px;line-height:1.5;padding:4px;margin:0;white-space:pre;';
      info.textContent =
        `innerWidth=${window.innerWidth} innerHeight=${window.innerHeight} dpr=${window.devicePixelRatio}\n` +
        `stage=${stage.getBoundingClientRect().width}  app=[${Math.round(r.left)},${Math.round(r.top)}] ${Math.round(r.width)}x${Math.round(r.height)}\n` +
        `docScrollW=${document.documentElement.scrollWidth} bodyW=${Math.round(document.body.getBoundingClientRect().width)}`;
      document.body.appendChild(info);
    }
  } catch (e) {
    console.error(e);
    setStatus('启动失败: ' + (e && e.message ? e.message : String(e)), true);
  }
})();

// ---------------------------------------------------------------------------
// Service Worker（离线可用）
// ---------------------------------------------------------------------------
if ('serviceWorker' in navigator && location.protocol.startsWith('http') && !params.get('nosw')) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('./sw.js', { scope: './' }).then(
      (reg) => console.log('[web] Service Worker 已注册:', reg.scope),
      (err) => console.warn('[web] Service Worker 注册失败:', err && err.message),
    );
  });
}

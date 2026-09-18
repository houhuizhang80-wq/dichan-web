// ============================================================================
// js/host.js —— 浏览器 / Node 共用的启动流程
// ============================================================================

import { createVFS, createWebBridge } from './bridge.js';

/**
 * @param {object} opts
 * @param {Function} opts.LuaFactory  wasmoon 的 LuaFactory 构造器
 * @param {string}   opts.wasmUrl     glue.wasm 地址（浏览器）；Node 下可省略
 * @param {object}   opts.sources     模块名 -> Lua 源码
 * @param {object}   opts.doc         document（真实或假 DOM）
 * @param {object}   opts.vfsAdapter  虚拟文件系统适配器
 * @param {Function} opts.log         日志
 * @param {object}   opts.audio       音频适配器
 * @param {string}   opts.initialScreen 启动后进入的屏幕
 * @param {Function} opts.raf         帧调度器（默认 requestAnimationFrame；无头测试传 null）
 */
export async function bootGame(opts) {
  const {
    LuaFactory,
    wasmUrl,
    sources,
    doc,
    vfsAdapter,
    log = (m) => console.log(m),
    audio,
    initialScreen = 'start',
    raf = typeof requestAnimationFrame === 'function' ? requestAnimationFrame.bind(globalThis) : null,
  } = opts;

  if (!sources || !sources.boot) throw new Error('缺少 boot.lua 源码（模块名 "boot"）');
  if (!sources.main) throw new Error('缺少 main.lua 源码（模块名 "main"）');

  const vfs = createVFS(vfsAdapter);
  const invokeRef = { current: () => {} };

  const bridge = createWebBridge({
    doc,
    vfs,
    readModule: (name) => (Object.prototype.hasOwnProperty.call(sources, name) ? sources[name] : null),
    log,
    initialScreen,
    invokeRef,
    audio,
  });

  // wasmoon/emscripten 会把 process.argv[1]（本工程路径含中文）写进 wasm 的 "_" 环境变量，
  // 而 environ_get 断言每个字符必须 <= 255（Latin-1），非 ASCII 路径会直接 abort。
  // 显式覆盖 "_" 为 ASCII 值即可，与目录名是否含中文无关。
  const factory = new LuaFactory(wasmUrl, { _: './this.program' });
  const lua = await factory.createEngine();

  lua.global.set('WebBridge', bridge);

  invokeRef.current = (id, value) => {
    try {
      lua.global.get('__webInvoke')(id, value);
    } catch (e) {
      log('[web] 回调执行失败: ' + (e && e.message ? e.message : String(e)));
    }
  };

  await lua.doString(sources.boot);

  // 标题
  try {
    const g = lua.global.get('graphics');
    if (g && g.windowTitle) doc.title = g.windowTitle;
  } catch (_) { /* 忽略 */ }

  const tick = lua.global.get('__webTick');
  let last = typeof performance !== 'undefined' ? performance.now() : Date.now();

  const pump = (dt) => {
    try {
      tick(dt);
    } catch (e) {
      log('[web] tick 出错: ' + (e && e.message ? e.message : String(e)));
    }
  };

  const frame = (now) => {
    const dt = Math.min((now - last) / 1000, 0.1);
    last = now;
    pump(dt);
    if (raf) raf(frame);
  };
  if (raf) raf(frame);

  return { lua, bridge, pump };
}

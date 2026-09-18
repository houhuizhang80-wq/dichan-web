// ============================================================================
// tools/modules.mjs —— 模块清单构建（dev server 与无头测试共用）
// 规则：垫片模块名 = 相对 lua/ 的路径；游戏模块名 = 相对 src/ 的路径。
// ============================================================================

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const WEB_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
export const LUA_ROOT = path.join(WEB_ROOT, 'lua');
// 游戏源码目录，按优先级查找：
//   1) 环境变量 GAME_SRC
//   2) 本仓库内的 game-src/（自包含布局，推荐）
//   3) 同级目录的 ../地产风云/src（原作者本机布局，向后兼容）
export const GAME_ROOT = (() => {
  if (process.env.GAME_SRC) return path.resolve(process.env.GAME_SRC);
  const local = path.join(WEB_ROOT, 'game-src');
  if (fs.existsSync(path.join(local, 'main.lua'))) return local;
  return path.resolve(WEB_ROOT, '..', '地产风云', 'src');
})();

function walkLua(dir, base, out) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      walkLua(full, base, out);
    } else if (entry.name.endsWith('.lua')) {
      const rel = path.relative(base, full).replace(/\\/g, '/').replace(/\.lua$/, '');
      out[rel] = full;
    }
  }
  return out;
}

/** @returns {Record<string, string>} 模块名 -> 绝对路径 */
export function buildModuleMap() {
  const map = {};
  walkLua(LUA_ROOT, LUA_ROOT, map);
  // 宿主入口别名
  map.boot = path.join(LUA_ROOT, 'web', 'boot.lua');
  // 游戏工程模块（main / GameData / screens/xxx ...）
  walkLua(GAME_ROOT, GAME_ROOT, map);
  return map;
}

/** @returns {Record<string, string>} 模块名 -> 源码文本 */
export function loadSources(map = buildModuleMap()) {
  const sources = {};
  for (const [name, file] of Object.entries(map)) {
    sources[name] = fs.readFileSync(file, 'utf8');
  }
  return sources;
}

/** 转为 dev server 使用的 URL 清单 */
export function buildModuleUrls(map = buildModuleMap()) {
  const modules = {};
  for (const name of Object.keys(map)) {
    if (name === 'boot') {
      modules[name] = '/lua/web/boot.lua';
    } else if (map[name].startsWith(LUA_ROOT)) {
      modules[name] = '/lua/' + path.relative(LUA_ROOT, map[name]).replace(/\\/g, '/');
    } else {
      modules[name] = '/game/' + path.relative(GAME_ROOT, map[name]).replace(/\\/g, '/');
    }
  }
  return modules;
}

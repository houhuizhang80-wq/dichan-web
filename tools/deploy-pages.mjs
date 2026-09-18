// ============================================================================
// tools/deploy-pages.mjs —— 把 dist/ 作为 gh-pages 分支推上去
//
// 用法：
//   node tools/deploy-pages.mjs                      # 用 game-src/ 构建并部署
//   node tools/deploy-pages.mjs --from=../地产风云/src
//   node tools/deploy-pages.mjs --repo=https://github.com/USER/REPO.git
//
// 说明：GitHub Pages 需要仓库为 public（Free 账号不支持私有仓库发布 Pages）。
// ============================================================================

import { execFileSync, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const WEB_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const DIST = path.join(WEB_ROOT, 'dist');
const BRANCH = 'gh-pages';

const args = process.argv.slice(2);
const repoArg = args.find((a) => a.startsWith('--repo='));
const fromArg = args.find((a) => a.startsWith('--from='));

function run(cmd, cmdArgs, cwd = WEB_ROOT, quiet = false) {
  const r = spawnSync(cmd, cmdArgs, { cwd, encoding: 'utf8', stdio: quiet ? 'pipe' : 'inherit' });
  if (r.status !== 0) {
    throw new Error(`${cmd} ${cmdArgs.join(' ')} 失败（exit ${r.status}）\n${r.stderr || ''}`);
  }
  return r.stdout || '';
}

/** 取父仓库的 origin，作为默认推送目标 */
function parentRemote() {
  try {
    const url = run('git', ['remote', 'get-url', 'origin'], WEB_ROOT, true).trim();
    return url || null;
  } catch {
    return null;
  }
}

console.log('\n=== 部署到 GitHub Pages ===\n');

// 1) 构建
console.log('[1/4] 构建 dist/');
const buildArgs = [path.join(WEB_ROOT, 'tools', 'build-dist.mjs')];
if (fromArg) buildArgs.push(fromArg);
run(process.execPath, buildArgs);

// 2) 确定远端
const remote = repoArg ? repoArg.slice(7) : parentRemote();
if (!remote) {
  console.error('\n✘ 找不到远端仓库。请先给本仓库加 origin，或用 --repo=<url> 指定。');
  process.exit(1);
}
console.log(`\n[2/4] 远端: ${remote}`);

// 3) 在 dist/ 里建一个独立仓库
console.log('[3/4] 生成 gh-pages 提交');
if (fs.existsSync(path.join(DIST, '.git'))) {
  fs.rmSync(path.join(DIST, '.git'), { recursive: true, force: true });
}
run('git', ['init', '-b', BRANCH], DIST, true);
run('git', ['add', '-A'], DIST, true);
const name = (() => { try { return run('git', ['config', 'user.name'], WEB_ROOT, true).trim(); } catch { return 'deploy'; } })();
const email = (() => { try { return run('git', ['config', 'user.email'], WEB_ROOT, true).trim(); } catch { return 'deploy@local'; } })();
run('git', ['-c', `user.name=${name}`, '-c', `user.email=${email}`,
  'commit', '-m', `deploy: ${new Date().toISOString()}`], DIST, true);
const count = fs.readdirSync(DIST).length;
console.log(`  已提交 ${count} 个顶层条目`);

// 4) 推送
console.log('[4/4] 推送');
run('git', ['push', '--force', remote, `${BRANCH}:${BRANCH}`], DIST);

// 推断 Pages 地址
let pagesUrl = '(未知)';
const m = /github\.com[/:]([^/]+)\/([^/.]+)(?:\.git)?/.exec(remote);
if (m) pagesUrl = `https://${m[1]}.github.io/${m[2]}/`;

console.log(`\n✓ 已推送到 ${BRANCH} 分支`);
console.log(`  试玩地址: ${pagesUrl}`);
console.log('  （首次推送后需要在 GitHub 仓库 Settings → Pages 里把 Source 选成');
console.log(`    "Deploy from a branch" + ${BRANCH} 分支，等 1~2 分钟生效）`);
console.log('');

#!/usr/bin/env node
'use strict';
/*
 * run-fixture.js — popup-shield.js（強力モード content script）の決定論テスト。
 *
 * iOS 17 を忠実にモデル化する要点（advisor 指摘）:
 *   - content script を「top frame のみ」に注入する（addInitScript=全フレームは使わない）。
 *     iOS 17 はページ生成 about:blank フレームに content script を注入しない（match_origin_as_fallback は 18.4+）。
 *     よって同一オリジン子フレームのカバーは hook の親→子 traversal に依存する＝ここが本丸の検証。
 *   - cross-site 判定は registrable ドメインで行うため、広告 URL は実在不要の別 registrable 文字列。
 *
 * 検証:
 *   ブロック対象（inline / third-party / about:blank / synthetic / iframe / 透明 overlay anchor）= popup 0・BLOCK/STUB
 *   正規（動画再生 / ユーザーが選んだ可視リンク / 内部リンク）= 妨害されない
 *
 * 終了コード: 0=全 PASS / 1=いずれか FAIL。
 */
const fs = require('fs');
const path = require('path');
const http = require('http');
const { chromium } = require('playwright-core');

const DIR = __dirname;
const RES = path.resolve(DIR, '../../Resources');
const IPHONE_UA = 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1';
const CT = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8' };

function serve(dir) {
  return new Promise((resolve) => {
    const srv = http.createServer((req, res) => {
      const u = decodeURIComponent(req.url.split('?')[0]);
      const fp = path.join(dir, u === '/' ? '/popunder-fixture.html' : u);
      if (!fp.startsWith(dir)) { res.writeHead(403); return res.end(); }
      fs.readFile(fp, (e, buf) => {
        if (e) { res.writeHead(404); return res.end('nf'); }
        res.writeHead(200, { 'content-type': CT[path.extname(fp)] || 'application/octet-stream' });
        res.end(buf);
      });
    });
    srv.listen(0, '127.0.0.1', () => resolve(srv));
  });
}

async function clickEl(page, sel) {
  const el = await page.$(sel);
  if (!el) throw new Error('no element ' + sel);
  const box = await el.boundingBox();
  if (box) await page.mouse.click(Math.round(box.x + box.width / 2), Math.round(box.y + Math.min(box.height / 2, 20)));
  else await el.click({ force: true }).catch(() => {});
  await page.waitForTimeout(350);
}

async function main() {
  const coreSrc = fs.readFileSync(path.join(RES, 'popup-shield-core.js'), 'utf8');
  const hookPath = path.join(RES, 'popup-shield-main.js');
  if (!fs.existsSync(hookPath)) { console.error('FAIL: popup-shield-main.js が存在しない（RED）'); process.exit(1); }
  const hookSrc = fs.readFileSync(hookPath, 'utf8');

  const srv = await serve(DIR);
  const port = srv.address().port;
  const base = `http://127.0.0.1:${port}/`;
  // ポータブル起動: system Chrome（channel）があれば使い、無ければ playwright bundled chromium に fallback
  // （ローカルは system Chrome / CI は bundled chromium で動かすため）。
  let browser;
  try {
    browser = await chromium.launch({ channel: 'chrome', headless: true, args: ['--no-sandbox'] });
  } catch (e) {
    browser = await chromium.launch({ headless: true, args: ['--no-sandbox'] });
  }
  const popups = [];
  let results = {}, decisions = [], shieldEvents = [];
  try {
    const context = await browser.newContext({ userAgent: IPHONE_UA, viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true });
    // 広告 popup が万一生成されてもコンテンツを読み込まない（.test は非解決だが保険で abort）
    await context.route('**/*', (route) => {
      const rt = route.request().resourceType();
      const h = (() => { try { return new URL(route.request().url()).hostname; } catch (e) { return ''; } })();
      // ローカル fixture 以外（.test 広告・news.example 等）は abort し、何も読み込まない。
      if (h && h !== '127.0.0.1') return route.abort();
      if (rt === 'image' || rt === 'media' || rt === 'font') return route.abort();
      return route.continue();
    });
    const page = await context.newPage();
    context.on('page', async (pg) => { if (pg === page) return; try { popups.push(pg.url() || '(blank)'); await pg.close(); } catch (e) {} });

    await page.goto(base, { waitUntil: 'load', timeout: 20000 });
    // iOS 17 モデル: top frame のみに core+hook を注入（about:blank 子フレームには注入しない）
    await page.evaluate(({ c, h }) => {
      // テスト観測用フック（PII 無し: kind/action/reason のみ）
      window.__popupShieldTest = { onDecision: (d) => (window.__decisions = window.__decisions || [], window.__decisions.push(d)) };
      // MAIN→ISOLATED bridge へ飛ぶ CustomEvent を捕捉（bridge の代わりに観測）
      window.__shieldEvents = [];
      window.addEventListener('__popupShieldMsg', (e) => { window.__shieldEvents.push(e.detail); }, false);
      // eslint-disable-next-line no-eval
      (0, eval)(c); (0, eval)(h);
    }, { c: coreSrc, h: hookSrc });
    await page.waitForTimeout(300);

    // ブロック対象ベクタ
    await clickEl(page, '#vInline');
    await clickEl(page, '#vProtoRel');
    await clickEl(page, '#vThird');
    await clickEl(page, '#vAboutBlank');
    await clickEl(page, '#vSyntheticClick');
    await clickEl(page, '#vIframe');
    // 透明全面 overlay anchor: player 領域をタップ（最前面の cross-site overlay anchor に当たる）
    await clickEl(page, '#player');
    // MutationObserver で overlay を追加 → player 再タップ
    await clickEl(page, '#vMutationOverlay');
    await clickEl(page, '#player');
    // 正規操作
    await clickEl(page, '#vPlayer');
    await clickEl(page, '#legitInternal');
    // 可視の正規外部リンク（target=_blank・許可されて popup 生成されるべき）
    await clickEl(page, '#legitLink');
    await page.waitForTimeout(400);

    results = await page.evaluate(() => window.__fixtureResults || {});
    decisions = await page.evaluate(() => window.__decisions || []);
    shieldEvents = await page.evaluate(() => window.__shieldEvents || []);
  } finally {
    await browser.close();
    await new Promise((r) => srv.close(r));
  }

  // 判定
  const hasDecision = (action, reasonSub) => decisions.some((d) => d.action === action && (!reasonSub || (d.reason || '').includes(reasonSub)));
  // 広告 window.open は全て block されるので popup を生成しない。よって生成された popup は
  // 許可された target=_blank（正規リンク 2 件: legitLink/legitInternal）だけになるはず。
  const legitCrossSiteAllowed = decisions.some((d) => d.kind === 'native-anchor' && d.action === 'allow' && d.crossSite === true && d.overlay === false);
  // MAIN→bridge イベント検証（PII を含まない最小スキーマ）
  const ALLOWED_EVENT_KEYS = ['version', 'type', 'frame', 'reason'];
  const readyEmitted = shieldEvents.some((e) => e && e.type === 'ready' && e.version === 1);
  const blockedEmitted = shieldEvents.filter((e) => e && e.type === 'blocked' && e.reason).length;
  const eventsNoPII = shieldEvents.every((e) => e && typeof e === 'object' && Object.keys(e).every((k) => ALLOWED_EVENT_KEYS.indexOf(k) !== -1));

  const checks = [
    ['inline window.open BLOCKED', results.inline === 'BLOCKED'],
    ['protocol-relative window.open BLOCKED（base 解決）', results.protoRel === 'BLOCKED'],
    ['third-party-script window.open BLOCKED', results.thirdParty === 'BLOCKED'],
    ['about:blank → STUB（実窓を作らない）', results.aboutBlank === 'STUB'],
    ['synthetic anchor.click() を BLOCK 判定', hasDecision('block', 'synthetic_anchor')],
    ['same-origin iframe window.open BLOCKED（traversal=iOS17 の本丸）', results.iframeOpen === 'BLOCKED'],
    ['透明 overlay anchor を BLOCK 判定', hasDecision('block', 'overlay_anchor')],
    ['正規: 動画 play() が妨害されない', results.player === 'PLAYING'],
    ['正規: 内部リンクがクリックできる', results.legitInternal === 'CLICKED'],
    ['正規: ユーザーが選んだ cross-site 可視リンクは許可', legitCrossSiteAllowed],
    ['広告由来の popup が 0 件（許可された正規リンクの 2 popup のみ）', popups.length === 2],
    ['MAIN→bridge: ready イベント発行', readyEmitted],
    ['MAIN→bridge: blocked イベントが reason 付きで発行', blockedEmitted >= 3],
    ['MAIN→bridge: イベントに URL/PII を含まない（最小スキーマのみ）', eventsNoPII && shieldEvents.length > 0],
  ];

  let ok = true;
  for (const [name, pass] of checks) { console.log((pass ? 'PASS' : 'FAIL') + ' - ' + name); if (!pass) ok = false; }
  console.log('\n--- detail ---');
  console.log('results:', JSON.stringify(results));
  console.log('decisions:', JSON.stringify(decisions));
  console.log('shieldEvents:', JSON.stringify(shieldEvents));
  console.log('popups:', JSON.stringify(popups));
  process.exit(ok ? 0 : 1);
}
main().catch((e) => { console.error('FATAL', e.stack || e.message); process.exit(1); });

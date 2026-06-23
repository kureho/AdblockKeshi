#!/usr/bin/env node
/*
 * diagnose.js — popunder の「発生フレーム」を確定する診断ツール（Phase 1 根本原因特定）。
 *
 * measure.js の baseline で「実 popup 7件/ロードだが top-frame の window.open=0」という
 * 矛盾を解明する。各フレーム（main + cross-origin iframe）に同じ計装を addInitScript で入れ、
 * クリック後に page.frames() を走査して各フレームの window.__diag を回収する。
 * これで「どのフレームの window.open / target=_blank anchor / native click が popup を生んだか」を確定する。
 *
 * コンテンツ保護: measure.js と同様 image/media/font を abort、cross-site top-doc を abort、
 * スクショ無し、URL は env/arg 渡し。
 */
'use strict';
const { chromium } = require('playwright-core');
const IPHONE_UA = 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1';

function host(u) { try { return new URL(u).hostname; } catch (e) { return ''; } }
function etld1(h) { const p = (h || '').split('.'); return p.slice(-2).join('.'); }

function perFrameInstrument() {
  // 各フレームで実行される。frame 自身の window.open / 合成クリック / native target=_blank を記録。
  var D = { frameURL: location.href, frameHost: location.hostname, windowOpen: [], anchorClick: [], nativeBlankClicks: [], blankAnchors: 0 };
  window.__diag = D;
  function h(u) { try { return new URL(u, location.href).hostname; } catch (e) { return ''; } }
  function st() { try { return (new Error()).stack || ''; } catch (e) { return ''; } }
  var ro = window.open;
  try {
    Object.defineProperty(window, 'open', { configurable: true, get: function () {
      return function (url) { D.windowOpen.push({ url: String(url == null ? 'about:blank' : url), host: h(url), stack: st().slice(0, 400) }); try { return ro.apply(window, arguments); } catch (e) { return null; } };
    }, set: function () {} });
  } catch (e) {}
  var rac = HTMLAnchorElement.prototype.click;
  HTMLAnchorElement.prototype.click = function () { D.anchorClick.push({ href: String(this.href || ''), target: String(this.target || ''), host: h(this.href) }); return rac.apply(this, arguments); };
  // capture-phase: native click が target=_blank anchor / cross-origin iframe に当たったか
  document.addEventListener('click', function (e) {
    try {
      var path = e.composedPath ? e.composedPath() : [];
      for (var i = 0; i < path.length; i++) {
        var n = path[i];
        if (n && n.tagName === 'A' && (n.target === '_blank' || !n.target) && n.href) {
          D.nativeBlankClicks.push({ href: String(n.href), host: h(n.href), target: n.target || '(self)' });
          break;
        }
      }
    } catch (er) {}
  }, true);
}

async function main() {
  const url = process.argv[2];
  if (!url) { console.error('usage: node diagnose.js <URL>'); process.exit(2); }
  const siteE = etld1(host(url).replace(/^www\./, ''));
  const browser = await chromium.launch({ channel: 'chrome', headless: true, args: ['--no-sandbox', '--disable-blink-features=AutomationControlled'] });
  const out = { frames: 0, crossOriginFrames: [], realPopups: [], perFrameDiag: [] };
  try {
    const context = await browser.newContext({ userAgent: IPHONE_UA, viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true, serviceWorkers: 'block' });
    await context.route('**/*', (route) => {
      const req = route.request(); const rt = req.resourceType();
      if (rt === 'image' || rt === 'media' || rt === 'font') return route.abort();
      if (rt === 'document' && req.isNavigationRequest()) {
        let isTop = false; try { const f = req.frame(); isTop = !!f && f.parentFrame() === null; } catch (e) { isTop = false; }
        if (isTop) { const hh = host(req.url()); if (hh && etld1(hh) !== siteE && req.url() !== url) { return route.abort(); } }
      }
      return route.continue();
    });
    await context.addInitScript(perFrameInstrument);
    const page = await context.newPage();
    context.on('page', async (pg) => { if (pg === page) return; try { out.realPopups.push(pg.url() || '(blank)'); await pg.close(); } catch (e) {} });
    try { await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 45000 }); } catch (e) { out.gotoError = e.message; }
    await page.waitForTimeout(8000);
    // advisor point 2: popunder 発火フレームが「click 前に既に存在するか」を確認する。
    // 既存なら親→子 same-origin traversal / MutationObserver が click より先に override を仕込める。
    out.framesBeforeClick = page.frames().map((f) => { const h = host(f.url()); return { host: h || '(blank)', sameOrigin: !h || etld1(h) === siteE }; });
    const W = 390, H = 844;
    for (const [x, y] of [[195, 270], [195, 270], [195, 340], [195, 470], [78, 340], [312, 340], [195, 210], [195, 380], [195, 270], [195, 510]]) {
      try { await page.mouse.click(x, y); } catch (e) {}
      await page.waitForTimeout(900);
    }
    await page.waitForTimeout(1500);
    // 全フレーム走査
    const frames = page.frames();
    out.frames = frames.length;
    for (const f of frames) {
      const fu = f.url();
      const fh = host(fu);
      if (fh && etld1(fh) !== siteE) out.crossOriginFrames.push(fh);
      try {
        const d = await f.evaluate(() => window.__diag || null);
        if (d && (d.windowOpen.length || d.anchorClick.length || d.nativeBlankClicks.length)) {
          out.perFrameDiag.push({ frameHost: fh || '(top/blank)', windowOpen: d.windowOpen, anchorClick: d.anchorClick, nativeBlankClicks: d.nativeBlankClicks });
        }
      } catch (e) { /* cross-origin frame.evaluate は CSP/detached で失敗しうる */ out.perFrameDiag.push({ frameHost: fh || '(?)', evalError: String(e.message).slice(0, 120) }); }
    }
    out.realPopups_crossSite = out.realPopups.filter((u) => { const hh = host(u); return hh && etld1(hh) !== siteE; }).length;
    out.crossOriginFrames = Array.from(new Set(out.crossOriginFrames));
  } finally { await browser.close(); }
  console.log(JSON.stringify(out, null, 2));
}
main().catch((e) => { console.error('FATAL', e.stack || e.message); process.exit(1); });

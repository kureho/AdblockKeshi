#!/usr/bin/env node
/*
 * measure.js — popunder 計測ハーネス（baseline / protection 二モード・同一シナリオ）
 *
 * 目的（tasks/streamtape-hardening の Phase 1/4 用）:
 *   - 任意の URL を iPhone Safari 相当 UA + viewport でコールドロードし、ポップアンダー／
 *     タップ乗っ取り／about:blank 経由遷移／current-tab リダイレクトを「実発火」で計測する。
 *   - --mode baseline = 計装のみ（広告挙動を素通りで観測・実ポップアップ数を数える）。
 *   - --mode protection --engine <path> = 出荷する content-script エンジン(popup-shield.js)を
 *     document_start で MAIN world に注入し、ブロック後の残存件数を同一シナリオで数える。
 *   ⇒ baseline と protection を同一操作で比較できる（受入条件14: 修正前後の実測比較）。
 *
 * コンテンツ保護方針（このタスクの厳守事項）:
 *   - resourceType が image / media / font のリクエストは route で abort する
 *     （= 動画本体・サムネ等のコンテンツを一切ダウンロードしない）。request イベントは
 *     abort 前に発火するので「メディア要求が出た=プレーヤー生存」の判定材料は残る。
 *   - スクリーンショットは一切撮らない。
 *   - cross-site の top-frame document ナビゲーションは記録してから abort（広告ページを
 *     現在タブに読み込まない）。広告 script / iframe の JS 実行は計測のため許可する
 *     （JS は「動画コンテンツ」ではない）。
 *
 * 対象 URL はコマンドラインで渡す（このファイルにアダルト URL を埋め込まない）。
 *
 * 実行例:
 *   NP="$HOME/.npm/_npx/<hash>/node_modules"
 *   NODE_PATH="$NP" node measure.js --url "$TARGET_URL" --mode baseline --runs 3
 *   NODE_PATH="$NP" node measure.js --url "$TARGET_URL" --mode protection \
 *       --engine ../../../PopupShieldExtension/Resources/popup-shield.js --runs 3
 */
'use strict';

const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright-core');

const IPHONE_UA =
  'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1';

function parseArgs(argv) {
  const a = { url: null, mode: 'baseline', engine: null, runs: 1, settle: 6000, staticSim: false };
  for (let i = 2; i < argv.length; i++) {
    const k = argv[i];
    if (k === '--url') a.url = argv[++i];
    else if (k === '--mode') a.mode = argv[++i];
    else if (k === '--engine') a.engine = argv[++i];
    else if (k === '--runs') a.runs = parseInt(argv[++i], 10);
    else if (k === '--settle') a.settle = parseInt(argv[++i], 10);
    else if (k === '--static-sim') a.staticSim = true; // 既存 L1+L2 静的ルール相当を network 層で模擬
  }
  return a;
}

// 既存 popunder Content Blocker（L1 既知網 $script + L2 第三者 script 全 block）の効果を
// network 層で模擬するための既知網リスト。静的ルールが本ケースに無効であることの実証用。
const KNOWN_NETWORKS = ['popads.net', 'popadscdn.com', 'popcash.net', 'pemsrv.com', 'adsterratech.com', 'profitabledisplaynetwork.com', 'exoclick.com', 'exosrv.com', 'exdynsrv.com', 'realsrv.com', 'juicyads.com', 'adexchangegate.com', 'jads.co', 'tsyndicate.com', 'ad-delivery.net', 'hilltopads.net', 'hilltopads.com', 'clickadu.com', 'fpctraffic2.com', 'propellerads.com', 'propellerpops.com', 'propu.net', 'ad-maven.com', 'admaven.com', 'onclickads.net', 'onclkds.com', 'serving-sys.com', 'poptm.com', 'popwin.net', 'glssp.net'];
function endsWithAny(h, list) { return list.some((d) => h === d || h.endsWith('.' + d)); }

function host(u) { try { return new URL(u).hostname; } catch { return ''; } }
// 計測用の簡易 eTLD+1（末尾2ラベル）。PSL 非対応（co.uk 等は厳密でない）だが、
// streamtape.com と広告網ドメインの first/third-party 判定には十分。
function etld1(h) { const p = (h || '').split('.'); return p.slice(-2).join('.'); }

// ページ MAIN world に document_start で注入する計装スクリプト。
// 文字列ではなく関数を addInitScript に渡す（Playwright が page.evaluate 同様 MAIN world で実行）。
function instrumentation(siteHost) {
  const SITE_E = (function (h) { const p = h.split('.'); return p.slice(-2).join('.'); })(siteHost.replace(/^www\./, ''));
  const T = {
    windowOpen: [],           // {url, sameSite, thirdPartyStack, gestureBound}
    anchorClick: [],          // {href, target, sameSite, thirdPartyStack}
    gestureListeners: [],     // {type, thirdParty:[hosts], firstPartyOrInline:bool}
    overlays: [],             // {tag, zMax, fullArea, transparent, href, sameSite}
    aboutBlankThenNav: [],    // about:blank を開いた後に別オリジンへ変えた件
    iframeContentOpen: [],    // iframe.contentWindow.open 由来
    earlyOpenCaptured: false, // window.open を別変数に退避した形跡（検知できた場合）
  };
  window.__st = T;

  function _host(u) { try { return new URL(u, location.href).hostname; } catch (e) { return ''; } }
  function _e1(h) { const p = (h || '').split('.'); return p.slice(-2).join('.'); }
  function sameSite(u) {
    const h = _host(u);
    if (!h) return true; // 相対 / about:blank / javascript: は同一サイト扱い
    return _e1(h) === SITE_E;
  }
  function stackHosts() {
    let s = ''; try { s = (new Error()).stack || ''; } catch (e) {}
    const out = new Set();
    (s.match(/https?:\/\/[^\s'")]+/g) || []).forEach(function (u) {
      const h = _host(u); if (h && _e1(h) !== SITE_E) out.add(h);
    });
    return Array.from(out);
  }

  // --- window.open ---
  var realOpen = window.open;
  function wrappedOpen(url, name, feats) {
    var u = url == null ? 'about:blank' : String(url);
    var rec = { url: u, sameSite: sameSite(u), thirdPartyStack: stackHosts() };
    T.windowOpen.push(rec);
    if (typeof window.__decide === 'function') {
      // protection モード: エンジンに委譲。false=ブロック
      var allow = false;
      try { allow = window.__decide('window.open', { url: u, sameSite: rec.sameSite }); } catch (e) { allow = false; }
      if (!allow) return null;
    }
    try { return realOpen.apply(window, arguments); } catch (e) { return null; }
  }
  try {
    Object.defineProperty(window, 'open', { configurable: true, get: function () { return wrappedOpen; }, set: function () { T.earlyOpenCaptured = true; } });
  } catch (e) { window.open = wrappedOpen; }

  // --- HTMLAnchorElement.prototype.click（合成クリック） ---
  var realAClick = HTMLAnchorElement.prototype.click;
  HTMLAnchorElement.prototype.click = function () {
    var href = this.href || ''; var target = this.target || '';
    var rec = { href: String(href), target: String(target), sameSite: sameSite(href), thirdPartyStack: stackHosts() };
    T.anchorClick.push(rec);
    if (typeof window.__decide === 'function') {
      var allow = false;
      try { allow = window.__decide('anchor.click', { url: String(href), target: String(target), sameSite: rec.sameSite }); } catch (e) { allow = false; }
      if (!allow) return;
    }
    return realAClick.apply(this, arguments);
  };

  // --- gesture listener 登録元 ---
  var GEST = { click: 1, mousedown: 1, pointerdown: 1, pointerup: 1, touchstart: 1, touchend: 1, auxclick: 1 };
  var realAdd = EventTarget.prototype.addEventListener;
  EventTarget.prototype.addEventListener = function (type) {
    if (GEST[type]) {
      var tp = stackHosts();
      T.gestureListeners.push({ type: type, thirdParty: tp, firstPartyOrInline: tp.length === 0 });
    }
    return realAdd.apply(this, arguments);
  };

  // --- iframe.contentWindow.open 回避（sacrificial iframe からの popunder） ---
  function hookIframe(ifr) {
    try {
      var cw = ifr.contentWindow; if (!cw) return;
      var ro = cw.open;
      cw.open = function (url) {
        var u = url == null ? 'about:blank' : String(url);
        T.iframeContentOpen.push({ url: u, sameSite: sameSite(u) });
        if (typeof window.__decide === 'function') {
          var allow = false;
          try { allow = window.__decide('iframe.open', { url: u, sameSite: sameSite(u) }); } catch (e) { allow = false; }
          if (!allow) return null;
        }
        try { return ro.apply(cw, arguments); } catch (e) { return null; }
      };
    } catch (e) {}
  }
  var mo = new MutationObserver(function (muts) {
    for (var i = 0; i < muts.length; i++) {
      var added = muts[i].addedNodes || [];
      for (var j = 0; j < added.length; j++) {
        var n = added[j];
        if (!n || n.nodeType !== 1) continue;
        if (n.tagName === 'IFRAME') hookIframe(n);
        // overlay 検知（透明全面 anchor / 高 z-index）
        try {
          var cs = getComputedStyle(n);
          var z = parseInt(cs.zIndex, 10);
          var r = n.getBoundingClientRect ? n.getBoundingClientRect() : { width: 0, height: 0 };
          var fullArea = r.width >= innerWidth * 0.6 && r.height >= innerHeight * 0.6;
          var transparent = cs.opacity === '0' || cs.backgroundColor === 'rgba(0, 0, 0, 0)' || cs.visibility === 'hidden';
          var clickable = n.tagName === 'A' || cs.cursor === 'pointer' || (z && z > 1000);
          if ((fullArea && clickable) || (n.tagName === 'A' && fullArea)) {
            T.overlays.push({ tag: n.tagName, zMax: isNaN(z) ? null : z, fullArea: fullArea, transparent: transparent, href: n.href ? String(n.href) : '', sameSite: n.href ? sameSite(n.href) : true });
          }
        } catch (e) {}
      }
    }
  });
  try { mo.observe(document.documentElement, { childList: true, subtree: true }); } catch (e) {}
}

async function runOnce(url, mode, injectScripts, settle, staticSim) {
  const siteHost = host(url);
  const siteE = etld1(siteHost.replace(/^www\./, ''));
  const browser = await chromium.launch({
    channel: 'chrome', headless: true,
    args: ['--no-sandbox', '--disable-blink-features=AutomationControlled'],
  });
  const result = {
    realPopups: [],            // context.on('page') で実際に生成された popup の target
    currentTabRedirects: [],   // top-frame の cross-site ナビ（abort 済）
    scriptHosts: new Set(),
    mediaRequests: 0,          // プレーヤー生存の証跡（body は DL しない）
    playlistRequests: 0,
    metrics: null,
    error: null,
  };
  try {
    const context = await browser.newContext({
      userAgent: IPHONE_UA, viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true,
      serviceWorkers: 'block',
    });

    // コンテンツ保護: image/media/font は abort（DL しない）。cross-site top-doc も abort。
    await context.route('**/*', (route) => {
      const req = route.request();
      const rt = req.resourceType();
      if (rt === 'image' || rt === 'media' || rt === 'font') return route.abort();
      if (staticSim && rt === 'script') {
        // 静的ルール模擬: L1=既知広告網 script を block / L2=対象サイト上の third-party script を全 block
        const sh = host(req.url());
        const thirdParty = sh && etld1(sh) !== siteE;
        if (endsWithAny(sh, KNOWN_NETWORKS) || thirdParty) { result.staticBlockedScripts = (result.staticBlockedScripts || 0) + 1; return route.abort(); }
      }
      if (rt === 'document' && req.isNavigationRequest()) {
        // top-frame ナビ判定（frame が未生成の早期リクエストでは frame() が throw するので guard）
        let isTop = false;
        try { const f = req.frame(); isTop = !!f && f.parentFrame() === null; } catch (e) { isTop = false; }
        if (isTop) {
          const h = host(req.url());
          if (h && etld1(h) !== etld1(siteHost.replace(/^www\./, '')) && req.url() !== url) {
            // cross-site の現在タブ遷移: 記録してから abort（広告ページを読み込まない）
            result.currentTabRedirects.push(req.url());
            return route.abort();
          }
        }
      }
      return route.continue();
    });

    const page = await context.newPage();
    // popup リスナーは本体 page 作成「後」に登録する（newPage の 'page' イベントを拾って
    // 本体を閉じてしまう事故を回避）。以降に生成される popup のみ対象。
    context.on('page', async (pg) => {
      if (pg === page) return;
      try {
        const u = pg.url();
        result.realPopups.push(u || '(blank)');
        await pg.close();
      } catch (e) {}
    });
    page.on('request', (r) => {
      const rt = r.resourceType();
      if (rt === 'script') { const h = host(r.url()); if (h) result.scriptHosts.add(h); }
      if (rt === 'media') result.mediaRequests++;
      if (/\.m3u8|\.mpd|get_video|\/dl\?|playlist|sources?=|\/v\//.test(r.url()) && (rt === 'xhr' || rt === 'fetch')) result.playlistRequests++;
    });

    if (mode === 'protection') {
      // 出荷する content script（popup-shield-core.js + popup-shield.js）を document_start で注入。
      // これが「エンジンロジックが実 streamtape の popunder を end-to-end で無害化するか」を検証する
      // （フレームカバレッジは Playwright が全フレーム注入＝楽観側。iOS17 のフレーム制約は fixture で別途検証）。
      for (const src of (injectScripts || [])) { await context.addInitScript(src); }
    } else {
      await context.addInitScript(instrumentation, siteHost);
    }

    try { await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 45000 }); }
    catch (e) { result.error = 'goto: ' + e.message; }
    await page.waitForTimeout(settle);

    // 10 操作シナリオ（プレーヤー領域中心の固定座標）。受入条件: 各ロード10操作。
    const W = 390, H = 844;
    const ops = [
      [W * 0.5, H * 0.32], [W * 0.5, H * 0.32], [W * 0.5, H * 0.40],  // 中央(偽 play overlay)
      [W * 0.5, H * 0.55], [W * 0.2, H * 0.40], [W * 0.8, H * 0.40],  // 下/左/右
      [W * 0.5, H * 0.25], [W * 0.5, H * 0.45], [W * 0.5, H * 0.32],  // 上端/中段/中央
      [W * 0.5, H * 0.60],                                            // プレーヤー下
    ];
    for (const [x, y] of ops) {
      try { await page.mouse.click(Math.round(x), Math.round(y)); } catch (e) {}
      await page.waitForTimeout(900);
    }
    await page.waitForTimeout(1500);

    // プレーヤー生存(DOM)を main frame から回収
    const dom = await page.evaluate(() => {
      const video = !!document.querySelector('video');
      const playerEl = !!document.querySelector('video, [class*="player" i], [id*="player" i], .plyr, .jwplayer, .video-js, .fp-player');
      const videoSrc = (function () { const v = document.querySelector('video'); return v ? !!(v.src || v.currentSrc || v.querySelector('source')) : false; })();
      return { video, playerEl, videoSrc };
    }).catch((e) => ({ video: false, playerEl: false, videoSrc: false, evalError: e.message }));

    // 計装結果(__st)は popunder が同一オリジンの about:blank ヘルパーフレームで発火するため
    // 全フレームを走査してマージする（main frame だけだと過小カウントになる＝diagnose.js で判明）。
    const merged = { windowOpen: [], anchorClick: [], gestureListeners: [], overlays: [], aboutBlankThenNav: [], iframeContentOpen: [], earlyOpenCaptured: false };
    for (const f of page.frames()) {
      try {
        const t = await f.evaluate(() => window.__st || null);
        if (!t) continue;
        merged.windowOpen.push(...(t.windowOpen || []));
        merged.anchorClick.push(...(t.anchorClick || []));
        merged.gestureListeners.push(...(t.gestureListeners || []));
        merged.overlays.push(...(t.overlays || []));
        merged.iframeContentOpen.push(...(t.iframeContentOpen || []));
        if (t.earlyOpenCaptured) merged.earlyOpenCaptured = true;
      } catch (e) { /* cross-origin frame.evaluate は失敗しうる（その frame の __st は読めない） */ }
    }
    dom.T = merged;
    result.metrics = dom;
  } finally {
    await browser.close();
  }
  result.scriptHosts = Array.from(result.scriptHosts);
  return result;
}

function classifyVectors(agg) {
  // 観測から A–F 経路を推定する補助（人間の最終判断材料）。
  const v = [];
  const t = agg;
  if (t.knownNetworksLoaded.length) v.push('A: 安定第三者広告ドメインの script (' + t.knownNetworksLoaded.join(',') + ')');
  if (t.rotatingGestureOrigins.length) v.push('B: 回転ドメインの gesture listener (' + t.rotatingGestureOrigins.slice(0, 5).join(',') + (t.rotatingGestureOrigins.length > 5 ? ',…' : '') + ')');
  if (t.firstPartyOrInlineGesture > 0 || t.firstPartyWindowOpen > 0) v.push('C: first-party/inline の window.open/redirect');
  if (t.overlays > 0) v.push('D: 透明 anchor/overlay クリック乗っ取り');
  if (t.aboutBlankOpens > 0) v.push('E: about:blank/iframe 経由遅延 popunder');
  if (v.length > 1) v.push('F: 複合');
  return v;
}

async function main() {
  const a = parseArgs(process.argv);
  if (!a.url) { console.error('usage: node measure.js --url <URL> [--mode baseline|protection] [--engine path] [--runs N]'); process.exit(2); }
  let injectScripts = null;
  if (a.mode === 'protection') {
    if (!a.engine) { console.error('protection モードは --engine <popup-shield.js> が必須（core は同ディレクトリの popup-shield-core.js を自動使用）'); process.exit(2); }
    const hookPath = path.resolve(a.engine);
    const corePath = path.join(path.dirname(hookPath), 'popup-shield-core.js');
    injectScripts = [fs.readFileSync(corePath, 'utf8'), fs.readFileSync(hookPath, 'utf8')];
  }
  const KNOWN = ['popads.net', 'popadscdn.com', 'popcash.net', 'pemsrv.com', 'adsterratech.com', 'profitabledisplaynetwork.com', 'exoclick.com', 'exosrv.com', 'exdynsrv.com', 'realsrv.com', 'juicyads.com', 'adexchangegate.com', 'jads.co', 'tsyndicate.com', 'ad-delivery.net', 'hilltopads.net', 'hilltopads.com', 'clickadu.com', 'fpctraffic2.com', 'propellerads.com', 'propellerpops.com', 'propu.net', 'ad-maven.com', 'admaven.com', 'onclickads.net', 'onclkds.com', 'serving-sys.com', 'poptm.com', 'popwin.net', 'glssp.net'];
  const endsAny = (h, list) => list.some((d) => h === d || h.endsWith('.' + d));

  const runs = [];
  for (let i = 0; i < a.runs; i++) {
    process.stderr.write(`run ${i + 1}/${a.runs} (${a.mode}${a.staticSim ? '+static-sim' : ''})...\n`);
    runs.push(await runOnce(a.url, a.mode, injectScripts, a.settle, a.staticSim));
  }

  // 集計
  const siteHost = host(a.url);
  const SITE_E = etld1(siteHost.replace(/^www\./, ''));
  const agg = {
    mode: a.mode, runs: a.runs, target_etld1: SITE_E,
    realPopups_total: 0, realPopups_crossSite: 0,
    currentTabRedirects_total: 0,
    windowOpen_total: 0, windowOpen_crossSite: 0, firstPartyWindowOpen: 0,
    anchorClick_total: 0, anchorClick_crossSite: 0,
    iframeOpen_total: 0,
    aboutBlankOpens: 0,
    overlays: 0,
    knownNetworksLoaded: new Set(),
    thirdPartyScriptHosts: new Set(),
    rotatingGestureOrigins: new Set(),
    firstPartyOrInlineGesture: 0,
    player_alive_runs: 0, media_request_runs: 0,
    perRun: [],
  };
  for (const r of runs) {
    const T = (r.metrics && r.metrics.T) || {};
    const wo = T.windowOpen || [], ac = T.anchorClick || [], gl = T.gestureListeners || [], ov = T.overlays || [], ifo = T.iframeContentOpen || [];
    agg.realPopups_total += r.realPopups.length;
    agg.realPopups_crossSite += r.realPopups.filter((u) => { const h = host(u); return h && etld1(h) !== SITE_E; }).length;
    agg.currentTabRedirects_total += r.currentTabRedirects.length;
    agg.windowOpen_total += wo.length;
    agg.windowOpen_crossSite += wo.filter((x) => !x.sameSite).length;
    agg.firstPartyWindowOpen += wo.filter((x) => x.thirdPartyStack.length === 0).length;
    agg.anchorClick_total += ac.length;
    agg.anchorClick_crossSite += ac.filter((x) => !x.sameSite).length;
    agg.iframeOpen_total += ifo.length;
    agg.aboutBlankOpens += wo.filter((x) => /^about:blank/.test(x.url)).length + ifo.filter((x) => /^about:blank/.test(x.url)).length;
    agg.overlays += ov.length;
    (r.scriptHosts || []).forEach((h) => { if (endsAny(h, KNOWN)) agg.knownNetworksLoaded.add(h); if (etld1(h) !== SITE_E) agg.thirdPartyScriptHosts.add(h); });
    gl.forEach((g) => { if (!g.firstPartyOrInline) g.thirdParty.forEach((h) => { if (!endsAny(h, KNOWN)) agg.rotatingGestureOrigins.add(h); }); else agg.firstPartyOrInlineGesture++; });
    if (r.metrics && (r.metrics.playerEl || r.metrics.video)) agg.player_alive_runs++;
    if (r.mediaRequests > 0 || r.playlistRequests > 0) agg.media_request_runs++;
    agg.perRun.push({
      realPopups: r.realPopups.length, currentTabRedirects: r.currentTabRedirects.length,
      windowOpen: wo.length, windowOpen_crossSite: wo.filter((x) => !x.sameSite).length,
      anchorClick: ac.length, iframeOpen: ifo.length, overlays: ov.length,
      mediaReq: r.mediaRequests, playlistReq: r.playlistRequests,
      staticBlockedScripts: r.staticBlockedScripts || 0,
      player_alive: !!(r.metrics && (r.metrics.playerEl || r.metrics.video)),
      error: r.error || null,
    });
  }
  agg.knownNetworksLoaded = Array.from(agg.knownNetworksLoaded);
  agg.thirdPartyScriptHosts = Array.from(agg.thirdPartyScriptHosts).sort();
  agg.rotatingGestureOrigins = Array.from(agg.rotatingGestureOrigins);
  agg.classification = classifyVectors(agg);

  console.log(JSON.stringify(agg, null, 2));
}

main().catch((e) => { console.error('FATAL', e.stack || e.message); process.exit(1); });

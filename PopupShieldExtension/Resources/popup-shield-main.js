/*
 * popup-shield-main.js — 強力モードのページ計装（MAIN world content script）。
 *
 * 責務（ページ側 API への介入のみ）:
 *   window.open のラップ / anchor.click 検査 / overlay anchor 検査 / same-origin frame への hook 伝播 /
 *   判定エンジン実行 / ブロック実行 / 稼働開始(ready)イベント発行 / ブロック発生(blocked)イベント発行。
 *
 * 禁止（このファイルに存在してはならない）: browser.* / chrome.* / storage.* / runtime.sendMessage /
 *   Extension 固有 API / URL・ページ内容の永続化。
 *   → Extension API との橋渡しは ISOLATED world の popup-shield-bridge.js が担当する。
 *   → MAIN world では content script 専用 Extension API が使えないため（本 PR の最重要修正）、
 *     件数報告は window への CustomEvent（最小情報・URL なし）で bridge に渡す。
 *
 * iOS 17 対応: streamtape の popunder は同一オリジン about:blank ヘルパーフレームの window.open から
 *   発火する。iOS 17 は page 生成 about:blank に content script を注入しない（match_origin_as_fallback は
 *   18.4+）ため、親フレームから同一オリジン子フレームへ override を伝播（traversal + MutationObserver）する。
 */
(function () {
  'use strict';
  if (window.__popupShieldInstalled) return;
  window.__popupShieldInstalled = true;

  var Core = window.PopupShieldCore;
  if (!Core || !Core.makeDecider) return; // core 未ロードなら何もしない（安全側）

  // bridge と一致させること（popup-shield-bridge.js の EVENT_NAME と同一文字列）。
  var EVENT_NAME = '__popupShieldMsg';

  function topHost() {
    try { return (window.top && window.top.location && window.top.location.hostname) || window.location.hostname; }
    catch (e) { return window.location.hostname; }
  }
  function topHref() {
    try { return (window.top && window.top.location && window.top.location.href) || window.location.href; }
    catch (e) { return window.location.href; }
  }
  // base を渡して相対/protocol-relative URL を正しく解決する（cross-site 判定の取りこぼし防止）。
  var decide = Core.makeDecider(topHost(), { base: topHref() });
  var frameLabel = (window.top === window) ? 'top' : 'child';

  // ISOLATED world bridge への一方向通知（最小情報のみ・URL/ページ内容は載せない）。
  function emit(type, reason) {
    try {
      var detail = { version: 1, type: type, frame: frameLabel };
      if (reason) detail.reason = reason;
      window.dispatchEvent(new CustomEvent(EVENT_NAME, { detail: detail }));
    } catch (e) {}
  }

  // 1 ユーザージェスチャ = 1 id。capture 段で trusted 入力を検出して採番する。
  var currentGesture = 0;
  ['pointerdown', 'mousedown', 'touchstart', 'click', 'auxclick'].forEach(function (type) {
    try {
      window.addEventListener(type, function (e) {
        if (e && e.isTrusted) {
          currentGesture++;
          // ジェスチャ開始時に同一オリジン子フレームを再走査して override を仕込み直す
          // （直前に動的生成された iframe からの popunder の取りこぼし=race を緩和）。capture 段なので
          //  ページのクリックハンドラ（= popunder 発火）より前に走る。
          try { traverseFrames(window); } catch (er) {}
        }
      }, true);
    } catch (e) {}
  });

  function report(kind, d, meta) {
    // テスト観測用シーム（URL・PII 無し: kind/action/reason と boolean メタのみ）。
    try {
      if (window.__popupShieldTest && window.__popupShieldTest.onDecision) {
        var o = { kind: kind, action: d.action, reason: d.reason };
        if (meta) { if (meta.crossSite !== undefined) o.crossSite = meta.crossSite; if (meta.overlay !== undefined) o.overlay = meta.overlay; }
        window.__popupShieldTest.onDecision(o);
      }
    } catch (e) {}
    if (d.action === 'block' || d.action === 'stub') {
      try { var s = (window.top.__popupShield = window.top.__popupShield || { count: 0 }); s.count++; } catch (e) {}
      emit('blocked', d.reason); // Extension API は使わず bridge に委譲
    }
  }

  // 非 throw な about:blank スタブ窓（遅延型 popunder=vector E を無害化）。
  function makeStub() {
    var loc = { _href: '', assign: function () {}, replace: function () {}, reload: function () {} };
    Object.defineProperty(loc, 'href', { get: function () { return loc._href; }, set: function () { /* 遷移させない（href 書き換えを一律無視＝遅延 popunder 無害化） */ } });
    var doc = { write: function () {}, writeln: function () {}, close: function () {}, open: function () { return doc; },
      createElement: function () { return {}; }, getElementById: function () { return null; }, body: null, documentElement: null };
    return { __popupShieldStub: true, closed: false, location: loc, document: doc,
      focus: function () {}, blur: function () {}, close: function () { this.closed = true; },
      open: function () { return null; }, postMessage: function () {}, addEventListener: function () {}, removeEventListener: function () {} };
  }

  // 任意の同一オリジン window に window.open override を仕込む（idempotent）。
  function installOpen(win) {
    try {
      if (!win || win.__popupShieldOpenHooked) return;
      var real = win.open;
      var wrapped = function (url, name, feats) {
        var d = decide('window.open', { url: url, gestureId: currentGesture });
        report('window.open', d, { crossSite: !decide.sameSite(url == null ? 'about:blank' : url) });
        if (d.action === 'block') return null;
        if (d.action === 'stub') return makeStub();
        try { return real.apply(win, arguments); } catch (e) { return null; }
      };
      try {
        // setter を握り潰し、サイトが window.open = fn で popunder を再インストールするのを防ぐ（意図的）。
        Object.defineProperty(win, 'open', { configurable: true, get: function () { return wrapped; }, set: function () {} });
      } catch (e) { win.open = wrapped; }
      win.__popupShieldOpenHooked = true;
    } catch (e) { /* cross-origin window はアクセス不可（カバー対象外）= 既知の限界 */ }
  }

  // 同一オリジン子フレームを走査して override を伝播（iOS 17 の about:blank 非注入を補う）。
  function traverseFrames(rootWin) {
    try {
      var frames = rootWin.frames;
      for (var i = 0; i < frames.length; i++) {
        var cw = null;
        try { cw = frames[i]; void cw.location.href; } catch (e) { cw = null; } // cross-origin は読めない→skip
        if (cw) { installOpen(cw); traverseFrames(cw); }
      }
    } catch (e) {}
  }

  // 合成 anchor.click()（cross-site）を止める。
  try {
    var realAClick = HTMLAnchorElement.prototype.click;
    HTMLAnchorElement.prototype.click = function () {
      var d = decide('anchor.click', { url: this.href, gestureId: currentGesture });
      report('anchor.click', d, { crossSite: !decide.sameSite(this.href) });
      if (d.action === 'block') return;
      return realAClick.apply(this, arguments);
    };
  } catch (e) {}

  // native target=_blank（透明全面 overlay の乗っ取り）を capture 段で止める。
  function isOverlayAnchor(a) {
    // overlay の特徴: (1) 実質不可視（opacity:0 / visibility:hidden）、または
    // (2) 「読めるテキストもアイコンも無い」リンクが一定面積を覆う。
    // 背景色 transparent だけでは判定しない（正規の大型カードリンクを誤ブロックしないため）。
    try {
      var cs = getComputedStyle(a);
      var r = a.getBoundingClientRect();
      var vw = window.innerWidth || 390, vh = window.innerHeight || 844;
      var invisible = cs.opacity === '0' || cs.visibility === 'hidden';
      var noVisibleContent = (a.textContent || '').trim() === '' && !a.querySelector('img,svg,picture,video,canvas');
      var coversArea = (r.width * r.height) >= (vw * vh * 0.12);
      return invisible || (noVisibleContent && coversArea);
    } catch (e) { return false; }
  }
  function onClickCapture(e) {
    try {
      var path = e.composedPath ? e.composedPath() : [];
      var a = null;
      for (var i = 0; i < path.length; i++) { if (path[i] && path[i].tagName === 'A') { a = path[i]; break; } }
      if (!a || !a.href) return;
      var blankish = a.target === '_blank' || a.target === '_new';
      if (!blankish) return; // 通常の self ナビ（#含む）は対象外＝壊さない
      var overlay = isOverlayAnchor(a);
      var d = decide('native-anchor', { url: a.href, overlay: overlay, gestureId: currentGesture });
      report('native-anchor', d, { crossSite: !decide.sameSite(a.href), overlay: overlay });
      if (d.action === 'block') { e.preventDefault(); e.stopImmediatePropagation(); }
    } catch (er) {}
  }
  try {
    window.addEventListener('click', onClickCapture, true);
    window.addEventListener('auxclick', onClickCapture, true);
  } catch (e) {}

  // インストール: 自フレーム + 同一オリジン子フレーム伝播。
  installOpen(window);
  traverseFrames(window);
  try {
    var mo = new MutationObserver(function () { traverseFrames(window); });
    mo.observe(document.documentElement || document, { childList: true, subtree: true });
  } catch (e) {}
  [0, 200, 800, 2000].forEach(function (t) { try { setTimeout(function () { traverseFrames(window); }, t); } catch (e) {} });

  window.__popupShield = window.__popupShield || { count: 0 };
  emit('ready'); // 稼働開始を bridge → background へ通知（active 判定の根拠）
})();

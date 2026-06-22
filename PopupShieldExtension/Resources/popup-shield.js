/*
 * popup-shield.js — 強力モードのページ計装（MAIN world content script）。
 *
 * 役割: ページの window.open / 合成 anchor.click / native target=_blank / 同一オリジン子フレームの
 *   window.open を計装し、popup-shield-core.js の判定で「cross-site のプログラム的遷移」だけを止める。
 *   正規の動画再生・同一オリジンナビ・ユーザーが選んだリンクは壊さない。
 *
 * iOS 17 対応の要点（tasks/streamtape-hardening/baseline.md・design.md）:
 *   - streamtape の popunder は同一オリジン about:blank ヘルパーフレームの window.open から発火する。
 *     iOS 17 は page 生成 about:blank に content script を注入しない（match_origin_as_fallback は 18.4+）ため、
 *     親フレームから同一オリジン子フレームへ override を伝播（traversal + MutationObserver）する。
 *   - 出荷時は scripting.registerContentScripts({world:"MAIN", allFrames:true, runAt:"document_start"}) で注入。
 *
 * プライバシー: ネットワーク送信なし。ログは件数・分類（reason）のみ（URL/ページ内容は保存しない）。
 */
(function () {
  'use strict';
  if (window.__popupShieldInstalled) return;
  window.__popupShieldInstalled = true;

  var Core = window.PopupShieldCore;
  if (!Core || !Core.makeDecider) return; // core 未ロードなら何もしない（安全側）

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
    // テスト観測用シーム。送る情報は kind/action/reason と boolean メタ（crossSite/overlay）のみ＝URL・PII 無し。
    try {
      if (window.__popupShieldTest && window.__popupShieldTest.onDecision) {
        var o = { kind: kind, action: d.action, reason: d.reason };
        if (meta) { if (meta.crossSite !== undefined) o.crossSite = meta.crossSite; if (meta.overlay !== undefined) o.overlay = meta.overlay; }
        window.__popupShieldTest.onDecision(o);
      }
    } catch (e) {}
    if (d.action === 'block' || d.action === 'stub') {
      try { var s = (window.top.__popupShield = window.top.__popupShield || { count: 0 }); s.count++; } catch (e) {}
      try {
        var b = (typeof browser !== 'undefined') ? browser : (typeof chrome !== 'undefined' ? chrome : null);
        if (b && b.runtime && b.runtime.sendMessage) b.runtime.sendMessage({ type: 'popupShieldBlock', reason: d.reason });
      } catch (e) {}
    }
  }

  // 非 throw な about:blank スタブ窓（遅延型 popunder=vector E を無害化）。
  // 正規の `var w=open('about:blank'); w.document.write(...)` が例外を投げず劣化するように最低限の API を備える。
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
    // クリック乗っ取り overlay の特徴: (1) 実質不可視（opacity:0 / visibility:hidden）、または
    // (2) 「読めるテキストもアイコンも無い」リンクが一定面積を覆う。
    // ※ 背景色が transparent なだけでは判定しない（正規の大型カードリンクは背景透明＋可視テキストが普通で、
    //   それを overlay 扱いするとユーザーが選んだ cross-site リンクを誤ブロックする＝Codex MEDIUM 指摘）。
    try {
      var cs = getComputedStyle(a);
      var r = a.getBoundingClientRect();
      var vw = window.innerWidth || 390, vh = window.innerHeight || 844;
      var invisible = cs.opacity === '0' || cs.visibility === 'hidden';
      var noVisibleContent = (a.textContent || '').trim() === '' && !a.querySelector('img,svg,picture,video,canvas');
      var coversArea = (r.width * r.height) >= (vw * vh * 0.12); // 画面の 12% 以上を覆う
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
  // 動的に追加される iframe / フレーム navigation を追う（settle 後の生成も拾う）。
  try {
    var mo = new MutationObserver(function () { traverseFrames(window); });
    mo.observe(document.documentElement || document, { childList: true, subtree: true });
  } catch (e) {}
  // 念のため数回 re-scan（about:blank 子フレームの生成タイミング差を吸収）。
  [0, 200, 800, 2000].forEach(function (t) { try { setTimeout(function () { traverseFrames(window); }, t); } catch (e) {} });

  window.__popupShield = window.__popupShield || { count: 0 };
})();

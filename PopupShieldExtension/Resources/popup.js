/*
 * popup.js — 強力モードの設定 UI（master トグル + サイト別一時停止 + 件数表示）。
 * 状態は storage.local に保存し、background.js が変更を検知して登録/解除を行う。
 * プライバシー: 表示するのは件数のみ。URL・ページ内容は保存も表示もしない。
 */
'use strict';
(function () {
  var b = (typeof browser !== 'undefined') ? browser : chrome;
  var enabledEl = document.getElementById('enabled');
  var pausedEl = document.getElementById('paused');
  var siteHostEl = document.getElementById('siteHost');
  var siteRow = document.getElementById('siteRow');
  var countNumEl = document.getElementById('countNum');

  function currentHostKey(url) {
    // registrable ドメインに正規化（cdn.streamtape.com → streamtape.com）。
    // background の照合（match パターン `*://*.streamtape.com/*` への部分一致）と一貫させ、
    // サブドメインからの一時停止が無言で効かない問題を防ぐ。
    try {
      var h = new URL(url).hostname;
      if (typeof PopupShieldCore !== 'undefined' && PopupShieldCore.registrable) return PopupShieldCore.registrable(h);
      return h.replace(/^www\./, '');
    } catch (e) { return ''; }
  }

  function totalCounts(counts) {
    var n = 0;
    Object.keys(counts || {}).forEach(function (day) {
      Object.keys(counts[day] || {}).forEach(function (r) { n += counts[day][r] || 0; });
    });
    return n;
  }

  var hostKey = '';

  function render(state) {
    enabledEl.checked = !!state.enabled;
    var paused = Array.isArray(state.pausedHosts) ? state.pausedHosts : [];
    pausedEl.checked = hostKey ? paused.indexOf(hostKey) !== -1 : false;
    siteHostEl.textContent = hostKey || '対象サイト外';
    siteRow.className = (state.enabled && hostKey) ? 'row' : 'row disabled';
    countNumEl.textContent = String(totalCounts(state.counts));
  }

  function load() {
    return b.storage.local.get(['enabled', 'pausedHosts', 'counts']).then(function (s) {
      return { enabled: !!s.enabled, pausedHosts: Array.isArray(s.pausedHosts) ? s.pausedHosts : [], counts: s.counts || {} };
    });
  }

  enabledEl.addEventListener('change', function () {
    b.storage.local.set({ enabled: enabledEl.checked }).then(function () { load().then(render); });
  });

  pausedEl.addEventListener('change', function () {
    if (!hostKey) return;
    load().then(function (state) {
      var paused = state.pausedHosts.slice();
      var i = paused.indexOf(hostKey);
      if (pausedEl.checked && i === -1) paused.push(hostKey);
      if (!pausedEl.checked && i !== -1) paused.splice(i, 1);
      b.storage.local.set({ pausedHosts: paused }).then(function () { load().then(render); });
    });
  });

  // 現在タブのホストを取得（tabs 権限が無い環境でも query は host_permissions 範囲で返る）。
  function init() {
    var p = (b.tabs && b.tabs.query) ? b.tabs.query({ active: true, currentWindow: true }) : Promise.resolve([]);
    Promise.resolve(p).then(function (tabs) {
      if (tabs && tabs[0] && tabs[0].url) hostKey = currentHostKey(tabs[0].url);
      return load();
    }).then(render).catch(function () { load().then(render); });
  }
  init();
})();

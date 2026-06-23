/*
 * popup.js — 強力モードの設定 UI（master トグル + 実稼働状態表示 + 再試行 + サイト別一時停止 + 診断）。
 * 状態は storage.local に保存し、background.js が変更を検知して登録/解除する。
 * プライバシー: 表示・保存するのは件数・分類・状態・対象 host・paused のみ。URL/ページ内容/履歴は扱わない。
 */
'use strict';
(function () {
  var b = (typeof browser !== 'undefined') ? browser : chrome;
  var enabledEl = document.getElementById('enabled');
  var pausedEl = document.getElementById('paused');
  var siteHostEl = document.getElementById('siteHost');
  var siteRow = document.getElementById('siteRow');
  var countNumEl = document.getElementById('countNum');
  var statusDot = document.getElementById('statusDot');
  var statusLabel = document.getElementById('statusLabel');
  var retryBtn = document.getElementById('retry');
  var diagEl = document.getElementById('diag');

  // background.deriveUiStatus と同じ規則（トグル ON だけでは active にしない）。
  function uiStatus(s) {
    if (!s.desiredEnabled) return 'off';
    var rs = s.registrationState;
    if (rs === 'unsupported') return 'unsupported';
    if (rs === 'failed') return 'failed';
    if (rs === 'active') return 'active';
    if (rs === 'registered') return s.lastReadyAt ? 'active' : 'registered';
    if (rs === 'registering') return 'registering';
    return 'registering';
  }
  var LABEL = {
    off: { t: '強力モード: オフ', dot: 'off', retry: false },
    registering: { t: '登録中…', dot: 'warn', retry: false },
    registered: { t: '有効（対象ページで動作確認待ち）', dot: 'warn', retry: false },
    active: { t: '有効・対象ページで動作確認済み', dot: 'active', retry: false },
    unsupported: { t: 'この端末では利用できません', dot: 'err', retry: true },
    failed: { t: '登録に失敗しました', dot: 'err', retry: true }
  };
  var ERR_HINT = {
    permission_missing: 'Safari で対象サイトの権限を確認してください',
    main_world_unsupported: 'この iOS では強力モードに非対応です',
    api_unavailable: 'この iOS では強力モードに非対応です'
  };

  function currentHostKey(url) {
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
  function reasonBreakdown(counts) {
    var agg = {};
    Object.keys(counts || {}).forEach(function (day) {
      Object.keys(counts[day] || {}).forEach(function (r) { agg[r] = (agg[r] || 0) + counts[day][r]; });
    });
    return agg;
  }

  var hostKey = '';

  function load() {
    return b.storage.local.get(['desiredEnabled', 'pausedHosts', 'registrationState', 'lastRegistrationError', 'lastReadyAt', 'registeredMatches', 'counts']).then(function (s) {
      return {
        desiredEnabled: !!s.desiredEnabled,
        pausedHosts: Array.isArray(s.pausedHosts) ? s.pausedHosts : [],
        registrationState: s.registrationState || 'off',
        lastRegistrationError: s.lastRegistrationError || null,
        lastReadyAt: s.lastReadyAt || null,
        registeredMatches: Array.isArray(s.registeredMatches) ? s.registeredMatches : [],
        counts: s.counts || {}
      };
    });
  }

  function render(s) {
    enabledEl.checked = s.desiredEnabled;
    var paused = s.pausedHosts;
    pausedEl.checked = hostKey ? paused.indexOf(hostKey) !== -1 : false;
    siteHostEl.textContent = hostKey || '対象サイト外';
    siteRow.className = (s.desiredEnabled && hostKey) ? 'row' : 'row disabled';
    countNumEl.textContent = String(totalCounts(s.counts));

    var st = uiStatus(s);
    var meta = LABEL[st] || LABEL.off;
    var label = meta.t;
    if ((st === 'failed' || st === 'unsupported') && s.lastRegistrationError && ERR_HINT[s.lastRegistrationError]) {
      label += '（' + ERR_HINT[s.lastRegistrationError] + '）';
    }
    statusLabel.textContent = label;
    statusDot.className = 'dot ' + meta.dot;
    retryBtn.style.display = meta.retry ? 'inline-block' : 'none';

    // 診断（プライバシー安全: 件数/分類/状態/host/paused のみ・URL なし）
    var br = reasonBreakdown(s.counts);
    var lines = [
      'registrationState: ' + s.registrationState,
      'desiredEnabled: ' + s.desiredEnabled,
      'lastReadyAt: ' + (s.lastReadyAt ? new Date(s.lastReadyAt).toISOString() : '(none)'),
      'lastRegistrationError: ' + (s.lastRegistrationError || '(none)'),
      'registeredMatches: ' + (s.registeredMatches.join(', ') || '(none)'),
      'pausedHosts: ' + (paused.join(', ') || '(none)'),
      'blocked total: ' + totalCounts(s.counts)
    ];
    Object.keys(br).forEach(function (r) { lines.push('  ' + r + ': ' + br[r]); });
    diagEl.textContent = lines.join('\n');
  }

  enabledEl.addEventListener('change', function () {
    b.storage.local.set({ desiredEnabled: enabledEl.checked }).then(function () { load().then(render); });
  });
  pausedEl.addEventListener('change', function () {
    if (!hostKey) return;
    load().then(function (s) {
      var paused = s.pausedHosts.slice();
      var i = paused.indexOf(hostKey);
      if (pausedEl.checked && i === -1) paused.push(hostKey);
      if (!pausedEl.checked && i !== -1) paused.splice(i, 1);
      b.storage.local.set({ pausedHosts: paused }).then(function () { load().then(render); });
    });
  });
  retryBtn.addEventListener('click', function () {
    try { if (b.runtime && b.runtime.sendMessage) b.runtime.sendMessage({ type: 'popupShieldRetry' }); } catch (e) {}
    setTimeout(function () { load().then(render); }, 400);
  });

  function init() {
    var p = (b.tabs && b.tabs.query) ? b.tabs.query({ active: true, currentWindow: true }) : Promise.resolve([]);
    Promise.resolve(p).then(function (tabs) {
      if (tabs && tabs[0] && tabs[0].url) hostKey = currentHostKey(tabs[0].url);
      return load();
    }).then(render).catch(function () { load().then(render); });
  }
  init();
})();

/*
 * background.js — 強力モードの登録管理（Safari Web Extension MV3 service worker）。
 *
 * 役割:
 *   - storage.local の { enabled, pausedHosts } に応じて popup-shield content script を
 *     scripting.registerContentScripts({world:"MAIN"}) で登録/解除する。
 *   - 既定 OFF（enabled=false）= 何も登録しない＝ページに一切干渉しない（プライバシー最小）。
 *   - content script からの件数報告（type:'popupShieldBlock'）を storage に集計（件数・分類のみ／URL 無し）。
 *
 * 設計: 判定ロジック（どの matches を登録するか）は純関数 popupShieldPlan に切り出し、node でテストする。
 */
'use strict';

// 対象（強力モードで実測済みのサイトのみ。<all_urls> は要求しない＝最小権限）。
// v1 は streamtape.com のみ（baseline→protection を実測で検証したサイト）。他サイトは
// 実測してから追加する（manifest host_permissions と必ず一致させること）。
var TARGET_HOSTS = ['*://*.streamtape.com/*'];
var SCRIPT_ID = 'popup-shield';

/**
 * 登録計画を返す純関数。enabled=false なら何も登録しない。
 * pausedHosts に含まれるホストを matches から除外する（サイト単位の一時停止）。
 * @returns {{register:boolean, matches:string[]}}
 */
function popupShieldPlan(state, targets) {
  var enabled = !!(state && state.enabled);
  var paused = (state && Array.isArray(state.pausedHosts)) ? state.pausedHosts : [];
  if (!enabled) return { register: false, matches: [] };
  var matches = targets.filter(function (m) {
    return !paused.some(function (h) { return h && m.indexOf(h) !== -1; });
  });
  return { register: matches.length > 0, matches: matches };
}

// ---- 以下はブラウザ環境でのみ動く配線（node テストでは未定義なので分離）----
if (typeof module !== 'undefined' && module.exports) {
  module.exports = { popupShieldPlan: popupShieldPlan, TARGET_HOSTS: TARGET_HOSTS, SCRIPT_ID: SCRIPT_ID };
}

(function () {
  var b = (typeof browser !== 'undefined') ? browser : (typeof chrome !== 'undefined' ? chrome : null);
  if (!b || !b.storage || !b.scripting) return; // node / 非対応環境では何もしない

  function getState() {
    return b.storage.local.get(['enabled', 'pausedHosts', 'counts']).then(function (s) {
      return { enabled: !!s.enabled, pausedHosts: Array.isArray(s.pausedHosts) ? s.pausedHosts : [], counts: s.counts || {} };
    });
  }

  function reconcile() {
    return getState().then(function (state) {
      var plan = popupShieldPlan(state, TARGET_HOSTS);
      return Promise.resolve()
        .then(function () { return b.scripting.unregisterContentScripts({ ids: [SCRIPT_ID] }).catch(function () {}); })
        .then(function () {
          if (!plan.register) return; // OFF or 全 pause = 登録しない
          return b.scripting.registerContentScripts([{
            id: SCRIPT_ID,
            js: ['popup-shield-core.js', 'popup-shield.js'],
            matches: plan.matches,
            runAt: 'document_start',
            allFrames: true,
            world: 'MAIN'
          }]).catch(function (e) { /* world:MAIN 非対応環境では失敗しうる（提出前の実機確認事項） */ });
        });
    });
  }

  if (b.runtime && b.runtime.onInstalled) b.runtime.onInstalled.addListener(reconcile);
  if (b.runtime && b.runtime.onStartup) b.runtime.onStartup.addListener(reconcile);
  if (b.storage && b.storage.onChanged) {
    b.storage.onChanged.addListener(function (changes, area) {
      if (area === 'local' && (changes.enabled || changes.pausedHosts)) reconcile();
    });
  }

  // 件数のみ集計（URL・ページ内容は保存しない）。日付ごとに reason 別カウント。
  if (b.runtime && b.runtime.onMessage) {
    b.runtime.onMessage.addListener(function (msg) {
      if (!msg || msg.type !== 'popupShieldBlock' || !msg.reason) return;
      getState().then(function (state) {
        var counts = state.counts || {};
        var day = new Date().toISOString().slice(0, 10);
        counts[day] = counts[day] || {};
        counts[day][msg.reason] = (counts[day][msg.reason] || 0) + 1;
        b.storage.local.set({ counts: counts });
      });
    });
  }

  reconcile();
})();

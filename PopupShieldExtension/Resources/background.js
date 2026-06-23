/*
 * background.js — 強力モードの登録管理（Safari Web Extension MV3 service worker）。
 *
 * Phase 3/4 の要点:
 *   - MAIN world(popup-shield-main.js)と ISOLATED bridge(popup-shield-bridge.js)を「別 ID」で登録する。
 *   - 「desiredEnabled（ユーザー設定）」と「実際の稼働状態（registrationState）」を区別する。
 *   - 登録失敗を握りつぶさない。ただし保存するのは正規化したエラー分類のみ（URL・ページ情報・OS 機密は保存しない）。
 *   - bridge からの ready で 'active' に遷移（対象ページで MAIN world が実際に動いた証跡）。
 *   - 件数のみ集計（URL/内容/履歴は保存も送信もしない）。
 *
 * 判定ロジック（plan / error 分類 / UI status 導出）は純関数に切り出し node でテストする。
 */
'use strict';

// 強力モードで実測済みのサイトのみ（<all_urls> は要求しない＝最小権限）。manifest host_permissions と一致必須。
var TARGET_HOSTS = ['*://*.streamtape.com/*'];
var ID_MAIN = 'popup-shield-main';
var ID_BRIDGE = 'popup-shield-bridge';
var LEGACY_IDS = ['popup-shield']; // 旧単一 ID（cleanup 対象）

var STATE = { OFF: 'off', REGISTERING: 'registering', REGISTERED: 'registered', ACTIVE: 'active', UNSUPPORTED: 'unsupported', FAILED: 'failed' };
var ERR = { API_UNAVAILABLE: 'api_unavailable', MAIN_WORLD_UNSUPPORTED: 'main_world_unsupported', REGISTRATION_REJECTED: 'registration_rejected', PERMISSION_MISSING: 'permission_missing', UNKNOWN: 'unknown_registration_error' };

/** 登録計画（純関数）。enabled=false なら何も登録しない。pausedHosts を matches から除外。 */
function popupShieldPlan(state, targets) {
  var enabled = !!(state && state.desiredEnabled);
  var paused = (state && Array.isArray(state.pausedHosts)) ? state.pausedHosts : [];
  if (!enabled) return { register: false, matches: [] };
  var matches = targets.filter(function (m) {
    return !paused.some(function (h) { return h && m.indexOf(h) !== -1; });
  });
  return { register: matches.length > 0, matches: matches };
}

/** registerContentScripts に渡す 2 つの descriptor（別 ID・MAIN と ISOLATED）。 */
function buildRegistrations(matches) {
  return [
    { id: ID_MAIN, js: ['popup-shield-core.js', 'popup-shield-main.js'], matches: matches, runAt: 'document_start', allFrames: true, world: 'MAIN' },
    { id: ID_BRIDGE, js: ['popup-shield-bridge.js'], matches: matches, runAt: 'document_start', allFrames: true, world: 'ISOLATED' }
  ];
}

/** 登録エラーを正規化分類（純関数）。元の文言は保存しない。 */
function classifyRegistrationError(err) {
  var msg = '';
  try { msg = (err && (err.message || err.toString())) || ''; } catch (e) { msg = ''; }
  msg = String(msg).toLowerCase();
  if (/world|main world|isolated/.test(msg)) return ERR.MAIN_WORLD_UNSUPPORTED;
  if (/permission|host_permission|not allowed|denied/.test(msg)) return ERR.PERMISSION_MISSING;
  if (/not a function|undefined is not|no such|unavailable|not supported on/.test(msg)) return ERR.API_UNAVAILABLE;
  if (/invalid|reject|duplicate|already|argument|schema/.test(msg)) return ERR.REGISTRATION_REJECTED;
  return ERR.UNKNOWN;
}

/** storage 状態 → UI ステータスキー（純関数）。トグル ON だけでは active にしない。 */
function deriveUiStatus(state) {
  if (!state || !state.desiredEnabled) return STATE.OFF;
  var rs = state.registrationState;
  if (rs === STATE.UNSUPPORTED) return STATE.UNSUPPORTED;
  if (rs === STATE.FAILED) return STATE.FAILED;
  if (rs === STATE.ACTIVE) return STATE.ACTIVE;
  if (rs === STATE.REGISTERED) return state.lastReadyAt ? STATE.ACTIVE : STATE.REGISTERED;
  if (rs === STATE.REGISTERING) return STATE.REGISTERING;
  return STATE.REGISTERING;
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = {
    popupShieldPlan: popupShieldPlan, buildRegistrations: buildRegistrations,
    classifyRegistrationError: classifyRegistrationError, deriveUiStatus: deriveUiStatus,
    TARGET_HOSTS: TARGET_HOSTS, STATE: STATE, ERR: ERR, ID_MAIN: ID_MAIN, ID_BRIDGE: ID_BRIDGE, LEGACY_IDS: LEGACY_IDS
  };
}

// ---- ブラウザ環境でのみ動く配線（node テストでは未定義なので分離）----
(function () {
  var b = (typeof browser !== 'undefined') ? browser : (typeof chrome !== 'undefined' ? chrome : null);
  if (!b || !b.storage) return;

  function now() { try { return Date.now(); } catch (e) { return 0; } }
  function getState() {
    return b.storage.local.get(['desiredEnabled', 'pausedHosts', 'registrationState', 'lastRegistrationError', 'lastRegistrationAttemptAt', 'lastReadyAt', 'registeredMatches', 'counts']).then(function (s) {
      return {
        desiredEnabled: !!s.desiredEnabled,
        pausedHosts: Array.isArray(s.pausedHosts) ? s.pausedHosts : [],
        registrationState: s.registrationState || STATE.OFF,
        lastRegistrationError: s.lastRegistrationError || null,
        lastRegistrationAttemptAt: s.lastRegistrationAttemptAt || null,
        lastReadyAt: s.lastReadyAt || null,
        registeredMatches: Array.isArray(s.registeredMatches) ? s.registeredMatches : [],
        counts: s.counts || {}
      };
    });
  }
  function patch(obj) { return b.storage.local.set(obj); }

  function unregisterAll() {
    if (!b.scripting || !b.scripting.unregisterContentScripts) return Promise.resolve();
    var ids = [ID_MAIN, ID_BRIDGE].concat(LEGACY_IDS);
    // 個別 unregister（存在しない ID で全体失敗しないように 1 件ずつ）
    return Promise.all(ids.map(function (id) {
      return b.scripting.unregisterContentScripts({ ids: [id] }).catch(function () {});
    }));
  }

  function reconcile() {
    return getState().then(function (state) {
      var plan = popupShieldPlan(state, TARGET_HOSTS);
      // API 非対応の早期判定
      if (!b.scripting || !b.scripting.registerContentScripts) {
        return patch({ registrationState: state.desiredEnabled ? STATE.UNSUPPORTED : STATE.OFF, lastRegistrationError: state.desiredEnabled ? ERR.API_UNAVAILABLE : null, registeredMatches: [], lastRegistrationAttemptAt: now() });
      }
      return patch({ registrationState: plan.register ? STATE.REGISTERING : STATE.OFF, lastRegistrationAttemptAt: now() })
        .then(unregisterAll)
        .then(function () {
          if (!plan.register) {
            return patch({ registrationState: STATE.OFF, registeredMatches: [], lastRegistrationError: null });
          }
          return b.scripting.registerContentScripts(buildRegistrations(plan.matches))
            .then(function () {
              // 登録成功（API 受理）。ready 受信までは registered（active ではない）。
              return patch({ registrationState: STATE.REGISTERED, registeredMatches: plan.matches, lastRegistrationError: null });
            })
            .catch(function (err) {
              var cls = classifyRegistrationError(err); // 元文言は保存しない
              var st = (cls === ERR.MAIN_WORLD_UNSUPPORTED || cls === ERR.API_UNAVAILABLE) ? STATE.UNSUPPORTED : STATE.FAILED;
              return patch({ registrationState: st, lastRegistrationError: cls, registeredMatches: [] });
            });
        });
    });
  }

  if (b.runtime && b.runtime.onInstalled) b.runtime.onInstalled.addListener(reconcile);
  if (b.runtime && b.runtime.onStartup) b.runtime.onStartup.addListener(reconcile);
  if (b.storage && b.storage.onChanged) {
    b.storage.onChanged.addListener(function (changes, area) {
      if (area === 'local' && (changes.desiredEnabled || changes.pausedHosts)) reconcile();
    });
  }

  if (b.runtime && b.runtime.onMessage) {
    b.runtime.onMessage.addListener(function (msg) {
      if (!msg || msg.version !== 1) {
        // popup からの retry 要求（version なし）も受ける
        if (msg && msg.type === 'popupShieldRetry') reconcile();
        return;
      }
      if (msg.type === 'popupShieldReady') {
        // 対象ページで MAIN world が実際に動いた → active へ昇格（registered 以上のときのみ）。
        getState().then(function (s) {
          if (s.desiredEnabled && (s.registrationState === STATE.REGISTERED || s.registrationState === STATE.ACTIVE)) {
            patch({ lastReadyAt: now(), registrationState: STATE.ACTIVE });
          } else {
            patch({ lastReadyAt: now() });
          }
        });
      } else if (msg.type === 'popupShieldBlock' && msg.reason) {
        getState().then(function (s) {
          var counts = s.counts || {};
          var day = new Date().toISOString().slice(0, 10);
          counts[day] = counts[day] || {};
          counts[day][msg.reason] = (counts[day][msg.reason] || 0) + 1;
          patch({ counts: counts });
        });
      }
    });
  }

  reconcile();
})();

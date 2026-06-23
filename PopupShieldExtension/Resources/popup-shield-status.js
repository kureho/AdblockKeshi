/*
 * popup-shield-status.js — storage 状態 → UI ステータスキーの導出（純関数・依存なし）。
 *
 * popup.js が利用する。MAIN world content script には含めない（UI 導出ロジックを
 * 判定エンジン core に混ぜない＝責務分離・全ページへの不要注入を避ける）。
 * background.js も同等のロジックを持つが、両者の一致は node テストでロックして drift を防ぐ
 * （SW の importScripts 実機リスクを避けるため、単一ファイル共有ではなくテスト固定とする）。
 */
(function (root) {
  'use strict';
  // トグル ON だけでは active にしない（実稼働状態を区別する）。background.deriveUiStatus と一致必須。
  function deriveUiStatus(state) {
    if (!state || !state.desiredEnabled) return 'off';
    var rs = state.registrationState;
    if (rs === 'unsupported') return 'unsupported';
    if (rs === 'failed') return 'failed';
    if (rs === 'active') return 'active';
    if (rs === 'registered') return state.lastReadyAt ? 'active' : 'registered';
    if (rs === 'registering') return 'registering';
    return 'registering';
  }
  var api = { deriveUiStatus: deriveUiStatus };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  if (root) root.PopupShieldStatus = api;
})(typeof window !== 'undefined' ? window : (typeof globalThis !== 'undefined' ? globalThis : null));

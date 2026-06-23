/*
 * popup-shield-bridge.js — ISOLATED world content script（Extension API への橋渡し専用）。
 *
 * 責務: MAIN world（popup-shield-main.js）が window に dispatch する最小イベントを受信し、
 *   厳格に検証してから background へ health/件数を report する。
 *
 * セキュリティ方針（Phase 2）:
 *   - 受理するのは固定 event 名・version:1・許可済み type/reason のみ。余分な property は破棄。
 *   - URL・ページタイトル・DOM・本文は一切受理しない（schema に存在しない）。
 *   - 受信イベントから権限操作や任意コマンドは実行しない（最大の影響は端末内件数の増加のみ）。
 *   - forged event 対策にレート制限を入れる。
 *   - イベントは一方向（MAIN → ISOLATED）。bridge から MAIN へは送らない。
 */
'use strict';

// MAIN world と一致させること（popup-shield-main.js の EVENT_NAME と同一文字列）。
var EVENT_NAME = '__popupShieldMsg';
var ALLOWED_TYPES = { ready: 1, blocked: 1 };
var ALLOWED_REASONS = {
  xsite_window_open: 1,
  xsite_synthetic_anchor: 1,
  overlay_anchor_hijack: 1,
  about_blank_deferred: 1,
  multi_nav_one_gesture: 1
};
var ALLOWED_FRAMES = { top: 1, child: 1 };

// 純関数: 受信 detail を厳格検証してサニタイズ。許可外は null。余分 property は載せない。
function parseShieldEvent(detail) {
  if (!detail || typeof detail !== 'object') return null;
  if (detail.version !== 1) return null;
  if (typeof detail.type !== 'string' || !Object.prototype.hasOwnProperty.call(ALLOWED_TYPES, detail.type)) return null;
  var out = { version: 1, type: detail.type };
  if (detail.type === 'blocked') {
    if (typeof detail.reason !== 'string' || !Object.prototype.hasOwnProperty.call(ALLOWED_REASONS, detail.reason)) return null;
    out.reason = detail.reason;
  }
  out.frame = (typeof detail.frame === 'string' && Object.prototype.hasOwnProperty.call(ALLOWED_FRAMES, detail.frame)) ? detail.frame : 'top';
  return out;
}

// 固定ウィンドウのレート制限（now を注入してテスト可能に）。
function makeRateLimiter(maxPerWindow, windowMs) {
  var times = [];
  return function (now) {
    times = times.filter(function (t) { return now - t < windowMs; });
    if (times.length >= maxPerWindow) return false;
    times.push(now);
    return true;
  };
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = { parseShieldEvent: parseShieldEvent, makeRateLimiter: makeRateLimiter, EVENT_NAME: EVENT_NAME, ALLOWED_REASONS: ALLOWED_REASONS };
}

// ---- ISOLATED world 配線（node テストでは window 未定義のためスキップ）----
(function () {
  if (typeof window === 'undefined') return;
  var b = (typeof browser !== 'undefined') ? browser : (typeof chrome !== 'undefined' ? chrome : null);
  if (window.__popupShieldBridgeInstalled) return;
  window.__popupShieldBridgeInstalled = true;

  var limiter = makeRateLimiter(60, 1000); // 60 件/秒 上限（forged flood 抑止）
  function now() { try { return Date.now(); } catch (e) { return 0; } }

  window.addEventListener(EVENT_NAME, function (e) {
    try {
      if (e.target !== window) return;          // window 上の event のみ受理（source===window 相当）
      var msg = parseShieldEvent(e.detail);     // 厳格検証（URL 等は構造的に受理不可）
      if (!msg) return;
      if (!limiter(now())) return;              // レート制限
      if (!b || !b.runtime || !b.runtime.sendMessage) return;
      if (msg.type === 'ready') {
        b.runtime.sendMessage({ type: 'popupShieldReady', frame: msg.frame, version: 1 });
      } else {
        b.runtime.sendMessage({ type: 'popupShieldBlock', reason: msg.reason, frame: msg.frame, version: 1 });
      }
    } catch (err) { /* 受信処理は失敗しても無害（権限操作は一切行わない） */ }
  }, false);
})();

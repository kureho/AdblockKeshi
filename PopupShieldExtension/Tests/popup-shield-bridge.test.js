'use strict';
/*
 * popup-shield-bridge.test.js — ISOLATED world bridge の検証・レート制限テスト（node --test）。
 * bridge は MAIN world からの最小イベントだけを受理し、URL・ページ内容は一切受け取らない。
 * forged event でも「件数が増える」以上の影響を与えないことを担保する。
 */
const test = require('node:test');
const assert = require('node:assert');
const { parseShieldEvent, makeRateLimiter, ALLOWED_REASONS } = require('../Resources/popup-shield-bridge.js');

test('正当な ready イベントを受理（最小情報のみ）', () => {
  assert.deepStrictEqual(parseShieldEvent({ version: 1, type: 'ready', frame: 'top' }), { version: 1, type: 'ready', frame: 'top' });
});

test('正当な blocked イベントを受理', () => {
  assert.deepStrictEqual(
    parseShieldEvent({ version: 1, type: 'blocked', reason: 'xsite_window_open', frame: 'child' }),
    { version: 1, type: 'blocked', reason: 'xsite_window_open', frame: 'child' }
  );
});

test('URL/ページ内容など余分な property は破棄する', () => {
  const out = parseShieldEvent({ version: 1, type: 'blocked', reason: 'xsite_window_open', frame: 'top', url: 'https://evil/x', title: 'secret', dom: '<b>' });
  assert.deepStrictEqual(out, { version: 1, type: 'blocked', reason: 'xsite_window_open', frame: 'top' });
  assert.ok(!('url' in out) && !('title' in out) && !('dom' in out));
});

test('不正な type は破棄（null）', () => {
  assert.strictEqual(parseShieldEvent({ version: 1, type: 'exec', reason: 'xsite_window_open' }), null);
  assert.strictEqual(parseShieldEvent({ version: 1, type: '__proto__' }), null);
});

test('許可外の reason は破棄（null）', () => {
  assert.strictEqual(parseShieldEvent({ version: 1, type: 'blocked', reason: 'run_command' }), null);
  assert.strictEqual(parseShieldEvent({ version: 1, type: 'blocked' }), null); // reason 欠落
});

test('version 不一致は破棄', () => {
  assert.strictEqual(parseShieldEvent({ version: 2, type: 'ready' }), null);
  assert.strictEqual(parseShieldEvent({ type: 'ready' }), null);
});

test('detail が object でない/null は破棄', () => {
  assert.strictEqual(parseShieldEvent(null), null);
  assert.strictEqual(parseShieldEvent('ready'), null);
  assert.strictEqual(parseShieldEvent(undefined), null);
});

test('不正な frame は top にフォールバック（任意値を流さない）', () => {
  assert.strictEqual(parseShieldEvent({ version: 1, type: 'ready', frame: 'evil' }).frame, 'top');
});

test('許可 reason 一覧は判定エンジンの reason と一致', () => {
  ['xsite_window_open', 'xsite_synthetic_anchor', 'overlay_anchor_hijack', 'about_blank_deferred', 'multi_nav_one_gesture']
    .forEach((r) => assert.ok(ALLOWED_REASONS[r], r + ' が許可一覧に無い'));
});

test('レート制限: ウィンドウ内 max 件まで・超過は false', () => {
  const limiter = makeRateLimiter(3, 1000);
  assert.strictEqual(limiter(0), true);
  assert.strictEqual(limiter(0), true);
  assert.strictEqual(limiter(0), true);
  assert.strictEqual(limiter(0), false); // 4 件目はドロップ
  assert.strictEqual(limiter(1001), true); // ウィンドウ経過で回復
});

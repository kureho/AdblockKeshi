'use strict';
/*
 * background-health.test.js — 登録状態管理・エラー分類・UI status 導出のテスト（node --test）。
 * 「トグル ON」と「実際に稼働中」を区別すること、登録失敗を握りつぶさず分類すること、を担保する。
 */
const test = require('node:test');
const assert = require('node:assert');
const { buildRegistrations, classifyRegistrationError, deriveUiStatus, STATE, ERR, ID_MAIN, ID_BRIDGE } = require('../Resources/background.js');

test('buildRegistrations: MAIN と ISOLATED を別 ID で生成', () => {
  const regs = buildRegistrations(['*://*.streamtape.com/*']);
  assert.strictEqual(regs.length, 2);
  const main = regs.find((r) => r.id === ID_MAIN);
  const bridge = regs.find((r) => r.id === ID_BRIDGE);
  assert.strictEqual(main.world, 'MAIN');
  assert.deepStrictEqual(main.js, ['popup-shield-core.js', 'popup-shield-main.js']);
  assert.strictEqual(main.runAt, 'document_start');
  assert.strictEqual(main.allFrames, true);
  assert.strictEqual(bridge.world, 'ISOLATED');
  assert.deepStrictEqual(bridge.js, ['popup-shield-bridge.js']);
});

test('classifyRegistrationError: world MAIN 非対応', () => {
  assert.strictEqual(classifyRegistrationError(new Error('world MAIN is not supported')), ERR.MAIN_WORLD_UNSUPPORTED);
});
test('classifyRegistrationError: API 非対応', () => {
  assert.strictEqual(classifyRegistrationError(new TypeError('registerContentScripts is not a function')), ERR.API_UNAVAILABLE);
});
test('classifyRegistrationError: 権限欠如', () => {
  assert.strictEqual(classifyRegistrationError(new Error('host permission denied')), ERR.PERMISSION_MISSING);
});
test('classifyRegistrationError: 登録拒否', () => {
  assert.strictEqual(classifyRegistrationError(new Error('Invalid argument: duplicate id')), ERR.REGISTRATION_REJECTED);
});
test('classifyRegistrationError: 不明', () => {
  assert.strictEqual(classifyRegistrationError(new Error('weird kernel panic')), ERR.UNKNOWN);
  assert.strictEqual(classifyRegistrationError(null), ERR.UNKNOWN);
});
test('classifyRegistrationError: 元文言を返さない（分類のみ）', () => {
  const cls = classifyRegistrationError(new Error('secret path /Users/foo and url https://x'));
  assert.ok(Object.values(ERR).includes(cls));
  assert.ok(!/Users|https/.test(cls));
});

test('deriveUiStatus: OFF（トグル ON だけでは active にしない）', () => {
  assert.strictEqual(deriveUiStatus({ desiredEnabled: false, registrationState: STATE.ACTIVE }), STATE.OFF);
});
test('deriveUiStatus: registering', () => {
  assert.strictEqual(deriveUiStatus({ desiredEnabled: true, registrationState: STATE.REGISTERING }), STATE.REGISTERING);
});
test('deriveUiStatus: registered（API 受理済みだが ready 未確認）は active にしない', () => {
  assert.strictEqual(deriveUiStatus({ desiredEnabled: true, registrationState: STATE.REGISTERED, lastReadyAt: null }), STATE.REGISTERED);
});
test('deriveUiStatus: registered + ready 受信で active', () => {
  assert.strictEqual(deriveUiStatus({ desiredEnabled: true, registrationState: STATE.REGISTERED, lastReadyAt: 123 }), STATE.ACTIVE);
});
test('deriveUiStatus: failed / unsupported はそのまま表示', () => {
  assert.strictEqual(deriveUiStatus({ desiredEnabled: true, registrationState: STATE.FAILED }), STATE.FAILED);
  assert.strictEqual(deriveUiStatus({ desiredEnabled: true, registrationState: STATE.UNSUPPORTED }), STATE.UNSUPPORTED);
});

'use strict';
/* background.js の登録計画 純関数 popupShieldPlan のテスト（node --test）。 */
const test = require('node:test');
const assert = require('node:assert');
const { popupShieldPlan, TARGET_HOSTS } = require('../Resources/background.js');

// 多ホストの登録ロジックは明示配列で検証（出荷スコープと独立）。
const MULTI = ['*://*.streamtape.com/*', '*://*.tokyomotion.net/*'];

test('desiredEnabled=false なら何も登録しない（既定 OFF・プライバシー最小）', () => {
  const plan = popupShieldPlan({ desiredEnabled: false, pausedHosts: [] }, MULTI);
  assert.strictEqual(plan.register, false);
  assert.deepStrictEqual(plan.matches, []);
});

test('desiredEnabled=true なら全対象を登録', () => {
  const plan = popupShieldPlan({ desiredEnabled: true, pausedHosts: [] }, MULTI);
  assert.strictEqual(plan.register, true);
  assert.deepStrictEqual(plan.matches, MULTI);
});

test('pausedHosts のサイトは matches から除外（サイト単位の一時停止）', () => {
  const plan = popupShieldPlan({ desiredEnabled: true, pausedHosts: ['streamtape.com'] }, MULTI);
  assert.strictEqual(plan.register, true);
  assert.ok(plan.matches.every((m) => m.indexOf('streamtape.com') === -1));
  assert.ok(plan.matches.some((m) => m.indexOf('tokyomotion.net') !== -1));
});

test('全サイト pause なら register=false', () => {
  const plan = popupShieldPlan({ desiredEnabled: true, pausedHosts: ['streamtape.com', 'tokyomotion.net'] }, MULTI);
  assert.strictEqual(plan.register, false);
  assert.deepStrictEqual(plan.matches, []);
});

test('state 不正でも落ちない（堅牢）', () => {
  assert.strictEqual(popupShieldPlan(null, MULTI).register, false);
  assert.strictEqual(popupShieldPlan({ desiredEnabled: true, pausedHosts: null }, MULTI).register, true);
});

test('出荷 TARGET_HOSTS は実測済み streamtape.com のみ（過剰権限を作らない）', () => {
  assert.deepStrictEqual(TARGET_HOSTS, ['*://*.streamtape.com/*']);
});

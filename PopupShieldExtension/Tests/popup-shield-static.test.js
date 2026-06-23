'use strict';
/*
 * popup-shield-static.test.js — MAIN world ファイルに Extension API が混入していないことを保証する。
 * （本 PR 最重要修正: MAIN world では content script 専用 Extension API が使えないため、混入は無言失敗になる）
 */
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');

const RES = path.resolve(__dirname, '../Resources');
const MAIN_WORLD_FILES = ['popup-shield-core.js', 'popup-shield-main.js'];
const FORBIDDEN = [/browser\.runtime/, /chrome\.runtime/, /browser\.storage/, /chrome\.storage/, /sendMessage\s*\(/];

for (const f of MAIN_WORLD_FILES) {
  test(`MAIN world ファイル ${f} に Extension API が無い`, () => {
    const src = fs.readFileSync(path.join(RES, f), 'utf8');
    for (const re of FORBIDDEN) {
      assert.ok(!re.test(src), `${f} に禁止パターン ${re} が含まれている`);
    }
  });
}

test('bridge(ISOLATED) は runtime.sendMessage を持つ（責務分離の裏取り）', () => {
  const src = fs.readFileSync(path.join(RES, 'popup-shield-bridge.js'), 'utf8');
  assert.ok(/runtime\.sendMessage/.test(src), 'bridge が Extension API 通信を担っていない');
});

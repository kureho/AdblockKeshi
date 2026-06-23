'use strict';
/*
 * popup-shield-display-name.test.js
 * PopupShield のポップアップ UI 表示名が新名称「遷移保護」に統一され、
 * user-visible resource に旧名称「強力ポップアップ対策」が残っていないこと、
 * manifest/locales の新名称（広告消し — 遷移保護 / 遷移保護）を壊していないことを保証する。
 * 命名統一（2026-06-23〜24）の取りこぼし再発防止。
 */
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');

const RES = path.resolve(__dirname, '../Resources');
const OLD_NAME = '強力ポップアップ対策';

test('popup.html の <title> が新名称「遷移保護」', () => {
  const html = fs.readFileSync(path.join(RES, 'popup.html'), 'utf8');
  assert.match(html, /<title>\s*遷移保護\s*<\/title>/, 'popup <title> が「遷移保護」でない');
});

test('popup.html の <h1> が新名称「遷移保護」', () => {
  const html = fs.readFileSync(path.join(RES, 'popup.html'), 'utf8');
  assert.match(html, /<h1>\s*遷移保護\s*<\/h1>/, 'popup <h1> が「遷移保護」でない');
});

test('Web Extension の user-visible resource に旧名称が残っていない', () => {
  const files = ['popup.html', 'popup.js', 'manifest.json', '_locales/ja/messages.json'];
  for (const f of files) {
    const src = fs.readFileSync(path.join(RES, f), 'utf8');
    assert.ok(!src.includes(OLD_NAME), `${f} に旧名称「${OLD_NAME}」が残っている`);
  }
});

test('locales の新名称を壊していない（extName / actionTitle）', () => {
  const msg = JSON.parse(fs.readFileSync(path.join(RES, '_locales/ja/messages.json'), 'utf8'));
  assert.strictEqual(msg.extName.message, '広告消し — 遷移保護');
  assert.strictEqual(msg.actionTitle.message, '遷移保護');
});

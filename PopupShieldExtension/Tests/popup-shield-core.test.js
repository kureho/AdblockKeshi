'use strict';
/*
 * popup-shield-core.test.js — 強力モード判定エンジンの仕様テスト（node --test で実行）。
 *
 * 仕様の根拠: tasks/streamtape-hardening/baseline.md の実測。
 *   - streamtape の popunder = first-party の window.open が cross-site 回転ドメインへ新規タブ → BLOCK 必須
 *   - 同一サイトのナビ・ユーザーが選んだリンク・正規 media は壊さない（プレーヤー生存＝受入条件 6/7）
 */
const test = require('node:test');
const assert = require('node:assert');
const { makeDecider, registrable, ACTION, REASON } = require('../Resources/popup-shield-core.js');

const SITE = 'streamtape.com';

test('registrable: 単純ドメイン', () => {
  assert.strictEqual(registrable('streamtape.com'), 'streamtape.com');
  assert.strictEqual(registrable('www.streamtape.com'), 'streamtape.com');
  assert.strictEqual(registrable('my.zoruftuiov.com'), 'zoruftuiov.com');
});

test('registrable: 多段 public suffix', () => {
  assert.strictEqual(registrable('a.example.co.uk'), 'example.co.uk');
  assert.strictEqual(registrable('example.co.uk'), 'example.co.uk');
  assert.strictEqual(registrable('foo.bar.co.jp'), 'bar.co.jp');
});

test('registrable: 空・末尾ドット', () => {
  assert.strictEqual(registrable(''), '');
  assert.strictEqual(registrable('streamtape.com.'), 'streamtape.com');
});

test('window.open cross-site は BLOCK（streamtape popunder の決定的ケース）', () => {
  const decide = makeDecider(SITE);
  const r = decide('window.open', { url: 'https://my.zoruftuiov.com/abc?zone=1', gestureId: 1 });
  assert.strictEqual(r.action, ACTION.BLOCK);
  assert.strictEqual(r.reason, REASON.XSITE_WINDOW_OPEN);
});

test('window.open same-site は ALLOW（サイト本体ナビを壊さない）', () => {
  const decide = makeDecider(SITE);
  const r = decide('window.open', { url: 'https://streamtape.com/login', gestureId: 1 });
  assert.strictEqual(r.action, ACTION.ALLOW);
});

test('window.open subdomain は same-site 扱いで ALLOW', () => {
  const decide = makeDecider(SITE);
  const r = decide('window.open', { url: 'https://cdn.streamtape.com/x.js', gestureId: 1 });
  assert.strictEqual(r.action, ACTION.ALLOW);
});

test('window.open about:blank は STUB（遅延型 popunder=vector E 対策・実窓を作らせない）', () => {
  const decide = makeDecider(SITE);
  assert.strictEqual(decide('window.open', { url: 'about:blank', gestureId: 1 }).action, ACTION.STUB);
  assert.strictEqual(decide('window.open', { url: '', gestureId: 1 }).action, ACTION.STUB);
  assert.strictEqual(decide('window.open', { url: null, gestureId: 1 }).action, ACTION.STUB);
});

test('window.open javascript: は ALLOW（ナビゲーション popup ではない）', () => {
  const decide = makeDecider(SITE);
  assert.strictEqual(decide('window.open', { url: 'javascript:void(0)', gestureId: 1 }).action, ACTION.ALLOW);
});

test('window.open 相対 URL は same-site 扱いで ALLOW', () => {
  const decide = makeDecider(SITE);
  assert.strictEqual(decide('window.open', { url: '/watch/123', gestureId: 1 }).action, ACTION.ALLOW);
});

test('iframe.open cross-site も BLOCK（同一オリジン about:blank ヘルパー由来）', () => {
  const decide = makeDecider(SITE);
  const r = decide('iframe.open', { url: 'https://zeloru.com/x', gestureId: 1 });
  assert.strictEqual(r.action, ACTION.BLOCK);
});

test('anchor.click 合成クリック cross-site は BLOCK', () => {
  const decide = makeDecider(SITE);
  const r = decide('anchor.click', { url: 'https://ad.example.org/x' });
  assert.strictEqual(r.action, ACTION.BLOCK);
  assert.strictEqual(r.reason, REASON.XSITE_SYNTHETIC_ANCHOR);
});

test('anchor.click 合成クリック same-site は ALLOW', () => {
  const decide = makeDecider(SITE);
  assert.strictEqual(decide('anchor.click', { url: 'https://streamtape.com/next' }).action, ACTION.ALLOW);
});

test('native-anchor cross-site + overlay は BLOCK（透明全面 anchor 乗っ取り=vector D）', () => {
  const decide = makeDecider(SITE);
  const r = decide('native-anchor', { url: 'https://ad.example.org/x', overlay: true });
  assert.strictEqual(r.action, ACTION.BLOCK);
  assert.strictEqual(r.reason, REASON.OVERLAY_ANCHOR_HIJACK);
});

test('native-anchor cross-site だが通常リンク（非overlay）は ALLOW（正規リンクを壊さない）', () => {
  const decide = makeDecider(SITE);
  assert.strictEqual(decide('native-anchor', { url: 'https://twitter.com/share', overlay: false }).action, ACTION.ALLOW);
});

test('native-anchor same-site は ALLOW', () => {
  const decide = makeDecider(SITE);
  assert.strictEqual(decide('native-anchor', { url: 'https://streamtape.com/p', overlay: true }).action, ACTION.ALLOW);
});

test('1 ジェスチャ複数遷移: gestureId 指定時は 2 件目以降 same-site open を BLOCK', () => {
  const decide = makeDecider(SITE);
  assert.strictEqual(decide('window.open', { url: 'https://streamtape.com/a', gestureId: 5 }).action, ACTION.ALLOW);
  assert.strictEqual(decide('window.open', { url: 'https://streamtape.com/b', gestureId: 5 }).action, ACTION.BLOCK);
  // 次のジェスチャ（id 変化）でリセット
  assert.strictEqual(decide('window.open', { url: 'https://streamtape.com/c', gestureId: 6 }).action, ACTION.ALLOW);
});

test('gestureId 未指定時は same-site open を恒久ブロックしない（silent-failure 回避・advisor point 5）', () => {
  const decide = makeDecider(SITE);
  for (let i = 0; i < 5; i++) {
    assert.strictEqual(decide('window.open', { url: 'https://streamtape.com/x' + i }).action, ACTION.ALLOW, 'call ' + i);
  }
});

test('protocol-relative cross-site (//evil) は base 無しでも BLOCK（Codex HIGH 回避）', () => {
  const decide = makeDecider(SITE); // base を渡さない＝フックがうっかり省いた場合でも守る
  assert.strictEqual(decide('window.open', { url: '//evil-ad.test/pop', gestureId: 1 }).action, ACTION.BLOCK);
});

test('protocol-relative same-site (//cdn.self) は ALLOW', () => {
  const decide = makeDecider(SITE);
  assert.strictEqual(decide('window.open', { url: '//cdn.streamtape.com/a.js', gestureId: 1 }).action, ACTION.ALLOW);
});

test('base を渡した相対パスの解決も cross-site を BLOCK', () => {
  const decide = makeDecider(SITE, { base: 'https://streamtape.com/v/x' });
  assert.strictEqual(decide('window.open', { url: '//evil-ad.test/x', gestureId: 1 }).action, ACTION.BLOCK);
});

test('未知 kind は ALLOW（予期せぬ呼び出しで壊さない）', () => {
  const decide = makeDecider(SITE);
  assert.strictEqual(decide('something-else', { url: 'https://x.com' }).action, ACTION.ALLOW);
});

test('cross-site 判定は registrable 単位（www. ありの自サイトは same-site）', () => {
  const decide = makeDecider('www.streamtape.com');
  assert.strictEqual(decide.siteRegistrable, 'streamtape.com');
  assert.strictEqual(decide('window.open', { url: 'https://streamtape.com/a', gestureId: 1 }).action, ACTION.ALLOW);
  assert.strictEqual(decide('window.open', { url: 'https://evil.com/a', gestureId: 1 }).action, ACTION.BLOCK);
});

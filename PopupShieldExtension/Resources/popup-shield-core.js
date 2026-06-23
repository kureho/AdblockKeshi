/*
 * popup-shield-core.js — 強力モード（Safari Web Extension）の判定エンジン（純関数・依存なし）。
 *
 * 設計根拠: tasks/streamtape-hardening/baseline.md（streamtape 実測）。
 *   主因 = サイト本体の first-party inline `window.open` がクリック契機で cross-site の
 *   回転広告ドメイン（zoruftuiov.com 等）へ新規タブを開く（tabunder）。静的 Content Blocker
 *   では原理的に止められない。MAIN-world で window.open を介入する以外に実効手段が無い。
 *
 * 判定の主信号 = 「クロスサイトのプログラム的遷移」。タップ位置は使わない（プレーヤー保護のため）。
 *   - 正規の動画再生・同一オリジン media/API・ユーザーが選んだリンクは壊さない。
 *   - cross-site の programmatic window.open / 合成 anchor.click / 全面透明 anchor の乗っ取りだけを止める。
 *
 * このファイルは window（ブラウザ MAIN world）と Node（テスト）の両方で読める形にしてある。
 * 出荷時は popup-shield.js（ページ計装）がこの makeDecider を使う。
 */
(function (root) {
  'use strict';

  // 代表的な多段 public suffix（最小サブセット）。registrable domain 判定の精度向上用。
  // 完全な PSL ではない（稀な多段 TLD は last-2-labels にフォールバック）= 既知の限界。
  var MULTI_SUFFIX = {
    'co.uk': 1, 'org.uk': 1, 'gov.uk': 1, 'ac.uk': 1, 'me.uk': 1,
    'co.jp': 1, 'or.jp': 1, 'ne.jp': 1, 'ac.jp': 1, 'go.jp': 1, 'com.jp': 1,
    'com.au': 1, 'net.au': 1, 'org.au': 1, 'com.br': 1, 'com.cn': 1, 'com.tw': 1,
    'co.kr': 1, 'co.in': 1, 'co.nz': 1, 'com.mx': 1, 'com.tr': 1, 'co.za': 1,
    'com.hk': 1, 'com.sg': 1, 'com.ru': 1, 'com.ua': 1
  };

  function registrable(hostname) {
    if (!hostname) return '';
    var parts = String(hostname).toLowerCase().replace(/\.$/, '').split('.').filter(Boolean);
    if (parts.length <= 2) return parts.join('.');
    var last2 = parts.slice(-2).join('.');
    if (MULTI_SUFFIX[last2]) return parts.slice(-3).join('.');
    return last2;
  }

  function parseHost(url, base) {
    try {
      var u = String(url);
      // protocol-relative（//host/...）は base 無しだと new URL が throw し「同一サイト扱い」に
      // フォールバックして cross-site popunder を見逃す（Codex HIGH）。明示スキームで必ず解決する。
      if (/^\/\//.test(u)) u = 'https:' + u;
      return new URL(u, base || undefined).hostname;
    } catch (e) { return ''; }
  }

  // 判定アクション: allow=素通り / block=実窓を作らせない(null)・遷移を止める / stub=安全スタブ窓を返す
  var ACTION = { ALLOW: 'allow', BLOCK: 'block', STUB: 'stub' };
  // 理由コード（端末内ログの分類用。URL・ページ内容は一切含めない）
  var REASON = {
    ALLOW: 'allow',
    XSITE_WINDOW_OPEN: 'xsite_window_open',
    XSITE_SYNTHETIC_ANCHOR: 'xsite_synthetic_anchor',
    OVERLAY_ANCHOR_HIJACK: 'overlay_anchor_hijack',
    ABOUT_BLANK_DEFERRED: 'about_blank_deferred',
    MULTI_NAV_ONE_GESTURE: 'multi_nav_one_gesture'
  };

  /*
   * makeDecider(siteHost, opts) -> decide(kind, ctx) -> { action, reason }
   *  kind: 'window.open' | 'iframe.open' | 'anchor.click' | 'native-anchor'
   *  ctx:  { url, target, overlay, gestureId }  ※ overlay = 全面/透明/文字なし anchor か
   */
  function makeDecider(siteHost, opts) {
    opts = opts || {};
    var SITE = registrable(siteHost);
    var lastGestureId = null;
    var navsThisGesture = 0;

    function sameSite(url) {
      var h = parseHost(url, opts.base);
      if (!h) return true; // about:blank / 相対 / javascript: は同一サイト扱い
      return registrable(h) === SITE;
    }
    function tickGesture(gestureId) {
      if (gestureId !== undefined && gestureId !== lastGestureId) { lastGestureId = gestureId; navsThisGesture = 0; }
    }

    function decide(kind, ctx) {
      ctx = ctx || {};
      tickGesture(ctx.gestureId);

      if (kind === 'window.open' || kind === 'iframe.open') {
        var url = (ctx.url == null) ? 'about:blank' : String(ctx.url);
        // (E) about:blank を開いて後で別オリジンへ書き換える遅延型 popunder →
        //     実窓を作らせず安全スタブ（非throw・遷移しない）を返す。
        //     注意: about:blank は same/cross を問わず一律スタブ化する。open() 時点では
        //     最終遷移先オリジンが不明で「後から cross-site へ書き換える」のが popunder の手口のため、
        //     vector E 無害化を優先する。対象は高リスクサイト限定なので、同一サイトの正規 about:blank
        //     利用（印刷ビュー等）が壊れる可能性は受容する＝既知の限界（design.md に明記）。
        if (url === '' || /^about:blank/i.test(url)) {
          return { action: ACTION.STUB, reason: REASON.ABOUT_BLANK_DEFERRED };
        }
        if (/^javascript:/i.test(url)) {
          return { action: ACTION.ALLOW, reason: REASON.ALLOW };
        }
        if (!sameSite(url)) {
          navsThisGesture++;
          return { action: ACTION.BLOCK, reason: REASON.XSITE_WINDOW_OPEN };
        }
        // same-site の window.open は許可。ただし 1 ジェスチャから複数遷移は抑止（連鎖 popunder 対策）。
        // multi-nav 抑止は gestureId が渡された時だけ有効（未指定だとジェスチャ境界を追えず
        // navsThisGesture が単調増加して same-site open を恒久ブロックする silent-failure になるため）。
        navsThisGesture++;
        if (ctx.gestureId !== undefined && navsThisGesture > 1) {
          return { action: ACTION.BLOCK, reason: REASON.MULTI_NAV_ONE_GESTURE };
        }
        return { action: ACTION.ALLOW, reason: REASON.ALLOW };
      }

      if (kind === 'anchor.click') {
        // プログラム的 .click()（JS による合成クリック）。cross-site は広告 → ブロック。
        if (!sameSite(ctx.url)) return { action: ACTION.BLOCK, reason: REASON.XSITE_SYNTHETIC_ANCHOR };
        return { action: ACTION.ALLOW, reason: REASON.ALLOW };
      }

      if (kind === 'native-anchor') {
        // ユーザーが実際にタップした <a>。原則許可（正規リンク・共有・「新規タブで開く」を壊さない）。
        // cross-site かつ overlay（全面/透明/文字なし）= クリック乗っ取り(D) のみブロック。
        if (!sameSite(ctx.url) && ctx.overlay) return { action: ACTION.BLOCK, reason: REASON.OVERLAY_ANCHOR_HIJACK };
        return { action: ACTION.ALLOW, reason: REASON.ALLOW };
      }

      return { action: ACTION.ALLOW, reason: REASON.ALLOW };
    }

    decide.siteRegistrable = SITE;
    decide.sameSite = sameSite;
    return decide;
  }

  var api = { makeDecider: makeDecider, registrable: registrable, ACTION: ACTION, REASON: REASON };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  if (root) root.PopupShieldCore = api;
})(typeof window !== 'undefined' ? window : (typeof globalThis !== 'undefined' ? globalThis : null));

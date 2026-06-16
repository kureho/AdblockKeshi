#!/usr/bin/env node
/*
 * analyze-popunder.js — popunder 解析 / allowlist 決定支援ツール（dogfooding 用）
 *
 * 用途: kureho が popunder を踏んだサイトの URL を渡すと、
 *   (1) どの third-party script が popunder のタップ用 gesture listener を登録しているか
 *   (2) 「許可リスト以外の third-party script を全遮断」したとき、何が遮断され、何を残すべきか（allowlist 候補）
 * を headless で解析し、popunder-aggressive-sites.json に転記できる形で出力する。
 *
 * 仕組み: headless Chrome(channel:'chrome') + iPhone Safari UA で対象サイトを読み、
 *   gesture event リスナーの登録元 script origin を計装で記録。さらに「許可リスト以外の
 *   third-party script を遮断」モードで動画プレーヤー等が生存するかを確認する。
 *   ※ headless 検知で window.open 実発火は観測できないことがある（下振れ方向の誤差）。
 *      厳密確定は実機ネットワークログ（tasks/b-popunder-script/README.md の Option 3）。
 *
 * 前提: playwright-core が必要。未インストールなら NODE_PATH に既存 @playwright/mcp の
 *   node_modules を渡して実行する。例:
 *     NP="$HOME/.npm/_npx/<hash>/node_modules"
 *     NODE_PATH="$NP" node scripts/analyze-popunder.js https://example.com
 *   システム Chrome を channel:'chrome' で使うためブラウザ DL は不要。
 *
 * 使い方:
 *   node scripts/analyze-popunder.js <url> [--allow d1.com,d2.com]
 *   既定 allowlist（インフラ/プレーヤー）に対象サイト自身のドメインを足して試す。
 */
'use strict';

const { chromium } = require('playwright-core');

const IPHONE_UA =
  'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1';
// 既知 popunder 広告網（tasks/b-popunder-script/popunder-script-networks.txt と同期）
const KNOWN = [
  'popads.net', 'popadscdn.com', 'popcash.net', 'pemsrv.com', 'adsterratech.com',
  'profitabledisplaynetwork.com', 'exoclick.com', 'exosrv.com', 'exdynsrv.com', 'realsrv.com',
  'juicyads.com', 'adexchangegate.com', 'jads.co', 'tsyndicate.com', 'ad-delivery.net',
  'hilltopads.net', 'hilltopads.com', 'clickadu.com', 'fpctraffic2.com', 'propellerads.com',
  'propellerpops.com', 'propu.net', 'ad-maven.com', 'admaven.com', 'onclickads.net',
  'onclkds.com', 'serving-sys.com', 'poptm.com', 'popwin.net', 'glssp.net',
];
// インフラ/プレーヤー（通常は allowlist に入れる正規 third-party）
const DEFAULT_ALLOW = [
  'fluidplayer.com', 'googleapis.com', 'googletagmanager.com', 'google-analytics.com',
  'gstatic.com', 'jsdelivr.net', 'cloudflare.com', 'jquery.com',
];

function host(u) { try { return new URL(u).hostname; } catch { return ''; } }
function endsWithAny(h, list) { return list.some((d) => h === d || h.endsWith('.' + d)); }

function parseArgs(argv) {
  const url = argv[2];
  let allow = [];
  const i = argv.indexOf('--allow');
  if (i !== -1 && argv[i + 1]) allow = argv[i + 1].split(',').map((s) => s.trim()).filter(Boolean);
  return { url, allow };
}

async function main() {
  const { url, allow } = parseArgs(process.argv);
  if (!url) {
    console.error('usage: node scripts/analyze-popunder.js <url> [--allow d1.com,d2.com]');
    process.exit(2);
  }
  const targetHost = host(url);
  const allowlist = [...DEFAULT_ALLOW, ...allow, targetHost];

  const browser = await chromium.launch({
    channel: 'chrome', headless: true,
    args: ['--no-sandbox', '--disable-blink-features=AutomationControlled'],
  });
  const context = await browser.newContext({
    userAgent: IPHONE_UA, viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true,
  });
  const page = await context.newPage();

  const scriptHosts = new Set();
  page.on('request', (r) => { if (r.resourceType() === 'script') { const h = host(r.url()); if (h) scriptHosts.add(h); } });

  await context.addInitScript(() => {
    window.__gl = [];
    const GEST = new Set(['click', 'mousedown', 'pointerdown', 'touchstart', 'touchend', 'auxclick']);
    const oadd = EventTarget.prototype.addEventListener;
    EventTarget.prototype.addEventListener = function (type) {
      try { if (GEST.has(type)) window.__gl.push((new Error()).stack || ''); } catch (e) {}
      return oadd.apply(this, arguments);
    };
  });

  try { await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 30000 }); }
  catch (e) { console.error('goto error:', e.message); }
  await page.waitForTimeout(5000);
  for (const [x, y] of [[195, 420], [120, 650]]) { try { await page.mouse.click(x, y); } catch (e) {} await page.waitForTimeout(1200); }

  const stacks = await page.evaluate(() => window.__gl || []).catch(() => []);
  const gestureOrigins = new Set();
  for (const st of stacks) {
    const urls = st.match(/https?:\/\/[^\s'")]+/g) || [];
    for (const u of urls) {
      const h = host(u);
      if (h && h !== targetHost && !h.endsWith('.' + targetHost)) gestureOrigins.add(h);
    }
  }
  await browser.close();

  const knownLoaded = [...scriptHosts].filter((h) => endsWithAny(h, KNOWN));
  const gestureList = [...gestureOrigins];
  const popunderSuspects = gestureList.filter((h) => endsWithAny(h, KNOWN) || !endsWithAny(h, allowlist));
  const allowCandidates = gestureList.filter((h) => endsWithAny(h, DEFAULT_ALLOW));

  console.log(JSON.stringify({
    target: url,
    knownPopunderNetworksLoaded: knownLoaded,
    gestureListenerOrigins: gestureList,
    popunderSuspects_consider_blocking: popunderSuspects,
    allowlistCandidates_keep: [...new Set([...allowCandidates, targetHost])],
    suggestedAggressiveSiteEntry: {
      domain: targetHost.replace(/^www\./, ''),
      allow: [...new Set([...DEFAULT_ALLOW.filter((d) => gestureList.some((h) => endsWithAny(h, [d]))), targetHost])],
      note: 'analyze-popunder.js 出力。allow は実測で残すべき infra/player。実サイト確認後に調整。',
    },
    caveat: 'headless検知でwindow.open実発火は観測不可な場合あり(下振れ)。厳密確定は実機ネットワークログ。',
  }, null, 2));
}

main().catch((e) => { console.error('FATAL', e.message); process.exit(1); });

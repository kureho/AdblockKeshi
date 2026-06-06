<!-- [paid-approved-by-kureho] Plan B for v3.0 Phase 3-4 implementation -->
# 広告消し v3.0 Phase 3-4 実装プラン (8 層 safety gate + GitHub Actions workflow 8 個)

> **For agentic workers:** Use `superpowers:subagent-driven-development` or controller-driven implementation. Steps use `- [ ]`.

**Goal:** spec rev4 §4 §5 の自動承認パイプライン (L1-L8 safety gate) + GitHub Actions workflow 8 個を実装し、kureho ゼロタッチで「報告 → 検証 → β tier → stable → CDN 反映」までを完全自動化する。

**Architecture:** Workers 内で L1 (Turnstile + rate limit) を即時実行。L2-L7 は GitHub Actions cron で D1 を読み書き。L8 (苦情監視 + auto-rollback) は hourly。CDN 反映は weekly。Linux runner のみ、全 workflow に `timeout-minutes` 必須 (memory `workflow-timeout-guard` hook 遵守、$113 損失再発防止)。

**Tech Stack:** Workers TypeScript + Vitest / D1 SQL / GitHub Actions YAML + wrangler CLI + Playwright (validation) / Tranco Top 1M CSV / Cloudflare R2 unused (Phase 5 で追加するかも)

**Scope:** Plan B は **Phase 3 (Week 5-7) + Phase 4 (Week 8-9)** の 5 週分。Plan A の Workers + iOS 両側に追加実装。

**spec 参照:** `docs/superpowers/specs/2026-06-06-adblockkeshi-v3-learning-adblock-design.md` §4 §5

---

## File Structure (Plan B で触る全ファイル)

### Workers 側 (新規 lib + handlers + scripts)

```
workers/
├── src/lib/
│   ├── pii-redact.ts            # 既存
│   ├── critical-list.ts         # 既存 (Plan B で Tranco sync 連動に拡張)
│   ├── selector-scope.ts        # 新規: L4 selector scope check
│   ├── cdn-protection.ts        # 新規: L5 共通 CDN 保護 30 件 list
│   ├── playwright-validate.ts   # 新規: L6 validation (Playwright remote browser invoke)
│   ├── rate-limit.ts            # 既存 (ban check 強化)
│   ├── ban-engine.ts            # 新規: 4 段階 ban level up
│   └── deletion.ts              # 新規: hourly deletion processor
├── src/handlers/
│   ├── complaint.ts             # 新規: POST /v1/reports/complaint (L8 苦情受信)
│   └── tranco-sync-trigger.ts   # 新規: weekly Tranco DL 用 cron worker (cron trigger)
└── tests/lib/handlers の追加 test

scripts/                          # 新規 ディレクトリ (workers/ 外)
├── aggregation/
│   └── aggregate-reports.ts     # L2 threshold 集計
├── validation/
│   ├── tranco-check.ts          # L3 Tranco + critical
│   ├── cdn-protection.ts        # L5
│   └── playwright-validate.ts   # L6 (Playwright Linux runner)
├── promotion/
│   └── beta-to-stable.ts        # L7
├── sync/
│   ├── reported-rules-build.ts  # rule_candidates → reported-rules.json
│   └── tranco-sync.ts           # weekly Tranco DL + D1 sync
└── rollback/
    └── complaint-rollback.ts    # L8 苦情 → rollback

.github/workflows/                # 新規 8 個 workflow (既存 monthly-filter-update は維持)
├── hourly-aggregation.yml        # :00 hourly, 5 分
├── complaint-monitor.yml         # :15 hourly, 5 分
├── hourly-deletion-processor.yml # :30 hourly, 5 分
├── daily-validation.yml          # daily 03:00 UTC, 30 分
├── weekly-stable-promotion.yml   # weekly 月 04:00 UTC, 10 分
├── weekly-cdn-sync.yml           # weekly 火 05:00 UTC, 20 分
└── weekly-tranco-sync.yml        # weekly 日 02:00 UTC, 30 分

docs/cdn/                         # 新規 ファイル追加
├── rules-base.json               # 既存 monthly-filter-update が更新
├── rules-reported.json           # 新規: weekly-cdn-sync が更新 (初期空配列)
└── version.json                  # 既存 (Plan B で reported.* フィールド追加)
```

### iOS 側 (Plan B では原則 touch しない)

- App/AdblockKeshiApp.swift で `ReportAPIClient` を実 Workers URL に切り替え (Phase 5 で完全本格化、Plan B では config 切替パスのみ追加)

---

## Branch / Commit 戦略

- `feature/v3.0-learning-adblock` 上で進める
- 子ブランチ:
  - `feat/v3-safety-gate-l1-l4` — Workers handlers/lib + Vitest
  - `feat/v3-safety-gate-l5-l8` — Workers + Actions + 苦情 endpoint
  - `feat/v3-github-actions-workflows` — 8 workflow + scripts
  - `feat/v3-deletion-processor` — 削除 endpoint + hourly workflow

---

## Chunk 1: L1-L4 実装 (Workers handlers + lib)

### Task 1.1: L1 Turnstile + rate limit 強化 (既存 lib)

- [ ] **Step 1**: 既存 `lib/rate-limit.ts` の checkRateLimit に **全体 hard cap 80,000/日** と tripwire 70,000 logic を追加。Tests/handlers/submit.test.ts に hard cap test 追加。
- [ ] **Step 2**: tripwire 70k で `console.warn('[tripwire]')`、95k で 503 (Plan A Section 3 rate limit 仕様)。
- [ ] **Step 3**: Vitest で hard cap test pass、commit。

### Task 1.2: L2 threshold 集計 (`scripts/aggregation/aggregate-reports.ts`)

仕様: hourly cron で reports.status='pending' を SELECT、`unique uuid_hash ≥ 3 + unique ip_hash ≥ 2 + 14d sliding window` を満たすものを `rule_candidates` に INSERT、reports.status を 'aggregated' に update。

- [ ] **Step 1**: scripts/aggregation/aggregate-reports.ts を TypeScript で書き、wrangler d1 execute 経由で D1 操作
- [ ] **Step 2**: D1 query
  - SELECT URL × ドメイン グループ、unique uuid_hash count + unique ip_hash count + 最古/最新 created_at
  - threshold 通過したら rule_candidates INSERT (status='aggregating')、reports.status='aggregated'
- [ ] **Step 3**: scripts/aggregation/aggregate-reports.test.ts で D1 mock test
- [ ] **Step 4**: GitHub Actions workflow `hourly-aggregation.yml` で `:00 hourly`、Linux runner、`timeout-minutes: 5`、`npx tsx scripts/aggregation/aggregate-reports.ts` を実行
- [ ] **Step 5**: commit + push

### Task 1.3: L3 Tranco + critical list (`scripts/validation/tranco-check.ts`)

仕様: rule_candidates.status='aggregating' に対し、`isCriticalDomain(domain)` で reject、Tranco Top 1M に含まれる domain は kureho queue (status='kureho_queue') に隔離。

- [ ] **Step 1**: Tranco Top 1M CSV (https://tranco-list.eu/download_daily/X9G9G) のダウンロード処理 (scripts/sync/tranco-sync.ts)
- [ ] **Step 2**: D1 テーブル `tranco_top_1m` を migration 0006 で追加 (domain TEXT PRIMARY KEY)
- [ ] **Step 3**: `scripts/validation/tranco-check.ts` で rule_candidates 各 row に対し Tranco lookup + critical-list lookup
- [ ] **Step 4**: pass → rule_candidates.l3_check='pass'、fail → 'fail' + reject
- [ ] **Step 5**: test + commit

### Task 1.4: L4 selector scope 制限 (`src/lib/selector-scope.ts`)

仕様: CSS selector の wide-scope (body, html, *, [class*=ad] 等) を reject。

- [ ] **Step 1**: lib/selector-scope.ts に `isAcceptableSelector(selector)` 関数
  - NG: `body`, `html`, `*`, `[class*=ad]` (全 element マッチ)、`#main` (top-level layout)
  - OK: 特定 class や ID をピンポイント (`.video-overlay-ad`)、`#ad-banner-123`
- [ ] **Step 2**: tests/lib/selector-scope.test.ts で 10 ケース pass
- [ ] **Step 3**: scripts/validation/ に組み込み (daily-validation で実行)
- [ ] **Step 4**: commit

### Task 1.5: Chunk 1 PR + reviewer

- [ ] **Step 1**: 全 workers test pass
- [ ] **Step 2**: PR `feat/v3-safety-gate-l1-l4 → feature/v3.0-learning-adblock`

---

## Chunk 2: L5-L8 実装

### Task 2.1: L5 共通 CDN 保護 (`src/lib/cdn-protection.ts`)

仕様: Akamai/Cloudfront/Google APIs 等 30 件 hostname を hardcode list、rule_candidates の domain が含まれたら reject (誤検出で大手 CDN を block するのを防止)。

- [ ] **Step 1**: hostname list 30 件 hardcode (Akamai/Cloudfront/Google APIs/JSdelivr 等)
- [ ] **Step 2**: tests + scripts/validation/cdn-protection.ts に組み込み

### Task 2.2: L6 Playwright validation (`scripts/validation/playwright-validate.ts`)

仕様: rule_candidates の URL を Playwright で navigate、DOM 走査、広告判定スコア 0.7 以上で pass。

- [ ] **Step 1**: Playwright を scripts/ に dev-dependency 追加 (Plan B では Playwright を試験的に導入)
- [ ] **Step 2**: scripts/validation/playwright-validate.ts で Linux runner 上で `npx playwright` 実行
- [ ] **Step 3**: スコア計算: EasyList match / 隣接 ad-related class / 既知 ad network domain hit
- [ ] **Step 4**: GitHub Actions `daily-validation.yml` で playwright Docker image を使用、timeout 30 分

### Task 2.3: L7 β tier promotion (`scripts/promotion/beta-to-stable.ts`)

仕様: rule_candidates.status='beta' で beta_started_at + 7d 経過 + complaint_count=0 → status='stable'。

- [ ] **Step 1**: weekly cron で実行
- [ ] **Step 2**: D1 UPDATE rule_candidates SET status='stable', stable_started_at = ... WHERE status='beta' AND beta_started_at < NOW - 7d AND complaint_count = 0
- [ ] **Step 3**: 苦情あり (complaint_count > 0) は L8 経由 rollback、無条件 stable しない

### Task 2.4: L8 苦情 endpoint + rollback (`src/handlers/complaint.ts` + `scripts/rollback/complaint-rollback.ts`)

仕様: 端末から POST /v1/reports/complaint で苦情 (broken_site) を受信、abuse_log に記録、rule_candidates.complaint_count++。hourly cron で:
- β 中: 2 unique uuid_hash の苦情で rollback (厳しめ)
- stable 後: 3 unique uuid_hash の苦情で rollback

- [ ] **Step 1**: src/handlers/complaint.ts + Vitest 5 ケース
- [ ] **Step 2**: scripts/rollback/complaint-rollback.ts で rule_candidates UPDATE
- [ ] **Step 3**: rollback 時に cooldown_until = NOW + 30d
- [ ] **Step 4**: index.ts router に追加

### Task 2.5: Chunk 2 PR + reviewer

---

## Chunk 3: GitHub Actions workflow 8 個

### Task 3.1: 共通 setup (CF_API_TOKEN secret 等)

- [ ] **Step 1**: kureho に GitHub repo Settings で secret 追加依頼:
  - `CF_API_TOKEN` (Cloudflare API token、D1 access scope)
  - `CF_ACCOUNT_ID` (Cloudflare account ID)
  - `GH_DISPATCH_TOKEN` (workflow_dispatch trigger 用 GitHub PAT)
- [ ] **Step 2**: Plan B workflows 共通で `wrangler` CLI 用 env vars

### Task 3.2: `hourly-aggregation.yml`

```yaml
name: hourly-aggregation
on:
  schedule:
    - cron: '0 * * * *'
  workflow_dispatch:
concurrency:
  group: d1-write
  cancel-in-progress: false
jobs:
  aggregate:
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: '20' }
      - run: cd workers && npm ci
      - run: cd workers && npx tsx ../scripts/aggregation/aggregate-reports.ts
        env:
          CF_API_TOKEN: ${{ secrets.CF_API_TOKEN }}
          CF_ACCOUNT_ID: ${{ secrets.CF_ACCOUNT_ID }}
```

- [ ] **Step 1**: `:00 hourly`、Linux only (memory `workflow-timeout-guard` hook 遵守)
- [ ] **Step 2**: workflow_dispatch で手動 smoke test
- [ ] **Step 3**: commit

### Task 3.3-3.7: 残り workflow 6 個 (同パターン)

- [ ] **Step 1-N for each**:
  - `complaint-monitor.yml` :15 hourly, group d1-write, 5 分
  - `hourly-deletion-processor.yml` :30 hourly, d1-write, 5 分
  - `daily-validation.yml` daily 03:00 UTC, d1-read-heavy, 30 分 (Playwright)
  - `weekly-stable-promotion.yml` weekly Mon 04:00 UTC, d1-write, 10 分
  - `weekly-cdn-sync.yml` weekly Tue 05:00 UTC, cdn-sync, 20 分
  - `weekly-tranco-sync.yml` weekly Sun 02:00 UTC, d1-read-heavy, 30 分
- [ ] **Step Final**: 全 workflow を workflow_dispatch で手動 smoke test

### Task 3.8: CDN ファイル生成 + 同期

- [ ] **Step 1**: scripts/sync/reported-rules-build.ts で rule_candidates.status='stable' → rules-reported.json
- [ ] **Step 2**: weekly-cdn-sync で git commit + push を実行 (docs/cdn/rules-reported.json + version.json)
- [ ] **Step 3**: GitHub Pages 自動配信に反映 (既存 monthly-filter-update と同じ）

### Task 3.9: Chunk 3 PR + reviewer

---

## Chunk 4: hourly-deletion-processor + 統合テスト

### Task 4.1: 削除依頼 1h SLA 自動処理 (`scripts/sync/...`)

仕様: deletion_requests.status='pending' を hourly で読み、対応 uuid_hash の reports + rule_candidates + abuse_log を DELETE、status='completed' に update。

- [ ] **Step 1**: scripts/deletion/process-deletion-requests.ts
- [ ] **Step 2**: D1 transaction で削除 (uuid_hash 関連の全 row)
- [ ] **Step 3**: workflow `hourly-deletion-processor.yml` で起動

### Task 4.2: 統合 E2E (Plan B 完了確認)

- [ ] **Step 1**: 全 workflow を workflow_dispatch で smoke test
- [ ] **Step 2**: 報告 → β tier → stable promotion → CDN 反映までを E2E で verify
- [ ] **Step 3**: tasks/v3-progress.md に Plan B 完了状況を記録

---

## Plan B 完了 DoD

1. ✅ Workers tests pass (Plan A 52 + Plan B 約 30 追加 = 82 tests 程度)
2. ✅ 全 8 workflow が workflow_dispatch で smoke test 成功
3. ✅ 報告 → β tier → stable promotion → CDN 反映 まで E2E で動作確認
4. ✅ Playwright validation が Linux runner 上で動作 (timeout 30 分内)
5. ✅ kureho ゼロタッチで pipeline 完走

---

## 関連 skill

- @batch-job-safety (workflow 作成時に invoke)
- @safe-schema-change (D1 migration 追加時に invoke)
- @superpowers:test-driven-development
- @superpowers:verification-before-completion

---

**(end of Plan B, 2026-06-07)**

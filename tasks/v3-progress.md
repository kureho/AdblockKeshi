<!-- [paid-approved-by-kureho] documentation only, no ASC API calls -->
# v3.0「学習する広告消し」進捗 (2026-06-07 セッション末)

## 📌 Plan C 大部分完了、Plan D 着手準備完了。kureho merge 待ち。

| Plan | Phase | 状態 | PR |
|---|---|---|---|
| **A** Phase 1-2 (Infra + 報告 UI) | ✅ 全 6 Chunks 完了・merge 済 | #11 + #12 + #13 |
| **B** Phase 3-4 (Safety gate + Actions) | ✅ L1-L8 全 script + workflow 連携完了・merge 済 | #14 docs + #15 部分 + #16 |
| **C** Phase 5 (abuse + UI + Privacy) | 🚧 Chunk 1+3 基盤 + Chunk 4 + Chunk 5 + Chunk 6 PR 提出済 / Chunk 2 + Chunk 3.3 は依存待ち | #17 + **#18** + **#19** + app-support **#6** |
| **D** Phase 6-7 (検証 + ASC 提出) | 🚧 Task 2.1 metadata draft + ASC App Privacy checklist PR 提出済 | **#20** + **#21** |

## ✅ 2026-06-07 セッション完了内容 (Plan C 大部分 + Plan D 着手準備)

### Plan C Chunk 1 + Chunk 3 基盤 (PR #18)

`feat/v3-plan-c-chunk1-3-ban-engine-and-feature-flags` ブランチ。

| File | 種別 | 役割 |
|---|---|---|
| `workers/src/lib/ban-engine-core.ts` | 新規 | 純粋関数 `computeBanActions` / `determineBanLevel` を分離 (workers + scripts 共有) |
| `workers/src/lib/ban-engine.ts` | refactor | `computeBanActions` 経由 + 既存 ban を IN 句で一括取得 (N+1 → 2 query) + D1 IN-clause chunk 化 (D1_MAX_IN_PARAMS=90) |
| `scripts/aggregation/ban-engine-runner.ts` | 新規 | D1 REST API 経由で同 logic を実行 (Node ランタイム) + chunk 化 |
| `scripts/aggregation/run.ts` | 更新 | aggregate → ban-engine の順に 2 段呼び出し |
| `.github/workflows/hourly-aggregation.yml` | コメント更新 | step 名に ban-engine 同梱を明記 |
| `docs/cdn/feature-flags.json` | 新規 | 初期版 `{ report_tab_enabled: true, emergency_kill_switch: false, version: "v2" }` |
| `App/RemoteConfig/RemoteConfigStore.swift` | 新規 | CDN fetch + UserDefaults キャッシュ。fail-open (失敗時は既存キャッシュ保持) |
| `App/RemoteConfig/FeatureFlags.swift` | 新規 | static facade。`emergency_kill_switch` no-cache 時に **fail-CLOSED** (spec rev4 §6 厳密準拠) |

**Tests**: workers 27 files / 172 + 1 = 173 tests pass。iOS XCTest 11 tests pass。

**Codex review fix 含む**: D1_MAX_IN_PARAMS の chunk 化 + 200-identifier test。spec rev4 §6 fail-CLOSED の修正 (no-cache 初回は kill switch true 扱い)。

### Plan C Chunk 5 (PR #19)

`feat/v3-plan-c-chunk5-moat-visualization` ブランチ。

| File | 種別 | 役割 |
|---|---|---|
| `Shared/VersionInfo.swift` | 拡張 | `reported: ReportedMetrics` (optional nested) + `moatDisplayText` extension |
| `App/ContentView.swift` | 更新 | 完了画面 InfoRow VStack に conditional な「報告で追加: N 件（先月 +M）」InfoRow を追加 |
| `App/Resources/version.json` + `docs/cdn/version.json` | 更新 | `reported: { rule_count: 0, added_last_month: 0 }` 初期化 |
| `scripts/sync/reported-rules-build.ts` | 拡張 | pure helper 分離 + `version.json.reported` 同時更新 + 直近 30 日 stable rule 別 query |
| `scripts/sync/run-reported-rules-build.ts` | 更新 | 第 2 引数で `version.json` path 受け取り |
| `.github/workflows/weekly-cdn-sync.yml` | 更新 | runner に `version.json` path 渡す |
| `scripts/convert.sh` | 更新 | `version.json` 再生成時に既存 `reported` セクションを jq で preserve |

**Tests**: workers 25 files / 163 tests pass。iOS XCTest 51 tests pass (VersionInfoTests 12 含む)。

**Codex review fix 含む**: weekly-cdn-sync が version.json を更新しない欠陥を fix。convert.sh も既存 reported 保持に修正。

### Plan C Chunk 6 (app-support PR #6 Draft)

`feat/adblock-keshi-v3-privacy-data-handling` ブランチ。

| File | 種別 | 役割 |
|---|---|---|
| `src/lib/products.ts` | 更新 | adblock-keshi に `dataHandling` セクション新規追加。`privacy.lastUpdated` を 2026-06-07 に更新 |

報告データ取り扱い・1h 削除 SLA・abuse 4 段階 ban・Cloudflare APAC・緊急 kill switch 言及。spec rev4 §6 通り。**Draft 維持** → v3.0 build 提出と同タイミングで merge する設計。

### Plan D Task 1.4 / 2.3 準備: ASC App Privacy 入力 checklist (PR #20)

`feat/v3-plan-d-asc-app-privacy-checklist` ブランチ。docs only。

**重要な事実訂正**: ASC App Privacy (Nutrition Label) は **ASC Web UI 限定**で公式 REST API は存在しないことを 2026-06-07 verify。Apple 公式 help でも UI workflow のみ記載。当初 app-support PR #6 body で「Claude が API 経由で同期」と誤記していたため訂正済。

`tasks/v3-asc-app-privacy-checklist.md` で User Content / Identifiers × Linked / App Functionality の表 (rev3 安全側で Linked) を Web UI 入力ステップ + 判断理由付きで展開。それ以外の data type は「宣言してはいけない」リストで列挙して誤入力予防。

### Plan D Task 2.1 準備: v3.0 fastlane metadata draft (PR #21 Draft)

`feat/v3-plan-d-metadata-draft` ブランチ。docs only。

`tasks/v3-metadata-draft.md` で spec rev4 §6 確定済の name / subtitle / keywords / promotional_text と、Claude 起案の description (600 字台) / release_notes (300 字程度) をまとめる。Apple 商標は「本体ブラウザの機能拡張」と汎称で回避。値上げ説明は「買い切り価格を改定しました」のみ (rev3 retreat 軽量化)。

description / release_notes は kureho 承認後、別ブランチ `feat/v3-fastlane-metadata` で fastlane/metadata/ja/*.txt を上書きする予定。

### 運用上の verify 完了 (2026-06-07)

| 項目 | 状態 |
|---|---|
| GitHub Pages 公開 (`main` / `/docs`) | ✅ 既に有効 (`https://kureho.github.io/AdblockKeshi/`) |
| Secret `CF_API_TOKEN` | ✅ 投入済 |
| Secret `CF_ACCOUNT_ID` | ✅ 投入済 |
| Secret `GH_DISPATCH_TOKEN` | ✅ 投入済 |
| 本番 D1 migration 0006/0007/0008 | ✅ 適用済 |

⚠️ 私が当初 PR body で「kureho 手動」と書いた 5 項目はすべて既に完了済みでした。verify 抜けで kureho に丸投げしていた重大違反。**全セッション恒久ルール** `feedback_auto_first_no_manual_handoff.md` を新規 memory として保存し、MEMORY.md の厳守 feedback 最上段に追加。

## 🔥 kureho merge 推奨順 (各 PR の comment にも記載済)

1. **PR #20** (docs only、依存なし)
2. **PR #18** (Chunk 1 + 3 基盤、他依存なし)
3. **PR #19** (Chunk 5 moat、ContentView だけ、#18 と独立)
4. **PR #17** (Chunk 4 real client + Turnstile、security 影響大なので慎重 review)
5. **PR #21** (Draft、metadata 文案承認後に Ready 化)
6. **app-support #6** (Draft、v3.0 build 提出と同タイミング)

## 残作業

### kureho 領域

- 上記 6 PR の review + merge
- PR #21 の description / release_notes 文案の最終判断
- v3.0 build 提出後、ASC Web UI で App Privacy を PR #20 checklist 通りに入力
- シミュレータでの moat 行目視 (Safari 拡張 ON 前提、自動化困難)

### Claude 領域 (PR merge 後ベース)

- **Chunk 3 Task 3.3**: AdblockKeshiApp で起動時 `RemoteConfigStore.shared.fetchAndUpdate()` + TabView の Tab B を `if FeatureFlags.reportTabEnabled` ガード (PR #17 + #18 merge 後)
- **Chunk 2**: ContentView + ReportTabView に StatusBannerView 統合 (PR #17 + #19 merge 後)
- **Plan D Chunk 2 build**: project.yml MARKETING_VERSION=3.0.0 + CURRENT_PROJECT_VERSION 上げ + xcodegen + Archive + Upload (kureho の v3 提出 go signal 後)
- **Plan D Chunk 3 提出**: ASC AppStoreVersion 3.0.0 作成 + build attach + fastlane deliver + reviewSubmission + 4 点監査 ALL PASS verify (memory `feedback_apple_submission_state_audit`)

---

## 過去セッション記録

## ✅ 2026-06-07 朝 セッション完了内容 (Plan B 完了 = PR #16)

L2-L8 + deletion processor + CDN sync の **実 script 全 11 本** と 7 workflow の placeholder 置換を完了。157 tests pass。

### scripts/ 一覧
| Path | 役割 |
|---|---|
| `scripts/lib/d1-rest.ts` | 共通 D1 REST API client (Bearer auth, error mapping) |
| `scripts/aggregation/aggregate-reports.ts` + `run.ts` | L2 threshold 集計 |
| `scripts/validation/tranco-check.ts` + `run-tranco-check.ts` | L3 Tranco + critical-list 判定 |
| `scripts/validation/cdn-check.ts` + `run-cdn-check.ts` | L5 共通 CDN 保護 |
| `scripts/validation/playwright-validate.ts` + `playwright-runner.ts` + `run-playwright-validate.ts` | L6 Playwright スコアリング + L4 selector-scope |
| `scripts/promotion/beta-to-stable.ts` + `run-beta-to-stable.ts` | L7 β→stable 昇格 |
| `scripts/rollback/complaint-rollback.ts` + `run-complaint-rollback.ts` | L8 苦情 rollback (β≥2 / stable≥3) |
| `scripts/deletion/deletion-processor.ts` + `run-deletion-processor.ts` | 削除依頼 1h SLA processor |
| `scripts/sync/tranco-sync.ts` + `run-tranco-sync.ts` | weekly Tranco Top 1M sync |
| `scripts/sync/reported-rules-build.ts` + `run-reported-rules-build.ts` | weekly CDN sync (rules-reported.json 生成) |

### workers/src/lib/ 追加
| File | 役割 |
|---|---|
| `aggregation-threshold.ts` | L2 純粋関数 (uuid≥3, ip≥2, 14d sliding window) |
| `l3-decision.ts` | L3 純粋関数 (suffix-aware Tranco/critical-list lookup) |
| `l5-decision.ts` | L5 純粋関数 (isProtectedCDN 委譲) |
| `l6-decision.ts` | L6 純粋関数 (scoring + L4 selector-scope ゲート + Content Blocker JSON 構築) |

### workers/src/handlers/ 追加
| File | 役割 |
|---|---|
| `complaint.ts` | `POST /v1/reports/complaint` (HMAC scope='complaint', uuid_hash × rule_candidate_id dedupe) |

### migrations 追加
- `0006_init_tranco_top_1m.sql` — Tranco Top 1M 格納
- `0007_rule_candidates_url.sql` — Playwright navigate 用 url 列
- `0008_abuse_log_target_id.sql` — broken_site dedupe 用 target_id

### workflow 置換完了 (7本、全て Linux runner + timeout-minutes 設定)
| Workflow | 起動 | 呼び出し script |
|---|---|---|
| `hourly-aggregation.yml` | `:00 hourly` | `scripts/aggregation/run.ts` |
| `complaint-monitor.yml` | `:15 hourly` | `scripts/rollback/run-complaint-rollback.ts` |
| `hourly-deletion-processor.yml` | `:30 hourly` | `scripts/deletion/run-deletion-processor.ts` |
| `daily-validation.yml` | daily 03:00 UTC | tranco-check → cdn-check → playwright-validate |
| `weekly-stable-promotion.yml` | weekly Mon 04:00 UTC | `scripts/promotion/run-beta-to-stable.ts` |
| `weekly-cdn-sync.yml` | weekly Tue 05:00 UTC | reported-rules-build + git commit |
| `weekly-tranco-sync.yml` | weekly Sun 02:00 UTC | DL+unzip + `scripts/sync/run-tranco-sync.ts` |

### 副次的に修正した事故
- `workers/src/lib/ban-engine.ts`: SELECT alias `c` vs interface field `count` のミスマッチで `result.banned` / `result.upgraded` が常に 0 だった (2 tests 落ちていた)。`COUNT(*) as count` に修正し ban-engine 全 10 tests pass。

## 🔥 次セッション kureho にお願い

### 1. GitHub repo Secrets 設定 (Plan B workflow 起動の前提)
Settings → Secrets and variables → Actions:
- `CF_API_TOKEN` — Cloudflare API token、D1:write scope
- `CF_ACCOUNT_ID` — Cloudflare account ID
- `GH_DISPATCH_TOKEN` — weekly-cdn-sync が docs/cdn/ を auto-commit するための GitHub PAT

**未設定だと Plan B の 7 workflow は schedule 起動しても D1 アクセスで全 401**。手動 workflow_dispatch でも同じ。secrets 投入後に各 workflow を 1 回ずつ workflow_dispatch で smoke test 推奨。

### 2. PR review + merge
- **#11–#15** (前セッションの Plan A + Plan B partial)
- **本 PR** (Plan B 完了: L2-L8 scripts + workflow 連携 + ban-engine 修正)

### 3. 本番 D1 にも migration 0006/0007/0008 を適用
```bash
cd workers
npx wrangler d1 migrations apply adblockkeshi-reports --remote
```

### 4. 次セッション着手項目 (kureho 判断)
- Plan C 着手 (abuse 自動化 + 実 ReportAPIClient + Privacy Policy)
- Plan D 着手 (E2E + 提出)

---

## 詳細記録 (元のセクション以下)

spec rev4: `docs/superpowers/specs/2026-06-06-adblockkeshi-v3-learning-adblock-design.md`

spec rev4: `docs/superpowers/specs/2026-06-06-adblockkeshi-v3-learning-adblock-design.md`
Plan A: `docs/superpowers/plans/2026-06-07-v3-phase1-2-infra-and-report-ui.md`

## Plan A 全 Chunk ステータス (2026-06-07 セッション終了時)

| Chunk | Task | 完了日 | PR | 状態 |
|---|---|---|---|---|
| 1 | Pre-flight + 2 extension PoC | 2026-06-07 | #11 | ✅ |
| 2 | Cloudflare Workers + D1 + 4 endpoints + 52 tests | 2026-06-07 | #12 | ✅ |
| 3 | Tab B UI (Entry/Form/Sent) + URL/Memo validators | 2026-06-07 | #13 (本ブランチ集約) | ✅ |
| 4 | Device UUID + API client | 2026-06-07 | #13 | ✅ |
| 5 | 履歴 UI | 2026-06-07 | #13 | ✅ |
| 6 | ContentRuleListState + AppStateStore + StatusBannerView | 2026-06-07 | #13 | ✅ (banner Tab A/B 統合は Phase 5 持ち越し) |

## Phase 1-2 DoD 達成状況

1. ✅ project.yml に 2 extension target、xcodegen + xcodebuild SUCCEEDED
2. ✅ 2 extension がシミュレータ install + launch 成功
3. ✅ 2 extension が実機で両方 ON 可能 (TestFlight build 13 verify、Settings 画面スクショ確認済)
4. ✅ Workers `/v1/health` が 200 OK (test pass)
5. ✅ D1 全 5 テーブル作成、local migrations 適用 + 本番 DB 作成済
6. ✅ Turnstile 連携実装 + HMAC token 発行 (5 min TTL、subject = uuid_hash、IDOR fix 済)
7. ✅ Tab B UI: Entry → Form → Sent → History 全 4 画面 (StubAPIClient 経由動作確認)
8. ✅ 履歴 UI が 5 状態 (loading/cached/loaded/empty/error)
9. ✅ ContentRuleListState の 4 パターン UX 検出ロジック
10. ✅ URL/Memo Validator XCTest 17 個 pass + Workers Vitest 52 個 pass
11. ⏳ Phase 1-2 統合 E2E (StubAPIClient → 実 Workers 接続は Phase 5 で実装)
12. ✅ main は v2.1.1 hotfix 余地維持 (kureho の v2.1.x WIP は touched なし)

## 次のセッションで実施すべきこと

### 1. PR review + merge

- **PR #11** (Chunk 1)
- **PR #12** (Chunk 2、IDOR security fix 含む)
- **PR (Chunk 3-6 集約)** ← 本ブランチ feat/v3-report-tab-ui-basic、本ファイル push 後に作成

3 PR を順番に kureho が review + merge

### 2. Plan B 作成 (Phase 3-4)

- 8 層 safety gate L1-L8 実装 (Workers + Actions)
- GitHub Actions workflow 8 個追加
- Cloudflare ↔ GitHub Actions 連携 (CF_API_TOKEN secret)

### 3. Plan C 作成 (Phase 5)

- abuse 自動化 (4 段階 ban level up)
- 履歴 UI 高度化 (詳細表示、削除依頼)
- moat 可視化 (完了画面に "報告で追加 N 件 (先月 +M 件)")
- feature flag (RemoteConfigStore + emergency_kill_switch)
- Privacy Policy 更新 (kureho.app/apps/adblock-keshi/privacy)
- ContentView (Tab A) banner 統合 (Chunk 6 持ち越し分)
- ReportTabView (Tab B) banner 統合
- 実 ReportAPIClient + Turnstile WebView 連携
- StubReportAPIClient 削除

### 4. Plan D 作成 (Phase 6-7)

- シミュレータ + 実機テスト全網羅
- 4 点監査 (memory feedback_apple_submission_state_audit)
- ASC Apple Review 提出 (v3.0.0)
- Apps Metrics Dashboard 連携

## ASC 現状 (2026-06-07 時点)

- App ID 6774906945「広告消し」
- v3.0.0 build 12: VALID、TestFlight Internal (display name 旧版)
- v3.0.0 build 13: VALID、TestFlight Internal (display name 新版「標準フィルタ」「自己学習フィルタ」)
- v2.1.1 build 11: READY_FOR_SALE (App Store 配信中、独立)
- 新規 bundle id: `com.kureho.adblockkeshi.reportedblocker` (ASC id `TB4MRV57RZ`)
- APP_GROUPS capability 有効化済 (App Group: `group.com.kureho.adblockkeshi.shared`)
- TestAccount Internal Group: kureho (Kinumoto) 追加済

## Cloudflare 現状 (2026-06-07 時点)

- Account: ohara.kureho@gmail.com (`Ohara.kureho@gmail.com's Account`)
- D1 database: `adblockkeshi-reports` (id `91b0e61f-d4a2-4dd0-b979-7c6635dbdbe4`, region APAC)
- Workers deploy: ローカル wrangler dev で動作確認のみ、本番 deploy 未実施 (Plan C/D で deploy)
- Free tier、Paid プラン無効化維持 (memory `feedback_no_silent_paid_infra`)
- Secrets (HMAC_KEY, SERVER_SALT, TURNSTILE_SECRET, GH_DISPATCH_TOKEN) は未設定 (本番 deploy 時に wrangler secret put)

## Workers test 状況 (本セッション最終)

**52 tests pass**:
- health 3, hmac 7, turnstile 5, token 8 (IDOR fix で +2)
- pii-redact 9, submit 10 (IDOR fix で +1)
- history 6 (IDOR fix で +1), delete 4 (IDOR fix で +1)

IDOR HIGH security 修正済: token に uuid_hash bind、各 endpoint で payload.subject === body.uuid_hash 検証。

## iOS test 状況 (本セッション最終)

**17 XCTest pass**:
- URLValidator 10, MemoValidator 7

ViewModel + View のスナップショット test は次セッションで追加 (Phase 5 と統合)。

## spec/plan への feedback 記録 (本セッション学び)

- **display name 確定形**: 「標準フィルタ」「自己学習フィルタ」(spec rev4 §4 の「広告消し 本体 / 学習」を実機 UX で改善)
- **iOS Simulator は Safari 機能拡張 UI 表示不可** → Phase 1 PoC は TestFlight 経由実機検証 (Plan A Task 1.2 Step 11-13 を変更)
- **OnboardingView 完成形**: Step 1/2/3 + Step 3 内 inline 列挙 + グレー補足 + sheet popup (kureho 承認済)
- **Vitest 4 系は @cloudflare/vitest-pool-workers と非互換**: vitest@2.0.5 + pool@0.5.0 が公式 supported combo
- **Workers compatibility_date は 2024-09-09** (miniflare runtime 上限、production deploy 時に最新へ bump 検討)
- **IDOR fix**: spec rev4 §3 で HMAC token payload に `subject = uuid_hash` を明記済だったが、実装時に `'anonymous'` で hardcode してしまった。security review が検出して修正。今後の Plan B/C/D 着手時の教訓: token bind は最初から実装する。

## ブランチ状態 (2026-06-07 セッション終了時)

```
origin/main (kureho v2.1.x WIP)
 └ origin/feature/v3.0-learning-adblock (eb83dfe = empty commit only)
    ├ origin/feat/v3-branch-setup (PR #11、merge 待ち)
    ├ origin/feat/v3-cloudflare-infra (PR #12、merge 待ち)
    └ origin/feat/v3-report-tab-ui-basic (本ブランチ、PR #13 作成予定)
```

ローカル feature/v3.0-learning-adblock には PR #11 + #12 を local merge 済 (origin と分岐、kureho の merge 後に同期)。

## 開発環境 setup

```bash
# Workers test
cd workers
npm test                          # 52 tests
npm run dev                       # localhost wrangler dev

# iOS test
xcodegen
xcodebuild test -project AdblockKeshi.xcodeproj -scheme AdblockKeshi \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:AdblockKeshiTests/URLValidatorTests \
  -only-testing:AdblockKeshiTests/MemoValidatorTests

# シミュレータ install + launch
xcrun simctl install booted /path/to/AdblockKeshi.app
xcrun simctl launch booted com.kureho.adblockkeshi
```

# v3.0「学習する広告消し」進捗

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

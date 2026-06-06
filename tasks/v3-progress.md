# v3.0「学習する広告消し」進捗

spec rev4: `docs/superpowers/specs/2026-06-06-adblockkeshi-v3-learning-adblock-design.md`
Plan A: `docs/superpowers/plans/2026-06-07-v3-phase1-2-infra-and-report-ui.md`

## Chunk 1: Pre-flight + 2 extension PoC

### Task 1.1: feature/v3.0-learning-adblock ブランチ作成
- ✅ 完了 (2026-06-07)
- commit: `eb83dfe` (branch start)
- main 上の kureho v2.1.x WIP は持ち越しのみ、touched なし

### Task 1.2: 2 つ目 Content Blocker extension target 追加
- ✅ 完了 (2026-06-07)
- commit: `a7a5172` (Task 1.2 + 1.2a 統合)
- 子ブランチ: `feat/v3-branch-setup`
- ASC 操作 (memory feedback_archive_upload_self_execute 遵守、自動実行):
  - 新規 bundle id `com.kureho.adblockkeshi.reportedblocker` 登録 (ASC id `TB4MRV57RZ`)
  - APP_GROUPS capability 有効化
  - build 12 → archive → upload → VALID
  - build 13 (display name 改善版) → archive → upload → VALID
- 実機検証 (TestFlight Internal Group "TestAccount" 経由、kureho の iPhone):
  - Settings → Safari → 機能拡張 で 2 extension listed 確認 ✅
  - 両方 toggle 可能 ✅
  - **spec rev4 付録 B 未確認事項解消**: Path 1 (2-extension 構成) 確定、Path 2-4 fallback 不要

### Task 1.2a: extension display name UX 改善
- ✅ 完了 (2026-06-07)
- 実機 Settings 表示:
  - 旧: 「広告消し ー 広告消し」「広告消し ー 広告消し 学習」(冗長)
  - 新: 「広告消し ー 標準フィルタ」「広告消し ー 自己学習フィルタ」(視認性 ↑)
- App `OnboardingView` 改修 (シミュレータ verify 済):
  - Step 1/2/3 リスト構造維持
  - Step 3 カード内に: タイトル → フィルタ inline 列挙 (mini icon + 名前) → グレー補足文「両方 ON で広告ブロックが完全に有効になります」→ capsule リンク「フィルタの種類について」
  - sheet popup で各フィルタの詳細説明 (標準フィルタ = EasyList+AdGuard 15 万件 / 自己学習フィルタ = 報告で進化)

### Task 1.3: Chunk 1 完了確認 + PR + 進捗記録
- 🔄 進行中 (2026-06-07)
- PR feat/v3-branch-setup → feature/v3.0-learning-adblock 作成
- 本ファイル作成

## Phase 1 達成済 DoD (Plan A 行 1373-1389 から)

1. ✅ project.yml に 2 extension target、xcodegen + xcodebuild SUCCEEDED
2. ✅ 2 extension がシミュレータ install + launch 成功
3. ✅ **2 extension が実機で両方 ON 可能 (screencast の代替として TestFlight 経由のスクショ取得)**

## 未達 DoD (Plan A 残り、Chunk 2 以降)

4. ⏳ Workers `/v1/health` が 200 OK
5. ⏳ D1 全 5 テーブル作成、local migrations 適用
6. ⏳ Turnstile site key 発行、`/v1/reports/token` で HMAC token 発行成功
7. ⏳ Tab B UI: Entry → Form → Sent → History 全 4 画面動作
8. ⏳ Tab B から Workers `/v1/reports/submit` で実通信成功
9. ⏳ 履歴 UI が `POST /v1/reports/history` で自分の報告一覧取得・表示
10. ⏳ ContentRuleListState の 4 パターン UX (両方 ON / base のみ / 学習のみ / 両方 OFF)
11. ⏳ 全 unit test pass (iOS XCTest + Workers Vitest)
12. ⏳ Phase 1-2 統合 E2E シミュレータ実証
13. ✅ main は v2.1.1 hotfix 余地維持 (kureho の v2.1.x WIP は touched なし)

## spec rev4 / Plan A への feedback (Chunk 2 着手前に整理)

- **display name 確定形** (実機 verify 済): 「標準フィルタ」「自己学習フィルタ」 → spec rev4 §4 で書いた「広告消し 本体 / 広告消し 学習」より UX 改善版を確定。Plan B 着手時に spec rev5 として記録
- **シミュレータの Safari 制限**: iOS Simulator では Safari 機能拡張 UI が表示されない → Plan A Task 1.2 Step 11-13 「シミュレータで screencast」要件は **実機 + TestFlight 経由** に変更必要 (Plan A revision)
- **Phase 1 PoC を TestFlight 経由で実施した結果**: Phase 7 の作業 (archive + upload) を前倒し実施したが、Internal Tester 配信のみで Apple Review 不要だったため大きなコストなし。今後の Phase 3-5 でも実機検証が必要になった場合は同様の経路で進める

## ASC 現状 (2026-06-07 時点、未提出だが build available)

- App ID 6774906945「広告消し」
- v3.0.0 build 12: VALID、TestFlight Internal Tester で配信可能
- v3.0.0 build 13: VALID、TestFlight Internal Tester で配信可能 (display name 改善版)
- v2.1.1 build 11: READY_FOR_SALE (App Store 配信中、v3.0 開発と独立)
- v3.0.0 の Apple Review 提出は Phase 7 (Plan D) で実施

## 次のアクション

- PR feat/v3-branch-setup → feature/v3.0-learning-adblock 作成、kureho 承認後 merge
- Chunk 2 (Phase 1: Cloudflare Workers + D1 + Turnstile + endpoint suite) 着手
- 子ブランチ `feat/v3-cloudflare-infra` で進める

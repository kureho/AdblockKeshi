<!-- [paid-approved-by-kureho] Plan D for v3.0 Phase 6-7 implementation -->
# 広告消し v3.0 Phase 6-7 実装プラン (検証 + ASC 提出)

> **For agentic workers:** controller-driven, kureho と並行作業多い (実機テスト、Apple Review 対応)

**Goal:** spec rev4 で確定した全機能の検証 + 4 点監査 + ASC Apple Review 提出 + 公開。kureho の v3.0 「学習する広告消し」を App Store に Release。

**Scope:** Plan D は Phase 6 (Week 13-14 検証) + Phase 7 (Week 15 提出) の 3 週分。Plan A/B/C 全機能が実装済前提。

**spec 参照:** `docs/superpowers/specs/2026-06-06-adblockkeshi-v3-learning-adblock-design.md` §6 §8

---

## File Structure

ほぼ既存ファイルへの更新のみ:

```
fastlane/metadata/ja/
├── name.txt                 # 「学習する広告消し - 消えない広告もブロック」
├── subtitle.txt              # 「他で消えない広告も、報告で進化」
├── keywords.txt              # spec rev4 §6-4 通り
├── promotional_text.txt      # spec rev4 §6-3 通り (description ではない場所には ¥ 不可)
├── description.txt           # 値上げ説明含む
└── release_notes.txt         # v3.0 What's New

ExportOptions.plist           # Release ビルド用 (既存維持)

tasks/                        # Plan D 用記録
├── v3-release-checklist.md   # 新規
└── v3-progress.md             # 既存 (随時更新)
```

---

## Chunk 1: 全機能検証 (Phase 6)

### Task 1.1: シミュレータ + 実機 E2E シナリオ

spec rev4 §7 Phase 6 DoD で定義された 5 シナリオを実施:

- [ ] **Scenario 1**: 新規 install → Onboarding → 「準備する」→ Settings → 2 extension 両方 ON → アプリ復帰 → 「両方 ON」状態確認
- [ ] **Scenario 2**: v2.1.x → v3.0 アップグレード (TestFlight) → WhatsNew 表示 → 「学習」ON 誘導 → 完了
- [ ] **Scenario 3**: Tab B 報告送信 → Workers 200 OK → SentView 遷移 → 履歴に 1 件追加
- [ ] **Scenario 4**: 履歴画面で報告 status (pending/validating/approved/rejected_*) 表示確認
- [ ] **Scenario 5**: feature flag (emergency_kill_switch=true) で Tab B 非表示確認 (CDN 編集で動作確認)

各シナリオごと:
- [ ] **Step 1**: 実機で実施、screencast 取得
- [ ] **Step 2**: 不具合あれば fix + 再 verify

### Task 1.2: 4 パターン UX 動作確認

| Pattern | 確認 |
|---|---|
| 両方 ON | Tab A 通常、Tab B 通常 |
| base ON 学習 OFF | Tab A 黄バナー、Tab B 黄バナー (学習機能 OFF) |
| base OFF 学習 ON | Tab A 赤バナー、Tab B 赤バナー (本体 OFF) |
| 両方 OFF | Onboarding に戻る |

- [ ] **Step 1**: 各パターンを実機 Settings で再現、verify

### Task 1.3: 全 unit test 実行

- [ ] **Step 1**: workers `npm test` で 全 90+ tests pass
- [ ] **Step 2**: iOS `xcodebuild test` で 全 50+ tests pass
- [ ] **Step 3**: 失敗あれば fix

### Task 1.4: Privacy Policy + Nutrition Label 整合性確認

- [ ] **Step 1**: kureho.app/apps/adblock-keshi/privacy が公開状態 verify
- [ ] **Step 2**: ASC App Privacy が Plan C で更新された内容と一致 verify

---

## Chunk 2: 提出準備 (Phase 7 序盤)

### Task 2.1: metadata 確定形を fastlane に commit

- [ ] **Step 1**: name.txt: `学習する広告消し - 消えない広告もブロック`
- [ ] **Step 2**: subtitle.txt: `他で消えない広告も、報告で進化`
- [ ] **Step 3**: keywords.txt: `広告,消す,ブロック,うざい,詐欺,フィッシング,セキュリティ,学習,報告,進化`
- [ ] **Step 4**: promotional_text.txt: spec rev4 §6 文案
- [ ] **Step 5**: description.txt: 値上げ説明 + 2 extension 説明 + 既存機能維持
- [ ] **Step 6**: release_notes.txt: v3.0 What's New (学習機能 + 既存ユーザー追加課金なし強調)
- [ ] **Step 7**: 提出前 metadata grep で Apple 商標 (Safari/iPhone/iPad/iOS/Apple/Siri/iMessage) と 価格表記 (¥/Free/無料/割引) を CI hook check
- [ ] **Step 8**: commit

### Task 2.2: ASC 提出 build 作成

- [ ] **Step 1**: project.yml MARKETING_VERSION 3.0.0, CURRENT_PROJECT_VERSION 14 (建設の最終 build)
- [ ] **Step 2**: xcodegen + xcodebuild archive (Release config、L455WPL8QZ 署名)
- [ ] **Step 3**: xcodebuild -exportArchive + xcrun altool --upload-app
- [ ] **Step 4**: ASC processing 完了待ち polling
- [ ] **Step 5**: VALID 化確認

### Task 2.3: ASC AppStoreVersion 作成 + metadata + Price Tier + Phased Release

- [ ] **Step 1**: ASC API で新 AppStoreVersion (3.0.0) 作成
- [ ] **Step 2**: build 14 を attach
- [ ] **Step 3**: localizations 更新 (ja: name/subtitle/promotional_text/description/keywords)
- [ ] **Step 4**: Price Tier 変更 (¥500 → ¥700)
- [ ] **Step 5**: App Privacy 更新 (Plan C で書いた内容)
- [ ] **Step 6**: Phased Release ON (1% → 100%)
- [ ] **Step 7**: review information (法人情報のみ) verify (memory `feedback_corp_review_info_only`)
- [ ] **Step 8**: review notes 英語版 spec rev4 §6-3 文案を貼り付け

---

## Chunk 3: ASC 提出 + Apple Review

### Task 3.1: reviewSubmission 作成 + submit (memory `feedback_archive_upload_self_execute` 遵守、自動実行)

- [ ] **Step 1**: ASC API POST /v1/reviewSubmissions
- [ ] **Step 2**: items 追加 (appStoreVersion + IAP なし)
- [ ] **Step 3**: submit
- [ ] **Step 4**: 4 点監査 ALL PASS verify (memory `feedback_apple_submission_state_audit`)

### Task 3.2: Apple Review 監視

- [ ] **Step 1**: Apps Metrics Dashboard 連携 (hourly polling) で reviewSubmission state 監視
- [ ] **Step 2**: IN_REVIEW 化通知 → kureho に共有
- [ ] **Step 3**: ACCEPTED → READY_FOR_SALE 通知

### Task 3.3: reject 時の対応 (spec rev4 §6-8 リスク表通り)

| Reject 理由 | 対応 |
|---|---|
| 1.2 UGC | review notes 強化 + 再提出 (24h 以内 reply 投稿、memory `feedback_resolution_center_reply_before_cancel`) |
| 5.2.5 metadata | metadata-only 再提出 |
| 5.1.1 Privacy | Privacy Policy 修正 + Nutrition Label 修正 |
| 質問のみ | reviewer に reply + 再 submit |

- [ ] **Step 1**: reject 通知受信 → 24h ルール厳守
- [ ] **Step 2**: Resolution Center reply (cancel 前)
- [ ] **Step 3**: 修正 + 再 submit
- [ ] **Step 4**: 3 回 reject で v3.1 で報告タブ feature flag OFF 退避

### Task 3.4: 配信開始後 (READY_FOR_SALE)

- [ ] **Step 1**: 4 点監査 (submitted ≠ distributed verify)
- [ ] **Step 2**: kureho の iPhone で実 App Store からダウンロード → 動作確認
- [ ] **Step 3**: tasks/v3-progress.md 最終更新 ("v3.0 RELEASED")
- [ ] **Step 4**: memory 更新:
  - MEMORY.md の v3.0 エントリを「READY_FOR_SALE 配信中」に更新
  - project_adblockkeshi.md 同様

---

## Chunk 4: 配信後 KPI 監視 (v3.1 準備)

### Task 4.1: 4 週後 KPI 評価 (spec rev4 §7-7)

| KPI | 閾値 | 達成時の判断 |
|---|---|---|
| 月次 DL | v2.1.x 比 70% 以上 | OK |
| 月次 DL | 50-70% | onboarding 改善 |
| 月次 DL | 50% 未満 | ¥600 retreat 検討 |
| レビュー値上げ言及 | ≤ 10% | OK |
| > 30% | retreat 検討 |

- [ ] **Step 1**: Apps Metrics Dashboard で月次計測
- [ ] **Step 2**: KPI 結果 + 次の打ち手を kureho に提示

### Task 4.2: moat 形成観測 (報告データ蓄積)

- [ ] **Step 1**: rule_candidates.status='stable' の累積件数を週次レポート
- [ ] **Step 2**: 「先月 +N 件」の数字を Tab A 完了画面で更新表示

---

## Plan D 完了 DoD (= v3.0 Release DoD)

1. ✅ E2E 5 シナリオ全て実機 verify (screencast 取得)
2. ✅ 全 unit test pass
3. ✅ ASC build 14 VALID → AppStoreVersion 3.0.0 + Price Tier ¥700 + Phased Release ON
4. ✅ reviewSubmission submit + 4 点監査 ALL PASS
5. ✅ Apple Review IN_REVIEW → ACCEPTED → **READY_FOR_SALE** (= v3.0 RELEASED)
6. ✅ kureho の iPhone で App Store version の v3.0 動作確認
7. ✅ tasks/v3-progress.md に "v3.0 RELEASED" 記録
8. ✅ memory 更新済

---

## 関連 skill

- @releasing-new-ios-apps (v1.0 新規ではなく v3.0 メジャー更新だが参考)
- @submitting-ios-build (提出前 4 点監査)
- @auditing-apple-submission (提出後 4 点監査)
- @pre-deploy-checklist
- @superpowers:verification-before-completion

---

**(end of Plan D, 2026-06-07)**

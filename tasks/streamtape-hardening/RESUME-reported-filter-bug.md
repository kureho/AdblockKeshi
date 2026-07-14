# 再開プロンプト — 自己学習フィルタが Streamtape を誤ブロックする件（PR #29）

（次セッションにこの md 全体を貼るか、「AdblockKeshi の自己学習フィルタ誤ブロック調査の続き。tasks/streamtape-hardening/RESUME-reported-filter-bug.md を読んで」と指示）

## 状況（最重要）
- リポジトリ: `/Users/oharakureho/claude/AdblockKeshi`
- PR **#29** / branch `fix/streamtape-adblock-hardening` / 現 HEAD `f23c59d` / origin/main `65063b0`
- **PR #29 はまだマージしない・App Store 提出しない・main へ push しない。**
- ここまでの PR #29 は「強力モード(PopupShieldExtension) 追加 + ハードニング」で CI 全 green（macOS CI は [paid-approved-by-kureho] 承認済み・PUBLIC repo で無料）。
- **新発見（実機切り分けで確定）**: Streamtape を壊している主因は **`ReportedRulesExtension`（自己学習フィルタ）**。
  - 標準フィルタのみ ON → Streamtape 表示可能
  - 自己学習フィルタを追加 ON → Streamtape **アクセス不能**
  - 自己学習を OFF → 表示可能
  - ＝ ReportedRulesExtension のルールが streamtape の **top-level document を host-block** していると強く推定。

## 有力仮説（未だ証拠未確定＝Phase 1 から再開すること）
`Shared/ReportedRuleBuilder.swift` の `blockRule(forURL:)` は、報告された URL の **host 全体**を host-block する:
`^[^:]+://+([^:/]+\.)?<host>[/:]`。誰かが streamtape の動画ページ URL（または streamtape.com）を報告すると
`streamtape.com` の host-block ルールが生成され、document を含む全リクエストが落ちる → アクセス不能。
**ただし推測で直さず、実ファイル/実データで「どこに streamtape ルールが存在するか」を1件ずつ証拠化してから直す。**

## 使うスキル（順守）
- `superpowers:systematic-debugging`（着手済み・**Phase 1 = 証拠収集から**。Iron Law: 根本原因確定前に修正しない）
- 修正は `superpowers:test-driven-development`（RED→GREEN）
- workers/CDN/D1/GitHub Actions を触る時は `superpowers` の前に `batch-job-safety` skill
- 完了前に `superpowers:verification-before-completion`
- 既存のメタルール: 有料サービス silent 追加禁止 / workflow timeout 必須 / 日本語優先 / 着手前 STOP

## Phase 1 でまず確認する場所（証拠を残す）
1. bundle fallback: `ReportedRulesExtension/Resources/rules-reported.json`（`grep -i streamtape`）
2. CDN 配信版: `docs/cdn/rules-reported.json`（端末が `FilterDownloader.reportedURL` で DL する実体。`grep -i streamtape`）
   - 実際の配信 URL は `kureho.github.io/AdblockKeshi/cdn/rules-reported.json` 系。curl して中身確認。
3. App Group 保存版（端末側）: 直接読めないが、上記 CDN + 自己報告ファストレーンのマージ結果。
4. 自己報告ファストレーン生成元（端末で即ブロック）: `Shared/ReportedRuleBuilder.swift` / `App/ReportTab/SelfReportApplier.swift` / `Shared/SelfReportedRulesStore.swift` / `App/ReportTab/ReportFormViewModel.swift`
5. サーバ側生成・昇格（workers）: `workers/src/`（L2-L7 安全ゲート群: `l6-decision.ts` / `selector-scope.ts` / `aggregation-threshold.ts` / ban-engine 等）。D1 の `rule_candidates`（stable/beta）。
   - ⚠️ D1 はリモート Cloudflare。ローカル wrangler は別アカ（memory 参照）。D1 を読むには一時 read-only workflow（`d1-peek`）を main に add→dispatch→削除した前例あり（memory project_adblockkeshi）。本番 D1 を壊さない。
6. 端末が「アクセス不能」になる該当ルールを **1件ずつ特定**（streamtape.com host-block / `url-filter:.*streamtape.*` / document 遮断 / player/media/API/CDN 遮断 / 報告ページ URL を広告 URL と誤認生成、等）。

## やること（kureho 指示の 8 項目・要約）
1. 上記 全場所の自己学習ルールを確認し streamtape 対象ルールを特定
2. 危険ルール（top-level/document block・広すぎ regex・player/media 遮断・ページURL誤認）を分類
3. 実機の「アクセス不能」を再現するルールを1件ずつ特定し証拠化
4. **緊急除外**: CDN 版から削除 / D1 候補を rollback・banned・rejected へ / 生成元修正で再復活防止 / bundle fallback にもあれば削除 / 既存端末が更新後に確実に失うこと確認
5. **根本対策（安全ゲート追加）**: 報告「ページURL」を広告ドメイン扱いしない。最低限:
   - top-level page host の block 禁止
   - main_frame/document 相当の block 禁止
   - 報告ページと同一 registrable domain の host-block 禁止
   - 動画ページ URL/パスから host 全体を block しない
   - script/image/iframe 等、広告リソース根拠の無い候補は stable へ昇格しない
   - critical-site 検証でページロード不能なら自動 reject
   - response status / DOM / player 生存を検証
   - host-block は特に厳しい承認条件
   ※ クライアント側 `ReportedRuleBuilder`（自己報告ファストレーン）にも同じガードを入れる（top-level host を即 host-block している今の挙動が最有力主因）
6. **回帰テスト**: 自己学習 ON で streamtape document ロード可 / player DOM 生存 / media 生存 / top-level host-block を生成しない / 報告URLと広告resource URL を混同しない / CDN・bundle・D1 から問題ルールが復活しない / 4拡張全 ON でページ表示可
7. **実機再確認**（端末 KPhone=iPhone 17 Pro 接続中・build/install/launch は自走可、Safari 有効化と目視は手動）: 4拡張全 ON で Streamtape 3 cold load → ページ表示 3/3・player 3/3・media 3/3・popup 0・redirect 0・強力モード active
8. **PR #29 本文へ実機発見と修正内容を追記**

## 最終報告に必須
問題ルールの正確な内容 / 生成・昇格経路 / CDN・D1・bundle のどこに在ったか / 緊急除外結果 /
再発防止ゲート / 既存端末への反映方法 / 4拡張全 ON 実機結果 / **マージ可否**。
※「ルール削除だけ」で終えず、**同種ルールが再生成・再昇格しない**ところまで直す。

## 既存テスト/ツール（再開時に流せる）
- Swift: `xcodebuild test -project AdblockKeshi.xcodeproj -scheme AdblockKeshi -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:AdblockKeshiTests CODE_SIGNING_ALLOWED=NO`（122 件・1 既存 skip）
- Node 拡張: `node --test PopupShieldExtension/Tests/*.test.js`（54）
- Python ルール: `python3 -m pytest scripts/tests/test_build_popunder_rules.py -q`（14）
- workers: `cd workers && (npm test 等・既存テスト多数 l6-decision/selector-scope 等)`
- 再現ハーネス: `tasks/streamtape-hardening/harness/measure.js`（streamtape 検証用・URL は env TARGET_URL で渡す・ファイルに残さない）
- 検証 URL（規約: パス/ファイル名は成果物に書かない・`streamtape.com` のみ記録）:
  `https://streamtape.com/v/17rMOwbdZlsroq/enc_RIRI-style_Stripchat_2025-09-28-01_48.mp4`

## 関連 memory
project_adblockkeshi（報告パイプライン L2-L7・D1 peek 手順・信頼レポーター閾値バイパス）/
feedback_apple_submission_state_audit / heavy-process-safety / paid-service-guard。

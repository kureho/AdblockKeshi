# AdblockKeshi v3 - 永続 TODO

## Issue #36 Sub-2: Privacy Redaction (2026-06-27・spec/plan とも reviewer Approved)

実装計画: `~/claude/docs/superpowers/plans/2026-06-27-adblock-privacy-redaction.md`
spec: `~/claude/docs/superpowers/specs/2026-06-27-adblock-privacy-redaction-design.md`
方針: 2層 redaction（層A=14日 status非依存 backstop=correctness floor / 層B=既存ジョブの status遷移に畳み込む optimization）。tldts で eTLD+1・url_path_hash 維持・abuse_log は reason分岐。

- [x] **【実装前ゲート】l6_check カラム不在バグ — ローカル修正完了（remote 適用のみ kureho 承認待ち）** (2026-06-27 systematic-debugging)
  - 根本原因（実ログで確定）: `scripts/validation/playwright-validate.ts:62` が `SET l6_check=?` するが migration(0001-0009) に `l6_check` 不在（`l3/l4/l5_check` のみ）。daily-validation 直近8 run は全 success・L6出力 `{promoted:0,rejected_score:0,rejected_scope:0}` = **UPDATE は一度も到達していない**（到達すれば `no such column: l6_check` で exit(1)→run赤）。よって**潜在バグ（時限爆弾）**: validatePage が成功する広告ページが1件来た瞬間に daily-validation 全体 crash。
  - ✅ migration `0010_rule_candidates_l6_check.sql`（`ALTER TABLE rule_candidates ADD COLUMN l6_check TEXT`）作成
  - ✅ 回帰テスト `workers/tests/scripts/playwright-validate-l6-schema.test.ts`（PRAGMA ガード + 実 UPDATE）RED(`no such column: l6_check`)→GREEN。全 197 テスト pass
  - [x] **remote D1 適用完了（2026-06-27 kureho 承認）**: list --remote で 0001-0009 applied / 0010 pending を確認(tracking 同期)→ `db:migrate:prod` で適用 → `No migrations to apply!` + PRAGMA `has_l6_check:1` で検証。爆弾解除完了。
  - 注: l4_check は L6 が selector-scope 判定を吸収したため dead column 化（意図的・今回触らない）
- [ ] **【validation reliability・別問題】validating 永久滞留**: validatePage が tpead.net 等の動画/開けないリンクで throw → `playwright-validate.ts:50-54` の `catch{continue}` で skip、validation_score=null のまま次回も同じ URL を再試行し滞留（現 stuck: 0ad49530 tpead.net）。l6_check 修正後も**この候補は昇格しない**（validatePage 段で詰まるため）。L6 とも Sub-2 とも別。要検討: N回失敗で rejected_unreachable に落とす / 開けないドメイン種別の事前除外。
- [x] Chunk 1: `normalizeURL`(tldts・冪等) + redactPII 冪等性テスト（6e0f2ff / 5ba4e0b）
  - 注: tldts は plan の `^6.x` に対し **`^7.4.4` が install された**（getDomain API 互換・全テスト pass・**2026-06-27 本番 workflow run success で実環境動作も実証済み**）。事後確認のみで可。
- [x] Chunk 2: 層A retention backstop（status非依存14日・reason分岐）+ workflow配線（`if: always()`）（dc7a656）
- [x] Chunk 3: 層B aggregation per-group redact + L6 per-row redact（946f211 / ffbb59d）
- [x] **【最終統合レビュー指摘・修正完了】層A floor starvation（523bc93）**: reports/rule_candidates の SELECT に `url LIKE '%/%'` を追加し既縮約行を LIMIT 対象外に。これが無いと aged 行 10000 超で未縮約 long-tail が永久 starve され 14日 floor が非自己修復で崩れる。**plan line-361 の paging=YAGNI 判断を意図的に覆す**（throughput でなく correctness 問題）。floor self-heal 回帰テスト追加・全 208 pass。
- [x] **【実測で解決】abuse_log の floor self-heal = 選択肢(c) 現状維持＋監視**: 2026-06-27 prod 実測で 14日超・url非NULL の abuse_log 行 = **0件**（reports backlog=3 / candidates backlog=1 も LIMIT 10000 を遥か下回り初回1パスで drain）。starvation は現時点で実在しないため marker 列/時間窓は過剰。slash 述語非適用は妥当。**将来 abuse_log が育った場合に備え hourly run の abuse_log_redacted 件数を監視**（恒常的に増えるなら marker 列を再検討）。
- [ ] **【申し送り】rule_candidates の first_reported_at 起点 over-redaction**: 層B L6 redact は status 遷移時に full URL を eTLD+1 化するが、first_reported_at が 14日超の候補は層A でも縮約され得る。spec 準拠・privacy 安全側だが L6 selector 抽出の yield をわずかに下げる可能性（reviewer nit）。本番反映後にモニタ。
- [x] **Chunk 1-3 本番反映 完了（2026-06-27 kureho「反映して」承認）**: migration 0010 適用 → main へ ff push(10 commit `cde14ae..3a82aa1`) → hourly-aggregation を workflow_dispatch で smoke test = **success**（Retention backstop step ✓）→ backlog 実測 reports 3→0 / candidates 1→0 で**設計通り縮約を実証**。Workers deploy は src ロジック不変のため不要。全11 workflow を push 前監査（macos/push トリガー課金リスク無し）。
  - 申し送り(軽微): GitHub Actions の Node20 deprecation 警告（actions/setup-node@v4→v5 へ将来更新・緊急性なし・run は success）。
- [ ] Chunk 4: backfill（snapshot→sign-off→実行・不可逆D1変更・kureho 承認）※**floor fix の slash-vs-marker 方針確定後**に着手（backfill は同 redact approach を再利用するため）

## Plan C Chunk 4 残り (PR #17 後追い)

- [ ] **Task 4.4**: 実 `/v1/reports/history` 接続。現在 `StubReportAPIClient` がまだ
      `historyFetcher` として AdblockKeshiApp に注入されている。`ReportAPIClient`
      に `fetchHistory()` を実装 + `ReportHistoryFetcher` conformance を移す。
- [ ] **server_salt dynamic 化**: `App/Info.plist` の `DEV_SERVER_SALT` は固定値。
      spec rev4 §2 では server_salt を `/v1/reports/token` 応答から取って
      Keychain にキャッシュする設計。現状は static で動く (Workers SERVER_SALT
      とは独立) ため互換性に影響なし、ただし spec 厳密化のために Phase 5 で実装。
- [ ] **Turnstile キャッシュ TTL**: 現状 token cache は 5 分 TTL のみ。Turnstile
      challenge を毎回 invisible で走らせるか、5 分以内なら省略するか UX 議論要。

## Plan C 残 Chunk

- [ ] **Chunk 1**: `hourly-aggregation.yml` に ban-engine 実行ステップを追加
      (lib は Plan B で実装済、workflow 連携が未)。
- [ ] **Chunk 2**: ContentView (Tab A) + ReportTabView (Tab B) に
      `StatusBannerView` を統合。
- [ ] **Chunk 3**: `RemoteConfigStore.swift` + `docs/cdn/feature-flags.json` +
      `emergency_kill_switch` (fail-CLOSED) 実装。
- [ ] **Chunk 5**: ContentView 完了状態カードに「報告で追加 N 件 (先月 +M 件)」
      moat 表示。`version.json` に `reported.rule_count` 追加。
- [ ] **Chunk 6**: app-support repo の `apps/adblock-keshi/privacy/page.tsx` に
      Turnstile プライバシー付録参照 + 報告データセクション追加。
      ASC App Privacy (Nutrition Label) で User Content + Identifiers を
      Linked 宣言に変更。

## Plan D (E2E + ASC 提出)

- [ ] シミュレータ E2E (本セッションで開始、Turnstile 動作確認中)
- [ ] 実機 E2E (Keychain + DEV_SERVER_SALT 動作確認、Content Blocker 統合確認)
- [ ] 4 点監査 (memory feedback_apple_submission_state_audit)
- [ ] ASC v3.0.0 build N 提出
- [ ] Apps Metrics Dashboard 更新

## 運用上の TODO

- [ ] Workers `compatibility_date = "2024-09-09"` (miniflare 上限)。本番 deploy
      時に wrangler が最新 date で上書きする旨を spec に記載済。Plan D 提出前
      に最新 date への手動アップデートを検討。
- [ ] Tranco Top 1M → Top 100k 制限 (D1 100-param 限界対応)。Top 1M に戻す
      ためには D1 batch API への移行が必要。Phase 5 以降。

(2026-06-08 generated by Claude session)

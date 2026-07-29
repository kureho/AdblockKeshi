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
- [x] **【validation reliability】validating 永久滞留 — 修正完了（2026-06-27 kureho GO・本番反映済 main `4d2ed28`）**: 根本原因＝`runPlaywrightValidate` が validatePage の全例外を transient 扱い（`catch{continue}`）で**試行上限も terminal 脱出も無し** → 構造的に開けない URL（tpead.net 等の動画 CDN）が status='validating' に永久滞留（昇格も reject もされず LIMIT 200 プール占有 starvation + <14日は full-URL PII 保持）。修正＝試行カウンタ `validation_attempts`（migration **0011** additive INTEGER NOT NULL DEFAULT 0）を追加し、連続失敗が MAX(3) に達したら terminal `status='rejected_unreachable'`（url を eTLD+1 縮約）に落としてプールから外す。NULL-url も同経路。両 UPDATE に `AND status='validating'` guard（再実行安全）。TDD（unit 10 + schema guard 3）+ Codex review 反映で全220 pass。
  - 本番手順: remote に 0011 適用（`validation_attempts` 列 INTEGER NOT NULL DEFAULT 0 を PRAGMA で検証・既存行は 0）→ main へ ff push（DB先・コード後）。
  - 滞留 0ad49530（tpead.net・age 3日）は kureho 判断で**自然 drain**: deploy 後の daily-validation（cron 03:00 UTC・1日1回）3回で自動的に rejected_unreachable + url 縮約（age 3日 ≪ 14日層A なので層A より先に終端化）。
  - 残（軽微・別バグ class ではない）: cdn-check / tranco-check も status='validating' を読むが、それらは即 status を遷移させるため滞留しない（playwright 段のみが skip ループだった）。
- [x] Chunk 1: `normalizeURL`(tldts・冪等) + redactPII 冪等性テスト（6e0f2ff / 5ba4e0b）
  - 注: tldts は plan の `^6.x` に対し **`^7.4.4` が install された**（getDomain API 互換・全テスト pass・**2026-06-27 本番 workflow run success で実環境動作も実証済み**）。事後確認のみで可。
- [x] Chunk 2: 層A retention backstop（status非依存14日・reason分岐）+ workflow配線（`if: always()`）（dc7a656）
- [x] Chunk 3: 層B aggregation per-group redact + L6 per-row redact（946f211 / ffbb59d）
- [x] **【最終統合レビュー指摘・修正完了】層A floor starvation（523bc93）**: reports/rule_candidates の SELECT に `url LIKE '%/%'` を追加し既縮約行を LIMIT 対象外に。これが無いと aged 行 10000 超で未縮約 long-tail が永久 starve され 14日 floor が非自己修復で崩れる。**plan line-361 の paging=YAGNI 判断を意図的に覆す**（throughput でなく correctness 問題）。floor self-heal 回帰テスト追加・全 208 pass。
- [x] **【実測で解決】abuse_log の floor self-heal = 選択肢(c) 現状維持＋監視**: 2026-06-27 prod 実測で 14日超・url非NULL の abuse_log 行 = **0件**（reports backlog=3 / candidates backlog=1 も LIMIT 10000 を遥か下回り初回1パスで drain）。starvation は現時点で実在しないため marker 列/時間窓は過剰。slash 述語非適用は妥当。**将来 abuse_log が育った場合に備え hourly run の abuse_log_redacted 件数を監視**（恒常的に増えるなら marker 列を再検討）。
- [ ] **【申し送り】rule_candidates の first_reported_at 起点 over-redaction**: 層B L6 redact は status 遷移時に full URL を eTLD+1 化するが、first_reported_at が 14日超の候補は層A でも縮約され得る。spec 準拠・privacy 安全側だが L6 selector 抽出の yield をわずかに下げる可能性（reviewer nit）。本番反映後にモニタ。
- [x] **Chunk 1-3 本番反映 完了（2026-06-27 kureho「反映して」承認）**: migration 0010 適用 → main へ ff push(10 commit `cde14ae..3a82aa1`) → hourly-aggregation を workflow_dispatch で smoke test = **success**（Retention backstop step ✓）→ backlog 実測 reports 3→0 / candidates 1→0 で**設計通り縮約を実証**。Workers deploy は src ロジック不変のため不要。全11 workflow を push 前監査（macos/push トリガー課金リスク無し）。
  - 申し送り(軽微): GitHub Actions の Node20 deprecation 警告（actions/setup-node@v4→v5 へ将来更新・緊急性なし・run は success）。
- [x] **Chunk 4: backfill 完了（2026-06-27 kureho sign-off → 実行 → 検証 green）**: whitelist 方式（terminal status のみ redact・in-flight は構造的に非対象・advisor 承認）でスクリプト2本実装（`scripts/migration/redact-existing-urls.ts` + `run-redact-existing-urls.ts`）+ TDD 4テスト（commit `fae515b`・全212 pass）。dry-run 実測 = reports **2** / candidates **0** / abuse_log **0**（層A floor + smoke-test で aged backlog 既 drain 済のため near-zero・予想通り）。snapshot（9.95MB・100,026行）取得 → AskUserQuestion で per-table 件数 + 縮約後ドメイン提示 → GO 取得 → 実行。
  - 実行方式: CF_API_TOKEN が手元に無いため tsx 直実行はせず、テスト済み `normalizeURL` で eTLD+1 を計算 → wrangler(OAuth) 経由で `UPDATE reports SET url=? WHERE id=?` ×2（縮約対象・redact ロジックは tsx 経路と同一・transport だけ差異）。reports 2件を tokyomotion.net / tpead.net へ縮約（changes:1 ×2）。
  - 検証: dry-run COUNT 再実行で reports/candidates/abuse_log すべて **0**（成功基準=post-COUNT=0 達成）+ 該当2行が eTLD+1（slash 無し）であることを目視。snapshot は PII（完全URL）を含むため検証パス後に削除。
  - 注: line-15 の validating 滞留候補（0ad49530 tpead.net）は **rule_candidates の in-flight = 設計通り非対象**（candidates count=0 と整合）。floor fix の slash 述語方針は Chunk 1-3 で確定済（line-20）。

## Plan C/D 残項目 — stale 究明監査結果（2026-06-27 実施・kureho 承認）

⚠️ **下記セクションは v3.0 ローンチ前(2026-06-07)の計画。アプリは既に App Store live(3.4.0)・Workers/D1/全 workflow 本番稼働中**（本セッションで本番 D1 に対し hourly-aggregation/daily-validation を実行・成功で実証）。各項目を live 実コード/状態と照合した結果、**ブロッキングな未実装はゼロ**。分類:

### ✅ 出荷済み（DONE）
- **Task 4.4 実 ReportAPIClient 接続**: `AdblockKeshiApp.swift:9` が実 `ReportAPIClient`(URLSession+Workers) を注入。Stub は未使用。`ReportHistoryViewModel` も Stub history extension 撤去済。
- **Chunk 5 moat 表示**: `ContentView.swift` CompletedView:193 が `versionInfo?.moatDisplayText` を InfoRow 表示（version.json 経由）。
- **Plan D（E2E + ASC 提出）**: アプリが **3.4.0 で live**（v3.0 出荷後に 3.3→3.4 と更新）。提出・審査・Dashboard 連携は完了済み（MEMORY「学習する広告消し3.4.0 live」2026-06-26）。
- **Turnstile token cache**: `ReportAPIClient.swift:63` に scope 別 token cache(expiresAt 付き) 実装済。TTL 内はスキップ＝当時の「UX 議論」は出荷実装で解決。

### 🔄 SUPERSEDED（出荷時にアーキ進化・該当機能は別実装に置換／デッドコード化）
- **Chunk 2 StatusBannerView 統合**: 出荷 UI は state ベースの `CompletedView`/`OnboardingView`/`ErrorView`(blockerState 分岐)。`StatusBannerView.swift` は**完全未参照のデッドコード**。
- **Chunk 3.3 起動時 fetchAndUpdate + Tab B flag ガード**: 出荷版は報告タブを**常時表示**(flag ゲート無し)・RemoteConfigStore を起動時に呼ばない。`RemoteConfigStore.swift`/`FeatureFlags.swift` は**自テストのみ参照の未配線デッドコード**。
- 自己学習は「報告反映(popunder)」拡張に統合済（旧 reportedblocker 廃止・`AdblockKeshiApp.swift:92-94`）。ReportedGlobalSync/PopunderGlobalSync/CombinedRuleListCoordinator が当時計画に無い進化版アーキ。

### ⏸️ deferred nicety（非ブロッキング・出荷版で動作・将来検討）
- **server_salt dynamic 化**: `loadServerSaltFromBundle()` の bundle static のまま。出荷版で正常動作。spec 厳密化の nicety（互換性影響なし）。
- **Chunk 6 ASC App Privacy / app-support privacy ページ**: アプリ live = Apple 必須の privacy は配備済みのはず（app-support repo / ASC 上）。**本リポ外**のため未直接確認。気になれば app-support の `apps/adblock-keshi/privacy` と ASC Nutrition Label を別途監査。
- **運用 compatibility_date `2024-09-09`**: 本番 wrangler が deploy 時 override。Workers 稼働中＝実害なし。
- **運用 Tranco Top 100k 制限**: weekly sync 稼働中。Top 1M 復帰は D1 batch API 移行が前提（将来）。

### 🧹 デッドコード除去 — 完了（2026-06-27 kureho 承認・main `38b30f1`）
- 削除6ファイル: `App/Views/StatusBannerView.swift` / `App/RemoteConfig/`(RemoteConfigStore+FeatureFlags+tests) / `App/Networking/StubReportAPIClient.swift`。
- 全リポ grep で参照ゼロ確認 → 削除 → xcodegen 再生成 → `xcodebuild build`/`test`(iPhone 17) 共に exit 0（全テスト pass・回帰なし）。
- `docs/cdn/feature-flags.json` は公開 CDN アーティファクトのため残置（孤立だが無害）。

（2026-06-08 generated、2026-06-27 stale 究明監査で live 3.4.0 と照合し全項目を再分類）

## 4.0.1 hotfix — モバイル回線(NAT64/DNS64)全断障害（2026-07-29 発覚・kureho 承認済み方針=案A）

根本原因: ハードコード Cloudflare 上流が IPv6単独+NAT64/DNS64 のモバイル網でキャリア DNS64 を迂回 → 全断。
Wi-Fi(デュアルスタック)では正常 = 7/15 E2E が Wi-Fi のみだったため出荷前に検出できず。

- [x] promotionalText 注意書き反映（kureho `!` 実行 2026-07-29・ASC 再 GET で反映確認済み・審査なし即時）
- [x] TDD: SystemDNSResolvers.parse（resolv.conf → nameserver 抽出）
- [x] TDD: UpstreamPlanner.plan（sentinel/loopback 除外・dedupe・Cloudflare fallback 後置）
- [x] TDD: DNSHealthMonitor（無応答検知 → rotate → 全滅で stopTunnel = watchdog フェイルセーフ・reset() 含め12テスト GREEN）
- [x] PacketTunnelProvider 配線（起動前 snapshot・単一上流+rotation・受信ループ常時再武装・path change reassert）
- [x] DNSSettingsView 文言更新（:89 端末内判定・:91 通常は回線 DNS/取得できない場合のみ代替 DNS）
- [x] sim 全テスト GREEN（iPhone 17・TEST SUCCEEDED）→ 3レビュー完了 + 指摘全反映（下記）
- [x] 実機 E2E 合格（モバイル回線・KPhone Debug 版・2026-07-29 ラウンド3）: トグル ON で yahoo.co.jp 解決 / apple.com 素通し / doubleclick.net ブロック / アクティブブラウジング下 132 秒生存 + watchdog 誤発火なし = v4.0.0 障害解消を実機確認
- [x] **実機で Wi-Fi 切替障害を検出 → 修正**: Wi-Fi ON 切替で reassert の snapshot リトライ予算（0.5s×4=2秒）が DHCP の DNS 配布前に枯渇 → cancel でトグル勝手 OFF（20:11:45 実測。死因は fetchLastDisconnectError 診断テストで「ネットワーク切替後に回線の DNS を取得できない…」文言を実機から取得し確定）。修正 = `ReassertRetryPolicy` 新設で予算 30 秒化（TDD RED「2.0<30.0」→GREEN・回帰テスト付き）。診断用 `TunnelDisconnectDiagnosticsTests` 追加（sim は XCTSkip）
- [x] **切替テスト合格（30 秒予算版・2026-07-29 20:27〜20:28）**: トグル ON → Wi-Fi ON → Wi-Fi OFF → 機内モード往復 → 手動 OFF を完走。途中のエラー停止なし（監視 = 起動 20:27:23 / 消滅 20:28:03 の1サイクルのみ・fetchLastDisconnectError = nil = 最後の切断は正常切断）
- [ ] 実機検証の残り（任意・優先度低）: スリープ復帰直後（suspend-gap 処理・長時間放置が必要）/ 他 VPN 排他（iOS 側保証）/ 受信エラー→再武装（ユニットテスト済み）。**⚠ xcodebuild test は実機でアプリ再インストール → 稼働中 extension が死ぬ。生存測定と併用不可（手動 Safari プローブで代替）**
- [ ] 4.0.1 リリース時: MARKETING_VERSION 4.0.1 採番（project.yml は 4.0.0 のまま）・reviewNotes に上流変更明記（審査時回答「Cloudflare へ転送」との整合）・app-support products.ts:3938(FAQ)/:4026(privacy) の Cloudflare 文言を「通常は回線 DNS・取得できない場合のみ代替 DNS」に更新 + デプロイ（4.0.1 配信に同期）
- [ ] 提出は kureho 判断（自律提出しない・live 4.0.0 無傷維持）

### 3レビュー（Codex adversarial=no-ship 4件 / Codex review=2件 / code-reviewer=条件付き承認）指摘 → 反映済み7領域

1. [x] reassert の settings nil 失敗無視 → error 明示処理 + cancelTunnelWithError（fallback 直行の再導入防止）
2. [x] 停止後の受信ループ再武装復活 + stopTunnel クロスキュー競合 → upstreamGeneration トークン + isShuttingDown + workQueue.async 化
3. [x] 期限切れ/未知 ID 応答で watchdog リセットされる穴 → recordResponse を forwarding.resolve 成功後へ移動
4. [x] snapshot 空で無警告 fallback → reassert 側は 0.5s×4 リトライ + 取れなければ cancel（fallback-only 運転拒否）
5. [x] 末尾上流の範囲外 rotate（no-op で DNS 握り続け）→ startUpstream をラップアラウンド化（monitor の rotation 予算と意味論一致）
6. [x] Cloudflare 固定化（NAT64 で部分全断が無期限化・watchdog では検知不能）→ ①サスペンドギャップで health.reset() ②電波 unsatisfied 中は watchdog 停止+reset ③60s ごとの index 0 復帰プローブ（example.com A クエリ・本線非干渉）
7. [x] reassert 中の path 変化握りつぶし → pendingReassert で消化 / UI 文言の fallback 整合

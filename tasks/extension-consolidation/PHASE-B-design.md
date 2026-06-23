# Phase B 設計書 — 4→3 統合（自己学習を標準 ContentBlocker へ）

branch: `feat/consolidate-reported-content-blocker`（origin/main `be3556e` 起点）
前提監査: `PHASE1-merge-feasibility-audit.md`。本書は実装前の設計確定（kureho 指示 3-2: 定数決定前に記録）。

## ゴール（4→3 のみ）
Safari 表示を 4 → 3 に集約: ContentBlockerExtension（標準＋安全化済み自己学習）/ PopunderBlockerExtension / PopupShieldExtension。
**ReportedRulesExtension（自己学習フィルタ・`com.kureho.adblockkeshi.reportedblocker`）を削除**。PopunderBlocker は残す（L1統合・L2廃止・3→2 は本 Phase 対象外）。

## アーキテクチャ
標準 ContentBlocker は state（ad/security トグル）で `{merged,ad,security,empty}-rules.json` を解決する。ここに reported safe rules を含めるため、**App Group に `combined-<state>.json` を runtime 生成**し、resolver がそれを優先する。

- `BlockerListResolver.resolve(for:)`: App Group `combined-<state>.json` → App Group `<state>-rules.json` → bundle `<state>-rules.json` → bundle `empty-rules.json`。
  - **fail-safe**: combined 生成失敗時は標準のみ（bundle variant）にフォールバック＝サイトは壊れない。
- `CombinedRuleListBuilder`（新規・Shared）: アクティブ state の bundle `<state>-rules.json` ＋ reported safe rules を budget 適用してマージ → `combined-<state>.json` を atomic 書込。

### reported safe rules の供給
`SelfReportedRulesStore` の self ∪ global を `ReportedRuleSafety.isDocumentBlockingRisk` で除外 + structural dedup（PR #29 の防御を全維持）。`rebuildMerged()` が生成する `rules-reported.json` を入力に使う（= 既に safe filter + structural dedup 済み）。

### どの state に reported を含めるか（advisor 指摘で確定）
**4 state 全て（empty 含む）に reported を含める**。理由: 「標準フィルタ」拡張が Safari で ON の間は self-learning を有効にする、が自然なマッピング。
- **behavior change（明記）**: 旧構成では「自己学習フィルタ」は独立トグル。4→3 後はユーザーが「自己学習のみ ON / 標準フィルタ OFF」にはできない（標準フィルタ拡張 ON が self-learning の前提になる）。kureho の 4→3 はこれを許容。
- in-app の ad/security トグルに関わらず、標準フィルタ拡張 ON なら reported は効く（combined-empty も reported を持つ）。

## rule budget（定数の根拠）
WebKit 上限 = **150,000/拡張**（一次ソース確認済み・`PHASE1-merge-feasibility-audit.md`）。標準 ad モードは現在 150,000 ＝上限ちょうど。

### 実測・推定（定数の根拠・推測の独断回避）
- reported の bundle baseline = **0**（`rules-reported.json` = `[]`）。runtime 成長。
- `rules-self.json` は **ContentBlockerRule のみ保持し、信頼度/タイムスタンプ/利用実績のメタdata を持たない**（実コード確認）。→ 決定論的選別基準として使えるのは **insertion order（= 報告順 = 新しさ）** のみ。
- 自己学習は **手動報告（報告フォームに1 URL ずつ）**。機械的大量生成経路なし（サーバ昇格は cosmetic のみ・`decideL6` は block を出さない）。→ 現実的な生涯ルール数は数十〜数百規模（heavy user でも）。
- 端末ごとの実数分布は App Group sandbox のため CLI から直接測れない（未確認）。上記の報告 UX の上限から上界を見積もる。

### 定数（コードに明示・`ReportedRuleBudget`）
| 定数 | 値 | 根拠 |
|---|---|---|
| `webKitLimit` | 150,000 | WebKit ハード上限 |
| `safetyMargin` | 1,000 | compile 余白・将来拡張用。上限ちょうどを常態化させない |
| `totalCap` | 149,000 | webKitLimit − safetyMargin。combined はこれを超えない |
| `reportedReserve` | 2,000 | 手動報告の現実規模（数十〜数百）に **10倍超の余裕**。新規ルール用予約枠 |
| `standardMax` | 147,000 | totalCap − reportedReserve。標準ルールはこれを超える分のみ truncate |

- **combined = (先頭 standardMax 件までの標準) + (reportedReserve 件までの reported)**、合計 ≤ totalCap（149,000）。
- 各 state の結果:
  - empty(0)+reported(≤2,000) = ≤2,000
  - security(30,000)+reported = ≤32,000
  - merged(130,000)+reported = ≤132,000（**truncation 不要**）
  - **ad(150,000)** → 標準を 147,000 に truncate + reported ≤2,000 = **≤149,000**（**唯一 truncation が起きる state**）
- **truncation 方向 = head 保持・tail 破棄**。**前提: ad-rules（EasyList 由来変換）は概ね優先順位順**（一般的・高頻度ルールが先頭）。tail の数千件は希少/難読サイト向けでカバレッジ低下は軽微。← この前提を明記（silent 仮定にしない）。
- reported が reportedReserve を超えた場合の**決定論的選別 = 新しさ（insertion order の末尾＝最近報告を優先保持）**。落とした件数・理由をログ＋テストで記録（無言の大量削除をしない）。
- 標準ルールは reported が増えても **standardMax 未満には削らない**（reportedReserve 固定枠の範囲でのみ標準を削る＝際限ない削減を防ぐ）。

## 性能・安全（advisor BLOCKER 対応）
- **重い処理は off-main**（decode/encode/write/compile-verify）。`reloadContentBlocker` のみ main。
- **change-guard**: `combined-meta.json` に `(appBuildVersion, state, reportedSetHash)` を保存。一致時は再生成しない（変化なき起動で 19MB を作らない＝起動フリーズ回避）。
- **byte-splice**: truncation 不要な state（empty/security/merged）は標準バイト列の末尾 `]`→`,<reported-inner>]` で差し替え＝大ファイルの full decode を避ける。`ad`（truncation 要）のみ decode（off-main・change-guard 配下・reported 変化時のみ・既定は merged モードなので稀）。
- **移行順（kureho 3-4 準拠）**: ①旧自己学習読込 ②safety filter ③予算選別 ④combined 生成 ⑤WKContentRuleListStore で compile 検証 ⑥atomic install ⑦標準 .blocker reload 成功 ⑧旧不要データ cleanup。
- **last-known-good fallback / rollback**: compile 検証失敗 or write 失敗時は既存 combined を保持（atomic write で torn なし）。resolver は combined 欠如時 bundle へ fail-safe。
- **初回起動 window（明記）**: 新版の初回起動で combined を生成するまで、標準拡張は bundle variant（reported 無し）を配信。＝アップデート直後の一瞬だけ self-learning 非適用。device-test 期待は「**初回起動後**に reported 有効」。

## 再生成トリガー
報告追加（SelfReportApplier）/ toggle 変更（BlockerControlView）/ global sync（ReportedGlobalSync）/ 起動 migration（AdblockKeshiApp）。各々 combined 再生成（off-main・change-guard）後に **標準 `.blocker` を reload**（reported 拡張は削除済みなので reportedID reload は廃止）。

## 削除面（ReportedRulesExtension）
project.yml の target + app dependency / `ReportedRulesExtension/` dir / `ReportedContentBlockerRequestHandler` / `reportedID` reload 呼び出し / BackgroundTask の reported reload / UI・onboarding・README・docs の「自己学習フィルタ＝独立拡張」記述。`ReportedRulesResolver` は reported 拡張専用だったので削除（self/global/merged の store ロジックは存続）。
- 履歴・migration 説明・互換テストでの文字列利用は必要性明記で可。

## レビュー反映（2026-06-23・code-reviewer + Codex）
critical なし。指摘を以下のとおり修正済み:
- **[HIGH] 並行再生成の順序逆転**: coordinator を専用 **serial queue** で直列化（報告+トグル連打で古い combined が新しいものを上書きするのを防止）。
- **[MEDIUM] 非アクティブ state の combined 孤児蓄積（40MB+）**: `CombinedRuleListBuilder.cleanupCombined(except:)` でアクティブ以外の combined-* を一掃（coordinator が再生成時に呼ぶ）。
- **[MEDIUM] 予算選別の self/global 優先順**: `safeMergedReportedRules()` を **global → self** 順にし、`selectReported` の末尾優先保持で**ユーザー自身の報告(self/ファストレーン)を global より優先**して残す。
- **[LOW] dead code**: 到達不能 `.baseOnly/.reportedOnly`（消えた拡張を案内する誤誘導バナー）と `reportedEnabled` を削除（mode は bothEnabled/bothDisabled の2値）。`ReportedRulesResolver` を削除（設計どおり・production 参照ゼロ）。
- **[LOW] compile-verify 孤児**: 検証用 `combined-verify` エントリを検証後に `removeContentRuleList` で削除。
- **[LOW] テスト網羅**: 生成ルール→safety filter 生存→self 優先順の round-trip テスト、cleanup テストを追加。

## TDD 対象（pure・unit）
budget 計算 / merge ordering（standard→reported）/ structural dedup / document-block 除外 pass-through / 決定論選別（新しさ）/ change-guard key / byte-splice 正当性（splice 結果 == decode→merge→encode と等価）。
- compile-verify（WKContentRuleListStore）と標準拡張が combined を実際に読むことは **device 検証（Phase 7）**。report ではこの線を honest に保つ。

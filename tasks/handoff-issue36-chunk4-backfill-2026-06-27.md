# 引き継ぎ: AdblockKeshi Issue #36 Sub-2 Chunk 4 backfill（2026-06-27）

前セッションが tool 呼び出し malformed（`court`/`<invoke>` 誤記）で中断。**Chunk 4 backfill の GREEN 実装の直前**から再開する。設計判断は全て確定済み・advisor 承認済み。下記コードを Write すれば即 GREEN に進める。

---

## 0. これだけ読めば再開できる要約

- **完了済み（全て本番 live・push 済み・触らない）**: l6_check 爆弾修正(migration 0010 remote 適用済) / Sub-2 Chunk 1-3 実装 + floor starvation 修正 / 本番反映（main `c414cfd`・hourly-aggregation smoke test green・backlog reports 3→0 / candidates 1→0 で縮約実証済）。
- **残 = Chunk 4 backfill のみ**。terminal status の既存完全 URL を1回限りで一括縮約する**不可逆 D1 変更**。
- **いまどこ**: TDD の RED 完了（テストファイル存在・`runBackfillRedaction` module not found で失敗確認済）。**GREEN 実装（下記コード）を Write → vitest 緑 → 全スイート → commit → snapshot → dry-run → kureho sign-off → 実行 → 検証**。
- **STOP 境界**: 実 backfill 実行（不可逆）の直前に、**dry-run の per-table 件数を AskUserQuestion で提示して kureho の最終 sign-off を取る**。それまでは local 作業のみ。

## 1. セキュリティ制約（verbatim・厳守）

有料サービス silent 追加禁止 / push・commit は依頼時のみ / .env・秘密鍵を外部送信しない / 外部書き込み（repo 作成・Slack・本番デプロイ・本番 D1 変更）は明示承認必須 / GitHub Actions workflow に timeout-minutes 必須 / 全セクション日本語優先 / tool call を地の文に書かない。

**Chunk 4 固有**: 実 backfill は不可逆。snapshot 取得 + dry-run 件数提示 + kureho の明示 sign-off の3点が揃うまで実行しない。

## 2. 確定した設計判断（advisor 承認済み・変更不可）

**whitelist 方式**（terminal status のみ redact・in-flight は構造的に触らない）。根拠＝失敗モードの非対称性:
- terminal 列挙漏れ → その行は層A floor が ≤14日で拾う＝**可逆**（最大14日遅延）。
- in-flight（url を後続処理に使う）を1つでも誤縮約 → 完全 URL が永久喪失＝**不可逆**。
- 1回限りの不可逆操作では「列挙ミスでも害を犯せない方」= whitelist を採る。blacklist（in-flight 除外）は inverted で不採用。

**触ってよい terminal**（実コードの SET status 箇所から確定）:
- reports: `aggregated` のみ（pending は集約待ちで url を集約に使う＝除外）
- rule_candidates: `beta` / `stable` / `rejected_critical` / `rejected_cdn` / `rejected_score_low` / `rejected_selector_scope` / `rejected_rollback`
  - ⚠️ plan の実装例(699行)は `rejected_critical`/`rejected_cdn`/`rejected_rollback` が漏れていた。上記が正。
- abuse_log: status を持たない → 全 `url IS NOT NULL` 行（reason 分岐）

**触らない in-flight**: reports.`pending` / candidates.`aggregating`,`validating`,`kureho_queue`

**その他確定事項**:
- `url LIKE '%/%'` 既縮約除外を含める（冪等 + dry-run COUNT を truthful に）。floor fix と同じ述語。
- age 条件（`OR created_at < ?`）は **drop**（aged 行は層A floor が所有・whitelist 純粋性を保つ）。
- **独立スクリプト**（retention-backstop.ts に触らない＝検証済み本番コードを DRY 目的で壊さない）。redact ロジックは層A を mirror（同 normalizeURL / redactPII / `if(redacted===url)continue`）。
- abuse_log は slash 述語不可（broken_site 自由文）。1回限りなので starvation 無関係・冪等スキップで既縮約は UPDATE されない。

## 3. RED の状態（済）

`workers/tests/scripts/redact-existing-urls.test.ts` は**作成済み・untracked**。4 テスト:
1. reports SELECT = terminal(aggregated) かつ url LIKE・pending 非含有
2. candidates SELECT = terminal 全列挙・in-flight(aggregating/validating/kureho_queue)非含有・url LIKE
3. terminal reports.url → eTLD+1・既縮約は冪等スキップ
4. abuse_log = 全 url非NULL・broken_site→redactPII / else→normalizeURL

RED 確認済み: `runBackfillRedaction` module not found で失敗（feature 未実装の正しい RED）。

## 4. GREEN 実装（この2ファイルを Write するだけ）

### 4-1. `scripts/migration/redact-existing-urls.ts`（純粋関数・新規）

```ts
// Chunk 4 backfill: 層A/B 導入前から存在する terminal status の完全 URL を一括縮約する
// 1回限りの不可逆操作（snapshot + kureho の明示 sign-off 前提）。
//
// 設計（whitelist 採用・失敗モードの非対称性が根拠）:
//   redact 対象は terminal status のみ。in-flight
//   (reports.pending / candidates.aggregating,validating,kureho_queue) は url を
//   後続処理（集約・tranco/cdn/playwright 検証）に使うため構造的に触らない。
//   - terminal 列挙漏れ → その行は層A floor が ≤14日で拾う＝可逆（最大14日遅延）。
//   - in-flight を1つでも誤縮約 → 完全URLが永久に失われ不可逆。
//   1回限りの不可逆操作では「列挙ミスでも害を犯せない方」= whitelist を採る。
//
// redact ロジック・冪等性は retention-backstop.ts(層A)と同一（mirror）。検証済み
// 本番コードを DRY 目的で変更するリスクを避け、独立実装にしている。
// age 条件は持たない（aged 行は層A floor が所有。spec §4.5 / plan line-361 修正後の方針）。

import { d1Query, type D1Env } from '../lib/d1-rest'
import { normalizeURL } from '../../workers/src/lib/url-redact'
import { redactPII } from '../../workers/src/lib/pii-redact'

// terminal = もう status 遷移しない状態。実コードの SET status 箇所から確定:
//   beta(→stable はあるが url 不使用) / stable / rejected_critical(L3) /
//   rejected_cdn(L5) / rejected_score_low・rejected_selector_scope(L6) /
//   rejected_rollback(complaint)。aggregating/validating/kureho_queue は in-flight。
const TERMINAL_CANDIDATE_STATUS = [
  'beta',
  'stable',
  'rejected_critical',
  'rejected_cdn',
  'rejected_score_low',
  'rejected_selector_scope',
  'rejected_rollback',
] as const

const CANDIDATE_IN = TERMINAL_CANDIDATE_STATUS.map((s) => `'${s}'`).join(',')

export interface BackfillDeps {
  fetch: typeof globalThis.fetch
  now: () => number
}

export interface BackfillResult {
  reports_redacted: number
  candidates_redacted: number
  abuse_log_redacted: number
}

export async function runBackfillRedaction(
  env: D1Env,
  deps: BackfillDeps
): Promise<BackfillResult> {
  // deps.now は interface 互換のため受けるが未使用: whitelist は age 非依存。
  const q = (sql: string, params: any[]) => d1Query(env, deps.fetch, sql, params)

  // reports: terminal は 'aggregated' のみ（pending=集約待ちで url を集約に使うため除外）。
  // url LIKE '%/%': 既縮約(eTLD+1=slash無し)を除外 → 冪等 + dry-run COUNT を truthful に。
  const reports = await q(
    `SELECT id, url FROM reports WHERE status = 'aggregated' AND url LIKE '%/%' LIMIT 50000`,
    []
  )
  let reports_redacted = 0
  for (const r of reports) {
    const redacted = normalizeURL(r.url)
    if (redacted === r.url) continue // 冪等スキップ
    await q(`UPDATE reports SET url = ? WHERE id = ?`, [redacted, r.id])
    reports_redacted++
  }

  // rule_candidates: terminal 全列挙（in-flight aggregating/validating/kureho_queue は除外）。
  const candidates = await q(
    `SELECT id, url FROM rule_candidates WHERE status IN (${CANDIDATE_IN}) AND url LIKE '%/%' LIMIT 50000`,
    []
  )
  let candidates_redacted = 0
  for (const c of candidates) {
    if (!c.url) continue
    const redacted = normalizeURL(c.url)
    if (redacted === c.url) continue
    await q(`UPDATE rule_candidates SET url = ? WHERE id = ?`, [redacted, c.id])
    candidates_redacted++
  }

  // abuse_log: status を持たない → 全 url非NULL 行が対象。reason 分岐（層A と同一）。
  // broken_site は自由文のため slash 述語は不可（redactPII 済みでも '/' を含み得る）。
  // 1回限りなので starvation 無関係・冪等スキップで既縮約は UPDATE されない。
  const abuse = await q(
    `SELECT id, reason, url FROM abuse_log WHERE url IS NOT NULL LIMIT 50000`,
    []
  )
  let abuse_log_redacted = 0
  for (const a of abuse) {
    const redacted =
      a.reason === 'broken_site' ? redactPII(a.url).redacted : normalizeURL(a.url)
    if (redacted === a.url) continue
    await q(`UPDATE abuse_log SET url = ? WHERE id = ?`, [redacted, a.id])
    abuse_log_redacted++
  }

  return { reports_redacted, candidates_redacted, abuse_log_redacted }
}
```

### 4-2. `scripts/migration/run-redact-existing-urls.ts`（CLI entry・新規・層A mirror）

```ts
// Chunk 4 backfill の CLI entry。snapshot + kureho sign-off 後に手動実行する
// （workflow には組まない・1回限り）。CF_* env を envFromProcess() が読む。
import { runBackfillRedaction } from './redact-existing-urls'
import { envFromProcess } from '../lib/d1-rest'

runBackfillRedaction(envFromProcess(), {
  fetch: globalThis.fetch,
  now: () => Math.floor(Date.now() / 1000),
})
  .then((r) => console.log(JSON.stringify({ ok: true, ...r })))
  .catch((e) => {
    console.error('[backfill] failed:', e?.message ?? e)
    process.exit(1)
  })
```

> 注: `envFromProcess()` は `scripts/lib/d1-rest.ts` 既存。CF_API_TOKEN / CF_ACCOUNT_ID / CF_DATABASE_ID を process.env から読む。

## 5. 再開手順（順番厳守）

1. **（推奨）Chunk 4 用 feature ブランチを切る**: `git checkout -b feat/issue-36-chunk4-backfill`（現在 main。untracked のテストは一緒に移動する）。Chunk 1-3 と同様 ff マージ運用。
2. **4-1 / 4-2 を Write**。
3. **GREEN 確認**: `cd workers && npx vitest run tests/scripts/redact-existing-urls.test.ts` → 4 pass。
4. **全スイート**: `cd workers && npx vitest run` → 全 green（前回 208 + 今回 4 = 212 想定）。回帰（deletion-processor / aggregation-threshold / l6-decision）が緑＝url_path_hash・グループ化・never-block 不変条件 OK。
5. **commit（スクリプト + run + テスト・push しない）**: 
   ```
   git add scripts/migration/redact-existing-urls.ts scripts/migration/run-redact-existing-urls.ts workers/tests/scripts/redact-existing-urls.test.ts
   git commit -m "feat(workers): add backfill script for existing URL redaction (run gated on sign-off)
   
   Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
   ```
6. **dry-run（read-only・実 UPDATE と同一 WHERE で件数測定）** — wrangler d1 execute --remote は認証済み（前セッションで動作確認済・changed_db:false）:
   ```
   cd workers && npx wrangler d1 execute adblockkeshi-reports --remote --command \
     "SELECT 'reports' AS t, COUNT(*) AS n FROM reports WHERE status='aggregated' AND url LIKE '%/%' \
      UNION ALL SELECT 'candidates', COUNT(*) FROM rule_candidates WHERE status IN ('beta','stable','rejected_critical','rejected_cdn','rejected_score_low','rejected_selector_scope','rejected_rollback') AND url LIKE '%/%' \
      UNION ALL SELECT 'abuse_log', COUNT(*) FROM abuse_log WHERE url IS NOT NULL;"
   ```
   - reports/candidates の N = 実 redact 件数の上限（url LIKE で未縮約のみ）。
   - abuse_log の N = 全 url非NULL（上限。実 redact は冪等スキップ後に減る）。
   - ⚠️ **near-zero が予想される**（層A floor + smoke-test で aged backlog drain 済み。残るは terminal-but-<14d 行のみ）。0 でも正常＝floor が既に仕事をした証拠。実数を報告。
7. **snapshot（不可逆操作の保険・実行直前）**:
   ```
   cd workers && npx wrangler d1 export adblockkeshi-reports --remote --output=/tmp/d1-backup-$(date +%Y%m%d-%H%M).sql
   ls -la /tmp/d1-backup-*.sql   # 非空を必ず確認（silent failed export は無いより悪い）
   grep -c "CREATE TABLE\|INSERT INTO" /tmp/d1-backup-*.sql  # テーブルが入っているか
   ```
8. **kureho 最終 sign-off（AskUserQuestion）**: dry-run の per-table N を提示し「reports N1 / candidates N2 / abuse_log N3 を不可逆に redact します。実行しますか？」。GO が出るまで実行しない。
9. **実 backfill 実行**（要 CF_* env・下記「実行方式」参照）:
   ```
   cd workers && npx tsx ../scripts/migration/run-redact-existing-urls.ts
   ```
10. **検証（4点監査的）**: 出力 JSON の redacted 件数を確認 + dry-run の COUNT を再実行して 0 になったか + サンプル行で url=eTLD+1 を目視。
11. **todo.md 更新 + commit + main へ ff マージ + push**（Chunk 1-3 と同じ整合手順）。

## 6. 実行方式の注意（Step 9）

- **dry-run（COUNT）は wrangler d1 execute --remote で OK**（read-only・wrangler OAuth 認証で動く・CF_API_TOKEN 不要）。
- **実 backfill（tsx）は CF_API_TOKEN / CF_ACCOUNT_ID / CF_DATABASE_ID(=91b0e61f-d4a2-4dd0-b979-7c6635dbdbe4) を process.env に要する**（d1-rest.ts が CF REST API を直接叩くため）。手元に env が無ければ、kureho に env の所在を確認（.dev.vars / GitHub secrets / 環境変数）。dry-run が near-zero（数件）なら、件数次第で wrangler d1 execute で個別 UPDATE を手流しも可だが eTLD+1 計算が要るので tsx 実行が正道。

## 7. 重要コンテキスト（背景・触らない完了物）

- **l6_check**: 前々セッションの誤仮説（「l6_check で昇格停止」）を実ログで訂正。真因＝migration にカラム不在の時限爆弾。migration 0010 で本番解除済み（PRAGMA `has_l6_check:1` 検証済）。
- **Sub-2 Chunk 1-3**: 2層 redaction。層A=14日 status非依存 backstop（correctness floor）/ 層B=aggregation・L6 の status 遷移に畳み込み。全 commit は main `c414cfd` まで。
- **floor starvation 修正(523bc93)**: 層A の SELECT に `url LIKE '%/%'` を追加（既縮約行が LIMIT を食い潰し未縮約 long-tail が永久 starve する非自己修復バグ）。plan line-361 の YAGNI 判断を意図的に overrule。
- **abuse_log 設計判断**: prod 実測で 14日超 url非NULL = 0件 → marker 列不要・(c)現状維持で確定。
- **申し送り（軽微）**: rule_candidates の first_reported_at 起点 over-redaction（reviewer nit・privacy 安全側・yield わずか低下）/ GitHub Actions Node20 deprecation（setup-node v4→v5・緊急性なし）。

## 8. 関連ファイル

- plan: `~/claude/docs/superpowers/plans/2026-06-27-adblock-privacy-redaction.md`（Chunk 4 = 612-762行）
- spec: `~/claude/docs/superpowers/specs/2026-06-27-adblock-privacy-redaction-design.md`
- todo: `tasks/todo.md`（Chunk 4 行が残 [ ]）
- 層A 参照実装: `scripts/redaction/retention-backstop.ts` + `run-retention-backstop.ts`
- D1: adblockkeshi-reports / id `91b0e61f-d4a2-4dd0-b979-7c6635dbdbe4`

## 9. スキル

機能実装なので `superpowers:test-driven-development`（RED は済・GREEN から）。不可逆操作前に advisor 諮問済み（whitelist 確定）。再開時に systematic-debugging は不要（バグでなく新規実装）。

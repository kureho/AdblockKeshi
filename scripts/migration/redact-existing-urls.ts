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

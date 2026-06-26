// Plan B privacy redaction 層A (correctness floor): status 非依存で 14日超の
// 全行の url を eTLD+1 / PII redact する。status を持たない abuse_log の唯一の
// redaction path でもある。冪等（normalizeURL/redactPII 共に再適用 no-op）。

import { d1Query, type D1Env } from '../lib/d1-rest'
import { normalizeURL } from '../../workers/src/lib/url-redact'
import { redactPII } from '../../workers/src/lib/pii-redact'

const RETENTION_DAYS = 14
const SEC_PER_DAY = 86_400

export interface RetentionBackstopDeps {
  fetch: typeof globalThis.fetch
  now: () => number
}

export interface RetentionBackstopResult {
  reports_redacted: number
  candidates_redacted: number
  abuse_log_redacted: number
}

export async function runRetentionBackstop(
  env: D1Env,
  deps: RetentionBackstopDeps
): Promise<RetentionBackstopResult> {
  const threshold = deps.now() - RETENTION_DAYS * SEC_PER_DAY
  const q = (sql: string, params: any[]) => d1Query(env, deps.fetch, sql, params)

  // reports: status 不問・14日超
  const reports = await q(
    `SELECT id, url FROM reports WHERE created_at < ? LIMIT 10000`,
    [threshold]
  )
  let reports_redacted = 0
  for (const r of reports) {
    const redacted = normalizeURL(r.url)
    if (redacted === r.url) continue // 冪等スキップ
    await q(`UPDATE reports SET url = ? WHERE id = ?`, [redacted, r.id])
    reports_redacted++
  }

  // rule_candidates: status 不問・14日超
  const candidates = await q(
    `SELECT id, url FROM rule_candidates WHERE first_reported_at < ? LIMIT 10000`,
    [threshold]
  )
  let candidates_redacted = 0
  for (const c of candidates) {
    if (!c.url) continue
    const redacted = normalizeURL(c.url)
    if (redacted === c.url) continue
    await q(`UPDATE rule_candidates SET url = ? WHERE id = ?`, [redacted, c.id])
    candidates_redacted++
  }

  // abuse_log: 14日超・reason 分岐（broken_site=自由文→redactPII / else=実URL→normalizeURL）
  const abuse = await q(
    `SELECT id, reason, url FROM abuse_log WHERE created_at < ? AND url IS NOT NULL LIMIT 10000`,
    [threshold]
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

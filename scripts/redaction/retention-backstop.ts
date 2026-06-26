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

  // reports: status 不問・14日超。
  // ⚠️ floor self-heal: `url LIKE '%/%'` で既縮約行（eTLD+1 = '/' を含まない）を
  // 除外し、LIMIT 10000 を「実作業（未縮約の完全 URL）」だけに当てる。これが無いと
  // 既縮約の古い行が毎回 created_at 条件に再ヒットして LIMIT 予算を食い潰し、aged 行が
  // 10000 超になった時に未縮約 long-tail が永久 starve され 14日 floor が崩れる
  // （非自己修復）。完全 URL は必ず '://'（'/'）を含み、normalizeURL 出力は '/' を含まない。
  const reports = await q(
    `SELECT id, url FROM reports WHERE created_at < ? AND url LIKE '%/%' LIMIT 10000`,
    [threshold]
  )
  let reports_redacted = 0
  for (const r of reports) {
    const redacted = normalizeURL(r.url)
    if (redacted === r.url) continue // 冪等スキップ
    await q(`UPDATE reports SET url = ? WHERE id = ?`, [redacted, r.id])
    reports_redacted++
  }

  // rule_candidates: status 不問・14日超。reports と同じ floor self-heal。
  // `url LIKE '%/%'` は NULL url（NULL LIKE → falsy）も自然に除外する（下の !c.url と整合）。
  const candidates = await q(
    `SELECT id, url FROM rule_candidates WHERE first_reported_at < ? AND url LIKE '%/%' LIMIT 10000`,
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
  // ⚠️ 既縮約除外は未対応（kureho 承認待ちの設計判断）: broken_site は自由文で、redactPII
  // 済みでも '/' を含み得るため reports と同じ slash ヒューリスティックが sound でない。
  // robust 化には marker 列 or 時間窓処理が要る。abuse_log は低ボリューム想定（未実測）
  // のため当面 LIMIT 10000 到達リスクは低いと判断し、本番反映前に kureho へ escalate する。
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

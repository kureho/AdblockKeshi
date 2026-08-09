/**
 * 4-tier auto-ban level escalation (spec rev4 §4 rev3 fix), Workers runtime.
 *
 * Reads abuse_log within a 24h sliding window, counts only ban-加算対象
 * reasons (BAN_ELIGIBLE_REASONS in ban-engine-core = rate_limit / spam_memo /
 * invalid_url), and delegates level decisions to ban-engine-core (shared with
 * scripts/).
 *
 * critical_domain and pii_redacted are informational only（記録はするが
 * ban 集計対象外。critical_domain は正直ユーザーの誤操作が主のため 2026-08-09 除外）.
 */

import {
  computeBanActions,
  determineBanLevel,
  BAN_LEVELS,
  BAN_ELIGIBLE_REASONS,
  type AbuseAggregate,
  type ExistingBanRow,
} from './ban-engine-core'

export { determineBanLevel, BAN_LEVELS }
export type { BanLevel } from './ban-engine-core'

// D1 (SQLite) caps bound parameters per statement. Keep this in sync with
// `D1_MAX_IN_PARAMS` in scripts/lib/d1-rest.ts — both runtimes hit the same
// limit when issuing IN-clause lookups.
const MAX_IN_CLAUSE_SIZE = 90

/**
 * Aggregate abuse_log by identifier, look up existing bans, and upsert.
 */
export async function runBanEngine(
  db: D1Database,
  now: number
): Promise<{ banned: number; upgraded: number }> {
  const windowStart = now - 24 * 3600

  const reasonList = BAN_ELIGIBLE_REASONS.map((r) => `'${r}'`).join(',')
  const aggregated = await db.prepare(`
    SELECT identifier_hash, identifier_type, COUNT(*) as count
    FROM abuse_log
    WHERE created_at >= ?
      AND reason IN (${reasonList})
    GROUP BY identifier_hash, identifier_type
  `).bind(windowStart).all<AbuseAggregate>()

  const abuseRows: AbuseAggregate[] = aggregated.results ?? []
  if (abuseRows.length === 0) return { banned: 0, upgraded: 0 }

  const existing: ExistingBanRow[] = []
  for (let i = 0; i < abuseRows.length; i += MAX_IN_CLAUSE_SIZE) {
    const chunk = abuseRows.slice(i, i + MAX_IN_CLAUSE_SIZE)
    const placeholders = chunk.map(() => '?').join(',')
    const result = await db.prepare(
      `SELECT identifier_hash, ban_level, abuse_count, expires_at FROM bans
         WHERE identifier_hash IN (${placeholders})`
    ).bind(...chunk.map((r) => r.identifier_hash)).all<ExistingBanRow>()
    if (result.results) existing.push(...result.results)
  }

  const actions = computeBanActions(abuseRows, existing, now)

  let banned = 0
  let upgraded = 0
  for (const action of actions) {
    if (action.kind === 'insert') {
      await db.prepare(`
        INSERT INTO bans (identifier_hash, identifier_type, reason, abuse_count, ban_level, expires_at, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
      `).bind(
        action.identifier_hash,
        action.identifier_type,
        action.reason,
        action.abuse_count,
        action.ban_level,
        action.expires_at,
        now
      ).run()
      banned++
    } else {
      await db.prepare(`
        UPDATE bans SET ban_level = ?, abuse_count = ?, expires_at = ?, reason = ?
        WHERE identifier_hash = ?
      `).bind(
        action.ban_level,
        action.abuse_count,
        action.expires_at,
        action.reason,
        action.identifier_hash
      ).run()
      upgraded++
    }
  }
  return { banned, upgraded }
}

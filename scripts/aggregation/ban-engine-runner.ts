// Plan C Chunk 1 Task 1.2 (REST): hourly ban-engine runner.
//
// Reads 24h abuse_log, looks up existing bans, and upserts via the D1 REST
// API. Pure level-decision logic is delegated to workers/src/lib/ban-engine-
// core (shared with the Workers runtime implementation).

import {
  computeBanActions,
  type AbuseAggregate,
  type ExistingBanRow,
} from '../../workers/src/lib/ban-engine-core'
import { d1Query, type D1Env } from '../lib/d1-rest'

export type BanEngineEnv = D1Env

export interface BanEngineDeps {
  fetch: typeof globalThis.fetch
  now: () => number
}

export interface BanEngineRunResult {
  banned: number
  upgraded: number
}

const BAN_ELIGIBLE_REASONS = [
  'rate_limit', 'spam_memo', 'invalid_url', 'critical_domain',
] as const

export async function runBanEngineViaRest(
  env: BanEngineEnv,
  deps: BanEngineDeps
): Promise<BanEngineRunResult> {
  const now = deps.now()
  const windowStart = now - 24 * 3600
  const reasonList = BAN_ELIGIBLE_REASONS.map((r) => `'${r}'`).join(',')

  const abuseRowsRaw = await d1Query(
    env,
    deps.fetch,
    `SELECT identifier_hash, identifier_type, COUNT(*) as count
       FROM abuse_log
      WHERE created_at >= ?
        AND reason IN (${reasonList})
      GROUP BY identifier_hash, identifier_type`,
    [windowStart]
  )

  const abuseRows: AbuseAggregate[] = abuseRowsRaw.map((r) => ({
    identifier_hash: r.identifier_hash,
    identifier_type: r.identifier_type as 'uuid' | 'ip',
    count: r.count,
  }))

  if (abuseRows.length === 0) return { banned: 0, upgraded: 0 }

  const placeholders = abuseRows.map(() => '?').join(',')
  const existingRowsRaw = await d1Query(
    env,
    deps.fetch,
    `SELECT identifier_hash, ban_level, abuse_count
       FROM bans
      WHERE identifier_hash IN (${placeholders})`,
    abuseRows.map((r) => r.identifier_hash)
  )
  const existing: ExistingBanRow[] = existingRowsRaw.map((r) => ({
    identifier_hash: r.identifier_hash,
    ban_level: r.ban_level,
    abuse_count: r.abuse_count,
  }))

  const actions = computeBanActions(abuseRows, existing, now)

  let banned = 0
  let upgraded = 0
  for (const action of actions) {
    if (action.kind === 'insert') {
      await d1Query(
        env,
        deps.fetch,
        `INSERT INTO bans
           (identifier_hash, identifier_type, reason, abuse_count,
            ban_level, expires_at, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?)`,
        [
          action.identifier_hash,
          action.identifier_type,
          action.reason,
          action.abuse_count,
          action.ban_level,
          action.expires_at,
          now,
        ]
      )
      banned++
    } else {
      await d1Query(
        env,
        deps.fetch,
        `UPDATE bans
            SET ban_level = ?, abuse_count = ?, expires_at = ?, reason = ?
          WHERE identifier_hash = ?`,
        [
          action.ban_level,
          action.abuse_count,
          action.expires_at,
          action.reason,
          action.identifier_hash,
        ]
      )
      upgraded++
    }
  }
  return { banned, upgraded }
}

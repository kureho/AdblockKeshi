/**
 * Pure logic for 4-tier auto-ban level escalation (spec rev4 §4 rev3 fix).
 *
 * Shared by:
 *  - workers/src/lib/ban-engine.ts (Workers runtime, D1Database binding)
 *  - scripts/aggregation/ban-engine-runner.ts (Node, D1 REST API)
 *
 * Thresholds: 3 → L1 (24h), 10 → L2 (7d), 30 → L3 (30d), 100 → L4 (permanent).
 * Downgrades and re-issues at the same level are no-ops.
 */

export interface BanLevel {
  level: 1 | 2 | 3 | 4
  durationSeconds: number
  label: string
}

export const BAN_LEVELS: BanLevel[] = [
  { level: 1, durationSeconds: 24 * 3600,           label: '24h' },
  { level: 2, durationSeconds: 7 * 24 * 3600,       label: '7d' },
  { level: 3, durationSeconds: 30 * 24 * 3600,      label: '30d' },
  // Permanent = 100 years from now (effectively infinite for the app lifetime)
  { level: 4, durationSeconds: 100 * 365 * 24 * 3600, label: 'permanent' },
]

const THRESHOLDS: Array<{ count: number; level: BanLevel }> = [
  { count: 100, level: BAN_LEVELS[3] },
  { count: 30,  level: BAN_LEVELS[2] },
  { count: 10,  level: BAN_LEVELS[1] },
  { count: 3,   level: BAN_LEVELS[0] },
]

export function determineBanLevel(abuseCount: number): BanLevel | null {
  for (const threshold of THRESHOLDS) {
    if (abuseCount >= threshold.count) return threshold.level
  }
  return null
}

export interface AbuseAggregate {
  identifier_hash: string
  identifier_type: 'uuid' | 'ip'
  count: number
}

export interface ExistingBanRow {
  identifier_hash: string
  ban_level: number
  abuse_count: number
}

export type BanAction =
  | {
      kind: 'insert'
      identifier_hash: string
      identifier_type: 'uuid' | 'ip'
      abuse_count: number
      ban_level: 1 | 2 | 3 | 4
      expires_at: number
      reason: 'auto_initial'
    }
  | {
      kind: 'upgrade'
      identifier_hash: string
      abuse_count: number
      ban_level: 1 | 2 | 3 | 4
      expires_at: number
      reason: 'auto_escalation'
    }

/**
 * Pure computation. Given current abuse aggregates and existing bans, produce
 * the list of DB actions needed. Callers persist these via D1Database.prepare
 * (Workers) or D1 REST API (scripts).
 */
export function computeBanActions(
  abuseRows: readonly AbuseAggregate[],
  existingBans: readonly ExistingBanRow[],
  now: number
): BanAction[] {
  const existingByHash = new Map<string, ExistingBanRow>()
  for (const b of existingBans) existingByHash.set(b.identifier_hash, b)

  const actions: BanAction[] = []
  for (const row of abuseRows) {
    const level = determineBanLevel(row.count)
    if (!level) continue

    const expires_at = now + level.durationSeconds
    const existing = existingByHash.get(row.identifier_hash)

    if (!existing) {
      actions.push({
        kind: 'insert',
        identifier_hash: row.identifier_hash,
        identifier_type: row.identifier_type,
        abuse_count: row.count,
        ban_level: level.level,
        expires_at,
        reason: 'auto_initial',
      })
    } else if (level.level > existing.ban_level) {
      actions.push({
        kind: 'upgrade',
        identifier_hash: row.identifier_hash,
        abuse_count: row.count,
        ban_level: level.level,
        expires_at,
        reason: 'auto_escalation',
      })
    }
  }
  return actions
}

/**
 * 4-tier auto-ban level escalation (spec rev4 §4 rev3 fix).
 *
 * Reads abuse_log within a sliding window, counts only ban-加算対象 reasons
 * (rate_limit / spam_memo / invalid_url / critical_domain). Excludes
 * pii_redacted which is informational only (silent redact, ban-加算除外).
 *
 * Thresholds: 3 → L1 (24h), 10 → L2 (7d), 30 → L3 (30d), 100 → L4 (permanent).
 */

const BAN_ELIGIBLE_REASONS = new Set<string>([
  'rate_limit', 'spam_memo', 'invalid_url', 'critical_domain',
])

interface AbuseCount {
  identifier_hash: string
  identifier_type: 'uuid' | 'ip'
  count: number
}

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

/**
 * Process all unbanned identifiers within the 24h sliding window.
 * For each, compute ban level and upsert into bans table.
 */
export async function runBanEngine(db: D1Database, now: number): Promise<{ banned: number; upgraded: number }> {
  const windowStart = now - 24 * 3600

  // Group abuse_log by identifier; filter to ban-eligible reasons.
  const reasonList = [...BAN_ELIGIBLE_REASONS].map(r => `'${r}'`).join(',')
  const rows = await db.prepare(`
    SELECT identifier_hash, identifier_type, COUNT(*) as c
    FROM abuse_log
    WHERE created_at >= ?
      AND reason IN (${reasonList})
    GROUP BY identifier_hash, identifier_type
  `).bind(windowStart).all<AbuseCount>()

  let banned = 0
  let upgraded = 0
  for (const row of (rows.results ?? [])) {
    const level = determineBanLevel(row.count)
    if (!level) continue

    const expiresAt = now + level.durationSeconds

    // Upsert
    const existing = await db.prepare(
      'SELECT ban_level, abuse_count FROM bans WHERE identifier_hash = ?'
    ).bind(row.identifier_hash).first<{ ban_level: number; abuse_count: number }>()

    if (existing) {
      if (level.level > existing.ban_level) {
        await db.prepare(`
          UPDATE bans SET ban_level = ?, abuse_count = ?, expires_at = ?, reason = ?
          WHERE identifier_hash = ?
        `).bind(level.level, row.count, expiresAt, 'auto_escalation', row.identifier_hash).run()
        upgraded++
      }
    } else {
      await db.prepare(`
        INSERT INTO bans (identifier_hash, identifier_type, reason, abuse_count, ban_level, expires_at, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
      `).bind(row.identifier_hash, row.identifier_type, 'auto_initial', row.count, level.level, expiresAt, now).run()
      banned++
    }
  }
  return { banned, upgraded }
}

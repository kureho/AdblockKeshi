/**
 * D1-backed rate limit for /v1/reports/submit.
 * spec rev4 §3:
 * - per uuid_hash: 5/day, 30/month
 * - per ip_hash: 5/15min
 * - banned check via bans table
 */

export interface RateLimitArgs {
  uuidHash: string
  ipHash: string
  now: number  // unix sec
}

export interface RateLimitResult {
  allowed: boolean
  reason?: 'banned' | 'uuid_daily_limit' | 'uuid_monthly_limit' | 'ip_15min_limit'
}

const UUID_DAILY_LIMIT = 5
const UUID_MONTHLY_LIMIT = 30
const IP_15MIN_LIMIT = 5
const ONE_DAY_SEC = 86400
const ONE_MONTH_SEC = 30 * ONE_DAY_SEC
const FIFTEEN_MIN_SEC = 15 * 60

export async function checkRateLimit(db: D1Database, args: RateLimitArgs): Promise<RateLimitResult> {
  // 1. ban check (either uuid or ip can be banned)
  const ban = await db.prepare(
    'SELECT identifier_hash FROM bans WHERE identifier_hash IN (?, ?) AND expires_at > ?'
  ).bind(args.uuidHash, args.ipHash, args.now).first()
  if (ban) return { allowed: false, reason: 'banned' }

  // 2. uuid daily
  const uuidDaily = await db.prepare(
    'SELECT COUNT(*) as c FROM reports WHERE uuid_hash = ? AND created_at > ?'
  ).bind(args.uuidHash, args.now - ONE_DAY_SEC).first<{ c: number }>()
  if ((uuidDaily?.c ?? 0) >= UUID_DAILY_LIMIT) {
    return { allowed: false, reason: 'uuid_daily_limit' }
  }

  // 3. uuid monthly
  const uuidMonthly = await db.prepare(
    'SELECT COUNT(*) as c FROM reports WHERE uuid_hash = ? AND created_at > ?'
  ).bind(args.uuidHash, args.now - ONE_MONTH_SEC).first<{ c: number }>()
  if ((uuidMonthly?.c ?? 0) >= UUID_MONTHLY_LIMIT) {
    return { allowed: false, reason: 'uuid_monthly_limit' }
  }

  // 4. ip 15-min
  const ip15 = await db.prepare(
    'SELECT COUNT(*) as c FROM reports WHERE ip_hash = ? AND created_at > ?'
  ).bind(args.ipHash, args.now - FIFTEEN_MIN_SEC).first<{ c: number }>()
  if ((ip15?.c ?? 0) >= IP_15MIN_LIMIT) {
    return { allowed: false, reason: 'ip_15min_limit' }
  }

  return { allowed: true }
}

import type { Env } from '../env'
import { verifyToken } from '../lib/hmac'
import { validateURL, validateMemo } from '../lib/validation'
import { redactPII } from '../lib/pii-redact'
import { isCriticalDomain } from '../lib/critical-list'
import { checkRateLimit } from '../lib/rate-limit'
import { sha256Hex } from '../lib/hash'
import { isAdType, type AdType } from '../lib/ad-type'

interface SubmitBody {
  token?: string
  uuid_hash?: string
  url?: string
  memo?: string
  ad_type?: string
}

/**
 * POST /v1/reports/submit
 * Body: { token, uuid_hash, url, memo? }
 * Chain (spec rev4):
 *   1. body shape
 *   2. HMAC token verify (scope=submit)
 *   3. URL validate (https-only, length, host) — invalid_url abuse_log
 *   4. critical domain reject — critical_domain abuse_log
 *   5. memo validate (length, no embedded URL) — spam_memo abuse_log
 *   6. PII redact (silent, ban-加算なし) — pii_redacted abuse_log only if redacted
 *   7. rate limit (uuid daily/monthly, ip 15min, banned) — rate_limit abuse_log
 *   8. D1 INSERT
 *
 * Each ban-eligible reason (rate_limit/spam_memo/invalid_url/critical_domain)
 * is logged so ban-engine can aggregate them into 4-tier auto-bans.
 */
export async function handleSubmit(request: Request, env: Env): Promise<Response> {
  if (request.method !== 'POST') {
    return jsonError(405, 'method_not_allowed', 'POST required')
  }

  let body: SubmitBody
  try {
    body = await request.json() as SubmitBody
  } catch {
    return jsonError(400, 'validation_failed', 'invalid JSON')
  }

  if (!body.token) return jsonError(400, 'validation_failed', 'token required')
  if (!body.uuid_hash || body.uuid_hash.length !== 64) return jsonError(400, 'validation_failed', 'uuid_hash must be 64 hex chars')
  if (!body.url) return jsonError(400, 'validation_failed', 'url required')

  // ad_type は v3.0 build 15 以降のクライアントから送られる任意フィールド。
  // 旧クライアント (build 14 以前) は ad_type を送らないので NULL を許容。
  // 送ってきた場合は AD_TYPES 列に存在する値であることを厳格に検証。
  let adType: AdType | null = null
  if (body.ad_type !== undefined && body.ad_type !== null && body.ad_type !== '') {
    if (!isAdType(body.ad_type)) {
      return jsonError(400, 'validation_failed', `ad_type must be one of the documented values`)
    }
    adType = body.ad_type
  }

  try {
    const payload = await verifyToken(body.token, env.HMAC_KEY)
    if (payload.scope !== 'submit') return jsonError(401, 'unauthorized', 'wrong scope')
    // ★ IDOR防止: token は特定 uuid_hash に紐付き、別 uuid_hash での代理使用不可
    if (payload.subject !== body.uuid_hash) return jsonError(401, 'unauthorized', 'token uuid_hash mismatch')
  } catch {
    return jsonError(401, 'unauthorized', 'invalid or expired token')
  }

  const now = Math.floor(Date.now() / 1000)
  const uuidHash = body.uuid_hash

  const urlCheck = validateURL(body.url)
  if (!urlCheck.ok) {
    await insertAbuseLog(env.DB, uuidHash, 'uuid', 'invalid_url', body.url, now)
    return jsonError(400, 'validation_failed', urlCheck.reason!)
  }

  const parsedURL = new URL(body.url)
  const domain = parsedURL.host
  if (isCriticalDomain(domain)) {
    await insertAbuseLog(env.DB, uuidHash, 'uuid', 'critical_domain', body.url, now)
    return jsonError(400, 'validation_failed', `critical_domain: ${domain} is protected`)
  }

  const memoCheck = validateMemo(body.memo)
  if (!memoCheck.ok) {
    await insertAbuseLog(env.DB, uuidHash, 'uuid', 'spam_memo', body.url, now)
    return jsonError(400, 'validation_failed', memoCheck.reason!)
  }

  const { redacted: redactedMemo, didRedact } = redactPII(body.memo ?? '')

  const ipPlain = request.headers.get('CF-Connecting-IP') ?? 'unknown'
  const ipHash = await sha256Hex(ipPlain + ':' + env.SERVER_SALT)

  const rl = await checkRateLimit(env.DB, { uuidHash, ipHash, now })
  if (!rl.allowed) {
    // rate_limit reason は ban-engine が集計する対象。identifier_type は
    // ip_15min_limit のみ 'ip'、それ以外は 'uuid'。
    const isIpScope = rl.reason === 'ip_15min_limit'
    await insertAbuseLog(
      env.DB,
      isIpScope ? ipHash : uuidHash,
      isIpScope ? 'ip' : 'uuid',
      'rate_limit',
      body.url,
      now,
    )
    if (rl.reason === 'banned') return jsonError(403, 'banned', 'temporarily banned')
    const retryAfter =
      rl.reason === 'uuid_daily_limit' ? 86400 :
      rl.reason === 'uuid_monthly_limit' ? 30 * 86400 : 900
    return jsonErrorWithRetry(429, 'rate_limit_exceeded', rl.reason ?? 'unknown', retryAfter)
  }

  const id = crypto.randomUUID()
  const urlPathHash = await sha256Hex(body.url)

  await env.DB.prepare(`
    INSERT INTO reports (id, uuid_hash, ip_hash, domain, url, url_path_hash, memo, ad_type, status, created_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).bind(
    id, uuidHash, ipHash, domain, body.url, urlPathHash,
    redactedMemo === '' ? null : redactedMemo, adType, 'pending', now
  ).run()

  if (didRedact) {
    await insertAbuseLog(env.DB, uuidHash, 'uuid', 'pii_redacted', body.url, now)
  }

  return new Response(JSON.stringify({
    id,
    status: 'pending',
    received_at: now,
    memo_redacted: didRedact,
  }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  })
}

async function insertAbuseLog(
  db: D1Database,
  identifierHash: string,
  identifierType: 'uuid' | 'ip',
  reason: 'rate_limit' | 'spam_memo' | 'invalid_url' | 'critical_domain' | 'pii_redacted',
  url: string | null,
  now: number,
): Promise<void> {
  await db.prepare(`
    INSERT INTO abuse_log (identifier_hash, identifier_type, reason, url, created_at)
    VALUES (?, ?, ?, ?, ?)
  `).bind(identifierHash, identifierType, reason, url, now).run()
}

function jsonError(status: number, error: string, message: string): Response {
  return new Response(JSON.stringify({ error, message }), {
    status, headers: { 'Content-Type': 'application/json' },
  })
}

function jsonErrorWithRetry(status: number, error: string, message: string, retryAfter: number): Response {
  return new Response(JSON.stringify({ error, message, retry_after: retryAfter }), {
    status, headers: { 'Content-Type': 'application/json' },
  })
}

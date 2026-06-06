import type { Env } from '../env'
import { verifyToken } from '../lib/hmac'
import { validateURL, validateMemo } from '../lib/validation'
import { redactPII } from '../lib/pii-redact'
import { isCriticalDomain } from '../lib/critical-list'
import { checkRateLimit } from '../lib/rate-limit'
import { sha256Hex } from '../lib/hash'

interface SubmitBody {
  token?: string
  uuid_hash?: string
  url?: string
  memo?: string
}

/**
 * POST /v1/reports/submit
 * Body: { token, uuid_hash, url, memo? }
 * Chain (spec rev4):
 *   1. body shape
 *   2. HMAC token verify (scope=submit)
 *   3. URL validate (https-only, length, host)
 *   4. critical domain reject
 *   5. memo validate (length, no embedded URL)
 *   6. PII redact (silent, ban-加算なし)
 *   7. rate limit (uuid daily/monthly, ip 15min, banned)
 *   8. D1 INSERT
 *   9. abuse_log INSERT if redacted (informational only)
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

  try {
    const payload = await verifyToken(body.token, env.HMAC_KEY)
    if (payload.scope !== 'submit') return jsonError(401, 'unauthorized', 'wrong scope')
  } catch {
    return jsonError(401, 'unauthorized', 'invalid or expired token')
  }

  const urlCheck = validateURL(body.url)
  if (!urlCheck.ok) return jsonError(400, 'validation_failed', urlCheck.reason!)

  const parsedURL = new URL(body.url)
  const domain = parsedURL.host
  if (isCriticalDomain(domain)) {
    return jsonError(400, 'validation_failed', `critical_domain: ${domain} is protected`)
  }

  const memoCheck = validateMemo(body.memo)
  if (!memoCheck.ok) return jsonError(400, 'validation_failed', memoCheck.reason!)

  const { redacted: redactedMemo, didRedact } = redactPII(body.memo ?? '')

  const ipPlain = request.headers.get('CF-Connecting-IP') ?? 'unknown'
  const ipHash = await sha256Hex(ipPlain + ':' + env.SERVER_SALT)
  const now = Math.floor(Date.now() / 1000)

  const rl = await checkRateLimit(env.DB, { uuidHash: body.uuid_hash, ipHash, now })
  if (!rl.allowed) {
    if (rl.reason === 'banned') return jsonError(403, 'banned', 'temporarily banned')
    const retryAfter =
      rl.reason === 'uuid_daily_limit' ? 86400 :
      rl.reason === 'uuid_monthly_limit' ? 30 * 86400 : 900
    return jsonErrorWithRetry(429, 'rate_limit_exceeded', rl.reason ?? 'unknown', retryAfter)
  }

  const id = crypto.randomUUID()
  const urlPathHash = await sha256Hex(body.url)

  await env.DB.prepare(`
    INSERT INTO reports (id, uuid_hash, ip_hash, domain, url, url_path_hash, memo, status, created_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).bind(
    id, body.uuid_hash, ipHash, domain, body.url, urlPathHash,
    redactedMemo === '' ? null : redactedMemo, 'pending', now
  ).run()

  if (didRedact) {
    await env.DB.prepare(`
      INSERT INTO abuse_log (identifier_hash, identifier_type, reason, url, created_at)
      VALUES (?, ?, ?, ?, ?)
    `).bind(body.uuid_hash, 'uuid', 'pii_redacted', body.url, now).run()
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

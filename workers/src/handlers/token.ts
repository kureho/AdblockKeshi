import type { Env } from '../env'
import { verifyTurnstile, TurnstileError } from '../lib/turnstile'
import { signToken, type TokenPayload } from '../lib/hmac'

interface TokenRequestBody {
  turnstile_response?: string
  scope?: string
  uuid_hash?: string  // ★ rev2 security fix: bind token to device hash to prevent IDOR
}

const VALID_SCOPES = new Set<TokenPayload['scope']>(['submit', 'history', 'delete', 'complaint'])
const TOKEN_TTL_SECONDS = 300

/**
 * POST /v1/reports/token
 *
 * Body: { turnstile_response: string, scope: 'submit'|'history'|'delete', uuid_hash: string (64 hex) }
 * Returns: { token, expires_at, server_salt }
 *
 * Token payload binds {subject: uuid_hash} so subsequent submit/history/delete
 * requests must match the same uuid_hash (prevents cross-account IDOR).
 */
export async function handleToken(request: Request, env: Env): Promise<Response> {
  if (request.method !== 'POST') {
    return jsonError(405, 'method_not_allowed', 'POST required')
  }

  let body: TokenRequestBody
  try {
    body = await request.json() as TokenRequestBody
  } catch {
    return jsonError(400, 'validation_failed', 'invalid JSON body')
  }

  const { turnstile_response, scope, uuid_hash } = body
  if (!turnstile_response || typeof turnstile_response !== 'string') {
    return jsonError(400, 'validation_failed', 'turnstile_response required')
  }
  if (!scope || !VALID_SCOPES.has(scope as TokenPayload['scope'])) {
    return jsonError(400, 'validation_failed', `scope must be one of: ${[...VALID_SCOPES].join(', ')}`)
  }
  if (!uuid_hash || typeof uuid_hash !== 'string' || uuid_hash.length !== 64) {
    return jsonError(400, 'validation_failed', 'uuid_hash must be 64 hex chars')
  }

  try {
    const remoteip = request.headers.get('CF-Connecting-IP') ?? undefined
    await verifyTurnstile({
      secret: env.TURNSTILE_SECRET,
      response: turnstile_response,
      remoteip,
    })
  } catch (e) {
    if (e instanceof TurnstileError) {
      return jsonError(400, 'turnstile_failed', e.message)
    }
    return jsonError(500, 'turnstile_internal', 'verification service error')
  }

  const payload: TokenPayload = {
    subject: uuid_hash,  // ★ bound to device
    expires: Date.now() + TOKEN_TTL_SECONDS * 1000,
    scope: scope as TokenPayload['scope'],
  }
  const token = await signToken(payload, env.HMAC_KEY)

  return new Response(JSON.stringify({
    token,
    expires_at: Math.floor(payload.expires / 1000),
    server_salt: env.SERVER_SALT,
  }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  })
}

function jsonError(status: number, error: string, message: string): Response {
  return new Response(JSON.stringify({ error, message }), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })
}

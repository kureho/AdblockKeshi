import type { Env } from '../env'
import { verifyTurnstile, TurnstileError } from '../lib/turnstile'
import { signToken, type TokenPayload } from '../lib/hmac'

interface TokenRequestBody {
  turnstile_response?: string
  scope?: string
}

const VALID_SCOPES = new Set<TokenPayload['scope']>(['submit', 'history', 'delete'])
const TOKEN_TTL_SECONDS = 300  // 5 分

/**
 * POST /v1/reports/token
 *
 * Body: { turnstile_response: string, scope: 'submit'|'history'|'delete' }
 * Returns: { token, expires_at, server_salt }
 *
 * 1. Validate body shape
 * 2. Verify Turnstile challenge with Cloudflare
 * 3. Sign HMAC token (5-minute TTL)
 * 4. Return token + expires_at + server_salt
 *    (server_salt is returned so client can compute SHA-256(uuid+salt)
 *     for submit/history/delete request bodies)
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

  const { turnstile_response, scope } = body
  if (!turnstile_response || typeof turnstile_response !== 'string') {
    return jsonError(400, 'validation_failed', 'turnstile_response required')
  }
  if (!scope || !VALID_SCOPES.has(scope as TokenPayload['scope'])) {
    return jsonError(400, 'validation_failed', `scope must be one of: ${[...VALID_SCOPES].join(', ')}`)
  }

  // Turnstile server-side verify
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

  // subject placeholder; submit handler enforces actual uuid_hash from body
  const payload: TokenPayload = {
    subject: 'anonymous',
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

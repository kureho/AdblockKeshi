import type { Env } from '../env'
import { verifyToken } from '../lib/hmac'

interface HistoryBody {
  token?: string
  uuid_hash?: string
}

/**
 * POST /v1/reports/history
 * Body: { token, uuid_hash }
 * Returns: { items: [{id, url, memo, memo_redacted, status, created_at, ...}], fetched_at }
 * memo_redacted is derived by JOIN against abuse_log (reason='pii_redacted').
 */
export async function handleHistory(request: Request, env: Env): Promise<Response> {
  if (request.method !== 'POST') {
    return jsonError(405, 'method_not_allowed', 'POST required')
  }

  let body: HistoryBody
  try { body = await request.json() as HistoryBody }
  catch { return jsonError(400, 'validation_failed', 'invalid JSON') }

  if (!body.token || !body.uuid_hash) {
    return jsonError(400, 'validation_failed', 'token and uuid_hash required')
  }

  try {
    const payload = await verifyToken(body.token, env.HMAC_KEY)
    if (payload.scope !== 'history') return jsonError(401, 'unauthorized', 'wrong scope')
  } catch {
    return jsonError(401, 'unauthorized', 'invalid token')
  }

  const rows = await env.DB.prepare(`
    SELECT
      r.id, r.url, r.memo, r.status, r.created_at, r.validated_at, r.applied_at,
      EXISTS (
        SELECT 1 FROM abuse_log a
        WHERE a.identifier_hash = r.uuid_hash
          AND a.reason = 'pii_redacted'
          AND a.url = r.url
      ) AS memo_redacted
    FROM reports r WHERE r.uuid_hash = ?
    ORDER BY r.created_at DESC LIMIT 50
  `).bind(body.uuid_hash).all<any>()

  const items = (rows.results ?? []).map(r => ({
    id: r.id,
    url: r.url,
    memo: r.memo,
    memo_redacted: Boolean(r.memo_redacted),
    status: r.status,
    created_at: r.created_at,
    validated_at: r.validated_at,
    applied_at: r.applied_at,
  }))

  return new Response(JSON.stringify({
    items,
    fetched_at: Math.floor(Date.now() / 1000),
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

import type { Env } from '../env'
import { verifyToken } from '../lib/hmac'

interface DeleteBody {
  token?: string
  uuid_hash?: string
  url_path_hash?: string  // optional: specify a single URL to delete; null = all
}

/**
 * POST /v1/reports/delete
 *
 * Phase 2: INSERT into deletion_requests (status='pending'). The actual DELETE
 * is performed by `hourly-deletion-processor.yml` workflow (Plan C). spec rev4
 * §4 SLA: processed within 1 hour (well inside the 24h Privacy Policy commit).
 */
export async function handleDelete(request: Request, env: Env): Promise<Response> {
  if (request.method !== 'POST') {
    return jsonError(405, 'method_not_allowed', 'POST required')
  }

  let body: DeleteBody
  try { body = await request.json() as DeleteBody }
  catch { return jsonError(400, 'validation_failed', 'invalid JSON') }

  if (!body.token || !body.uuid_hash) {
    return jsonError(400, 'validation_failed', 'token and uuid_hash required')
  }

  try {
    const payload = await verifyToken(body.token, env.HMAC_KEY)
    if (payload.scope !== 'delete') return jsonError(401, 'unauthorized', 'wrong scope')
  } catch {
    return jsonError(401, 'unauthorized', 'invalid token')
  }

  const id = crypto.randomUUID()
  const now = Math.floor(Date.now() / 1000)

  await env.DB.prepare(`
    INSERT INTO deletion_requests (id, uuid_hash, url_path_hash, requested_at, status)
    VALUES (?, ?, ?, ?, ?)
  `).bind(id, body.uuid_hash, body.url_path_hash ?? null, now, 'pending').run()

  return new Response(JSON.stringify({
    id,
    status: 'pending',
    received_at: now,
    sla_seconds: 3600,
  }), {
    status: 202,
    headers: { 'Content-Type': 'application/json' },
  })
}

function jsonError(status: number, error: string, message: string): Response {
  return new Response(JSON.stringify({ error, message }), {
    status, headers: { 'Content-Type': 'application/json' },
  })
}

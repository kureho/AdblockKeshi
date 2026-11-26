import type { Env } from '../env'
import { verifyToken } from '../lib/hmac'
import { readJsonObject, isHex64, isStringWithin } from '../lib/request-body'

/** 1 つの uuid_hash が同時に抱えられる未処理の削除依頼の上限。 */
const MAX_PENDING_PER_UUID = 20

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

  const parsed = await readJsonObject(request)
  if (!parsed.ok) return parsed.response
  const body = parsed.body as DeleteBody

  if (!isStringWithin(body.token, 2048) || body.token === '' || !isHex64(body.uuid_hash)) {
    return jsonError(400, 'validation_failed', 'token and uuid_hash required')
  }
  if (body.url_path_hash !== undefined && body.url_path_hash !== null &&
      !isStringWithin(body.url_path_hash, 128)) {
    return jsonError(400, 'validation_failed', 'url_path_hash must be a string')
  }

  let bindUUIDHash: string
  try {
    const payload = await verifyToken(body.token, env.HMAC_KEY)
    if (payload.scope !== 'delete') return jsonError(401, 'unauthorized', 'wrong scope')
    if (payload.subject !== body.uuid_hash) return jsonError(401, 'unauthorized', 'token uuid_hash mismatch')
    // ★ IDOR防止: INSERT には token に bound された uuid_hash (payload.subject) を使う
    bindUUIDHash = payload.subject
  } catch {
    return jsonError(401, 'unauthorized', 'invalid token')
  }

  const now = Math.floor(Date.now() / 1000)
  const scope: string | null = (body.url_path_hash as string | null | undefined) ?? null

  // 同じ uuid_hash・同じ範囲（url_path_hash か全削除）の未処理依頼は 1 件にまとめる。
  // 1 文で「同じ範囲が未処理でない」かつ「未処理が上限未満」のときだけ追加する（原子的）。
  const newId = crypto.randomUUID()
  await env.DB.prepare(`
    INSERT INTO deletion_requests (id, uuid_hash, url_path_hash, requested_at, status)
    SELECT ?1, ?2, ?3, ?4, 'pending'
    WHERE NOT EXISTS (
            SELECT 1 FROM deletion_requests
             WHERE uuid_hash = ?2 AND status = 'pending' AND COALESCE(url_path_hash, '') = COALESCE(?3, ''))
      AND (SELECT COUNT(*) FROM deletion_requests WHERE uuid_hash = ?2 AND status = 'pending') < ?5
  `).bind(newId, bindUUIDHash, scope, now, MAX_PENDING_PER_UUID).run()

  const existing = await env.DB.prepare(`
    SELECT id FROM deletion_requests
     WHERE uuid_hash = ? AND status = 'pending' AND COALESCE(url_path_hash, '') = COALESCE(?, '')
     ORDER BY requested_at ASC LIMIT 1
  `).bind(bindUUIDHash, scope).first<{ id: string }>()

  if (!existing) {
    return jsonError(429, 'rate_limit_exceeded', 'too many pending deletion requests')
  }
  const id = existing.id

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

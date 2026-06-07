// Plan B Task 2.4 (L8 broken-site complaint receiver).
//
// POST /v1/reports/complaint
// Body: { token, uuid_hash, rule_candidate_id, reason? }
//
// Records a per-uuid complaint against a specific rule_candidate. Each uuid
// only counts once per rule (subsequent calls return 200 but do not double-
// count). Hourly cron (complaint-monitor.yml) reads abuse_log/broken_site to
// decide whether to roll a rule back.

import type { Env } from '../env'
import { verifyToken } from '../lib/hmac'

interface ComplaintBody {
  token?: string
  uuid_hash?: string
  rule_candidate_id?: string
  reason?: string
}

function jsonError(status: number, code: string, detail: string) {
  return new Response(JSON.stringify({ error: code, detail }), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })
}

export async function handleComplaint(request: Request, env: Env): Promise<Response> {
  if (request.method !== 'POST') {
    return jsonError(405, 'method_not_allowed', 'POST required')
  }

  let body: ComplaintBody
  try {
    body = (await request.json()) as ComplaintBody
  } catch {
    return jsonError(400, 'validation_failed', 'invalid JSON')
  }

  if (!body.token) return jsonError(400, 'validation_failed', 'token required')
  if (!body.uuid_hash || body.uuid_hash.length !== 64) {
    return jsonError(400, 'validation_failed', 'uuid_hash must be 64 hex chars')
  }
  if (!body.rule_candidate_id) {
    return jsonError(400, 'validation_failed', 'rule_candidate_id required')
  }
  if (body.reason && body.reason.length > 200) {
    return jsonError(400, 'validation_failed', 'reason too long')
  }

  try {
    const payload = await verifyToken(body.token, env.HMAC_KEY)
    if (payload.scope !== 'complaint') {
      return jsonError(401, 'unauthorized', 'wrong scope')
    }
    if (payload.subject !== body.uuid_hash) {
      return jsonError(401, 'unauthorized', 'token uuid_hash mismatch')
    }
  } catch {
    return jsonError(401, 'unauthorized', 'invalid or expired token')
  }

  const existing = await env.DB.prepare(
    `SELECT id, complaint_count FROM rule_candidates WHERE id = ?`
  )
    .bind(body.rule_candidate_id)
    .first<{ id: string; complaint_count: number }>()

  if (!existing) {
    return jsonError(404, 'not_found', 'rule_candidate not found')
  }

  // De-dupe: if this uuid already complained about this rule, return current
  // count without modifying anything.
  const dup = await env.DB.prepare(
    `SELECT 1 FROM abuse_log
      WHERE identifier_hash = ? AND target_id = ? AND reason = 'broken_site'
      LIMIT 1`
  )
    .bind(body.uuid_hash, body.rule_candidate_id)
    .first()

  if (dup) {
    return new Response(
      JSON.stringify({ ok: true, complaint_count: existing.complaint_count, deduped: true }),
      { status: 200, headers: { 'Content-Type': 'application/json' } }
    )
  }

  const now = Math.floor(Date.now() / 1000)
  await env.DB.prepare(
    `INSERT INTO abuse_log
       (identifier_hash, identifier_type, reason, url, target_id, created_at)
     VALUES (?, 'uuid', 'broken_site', ?, ?, ?)`
  )
    .bind(body.uuid_hash, body.reason ?? null, body.rule_candidate_id, now)
    .run()

  await env.DB.prepare(
    `UPDATE rule_candidates SET complaint_count = complaint_count + 1 WHERE id = ?`
  )
    .bind(body.rule_candidate_id)
    .run()

  return new Response(
    JSON.stringify({ ok: true, complaint_count: existing.complaint_count + 1 }),
    { status: 200, headers: { 'Content-Type': 'application/json' } }
  )
}

import type { Env } from '../env'
import { resolveReviewOutcome } from '../lib/review-outcome'

interface StatusBody {
  ids?: unknown
}

interface ReportRow {
  id: string
  status: string
  applied_at: number | null
  review_outcome: string | null
}

const MAX_IDS = 20
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

/**
 * POST /v1/reports/status
 * Body: { ids: string[] }  （1〜20件、UUID形式のみ、重複は除く）
 * Returns: { items: [{id, outcome}], fetched_at } のみ。url/memo/uuid_hash 等は返さない。
 *
 * 設計 tasks/a88-design-2026-09-27.md §3:
 * 報告 ID は submit 応答でのみ手に入る乱数（crypto.randomUUID()）＝知っている本人だけが引ける前提。
 * ロボット確認は不要。回数制限は「1回20件まで・主キー検索のみ」に留め、
 * 別の課金・上限つき機能（Rate Limiting binding 等）は追加しない。
 *
 * 存在しない ID は items から単純に外れる。認可を持たない読み取りなので
 * 「存在しない」と「他人の ID」を区別する仕組みはそもそも無い＝どちらも同じ見え方になる。
 */
export async function handleReportStatus(request: Request, env: Env): Promise<Response> {
  if (request.method !== 'POST') {
    return jsonError(405, 'method_not_allowed', 'POST required')
  }

  let body: StatusBody
  try {
    body = await request.json() as StatusBody
  } catch {
    return jsonError(400, 'validation_failed', 'invalid JSON')
  }

  if (!Array.isArray(body.ids) || body.ids.length === 0) {
    return jsonError(400, 'validation_failed', 'ids must be a non-empty array')
  }
  if (body.ids.length > MAX_IDS) {
    return jsonError(400, 'validation_failed', `ids must be ${MAX_IDS} or fewer`)
  }
  for (const id of body.ids) {
    if (typeof id !== 'string' || !UUID_RE.test(id)) {
      return jsonError(400, 'validation_failed', 'ids must all be UUID strings')
    }
  }

  // D1 を読む前にここまでの検証を必ず終える。重複除去は検証の後（件数上限は生の配列に対してかける）。
  const deduped = Array.from(new Set(body.ids as string[]))

  const placeholders = deduped.map(() => '?').join(',')
  const rows = await env.DB.prepare(
    `SELECT id, status, applied_at, review_outcome FROM reports WHERE id IN (${placeholders})`
  ).bind(...deduped).all<ReportRow>()

  const items = (rows.results ?? []).map((r) => ({
    id: r.id,
    outcome: resolveReviewOutcome({
      status: r.status,
      appliedAt: r.applied_at,
      reviewOutcome: r.review_outcome,
    }),
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

// Plan B Task 2.3 (L7 β→stable): weekly cron. Promotes beta candidates that
// have been live for ≥ 7 days with zero complaints to status='stable'.

import { d1Query, type D1Env } from '../lib/d1-rest'

export interface BetaPromotionDeps {
  fetch: typeof globalThis.fetch
  now: () => number
}

export interface BetaPromotionResult {
  promoted: number
}

const DWELL_SECONDS = 7 * 86_400

export async function runBetaPromotion(
  env: D1Env,
  deps: BetaPromotionDeps
): Promise<BetaPromotionResult> {
  const now = deps.now()
  const cutoff = now - DWELL_SECONDS

  const rows = (await d1Query(
    env,
    deps.fetch,
    `SELECT id FROM rule_candidates
      WHERE status = 'beta'
        AND beta_started_at IS NOT NULL
        AND beta_started_at <= ?
        AND complaint_count = 0
      LIMIT 10000`,
    [cutoff]
  )) as Array<{ id: string }>

  if (rows.length === 0) {
    return { promoted: 0 }
  }

  const ids = rows.map((r) => r.id)
  const placeholders = ids.map(() => '?').join(',')
  await d1Query(
    env,
    deps.fetch,
    `UPDATE rule_candidates
        SET status = 'stable', stable_started_at = ?
      WHERE id IN (${placeholders})`,
    [now, ...ids]
  )
  return { promoted: ids.length }
}

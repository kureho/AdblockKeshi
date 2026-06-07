// Plan B Task 2.4 (L8 rollback): hourly via complaint-monitor.yml.
// Rolls back rules with too many unique complaints (β: ≥2, stable: ≥3) and
// puts the candidate in 30-day cooldown so it can't be re-aggregated.

import { chunked, d1Query, D1_MAX_IN_PARAMS, type D1Env } from '../lib/d1-rest'

const COOLDOWN_SECONDS = 30 * 86_400

export interface ComplaintRollbackDeps {
  fetch: typeof globalThis.fetch
  now: () => number
}

export interface ComplaintRollbackResult {
  rolled_back: number
}

export async function runComplaintRollback(
  env: D1Env,
  deps: ComplaintRollbackDeps
): Promise<ComplaintRollbackResult> {
  const rows = (await d1Query(
    env,
    deps.fetch,
    `SELECT id FROM rule_candidates
      WHERE (status = 'beta' AND complaint_count >= 2)
         OR (status = 'stable' AND complaint_count >= 3)
      LIMIT 10000`
  )) as Array<{ id: string }>

  if (rows.length === 0) return { rolled_back: 0 }

  const now = deps.now()
  const cooldownUntil = now + COOLDOWN_SECONDS
  const ids = rows.map((r) => r.id)
  await chunked(ids, D1_MAX_IN_PARAMS, async (chunk) => {
    const placeholders = chunk.map(() => '?').join(',')
    await d1Query(
      env,
      deps.fetch,
      `UPDATE rule_candidates
          SET status = 'rejected_rollback', cooldown_until = ?
        WHERE id IN (${placeholders})`,
      [cooldownUntil, ...chunk]
    )
  })
  return { rolled_back: ids.length }
}

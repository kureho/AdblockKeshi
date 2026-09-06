// Plan B Task 1.3 (L3): runs hourly-ish via daily-validation.yml.
// Pulls aggregating rule_candidates, looks up their domains in the Tranco
// Top 100k set (suffix-aware, in-memory), and updates each candidate's status:
//   - critical-list hit → rejected_critical
//   - tranco hit          → kureho_queue (manual review)
//   - neither             → validating  (next layer L4)

import { chunked, d1Query, D1_MAX_IN_PARAMS, type D1Env } from '../lib/d1-rest'
import { decideL3 } from '../../workers/src/lib/l3-decision'

export interface TrancoCheckDeps {
  fetch: typeof globalThis.fetch
  /**
   * Tranco 上位ドメイン集合。ワークフローが CSV を落として渡す。
   * 2026-09-06 まで D1 の tranco_top_1m を引いていたが、その週次同期が
   * rows_written 無料枠の 4 倍を消費していたため in-memory に移した。
   */
  loadTrancoSet: () => Promise<Set<string>>
}

export interface TrancoCheckResult {
  passed: number
  queued: number
  rejected: number
}

interface CandidateRow {
  id: string
  domain: string
}

export async function runTrancoCheck(
  env: D1Env,
  deps: TrancoCheckDeps
): Promise<TrancoCheckResult> {
  const candidates = (await d1Query(
    env,
    deps.fetch,
    `SELECT id, domain FROM rule_candidates WHERE status = 'aggregating' LIMIT 10000`
  )) as CandidateRow[]

  if (candidates.length === 0) {
    return { passed: 0, queued: 0, rejected: 0 }
  }

  const trancoSet = await deps.loadTrancoSet()
  const decisions = candidates.map((c) => decideL3(c, trancoSet))

  const groups = {
    validating: decisions.filter((d) => d.next_status === 'validating'),
    kureho_queue: decisions.filter((d) => d.next_status === 'kureho_queue'),
    rejected_critical: decisions.filter((d) => d.next_status === 'rejected_critical'),
  }

  for (const [status, group] of Object.entries(groups)) {
    if (group.length === 0) continue
    const ids = group.map((d) => d.id)
    const l3 = group[0].l3_check
    await chunked(ids, D1_MAX_IN_PARAMS, async (chunk) => {
      const placeholders = chunk.map(() => '?').join(',')
      await d1Query(
        env,
        deps.fetch,
        `UPDATE rule_candidates SET status = ?, l3_check = ? WHERE id IN (${placeholders})`,
        [status, l3, ...chunk]
      )
    })
  }

  return {
    passed: groups.validating.length,
    queued: groups.kureho_queue.length,
    rejected: groups.rejected_critical.length,
  }
}

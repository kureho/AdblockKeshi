// Plan B Task 2.1 (L5 CDN protection): filters candidates with status='validating'.
// Runs from daily-validation.yml between tranco-check and playwright-validate.

import { d1Query, type D1Env } from '../lib/d1-rest'
import { decideL5 } from '../../workers/src/lib/l5-decision'

export interface CdnCheckDeps {
  fetch: typeof globalThis.fetch
}

export interface CdnCheckResult {
  passed: number
  rejected: number
}

interface CandidateRow {
  id: string
  domain: string
}

export async function runCdnCheck(
  env: D1Env,
  deps: CdnCheckDeps
): Promise<CdnCheckResult> {
  const candidates = (await d1Query(
    env,
    deps.fetch,
    `SELECT id, domain FROM rule_candidates WHERE status = 'validating' LIMIT 10000`
  )) as CandidateRow[]

  if (candidates.length === 0) {
    return { passed: 0, rejected: 0 }
  }

  const decisions = candidates.map(decideL5)
  const groups = {
    validating: decisions.filter((d) => d.next_status === 'validating'),
    rejected_cdn: decisions.filter((d) => d.next_status === 'rejected_cdn'),
  }

  for (const [status, group] of Object.entries(groups)) {
    if (group.length === 0) continue
    const ids = group.map((d) => d.id)
    const l5 = group[0].l5_check
    const placeholders = ids.map(() => '?').join(',')
    await d1Query(
      env,
      deps.fetch,
      `UPDATE rule_candidates SET status = ?, l5_check = ? WHERE id IN (${placeholders})`,
      [status, l5, ...ids]
    )
  }

  return {
    passed: groups.validating.length,
    rejected: groups.rejected_cdn.length,
  }
}

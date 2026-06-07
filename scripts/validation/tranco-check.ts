// Plan B Task 1.3 (L3): runs hourly-ish via daily-validation.yml.
// Pulls aggregating rule_candidates, looks up their domains in tranco_top_1m
// (suffix-aware), and updates each candidate's status:
//   - critical-list hit → rejected_critical
//   - tranco hit          → kureho_queue (manual review)
//   - neither             → validating  (next layer L4)

import { d1Query, type D1Env } from '../lib/d1-rest'
import { decideL3 } from '../../workers/src/lib/l3-decision'

export interface TrancoCheckDeps {
  fetch: typeof globalThis.fetch
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

function buildSuffixLookupKeys(domains: string[]): string[] {
  const keys = new Set<string>()
  for (const d of domains) {
    keys.add(d)
    const parts = d.split('.')
    for (let i = 1; i < parts.length; i++) {
      const suffix = parts.slice(i).join('.')
      if (suffix.includes('.')) keys.add(suffix)
    }
  }
  return [...keys]
}

async function loadTrancoHits(
  env: D1Env,
  fetchFn: typeof fetch,
  candidates: CandidateRow[]
): Promise<Set<string>> {
  const lookupKeys = buildSuffixLookupKeys(candidates.map((c) => c.domain))
  if (lookupKeys.length === 0) return new Set()
  const placeholders = lookupKeys.map(() => '?').join(',')
  const rows = await d1Query(
    env,
    fetchFn,
    `SELECT domain FROM tranco_top_1m WHERE domain IN (${placeholders})`,
    lookupKeys
  )
  return new Set(rows.map((r: any) => r.domain))
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

  const trancoHits = await loadTrancoHits(env, deps.fetch, candidates)
  const decisions = candidates.map((c) => decideL3(c, trancoHits))

  const groups = {
    validating: decisions.filter((d) => d.next_status === 'validating'),
    kureho_queue: decisions.filter((d) => d.next_status === 'kureho_queue'),
    rejected_critical: decisions.filter((d) => d.next_status === 'rejected_critical'),
  }

  for (const [status, group] of Object.entries(groups)) {
    if (group.length === 0) continue
    const ids = group.map((d) => d.id)
    const l3 = group[0].l3_check
    const placeholders = ids.map(() => '?').join(',')
    await d1Query(
      env,
      deps.fetch,
      `UPDATE rule_candidates SET status = ?, l3_check = ? WHERE id IN (${placeholders})`,
      [status, l3, ...ids]
    )
  }

  return {
    passed: groups.validating.length,
    queued: groups.kureho_queue.length,
    rejected: groups.rejected_critical.length,
  }
}

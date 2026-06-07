// Plan B Task 4.2: build docs/cdn/rules-reported.json from stable rule
// candidates. Pulled by weekly-cdn-sync.yml which then git-commits the file.

import { writeFileSync } from 'node:fs'
import { d1Query, type D1Env } from '../lib/d1-rest'

export interface StableRuleRow {
  id: string
  rule_text: string
}

export function buildReportedRulesJson(rows: StableRuleRow[]): string {
  const flat: any[] = []
  for (const r of rows) {
    if (!r.rule_text) continue
    try {
      const parsed = JSON.parse(r.rule_text)
      if (Array.isArray(parsed)) {
        for (const rule of parsed) flat.push(rule)
      }
    } catch {
      // Skip malformed rule_text rather than poison the entire CDN file.
    }
  }
  return JSON.stringify(flat)
}

export interface ReportedRulesBuildDeps {
  fetch: typeof globalThis.fetch
  outputPath: string
}

export interface ReportedRulesBuildResult {
  rows_consumed: number
  rules_emitted: number
}

export async function runReportedRulesBuild(
  env: D1Env,
  deps: ReportedRulesBuildDeps
): Promise<ReportedRulesBuildResult> {
  const rows = (await d1Query(
    env,
    deps.fetch,
    `SELECT id, rule_text FROM rule_candidates WHERE status = 'stable' LIMIT 200000`
  )) as StableRuleRow[]
  const json = buildReportedRulesJson(rows)
  writeFileSync(deps.outputPath, json)
  const rulesEmitted = JSON.parse(json).length as number
  return { rows_consumed: rows.length, rules_emitted: rulesEmitted }
}

// Plan B Task 4.2: build docs/cdn/rules-reported.json from stable rule
// candidates. Pulled by weekly-cdn-sync.yml which then git-commits the file.
//
// Plan C Chunk 5: also patches docs/cdn/version.json with
// `reported.{rule_count, added_last_month}` so that ContentView's moat row
// reflects the actual cumulative + monthly-delta numbers.

import { readFileSync, writeFileSync } from 'node:fs'
import { d1Query, type D1Env } from '../lib/d1-rest'

export interface StableRuleRow {
  id: string
  rule_text: string
}

export interface ReportedMetrics {
  rule_count: number
  added_last_month: number
}

function flattenRules(rows: StableRuleRow[]): unknown[] {
  const flat: unknown[] = []
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
  return flat
}

export function buildReportedRulesJson(rows: StableRuleRow[]): string {
  return JSON.stringify(flattenRules(rows))
}

export function computeReportedMetrics(
  allStable: StableRuleRow[],
  recentlyStable: StableRuleRow[]
): ReportedMetrics {
  return {
    rule_count: flattenRules(allStable).length,
    added_last_month: flattenRules(recentlyStable).length,
  }
}

/**
 * Merge the freshly computed reported metrics into an existing version.json
 * payload, preserving every other field. Throws if the input is not valid
 * JSON; callers (the CLI runner / workflow) treat that as fatal.
 */
export function applyReportedToVersionJson(
  versionJson: string,
  metrics: ReportedMetrics
): string {
  const parsed = JSON.parse(versionJson) as Record<string, unknown>
  parsed.reported = metrics
  return JSON.stringify(parsed, null, 2) + '\n'
}

export interface ReportedRulesBuildDeps {
  fetch: typeof globalThis.fetch
  outputPath: string
  /** Path to docs/cdn/version.json. The file's `reported` section is updated. */
  versionJsonPath: string
  /** Returns the current unix timestamp (seconds). Injected for tests. */
  now: () => number
}

export interface ReportedRulesBuildResult {
  rows_consumed: number
  rules_emitted: number
  reported: ReportedMetrics
}

export async function runReportedRulesBuild(
  env: D1Env,
  deps: ReportedRulesBuildDeps
): Promise<ReportedRulesBuildResult> {
  const recentCutoff = deps.now() - 30 * 24 * 3600
  const stableRows = (await d1Query(
    env,
    deps.fetch,
    `SELECT id, rule_text FROM rule_candidates WHERE status = 'stable' LIMIT 200000`
  )) as StableRuleRow[]
  const recentRows = (await d1Query(
    env,
    deps.fetch,
    `SELECT id, rule_text FROM rule_candidates
       WHERE status = 'stable' AND stable_started_at >= ?
       LIMIT 200000`,
    [recentCutoff]
  )) as StableRuleRow[]

  const rulesJson = buildReportedRulesJson(stableRows)
  writeFileSync(deps.outputPath, rulesJson)

  const metrics = computeReportedMetrics(stableRows, recentRows)
  const versionJsonRaw = readFileSync(deps.versionJsonPath, 'utf-8')
  writeFileSync(
    deps.versionJsonPath,
    applyReportedToVersionJson(versionJsonRaw, metrics)
  )

  return {
    rows_consumed: stableRows.length,
    rules_emitted: JSON.parse(rulesJson).length as number,
    reported: metrics,
  }
}

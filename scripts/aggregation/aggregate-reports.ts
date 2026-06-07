// Plan B Task 1.2 (L2 threshold): hourly aggregation script.
//
// Reads pending reports from D1, groups them by (domain, url_path_hash),
// inserts rule_candidates for groups passing the threshold, and updates
// reports.status='aggregated' for the consumed reports.
//
// Runs under Node.js in GitHub Actions (hourly-aggregation.yml). The D1
// REST API is called via fetch with a Cloudflare API token.

import {
  computeAggregations,
  type PendingReport,
} from '../../workers/src/lib/aggregation-threshold'
import { d1Query, type D1Env } from '../lib/d1-rest'

export type AggregationEnv = D1Env

export interface AggregationDeps {
  fetch: typeof globalThis.fetch
  uuidv4: () => string
  now: () => number
}

export interface AggregationRunResult {
  candidates_created: number
  reports_aggregated: number
}

export async function runAggregation(
  env: AggregationEnv,
  deps: AggregationDeps
): Promise<AggregationRunResult> {
  const rows = await d1Query(
    env,
    deps.fetch,
    `SELECT id, uuid_hash, ip_hash, domain, url, url_path_hash, memo, created_at
       FROM reports
      WHERE status = 'pending'
      ORDER BY created_at ASC
      LIMIT 10000`
  )

  const reports: PendingReport[] = rows.map((r) => ({
    id: r.id,
    uuid_hash: r.uuid_hash,
    ip_hash: r.ip_hash,
    domain: r.domain,
    url: r.url,
    url_path_hash: r.url_path_hash,
    memo: r.memo,
    created_at: r.created_at,
  }))

  const aggregations = computeAggregations(reports, deps.now())
  if (aggregations.length === 0) {
    return { candidates_created: 0, reports_aggregated: 0 }
  }

  const consumedIds: string[] = []
  for (const a of aggregations) {
    const id = deps.uuidv4()
    // rule_text is intentionally empty here. L6 (playwright-validate) detects
    // the actual ad selector and replaces this with the proper Content
    // Blocker JSON before status transitions to 'beta'.
    await d1Query(
      env,
      deps.fetch,
      `INSERT INTO rule_candidates (
         id, domain, selector, rule_text,
         unique_uuid_count, unique_ip_count,
         first_reported_at, last_reported_at,
         status, complaint_count
       ) VALUES (?, ?, NULL, '', ?, ?, ?, ?, 'aggregating', 0)`,
      [
        id,
        a.domain,
        a.unique_uuid_count,
        a.unique_ip_count,
        a.first_reported_at,
        a.last_reported_at,
      ]
    )
    consumedIds.push(...a.report_ids)
  }

  if (consumedIds.length > 0) {
    const placeholders = consumedIds.map(() => '?').join(',')
    await d1Query(
      env,
      deps.fetch,
      `UPDATE reports SET status = 'aggregated' WHERE id IN (${placeholders})`,
      consumedIds
    )
  }

  return {
    candidates_created: aggregations.length,
    reports_aggregated: consumedIds.length,
  }
}

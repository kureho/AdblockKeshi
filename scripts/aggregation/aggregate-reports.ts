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
import { chunked, d1Query, D1_MAX_IN_PARAMS, type D1Env } from '../lib/d1-rest'
// 層B: 集約時点で reports.url を eTLD+1 に縮約するために使用
import { normalizeURL } from '../../workers/src/lib/url-redact'

export type AggregationEnv = D1Env

export interface AggregationDeps {
  fetch: typeof globalThis.fetch
  uuidv4: () => string
  now: () => number
  /** 信頼レポーター(kureho 自身等)の uuid_hash 集合。L2 閾値をバイパスさせる。 */
  trustedUuidHashes?: Set<string>
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
    // D-lite: 自動改善パイプラインの母集団は「Safari で見た かつ Content Blocker が有効だった」
    // 報告のみ。other_app は Safari 用フィルタでは原理的に消せず、blocker OFF はフィルタの
    // 取りこぼしではないため、どちらも cosmetic rule 生成の材料にならない。
    // 旧クライアントの報告は status='observation_legacy' で入るので status でも除外されるが、
    // ここでも条件を効かせて二重に塞ぐ。
    `SELECT id, uuid_hash, ip_hash, domain, url, url_path_hash, memo, created_at
       FROM reports
      WHERE status = 'pending'
        AND seen_in = 'safari'
        AND blocker_enabled = 1
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

  const aggregations = computeAggregations(reports, deps.now(), {
    trustedUuidHashes: deps.trustedUuidHashes,
  })
  if (aggregations.length === 0) {
    return { candidates_created: 0, reports_aggregated: 0 }
  }

  let reports_aggregated = 0
  for (const a of aggregations) {
    const id = deps.uuidv4()
    // rule_text is intentionally empty here. L6 (playwright-validate) detects
    // the actual ad selector and replaces this with the proper Content
    // Blocker JSON before status transitions to 'beta'.
    await d1Query(
      env,
      deps.fetch,
      `INSERT INTO rule_candidates (
         id, domain, url, selector, rule_text,
         unique_uuid_count, unique_ip_count,
         first_reported_at, last_reported_at,
         status, complaint_count
       ) VALUES (?, ?, ?, NULL, '', ?, ?, ?, ?, 'aggregating', 0)`,
      [
        id,
        a.domain,
        a.url, // 完全 URL のまま（L6 が開くため縮約しない）
        a.unique_uuid_count,
        a.unique_ip_count,
        a.first_reported_at,
        a.last_reported_at,
      ]
    )
    // 層B: このグループの reports.url を eTLD+1 に縮約しつつ status='aggregated'（chunked）
    // 1 グループの report_ids が D1_MAX_IN_PARAMS(=90) を超え得るため chunk 分割必須
    const redacted = normalizeURL(a.url)
    await chunked(a.report_ids, D1_MAX_IN_PARAMS, async (chunk) => {
      const placeholders = chunk.map(() => '?').join(',')
      await d1Query(
        env,
        deps.fetch,
        `UPDATE reports SET status = 'aggregated', url = ? WHERE id IN (${placeholders})`,
        [redacted, ...chunk]
      )
    })
    reports_aggregated += a.report_ids.length
  }

  return {
    candidates_created: aggregations.length,
    reports_aggregated,
  }
}

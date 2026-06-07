// Plan B Task 1.3 weekly Tranco list sync.
//
// Downloads the latest Tranco Top 1M CSV, parses it, then refreshes the
// tranco_top_1m D1 table. Runs from weekly-tranco-sync.yml (timeout 30 min).
// The CSV URL is configurable so weekly runs can pin to "latest" while tests
// can stub a small fixture.

import { d1Query, type D1Env } from '../lib/d1-rest'

export interface TrancoRow {
  rank: number
  domain: string
}

export function parseTrancoCsv(csv: string): TrancoRow[] {
  const out: TrancoRow[] = []
  for (const raw of csv.split('\n')) {
    const line = raw.trim()
    if (!line) continue
    const comma = line.indexOf(',')
    if (comma < 0) continue
    const rankStr = line.slice(0, comma).trim()
    const domain = line.slice(comma + 1).trim()
    const rank = Number.parseInt(rankStr, 10)
    if (!Number.isFinite(rank) || !domain) continue
    out.push({ rank, domain })
  }
  return out
}

export interface TrancoSyncDeps {
  fetch: typeof globalThis.fetch
  now: () => number
  /** Loader resolves to raw CSV text (post-unzip). */
  loadCsv: () => Promise<string>
  batchSize?: number
  /** Cap rows imported (Tranco gives 1M, top 100k is plenty for L3). */
  maxRows?: number
}

export interface TrancoSyncResult {
  rows_inserted: number
}

// D1 caps bound parameters at 100 per query. Each row binds 3 params
// (domain, rank, synced_at), so the safe max batch is 33. Use 30 for headroom.
const DEFAULT_BATCH = 30
// L3 only needs to know if a domain is a "big site". Top 100k of Tranco covers
// every site with meaningful daily traffic.
const DEFAULT_MAX_ROWS = 100_000

export async function runTrancoSync(
  env: D1Env,
  deps: TrancoSyncDeps
): Promise<TrancoSyncResult> {
  const csv = await deps.loadCsv()
  const parsed = parseTrancoCsv(csv)
  const maxRows = deps.maxRows ?? DEFAULT_MAX_ROWS
  const rows = parsed.length > maxRows ? parsed.slice(0, maxRows) : parsed

  await d1Query(env, deps.fetch, `DELETE FROM tranco_top_1m`)

  const batchSize = deps.batchSize ?? DEFAULT_BATCH
  const syncedAt = deps.now()
  for (let i = 0; i < rows.length; i += batchSize) {
    const chunk = rows.slice(i, i + batchSize)
    const placeholders = chunk.map(() => '(?, ?, ?)').join(',')
    const params: any[] = []
    for (const r of chunk) {
      params.push(r.domain, r.rank, syncedAt)
    }
    await d1Query(
      env,
      deps.fetch,
      `INSERT INTO tranco_top_1m (domain, rank, synced_at) VALUES ${placeholders}`,
      params
    )
  }

  return { rows_inserted: rows.length }
}

/** Convenience HTTP loader for use from CLI runners. Throws on non-2xx. */
export function httpLoader(url: string, fetchFn: typeof globalThis.fetch) {
  return async (): Promise<string> => {
    const res = await fetchFn(url)
    if (!res.ok) {
      throw new Error(`Tranco CSV download failed: HTTP ${res.status}`)
    }
    return res.text()
  }
}

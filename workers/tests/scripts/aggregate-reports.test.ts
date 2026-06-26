// Plan B Task 1.2: orchestrator test (mocks D1 REST API via fetch stub).

import { describe, expect, test, vi } from 'vitest'
import { runAggregation } from '../../../scripts/aggregation/aggregate-reports'

interface FetchCall {
  url: string
  body: { sql: string; params: any[] }
}

function makeFetchMock(
  responses: Array<{ rows?: any[]; success?: boolean; error?: string }>
): { fetch: typeof fetch; calls: FetchCall[] } {
  const calls: FetchCall[] = []
  let idx = 0
  const fetchFn = (async (url: string, init: any) => {
    const body = JSON.parse(init.body)
    calls.push({ url, body })
    const r = responses[idx++] ?? { rows: [] }
    const payload = r.error
      ? { success: false, errors: [{ message: r.error }] }
      : {
          success: r.success ?? true,
          result: [{ results: r.rows ?? [], success: true }],
        }
    return new Response(JSON.stringify(payload), { status: 200 })
  }) as unknown as typeof fetch
  return { fetch: fetchFn, calls }
}

const ENV = {
  CF_API_TOKEN: 'test-token',
  CF_ACCOUNT_ID: 'acct123',
  CF_DATABASE_ID: 'db456',
}

const NOW = 2_000_000

describe('runAggregation', () => {
  test('no pending reports → no candidates created', async () => {
    const { fetch, calls } = makeFetchMock([{ rows: [] }])
    const result = await runAggregation(ENV, {
      fetch,
      uuidv4: () => 'rc-uuid',
      now: () => NOW,
    })
    expect(result).toEqual({ candidates_created: 0, reports_aggregated: 0 })
    expect(calls).toHaveLength(1)
    expect(calls[0].body.sql).toMatch(/SELECT/i)
    expect(calls[0].body.sql).toMatch(/status\s*=\s*'pending'/i)
  })

  test('below threshold → no candidates created (no writes)', async () => {
    const rows = [
      { id: 'r1', uuid_hash: 'u1', ip_hash: 'i1', domain: 'ex.com', url: 'https://ex.com/a', url_path_hash: 'p1', memo: null, created_at: NOW - 100 },
      { id: 'r2', uuid_hash: 'u2', ip_hash: 'i2', domain: 'ex.com', url: 'https://ex.com/a', url_path_hash: 'p1', memo: null, created_at: NOW - 50 },
    ]
    const { fetch, calls } = makeFetchMock([{ rows }])
    const result = await runAggregation(ENV, { fetch, uuidv4: () => 'rc1', now: () => NOW })
    expect(result.candidates_created).toBe(0)
    expect(result.reports_aggregated).toBe(0)
    expect(calls).toHaveLength(1) // only the SELECT
  })

  test('above threshold → INSERT rule_candidate + UPDATE reports.status', async () => {
    const rows = [
      { id: 'r1', uuid_hash: 'u1', ip_hash: 'i1', domain: 'ex.com', url: 'https://ex.com/a', url_path_hash: 'p1', memo: null, created_at: NOW - 300 },
      { id: 'r2', uuid_hash: 'u2', ip_hash: 'i2', domain: 'ex.com', url: 'https://ex.com/a', url_path_hash: 'p1', memo: null, created_at: NOW - 200 },
      { id: 'r3', uuid_hash: 'u3', ip_hash: 'i1', domain: 'ex.com', url: 'https://ex.com/a', url_path_hash: 'p1', memo: null, created_at: NOW - 100 },
    ]
    const { fetch, calls } = makeFetchMock([{ rows }, { rows: [] }, { rows: [] }])
    let uuidIdx = 0
    const result = await runAggregation(ENV, {
      fetch,
      uuidv4: () => `rc-${++uuidIdx}`,
      now: () => NOW,
    })
    expect(result.candidates_created).toBe(1)
    expect(result.reports_aggregated).toBe(3)
    // 3 calls: SELECT, INSERT, UPDATE（per-group）
    expect(calls).toHaveLength(3)
    expect(calls[1].body.sql).toMatch(/INSERT INTO rule_candidates/i)
    expect(calls[1].body.params).toContain('rc-1')
    expect(calls[1].body.params).toContain('ex.com')
    // L6 (playwright-validate) navigates rule_candidates.url, so the URL must
    // round-trip into the INSERT — regressions break the whole L6 path silently.
    expect(calls[1].body.params).toContain('https://ex.com/a')
    // 層B: per-group UPDATE で reports.url を eTLD+1 に縮約しつつ status='aggregated'
    const upd = calls.find((c) => /UPDATE reports/i.test(c.body.sql))!
    expect(upd.body.sql).toMatch(/aggregated/)
    expect(upd.body.sql).toMatch(/url\s*=\s*\?/i)
    // params[0] = 縮約 URL（normalizeURL('https://ex.com/a') === 'ex.com'）、以降が ids
    expect(upd.body.params[0]).toBe('ex.com')
    expect(upd.body.params.slice(1).sort()).toEqual(['r1', 'r2', 'r3'])
  })

  test('two domains above threshold → two INSERTs + two per-group UPDATEs', async () => {
    const rows = [
      // domain A
      { id: 'a1', uuid_hash: 'u1', ip_hash: 'i1', domain: 'a.com', url: 'https://a.com/x', url_path_hash: 'pa', memo: null, created_at: NOW - 300 },
      { id: 'a2', uuid_hash: 'u2', ip_hash: 'i2', domain: 'a.com', url: 'https://a.com/x', url_path_hash: 'pa', memo: null, created_at: NOW - 200 },
      { id: 'a3', uuid_hash: 'u3', ip_hash: 'i1', domain: 'a.com', url: 'https://a.com/x', url_path_hash: 'pa', memo: null, created_at: NOW - 100 },
      // domain B
      { id: 'b1', uuid_hash: 'v1', ip_hash: 'j1', domain: 'b.com', url: 'https://b.com/y', url_path_hash: 'pb', memo: null, created_at: NOW - 250 },
      { id: 'b2', uuid_hash: 'v2', ip_hash: 'j2', domain: 'b.com', url: 'https://b.com/y', url_path_hash: 'pb', memo: null, created_at: NOW - 150 },
      { id: 'b3', uuid_hash: 'v3', ip_hash: 'j1', domain: 'b.com', url: 'https://b.com/y', url_path_hash: 'pb', memo: null, created_at: NOW - 50 },
    ]
    // 層B: SELECT + 2 INSERT + 2 per-group UPDATE = 5 calls
    const { fetch, calls } = makeFetchMock([
      { rows },
      { rows: [] },
      { rows: [] },
      { rows: [] },
      { rows: [] },
    ])
    let i = 0
    const result = await runAggregation(ENV, {
      fetch,
      uuidv4: () => `rc-${++i}`,
      now: () => NOW,
    })
    expect(result.candidates_created).toBe(2)
    expect(result.reports_aggregated).toBe(6)
    expect(calls).toHaveLength(5)
    // グループ A の per-group UPDATE を id で特定
    const updA = calls.find(
      (c) => /UPDATE reports/i.test(c.body.sql) && c.body.params.includes('a1')
    )!
    // グループ B の per-group UPDATE を id で特定
    const updB = calls.find(
      (c) => /UPDATE reports/i.test(c.body.sql) && c.body.params.includes('b1')
    )!
    // params[0] = 縮約 URL（normalizeURL('https://a.com/x') === 'a.com'）
    expect(updA.body.params[0]).toBe('a.com')
    expect(updA.body.params.slice(1).sort()).toEqual(['a1', 'a2', 'a3'])
    // params[0] = 縮約 URL（normalizeURL('https://b.com/y') === 'b.com'）
    expect(updB.body.params[0]).toBe('b.com')
    expect(updB.body.params.slice(1).sort()).toEqual(['b1', 'b2', 'b3'])
  })

  test('D1 returns error → throws with diagnostic', async () => {
    const { fetch } = makeFetchMock([{ error: 'auth failed' }])
    await expect(
      runAggregation(ENV, { fetch, uuidv4: () => 'x', now: () => NOW })
    ).rejects.toThrow(/auth failed/)
  })
})

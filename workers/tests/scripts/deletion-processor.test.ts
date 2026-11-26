// Plan B Task 4.1 deletion processor.

import { describe, expect, test } from 'vitest'
import { runDeletionProcessor } from '../../../scripts/deletion/deletion-processor'

function makeD1FetchMock(responses: Array<{ rows?: any[]; error?: string }>) {
  const calls: Array<{ url: string; body: any }> = []
  let idx = 0
  const fetchFn = (async (url: string, init: any) => {
    calls.push({ url, body: JSON.parse(init.body) })
    const r = responses[idx++] ?? { rows: [] }
    const payload = r.error
      ? { success: false, errors: [{ message: r.error }] }
      : { success: true, result: [{ results: r.rows ?? [], success: true }] }
    return new Response(JSON.stringify(payload), { status: 200 })
  }) as unknown as typeof fetch
  return { fetch: fetchFn, calls }
}

const ENV = { CF_API_TOKEN: 't', CF_ACCOUNT_ID: 'a', CF_DATABASE_ID: 'd' }
const NOW = 100_000

describe('runDeletionProcessor', () => {
  test('no pending requests → noop', async () => {
    const { fetch, calls } = makeD1FetchMock([{ rows: [] }, { rows: [] }])
    const r = await runDeletionProcessor(ENV, { fetch, now: () => NOW })
    expect(r).toEqual({ processed: 0 })
    expect(calls).toHaveLength(2)
  })

  test('full-deletion (url_path_hash=null) cleans reports + abuse_log + bans', async () => {
    const requests = [
      { id: 'd1', uuid_hash: 'u1', url_path_hash: null },
    ]
    const { fetch, calls } = makeD1FetchMock([
      { rows: [] }, // reset stale claims
      { rows: requests }, // claim (RETURNING)
      { rows: [] }, // DELETE reports
      { rows: [] }, // DELETE abuse_log
      { rows: [] }, // DELETE bans
      { rows: [] }, // UPDATE deletion_requests
    ])
    const r = await runDeletionProcessor(ENV, { fetch, now: () => NOW })
    expect(r.processed).toBe(1)
    const sqls = calls.slice(2).map((c) => c.body.sql)
    expect(sqls.find((s) => /DELETE FROM reports/i.test(s))).toBeTruthy()
    expect(sqls.find((s) => /DELETE FROM abuse_log/i.test(s))).toBeTruthy()
    expect(sqls.find((s) => /DELETE FROM bans/i.test(s))).toBeTruthy()
    const update = calls.find((c) => /UPDATE deletion_requests SET status = \?/i.test(c.body.sql))!
    expect(update.body.params).toContain('completed')
    expect(update.body.params).toContain(NOW)
    expect(update.body.params).toContain('d1')
  })

  test('scoped deletion (with url_path_hash) only touches reports', async () => {
    const requests = [
      { id: 'd2', uuid_hash: 'u2', url_path_hash: 'p1' },
    ]
    const { fetch, calls } = makeD1FetchMock([
      { rows: [] }, // reset stale claims
      { rows: requests },
      { rows: [] }, // DELETE reports
      { rows: [] }, // UPDATE deletion_requests
    ])
    const r = await runDeletionProcessor(ENV, { fetch, now: () => NOW })
    expect(r.processed).toBe(1)
    const sqls = calls.slice(2).map((c) => c.body.sql)
    expect(sqls.find((s) => /DELETE FROM reports/i.test(s))).toBeTruthy()
    expect(sqls.find((s) => /DELETE FROM abuse_log/i.test(s))).toBeFalsy()
    expect(sqls.find((s) => /DELETE FROM bans/i.test(s))).toBeFalsy()
    // The DELETE FROM reports query should bind both uuid_hash and url_path_hash.
    const delReports = calls.find((c) => /DELETE FROM reports/i.test(c.body.sql))!
    expect(delReports.body.params).toContain('u2')
    expect(delReports.body.params).toContain('p1')
  })

  test('processes multiple requests', async () => {
    const requests = [
      { id: 'd1', uuid_hash: 'u1', url_path_hash: null },
      { id: 'd2', uuid_hash: 'u2', url_path_hash: 'p1' },
    ]
    const { fetch } = makeD1FetchMock([
      { rows: [] },
      { rows: requests },
      ...Array(10).fill({ rows: [] }), // padding for DELETEs and UPDATEs
    ])
    const r = await runDeletionProcessor(ENV, { fetch, now: () => NOW })
    expect(r.processed).toBe(2)
  })

  test('claims pending rows atomically as processing before deleting', async () => {
    const { fetch, calls } = makeD1FetchMock([
      { rows: [] },
      { rows: [{ id: 'd1', uuid_hash: 'u1', url_path_hash: null }] },
      ...Array(5).fill({ rows: [] }),
    ])
    await runDeletionProcessor(ENV, { fetch, now: () => NOW })
    const claimIdx = calls.findIndex((c) => /SET status = 'processing'/i.test(c.body.sql))
    const firstDelete = calls.findIndex((c) => /DELETE FROM/i.test(c.body.sql))
    expect(claimIdx).toBeGreaterThanOrEqual(0)
    expect(claimIdx).toBeLessThan(firstDelete)
    expect(calls[claimIdx].body.sql).toMatch(/RETURNING/i)
    expect(calls[claimIdx].body.sql).toMatch(/status = 'pending'/i)
  })

  test('stale processing claims are returned to pending (crash recovery)', async () => {
    const { fetch, calls } = makeD1FetchMock([{ rows: [] }, { rows: [] }])
    await runDeletionProcessor(ENV, { fetch, now: () => NOW })
    expect(calls[0].body.sql).toMatch(/SET status = 'pending'/i)
    expect(calls[0].body.sql).toMatch(/status = 'processing' AND processed_at < \?/i)
    expect(calls[0].body.params).toEqual([NOW - 30 * 60])
  })

  test('ban cleanup is limited to uuid-type rows', async () => {
    const { fetch, calls } = makeD1FetchMock([
      { rows: [] },
      { rows: [{ id: 'd1', uuid_hash: 'u1', url_path_hash: null }] },
      ...Array(5).fill({ rows: [] }),
    ])
    await runDeletionProcessor(ENV, { fetch, now: () => NOW })
    const del = calls.find((c) => /DELETE FROM bans/i.test(c.body.sql))!
    expect(del.body.sql).toMatch(/identifier_type = 'uuid'/i)
  })
})

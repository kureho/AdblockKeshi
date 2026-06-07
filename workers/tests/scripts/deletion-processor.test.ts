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
    const { fetch, calls } = makeD1FetchMock([{ rows: [] }])
    const r = await runDeletionProcessor(ENV, { fetch, now: () => NOW })
    expect(r).toEqual({ processed: 0 })
    expect(calls).toHaveLength(1)
  })

  test('full-deletion (url_path_hash=null) cleans reports + abuse_log + bans', async () => {
    const requests = [
      { id: 'd1', uuid_hash: 'u1', url_path_hash: null },
    ]
    const { fetch, calls } = makeD1FetchMock([
      { rows: requests }, // SELECT
      { rows: [] }, // DELETE reports
      { rows: [] }, // DELETE abuse_log
      { rows: [] }, // DELETE bans
      { rows: [] }, // UPDATE deletion_requests
    ])
    const r = await runDeletionProcessor(ENV, { fetch, now: () => NOW })
    expect(r.processed).toBe(1)
    const sqls = calls.slice(1).map((c) => c.body.sql)
    expect(sqls.find((s) => /DELETE FROM reports/i.test(s))).toBeTruthy()
    expect(sqls.find((s) => /DELETE FROM abuse_log/i.test(s))).toBeTruthy()
    expect(sqls.find((s) => /DELETE FROM bans/i.test(s))).toBeTruthy()
    const update = calls.find((c) => /UPDATE deletion_requests/i.test(c.body.sql))!
    expect(update.body.params).toContain('completed')
    expect(update.body.params).toContain(NOW)
    expect(update.body.params).toContain('d1')
  })

  test('scoped deletion (with url_path_hash) only touches reports', async () => {
    const requests = [
      { id: 'd2', uuid_hash: 'u2', url_path_hash: 'p1' },
    ]
    const { fetch, calls } = makeD1FetchMock([
      { rows: requests },
      { rows: [] }, // DELETE reports
      { rows: [] }, // UPDATE deletion_requests
    ])
    const r = await runDeletionProcessor(ENV, { fetch, now: () => NOW })
    expect(r.processed).toBe(1)
    const sqls = calls.slice(1).map((c) => c.body.sql)
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
      { rows: requests },
      ...Array(10).fill({ rows: [] }), // padding for DELETEs and UPDATEs
    ])
    const r = await runDeletionProcessor(ENV, { fetch, now: () => NOW })
    expect(r.processed).toBe(2)
  })
})

// Plan B Task 2.4 (L8 rollback) orchestrator test.

import { describe, expect, test } from 'vitest'
import { runComplaintRollback } from '../../../scripts/rollback/complaint-rollback'

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
const NOW = 5_000_000
const THIRTY_DAYS = 30 * 86_400

describe('runComplaintRollback', () => {
  test('no eligible rows → noop', async () => {
    const { fetch, calls } = makeD1FetchMock([{ rows: [] }])
    const r = await runComplaintRollback(ENV, { fetch, now: () => NOW })
    expect(r).toEqual({ rolled_back: 0 })
    expect(calls).toHaveLength(1)
    expect(calls[0].body.sql).toMatch(/'beta'.*complaint_count\s*>=\s*2/is)
    expect(calls[0].body.sql).toMatch(/'stable'.*complaint_count\s*>=\s*3/is)
  })

  test('rollback sets status + cooldown_until = now + 30d', async () => {
    const eligible = [{ id: 'c1' }, { id: 'c2' }]
    const { fetch, calls } = makeD1FetchMock([{ rows: eligible }, { rows: [] }])
    const r = await runComplaintRollback(ENV, { fetch, now: () => NOW })
    expect(r.rolled_back).toBe(2)
    const updateCall = calls.find((c) => /UPDATE rule_candidates/i.test(c.body.sql))
    expect(updateCall!.body.sql).toMatch(/rejected_rollback/)
    expect(updateCall!.body.params).toContain(NOW + THIRTY_DAYS)
    expect(updateCall!.body.params).toContain('c1')
    expect(updateCall!.body.params).toContain('c2')
  })
})

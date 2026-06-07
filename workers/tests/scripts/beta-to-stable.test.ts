// Plan B Task 2.3 (L7 β→stable promotion) test.

import { describe, expect, test } from 'vitest'
import { runBetaPromotion } from '../../../scripts/promotion/beta-to-stable'

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
const SEVEN_DAYS = 7 * 86_400

describe('runBetaPromotion', () => {
  test('no eligible beta candidates → noop', async () => {
    const { fetch, calls } = makeD1FetchMock([{ rows: [] }])
    const r = await runBetaPromotion(ENV, { fetch, now: () => 1_000_000 })
    expect(r).toEqual({ promoted: 0 })
    expect(calls).toHaveLength(1)
    // SELECT enforces both window AND complaint_count=0
    expect(calls[0].body.sql).toMatch(/status\s*=\s*'beta'/)
    expect(calls[0].body.sql).toMatch(/complaint_count\s*=\s*0/)
  })

  test('eligible candidates → UPDATE status=stable + stable_started_at=now', async () => {
    const eligible = [{ id: 'c1' }, { id: 'c2' }]
    const { fetch, calls } = makeD1FetchMock([{ rows: eligible }, { rows: [] }])
    const now = 9_000_000
    const r = await runBetaPromotion(ENV, { fetch, now: () => now })
    expect(r.promoted).toBe(2)
    const updateCall = calls.find((c) => /UPDATE rule_candidates/i.test(c.body.sql))
    expect(updateCall!.body.sql).toMatch(/SET status = 'stable'/)
    expect(updateCall!.body.params).toContain(now)
    expect(updateCall!.body.params).toContain('c1')
    expect(updateCall!.body.params).toContain('c2')
  })

  test('SELECT uses correct dwell-time cutoff', async () => {
    const { fetch, calls } = makeD1FetchMock([{ rows: [] }])
    const now = 10_000_000
    await runBetaPromotion(ENV, { fetch, now: () => now })
    const cutoff = now - SEVEN_DAYS
    expect(calls[0].body.params).toContain(cutoff)
  })
})

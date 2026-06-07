// Plan B Task 2.1 orchestrator test.

import { describe, expect, test } from 'vitest'
import { runCdnCheck } from '../../../scripts/validation/cdn-check'

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

describe('runCdnCheck', () => {
  test('no validating candidates → noop', async () => {
    const { fetch, calls } = makeD1FetchMock([{ rows: [] }])
    const r = await runCdnCheck(ENV, { fetch })
    expect(r).toEqual({ passed: 0, rejected: 0 })
    expect(calls).toHaveLength(1)
  })

  test('CDN candidate → status=rejected_cdn, l5_check=fail', async () => {
    const candidates = [{ id: 'c1', domain: 'foo.cloudfront.net' }]
    const { fetch, calls } = makeD1FetchMock([{ rows: candidates }, { rows: [] }])
    const r = await runCdnCheck(ENV, { fetch })
    expect(r).toEqual({ passed: 0, rejected: 1 })
    const updateCall = calls.find((c) => /UPDATE rule_candidates/i.test(c.body.sql))
    expect(updateCall!.body.params[0]).toBe('rejected_cdn')
    expect(updateCall!.body.params[1]).toBe('fail')
  })

  test('non-CDN candidate → l5_check=pass, status unchanged', async () => {
    const candidates = [{ id: 'c2', domain: 'small-blog.example' }]
    const { fetch, calls } = makeD1FetchMock([{ rows: candidates }, { rows: [] }])
    const r = await runCdnCheck(ENV, { fetch })
    expect(r).toEqual({ passed: 1, rejected: 0 })
    const updateCall = calls.find((c) => /UPDATE rule_candidates/i.test(c.body.sql))
    expect(updateCall!.body.params[0]).toBe('validating')
    expect(updateCall!.body.params[1]).toBe('pass')
  })

  test('mixed: 1 CDN + 1 non-CDN → 2 batched UPDATEs', async () => {
    const candidates = [
      { id: 'c1', domain: 'd123.akamaized.net' },
      { id: 'c2', domain: 'normal-site.example' },
    ]
    const { fetch, calls } = makeD1FetchMock([
      { rows: candidates },
      { rows: [] }, // rejected UPDATE
      { rows: [] }, // passed UPDATE
    ])
    const r = await runCdnCheck(ENV, { fetch })
    expect(r).toEqual({ passed: 1, rejected: 1 })
    const updates = calls.filter((c) => /UPDATE rule_candidates/i.test(c.body.sql))
    expect(updates).toHaveLength(2)
  })
})

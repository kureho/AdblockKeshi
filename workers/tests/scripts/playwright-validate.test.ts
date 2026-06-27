// Plan B Task 2.2 orchestrator test (injectable validatePage so real Playwright
// stays out of vitest).

import { describe, expect, test, vi } from 'vitest'
import { runPlaywrightValidate } from '../../../scripts/validation/playwright-validate'
import type { PageValidation } from '../../../workers/src/lib/l6-decision'

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

describe('runPlaywrightValidate', () => {
  test('no candidates → noop', async () => {
    const { fetch, calls } = makeD1FetchMock([{ rows: [] }])
    const r = await runPlaywrightValidate(ENV, {
      fetch,
      validatePage: async () => ({
        ad_class_count: 0,
        ad_network_hits: 0,
        detected_selector: null,
      }),
      now: () => 5000,
    })
    expect(r).toEqual({ promoted: 0, rejected_score: 0, rejected_scope: 0, rejected_unreachable: 0 })
    expect(calls).toHaveLength(1)
  })

  test('high-quality candidate → beta with selector+rule_text+beta_started_at', async () => {
    const candidates = [
      { id: 'c1', domain: 'example.com', url: 'https://example.com/page' },
    ]
    const { fetch, calls } = makeD1FetchMock([{ rows: candidates }, { rows: [] }])
    const validatePage = vi.fn(
      async (): Promise<PageValidation> => ({
        ad_class_count: 5,
        ad_network_hits: 3,
        detected_selector: '.banner-ad-123',
      })
    )
    const r = await runPlaywrightValidate(ENV, { fetch, validatePage, now: () => 7777 })
    expect(r.promoted).toBe(1)
    expect(validatePage).toHaveBeenCalledWith('https://example.com/page')
    const updateCall = calls.find((c) => /UPDATE rule_candidates/i.test(c.body.sql))
    const params = updateCall!.body.params
    expect(params).toContain('beta')
    expect(params).toContain('pass')
    expect(params).toContain('.banner-ad-123')
    expect(params).toContain(7777) // beta_started_at
    expect(params.some((p: string) => typeof p === 'string' && p.includes('css-display-none'))).toBe(true)
    // 層B: url = normalizeURL('https://example.com/page') === 'example.com'
    expect(params).toContain('example.com')
  })

  test('low score → rejected_score_low (no beta_started_at)', async () => {
    const candidates = [{ id: 'c2', domain: 'low.example', url: 'https://low.example/x' }]
    const { fetch, calls } = makeD1FetchMock([{ rows: candidates }, { rows: [] }])
    const r = await runPlaywrightValidate(ENV, {
      fetch,
      validatePage: async () => ({
        ad_class_count: 0,
        ad_network_hits: 0,
        detected_selector: '.something',
      }),
      now: () => 0,
    })
    expect(r.rejected_score).toBe(1)
    const updateCall = calls.find((c) => /UPDATE rule_candidates/i.test(c.body.sql))
    expect(updateCall!.body.params).toContain('rejected_score_low')
  })

  test('high score but wide selector → rejected_selector_scope', async () => {
    const candidates = [{ id: 'c3', domain: 'wide.example', url: 'https://wide.example/' }]
    const { fetch, calls } = makeD1FetchMock([{ rows: candidates }, { rows: [] }])
    const r = await runPlaywrightValidate(ENV, {
      fetch,
      validatePage: async () => ({
        ad_class_count: 5,
        ad_network_hits: 3,
        detected_selector: 'body',
      }),
      now: () => 0,
    })
    expect(r.rejected_scope).toBe(1)
    const updateCall = calls.find((c) => /UPDATE rule_candidates/i.test(c.body.sql))
    expect(updateCall!.body.params).toContain('rejected_selector_scope')
  })

  test('validatePage error on one URL increments it (stays validating) and keeps processing the next', async () => {
    const candidates = [
      { id: 'c1', domain: 'a.example', url: 'https://a.example/', validation_attempts: 0 },
      { id: 'c2', domain: 'b.example', url: 'https://b.example/', validation_attempts: 0 },
    ]
    const { fetch, calls } = makeD1FetchMock([{ rows: candidates }, { rows: [] }, { rows: [] }])
    let n = 0
    const r = await runPlaywrightValidate(ENV, {
      fetch,
      validatePage: async () => {
        n++
        if (n === 1) throw new Error('timeout')
        return { ad_class_count: 5, ad_network_hits: 3, detected_selector: '.ad' }
      },
      now: () => 1,
    })
    // First failed → transient increment (NOT rejected); second promoted.
    expect(r.promoted).toBe(1)
    expect(r.rejected_unreachable).toBe(0)
    const updates = calls.filter((c) => /UPDATE rule_candidates/i.test(c.body.sql))
    expect(updates[0].body.params).toEqual([1, 'c1']) // c1: counter bump only
    expect(updates[1].body.params).toContain('beta') // c2: promoted
  })

  test('validatePage failure below max attempts → increments validation_attempts, stays validating, full url retained', async () => {
    const candidates = [
      { id: 'c1', domain: 'a.example', url: 'https://a.example/p?q=1', validation_attempts: 0 },
    ]
    const { fetch, calls } = makeD1FetchMock([{ rows: candidates }, { rows: [] }])
    const r = await runPlaywrightValidate(ENV, {
      fetch,
      validatePage: async () => {
        throw new Error('timeout')
      },
      now: () => 1,
    })
    expect(r.rejected_unreachable).toBe(0)
    const upd = calls.find((c) => /UPDATE rule_candidates/i.test(c.body.sql))!
    // transient: bumps the counter only — does NOT promote/reject or redact url.
    expect(upd.body.sql).toMatch(/SET validation_attempts/i)
    expect(upd.body.sql).not.toMatch(/rejected_unreachable/i)
    // status guard makes the write a no-op if the row already left 'validating'.
    expect(upd.body.sql).toMatch(/WHERE id = \? AND status = 'validating'/i)
    expect(upd.body.params).toEqual([1, 'c1'])
  })

  test('validatePage failure at attempt N-1 stays validating (boundary just below max)', async () => {
    const candidates = [
      { id: 'c1', domain: 'a.example', url: 'https://a.example/p', validation_attempts: 1 },
    ]
    const { fetch, calls } = makeD1FetchMock([{ rows: candidates }, { rows: [] }])
    const r = await runPlaywrightValidate(ENV, {
      fetch,
      validatePage: async () => {
        throw new Error('timeout')
      },
      now: () => 1,
    })
    // attempts 1 → 2 (< MAX 3): still transient, not rejected.
    expect(r.rejected_unreachable).toBe(0)
    const upd = calls.find((c) => /UPDATE rule_candidates/i.test(c.body.sql))!
    expect(upd.body.sql).not.toMatch(/rejected_unreachable/i)
    expect(upd.body.params).toEqual([2, 'c1'])
  })

  test('null-url candidate below max → transient increment, validatePage not called', async () => {
    const candidates = [
      { id: 'c1', domain: 'x.example', url: null, validation_attempts: 0 },
    ]
    const { fetch, calls } = makeD1FetchMock([{ rows: candidates }, { rows: [] }])
    const validatePage = vi.fn(async () => ({
      ad_class_count: 5,
      ad_network_hits: 3,
      detected_selector: '.ad',
    }))
    const r = await runPlaywrightValidate(ENV, { fetch, validatePage, now: () => 1 })
    expect(r.rejected_unreachable).toBe(0)
    expect(validatePage).not.toHaveBeenCalled() // no url → never attempt navigation
    const upd = calls.find((c) => /UPDATE rule_candidates/i.test(c.body.sql))!
    expect(upd.body.sql).not.toMatch(/rejected_unreachable/i)
    expect(upd.body.params).toEqual([1, 'c1'])
  })

  test('validatePage failure reaching max attempts → rejected_unreachable, url redacted to eTLD+1, counted', async () => {
    const candidates = [
      { id: 'c1', domain: 'tpead.net', url: 'https://tpead.net/v/abc?x=1', validation_attempts: 2 },
    ]
    const { fetch, calls } = makeD1FetchMock([{ rows: candidates }, { rows: [] }])
    const r = await runPlaywrightValidate(ENV, {
      fetch,
      validatePage: async () => {
        throw new Error('net::ERR_ABORTED')
      },
      now: () => 1,
    })
    expect(r.rejected_unreachable).toBe(1)
    const upd = calls.find((c) => /UPDATE rule_candidates/i.test(c.body.sql))!
    expect(upd.body.sql).toMatch(/rejected_unreachable/i)
    // attempts=3 persisted, url redacted (full URL discarded), keyed by id.
    expect(upd.body.params).toEqual([3, 'tpead.net', 'c1'])
  })

  test('null-url candidate reaching max attempts → rejected_unreachable, url stays null, validatePage not called', async () => {
    const candidates = [
      { id: 'c1', domain: 'x.example', url: null, validation_attempts: 2 },
    ]
    const { fetch, calls } = makeD1FetchMock([{ rows: candidates }, { rows: [] }])
    const validatePage = vi.fn(async () => ({
      ad_class_count: 5,
      ad_network_hits: 3,
      detected_selector: '.ad',
    }))
    const r = await runPlaywrightValidate(ENV, { fetch, validatePage, now: () => 1 })
    expect(r.rejected_unreachable).toBe(1)
    expect(validatePage).not.toHaveBeenCalled() // no url → never attempt navigation
    const upd = calls.find((c) => /UPDATE rule_candidates/i.test(c.body.sql))!
    expect(upd.body.params).toEqual([3, null, 'c1']) // url stays null (nothing to redact)
  })
})

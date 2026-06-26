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
    expect(r).toEqual({ promoted: 0, rejected_score: 0, rejected_scope: 0 })
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

  test('validatePage error on one URL skips that candidate, keeps going', async () => {
    const candidates = [
      { id: 'c1', domain: 'a.example', url: 'https://a.example/' },
      { id: 'c2', domain: 'b.example', url: 'https://b.example/' },
    ]
    const { fetch } = makeD1FetchMock([{ rows: candidates }, { rows: [] }])
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
    // First failed (skip), second promoted.
    expect(r.promoted).toBe(1)
  })
})

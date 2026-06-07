// Plan B Task 2.2 (L6 Playwright validation): pure scoring + L4 selector-scope.

import { describe, expect, test } from 'vitest'
import { computeAdScore, decideL6 } from '../../src/lib/l6-decision'

describe('computeAdScore', () => {
  test('zero signals → score 0', () => {
    expect(
      computeAdScore({ ad_class_count: 0, ad_network_hits: 0, detected_selector: null })
    ).toBe(0)
  })

  test('only ad class → ~0.4', () => {
    expect(
      computeAdScore({ ad_class_count: 3, ad_network_hits: 0, detected_selector: null })
    ).toBeCloseTo(0.4, 1)
  })

  test('all three signals → ~1.0', () => {
    expect(
      computeAdScore({
        ad_class_count: 5,
        ad_network_hits: 2,
        detected_selector: '.banner-ad',
      })
    ).toBeCloseTo(1.0, 1)
  })

  test('score is clamped to [0, 1]', () => {
    const s = computeAdScore({
      ad_class_count: 100,
      ad_network_hits: 100,
      detected_selector: '.ad',
    })
    expect(s).toBeLessThanOrEqual(1)
    expect(s).toBeGreaterThanOrEqual(0)
  })
})

describe('decideL6', () => {
  const candidate = { domain: 'example.com' }

  test('high score + acceptable selector → beta', () => {
    const r = decideL6(candidate, {
      ad_class_count: 5,
      ad_network_hits: 2,
      detected_selector: '.video-overlay-ad',
    })
    expect(r.l6_check).toBe('pass')
    expect(r.next_status).toBe('beta')
    expect(r.validation_score).toBeGreaterThanOrEqual(0.7)
    expect(r.selector).toBe('.video-overlay-ad')
    expect(r.rule_text).toContain('css-display-none')
    expect(r.rule_text).toContain('.video-overlay-ad')
    expect(r.rule_text).toContain('example.com')
  })

  test('low score → rejected_score_low', () => {
    const r = decideL6(candidate, {
      ad_class_count: 0,
      ad_network_hits: 0,
      detected_selector: '.banner',
    })
    expect(r.l6_check).toBe('fail')
    expect(r.next_status).toBe('rejected_score_low')
    expect(r.reason).toBeTruthy()
  })

  test('high score but wide selector → rejected_selector_scope (L4)', () => {
    const r = decideL6(candidate, {
      ad_class_count: 5,
      ad_network_hits: 2,
      detected_selector: 'body',
    })
    expect(r.l6_check).toBe('fail')
    expect(r.next_status).toBe('rejected_selector_scope')
    expect(r.reason).toMatch(/bare_body|too_broad/)
  })

  test('high score but null selector → rejected_selector_scope', () => {
    const r = decideL6(candidate, {
      ad_class_count: 5,
      ad_network_hits: 2,
      detected_selector: null,
    })
    expect(r.next_status).toBe('rejected_selector_scope')
  })

  test('rule_text is valid JSON wrapping the selector and domain', () => {
    const r = decideL6(candidate, {
      ad_class_count: 5,
      ad_network_hits: 2,
      detected_selector: '#ad-slot-123',
    })
    const parsed = JSON.parse(r.rule_text)
    expect(Array.isArray(parsed)).toBe(true)
    expect(parsed[0].action.type).toBe('css-display-none')
    expect(parsed[0].action.selector).toBe('#ad-slot-123')
    expect(parsed[0].trigger['if-domain']).toContain('example.com')
  })
})

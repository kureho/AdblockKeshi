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

// 2026-06-23 サーバ不変条件: サーバが昇格するルールは cosmetic(css-display-none)のみで、
// top-level document を遮断し得る action 'block' を絶対に出力しない。
// （誤ブロック事故の主因はクライアント自己報告ファストレーンであり、サーバ経路は無実である
//  という根拠をテストでロックする。将来 decideL6 が 'block' を出すように退行したら検知する。）
describe('decideL6 server invariant: never emits a document-blocking block rule', () => {
  const candidate = { domain: 'example.com' }

  // pass する典型入力を網羅し、生成 rule の action.type が常に css-display-none で
  // 'block' を一切含まないこと。
  const passingInputs = [
    { ad_class_count: 5, ad_network_hits: 2, detected_selector: '.video-overlay-ad' },
    { ad_class_count: 1, ad_network_hits: 1, detected_selector: '#ad-slot-123' },
    { ad_class_count: 9, ad_network_hits: 9, detected_selector: '.banner.promo' },
  ]

  for (const v of passingInputs) {
    test(`pass(${v.detected_selector}) は css-display-none のみ・block を出さない`, () => {
      const r = decideL6(candidate, v)
      expect(r.l6_check).toBe('pass')
      const parsed = JSON.parse(r.rule_text)
      for (const rule of parsed) {
        expect(rule.action.type).toBe('css-display-none')
        expect(rule.action.type).not.toBe('block')
      }
      // 文字列としても 'block' action を含まない（保険）。
      expect(r.rule_text).not.toContain('"block"')
    })
  }

  // fail ケースは rule_text が空文字（昇格しない）= block を出す余地がそもそも無い。
  test('fail ケースは rule_text 空・block を出さない', () => {
    const lowScore = decideL6(candidate, {
      ad_class_count: 0,
      ad_network_hits: 0,
      detected_selector: '.banner',
    })
    expect(lowScore.rule_text).toBe('')
    const wideSelector = decideL6(candidate, {
      ad_class_count: 5,
      ad_network_hits: 2,
      detected_selector: 'body',
    })
    expect(wideSelector.rule_text).toBe('')
  })
})

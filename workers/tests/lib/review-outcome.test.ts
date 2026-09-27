// A-88 §3: resolveReviewOutcome の対応表を全値固定する。
import { describe, expect, test } from 'vitest'
import {
  RAW_REVIEW_OUTCOMES,
  isRawReviewOutcome,
  resolveReviewOutcome,
  type RawReviewOutcome,
} from '../../src/lib/review-outcome'

describe('isRawReviewOutcome', () => {
  test('5値すべてを true と判定する', () => {
    for (const v of RAW_REVIEW_OUTCOMES) {
      expect(isRawReviewOutcome(v)).toBe(true)
    }
  })

  test('未知の値・非文字列は false', () => {
    expect(isRawReviewOutcome('unknown')).toBe(false)
    expect(isRawReviewOutcome('')).toBe(false)
    expect(isRawReviewOutcome(null)).toBe(false)
    expect(isRawReviewOutcome(undefined)).toBe(false)
    expect(isRawReviewOutcome(123)).toBe(false)
  })
})

describe('resolveReviewOutcome: review_outcome がある場合（最優先・全値固定）', () => {
  const cases: Array<[RawReviewOutcome, string]> = [
    ['applied', 'applied'],
    ['in_app_ad', 'in_app_ad'],
    ['site_own_ad', 'site_own_ad'],
    ['not_reproduced', 'declined'],
    ['invalid', 'declined'],
  ]

  for (const [raw, expected] of cases) {
    test(`review_outcome='${raw}' → '${expected}'`, () => {
      expect(
        resolveReviewOutcome({ status: 'pending', appliedAt: null, reviewOutcome: raw })
      ).toBe(expected)
    })
  }

  test('review_outcome があれば status/appliedAt に関係なく優先される', () => {
    expect(
      resolveReviewOutcome({ status: 'rejected_score_low', appliedAt: 1000, reviewOutcome: 'applied' })
    ).toBe('applied')
    expect(
      resolveReviewOutcome({ status: 'stable', appliedAt: null, reviewOutcome: 'not_reproduced' })
    ).toBe('declined')
  })
})

describe('resolveReviewOutcome: review_outcome が無い場合（既存 status からのフォールバック）', () => {
  test('applied_at がある → applied', () => {
    expect(
      resolveReviewOutcome({ status: 'aggregated', appliedAt: 1700000000, reviewOutcome: null })
    ).toBe('applied')
  })

  test("status='stable' → applied（applied_at 無しでも）", () => {
    expect(
      resolveReviewOutcome({ status: 'stable', appliedAt: null, reviewOutcome: null })
    ).toBe('applied')
  })

  test("status が 'rejected_' で始まる → declined", () => {
    for (const s of ['rejected_critical', 'rejected_cdn', 'rejected_score_low', 'rejected_selector_scope', 'rejected_rollback', 'rejected_unreachable']) {
      expect(resolveReviewOutcome({ status: s, appliedAt: null, reviewOutcome: null })).toBe('declined')
    }
  })

  test('それ以外（pending / aggregated / observation_* 等）→ checking', () => {
    for (const s of ['pending', 'aggregated', 'observation_legacy', 'observation_out_of_scope', 'observation_unknown_kind', 'broken_site', 'validating', 'kureho_queue', 'beta']) {
      expect(resolveReviewOutcome({ status: s, appliedAt: null, reviewOutcome: null })).toBe('checking')
    }
  })

  test('review_outcome が未知文字列でもフォールバックとして扱う（null 同様）', () => {
    expect(
      resolveReviewOutcome({ status: 'rejected_cdn', appliedAt: null, reviewOutcome: 'not_a_real_value' })
    ).toBe('declined')
  })
})

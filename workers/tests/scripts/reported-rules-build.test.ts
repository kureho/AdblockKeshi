// Plan B Task 4.2 reported-rules.json build test.

import { describe, expect, test } from 'vitest'
import {
  buildReportedRulesJson,
  computeReportedMetrics,
  applyReportedToVersionJson,
  type StableRuleRow,
} from '../../../scripts/sync/reported-rules-build'

describe('buildReportedRulesJson', () => {
  test('empty stable list → empty JSON array', () => {
    expect(buildReportedRulesJson([])).toBe('[]')
  })

  test('flattens rule_text from each candidate into a single Content Blocker array', () => {
    const rows: StableRuleRow[] = [
      {
        id: 'c1',
        rule_text: JSON.stringify([
          {
            action: { type: 'css-display-none', selector: '.ad' },
            trigger: { 'url-filter': '.*', 'if-domain': ['a.com'] },
          },
        ]),
      },
      {
        id: 'c2',
        rule_text: JSON.stringify([
          {
            action: { type: 'css-display-none', selector: '#banner' },
            trigger: { 'url-filter': '.*', 'if-domain': ['b.com'] },
          },
        ]),
      },
    ]
    const out = JSON.parse(buildReportedRulesJson(rows))
    expect(Array.isArray(out)).toBe(true)
    expect(out).toHaveLength(2)
    expect(out[0].trigger['if-domain']).toContain('a.com')
    expect(out[1].trigger['if-domain']).toContain('b.com')
  })

  test('skips candidates whose rule_text is unparseable (defensive)', () => {
    const rows: StableRuleRow[] = [
      { id: 'good', rule_text: '[{"action":{"type":"block"},"trigger":{"url-filter":".*"}}]' },
      { id: 'broken', rule_text: 'not json' },
      { id: 'empty', rule_text: '' },
    ]
    const out = JSON.parse(buildReportedRulesJson(rows))
    expect(out).toHaveLength(1)
  })
})

describe('computeReportedMetrics (Plan C Chunk 5)', () => {
  const goodRow = (id: string): StableRuleRow => ({
    id,
    rule_text: JSON.stringify([
      { action: { type: 'block' }, trigger: { 'url-filter': '.*' } },
    ]),
  })
  const twoRuleRow = (id: string): StableRuleRow => ({
    id,
    rule_text: JSON.stringify([
      { action: { type: 'block' }, trigger: { 'url-filter': '.*' } },
      { action: { type: 'css-display-none', selector: '.ad' }, trigger: { 'url-filter': '.*' } },
    ]),
  })

  test('counts flat rule emissions from all stable rows + the recent subset', () => {
    const all = [goodRow('a'), twoRuleRow('b'), goodRow('c')]
    const recent = [twoRuleRow('b'), goodRow('c')]
    const metrics = computeReportedMetrics(all, recent)
    expect(metrics).toEqual({ rule_count: 4, added_last_month: 3 })
  })

  test('returns zero counts when both sets are empty', () => {
    expect(computeReportedMetrics([], [])).toEqual({
      rule_count: 0,
      added_last_month: 0,
    })
  })

  test('ignores unparseable rule_text in either set (defensive)', () => {
    const broken: StableRuleRow = { id: 'x', rule_text: 'not json' }
    const metrics = computeReportedMetrics([goodRow('a'), broken], [broken])
    expect(metrics).toEqual({ rule_count: 1, added_last_month: 0 })
  })
})

describe('applyReportedToVersionJson (Plan C Chunk 5)', () => {
  test('inserts reported section when absent and preserves other fields', () => {
    const before = JSON.stringify(
      { generated_at: '2026-05-30T00:00:00Z', rule_count: 150_000, filters: [] },
      null,
      2
    )
    const after = applyReportedToVersionJson(before, {
      rule_count: 42,
      added_last_month: 7,
    })
    const parsed = JSON.parse(after)
    expect(parsed.generated_at).toBe('2026-05-30T00:00:00Z')
    expect(parsed.rule_count).toBe(150_000)
    expect(parsed.filters).toEqual([])
    expect(parsed.reported).toEqual({ rule_count: 42, added_last_month: 7 })
  })

  test('overwrites stale reported metrics without affecting other fields', () => {
    const before = JSON.stringify(
      {
        generated_at: '2026-05-30T00:00:00Z',
        rule_count: 150_000,
        reported: { rule_count: 1, added_last_month: 1 },
      },
      null,
      2
    )
    const after = applyReportedToVersionJson(before, {
      rule_count: 99,
      added_last_month: 12,
    })
    const parsed = JSON.parse(after)
    expect(parsed.reported).toEqual({ rule_count: 99, added_last_month: 12 })
    expect(parsed.rule_count).toBe(150_000)
  })

  test('throws on malformed input JSON (callers handle this case)', () => {
    expect(() =>
      applyReportedToVersionJson('not json at all', {
        rule_count: 1,
        added_last_month: 1,
      })
    ).toThrow()
  })
})

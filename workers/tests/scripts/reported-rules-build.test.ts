// Plan B Task 4.2 reported-rules.json build test.

import { describe, expect, test } from 'vitest'
import { buildReportedRulesJson, type StableRuleRow } from '../../../scripts/sync/reported-rules-build'

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

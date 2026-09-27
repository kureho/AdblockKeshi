// Plan B Task 4.2 reported-rules.json build test.

import { describe, expect, test } from 'vitest'
import {
  buildReportedRulesJson,
  computeReportedMetrics,
  applyReportedToVersionJson,
  parseManualRuleFile,
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

// A-88 §2: 週1回の判定で人（Claude）が書いた「そのサイト限定」のルール（review/rules/*.json）。
// 公開リポジトリに置くので、報告の URL・メモは入れず、サイトのドメインと広告の通信先だけを持つ。
describe('parseManualRuleFile (A-88 §2)', () => {
  const siteRule = {
    trigger: { 'url-filter': '^https?://([^/]+\\.)?html-load\\.com[/:]', 'if-domain': ['*thedigestweb.com'] },
    action: { type: 'block' },
  }
  const ok = (rules: unknown[]) => JSON.stringify({ added_at: '2026-09-28', rules })

  test('受け付ける: if-domain つきの block と css-display-none', () => {
    const hide = { trigger: { 'url-filter': '.*', 'if-domain': ['example.jp'] }, action: { type: 'css-display-none', selector: '.ad-box' } }
    const parsed = parseManualRuleFile('2026-09-28-thedigestweb.json', ok([siteRule, hide]))
    expect(parsed.added_at).toBe('2026-09-28')
    expect(parsed.rules).toHaveLength(2)
  })

  test('拒否: if-domain が無い（全サイトに効いてしまう）', () => {
    const r = { trigger: { 'url-filter': 'html-load\\.com' }, action: { type: 'block' } }
    expect(() => parseManualRuleFile('x.json', ok([r]))).toThrow(/if-domain/)
  })

  test('拒否: if-domain の形がドメインでない', () => {
    const r = { ...siteRule, trigger: { ...siteRule.trigger, 'if-domain': ['https://thedigestweb.com/a'] } }
    expect(() => parseManualRuleFile('x.json', ok([r]))).toThrow(/if-domain/)
  })

  test('拒否: ignore-previous-rules（ほかの防御を外せてしまう）', () => {
    const r = { ...siteRule, action: { type: 'ignore-previous-rules' } }
    expect(() => parseManualRuleFile('x.json', ok([r]))).toThrow(/action/)
  })

  test('拒否: サイトそのもの（document）を止める block', () => {
    const r = { trigger: { ...siteRule.trigger, 'resource-type': ['document'] }, action: { type: 'block' } }
    expect(() => parseManualRuleFile('x.json', ok([r]))).toThrow(/document/)
  })

  test('拒否: 何でも止める url-filter の block', () => {
    const r = { trigger: { 'url-filter': '.*', 'if-domain': ['example.jp'] }, action: { type: 'block' } }
    expect(() => parseManualRuleFile('x.json', ok([r]))).toThrow(/url-filter/)
  })

  test('拒否: css-display-none に selector が無い', () => {
    const r = { trigger: { 'url-filter': '.*', 'if-domain': ['example.jp'] }, action: { type: 'css-display-none' } }
    expect(() => parseManualRuleFile('x.json', ok([r]))).toThrow(/selector/)
  })

  test('拒否: 想定外の trigger キー（unless-domain 等）', () => {
    const r = { ...siteRule, trigger: { ...siteRule.trigger, 'unless-domain': ['a.com'] } }
    expect(() => parseManualRuleFile('x.json', ok([r]))).toThrow(/unless-domain/)
  })

  test('拒否: added_at が日付でない・rules が空', () => {
    expect(() => parseManualRuleFile('x.json', JSON.stringify({ added_at: '9/28', rules: [siteRule] }))).toThrow(/added_at/)
    expect(() => parseManualRuleFile('x.json', JSON.stringify({ added_at: '2026-09-28', rules: [] }))).toThrow(/rules/)
  })

  test('拒否: JSON でない（ファイル名つきで失敗を返す）', () => {
    expect(() => parseManualRuleFile('broken.json', 'not json')).toThrow(/broken\.json/)
  })
})

describe('mergeManualRules (A-88 §2)', () => {
  const stable: StableRuleRow[] = [
    { id: 'c1', rule_text: JSON.stringify([{ action: { type: 'block' }, trigger: { 'url-filter': 'a\\.net', 'if-domain': ['a.com'] } }]) },
  ]
  const manual = [
    { added_at: '2026-09-28', rules: [{ action: { type: 'block' }, trigger: { 'url-filter': 'b\\.net', 'if-domain': ['b.com'] } }] },
    { added_at: '2026-07-01', rules: [{ action: { type: 'block' }, trigger: { 'url-filter': 'c\\.net', 'if-domain': ['c.com'] } }] },
  ]

  test('D1 の stable の後ろに手書きのルールを足す', () => {
    const out = JSON.parse(buildReportedRulesJson(stable, manual))
    expect(out.map((r: { trigger: { 'if-domain': string[] } }) => r.trigger['if-domain'][0])).toEqual(['a.com', 'b.com', 'c.com'])
  })

  test('件数にも手書き分を数え、直近 30 日は added_at で判定する', () => {
    const cutoff = Date.parse('2026-09-01T00:00:00Z') / 1000
    const m = computeReportedMetrics(stable, [], manual, cutoff)
    expect(m.rule_count).toBe(3)
    expect(m.added_last_month).toBe(1)
  })

  test('手書きが無ければ従来どおり（旧呼び出しを壊さない）', () => {
    expect(JSON.parse(buildReportedRulesJson(stable))).toHaveLength(1)
    expect(computeReportedMetrics(stable, stable)).toEqual({ rule_count: 1, added_last_month: 1 })
  })
})

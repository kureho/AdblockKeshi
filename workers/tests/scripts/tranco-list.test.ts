// D1 rows_written 超過対策 (2026-09-06): Tranco リストは D1 に入れず
// GitHub Actions 上で CSV から直接 Set を組む。そのパーサのテスト。

import { describe, expect, test } from 'vitest'
import { parseTrancoDomains } from '../../../scripts/lib/tranco-list'

const CSV = `1,google.com
2,amazon.com
3,big-portal.com
bogus-line-without-comma
,empty-rank.com
4,
5,news.example.jp
`

describe('parseTrancoDomains', () => {
  test('rank,domain の CSV からドメイン集合を作る', () => {
    const set = parseTrancoDomains(CSV)
    expect(set.has('google.com')).toBe(true)
    expect(set.has('amazon.com')).toBe(true)
    expect(set.has('news.example.jp')).toBe(true)
  })

  test('壊れた行（カンマ無し / rank 空 / domain 空）は捨てる', () => {
    const set = parseTrancoDomains(CSV)
    expect(set.has('bogus-line-without-comma')).toBe(false)
    expect(set.has('empty-rank.com')).toBe(false)
    expect(set.size).toBe(4)
  })

  test('maxRows で上位 N 件に打ち切る（既定 100,000 と同じ意味）', () => {
    const set = parseTrancoDomains(CSV, 2)
    expect(set.size).toBe(2)
    expect(set.has('google.com')).toBe(true)
    expect(set.has('amazon.com')).toBe(true)
    expect(set.has('big-portal.com')).toBe(false)
  })

  test('空 CSV → 空集合', () => {
    expect(parseTrancoDomains('').size).toBe(0)
  })
})

// Plan B Task 1.3 (L3 Tranco + critical list): pure decision logic tests.
// spec rev4 §4.3.

import { describe, expect, test } from 'vitest'
import { decideL3, isInTrancoSet } from '../../src/lib/l3-decision'

describe('isInTrancoSet', () => {
  test('exact domain match', () => {
    const set = new Set(['example.com'])
    expect(isInTrancoSet('example.com', set)).toBe(true)
  })

  test('subdomain matches parent via suffix', () => {
    const set = new Set(['example.com'])
    expect(isInTrancoSet('www.example.com', set)).toBe(true)
    expect(isInTrancoSet('cdn.api.example.com', set)).toBe(true)
  })

  test('no match returns false', () => {
    const set = new Set(['example.com'])
    expect(isInTrancoSet('badsite.com', set)).toBe(false)
  })

  test('does not match by substring (must be suffix boundary)', () => {
    const set = new Set(['example.com'])
    // 'notexample.com' should NOT match 'example.com'
    expect(isInTrancoSet('notexample.com', set)).toBe(false)
  })

  test('empty set returns false', () => {
    expect(isInTrancoSet('example.com', new Set())).toBe(false)
  })
})

describe('decideL3', () => {
  const trancoSet = new Set(['big-site.com', 'news-portal.jp'])

  // D-lite: critical も自動却下せず kureho_queue へ送る（報告データとしては価値があるため）。
  // 自動適用しない点は変わらないので l3_check は 'fail' のまま。
  test('critical-list hit → kureho_queue', () => {
    const result = decideL3({ id: 'c1', domain: 'apple.com' }, trancoSet)
    expect(result).toEqual({
      id: 'c1',
      l3_check: 'fail',
      next_status: 'kureho_queue',
    })
  })

  test('critical-list hit via suffix → kureho_queue', () => {
    const result = decideL3({ id: 'c2', domain: 'support.apple.com' }, trancoSet)
    expect(result.next_status).toBe('kureho_queue')
  })

  test('tranco hit (not critical) → kureho_queue', () => {
    const result = decideL3({ id: 'c3', domain: 'big-site.com' }, trancoSet)
    expect(result).toEqual({
      id: 'c3',
      l3_check: 'fail',
      next_status: 'kureho_queue',
    })
  })

  test('tranco hit via subdomain → kureho_queue', () => {
    const result = decideL3({ id: 'c4', domain: 'www.news-portal.jp' }, trancoSet)
    expect(result.next_status).toBe('kureho_queue')
  })

  test('neither hit → pass, status=validating', () => {
    const result = decideL3({ id: 'c5', domain: 'random-ad-site.example' }, trancoSet)
    expect(result).toEqual({
      id: 'c5',
      l3_check: 'pass',
      next_status: 'validating',
    })
  })

  test('critical-list takes precedence over tranco', () => {
    // Hypothetical: apple.com appears in tranco too (it would in real Top 1M)
    const set = new Set(['apple.com', 'big-site.com'])
    const result = decideL3({ id: 'c6', domain: 'apple.com' }, set)
    expect(result.next_status).toBe('kureho_queue')
  })
})

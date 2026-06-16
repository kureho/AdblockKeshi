// Phase 3: 低スケール対策。信頼レポーター(kureho自身)の報告は L2 の
// 「別ユーザー3人」閾値をバイパスして昇格候補にする。毒入れ耐性は他ユーザーには維持。
import { describe, expect, test } from 'vitest'
import {
  computeAggregations,
  type PendingReport,
} from '../../src/lib/aggregation-threshold'

const baseReport = (o: Partial<PendingReport>): PendingReport => ({
  id: 'r1',
  uuid_hash: 'u1',
  ip_hash: 'i1',
  domain: 'ads.example.com',
  url: 'https://ads.example.com/a',
  url_path_hash: 'p1',
  created_at: 1_000_000,
  ...o,
})

const NOW = 2_000_000

describe('computeAggregations: trusted-reporter bypass', () => {
  test('single report from a trusted uuid bypasses the 3-user threshold', () => {
    const reports = [baseReport({ id: 'r1', uuid_hash: 'kureho', created_at: NOW - 100 })]
    const result = computeAggregations(reports, NOW, {
      trustedUuidHashes: new Set(['kureho']),
    })
    expect(result).toHaveLength(1)
    expect(result[0].domain).toBe('ads.example.com')
  })

  test('single report from a non-trusted uuid is still excluded', () => {
    const reports = [baseReport({ id: 'r1', uuid_hash: 'stranger', created_at: NOW - 100 })]
    const result = computeAggregations(reports, NOW, {
      trustedUuidHashes: new Set(['kureho']),
    })
    expect(result).toEqual([])
  })

  test('without a trusted set, the normal threshold is enforced', () => {
    const reports = [baseReport({ id: 'r1', uuid_hash: 'u1', created_at: NOW - 100 })]
    expect(computeAggregations(reports, NOW)).toEqual([])
  })
})

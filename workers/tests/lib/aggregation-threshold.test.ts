// Plan B Task 1.2 (L2 threshold): pure aggregation logic tests.
// spec rev4 §4.2: unique uuid_hash ≥ 3 + unique ip_hash ≥ 2 within 14d sliding window.

import { describe, expect, test } from 'vitest'
import {
  computeAggregations,
  type PendingReport,
} from '../../src/lib/aggregation-threshold'

const baseReport = (overrides: Partial<PendingReport>): PendingReport => ({
  id: 'r1',
  uuid_hash: 'u1',
  ip_hash: 'i1',
  domain: 'example.com',
  url: 'https://example.com/a',
  url_path_hash: 'p1',
  created_at: 1_000_000,
  ...overrides,
})

const NOW = 2_000_000 // arbitrary "now" (unix sec)
const DAY = 86_400
const WINDOW_START = NOW - 14 * DAY

describe('computeAggregations', () => {
  test('empty input returns empty array', () => {
    expect(computeAggregations([], NOW)).toEqual([])
  })

  test('below threshold (2 unique uuid_hash) is excluded', () => {
    const reports = [
      baseReport({ id: 'r1', uuid_hash: 'u1', ip_hash: 'i1', created_at: NOW - 100 }),
      baseReport({ id: 'r2', uuid_hash: 'u2', ip_hash: 'i2', created_at: NOW - 50 }),
    ]
    expect(computeAggregations(reports, NOW)).toEqual([])
  })

  test('above threshold (3 uuid_hash, 2 ip_hash) is included', () => {
    const reports = [
      baseReport({ id: 'r1', uuid_hash: 'u1', ip_hash: 'i1', created_at: NOW - 300 }),
      baseReport({ id: 'r2', uuid_hash: 'u2', ip_hash: 'i2', created_at: NOW - 200 }),
      baseReport({ id: 'r3', uuid_hash: 'u3', ip_hash: 'i1', created_at: NOW - 100 }),
    ]
    const result = computeAggregations(reports, NOW)
    expect(result).toHaveLength(1)
    expect(result[0]).toMatchObject({
      domain: 'example.com',
      url_path_hash: 'p1',
      url: 'https://example.com/a',
      unique_uuid_count: 3,
      unique_ip_count: 2,
      first_reported_at: NOW - 300,
      last_reported_at: NOW - 100,
    })
    expect(result[0].report_ids.sort()).toEqual(['r1', 'r2', 'r3'])
  })

  test('3 uuid_hash but only 1 unique ip_hash is excluded', () => {
    const reports = [
      baseReport({ id: 'r1', uuid_hash: 'u1', ip_hash: 'i1', created_at: NOW - 300 }),
      baseReport({ id: 'r2', uuid_hash: 'u2', ip_hash: 'i1', created_at: NOW - 200 }),
      baseReport({ id: 'r3', uuid_hash: 'u3', ip_hash: 'i1', created_at: NOW - 100 }),
    ]
    expect(computeAggregations(reports, NOW)).toEqual([])
  })

  test('reports older than 14d sliding window are excluded from threshold', () => {
    const reports = [
      baseReport({ id: 'old', uuid_hash: 'u_old', ip_hash: 'i_old', created_at: WINDOW_START - 1 }),
      baseReport({ id: 'r1', uuid_hash: 'u1', ip_hash: 'i1', created_at: NOW - 300 }),
      baseReport({ id: 'r2', uuid_hash: 'u2', ip_hash: 'i2', created_at: NOW - 200 }),
    ]
    // Only 2 fresh uuids → below threshold.
    expect(computeAggregations(reports, NOW)).toEqual([])
  })

  test('reports at window boundary (exactly 14d ago) are included', () => {
    const reports = [
      baseReport({ id: 'r1', uuid_hash: 'u1', ip_hash: 'i1', created_at: WINDOW_START }),
      baseReport({ id: 'r2', uuid_hash: 'u2', ip_hash: 'i2', created_at: NOW - 100 }),
      baseReport({ id: 'r3', uuid_hash: 'u3', ip_hash: 'i1', created_at: NOW - 50 }),
    ]
    const result = computeAggregations(reports, NOW)
    expect(result).toHaveLength(1)
    expect(result[0].unique_uuid_count).toBe(3)
  })

  test('different domains are grouped separately', () => {
    const reports = [
      // example.com (above threshold)
      baseReport({ id: 'a1', domain: 'example.com', url_path_hash: 'p1', uuid_hash: 'u1', ip_hash: 'i1', created_at: NOW - 300 }),
      baseReport({ id: 'a2', domain: 'example.com', url_path_hash: 'p1', uuid_hash: 'u2', ip_hash: 'i2', created_at: NOW - 200 }),
      baseReport({ id: 'a3', domain: 'example.com', url_path_hash: 'p1', uuid_hash: 'u3', ip_hash: 'i1', created_at: NOW - 100 }),
      // other.com (below threshold)
      baseReport({ id: 'b1', domain: 'other.com', url_path_hash: 'p2', uuid_hash: 'u4', ip_hash: 'i3', created_at: NOW - 50 }),
    ]
    const result = computeAggregations(reports, NOW)
    expect(result).toHaveLength(1)
    expect(result[0].domain).toBe('example.com')
  })

  test('same domain but different url_path_hash are grouped separately', () => {
    const reports = [
      // p1 (above threshold)
      baseReport({ id: 'a1', url_path_hash: 'p1', uuid_hash: 'u1', ip_hash: 'i1', created_at: NOW - 300 }),
      baseReport({ id: 'a2', url_path_hash: 'p1', uuid_hash: 'u2', ip_hash: 'i2', created_at: NOW - 200 }),
      baseReport({ id: 'a3', url_path_hash: 'p1', uuid_hash: 'u3', ip_hash: 'i1', created_at: NOW - 100 }),
      // p2 (also above threshold)
      baseReport({ id: 'b1', url_path_hash: 'p2', url: 'https://example.com/b', uuid_hash: 'u4', ip_hash: 'i3', created_at: NOW - 90 }),
      baseReport({ id: 'b2', url_path_hash: 'p2', url: 'https://example.com/b', uuid_hash: 'u5', ip_hash: 'i4', created_at: NOW - 80 }),
      baseReport({ id: 'b3', url_path_hash: 'p2', url: 'https://example.com/b', uuid_hash: 'u6', ip_hash: 'i3', created_at: NOW - 70 }),
    ]
    const result = computeAggregations(reports, NOW)
    expect(result).toHaveLength(2)
    const paths = result.map((r) => r.url_path_hash).sort()
    expect(paths).toEqual(['p1', 'p2'])
  })

  test('duplicate uuid_hash within same group counts as one', () => {
    const reports = [
      baseReport({ id: 'r1', uuid_hash: 'u1', ip_hash: 'i1', created_at: NOW - 300 }),
      baseReport({ id: 'r2', uuid_hash: 'u1', ip_hash: 'i2', created_at: NOW - 200 }), // same uuid as r1
      baseReport({ id: 'r3', uuid_hash: 'u2', ip_hash: 'i3', created_at: NOW - 100 }),
    ]
    // unique_uuid_count = 2 (u1, u2) → below threshold of 3.
    expect(computeAggregations(reports, NOW)).toEqual([])
  })

  test('configurable thresholds (minUuid / minIp / windowDays)', () => {
    const reports = [
      baseReport({ id: 'r1', uuid_hash: 'u1', ip_hash: 'i1', created_at: NOW - 100 }),
      baseReport({ id: 'r2', uuid_hash: 'u2', ip_hash: 'i2', created_at: NOW - 50 }),
    ]
    // With minUuid=2 + minIp=2, this should pass.
    const result = computeAggregations(reports, NOW, { minUuid: 2, minIp: 2, windowDays: 14 })
    expect(result).toHaveLength(1)
    expect(result[0].unique_uuid_count).toBe(2)
  })
})

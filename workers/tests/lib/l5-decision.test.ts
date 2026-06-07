// Plan B Task 2.1 (L5 CDN protection): pure decision logic.

import { describe, expect, test } from 'vitest'
import { decideL5 } from '../../src/lib/l5-decision'

describe('decideL5', () => {
  test('CDN exact match → rejected_cdn', () => {
    expect(decideL5({ id: 'c1', domain: 'cloudfront.net' })).toEqual({
      id: 'c1',
      l5_check: 'fail',
      next_status: 'rejected_cdn',
    })
  })

  test('CDN subdomain match → rejected_cdn', () => {
    expect(decideL5({ id: 'c2', domain: 'd123.cloudfront.net' }).next_status).toBe(
      'rejected_cdn'
    )
  })

  test('non-CDN domain → validating (passes through)', () => {
    expect(decideL5({ id: 'c3', domain: 'ads.example.com' })).toEqual({
      id: 'c3',
      l5_check: 'pass',
      next_status: 'validating',
    })
  })

  test('does not match substring (suffix boundary required)', () => {
    expect(decideL5({ id: 'c4', domain: 'notcloudfront.net' }).next_status).toBe(
      'validating'
    )
  })
})

import { describe, it, expect } from 'vitest'
import { BAN_ELIGIBLE_REASONS } from '../../src/lib/ban-engine-core'

describe('BAN_ELIGIBLE_REASONS', () => {
  it('excludes critical_domain and pii_redacted (honest-user reasons)', () => {
    expect(BAN_ELIGIBLE_REASONS).not.toContain('critical_domain')
    expect(BAN_ELIGIBLE_REASONS).not.toContain('pii_redacted')
  })
  it('keeps the malicious-pattern reasons', () => {
    expect(BAN_ELIGIBLE_REASONS).toContain('rate_limit')
    expect(BAN_ELIGIBLE_REASONS).toContain('spam_memo')
    expect(BAN_ELIGIBLE_REASONS).toContain('invalid_url')
  })
})
import {
  computeBanActions,
  type AbuseAggregate,
  type ExistingBanRow,
} from '../../src/lib/ban-engine-core'

const NOW = 1_700_000_000
const HEX64 = (c: string) => c.repeat(64)
const ID_A = HEX64('a')
const ID_B = HEX64('b')
const ID_C = HEX64('c')

describe('computeBanActions', () => {
  it('returns empty array when no abuse rows', () => {
    expect(computeBanActions([], [], NOW)).toEqual([])
  })

  it('skips identifiers with count below L1 threshold (3)', () => {
    const rows: AbuseAggregate[] = [
      { identifier_hash: ID_A, identifier_type: 'uuid', count: 2 },
    ]
    expect(computeBanActions(rows, [], NOW)).toEqual([])
  })

  it('inserts L1 ban (24h) for count 3 with no existing ban', () => {
    const rows: AbuseAggregate[] = [
      { identifier_hash: ID_A, identifier_type: 'uuid', count: 3 },
    ]
    const actions = computeBanActions(rows, [], NOW)
    expect(actions).toHaveLength(1)
    expect(actions[0]).toEqual({
      kind: 'insert',
      identifier_hash: ID_A,
      identifier_type: 'uuid',
      abuse_count: 3,
      ban_level: 1,
      expires_at: NOW + 24 * 3600,
      reason: 'auto_initial',
    })
  })

  it('inserts L4 (permanent) for count >= 100', () => {
    const rows: AbuseAggregate[] = [
      { identifier_hash: ID_A, identifier_type: 'ip', count: 250 },
    ]
    const actions = computeBanActions(rows, [], NOW)
    expect(actions).toHaveLength(1)
    expect(actions[0].kind).toBe('insert')
    if (actions[0].kind === 'insert') {
      expect(actions[0].ban_level).toBe(4)
      expect(actions[0].expires_at).toBe(NOW + 100 * 365 * 24 * 3600)
      expect(actions[0].identifier_type).toBe('ip')
    }
  })

  it('upgrades existing L1 to L2 when count reaches 10', () => {
    const rows: AbuseAggregate[] = [
      { identifier_hash: ID_A, identifier_type: 'uuid', count: 10 },
    ]
    const existing: ExistingBanRow[] = [
      { identifier_hash: ID_A, ban_level: 1, abuse_count: 3 },
    ]
    const actions = computeBanActions(rows, existing, NOW)
    expect(actions).toHaveLength(1)
    expect(actions[0]).toEqual({
      kind: 'upgrade',
      identifier_hash: ID_A,
      abuse_count: 10,
      ban_level: 2,
      expires_at: NOW + 7 * 24 * 3600,
      reason: 'auto_escalation',
    })
  })

  it('does not downgrade or re-issue when existing level >= computed level', () => {
    const rows: AbuseAggregate[] = [
      { identifier_hash: ID_A, identifier_type: 'uuid', count: 10 },
      { identifier_hash: ID_B, identifier_type: 'uuid', count: 5 },
    ]
    const existing: ExistingBanRow[] = [
      { identifier_hash: ID_A, ban_level: 2, abuse_count: 12 },
      { identifier_hash: ID_B, ban_level: 1, abuse_count: 4 },
    ]
    expect(computeBanActions(rows, existing, NOW)).toEqual([])
  })

  it('keeps L4 permanent ban regardless of subsequent counts', () => {
    const rows: AbuseAggregate[] = [
      { identifier_hash: ID_A, identifier_type: 'uuid', count: 1000 },
    ]
    const existing: ExistingBanRow[] = [
      { identifier_hash: ID_A, ban_level: 4, abuse_count: 200 },
    ]
    expect(computeBanActions(rows, existing, NOW)).toEqual([])
  })

  it('reissues an expired same-level ban with kind=upgrade reason=auto_reissue', () => {
    const rows: AbuseAggregate[] = [
      { identifier_hash: ID_A, identifier_type: 'uuid', count: 3 },
    ]
    const existing: ExistingBanRow[] = [
      { identifier_hash: ID_A, ban_level: 1, abuse_count: 3, expires_at: NOW - 100 },
    ]
    const actions = computeBanActions(rows, existing, NOW)
    expect(actions).toHaveLength(1)
    expect(actions[0]).toMatchObject({
      kind: 'upgrade',
      identifier_hash: ID_A,
      ban_level: 1,
      reason: 'auto_reissue',
      expires_at: NOW + 24 * 3600,
    })
  })

  it('does not reissue a same-level ban that is still active', () => {
    const rows: AbuseAggregate[] = [
      { identifier_hash: ID_A, identifier_type: 'uuid', count: 3 },
    ]
    const existing: ExistingBanRow[] = [
      { identifier_hash: ID_A, ban_level: 1, abuse_count: 3, expires_at: NOW + 3600 },
    ]
    expect(computeBanActions(rows, existing, NOW)).toEqual([])
  })

  it('handles multiple identifiers independently in one pass', () => {
    const rows: AbuseAggregate[] = [
      { identifier_hash: ID_A, identifier_type: 'uuid', count: 5 },
      { identifier_hash: ID_B, identifier_type: 'ip', count: 30 },
      { identifier_hash: ID_C, identifier_type: 'uuid', count: 2 },
    ]
    const existing: ExistingBanRow[] = [
      { identifier_hash: ID_B, ban_level: 1, abuse_count: 4 },
    ]
    const actions = computeBanActions(rows, existing, NOW)
    expect(actions).toHaveLength(2)
    const a = actions.find(
      (x) => 'identifier_hash' in x && x.identifier_hash === ID_A
    )
    const b = actions.find(
      (x) => 'identifier_hash' in x && x.identifier_hash === ID_B
    )
    expect(a?.kind).toBe('insert')
    if (a?.kind === 'insert') expect(a.ban_level).toBe(1)
    expect(b?.kind).toBe('upgrade')
    if (b?.kind === 'upgrade') expect(b.ban_level).toBe(3)
  })
})

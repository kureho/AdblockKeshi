// Plan C Chunk 1 Task 1.2: ban-engine runner (REST) test.

import { describe, expect, test } from 'vitest'
import { runBanEngineViaRest } from '../../../scripts/aggregation/ban-engine-runner'

interface FetchCall {
  url: string
  body: { sql: string; params: any[] }
}

function makeFetchMock(
  responses: Array<{ rows?: any[]; success?: boolean; error?: string }>
): { fetch: typeof fetch; calls: FetchCall[] } {
  const calls: FetchCall[] = []
  let idx = 0
  const fetchFn = (async (url: string, init: any) => {
    const body = JSON.parse(init.body)
    calls.push({ url, body })
    const r = responses[idx++] ?? { rows: [] }
    const payload = r.error
      ? { success: false, errors: [{ message: r.error }] }
      : {
          success: r.success ?? true,
          result: [{ results: r.rows ?? [], success: true }],
        }
    return new Response(JSON.stringify(payload), { status: 200 })
  }) as unknown as typeof fetch
  return { fetch: fetchFn, calls }
}

const ENV = {
  CF_API_TOKEN: 'test-token',
  CF_ACCOUNT_ID: 'acct123',
  CF_DATABASE_ID: 'db456',
}

const NOW = 2_000_000
const HEX64 = (c: string) => c.repeat(64)
const ID_A = HEX64('a')
const ID_B = HEX64('b')

describe('runBanEngineViaRest', () => {
  test('no abuse rows → no further queries, no writes', async () => {
    const { fetch, calls } = makeFetchMock([{ rows: [] }])
    const result = await runBanEngineViaRest(ENV, { fetch, now: () => NOW })
    expect(result).toEqual({ banned: 0, upgraded: 0 })
    expect(calls).toHaveLength(1)
    expect(calls[0].body.sql).toMatch(/SELECT/i)
    expect(calls[0].body.sql).toMatch(/abuse_log/)
    expect(calls[0].body.sql).toMatch(/reason IN/i)
    // critical_domain は ban 材料にしない（正直ユーザーの保護ドメイン報告を封じないため）
    expect(calls[0].body.sql).not.toMatch(/critical_domain/)
  })

  test('below L1 threshold → existing query runs but no writes', async () => {
    const abuse = [
      { identifier_hash: ID_A, identifier_type: 'uuid', count: 2 },
    ]
    const { fetch, calls } = makeFetchMock([
      { rows: abuse },
      { rows: [] }, // existing bans query (empty)
    ])
    const result = await runBanEngineViaRest(ENV, { fetch, now: () => NOW })
    expect(result).toEqual({ banned: 0, upgraded: 0 })
    expect(calls).toHaveLength(2)
    expect(calls[1].body.sql).toMatch(/SELECT/i)
    expect(calls[1].body.sql).toMatch(/bans/)
  })

  test('above L1 with no existing → INSERT', async () => {
    const abuse = [
      { identifier_hash: ID_A, identifier_type: 'uuid', count: 3 },
    ]
    const { fetch, calls } = makeFetchMock([
      { rows: abuse },
      { rows: [] }, // no existing
      { rows: [] }, // INSERT response
    ])
    const result = await runBanEngineViaRest(ENV, { fetch, now: () => NOW })
    expect(result).toEqual({ banned: 1, upgraded: 0 })
    expect(calls).toHaveLength(3)
    expect(calls[2].body.sql).toMatch(/INSERT INTO bans/)
    expect(calls[2].body.params[0]).toBe(ID_A)
    expect(calls[2].body.params[1]).toBe('uuid')
    expect(calls[2].body.params[2]).toBe('auto_initial')
    expect(calls[2].body.params[3]).toBe(3)
    expect(calls[2].body.params[4]).toBe(1) // ban_level
    expect(calls[2].body.params[5]).toBe(NOW + 24 * 3600)
    expect(calls[2].body.params[6]).toBe(NOW)
  })

  test('existing L1, abuse hits 10 → UPDATE to L2', async () => {
    const abuse = [
      { identifier_hash: ID_A, identifier_type: 'uuid', count: 10 },
    ]
    const existing = [
      { identifier_hash: ID_A, ban_level: 1, abuse_count: 5 },
    ]
    const { fetch, calls } = makeFetchMock([
      { rows: abuse },
      { rows: existing },
      { rows: [] }, // UPDATE response
    ])
    const result = await runBanEngineViaRest(ENV, { fetch, now: () => NOW })
    expect(result).toEqual({ banned: 0, upgraded: 1 })
    expect(calls).toHaveLength(3)
    expect(calls[2].body.sql).toMatch(/UPDATE bans/)
    expect(calls[2].body.params[0]).toBe(2) // ban_level
    expect(calls[2].body.params[1]).toBe(10) // abuse_count
    expect(calls[2].body.params[2]).toBe(NOW + 7 * 24 * 3600)
    expect(calls[2].body.params[3]).toBe('auto_escalation')
    expect(calls[2].body.params[4]).toBe(ID_A)
  })

  test('existing L4 permanent, abuse 200 → no writes (no downgrade/re-issue)', async () => {
    const abuse = [
      { identifier_hash: ID_A, identifier_type: 'uuid', count: 200 },
    ]
    const existing = [
      { identifier_hash: ID_A, ban_level: 4, abuse_count: 150 },
    ]
    const { fetch, calls } = makeFetchMock([
      { rows: abuse },
      { rows: existing },
    ])
    const result = await runBanEngineViaRest(ENV, { fetch, now: () => NOW })
    expect(result).toEqual({ banned: 0, upgraded: 0 })
    expect(calls).toHaveLength(2)
  })

  test('mix: one insert + one upgrade in single run', async () => {
    const abuse = [
      { identifier_hash: ID_A, identifier_type: 'uuid', count: 3 },
      { identifier_hash: ID_B, identifier_type: 'ip', count: 30 },
    ]
    const existing = [
      { identifier_hash: ID_B, ban_level: 1, abuse_count: 5 },
    ]
    const { fetch, calls } = makeFetchMock([
      { rows: abuse },
      { rows: existing },
      { rows: [] }, // INSERT
      { rows: [] }, // UPDATE
    ])
    const result = await runBanEngineViaRest(ENV, { fetch, now: () => NOW })
    expect(result).toEqual({ banned: 1, upgraded: 1 })
    expect(calls).toHaveLength(4)
  })

  test('propagates D1 errors', async () => {
    const { fetch } = makeFetchMock([{ error: 'db unavailable' }])
    await expect(
      runBanEngineViaRest(ENV, { fetch, now: () => NOW })
    ).rejects.toThrow(/db unavailable/)
  })

  test('chunks existing-ban lookup to stay under D1_MAX_IN_PARAMS', async () => {
    // 200 identifiers, all below L1 threshold → no writes after lookup.
    // D1_MAX_IN_PARAMS = 90, so we expect ceil(200/90) = 3 SELECT statements.
    const abuse = Array.from({ length: 200 }, (_, i) => ({
      identifier_hash: HEX64(String.fromCharCode(33 + (i % 80))).slice(0, 64),
      identifier_type: 'uuid' as const,
      count: 1, // below threshold so no INSERT/UPDATE
    }))
    // Make each hash unique by prefixing the index.
    abuse.forEach((row, i) => {
      row.identifier_hash =
        i.toString(16).padStart(8, '0') + row.identifier_hash.slice(8)
    })
    const responses = [
      { rows: abuse },
      { rows: [] }, // chunk 1 existing
      { rows: [] }, // chunk 2 existing
      { rows: [] }, // chunk 3 existing
    ]
    const { fetch, calls } = makeFetchMock(responses)
    const result = await runBanEngineViaRest(ENV, { fetch, now: () => NOW })
    expect(result).toEqual({ banned: 0, upgraded: 0 })
    // 1 abuse SELECT + 3 existing SELECTs = 4 calls
    expect(calls).toHaveLength(4)
    // each chunk's IN clause must not exceed D1_MAX_IN_PARAMS placeholders
    for (let i = 1; i <= 3; i++) {
      const placeholderCount = (calls[i].body.sql.match(/\?/g) ?? []).length
      expect(placeholderCount).toBeLessThanOrEqual(90)
    }
    // sum of chunk params must equal the abuse cardinality
    const totalParams =
      calls[1].body.params.length +
      calls[2].body.params.length +
      calls[3].body.params.length
    expect(totalParams).toBe(200)
  })
})

// Plan B Task 1.3 orchestrator test.
// 2026-09-06: Tranco 判定を D1 テーブルから in-memory Set へ移行（D1 rows_written 超過対策）。

import { describe, expect, test } from 'vitest'
import { runTrancoCheck } from '../../../scripts/validation/tranco-check'

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
  CF_API_TOKEN: 't',
  CF_ACCOUNT_ID: 'a',
  CF_DATABASE_ID: 'd',
}

/** 既定は「Tranco に何も載っていない」集合。 */
function deps(fetch: typeof globalThis.fetch, domains: string[] = []) {
  return { fetch, loadTrancoSet: async () => new Set(domains) }
}

describe('runTrancoCheck', () => {
  test('no aggregating candidates → no updates', async () => {
    const { fetch, calls } = makeFetchMock([{ rows: [] }])
    const r = await runTrancoCheck(ENV, deps(fetch))
    expect(r).toEqual({ passed: 0, queued: 0, rejected: 0 })
    expect(calls).toHaveLength(1) // only the SELECT
  })

  test('all candidates pass → status=validating, l3_check=pass', async () => {
    const candidates = [
      { id: 'c1', domain: 'random-ad.example' },
      { id: 'c2', domain: 'sketchy.test' },
    ]
    const { fetch, calls } = makeFetchMock([
      { rows: candidates }, // SELECT candidates
      { rows: [] }, // batch UPDATE
    ])
    const r = await runTrancoCheck(ENV, deps(fetch))
    expect(r.passed).toBe(2)
    expect(r.queued).toBe(0)
    expect(r.rejected).toBe(0)
    const updateCall = calls.find((c) => /UPDATE rule_candidates/i.test(c.body.sql))
    expect(updateCall).toBeTruthy()
    expect(updateCall!.body.params[0]).toBe('validating')
    expect(updateCall!.body.params[1]).toBe('pass')
  })

  // D-lite: critical も自動却下せず kureho_queue へ（rejected は常に 0 になる）。
  test('critical-list hit → kureho_queue', async () => {
    const candidates = [{ id: 'c1', domain: 'apple.com' }]
    const { fetch, calls } = makeFetchMock([{ rows: candidates }, { rows: [] }])
    const r = await runTrancoCheck(ENV, deps(fetch))
    expect(r.queued).toBe(1)
    expect(r.rejected).toBe(0)
    expect(r.passed).toBe(0)
    const updateCall = calls.find((c) => /UPDATE rule_candidates/i.test(c.body.sql))
    expect(updateCall!.body.params[0]).toBe('kureho_queue')
    expect(updateCall!.body.params[1]).toBe('fail')
  })

  test('tranco hit（サブドメインは親ドメインで一致）→ kureho_queue', async () => {
    const candidates = [{ id: 'c1', domain: 'www.big-portal.com' }]
    const { fetch, calls } = makeFetchMock([{ rows: candidates }, { rows: [] }])
    const r = await runTrancoCheck(ENV, deps(fetch, ['big-portal.com']))
    expect(r.queued).toBe(1)
    const updateCall = calls.find((c) => /UPDATE rule_candidates/i.test(c.body.sql))
    expect(updateCall!.body.params[0]).toBe('kureho_queue')
    expect(updateCall!.body.params[1]).toBe('fail')
  })

  test('mixed: 1 critical + 1 tranco + 1 pass', async () => {
    const candidates = [
      { id: 'c1', domain: 'apple.com' },
      { id: 'c2', domain: 'www.big-portal.com' },
      { id: 'c3', domain: 'random.example' },
    ]
    const { fetch } = makeFetchMock([
      { rows: candidates },
      { rows: [] }, // UPDATE queued (critical + tranco が同じ status になる)
      { rows: [] }, // UPDATE passed
    ])
    const r = await runTrancoCheck(ENV, deps(fetch, ['big-portal.com']))
    expect(r).toEqual({ passed: 1, queued: 2, rejected: 0 })
  })

  // 回帰ガード: D1 の tranco テーブルを二度と参照しない（2026-09-06 の枠超過の原因）。
  test('tranco_top_1m を SQL で引かない', async () => {
    const candidates = [{ id: 'c1', domain: 'www.big-portal.com' }]
    const { fetch, calls } = makeFetchMock([{ rows: candidates }, { rows: [] }])
    await runTrancoCheck(ENV, deps(fetch, ['big-portal.com']))
    expect(calls.some((c) => /tranco/i.test(c.body.sql))).toBe(false)
  })

  test('D1 error propagates', async () => {
    const { fetch } = makeFetchMock([{ error: 'db offline' }])
    await expect(runTrancoCheck(ENV, deps(fetch))).rejects.toThrow(/db offline/)
  })
})

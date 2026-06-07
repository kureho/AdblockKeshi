// Plan B Task 1.3 weekly Tranco list sync.

import { describe, expect, test } from 'vitest'
import { parseTrancoCsv, runTrancoSync } from '../../../scripts/sync/tranco-sync'

const ENV = { CF_API_TOKEN: 't', CF_ACCOUNT_ID: 'a', CF_DATABASE_ID: 'd' }

describe('parseTrancoCsv', () => {
  test('parses rank,domain lines', () => {
    const csv = '1,google.com\n2,facebook.com\n3,youtube.com'
    expect(parseTrancoCsv(csv)).toEqual([
      { rank: 1, domain: 'google.com' },
      { rank: 2, domain: 'facebook.com' },
      { rank: 3, domain: 'youtube.com' },
    ])
  })

  test('ignores blank lines and trailing newlines', () => {
    const csv = '1,google.com\n\n2,facebook.com\n'
    expect(parseTrancoCsv(csv)).toEqual([
      { rank: 1, domain: 'google.com' },
      { rank: 2, domain: 'facebook.com' },
    ])
  })

  test('ignores malformed lines (no comma, non-numeric rank)', () => {
    const csv = '1,good.com\nnotacsv\nbad,nope\n3,fine.com'
    expect(parseTrancoCsv(csv)).toEqual([
      { rank: 1, domain: 'good.com' },
      { rank: 3, domain: 'fine.com' },
    ])
  })

  test('trims whitespace around domain', () => {
    const csv = '1, google.com '
    expect(parseTrancoCsv(csv)).toEqual([{ rank: 1, domain: 'google.com' }])
  })
})

function makeD1FetchMock(d1Responses: Array<{ rows?: any[]; error?: string }> = []) {
  const calls: Array<{ url: string; body: any }> = []
  let idx = 0
  const fetchFn = (async (url: string, init: any) => {
    calls.push({ url, body: JSON.parse(init.body) })
    const r = d1Responses[idx++] ?? { rows: [] }
    const payload = r.error
      ? { success: false, errors: [{ message: r.error }] }
      : { success: true, result: [{ results: r.rows ?? [], success: true }] }
    return new Response(JSON.stringify(payload), { status: 200 })
  }) as unknown as typeof fetch
  return { fetch: fetchFn, calls }
}

describe('runTrancoSync', () => {
  test('loads CSV via loader, deletes old rows, batch INSERTs new rows', async () => {
    const csv = '1,a.com\n2,b.com\n3,c.com'
    const { fetch, calls } = makeD1FetchMock()
    const result = await runTrancoSync(ENV, {
      fetch,
      now: () => 12345,
      loadCsv: async () => csv,
      batchSize: 100,
    })
    expect(result.rows_inserted).toBe(3)
    expect(calls[0].body.sql).toMatch(/DELETE FROM tranco_top_1m/i)
    expect(calls[1].body.sql).toMatch(/INSERT INTO tranco_top_1m/i)
    expect(calls[1].body.params).toContain('a.com')
    expect(calls[1].body.params).toContain('b.com')
  })

  test('batches large lists', async () => {
    const lines: string[] = []
    for (let i = 1; i <= 5; i++) lines.push(`${i},d${i}.com`)
    const csv = lines.join('\n')
    const { fetch, calls } = makeD1FetchMock()
    const result = await runTrancoSync(ENV, {
      fetch,
      now: () => 0,
      loadCsv: async () => csv,
      batchSize: 2,
    })
    expect(result.rows_inserted).toBe(5)
    const insertCalls = calls.filter((c) => /INSERT/i.test(c.body.sql))
    // batchSize=2, 5 rows → 3 inserts (2+2+1)
    expect(insertCalls).toHaveLength(3)
  })

  test('loadCsv error propagates', async () => {
    const { fetch } = makeD1FetchMock()
    await expect(
      runTrancoSync(ENV, {
        fetch,
        now: () => 0,
        loadCsv: async () => {
          throw new Error('Tranco 404')
        },
      })
    ).rejects.toThrow(/404|Tranco/)
  })
})

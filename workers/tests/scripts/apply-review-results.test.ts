// A-88 §2: review/results/*.json → D1 reports.review_outcome/reviewed_at 書き込みスクリプト。
import { describe, expect, test } from 'vitest'
import {
  parseReviewResultFile,
  applyReviewResultFiles,
} from '../../../scripts/review/apply-review-results'

function makeD1FetchMock() {
  const calls: Array<{ url: string; body: any }> = []
  const fetchFn = (async (url: string, init: any) => {
    calls.push({ url, body: JSON.parse(init.body) })
    return new Response(JSON.stringify({ success: true, result: [{ results: [], success: true }] }), { status: 200 })
  }) as unknown as typeof fetch
  return { fetch: fetchFn, calls }
}

const ENV = { CF_API_TOKEN: 't', CF_ACCOUNT_ID: 'a', CF_DATABASE_ID: 'd' }
const UUID_A = '11111111-1111-4111-8111-111111111111'
const UUID_B = '22222222-2222-4222-8222-222222222222'

const VALID_FILE_JSON = JSON.stringify({
  reviewed_at: '2026-09-27',
  results: [
    { report_id: UUID_A, outcome: 'applied', note: '広告セレクタを反映' },
    { report_id: UUID_B, outcome: 'not_reproduced' },
  ],
})

describe('parseReviewResultFile', () => {
  test('正常な形式をパースできる', () => {
    const parsed = parseReviewResultFile('r1.json', VALID_FILE_JSON)
    expect(parsed.items).toEqual([
      { reportId: UUID_A, outcome: 'applied' },
      { reportId: UUID_B, outcome: 'not_reproduced' },
    ])
    // 2026-09-27T00:00:00Z の unix 秒
    expect(parsed.reviewedAtSec).toBe(Math.floor(Date.parse('2026-09-27T00:00:00Z') / 1000))
  })

  test('不正な JSON は Error', () => {
    expect(() => parseReviewResultFile('bad.json', '{not json')).toThrow(/bad\.json/)
  })

  test('reviewed_at が無い/形式違いは Error', () => {
    expect(() => parseReviewResultFile('r.json', JSON.stringify({ results: [] }))).toThrow(/reviewed_at/)
    expect(() => parseReviewResultFile('r.json', JSON.stringify({ reviewed_at: '2026/09/27', results: [] }))).toThrow(/reviewed_at/)
  })

  test('results が空配列/無いは Error', () => {
    expect(() => parseReviewResultFile('r.json', JSON.stringify({ reviewed_at: '2026-09-27', results: [] }))).toThrow(/results/)
    expect(() => parseReviewResultFile('r.json', JSON.stringify({ reviewed_at: '2026-09-27' }))).toThrow(/results/)
  })

  test('report_id が UUID 形式でないと Error（ファイルごと失敗）', () => {
    const bad = JSON.stringify({ reviewed_at: '2026-09-27', results: [{ report_id: 'not-a-uuid', outcome: 'applied' }] })
    expect(() => parseReviewResultFile('bad-id.json', bad)).toThrow(/report_id/)
  })

  test('outcome が未知の値だと Error（ファイルごと失敗）', () => {
    const bad = JSON.stringify({ reviewed_at: '2026-09-27', results: [{ report_id: UUID_A, outcome: 'maybe' }] })
    expect(() => parseReviewResultFile('bad-outcome.json', bad)).toThrow(/outcome/)
  })
})

describe('applyReviewResultFiles', () => {
  test('正常ファイル → UPDATE reports が report_id ごとに走る', async () => {
    const { fetch, calls } = makeD1FetchMock()
    const results = await applyReviewResultFiles(ENV, [{ name: 'r1.json', raw: VALID_FILE_JSON }], { fetch })
    expect(results).toEqual([{ fileName: 'r1.json', ok: true, updated: 2 }])
    expect(calls).toHaveLength(2)
    for (const c of calls) {
      expect(c.body.sql).toMatch(/UPDATE reports SET review_outcome = \?, reviewed_at = \? WHERE id = \?/)
    }
    expect(calls[0].body.params).toEqual(['applied', Math.floor(Date.parse('2026-09-27T00:00:00Z') / 1000), UUID_A])
    expect(calls[1].body.params).toEqual(['not_reproduced', Math.floor(Date.parse('2026-09-27T00:00:00Z') / 1000), UUID_B])
  })

  test('不正なファイルはそのファイルだけ失敗し、他の正常ファイルは適用される', async () => {
    const { fetch, calls } = makeD1FetchMock()
    const badJson = JSON.stringify({ reviewed_at: '2026-09-27', results: [{ report_id: 'not-a-uuid', outcome: 'applied' }] })
    const results = await applyReviewResultFiles(
      ENV,
      [
        { name: 'bad.json', raw: badJson },
        { name: 'good.json', raw: VALID_FILE_JSON },
      ],
      { fetch }
    )
    const bad = results.find((r) => r.fileName === 'bad.json')!
    const good = results.find((r) => r.fileName === 'good.json')!
    expect(bad.ok).toBe(false)
    expect(bad.error).toMatch(/report_id/)
    expect(good.ok).toBe(true)
    expect(good.updated).toBe(2)
    // bad.json からは1件も D1 に書かれない
    expect(calls).toHaveLength(2)
  })

  test('dryRun: D1 に書き込まず SQL だけ返す', async () => {
    const { fetch, calls } = makeD1FetchMock()
    const results = await applyReviewResultFiles(ENV, [{ name: 'r1.json', raw: VALID_FILE_JSON }], { fetch, dryRun: true })
    expect(calls).toHaveLength(0)
    expect(results[0].ok).toBe(true)
    expect(results[0].updated).toBe(2)
    expect(results[0].statements).toHaveLength(2)
    expect(results[0].statements![0].params).toEqual(['applied', Math.floor(Date.parse('2026-09-27T00:00:00Z') / 1000), UUID_A])
  })

  test('冪等性: 同じファイルを2回流しても同じ UPDATE が同じ引数で流れる', async () => {
    const run1 = makeD1FetchMock()
    const run2 = makeD1FetchMock()
    await applyReviewResultFiles(ENV, [{ name: 'r1.json', raw: VALID_FILE_JSON }], { fetch: run1.fetch })
    await applyReviewResultFiles(ENV, [{ name: 'r1.json', raw: VALID_FILE_JSON }], { fetch: run2.fetch })
    expect(run1.calls.map((c) => c.body)).toEqual(run2.calls.map((c) => c.body))
  })

  test('files が空配列 → 何も呼ばず空配列を返す', async () => {
    const { fetch, calls } = makeD1FetchMock()
    const results = await applyReviewResultFiles(ENV, [], { fetch })
    expect(results).toEqual([])
    expect(calls).toHaveLength(0)
  })

  test('同一ファイル内で report_id が重複していても、両方 UPDATE が走る', async () => {
    const { fetch, calls } = makeD1FetchMock()
    const dup = JSON.stringify({
      reviewed_at: '2026-09-27',
      results: [
        { report_id: UUID_A, outcome: 'applied' },
        { report_id: UUID_A, outcome: 'not_reproduced' },
      ],
    })
    const results = await applyReviewResultFiles(ENV, [{ name: 'dup.json', raw: dup }], { fetch })
    expect(results[0].ok).toBe(true)
    expect(results[0].updated).toBe(2)
    expect(calls).toHaveLength(2)
    // 後勝ち: 2回目の UPDATE がそのまま最終値になる（idempotent な UPDATE の連続適用なので問題ない）
    expect(calls[1].body.params[0]).toBe('not_reproduced')
  })

  test('D1 側で対象 ID が存在せず0行更新でも成功扱いになる（存在確認オラクルにしない）', async () => {
    const calls: Array<{ url: string; body: any }> = []
    const fetchFn = (async (url: string, init: any) => {
      calls.push({ url, body: JSON.parse(init.body) })
      // D1 REST は WHERE に一致行が無くても success:true を返す（UPDATE 自体は正常終了のため）
      return new Response(JSON.stringify({ success: true, result: [{ results: [], meta: { changes: 0 }, success: true }] }), { status: 200 })
    }) as unknown as typeof fetch
    const results = await applyReviewResultFiles(ENV, [{ name: 'r1.json', raw: VALID_FILE_JSON }], { fetch: fetchFn })
    expect(results[0].ok).toBe(true)
    expect(results[0].updated).toBe(2)
    expect(calls).toHaveLength(2)
  })

  test('実行時（D1）エラーはそのファイルだけ ok=false にし、途中まで書けた件数を保持しつつ他のファイルは続行する', async () => {
    const calls: Array<{ url: string; body: any }> = []
    let callCount = 0
    const fetchFn = (async (url: string, init: any) => {
      callCount++
      const body = JSON.parse(init.body)
      calls.push({ url, body })
      // 1件目の UPDATE (UUID_A) は成功、2件目 (UUID_B) で D1 障害を模擬する
      if (callCount === 2) {
        return new Response(JSON.stringify({ success: false, errors: [{ message: 'D1_ERROR: temporary failure' }] }), { status: 200 })
      }
      return new Response(JSON.stringify({ success: true, result: [{ results: [], success: true }] }), { status: 200 })
    }) as unknown as typeof fetch

    const results = await applyReviewResultFiles(
      ENV,
      [
        { name: 'fails.json', raw: VALID_FILE_JSON }, // 2件中1件目で失敗する
        { name: 'good.json', raw: JSON.stringify({ reviewed_at: '2026-09-27', results: [{ report_id: UUID_A, outcome: 'applied' }] }) },
      ],
      { fetch: fetchFn }
    )

    const failed = results.find((r) => r.fileName === 'fails.json')!
    const good = results.find((r) => r.fileName === 'good.json')!
    expect(failed.ok).toBe(false)
    expect(failed.updated).toBe(1) // 1件目 (UUID_A) までは書けている
    expect(failed.error).toMatch(/D1_ERROR/)
    // fails.json が失敗しても good.json は続けて適用される
    expect(good.ok).toBe(true)
    expect(good.updated).toBe(1)
    expect(calls).toHaveLength(3) // fails.json 2回（1成功+1失敗） + good.json 1回
  })
})

// A-88 §2: 止まっている kureho_queue の候補に出口を作る。判定したら candidates に書いて閉じる
// （ルールが要るなら review/rules/ にサイト限定で書く＝候補の rule_text はそのまま配らない）。
describe('candidates（止まっている候補を閉じる）', () => {
  const UUID_C = '33333333-3333-4333-8333-333333333333'
  const CLOSE_SQL = `UPDATE rule_candidates SET status = 'closed_by_review' WHERE id = ? AND status = 'kureho_queue'`

  test('results が空でも candidates があればパースできる', () => {
    const raw = JSON.stringify({ reviewed_at: '2026-09-28', results: [], candidates: [{ candidate_id: UUID_C, decision: 'closed' }] })
    const parsed = parseReviewResultFile('c.json', raw)
    expect(parsed.items).toEqual([])
    expect(parsed.candidateIds).toEqual([UUID_C])
  })

  test('results も candidates も空なら Error', () => {
    const raw = JSON.stringify({ reviewed_at: '2026-09-28', results: [], candidates: [] })
    expect(() => parseReviewResultFile('c.json', raw)).toThrow()
  })

  test('candidate_id が UUID でない・decision が未知なら Error（ファイルごと失敗）', () => {
    const bad1 = JSON.stringify({ reviewed_at: '2026-09-28', results: [], candidates: [{ candidate_id: 'x', decision: 'closed' }] })
    const bad2 = JSON.stringify({ reviewed_at: '2026-09-28', results: [], candidates: [{ candidate_id: UUID_C, decision: 'promote' }] })
    expect(() => parseReviewResultFile('c.json', bad1)).toThrow(/candidate_id/)
    expect(() => parseReviewResultFile('c.json', bad2)).toThrow(/decision/)
  })

  test('適用すると kureho_queue の候補だけを closed_by_review にする UPDATE が走る', async () => {
    const { fetch, calls } = makeD1FetchMock()
    const raw = JSON.stringify({
      reviewed_at: '2026-09-28',
      results: [{ report_id: UUID_A, outcome: 'site_own_ad' }],
      candidates: [{ candidate_id: UUID_C, decision: 'closed' }],
    })
    const res = await applyReviewResultFiles(ENV, [{ name: 'c.json', raw }], { fetch })
    expect(res[0].ok).toBe(true)
    expect(res[0].updated).toBe(2)
    expect(calls.map((c) => c.body.sql)).toContain(CLOSE_SQL)
    expect(calls.find((c) => c.body.sql === CLOSE_SQL)!.body.params).toEqual([UUID_C])
  })

  test('dryRun でも候補の UPDATE が予定に出る', async () => {
    const { fetch, calls } = makeD1FetchMock()
    const raw = JSON.stringify({ reviewed_at: '2026-09-28', results: [], candidates: [{ candidate_id: UUID_C, decision: 'closed' }] })
    const res = await applyReviewResultFiles(ENV, [{ name: 'c.json', raw }], { fetch, dryRun: true })
    expect(calls).toHaveLength(0)
    expect(res[0].statements).toEqual([{ sql: CLOSE_SQL, params: [UUID_C] }])
  })
})

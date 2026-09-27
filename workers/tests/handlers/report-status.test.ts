// A-88 §3: POST /v1/reports/status
import { describe, it, expect, beforeEach } from 'vitest'
import { SELF, env } from 'cloudflare:test'

const UUID_A = '11111111-1111-4111-8111-111111111111'
const UUID_B = '22222222-2222-4222-8222-222222222222'
const UUID_MISSING = '99999999-9999-4999-8999-999999999999'

async function insertReport(overrides: Partial<{
  id: string
  status: string
  applied_at: number | null
  review_outcome: string | null
  url: string
  memo: string | null
  uuid_hash: string
}> = {}) {
  const now = Math.floor(Date.now() / 1000)
  const r = {
    id: UUID_A,
    uuid_hash: 'a'.repeat(64),
    ip_hash: 'iphash',
    domain: 'example.com',
    url: 'https://example.com/secret-path',
    url_path_hash: 'h1',
    memo: 'secret memo',
    status: 'pending',
    created_at: now,
    applied_at: null as number | null,
    review_outcome: null as string | null,
    ...overrides,
  }
  await env.DB.prepare(
    `INSERT INTO reports (id, uuid_hash, ip_hash, domain, url, url_path_hash, memo, status, created_at, applied_at, review_outcome)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
  ).bind(r.id, r.uuid_hash, r.ip_hash, r.domain, r.url, r.url_path_hash, r.memo, r.status, r.created_at, r.applied_at, r.review_outcome).run()
  return r
}

async function post(body: unknown) {
  return SELF.fetch('https://test/v1/reports/status', {
    method: 'POST',
    body: JSON.stringify(body),
    headers: { 'Content-Type': 'application/json' },
  })
}

describe('POST /v1/reports/status', () => {
  beforeEach(async () => {
    await env.DB.prepare('DELETE FROM reports').run()
  })

  it('405: GET は許可しない', async () => {
    const res = await SELF.fetch('https://test/v1/reports/status', { method: 'GET' })
    expect(res.status).toBe(405)
  })

  it('400: 不正な JSON', async () => {
    const res = await SELF.fetch('https://test/v1/reports/status', {
      method: 'POST',
      body: '{invalid',
      headers: { 'Content-Type': 'application/json' },
    })
    expect(res.status).toBe(400)
  })

  it('400: ids が空配列', async () => {
    const res = await post({ ids: [] })
    expect(res.status).toBe(400)
  })

  it('400: ids が無い', async () => {
    const res = await post({})
    expect(res.status).toBe(400)
  })

  it('400: ids が21件（上限超過）', async () => {
    const ids = Array.from({ length: 21 }, (_, i) => `11111111-1111-4111-8111-${String(i).padStart(12, '0')}`)
    const res = await post({ ids })
    expect(res.status).toBe(400)
  })

  it('200: ids がちょうど20件は許可される（D1 は読まれるので空でも 200）', async () => {
    const ids = Array.from({ length: 20 }, (_, i) => `11111111-1111-4111-8111-${String(i).padStart(12, '0')}`)
    const res = await post({ ids })
    expect(res.status).toBe(200)
    const body = await res.json() as any
    expect(body.items).toEqual([])
  })

  it('400: UUID 形式でない ID が混ざっている（D1 を読む前に弾く）', async () => {
    const res = await post({ ids: [UUID_A, 'not-a-uuid'] })
    expect(res.status).toBe(400)
    const body = await res.json() as any
    expect(body.error).toBe('validation_failed')
  })

  it('400: ids に文字列でない要素（null・数値）が混ざっている', async () => {
    const res1 = await post({ ids: [UUID_A, null] })
    expect(res1.status).toBe(400)
    const res2 = await post({ ids: [123] })
    expect(res2.status).toBe(400)
  })

  it('400: ids 自体が配列でない（文字列やオブジェクト）', async () => {
    const res1 = await post({ ids: UUID_A })
    expect(res1.status).toBe(400)
    const res2 = await post({ ids: { id: UUID_A } })
    expect(res2.status).toBe(400)
  })

  it('200: 存在しない ID は items に入らない（他人の ID との区別をさせない）', async () => {
    const res = await post({ ids: [UUID_MISSING] })
    expect(res.status).toBe(200)
    const body = await res.json() as any
    expect(body.items).toEqual([])
  })

  it('200: url/memo/uuid_hash 等の他列を一切返さない', async () => {
    await insertReport({ id: UUID_A, status: 'pending' })
    const res = await post({ ids: [UUID_A] })
    const body = await res.json() as any
    expect(body.items).toHaveLength(1)
    expect(Object.keys(body.items[0]).sort()).toEqual(['id', 'outcome'])
    expect(body.items[0]).toEqual({ id: UUID_A, outcome: 'checking' })
  })

  it('200: 重複 ID は1件として扱う', async () => {
    await insertReport({ id: UUID_A, status: 'pending' })
    const res = await post({ ids: [UUID_A, UUID_A, UUID_A] })
    const body = await res.json() as any
    expect(body.items).toHaveLength(1)
  })

  it('200: review_outcome があればそれを丸めて返す（applied）', async () => {
    await insertReport({ id: UUID_A, status: 'pending', review_outcome: 'applied' })
    const res = await post({ ids: [UUID_A] })
    const body = await res.json() as any
    expect(body.items[0].outcome).toBe('applied')
  })

  it('200: review_outcome=not_reproduced は declined に丸める', async () => {
    await insertReport({ id: UUID_A, status: 'pending', review_outcome: 'not_reproduced' })
    const res = await post({ ids: [UUID_A] })
    const body = await res.json() as any
    expect(body.items[0].outcome).toBe('declined')
  })

  it('200: review_outcome が無く applied_at があれば applied', async () => {
    await insertReport({ id: UUID_A, status: 'aggregated', applied_at: 1700000000 })
    const res = await post({ ids: [UUID_A] })
    const body = await res.json() as any
    expect(body.items[0].outcome).toBe('applied')
  })

  it('200: 複数 ID をまとめて解決する', async () => {
    await insertReport({ id: UUID_A, status: 'pending' })
    await insertReport({ id: UUID_B, status: 'pending', review_outcome: 'site_own_ad', uuid_hash: 'b'.repeat(64) })
    const res = await post({ ids: [UUID_A, UUID_B, UUID_MISSING] })
    const body = await res.json() as any
    expect(body.items).toHaveLength(2)
    const byId = Object.fromEntries(body.items.map((i: any) => [i.id, i.outcome]))
    expect(byId[UUID_A]).toBe('checking')
    expect(byId[UUID_B]).toBe('site_own_ad')
    expect(byId[UUID_MISSING]).toBeUndefined()
  })

  it('fetched_at を秒単位の unix time で返す', async () => {
    const res = await post({ ids: [UUID_A] })
    const body = await res.json() as any
    expect(body.fetched_at).toBeGreaterThan(1_700_000_000)
  })
})

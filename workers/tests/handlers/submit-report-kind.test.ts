import { describe, it, expect, beforeEach } from 'vitest'
import { SELF, env } from 'cloudflare:test'
import { signToken } from '../../src/lib/hmac'

const HEX64 = (c: string) => c.repeat(64)

async function makeToken(uuidHash: string): Promise<string> {
  return signToken(
    { subject: uuidHash, expires: Date.now() + 60000, scope: 'submit' },
    env.HMAC_KEY
  )
}

async function submit(uuid: string, extra: Record<string, unknown>): Promise<Response> {
  const token = await makeToken(uuid)
  return SELF.fetch('https://test/v1/reports/submit', {
    method: 'POST',
    body: JSON.stringify({
      token,
      uuid_hash: uuid,
      url: 'https://news.example.jp/article',
      ...extra,
    }),
    headers: { 'Content-Type': 'application/json' },
  })
}

/**
 * v4.2.0 report_kind（壊れ報告）の隔離契約。
 *
 * ★不変条件: `site_broken` は **どんな診断値でも `pending` に入らない**。
 * pending は広告集約（= ブロックを強める方向）が必ず消費する母集団なので、
 * 「壊れている」報告が混入すると、壊れているサイトをさらにブロックする方向へ誤学習する。
 */
describe('POST /v1/reports/submit report_kind', () => {
  beforeEach(async () => {
    await env.DB.prepare('DELETE FROM reports').run()
    await env.DB.prepare('DELETE FROM abuse_log').run()
    await env.DB.prepare('DELETE FROM bans').run()
  })

  it('site_broken (safari + blocker on) → status broken_site, never pending', async () => {
    const res = await submit(HEX64('a'), {
      report_kind: 'site_broken', seen_in: 'safari', blocker_enabled: true,
    })
    expect(res.status).toBe(200)
    const body = await res.json() as any
    expect(body.status).toBe('broken_site')

    const row = await env.DB.prepare('SELECT status, report_kind FROM reports WHERE id = ?')
      .bind(body.id).first<any>()
    expect(row.status).toBe('broken_site')
    expect(row.report_kind).toBe('site_broken')
  })

  it('site_broken (other_app) → also broken_site (診断値に関わらず隔離)', async () => {
    const res = await submit(HEX64('b'), {
      report_kind: 'site_broken', seen_in: 'other_app', blocker_enabled: false,
    })
    const body = await res.json() as any
    expect(body.status).toBe('broken_site')
  })

  it('ad_not_blocked → 従来どおり pending (集約対象)', async () => {
    const res = await submit(HEX64('c'), {
      report_kind: 'ad_not_blocked', seen_in: 'safari', blocker_enabled: true,
    })
    const body = await res.json() as any
    expect(body.status).toBe('pending')

    const row = await env.DB.prepare('SELECT report_kind FROM reports WHERE id = ?')
      .bind(body.id).first<any>()
    expect(row.report_kind).toBe('ad_not_blocked')
  })

  it('report_kind 未送信（旧クライアント）→ NULL 保存・status は従来ロジック', async () => {
    const res = await submit(HEX64('d'), { seen_in: 'safari', blocker_enabled: true })
    const body = await res.json() as any
    expect(body.status).toBe('pending')

    const row = await env.DB.prepare('SELECT report_kind FROM reports WHERE id = ?')
      .bind(body.id).first<any>()
    expect(row.report_kind).toBeNull()
  })

  it('未知の report_kind 値 → NULL 保存・広告扱い（seen_in 未知値と同じ前方互換方針）', async () => {
    const res = await submit(HEX64('e'), {
      report_kind: 'future_kind', seen_in: 'safari', blocker_enabled: true,
    })
    expect(res.status).toBe(200)
    const body = await res.json() as any
    expect(body.status).toBe('pending')

    const row = await env.DB.prepare('SELECT report_kind FROM reports WHERE id = ?')
      .bind(body.id).first<any>()
    expect(row.report_kind).toBeNull()
  })

  it('site_broken は旧クライアント相当（seen_in なし）でも broken_site', async () => {
    // 実際には新クライアントしか report_kind を送らないが、
    // 「site_broken が pending / observation_legacy に落ちる経路は存在しない」ことを固定する。
    const res = await submit(HEX64('f'), { report_kind: 'site_broken' })
    const body = await res.json() as any
    expect(body.status).toBe('broken_site')
  })
})

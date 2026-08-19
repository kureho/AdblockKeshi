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

  /**
   * ★2026-08-19 の反証レビューで仕様変更。
   * 旧仕様は「未知の report_kind → NULL 保存・広告扱い（= pending）」だったが、
   * 知らない種別名を送ってくるクライアントは「この サーバが知らない改善方向」を持っている。
   * それを広告集約（ブロックを強める方向）に入れると、壊れ報告系の新種別が増えたときに
   * 真逆へ誤学習する。方向が判定できないものは集約に入れず observation として保持する。
   * ★未送信（旧クライアント = 4.1.0 以前）は従来どおり広告扱いのまま（下のテスト）。
   */
  it('未知の report_kind 値 → 集約に入れず observation_unknown_kind へ隔離', async () => {
    const res = await submit(HEX64('e'), {
      report_kind: 'future_kind', seen_in: 'safari', blocker_enabled: true,
    })
    expect(res.status).toBe(200)
    const body = await res.json() as any
    expect(body.status).toBe('observation_unknown_kind')
    expect(body.status).not.toBe('pending')

    const row = await env.DB.prepare('SELECT report_kind, status FROM reports WHERE id = ?')
      .bind(body.id).first<any>()
    expect(row.report_kind).toBeNull()   // 既知値だけを列に保存する（生値は残さない）
    expect(row.status).toBe('observation_unknown_kind')
  })

  it('report_kind 未送信（旧クライアント）→ 従来どおり広告扱い（pending）', async () => {
    const res = await submit(HEX64('9'), { seen_in: 'safari', blocker_enabled: true })
    const body = await res.json() as any
    expect(body.status).toBe('pending')

    const row = await env.DB.prepare('SELECT report_kind FROM reports WHERE id = ?')
      .bind(body.id).first<any>()
    expect(row.report_kind).toBeNull()
  })

  it('型違いの report_kind（数値）も集約に入れない', async () => {
    const res = await submit(HEX64('8'), {
      report_kind: 42, seen_in: 'safari', blocker_enabled: true,
    })
    const body = await res.json() as any
    expect(body.status).toBe('observation_unknown_kind')
  })

  it('site_broken は旧クライアント相当（seen_in なし）でも broken_site', async () => {
    // 実際には新クライアントしか report_kind を送らないが、
    // 「site_broken が pending / observation_legacy に落ちる経路は存在しない」ことを固定する。
    const res = await submit(HEX64('f'), { report_kind: 'site_broken' })
    const body = await res.json() as any
    expect(body.status).toBe('broken_site')
  })
})

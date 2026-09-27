import { describe, it, expect, beforeEach } from 'vitest'
import { SELF, env } from 'cloudflare:test'
import { signToken } from '../../src/lib/hmac'

// A-88: 正規のアプリから来る普通の入力を「不正」と数えて送信停止にしていた件の回帰テスト。
// - アプリは貼り付けた文字数で URL を検査するが、送るのは日本語を %XX に置き換えた形
//   （生 73 字 → 送信形 233 字を実測）。サーバの 200 字上限で弾かれ invalid_url が記録されていた
// - メモはアプリが見た目の文字数・サーバが UTF-16 で数えていた（絵文字 150 個 = 300）
// - 停止中の再送・長さ超過が abuse_log に積まれ、停止が延びていた（3 件で 24h / 10 件で 7 日）

const HEX64 = (c: string) => c.repeat(64)

async function makeToken(uuidHash: string): Promise<string> {
  return signToken({ subject: uuidHash, expires: Date.now() + 60000, scope: 'submit' }, env.HMAC_KEY)
}

async function submit(uuid: string, extra: Record<string, unknown>) {
  const token = await makeToken(uuid)
  return SELF.fetch('https://test/v1/reports/submit', {
    method: 'POST',
    body: JSON.stringify({ token, uuid_hash: uuid, seen_in: 'safari', blocker_enabled: true, ...extra }),
    headers: { 'Content-Type': 'application/json' },
  })
}

async function abuseCount(identifier: string): Promise<number> {
  const row = await env.DB.prepare('SELECT COUNT(*) AS n FROM abuse_log WHERE identifier_hash = ?')
    .bind(identifier).first<{ n: number }>()
  return row?.n ?? 0
}

async function seedReports(uuid: string, count: number, createdAt: (i: number) => number) {
  for (let i = 0; i < count; i++) {
    await env.DB.prepare(
      'INSERT INTO reports (id, uuid_hash, ip_hash, domain, url, url_path_hash, status, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)'
    ).bind(`${uuid.slice(0, 4)}-${i}`, uuid, `ip-${i}`, 'example.com', `https://example.com/${i}`, `h${i}`, 'pending', createdAt(i)).run()
  }
}

describe('POST /v1/reports/submit — 正規の入力を不正扱いしない（A-88）', () => {
  beforeEach(async () => {
    await env.DB.prepare('DELETE FROM reports').run()
    await env.DB.prepare('DELETE FROM abuse_log').run()
    await env.DB.prepare('DELETE FROM bans').run()
  })

  it('日本語入りの URL（送信形 233 字）を受け付ける', async () => {
    const url = new URL('https://example-blog.jp/2026/09/iphone-safari-広告-消し方-おすすめ-アプリ-まとめ-比較-最新版/').href
    expect(url.length).toBe(233)
    const res = await submit(HEX64('a'), { url })
    expect(res.status).toBe(200)
  })

  it('URL は 2048 字まで受け付ける', async () => {
    const base = 'https://example.com/'
    const res = await submit(HEX64('b'), { url: base + 'a'.repeat(2048 - base.length) })
    expect(res.status).toBe(200)
  })

  it('2048 字を超える URL は 400 だが不正の記録には数えない', async () => {
    const uuid = HEX64('c')
    const base = 'https://example.com/'
    const res = await submit(uuid, { url: base + 'a'.repeat(2049 - base.length) })
    expect(res.status).toBe(400)
    expect(await abuseCount(uuid)).toBe(0)
  })

  it('絵文字 150 個のメモ（UTF-16 では 300）を受け付ける', async () => {
    const res = await submit(HEX64('d'), { url: 'https://example.com/a', memo: '😀'.repeat(150) })
    expect(res.status).toBe(200)
  })

  it('見た目 200 字のメモ（家族の絵文字・結合文字を含む）を受け付ける', async () => {
    const memo = '👨‍👩‍👧'.repeat(100) + 'が'.normalize('NFD').repeat(100)
    const res = await submit(HEX64('e'), { url: 'https://example.com/a', memo })
    expect(res.status).toBe(200)
  })

  it('見た目 201 字のメモは 400 だが不正の記録には数えない', async () => {
    const uuid = HEX64('f')
    const res = await submit(uuid, { url: 'https://example.com/a', memo: 'あ'.repeat(201) })
    expect(res.status).toBe(400)
    expect(await abuseCount(uuid)).toBe(0)
  })

  it('停止中の再送は 403 を返し、不正の記録を増やさない（停止が延びない）', async () => {
    const uuid = HEX64('g')
    const now = Math.floor(Date.now() / 1000)
    await env.DB.prepare(`
      INSERT INTO bans (identifier_hash, identifier_type, reason, abuse_count, ban_level, expires_at, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?)
    `).bind(uuid, 'uuid', 'rate_limit_repeat', 3, 1, now + 86400, now).run()

    for (let i = 0; i < 3; i++) {
      const res = await submit(uuid, { url: `https://example.com/retry${i}` })
      expect(res.status).toBe(403)
    }
    expect(await abuseCount(uuid)).toBe(0)
  })

  it('日と月の上限に同時に当たったら、長い方（月）を返す', async () => {
    const uuid = HEX64('h')
    const now = Math.floor(Date.now() / 1000)
    // 30 件のうち 5 件が直近 24 時間 → 日の上限（5）と月の上限（30）の両方に当たる
    await seedReports(uuid, 30, i => (i < 5 ? now - 60 : now - 10 * 86400))
    const res = await submit(uuid, { url: 'https://example.com/both' })
    expect(res.status).toBe(429)
    const body = await res.json() as { message: string; retry_after: number }
    expect(body.message).toBe('uuid_monthly_limit')
    expect(body.retry_after).toBe(30 * 86400)
  })
})

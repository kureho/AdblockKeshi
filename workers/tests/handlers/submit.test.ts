import { describe, it, expect, beforeEach } from 'vitest'
import { SELF, env } from 'cloudflare:test'
import { signToken } from '../../src/lib/hmac'

const HEX64 = (c: string) => c.repeat(64)

async function makeToken(scope: 'submit' | 'history' | 'delete' = 'submit', overrides?: { expires?: number }): Promise<string> {
  return signToken(
    { subject: 'anonymous', expires: overrides?.expires ?? Date.now() + 60000, scope },
    env.HMAC_KEY
  )
}

describe('POST /v1/reports/submit', () => {
  beforeEach(async () => {
    await env.DB.prepare('DELETE FROM reports').run()
    await env.DB.prepare('DELETE FROM abuse_log').run()
    await env.DB.prepare('DELETE FROM bans').run()
  })

  it('returns 200 and creates D1 row for valid submission', async () => {
    const token = await makeToken('submit')
    const response = await SELF.fetch('https://test/v1/reports/submit', {
      method: 'POST',
      body: JSON.stringify({
        token, uuid_hash: HEX64('a'),
        url: 'https://example.com/article', memo: 'overlay ad',
      }),
      headers: { 'Content-Type': 'application/json' },
    })
    expect(response.status).toBe(200)
    const body = await response.json() as any
    expect(body.id).toBeTruthy()
    expect(body.status).toBe('pending')
    expect(body.memo_redacted).toBe(false)

    const row = await env.DB.prepare('SELECT * FROM reports WHERE id = ?').bind(body.id).first<any>()
    expect(row.url).toBe('https://example.com/article')
    expect(row.memo).toBe('overlay ad')
  })

  it('redacts PII in memo and sets memo_redacted=true + abuse_log entry', async () => {
    const token = await makeToken('submit')
    const response = await SELF.fetch('https://test/v1/reports/submit', {
      method: 'POST',
      body: JSON.stringify({
        token, uuid_hash: HEX64('b'),
        url: 'https://news.example.jp/page', memo: '電話 03-1234-5678 を見せる広告',
      }),
      headers: { 'Content-Type': 'application/json' },
    })
    expect(response.status).toBe(200)
    const body = await response.json() as any
    expect(body.memo_redacted).toBe(true)

    const row = await env.DB.prepare('SELECT memo FROM reports WHERE id = ?').bind(body.id).first<any>()
    expect(row.memo).toContain('***-****-****')

    const abuse = await env.DB.prepare(
      'SELECT reason FROM abuse_log WHERE identifier_hash = ?'
    ).bind(HEX64('b')).first<any>()
    expect(abuse.reason).toBe('pii_redacted')
  })

  it('rejects with 400 for non-https URL', async () => {
    const token = await makeToken('submit')
    const response = await SELF.fetch('https://test/v1/reports/submit', {
      method: 'POST',
      body: JSON.stringify({ token, uuid_hash: HEX64('c'), url: 'http://no-https.com' }),
      headers: { 'Content-Type': 'application/json' },
    })
    expect(response.status).toBe(400)
  })

  it('rejects critical domain (apple.com)', async () => {
    const token = await makeToken('submit')
    const response = await SELF.fetch('https://test/v1/reports/submit', {
      method: 'POST',
      body: JSON.stringify({ token, uuid_hash: HEX64('d'), url: 'https://apple.com/support' }),
      headers: { 'Content-Type': 'application/json' },
    })
    expect(response.status).toBe(400)
    const body = await response.json() as any
    expect(body.message).toContain('critical')
  })

  it('rejects critical subdomain (developer.apple.com)', async () => {
    const token = await makeToken('submit')
    const response = await SELF.fetch('https://test/v1/reports/submit', {
      method: 'POST',
      body: JSON.stringify({ token, uuid_hash: HEX64('e'), url: 'https://developer.apple.com/docs' }),
      headers: { 'Content-Type': 'application/json' },
    })
    expect(response.status).toBe(400)
  })

  it('rejects with 401 for invalid token', async () => {
    const response = await SELF.fetch('https://test/v1/reports/submit', {
      method: 'POST',
      body: JSON.stringify({
        token: 'invalid.signature',
        uuid_hash: HEX64('f'), url: 'https://example.com/x',
      }),
      headers: { 'Content-Type': 'application/json' },
    })
    expect(response.status).toBe(401)
  })

  it('rejects with 401 for wrong scope token', async () => {
    const token = await makeToken('history')
    const response = await SELF.fetch('https://test/v1/reports/submit', {
      method: 'POST',
      body: JSON.stringify({ token, uuid_hash: HEX64('g'), url: 'https://example.com/x' }),
      headers: { 'Content-Type': 'application/json' },
    })
    expect(response.status).toBe(401)
  })

  it('rejects with 429 after 5 reports/day per uuid', async () => {
    const token = await makeToken('submit')
    const uuidHash = HEX64('h')
    const now = Math.floor(Date.now() / 1000)
    for (let i = 0; i < 5; i++) {
      await env.DB.prepare(
        'INSERT INTO reports (id, uuid_hash, ip_hash, domain, url, url_path_hash, status, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)'
      ).bind(`r${i}`, uuidHash, 'ip', 'example.com', `https://example.com/${i}`, `hash${i}`, 'pending', now).run()
    }
    const response = await SELF.fetch('https://test/v1/reports/submit', {
      method: 'POST',
      body: JSON.stringify({ token, uuid_hash: uuidHash, url: 'https://example.com/6' }),
      headers: { 'Content-Type': 'application/json' },
    })
    expect(response.status).toBe(429)
    const body = await response.json() as any
    expect(body.error).toBe('rate_limit_exceeded')
  })

  it('rejects with 403 if banned', async () => {
    const token = await makeToken('submit')
    const uuidHash = HEX64('i')
    const now = Math.floor(Date.now() / 1000)
    await env.DB.prepare(`
      INSERT INTO bans (identifier_hash, identifier_type, reason, abuse_count, ban_level, expires_at, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?)
    `).bind(uuidHash, 'uuid', 'rate_limit_repeat', 5, 2, now + 7 * 86400, now).run()

    const response = await SELF.fetch('https://test/v1/reports/submit', {
      method: 'POST',
      body: JSON.stringify({ token, uuid_hash: uuidHash, url: 'https://example.com/x' }),
      headers: { 'Content-Type': 'application/json' },
    })
    expect(response.status).toBe(403)
  })
})

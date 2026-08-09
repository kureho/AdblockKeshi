import { describe, it, expect, beforeEach } from 'vitest'
import { SELF, env } from 'cloudflare:test'
import { signToken } from '../../src/lib/hmac'

const HEX64 = (c: string) => c.repeat(64)

async function makeToken(uuidHash: string, scope: 'submit' | 'history' | 'delete' = 'submit', overrides?: { expires?: number }): Promise<string> {
  return signToken(
    { subject: uuidHash, expires: overrides?.expires ?? Date.now() + 60000, scope },
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
    const uuid = HEX64('a')
    const token = await makeToken(uuid, 'submit')
    const response = await SELF.fetch('https://test/v1/reports/submit', {
      method: 'POST',
      body: JSON.stringify({ token, uuid_hash: uuid, url: 'https://example.com/article', memo: 'overlay ad' }),
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
    const uuid = HEX64('b')
    const token = await makeToken(uuid, 'submit')
    const response = await SELF.fetch('https://test/v1/reports/submit', {
      method: 'POST',
      body: JSON.stringify({ token, uuid_hash: uuid, url: 'https://news.example.jp/page', memo: '電話 03-1234-5678 を見せる広告' }),
      headers: { 'Content-Type': 'application/json' },
    })
    expect(response.status).toBe(200)
    const body = await response.json() as any
    expect(body.memo_redacted).toBe(true)

    const row = await env.DB.prepare('SELECT memo FROM reports WHERE id = ?').bind(body.id).first<any>()
    expect(row.memo).toContain('***-****-****')

    const abuse = await env.DB.prepare(
      'SELECT reason FROM abuse_log WHERE identifier_hash = ?'
    ).bind(uuid).first<any>()
    expect(abuse.reason).toBe('pii_redacted')
  })

  it('rejects with 400 for non-https URL', async () => {
    const uuid = HEX64('c')
    const token = await makeToken(uuid, 'submit')
    const response = await SELF.fetch('https://test/v1/reports/submit', {
      method: 'POST',
      body: JSON.stringify({ token, uuid_hash: uuid, url: 'http://no-https.com' }),
      headers: { 'Content-Type': 'application/json' },
    })
    expect(response.status).toBe(400)
  })

  it('rejects critical domain (apple.com)', async () => {
    const uuid = HEX64('d')
    const token = await makeToken(uuid, 'submit')
    const response = await SELF.fetch('https://test/v1/reports/submit', {
      method: 'POST',
      body: JSON.stringify({ token, uuid_hash: uuid, url: 'https://apple.com/support' }),
      headers: { 'Content-Type': 'application/json' },
    })
    expect(response.status).toBe(400)
    const body = await response.json() as any
    expect(body.message).toContain('critical')
  })

  it('rejects critical subdomain (developer.apple.com)', async () => {
    const uuid = HEX64('e')
    const token = await makeToken(uuid, 'submit')
    const response = await SELF.fetch('https://test/v1/reports/submit', {
      method: 'POST',
      body: JSON.stringify({ token, uuid_hash: uuid, url: 'https://developer.apple.com/docs' }),
      headers: { 'Content-Type': 'application/json' },
    })
    expect(response.status).toBe(400)
  })

  it('rejects with 401 for invalid token', async () => {
    const response = await SELF.fetch('https://test/v1/reports/submit', {
      method: 'POST',
      body: JSON.stringify({ token: 'invalid.signature', uuid_hash: HEX64('f'), url: 'https://example.com/x' }),
      headers: { 'Content-Type': 'application/json' },
    })
    expect(response.status).toBe(401)
  })

  it('rejects with 401 for wrong scope token', async () => {
    const uuid = HEX64('g')
    const token = await makeToken(uuid, 'history')
    const response = await SELF.fetch('https://test/v1/reports/submit', {
      method: 'POST',
      body: JSON.stringify({ token, uuid_hash: uuid, url: 'https://example.com/x' }),
      headers: { 'Content-Type': 'application/json' },
    })
    expect(response.status).toBe(401)
  })

  it('★ IDOR防止: rejects 401 if token uuid_hash ≠ body uuid_hash', async () => {
    const tokenForA = await makeToken(HEX64('a'), 'submit')
    const response = await SELF.fetch('https://test/v1/reports/submit', {
      method: 'POST',
      body: JSON.stringify({ token: tokenForA, uuid_hash: HEX64('b'), url: 'https://example.com/x' }),
      headers: { 'Content-Type': 'application/json' },
    })
    expect(response.status).toBe(401)
    const body = await response.json() as any
    expect(body.message).toContain('uuid_hash mismatch')
  })

  it('rejects with 429 after 5 reports/day per uuid', async () => {
    const uuid = HEX64('h')
    const token = await makeToken(uuid, 'submit')
    const now = Math.floor(Date.now() / 1000)
    for (let i = 0; i < 5; i++) {
      await env.DB.prepare(
        'INSERT INTO reports (id, uuid_hash, ip_hash, domain, url, url_path_hash, status, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)'
      ).bind(`r${i}`, uuid, 'ip', 'example.com', `https://example.com/${i}`, `hash${i}`, 'pending', now).run()
    }
    const response = await SELF.fetch('https://test/v1/reports/submit', {
      method: 'POST',
      body: JSON.stringify({ token, uuid_hash: uuid, url: 'https://example.com/6' }),
      headers: { 'Content-Type': 'application/json' },
    })
    expect(response.status).toBe(429)
    const body = await response.json() as any
    expect(body.error).toBe('rate_limit_exceeded')
  })

  it('rejects with 403 if banned', async () => {
    const uuid = HEX64('i')
    const token = await makeToken(uuid, 'submit')
    const now = Math.floor(Date.now() / 1000)
    await env.DB.prepare(`
      INSERT INTO bans (identifier_hash, identifier_type, reason, abuse_count, ban_level, expires_at, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?)
    `).bind(uuid, 'uuid', 'rate_limit_repeat', 5, 2, now + 7 * 86400, now).run()

    const response = await SELF.fetch('https://test/v1/reports/submit', {
      method: 'POST',
      body: JSON.stringify({ token, uuid_hash: uuid, url: 'https://example.com/x' }),
      headers: { 'Content-Type': 'application/json' },
    })
    expect(response.status).toBe(403)
  })

  // 🆕 abuse reason を abuse_log に書く verify (ban-engine の入力。
  // ただし critical_domain は記録のみで ban 集計対象外 = BAN_ELIGIBLE_REASONS 参照)
  async function abuseRow(uuid: string) {
    return await env.DB
      .prepare(`SELECT identifier_type, reason FROM abuse_log WHERE identifier_hash = ? ORDER BY id DESC LIMIT 1`)
      .bind(uuid)
      .first<{ identifier_type: string; reason: string }>()
  }

  it('logs invalid_url to abuse_log when URL validation fails', async () => {
    const uuid = HEX64('j')
    const token = await makeToken(uuid, 'submit')
    const res = await SELF.fetch('https://test/v1/reports/submit', {
      method: 'POST',
      body: JSON.stringify({ token, uuid_hash: uuid, url: 'http://example.com/insecure' }),
      headers: { 'Content-Type': 'application/json' },
    })
    expect(res.status).toBe(400)
    const row = await abuseRow(uuid)
    expect(row?.reason).toBe('invalid_url')
    expect(row?.identifier_type).toBe('uuid')
  })

  it('logs critical_domain to abuse_log when reporting a protected host', async () => {
    const uuid = HEX64('k')
    const token = await makeToken(uuid, 'submit')
    const res = await SELF.fetch('https://test/v1/reports/submit', {
      method: 'POST',
      body: JSON.stringify({ token, uuid_hash: uuid, url: 'https://apple.com/' }),
      headers: { 'Content-Type': 'application/json' },
    })
    expect(res.status).toBe(400)
    const row = await abuseRow(uuid)
    expect(row?.reason).toBe('critical_domain')
    expect(row?.identifier_type).toBe('uuid')
  })

  it('logs spam_memo to abuse_log when memo validation fails', async () => {
    const uuid = HEX64('l')
    const token = await makeToken(uuid, 'submit')
    // memo に URL を埋め込むと validateMemo 失格
    const res = await SELF.fetch('https://test/v1/reports/submit', {
      method: 'POST',
      body: JSON.stringify({
        token,
        uuid_hash: uuid,
        url: 'https://example.com/article',
        memo: 'see also https://spam.example.com/ad',
      }),
      headers: { 'Content-Type': 'application/json' },
    })
    expect(res.status).toBe(400)
    const row = await abuseRow(uuid)
    expect(row?.reason).toBe('spam_memo')
    expect(row?.identifier_type).toBe('uuid')
  })

  // 🆕 v3.0 build 15: ad_type 受け入れ
  async function reportAdType(uuid: string) {
    return await env.DB
      .prepare(`SELECT ad_type FROM reports WHERE uuid_hash = ? ORDER BY created_at DESC LIMIT 1`)
      .bind(uuid)
      .first<{ ad_type: string | null }>()
  }

  it('persists ad_type when client sends a valid value', async () => {
    const uuid = HEX64('n')
    const token = await makeToken(uuid, 'submit')
    const res = await SELF.fetch('https://test/v1/reports/submit', {
      method: 'POST',
      body: JSON.stringify({
        token, uuid_hash: uuid,
        url: 'https://example.com/article',
        memo: 'overlay ad',
        ad_type: 'interstitial',
      }),
      headers: { 'Content-Type': 'application/json' },
    })
    expect(res.status).toBe(200)
    const row = await reportAdType(uuid)
    expect(row?.ad_type).toBe('interstitial')
  })

  it('stores ad_type as null when client omits it (legacy build 14 compatibility)', async () => {
    const uuid = HEX64('o')
    const token = await makeToken(uuid, 'submit')
    const res = await SELF.fetch('https://test/v1/reports/submit', {
      method: 'POST',
      body: JSON.stringify({ token, uuid_hash: uuid, url: 'https://example.com/legacy' }),
      headers: { 'Content-Type': 'application/json' },
    })
    expect(res.status).toBe(200)
    const row = await reportAdType(uuid)
    expect(row?.ad_type).toBeNull()
  })

  it('rejects with 400 when ad_type is not in the documented set', async () => {
    const uuid = HEX64('p')
    const token = await makeToken(uuid, 'submit')
    const res = await SELF.fetch('https://test/v1/reports/submit', {
      method: 'POST',
      body: JSON.stringify({
        token, uuid_hash: uuid,
        url: 'https://example.com/x',
        ad_type: 'something-unexpected',
      }),
      headers: { 'Content-Type': 'application/json' },
    })
    expect(res.status).toBe(400)
  })

  it('logs rate_limit (uuid) to abuse_log when daily quota is hit', async () => {
    const uuid = HEX64('m')
    const token = await makeToken(uuid, 'submit')
    const now = Math.floor(Date.now() / 1000)
    for (let i = 0; i < 5; i++) {
      await env.DB.prepare(
        'INSERT INTO reports (id, uuid_hash, ip_hash, domain, url, url_path_hash, status, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)'
      ).bind(`rlm${i}`, uuid, 'ip', 'example.com', `https://example.com/m${i}`, `mhash${i}`, 'pending', now).run()
    }
    const res = await SELF.fetch('https://test/v1/reports/submit', {
      method: 'POST',
      body: JSON.stringify({ token, uuid_hash: uuid, url: 'https://example.com/m6' }),
      headers: { 'Content-Type': 'application/json' },
    })
    expect(res.status).toBe(429)
    const row = await abuseRow(uuid)
    expect(row?.reason).toBe('rate_limit')
    expect(row?.identifier_type).toBe('uuid')
  })
})

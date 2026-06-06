import { describe, it, expect, beforeEach } from 'vitest'
import { SELF, env } from 'cloudflare:test'
import { signToken } from '../../src/lib/hmac'

const HEX64 = (c: string) => c.repeat(64)

async function historyToken(): Promise<string> {
  return signToken(
    { subject: 'anonymous', expires: Date.now() + 60000, scope: 'history' },
    env.HMAC_KEY
  )
}

describe('POST /v1/reports/history', () => {
  beforeEach(async () => {
    await env.DB.prepare('DELETE FROM reports').run()
    await env.DB.prepare('DELETE FROM abuse_log').run()
  })

  it('returns empty items when user has no reports', async () => {
    const token = await historyToken()
    const response = await SELF.fetch('https://test/v1/reports/history', {
      method: 'POST',
      body: JSON.stringify({ token, uuid_hash: HEX64('a') }),
      headers: { 'Content-Type': 'application/json' },
    })
    expect(response.status).toBe(200)
    const body = await response.json() as any
    expect(body.items).toEqual([])
    expect(body.fetched_at).toBeGreaterThan(0)
  })

  it('returns user reports sorted DESC by created_at', async () => {
    const uuidHash = HEX64('b')
    const now = Math.floor(Date.now() / 1000)
    await env.DB.prepare(
      'INSERT INTO reports (id, uuid_hash, ip_hash, domain, url, url_path_hash, memo, status, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)'
    ).bind('old', uuidHash, 'ip', 'example.com', 'https://example.com/1', 'h1', 'first', 'pending', now - 100).run()
    await env.DB.prepare(
      'INSERT INTO reports (id, uuid_hash, ip_hash, domain, url, url_path_hash, memo, status, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)'
    ).bind('new', uuidHash, 'ip', 'example.com', 'https://example.com/2', 'h2', 'second', 'pending', now).run()

    const token = await historyToken()
    const response = await SELF.fetch('https://test/v1/reports/history', {
      method: 'POST',
      body: JSON.stringify({ token, uuid_hash: uuidHash }),
      headers: { 'Content-Type': 'application/json' },
    })
    const body = await response.json() as any
    expect(body.items).toHaveLength(2)
    expect(body.items[0].id).toBe('new')
    expect(body.items[1].id).toBe('old')
    expect(body.items[0].memo_redacted).toBe(false)
  })

  it('sets memo_redacted=true when abuse_log has pii_redacted entry for same URL', async () => {
    const uuidHash = HEX64('c')
    const now = Math.floor(Date.now() / 1000)
    const url = 'https://example.com/article'
    await env.DB.prepare(
      'INSERT INTO reports (id, uuid_hash, ip_hash, domain, url, url_path_hash, memo, status, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)'
    ).bind('r1', uuidHash, 'ip', 'example.com', url, 'h', '***-****-****', 'pending', now).run()
    await env.DB.prepare(
      'INSERT INTO abuse_log (identifier_hash, identifier_type, reason, url, created_at) VALUES (?, ?, ?, ?, ?)'
    ).bind(uuidHash, 'uuid', 'pii_redacted', url, now).run()

    const token = await historyToken()
    const response = await SELF.fetch('https://test/v1/reports/history', {
      method: 'POST',
      body: JSON.stringify({ token, uuid_hash: uuidHash }),
      headers: { 'Content-Type': 'application/json' },
    })
    const body = await response.json() as any
    expect(body.items[0].memo_redacted).toBe(true)
  })

  it('rejects 401 for wrong scope token', async () => {
    const token = await signToken(
      { subject: 'anonymous', expires: Date.now() + 60000, scope: 'submit' },
      env.HMAC_KEY
    )
    const response = await SELF.fetch('https://test/v1/reports/history', {
      method: 'POST',
      body: JSON.stringify({ token, uuid_hash: HEX64('d') }),
      headers: { 'Content-Type': 'application/json' },
    })
    expect(response.status).toBe(401)
  })

  it('limits to 50 items', async () => {
    const uuidHash = HEX64('e')
    const now = Math.floor(Date.now() / 1000)
    for (let i = 0; i < 60; i++) {
      await env.DB.prepare(
        'INSERT INTO reports (id, uuid_hash, ip_hash, domain, url, url_path_hash, status, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)'
      ).bind(`r${i}`, uuidHash, 'ip', 'example.com', `https://example.com/${i}`, `h${i}`, 'pending', now - i).run()
    }
    const token = await historyToken()
    const response = await SELF.fetch('https://test/v1/reports/history', {
      method: 'POST',
      body: JSON.stringify({ token, uuid_hash: uuidHash }),
      headers: { 'Content-Type': 'application/json' },
    })
    const body = await response.json() as any
    expect(body.items).toHaveLength(50)
  })
})

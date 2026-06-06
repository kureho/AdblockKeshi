import { describe, it, expect, beforeEach } from 'vitest'
import { SELF, env } from 'cloudflare:test'
import { signToken } from '../../src/lib/hmac'

const HEX64 = (c: string) => c.repeat(64)

async function deleteToken(): Promise<string> {
  return signToken(
    { subject: 'anonymous', expires: Date.now() + 60000, scope: 'delete' },
    env.HMAC_KEY
  )
}

describe('POST /v1/reports/delete', () => {
  beforeEach(async () => {
    await env.DB.prepare('DELETE FROM deletion_requests').run()
  })

  it('returns 202 and inserts into deletion_requests', async () => {
    const token = await deleteToken()
    const response = await SELF.fetch('https://test/v1/reports/delete', {
      method: 'POST',
      body: JSON.stringify({ token, uuid_hash: HEX64('a') }),
      headers: { 'Content-Type': 'application/json' },
    })
    expect(response.status).toBe(202)
    const body = await response.json() as any
    expect(body.status).toBe('pending')
    expect(body.sla_seconds).toBe(3600)

    const row = await env.DB.prepare(
      'SELECT * FROM deletion_requests WHERE uuid_hash = ?'
    ).bind(HEX64('a')).first<any>()
    expect(row.status).toBe('pending')
    expect(row.url_path_hash).toBe(null)
  })

  it('accepts optional url_path_hash for targeted deletion', async () => {
    const token = await deleteToken()
    const urlHash = 'abc123hash'
    const response = await SELF.fetch('https://test/v1/reports/delete', {
      method: 'POST',
      body: JSON.stringify({ token, uuid_hash: HEX64('b'), url_path_hash: urlHash }),
      headers: { 'Content-Type': 'application/json' },
    })
    expect(response.status).toBe(202)
    const row = await env.DB.prepare(
      'SELECT url_path_hash FROM deletion_requests WHERE uuid_hash = ?'
    ).bind(HEX64('b')).first<any>()
    expect(row.url_path_hash).toBe(urlHash)
  })

  it('rejects 401 for wrong scope token', async () => {
    const token = await signToken(
      { subject: 'anonymous', expires: Date.now() + 60000, scope: 'submit' },
      env.HMAC_KEY
    )
    const response = await SELF.fetch('https://test/v1/reports/delete', {
      method: 'POST',
      body: JSON.stringify({ token, uuid_hash: HEX64('c') }),
      headers: { 'Content-Type': 'application/json' },
    })
    expect(response.status).toBe(401)
  })
})

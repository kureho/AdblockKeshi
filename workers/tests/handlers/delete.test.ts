import { describe, it, expect, beforeEach } from 'vitest'
import { SELF, env } from 'cloudflare:test'
import { signToken } from '../../src/lib/hmac'

const HEX64 = (c: string) => c.repeat(64)

async function deleteToken(uuidHash: string): Promise<string> {
  return signToken(
    { subject: uuidHash, expires: Date.now() + 60000, scope: 'delete' },
    env.HMAC_KEY
  )
}

describe('POST /v1/reports/delete', () => {
  beforeEach(async () => {
    await env.DB.prepare('DELETE FROM deletion_requests').run()
  })

  it('returns 202 and inserts into deletion_requests', async () => {
    const uuid = HEX64('a')
    const token = await deleteToken(uuid)
    const response = await SELF.fetch('https://test/v1/reports/delete', {
      method: 'POST',
      body: JSON.stringify({ token, uuid_hash: uuid }),
      headers: { 'Content-Type': 'application/json' },
    })
    expect(response.status).toBe(202)
    const body = await response.json() as any
    expect(body.status).toBe('pending')
    expect(body.sla_seconds).toBe(3600)

    const row = await env.DB.prepare(
      'SELECT * FROM deletion_requests WHERE uuid_hash = ?'
    ).bind(uuid).first<any>()
    expect(row.status).toBe('pending')
    expect(row.url_path_hash).toBe(null)
  })

  it('accepts optional url_path_hash for targeted deletion', async () => {
    const uuid = HEX64('b')
    const urlHash = 'abc123hash'
    const token = await deleteToken(uuid)
    const response = await SELF.fetch('https://test/v1/reports/delete', {
      method: 'POST',
      body: JSON.stringify({ token, uuid_hash: uuid, url_path_hash: urlHash }),
      headers: { 'Content-Type': 'application/json' },
    })
    expect(response.status).toBe(202)
    const row = await env.DB.prepare(
      'SELECT url_path_hash FROM deletion_requests WHERE uuid_hash = ?'
    ).bind(uuid).first<any>()
    expect(row.url_path_hash).toBe(urlHash)
  })

  it('rejects 401 for wrong scope token', async () => {
    const uuid = HEX64('c')
    const token = await signToken(
      { subject: uuid, expires: Date.now() + 60000, scope: 'submit' },
      env.HMAC_KEY
    )
    const response = await SELF.fetch('https://test/v1/reports/delete', {
      method: 'POST',
      body: JSON.stringify({ token, uuid_hash: uuid }),
      headers: { 'Content-Type': 'application/json' },
    })
    expect(response.status).toBe(401)
  })

  it('★ IDOR防止: rejects 401 if token uuid_hash ≠ body uuid_hash', async () => {
    const tokenForA = await deleteToken(HEX64('a'))
    const response = await SELF.fetch('https://test/v1/reports/delete', {
      method: 'POST',
      body: JSON.stringify({ token: tokenForA, uuid_hash: HEX64('b') }),
      headers: { 'Content-Type': 'application/json' },
    })
    expect(response.status).toBe(401)
  })
})

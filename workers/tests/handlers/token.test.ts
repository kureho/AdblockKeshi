import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { SELF, env, fetchMock } from 'cloudflare:test'

const TEST_HMAC_KEY = 'test-hmac-key-do-not-use-in-prod'
const TEST_SERVER_SALT = 'test-server-salt'
const HEX64 = (c: string) => c.repeat(64)
const VALID_UUID_HASH = HEX64('a')

describe('POST /v1/reports/token', () => {
  beforeEach(() => {
    fetchMock.activate()
    fetchMock.disableNetConnect()
  })
  afterEach(() => {
    fetchMock.assertNoPendingInterceptors()
  })

  it('returns 200 with token + expires_at + server_salt for valid Turnstile + uuid_hash', async () => {
    fetchMock.get('https://challenges.cloudflare.com')
      .intercept({ path: '/turnstile/v0/siteverify', method: 'POST' })
      .reply(200, { success: true })

    const response = await SELF.fetch('https://test/v1/reports/token', {
      method: 'POST',
      body: JSON.stringify({ turnstile_response: 'dummy', scope: 'submit', uuid_hash: VALID_UUID_HASH }),
      headers: { 'Content-Type': 'application/json' },
    })
    expect(response.status).toBe(200)
    const body = await response.json() as { token: string; expires_at: number; server_salt: string }
    expect(body.token).toMatch(/^.+\..+$/)
    expect(body.expires_at).toBeGreaterThan(Math.floor(Date.now() / 1000))
    expect(body.server_salt).toBe(TEST_SERVER_SALT)
  })

  it('returns 400 for missing turnstile_response', async () => {
    const response = await SELF.fetch('https://test/v1/reports/token', {
      method: 'POST',
      body: JSON.stringify({ scope: 'submit', uuid_hash: VALID_UUID_HASH }),
      headers: { 'Content-Type': 'application/json' },
    })
    expect(response.status).toBe(400)
  })

  it('returns 400 for missing uuid_hash', async () => {
    const response = await SELF.fetch('https://test/v1/reports/token', {
      method: 'POST',
      body: JSON.stringify({ turnstile_response: 'x', scope: 'submit' }),
      headers: { 'Content-Type': 'application/json' },
    })
    expect(response.status).toBe(400)
    const body = await response.json() as { error: string; message: string }
    expect(body.message).toContain('uuid_hash')
  })

  it('returns 400 for invalid uuid_hash length', async () => {
    const response = await SELF.fetch('https://test/v1/reports/token', {
      method: 'POST',
      body: JSON.stringify({ turnstile_response: 'x', scope: 'submit', uuid_hash: 'too-short' }),
      headers: { 'Content-Type': 'application/json' },
    })
    expect(response.status).toBe(400)
  })

  it('returns 400 for invalid scope', async () => {
    const response = await SELF.fetch('https://test/v1/reports/token', {
      method: 'POST',
      body: JSON.stringify({ turnstile_response: 'x', scope: 'bad', uuid_hash: VALID_UUID_HASH }),
      headers: { 'Content-Type': 'application/json' },
    })
    expect(response.status).toBe(400)
  })

  it('returns 400 with turnstile_failed when Turnstile rejects', async () => {
    fetchMock.get('https://challenges.cloudflare.com')
      .intercept({ path: '/turnstile/v0/siteverify', method: 'POST' })
      .reply(200, { success: false, 'error-codes': ['invalid-input-response'] })

    const response = await SELF.fetch('https://test/v1/reports/token', {
      method: 'POST',
      body: JSON.stringify({ turnstile_response: 'bad', scope: 'submit', uuid_hash: VALID_UUID_HASH }),
      headers: { 'Content-Type': 'application/json' },
    })
    expect(response.status).toBe(400)
    const body = await response.json() as { error: string }
    expect(body.error).toBe('turnstile_failed')
  })

  it('returns 405 for GET', async () => {
    const response = await SELF.fetch('https://test/v1/reports/token', { method: 'GET' })
    expect(response.status).toBe(405)
  })

  it('issued token binds subject to provided uuid_hash', async () => {
    fetchMock.get('https://challenges.cloudflare.com')
      .intercept({ path: '/turnstile/v0/siteverify', method: 'POST' })
      .reply(200, { success: true })

    const response = await SELF.fetch('https://test/v1/reports/token', {
      method: 'POST',
      body: JSON.stringify({ turnstile_response: 'x', scope: 'history', uuid_hash: VALID_UUID_HASH }),
      headers: { 'Content-Type': 'application/json' },
    })
    const body = await response.json() as { token: string }
    const { verifyToken } = await import('../../src/lib/hmac')
    const payload = await verifyToken(body.token, TEST_HMAC_KEY)
    expect(payload.scope).toBe('history')
    expect(payload.subject).toBe(VALID_UUID_HASH)  // ★ token bound to device hash
  })
})

import { describe, it, expect } from 'vitest'
import { signToken, verifyToken } from '../../src/lib/hmac'

const HMAC_KEY = 'test-key-do-not-use-in-prod'

describe('HMAC ephemeral token', () => {
  it('signs and verifies a token with matching payload', async () => {
    const payload = { subject: 'abc123', expires: Date.now() + 60000, scope: 'submit' as const }
    const token = await signToken(payload, HMAC_KEY)
    const verified = await verifyToken(token, HMAC_KEY)
    expect(verified).toEqual(payload)
  })

  it('produces token in data.signature format', async () => {
    const payload = { subject: 'abc', expires: Date.now() + 60000, scope: 'history' as const }
    const token = await signToken(payload, HMAC_KEY)
    expect(token).toMatch(/^.+\..+$/)
  })

  it('rejects expired token', async () => {
    const payload = { subject: 'abc123', expires: Date.now() - 1000, scope: 'submit' as const }
    const token = await signToken(payload, HMAC_KEY)
    await expect(verifyToken(token, HMAC_KEY)).rejects.toThrow('Token expired')
  })

  it('rejects tampered token', async () => {
    const payload = { subject: 'abc123', expires: Date.now() + 60000, scope: 'submit' as const }
    const token = await signToken(payload, HMAC_KEY)
    const tampered = token.slice(0, -4) + 'XXXX'
    await expect(verifyToken(tampered, HMAC_KEY)).rejects.toThrow('Invalid signature')
  })

  it('rejects token signed with different key', async () => {
    const payload = { subject: 'abc123', expires: Date.now() + 60000, scope: 'submit' as const }
    const token = await signToken(payload, HMAC_KEY)
    await expect(verifyToken(token, 'different-key')).rejects.toThrow('Invalid signature')
  })

  it('rejects malformed token (no dot separator)', async () => {
    await expect(verifyToken('no-dot-here', HMAC_KEY)).rejects.toThrow('Invalid token format')
  })

  it('accepts all three valid scopes', async () => {
    const scopes = ['submit', 'history', 'delete'] as const
    for (const scope of scopes) {
      const payload = { subject: 'x', expires: Date.now() + 60000, scope }
      const token = await signToken(payload, HMAC_KEY)
      const verified = await verifyToken(token, HMAC_KEY)
      expect(verified.scope).toBe(scope)
    }
  })
})

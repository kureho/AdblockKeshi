import { describe, it, expect, vi, beforeEach } from 'vitest'
import { verifyTurnstile, TurnstileError } from '../../src/lib/turnstile'

describe('verifyTurnstile', () => {
  beforeEach(() => {
    vi.restoreAllMocks()
  })

  it('returns true for always-success test secret', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(
      new Response(JSON.stringify({ success: true }), { status: 200 })
    )
    const result = await verifyTurnstile({
      secret: '1x0000000000000000000000000000000AA',
      response: 'dummy-token',
      remoteip: '1.2.3.4',
    })
    expect(result).toBe(true)
  })

  it('throws TurnstileError for invalid-input-response', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(
      new Response(JSON.stringify({
        success: false,
        'error-codes': ['invalid-input-response'],
      }), { status: 200 })
    )
    await expect(verifyTurnstile({
      secret: 's',
      response: 'bad',
    })).rejects.toThrow(TurnstileError)
  })

  it('includes remoteip in request body when provided', async () => {
    const fetchSpy = vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(
      new Response(JSON.stringify({ success: true }), { status: 200 })
    )
    await verifyTurnstile({
      secret: '1x0000000000000000000000000000000AA',
      response: 'dummy',
      remoteip: '1.2.3.4',
    })
    expect(fetchSpy).toHaveBeenCalled()
    const callArgs = fetchSpy.mock.calls[0]
    const body = callArgs[1]?.body as string
    expect(body).toContain('remoteip=1.2.3.4')
  })

  it('omits remoteip when not provided', async () => {
    const fetchSpy = vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(
      new Response(JSON.stringify({ success: true }), { status: 200 })
    )
    await verifyTurnstile({ secret: 's', response: 'r' })
    const body = fetchSpy.mock.calls[0][1]?.body as string
    expect(body).not.toContain('remoteip')
  })

  it('throws plain Error for non-200 Cloudflare response', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(
      new Response('Server Error', { status: 500 })
    )
    await expect(verifyTurnstile({
      secret: 's',
      response: 'x',
    })).rejects.toThrow('Turnstile siteverify HTTP 500')
  })
})

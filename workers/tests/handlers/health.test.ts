import { describe, it, expect } from 'vitest'
import { SELF } from 'cloudflare:test'

describe('GET /v1/health', () => {
  it('returns 200 with { status: "ok" }', async () => {
    const response = await SELF.fetch('https://test.example/v1/health')
    expect(response.status).toBe(200)
    const json = await response.json()
    expect(json).toEqual({ status: 'ok' })
  })

  it('rejects non-GET methods with 405', async () => {
    const response = await SELF.fetch('https://test.example/v1/health', { method: 'POST' })
    expect(response.status).toBe(405)
  })

  it('returns 404 for unknown path', async () => {
    const response = await SELF.fetch('https://test.example/v1/unknown')
    expect(response.status).toBe(404)
  })
})

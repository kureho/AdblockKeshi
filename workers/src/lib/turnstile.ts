/**
 * Cloudflare Turnstile server-side verification.
 *
 * Test secrets (Cloudflare 公式):
 * - `1x0000000000000000000000000000000AA` → always success
 * - `2x0000000000000000000000000000000AA` → always failure
 *
 * https://developers.cloudflare.com/turnstile/troubleshooting/testing/
 */

export class TurnstileError extends Error {
  constructor(public readonly errorCodes: string[]) {
    super(`Turnstile verification failed: ${errorCodes.join(', ')}`)
    this.name = 'TurnstileError'
  }
}

interface VerifyArgs {
  secret: string
  response: string
  remoteip?: string
}

interface TurnstileResponseBody {
  success: boolean
  'error-codes'?: string[]
  challenge_ts?: string
  hostname?: string
  action?: string
}

const SITEVERIFY_URL = 'https://challenges.cloudflare.com/turnstile/v0/siteverify'

export async function verifyTurnstile(args: VerifyArgs): Promise<boolean> {
  const params = new URLSearchParams()
  params.set('secret', args.secret)
  params.set('response', args.response)
  if (args.remoteip) params.set('remoteip', args.remoteip)

  const response = await fetch(SITEVERIFY_URL, {
    method: 'POST',
    body: params.toString(),
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
  })

  if (!response.ok) {
    throw new Error(`Turnstile siteverify HTTP ${response.status}`)
  }

  const body = (await response.json()) as TurnstileResponseBody
  if (!body.success) {
    throw new TurnstileError(body['error-codes'] ?? ['unknown'])
  }
  return true
}

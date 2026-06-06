/**
 * HMAC ephemeral token for AdblockKeshi v3.0 report API.
 *
 * Token format: `<base64url(payload_json)>.<base64url(hmac_sha256_signature)>`
 *
 * spec rev4 §3 §4:
 * - 5-minute TTL (enforced via payload.expires)
 * - 3 scopes: submit / history / delete
 * - subject is uuid_hash placeholder; submit handler additionally checks
 *   request-body uuid_hash for IDOR防止
 */

export interface TokenPayload {
  subject: string                       // uuid_hash placeholder (or "anonymous" pre-submit)
  expires: number                       // Unix ms
  scope: 'submit' | 'history' | 'delete'
}

export async function signToken(payload: TokenPayload, key: string): Promise<string> {
  const data = base64UrlEncode(new TextEncoder().encode(JSON.stringify(payload)))
  const sig = await hmacSha256Base64(data, key)
  return `${data}.${sig}`
}

export async function verifyToken(token: string, key: string): Promise<TokenPayload> {
  const parts = token.split('.')
  if (parts.length !== 2 || !parts[0] || !parts[1]) {
    throw new Error('Invalid token format')
  }
  const [data, sig] = parts

  const expectedSig = await hmacSha256Base64(data, key)
  if (!constantTimeEqual(sig, expectedSig)) {
    throw new Error('Invalid signature')
  }

  const payloadJson = new TextDecoder().decode(base64UrlDecode(data))
  const payload = JSON.parse(payloadJson) as TokenPayload

  if (Date.now() > payload.expires) {
    throw new Error('Token expired')
  }

  return payload
}

// MARK: - internal helpers

async function hmacSha256Base64(data: string, key: string): Promise<string> {
  const enc = new TextEncoder()
  const cryptoKey = await crypto.subtle.importKey(
    'raw',
    enc.encode(key),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign']
  )
  const sigBytes = await crypto.subtle.sign('HMAC', cryptoKey, enc.encode(data))
  return base64UrlEncode(new Uint8Array(sigBytes))
}

function base64UrlEncode(bytes: Uint8Array): string {
  let binary = ''
  for (const b of bytes) binary += String.fromCharCode(b)
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

function base64UrlDecode(s: string): Uint8Array {
  const padded = s.replace(/-/g, '+').replace(/_/g, '/') + '='.repeat((4 - (s.length % 4)) % 4)
  const binary = atob(padded)
  const bytes = new Uint8Array(binary.length)
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i)
  return bytes
}

/** Constant-time string compare to prevent timing-based signature leak. */
function constantTimeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false
  let diff = 0
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i)
  }
  return diff === 0
}

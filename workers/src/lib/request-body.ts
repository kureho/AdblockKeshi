/**
 * Shared request-body reader for the POST handlers.
 * - reads at most MAX_BODY_BYTES (rejects larger bodies with 413 without buffering them)
 * - requires the parsed JSON to be a plain object (not null / array / scalar)
 */

export const MAX_BODY_BYTES = 16 * 1024

export type BodyResult =
  | { ok: true; body: Record<string, unknown> }
  | { ok: false; response: Response }

const HEX64_RE = /^[0-9a-f]{64}$/

export function isHex64(value: unknown): value is string {
  return typeof value === 'string' && HEX64_RE.test(value)
}

export function byteLength(text: string): number {
  return new TextEncoder().encode(text).length
}

/** string かつ UTF-8 で maxBytes 以下。 */
export function isStringWithin(value: unknown, maxBytes: number): value is string {
  return typeof value === 'string' && byteLength(value) <= maxBytes
}

export function errorResponse(status: number, error: string, message: string): Response {
  return new Response(JSON.stringify({ error, message }), {
    status, headers: { 'Content-Type': 'application/json' },
  })
}

export async function readJsonObject(request: Request): Promise<BodyResult> {
  const declared = Number(request.headers.get('Content-Length'))
  if (Number.isFinite(declared) && declared > MAX_BODY_BYTES) {
    return { ok: false, response: errorResponse(413, 'payload_too_large', 'request body too large') }
  }

  let text = ''
  if (request.body) {
    const reader = request.body.getReader()
    const decoder = new TextDecoder()
    let total = 0
    for (;;) {
      const { done, value } = await reader.read()
      if (done) break
      total += value.byteLength
      if (total > MAX_BODY_BYTES) {
        await reader.cancel().catch(() => {})
        return { ok: false, response: errorResponse(413, 'payload_too_large', 'request body too large') }
      }
      text += decoder.decode(value, { stream: true })
    }
    text += decoder.decode()
  }

  let parsed: unknown
  try {
    parsed = JSON.parse(text)
  } catch {
    return { ok: false, response: errorResponse(400, 'validation_failed', 'invalid JSON') }
  }
  if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
    return { ok: false, response: errorResponse(400, 'validation_failed', 'body must be a JSON object') }
  }
  return { ok: true, body: parsed as Record<string, unknown> }
}

/**
 * URL/memo basic validation for /v1/reports/submit.
 * spec rev4 §2 §3: URL `https://` only, 200 char max, host non-empty.
 */

export interface ValidationResult {
  ok: boolean
  reason?: string
}

const MAX_URL_LENGTH = 200
const MAX_MEMO_LENGTH = 200
const MIN_HOST_LENGTH = 7

export function validateURL(url: string): ValidationResult {
  if (!url || url.trim().length === 0) return { ok: false, reason: 'url_empty' }
  if (url.length > MAX_URL_LENGTH) return { ok: false, reason: 'url_too_long' }
  if (!url.toLowerCase().startsWith('https://')) return { ok: false, reason: 'url_not_https' }
  try {
    const u = new URL(url)
    if (!u.host) return { ok: false, reason: 'url_malformed' }
    if (u.host.length < MIN_HOST_LENGTH) return { ok: false, reason: 'url_domain_too_short' }
    return { ok: true }
  } catch {
    return { ok: false, reason: 'url_malformed' }
  }
}

export function validateMemo(memo: string | undefined | null): ValidationResult {
  if (memo == null || memo === '') return { ok: true }
  if (memo.length > MAX_MEMO_LENGTH) return { ok: false, reason: 'memo_too_long' }
  if (/https?:\/\//.test(memo)) return { ok: false, reason: 'memo_contains_url' }
  return { ok: true }
}

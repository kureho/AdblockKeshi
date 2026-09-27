/**
 * URL/memo basic validation for /v1/reports/submit.
 * spec rev4 §2 §3: URL `https://` only, host non-empty.
 *
 * A-88（2026-09-27）: URL 上限を 200 → 2048 に上げ、メモは見た目の文字数で数える。
 * アプリは貼り付けた文字数・見た目の文字数で検査するが、送る URL は日本語が %XX に
 * 置き換わった形（生 73 字 → 233 字を実測）、メモは UTF-16 で数えると絵文字が 2 倍になり、
 * 正規のアプリからの報告を弾いて abuse_log に積んでいた。
 */

export interface ValidationResult {
  ok: boolean
  reason?: string
}

const MAX_URL_LENGTH = 2048
const MAX_MEMO_LENGTH = 200
const MIN_HOST_LENGTH = 7

// 長さ超過はアプリとサーバの数え方のずれで正規の利用者にも起きるので、不正の記録に数えない。
const LENGTH_REASONS = new Set(['url_too_long', 'memo_too_long'])

export function countsAsAbuse(result: ValidationResult): boolean {
  return !result.ok && !LENGTH_REASONS.has(result.reason ?? '')
}

/** 見た目の文字数（書記素クラスタ数）。アプリ側 Swift の `String.count` と同じ数え方。 */
export function visibleLength(text: string): number {
  if (typeof Intl !== 'undefined' && typeof Intl.Segmenter === 'function') {
    let n = 0
    for (const _ of new Intl.Segmenter().segment(text)) n++
    return n
  }
  return Array.from(text).length
}

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
  if (visibleLength(memo) > MAX_MEMO_LENGTH) return { ok: false, reason: 'memo_too_long' }
  if (/https?:\/\//.test(memo)) return { ok: false, reason: 'memo_contains_url' }
  return { ok: true }
}

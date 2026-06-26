import { describe, it, expect } from 'vitest'
import { redactPII } from '../../src/lib/pii-redact'

describe('redactPII', () => {
  it('returns original if no PII', () => {
    const { redacted, didRedact } = redactPII('動画上のオーバーレイ広告')
    expect(redacted).toBe('動画上のオーバーレイ広告')
    expect(didRedact).toBe(false)
  })

  it('masks Japanese phone with hyphens', () => {
    const { redacted, didRedact } = redactPII('連絡先 03-1234-5678 です')
    expect(redacted).toContain('***-****-****')
    expect(redacted).not.toContain('03-1234-5678')
    expect(didRedact).toBe(true)
  })

  it('masks free-dial', () => {
    const { redacted, didRedact } = redactPII('0120-123-4567 で予約')
    expect(redacted).toContain('***-****-****')
    expect(didRedact).toBe(true)
  })

  it('masks email addresses', () => {
    const { redacted, didRedact } = redactPII('連絡先: user@example.com まで')
    expect(redacted).toContain('***@***.***')
    expect(redacted).not.toContain('user@example.com')
    expect(didRedact).toBe(true)
  })

  it('masks credit card numbers', () => {
    const { redacted, didRedact } = redactPII('カード 4242-4242-4242-4242 の不正利用')
    expect(redacted).toContain('****-****-****-****')
    expect(didRedact).toBe(true)
  })

  it('does NOT mask short digit sequences', () => {
    const { redacted, didRedact } = redactPII('ABCD-1234 のID')
    expect(redacted).toBe('ABCD-1234 のID')
    expect(didRedact).toBe(false)
  })

  it('handles multiple PIIs in one memo', () => {
    const { redacted, didRedact } = redactPII('tel 03-1234-5678 email a@b.com')
    expect(redacted).toContain('***-****-****')
    expect(redacted).toContain('***@***.***')
    expect(didRedact).toBe(true)
  })

  it('preserves URL-like substrings (URL is rejected separately)', () => {
    const { redacted } = redactPII('see https://example.com/path')
    expect(redacted).toContain('https://example.com')
  })

  it('handles empty input', () => {
    const { redacted, didRedact } = redactPII('')
    expect(redacted).toBe('')
    expect(didRedact).toBe(false)
  })
})

// 層Aは 14 日超の broken_site 行に redactPII を毎回再適用するため、
// 冪等性を回帰ロックとして保証する。
describe('redactPII idempotency', () => {
  it('re-applying redactPII does not change already-masked text', () => {
    const input = '電話 0120-123-4567 メール user@example.com カード 1234-5678-9012-3456'
    const once = redactPII(input).redacted
    const twice = redactPII(once).redacted
    expect(twice).toBe(once)
  })

  it('masked output contains no digit/@ that re-matches a pattern', () => {
    const once = redactPII('+81-90-1234-5678').redacted
    expect(redactPII(once).redacted).toBe(once)
  })
})

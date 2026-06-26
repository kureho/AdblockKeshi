import { describe, expect, test } from 'vitest'
import { getDomain } from 'tldts'
import { normalizeURL } from '../../src/lib/url-redact'

describe('normalizeURL', () => {
  test('strips path/query/fragment to eTLD+1', () => {
    expect(normalizeURL('https://sub.example.co.jp/a?b=c#d')).toBe('example.co.jp')
  })
  test('strips subdomain to registrable domain', () => {
    expect(normalizeURL('https://ads.cdn.example.com/x')).toBe('example.com')
  })
  test('discards token/query', () => {
    expect(normalizeURL('https://evil.com/track?token=secret123&u=foo')).toBe('evil.com')
  })
  test('idempotent on already-reduced eTLD+1', () => {
    expect(normalizeURL('example.com')).toBe('example.com')
    expect(normalizeURL('example.co.jp')).toBe('example.co.jp')
    expect(normalizeURL(normalizeURL('https://a.b.example.co.jp/p'))).toBe('example.co.jp')
  })
  test('IP literal → host as-is (no over-collapse)', () => {
    expect(normalizeURL('https://192.168.0.1/ad')).toBe('192.168.0.1')
  })
  test('IDN/punycode reduces to its registrable domain (matches tldts)', () => {
    // tldts の正確な返り値に合わせる（punycode 正規化は tldts に委譲）。
    const idn = 'https://www.例え.jp/x'
    expect(normalizeURL(idn)).toBe(getDomain(idn))
  })
})

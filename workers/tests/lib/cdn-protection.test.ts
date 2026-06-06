import { describe, it, expect } from 'vitest'
import { isProtectedCDN } from '../../src/lib/cdn-protection'

describe('isProtectedCDN', () => {
  it('protects exact CDN domains', () => {
    expect(isProtectedCDN('cloudfront.net')).toBe(true)
    expect(isProtectedCDN('akamaihd.net')).toBe(true)
    expect(isProtectedCDN('jsdelivr.net')).toBe(true)
  })

  it('protects CDN subdomains', () => {
    expect(isProtectedCDN('d1.cloudfront.net')).toBe(true)
    expect(isProtectedCDN('static.googleusercontent.com')).toBe(true)
    expect(isProtectedCDN('cdn.jsdelivr.net')).toBe(true)
  })

  it('does NOT protect random domains', () => {
    expect(isProtectedCDN('example.com')).toBe(false)
    expect(isProtectedCDN('news.example.jp')).toBe(false)
  })

  it('protects gov / education TLDs', () => {
    expect(isProtectedCDN('mhlw.go.jp')).toBe(true)
    expect(isProtectedCDN('home.gov.uk')).toBe(true)
  })

  it('protects Apple CDNs', () => {
    expect(isProtectedCDN('mzstatic.com')).toBe(true)
    expect(isProtectedCDN('cdn.mzstatic.com')).toBe(true)
  })
})

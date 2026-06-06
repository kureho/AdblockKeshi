import { describe, it, expect } from 'vitest'
import { isAcceptableSelector } from '../../src/lib/selector-scope'

describe('isAcceptableSelector', () => {
  it('rejects null/empty selector', () => {
    expect(isAcceptableSelector(null).ok).toBe(false)
    expect(isAcceptableSelector('').ok).toBe(false)
    expect(isAcceptableSelector('   ').ok).toBe(false)
  })

  it('rejects bare body/html/main', () => {
    expect(isAcceptableSelector('body').ok).toBe(false)
    expect(isAcceptableSelector('html').ok).toBe(false)
    expect(isAcceptableSelector('main').ok).toBe(false)
    expect(isAcceptableSelector('article').ok).toBe(false)
  })

  it('rejects bare universal selector *', () => {
    expect(isAcceptableSelector('*').ok).toBe(false)
  })

  it('rejects [class*=...] and [id*=...]', () => {
    expect(isAcceptableSelector('[class*=ad]').ok).toBe(false)
    expect(isAcceptableSelector('[id*=banner]').ok).toBe(false)
  })

  it('rejects top-level layout IDs', () => {
    expect(isAcceptableSelector('#main').ok).toBe(false)
    expect(isAcceptableSelector('#root').ok).toBe(false)
    expect(isAcceptableSelector('#app').ok).toBe(false)
    expect(isAcceptableSelector('#wrapper').ok).toBe(false)
    expect(isAcceptableSelector('#container').ok).toBe(false)
  })

  it('accepts narrow class-based selectors', () => {
    expect(isAcceptableSelector('.video-overlay-ad').ok).toBe(true)
    expect(isAcceptableSelector('.banner-728x90').ok).toBe(true)
    expect(isAcceptableSelector('div.advertisement-block').ok).toBe(true)
  })

  it('accepts specific ID selectors', () => {
    expect(isAcceptableSelector('#ad-banner-123').ok).toBe(true)
    expect(isAcceptableSelector('#header-promo-slot').ok).toBe(true)
  })

  it('accepts attribute equality selectors (not substring)', () => {
    expect(isAcceptableSelector('[data-ad=true]').ok).toBe(true)
    expect(isAcceptableSelector('a[href="https://ad.example.com"]').ok).toBe(true)
  })

  it('accepts descendant combinator with narrow start', () => {
    expect(isAcceptableSelector('.sidebar .ad-slot').ok).toBe(true)
    expect(isAcceptableSelector('#article-body > .promotion').ok).toBe(true)
  })
})

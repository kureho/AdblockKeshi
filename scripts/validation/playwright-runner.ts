// Plan B Task 2.2 (L6) — real Playwright glue.
//
// Loaded dynamically so it stays out of test bundles and out of cold-start
// dependency installs. The CI workflow installs `playwright` with
// `npm install --no-save` before calling run-playwright-validate.ts.

import type { PageValidation } from '../../workers/src/lib/l6-decision'

const AD_NETWORK_HOSTS = [
  'doubleclick.net',
  'googleadservices.com',
  'googlesyndication.com',
  'adservice.google.com',
  'adsystem.com',
  'adnxs.com',
  'taboola.com',
  'outbrain.com',
  'criteo.com',
  'rubiconproject.com',
  'pubmatic.com',
  'openx.net',
  'yieldmo.com',
  'amazon-adsystem.com',
]

const NAVIGATION_TIMEOUT_MS = 15_000

export async function validatePageWithPlaywright(url: string): Promise<PageValidation> {
  const { chromium } = (await import('playwright')) as typeof import('playwright')
  const browser = await chromium.launch({ headless: true })
  try {
    const ctx = await browser.newContext({
      userAgent:
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15',
      viewport: { width: 1280, height: 800 },
    })
    const page = await ctx.newPage()

    let ad_network_hits = 0
    page.on('request', (req) => {
      const reqUrl = req.url()
      if (AD_NETWORK_HOSTS.some((h) => reqUrl.includes(h))) ad_network_hits++
    })

    await page.goto(url, { waitUntil: 'domcontentloaded', timeout: NAVIGATION_TIMEOUT_MS })

    const result = await page.evaluate(() => {
      const adPattern = /\b(ad|ads|banner|sponsor|promo|popup)\b/i
      const matches: Element[] = []
      for (const el of Array.from(document.querySelectorAll('*'))) {
        const cls = (el as HTMLElement).className?.toString?.() ?? ''
        const id = (el as HTMLElement).id ?? ''
        if (adPattern.test(cls) || adPattern.test(id)) matches.push(el)
        if (matches.length >= 200) break
      }
      let detected: string | null = null
      if (matches.length > 0) {
        const first = matches[0] as HTMLElement
        if (first.id) {
          detected = '#' + CSS.escape(first.id)
        } else {
          const cls = first.className.toString().split(/\s+/).filter(Boolean)[0]
          if (cls) detected = '.' + CSS.escape(cls)
        }
      }
      return { ad_class_count: matches.length, detected_selector: detected }
    })

    return {
      ad_class_count: result.ad_class_count,
      ad_network_hits,
      detected_selector: result.detected_selector,
    }
  } finally {
    await browser.close()
  }
}

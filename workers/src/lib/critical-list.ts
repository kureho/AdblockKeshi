/**
 * Critical domain list - never block. Phase 2 has 50 hardcoded entries;
 * Plan B switches to Tranco Top 1M sync.
 * Matches exact host + suffix match (so subdomains are also protected).
 */
export const CRITICAL_DOMAINS = new Set<string>([
  // Apple & Apple services
  'apple.com', 'icloud.com', 'me.com', 'mac.com', 'itunes.com',
  // Google & Google services
  'google.com', 'gmail.com', 'youtube.com', 'googleusercontent.com', 'gstatic.com',
  // Microsoft
  'microsoft.com', 'outlook.com', 'live.com', 'office.com', 'azure.com',
  // Amazon
  'amazon.com', 'amazon.co.jp', 'amazonaws.com',
  // Meta
  'meta.com', 'facebook.com', 'instagram.com', 'whatsapp.com',
  // Twitter/X
  'twitter.com', 'x.com', 't.co',
  // Devops/Code
  'linkedin.com', 'github.com', 'cloudflare.com',
  // Japan e-commerce
  'yahoo.co.jp', 'rakuten.co.jp', 'mercari.com',
  // Japan gov
  'mhlw.go.jp', 'meti.go.jp', 'mof.go.jp', 'jnto.go.jp',
  // Japan media
  'nhk.or.jp', 'mainichi.jp', 'asahi.com', 'nikkei.com',
  // kureho own
  'kureho.app', 'kureho.com',
  // Payment
  'visa.com', 'mastercard.com', 'paypal.com', 'stripe.com',
  // Banks
  'mizuhobank.co.jp', 'smbc.co.jp', 'mufg.jp',
  // Search engines
  'bing.com', 'duckduckgo.com',
])

export function isCriticalDomain(domain: string): boolean {
  if (CRITICAL_DOMAINS.has(domain)) return true
  for (const critical of CRITICAL_DOMAINS) {
    if (domain.endsWith('.' + critical)) return true
  }
  return false
}

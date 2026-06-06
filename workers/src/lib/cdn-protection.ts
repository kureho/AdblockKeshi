/**
 * L5 共通 CDN 保護 (spec rev4 §4).
 * Prevents accidental blocking of shared CDN hosts that serve many legitimate sites.
 */

const PROTECTED_CDNS = new Set<string>([
  // Cloudflare / global CDNs
  'cloudflare.com', 'cdnjs.cloudflare.com', 'cf-ipfs.com',
  // Google APIs / Fonts / Storage / Cache
  'googleapis.com', 'gstatic.com', 'googleusercontent.com', 'googleadservices.com',
  // Akamai
  'akamai.com', 'akamaihd.net', 'akamaized.net',
  // Amazon CloudFront / S3 / AWS
  'cloudfront.net', 'amazonaws.com', 'amazon.com',
  // Fastly
  'fastly.net', 'fastlylb.net',
  // Microsoft Azure CDN
  'azureedge.net', 'msftcdn.net',
  // jsDelivr / unpkg / common JS hosts
  'jsdelivr.net', 'unpkg.com', 'bootstrapcdn.com',
  // Other major CDNs
  'staticfile.org', 'cdnjs.com', 'sinaapp.com',
  // Apple
  'apple.com', 'icloud.com', 'mzstatic.com',
  // Government / education TLDs that shouldn't be blocked
  'go.jp', 'gov.uk', 'gov.gov',
])

export function isProtectedCDN(domain: string): boolean {
  if (PROTECTED_CDNS.has(domain)) return true
  for (const cdn of PROTECTED_CDNS) {
    if (domain.endsWith('.' + cdn)) return true
  }
  return false
}

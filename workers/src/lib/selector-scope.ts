/**
 * L4 selector scope check (spec rev4 §4).
 * Rejects overly-broad CSS selectors that would block entire pages or layout regions.
 */

const FORBIDDEN_BARE_SELECTORS = new Set<string>([
  '*', 'html', 'body', 'head', 'main', 'article', 'section',
  'header', 'footer', 'nav', 'aside', 'div', 'span', 'p',
])

// Class/ID patterns suggesting too-broad scope. e.g. [class*=ad] matches any class
// containing "ad" — even "header", "loaded", "navigation".
const FORBIDDEN_PATTERNS: RegExp[] = [
  /^\*$/,
  /^\[(class|id)\*=/i,      // [class*=...] [id*=...]
  /^#main(\s|$)/i,           // top-level layout id
  /^#root(\s|$)/i,
  /^#app(\s|$)/i,
  /^#wrapper(\s|$)/i,
  /^#container(\s|$)/i,
]

export interface SelectorCheckResult {
  ok: boolean
  reason?: string
}

export function isAcceptableSelector(selector: string | null | undefined): SelectorCheckResult {
  if (!selector || selector.trim().length === 0) {
    // null selector = "block whole URL" — explicitly rejected at L4
    return { ok: false, reason: 'null_selector_url_wide_block' }
  }

  const trimmed = selector.trim()
  const firstToken = trimmed.split(/[\s>+~]/)[0]?.trim() ?? ''

  if (FORBIDDEN_BARE_SELECTORS.has(firstToken.toLowerCase())) {
    return { ok: false, reason: `bare_${firstToken.toLowerCase()}_too_broad` }
  }
  for (const pat of FORBIDDEN_PATTERNS) {
    if (pat.test(trimmed)) {
      return { ok: false, reason: 'pattern_matches_too_broad' }
    }
  }
  return { ok: true }
}

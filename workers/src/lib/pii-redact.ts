/**
 * PII redact for memo (spec rev4 §2 §4).
 *
 * Design: REDACT instead of reject (rev3 transition).
 * Reason: Japanese phone numbers like "0120-XXX-XXXX" are legitimate report
 * context (the ad itself shows a fraudulent contact number). Rejecting them
 * would block正当な report from going through.
 *
 * Detected PII is masked in-place. The report is still saved with the masked
 * memo. abuse_log records `reason='pii_redacted'` as informational (NOT counted
 * toward ban escalation — see lib/rate-limit.ts).
 */

export interface RedactResult {
  redacted: string
  didRedact: boolean
}

interface Pattern {
  regex: RegExp
  mask: string
}

const PATTERNS: Pattern[] = [
  // Japanese phone (with/without hyphens)
  { regex: /0\d{1,4}-?\d{1,4}-?\d{4}/g, mask: '***-****-****' },
  // International phone
  { regex: /\+\d{1,3}[\s-]?\d{2,4}[\s-]?\d{2,4}[\s-]?\d{2,4}/g, mask: '+**-****-****' },
  // Email address
  { regex: /[\w._%+-]+@[\w.-]+\.\w+/g, mask: '***@***.***' },
  // Credit card (16 digits, with/without hyphens). Luhn check omitted (rev3).
  { regex: /\b\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}\b/g, mask: '****-****-****-****' },
]

export function redactPII(input: string): RedactResult {
  let didRedact = false
  let result = input
  for (const { regex, mask } of PATTERNS) {
    // Reset regex.lastIndex (regex has /g flag, state persists across calls)
    regex.lastIndex = 0
    if (regex.test(result)) {
      didRedact = true
      regex.lastIndex = 0
      result = result.replace(regex, mask)
    }
  }
  return { redacted: result, didRedact }
}

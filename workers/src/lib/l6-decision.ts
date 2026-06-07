// Plan B Task 2.2 (L6 Playwright validation): pure scoring + L4 selector-scope check.
// spec rev4 §4.6: detected page must score ≥ threshold AND selector must be
// narrowly scoped to advance to `beta`.

import { isAcceptableSelector } from './selector-scope'

export interface PageValidation {
  ad_class_count: number
  ad_network_hits: number
  detected_selector: string | null
}

export interface L6Candidate {
  domain: string
}

export type L6Status = 'beta' | 'rejected_score_low' | 'rejected_selector_scope'

export interface L6Decision {
  l6_check: 'pass' | 'fail'
  next_status: L6Status
  validation_score: number
  selector: string | null
  rule_text: string
  reason?: string
}

const DEFAULT_THRESHOLD = 0.7

const WEIGHT_AD_CLASS = 0.4
const WEIGHT_AD_NETWORK = 0.4
const WEIGHT_SELECTOR_PRESENT = 0.2

export function computeAdScore(v: PageValidation): number {
  let s = 0
  if (v.ad_class_count > 0) s += WEIGHT_AD_CLASS
  if (v.ad_network_hits > 0) s += WEIGHT_AD_NETWORK
  if (v.detected_selector) s += WEIGHT_SELECTOR_PRESENT
  if (s > 1) s = 1
  if (s < 0) s = 0
  return s
}

function buildRuleText(selector: string, domain: string): string {
  return JSON.stringify([
    {
      action: { type: 'css-display-none', selector },
      trigger: { 'url-filter': '.*', 'if-domain': [domain] },
    },
  ])
}

export function decideL6(
  candidate: L6Candidate,
  validation: PageValidation,
  threshold = DEFAULT_THRESHOLD
): L6Decision {
  const score = computeAdScore(validation)
  if (score < threshold) {
    return {
      l6_check: 'fail',
      next_status: 'rejected_score_low',
      validation_score: score,
      selector: validation.detected_selector,
      rule_text: '',
      reason: `score_${score.toFixed(2)}_below_${threshold}`,
    }
  }
  const scope = isAcceptableSelector(validation.detected_selector)
  if (!scope.ok) {
    return {
      l6_check: 'fail',
      next_status: 'rejected_selector_scope',
      validation_score: score,
      selector: validation.detected_selector,
      rule_text: '',
      reason: scope.reason,
    }
  }
  const selector = validation.detected_selector as string
  return {
    l6_check: 'pass',
    next_status: 'beta',
    validation_score: score,
    selector,
    rule_text: buildRuleText(selector, candidate.domain),
  }
}

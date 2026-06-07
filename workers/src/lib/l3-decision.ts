// Plan B Task 1.3 (L3 Tranco + critical-list): pure decision logic.
// spec rev4 §4.3: Top 1M domains go into kureho_queue for manual review;
// critical-list domains are auto-rejected regardless of report volume.

import { isCriticalDomain } from './critical-list'

export interface L3Candidate {
  id: string
  domain: string
}

export type L3Status = 'validating' | 'kureho_queue' | 'rejected_critical'

export interface L3Decision {
  id: string
  l3_check: 'pass' | 'fail'
  next_status: L3Status
}

/**
 * Suffix-aware lookup against a Set of root domains. 'cdn.example.com'
 * matches 'example.com' in the set, but 'notexample.com' does not.
 */
export function isInTrancoSet(domain: string, trancoSet: Set<string>): boolean {
  if (trancoSet.has(domain)) return true
  const parts = domain.split('.')
  // Try each suffix from index 1 onwards (skip the full domain already tested).
  for (let i = 1; i < parts.length; i++) {
    const suffix = parts.slice(i).join('.')
    if (!suffix.includes('.')) break // single-label TLDs are not useful
    if (trancoSet.has(suffix)) return true
  }
  return false
}

export function decideL3(candidate: L3Candidate, trancoSet: Set<string>): L3Decision {
  if (isCriticalDomain(candidate.domain)) {
    return { id: candidate.id, l3_check: 'fail', next_status: 'rejected_critical' }
  }
  if (isInTrancoSet(candidate.domain, trancoSet)) {
    return { id: candidate.id, l3_check: 'fail', next_status: 'kureho_queue' }
  }
  return { id: candidate.id, l3_check: 'pass', next_status: 'validating' }
}

// Plan B Task 2.1 (L5 CDN protection): pure decision logic.
// spec rev4 §4.5: rejects rule candidates targeting shared CDN hosts that
// would harm many legitimate sites if blocked.

import { isProtectedCDN } from './cdn-protection'

export interface L5Candidate {
  id: string
  domain: string
}

export type L5Status = 'validating' | 'rejected_cdn'

export interface L5Decision {
  id: string
  l5_check: 'pass' | 'fail'
  next_status: L5Status
}

export function decideL5(candidate: L5Candidate): L5Decision {
  if (isProtectedCDN(candidate.domain)) {
    return { id: candidate.id, l5_check: 'fail', next_status: 'rejected_cdn' }
  }
  return { id: candidate.id, l5_check: 'pass', next_status: 'validating' }
}

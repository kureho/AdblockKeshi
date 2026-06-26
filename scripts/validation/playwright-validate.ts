// Plan B Task 2.2 (L6): Playwright validation orchestrator.
//
// Reads rule_candidates with status='validating' (already past L3+L5), runs an
// injectable page-validator against each one, applies decideL6, then writes
// the verdict back to D1. Real Playwright lives in playwright-runner.ts and
// is wired in by run-playwright-validate.ts; tests stub it out.

import { d1Query, type D1Env } from '../lib/d1-rest'
import { decideL6, type PageValidation } from '../../workers/src/lib/l6-decision'
import { normalizeURL } from '../../workers/src/lib/url-redact'

export interface PlaywrightValidateDeps {
  fetch: typeof globalThis.fetch
  validatePage: (url: string) => Promise<PageValidation>
  now: () => number
}

export interface PlaywrightValidateResult {
  promoted: number
  rejected_score: number
  rejected_scope: number
}

interface CandidateRow {
  id: string
  domain: string
  url: string | null
}

export async function runPlaywrightValidate(
  env: D1Env,
  deps: PlaywrightValidateDeps
): Promise<PlaywrightValidateResult> {
  const candidates = (await d1Query(
    env,
    deps.fetch,
    `SELECT id, domain, url FROM rule_candidates WHERE status = 'validating' LIMIT 200`
  )) as CandidateRow[]

  const result: PlaywrightValidateResult = {
    promoted: 0,
    rejected_score: 0,
    rejected_scope: 0,
  }

  for (const c of candidates) {
    if (!c.url) continue
    let validation: PageValidation
    try {
      validation = await deps.validatePage(c.url)
    } catch {
      // Navigation errors are common (404, timeout, JS error). Skip the
      // candidate; it will be re-tried on the next daily-validation run.
      continue
    }
    const decision = decideL6({ domain: c.domain }, validation)
    const betaStartedAt = decision.next_status === 'beta' ? deps.now() : null
    await d1Query(
      env,
      deps.fetch,
      `UPDATE rule_candidates
          SET status = ?,
              l6_check = ?,
              validation_score = ?,
              selector = ?,
              rule_text = ?,
              beta_started_at = COALESCE(?, beta_started_at),
              url = ?
        WHERE id = ?`,
      [
        decision.next_status,
        decision.l6_check,
        decision.validation_score,
        decision.selector,
        decision.rule_text,
        betaStartedAt,
        normalizeURL(c.url), // 層B: 検証後は eTLD+1 に縮約してパス/クエリを破棄
        c.id,
      ]
    )
    if (decision.next_status === 'beta') result.promoted++
    else if (decision.next_status === 'rejected_score_low') result.rejected_score++
    else if (decision.next_status === 'rejected_selector_scope') result.rejected_scope++
  }

  return result
}

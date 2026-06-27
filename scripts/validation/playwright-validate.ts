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
  rejected_unreachable: number
}

interface CandidateRow {
  id: string
  domain: string
  url: string | null
  validation_attempts: number
}

// validatePage の失敗を transient とみなして無限再試行すると、構造的に開けない URL
// （動画 CDN 等）が status='validating' に永久滞留する: 昇格も reject もされず
// LIMIT 200 の検証プールを占有し（層A floor と同類の starvation）、14日後に層A が
// 縮約するまで完全 URL(PII) を保持し続ける。連続失敗がこの上限に達したら terminal
// status='rejected_unreachable' に落としてプールから外す。
const MAX_VALIDATION_ATTEMPTS = 3

export async function runPlaywrightValidate(
  env: D1Env,
  deps: PlaywrightValidateDeps
): Promise<PlaywrightValidateResult> {
  const candidates = (await d1Query(
    env,
    deps.fetch,
    `SELECT id, domain, url, validation_attempts FROM rule_candidates WHERE status = 'validating' LIMIT 200`
  )) as CandidateRow[]

  const result: PlaywrightValidateResult = {
    promoted: 0,
    rejected_score: 0,
    rejected_scope: 0,
    rejected_unreachable: 0,
  }

  for (const c of candidates) {
    let validation: PageValidation | null = null
    if (c.url) {
      try {
        validation = await deps.validatePage(c.url)
      } catch {
        // Navigation errors (404, timeout, JS error, unopenable media) leave
        // validation null and fall through to the bounded-retry handler below.
        validation = null
      }
    }

    if (validation === null) {
      // url 欠落 or validatePage 失敗 = 非 terminal な失敗。再試行を上限で打ち切り、
      // 永久滞留（プール starvation + 完全 URL の無期限保持）を防ぐ。
      const attempts = (c.validation_attempts ?? 0) + 1
      if (attempts >= MAX_VALIDATION_ATTEMPTS) {
        // 諦める: terminal。これ以上再試行しないので url は eTLD+1 に縮約（PII 破棄）。
        // url が無ければ縮約対象が無いので null のまま。l6_check は実行されていないため
        // 触らない（status が理由を表す）。
        // `AND status = 'validating'`: SELECT〜UPDATE 間に別ステップ（cdn/tranco 等）が
        // この行を遷移させていたら no-op にして上書き事故を防ぐ（再実行安全）。
        await d1Query(
          env,
          deps.fetch,
          `UPDATE rule_candidates SET status = 'rejected_unreachable', validation_attempts = ?, url = ? WHERE id = ? AND status = 'validating'`,
          [attempts, c.url ? normalizeURL(c.url) : c.url, c.id]
        )
        result.rejected_unreachable++
      } else {
        // transient: カウンタだけ進め、status='validating' のまま次回再試行に備えて
        // 完全 URL を保持する。status guard で再実行安全性を確保。
        await d1Query(
          env,
          deps.fetch,
          `UPDATE rule_candidates SET validation_attempts = ? WHERE id = ? AND status = 'validating'`,
          [attempts, c.id]
        )
      }
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

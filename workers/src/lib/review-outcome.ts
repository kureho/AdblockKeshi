/**
 * A-88 §3: 報告者へ返す「結果」を丸める純粋関数。
 * 設計: tasks/a88-design-2026-09-27.md §3。
 *
 * 判定結果ファイル（review/results/*.json）に書く生の値（5値）と、
 * API (`POST /v1/reports/status`) が報告者に返す丸めた値（5値）は別物。
 *
 *   raw    (review_outcome 列 / 判定ファイルの outcome):
 *     applied / in_app_ad / site_own_ad / not_reproduced / invalid
 *   rolled (API が返す outcome):
 *     checking / applied / in_app_ad / site_own_ad / declined
 *
 * not_reproduced と invalid はどちらも declined に丸める
 * （報告者には「なぜ見送られたか」の理由の粒度までは返さない）。
 */

export const RAW_REVIEW_OUTCOMES = [
  'applied',
  'in_app_ad',
  'site_own_ad',
  'not_reproduced',
  'invalid',
] as const
export type RawReviewOutcome = (typeof RAW_REVIEW_OUTCOMES)[number]

export function isRawReviewOutcome(value: unknown): value is RawReviewOutcome {
  return typeof value === 'string' && (RAW_REVIEW_OUTCOMES as readonly string[]).includes(value)
}

export const REPORT_STATUS_OUTCOMES = [
  'checking',
  'applied',
  'in_app_ad',
  'site_own_ad',
  'declined',
] as const
export type ReportStatusOutcome = (typeof REPORT_STATUS_OUTCOMES)[number]

export interface ResolveReviewOutcomeInput {
  /** reports.status の生値 */
  status: string
  /** reports.applied_at（未設定は null） */
  appliedAt: number | null
  /** reports.review_outcome（未判定は null） */
  reviewOutcome: string | null
}

const RAW_TO_ROLLED: Record<RawReviewOutcome, ReportStatusOutcome> = {
  applied: 'applied',
  in_app_ad: 'in_app_ad',
  site_own_ad: 'site_own_ad',
  not_reproduced: 'declined',
  invalid: 'declined',
}

/**
 * 丸め方の優先順位（設計 §3）:
 *   1. review_outcome（人手判定の結果）があれば最優先でそれを丸める
 *   2. 無ければ既存の status から:
 *        applied_at がある、または status='stable'  → applied
 *        status が 'rejected_' で始まる              → declined
 *        それ以外（pending 等・判定前）               → checking
 *
 * ★現状 reports.status が実際に 'stable' や 'rejected_*' になることは無い
 *  （それらは rule_candidates 側の値。reports 側の terminal は 'aggregated' のみ、
 *  applied_at も現行コードでは書き込まれない）。この分岐は将来 reports 側の
 *  昇格/却下が直接書き込まれるようになった場合に備えた防御的フォールバックで、
 *  設計 §2/§3 の対応表をそのままコードに固定したもの。
 */
export function resolveReviewOutcome(input: ResolveReviewOutcomeInput): ReportStatusOutcome {
  if (isRawReviewOutcome(input.reviewOutcome)) {
    return RAW_TO_ROLLED[input.reviewOutcome]
  }
  if (input.appliedAt != null || input.status === 'stable') return 'applied'
  if (input.status.startsWith('rejected_')) return 'declined'
  return 'checking'
}

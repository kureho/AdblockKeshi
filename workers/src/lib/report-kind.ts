/**
 * 報告種別（v4.2.0）。iOS の `App/Models/ReportKind.swift` と**完全同期**。
 *
 * - `ad_not_blocked`: 広告が消えない（ブロックを強めたい）→ 従来の集約パイプラインへ
 * - `site_broken`:    サイトが壊れた（ブロックが強すぎた）→ `broken_site` へ隔離
 *
 * 改善の方向が真逆なので、site_broken を集約母集団（pending）に入れてはいけない。
 * 未知の値は seen_in と同じ前方互換方針で NULL（= 広告扱い）に落とす。
 */
export const REPORT_KINDS = ['ad_not_blocked', 'site_broken'] as const

export type ReportKind = typeof REPORT_KINDS[number]

export function isReportKind(value: unknown): value is ReportKind {
  return typeof value === 'string' && (REPORT_KINDS as readonly string[]).includes(value)
}

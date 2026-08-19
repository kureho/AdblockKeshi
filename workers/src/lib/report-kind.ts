/**
 * 報告種別（v4.2.0）。iOS の `App/Models/ReportKind.swift` と**完全同期**。
 *
 * - `ad_not_blocked`: 広告が消えない（ブロックを強めたい）→ 従来の集約パイプラインへ
 * - `site_broken`:    サイトが壊れた（ブロックが強すぎた）→ `broken_site` へ隔離
 *
 * 改善の方向が真逆なので、site_broken を集約母集団（pending）に入れてはいけない。
 *
 * 未送信（旧クライアント）は NULL = 広告扱い。ただし **値は来ているが未知**の場合は広告扱いにしない
 * （2026-08-19 の反証レビューで変更）。知らない種別名を送るクライアントは、このサーバが知らない
 * 改善方向を持っている。それを pending に入れると、将来 site_broken 系の種別が増えたときに
 * 真逆へ誤学習する。方向が判定できないものは集約に入れず observation として保持する。
 */
export const REPORT_KINDS = ['ad_not_blocked', 'site_broken'] as const

export type ReportKind = typeof REPORT_KINDS[number]

export function isReportKind(value: unknown): value is ReportKind {
  return typeof value === 'string' && (REPORT_KINDS as readonly string[]).includes(value)
}

/**
 * 値は来ているが既知の種別ではない（= 改善の方向が判定できない）。
 * 未送信・null は false（旧クライアントは従来どおり広告扱いのまま）。
 */
export function hasUnknownReportKind(value: unknown): boolean {
  return value !== undefined && value !== null && !isReportKind(value)
}

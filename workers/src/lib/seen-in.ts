/**
 * 報告時の「どこで見た広告か」。iOS の `App/Models/SeenIn.swift` と完全同期させる。
 *
 * D-lite の中核: Safari 用 Content Blocker で対処できる報告かどうかを切り分ける。
 * `other_app`（アプリ内広告）は Safari 用フィルタでは原理的に消せないため、
 * 自動改善パイプラインには乗せず、診断データとしてのみ使う。
 *
 * この値の **有無** が新旧クライアントの境界でもある（旧クライアントは送ってこない）。
 */
export const SEEN_IN_VALUES = ['safari', 'other_app'] as const

export type SeenIn = (typeof SEEN_IN_VALUES)[number]

export function isSeenIn(value: unknown): value is SeenIn {
  return typeof value === 'string' && (SEEN_IN_VALUES as readonly string[]).includes(value)
}

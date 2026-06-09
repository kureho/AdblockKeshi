/**
 * v3.0 build 15: ユーザーが報告フォームで選択する広告タイプ。
 * iOS 側 `AdType` enum と完全に同期。新規追加するときは両方で同じ value を
 * 同じ順序で追加する (UI 側のデフォルト並び順を tests に固定するため)。
 */
export const AD_TYPES = [
  'interstitial',
  'popup',
  'autoplay_video',
  'sticky_banner',
  'fake_close',
  'fake_notification',
  'phishing',
  'redirect',
  'preroll',
  'misleading_link',
  'other',
] as const

export type AdType = (typeof AD_TYPES)[number]

const AD_TYPE_SET = new Set<string>(AD_TYPES)

export function isAdType(value: unknown): value is AdType {
  return typeof value === 'string' && AD_TYPE_SET.has(value)
}

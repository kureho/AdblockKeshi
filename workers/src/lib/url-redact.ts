import { getDomain } from 'tldts'

/**
 * 完全 URL（または既に縮約済みの eTLD+1）を registrable domain（eTLD+1）に縮約する。
 * path/query/fragment/token/subdomain を全て破棄する。
 *
 * 冪等: normalizeURL(normalizeURL(x)) === normalizeURL(x)。
 * tldts.getDomain は ICANN public suffix list を用いるため、example.co.jp の
 * ような multi-level TLD も正しく縮約される。getDomain は URL でも hostname でも受ける。
 *
 * fallback: getDomain が registrable domain を抽出できない入力（IP リテラル・
 * 不正ホスト）は host をそのまま返す（過剰縮約より安全側）。null/空は返さない
 * （呼び出し側は NOT NULL カラムに保存するため）。
 */
export function normalizeURL(input: string): string {
  const domain = getDomain(input)
  if (domain) return domain
  try {
    return new URL(input).host || input
  } catch {
    return input
  }
}

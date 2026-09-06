// Tranco Top 1M リストのパーサ。
//
// 2026-09-06 まではこのリストを D1 テーブル tranco_top_1m に週次で全入れ替え
// していたが、1 回の同期で rows_written 40 万行（無料枠 10 万行/日の 4 倍）を
// 消費して毎週日曜に D1 書き込みが停止していた。リストの読み手は
// daily-validation の L3 判定だけで、そこは GitHub Actions ランナー上の
// Node プロセス = CSV をそのままメモリに載せられる。よって D1 を経由しない。

export interface ParseOptions {
  /** 取り込む上位件数。L3 は「大手サイトか」だけを見るので上位 10 万で足りる。 */
  maxRows?: number
}

/** L3 が必要とするのは上位 10 万件（旧 D1 テーブルの中身と同じ範囲）。 */
export const TRANCO_DEFAULT_MAX_ROWS = 100_000

/**
 * `rank,domain` 形式の CSV からドメイン集合を作る。
 * 壊れた行（カンマ無し / rank が数値でない / domain 空）は捨てる。
 */
export function parseTrancoDomains(
  csv: string,
  maxRows: number = TRANCO_DEFAULT_MAX_ROWS
): Set<string> {
  const out = new Set<string>()
  for (const raw of csv.split('\n')) {
    if (out.size >= maxRows) break
    const line = raw.trim()
    if (!line) continue
    const comma = line.indexOf(',')
    if (comma < 0) continue
    const rank = Number.parseInt(line.slice(0, comma).trim(), 10)
    const domain = line.slice(comma + 1).trim()
    if (!Number.isFinite(rank) || !domain) continue
    out.add(domain)
  }
  return out
}

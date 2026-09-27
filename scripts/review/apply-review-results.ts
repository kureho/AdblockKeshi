// A-88 §2: 週1回の人手判定結果（review/results/*.json）を D1 の
// reports.review_outcome / reports.reviewed_at に書き込む。
// 設計: tasks/a88-design-2026-09-27.md §2「報告ごとの結果は GitHub Actions が
// D1 に書き込む（既存のスクリプトと同じ経路・本番 DB を手で触らない）」。
//
// 冪等性: UPDATE ... SET review_outcome = ?, reviewed_at = ? WHERE id = ? は
// 同じファイルを何度流しても同じ値を書くだけなので、結果は変わらない。

import { d1Query, type D1Env } from '../lib/d1-rest'
import { isRawReviewOutcome, type RawReviewOutcome } from '../../workers/src/lib/review-outcome'

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/

export interface ReviewResultItem {
  report_id: string
  outcome: string
  note?: string
}

export interface ReviewResultFile {
  reviewed_at: string
  results: ReviewResultItem[]
}

export interface ParsedReviewFile {
  fileName: string
  reviewedAtSec: number
  items: Array<{ reportId: string; outcome: RawReviewOutcome }>
}

/**
 * review/results/*.json 1ファイル分をパース＋検証する。
 * 未知の outcome・UUID でない report_id が1件でもあれば、そのファイルごと Error を投げる
 * （部分適用しない＝設計 §2 の「入力検証：未知の outcome や UUID でない ID はそのファイルごと失敗させる」）。
 */
export function parseReviewResultFile(fileName: string, raw: string): ParsedReviewFile {
  let data: unknown
  try {
    data = JSON.parse(raw)
  } catch (e) {
    throw new Error(`${fileName}: invalid JSON (${(e as Error).message})`)
  }
  if (typeof data !== 'object' || data === null || Array.isArray(data)) {
    throw new Error(`${fileName}: top-level must be a JSON object`)
  }
  const file = data as Partial<ReviewResultFile>

  if (typeof file.reviewed_at !== 'string' || !DATE_RE.test(file.reviewed_at)) {
    throw new Error(`${fileName}: reviewed_at must be "YYYY-MM-DD"`)
  }
  const reviewedAtMs = Date.parse(`${file.reviewed_at}T00:00:00Z`)
  if (!Number.isFinite(reviewedAtMs)) {
    throw new Error(`${fileName}: reviewed_at is not a valid date`)
  }
  const reviewedAtSec = Math.floor(reviewedAtMs / 1000)

  if (!Array.isArray(file.results) || file.results.length === 0) {
    throw new Error(`${fileName}: results must be a non-empty array`)
  }

  const items = file.results.map((item, i) => {
    if (typeof item !== 'object' || item === null) {
      throw new Error(`${fileName}: results[${i}] must be an object`)
    }
    const reportId = (item as ReviewResultItem).report_id
    if (typeof reportId !== 'string' || !UUID_RE.test(reportId)) {
      throw new Error(`${fileName}: results[${i}].report_id is not a UUID`)
    }
    const outcome = (item as ReviewResultItem).outcome
    if (!isRawReviewOutcome(outcome)) {
      throw new Error(`${fileName}: results[${i}].outcome is unknown: ${JSON.stringify(outcome)}`)
    }
    return { reportId, outcome }
  })

  return { fileName, reviewedAtSec, items }
}

export interface ApplyReviewResultsDeps {
  fetch: typeof globalThis.fetch
  /** true の場合 D1 に書き込まず、流す予定の SQL/params だけを返す（ローカル確認用）。 */
  dryRun?: boolean
}

export interface ApplyFileResult {
  fileName: string
  ok: boolean
  updated: number
  error?: string
  /** dryRun 時のみ。実行される予定だった UPDATE 文。 */
  statements?: Array<{ sql: string; params: [string, number, string] }>
}

const UPDATE_SQL = `UPDATE reports SET review_outcome = ?, reviewed_at = ? WHERE id = ?`

/**
 * 複数の判定結果ファイルを順に適用する。
 * ★失敗の粒度は「ファイル単位」: 1ファイル内に不正な行が1つでもあれば、
 *   そのファイルからは1件も書き込まない。実行時（D1側）のエラーでも同様に、
 *   失敗したファイルの処理を打ち切って他のファイルへ進む。他のファイルの適用は続ける。
 */
export async function applyReviewResultFiles(
  env: D1Env,
  files: Array<{ name: string; raw: string }>,
  deps: ApplyReviewResultsDeps
): Promise<ApplyFileResult[]> {
  const out: ApplyFileResult[] = []

  for (const f of files) {
    let parsed: ParsedReviewFile
    try {
      parsed = parseReviewResultFile(f.name, f.raw)
    } catch (e) {
      out.push({ fileName: f.name, ok: false, updated: 0, error: (e as Error).message })
      continue
    }

    const statements: Array<{ sql: string; params: [string, number, string] }> = parsed.items.map((item) => ({
      sql: UPDATE_SQL,
      params: [item.outcome, parsed.reviewedAtSec, item.reportId],
    }))

    if (deps.dryRun) {
      out.push({ fileName: f.name, ok: true, updated: statements.length, statements })
      continue
    }

    // ★実行時エラー（D1側の一時障害等）もパースエラーと同じくファイル単位で分離する。
    //   ここまでに書けた件数は updated に残しつつ ok=false にし、他のファイルの処理は続ける
    //   （batch-job-safety: 1件・1ファイルの失敗が全体をブロックしない）。再実行は idempotent
    //   なので、途中まで書けたファイルをそのまま再度流しても安全。
    let updated = 0
    try {
      for (const s of statements) {
        await d1Query(env, deps.fetch, s.sql, s.params)
        updated++
      }
      out.push({ fileName: f.name, ok: true, updated })
    } catch (e) {
      out.push({ fileName: f.name, ok: false, updated, error: (e as Error).message })
    }
  }

  return out
}

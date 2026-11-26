// Plan B Task 4.1: hourly deletion processor (1h SLA).
//
// Pulls pending deletion_requests and removes the requesting uuid_hash's data
// from reports / abuse_log / bans. If url_path_hash is set, only that specific
// report is removed; otherwise everything tied to the uuid is wiped.

import { d1Query, type D1Env } from '../lib/d1-rest'

/** claim からこの秒数を過ぎた 'processing' は異常終了とみなして pending に戻す（実行は毎時・SLA 1h）。 */
const STALE_CLAIM_SEC = 30 * 60

export interface DeletionProcessorDeps {
  fetch: typeof globalThis.fetch
  now: () => number
}

export interface DeletionProcessorResult {
  processed: number
}

interface DeletionRequestRow {
  id: string
  uuid_hash: string
  url_path_hash: string | null
}

export async function runDeletionProcessor(
  env: D1Env,
  deps: DeletionProcessorDeps
): Promise<DeletionProcessorResult> {
  const now = deps.now()

  // 途中で落ちた実行が 'processing' のまま残らないよう、一定時間を過ぎた claim は pending に戻す。
  // （削除は冪等なので再処理しても問題ない。processed_at は processing の間は claim 時刻として使う）
  await d1Query(
    env,
    deps.fetch,
    `UPDATE deletion_requests SET status = 'pending', processed_at = NULL
      WHERE status = 'processing' AND processed_at < ?`,
    [now - STALE_CLAIM_SEC]
  )

  // pending を 1 文で claim する。claim 後に届いた依頼は別の pending 行になり、次の実行で処理される
  // （Worker 側は pending だけを対象に重複をまとめるため、処理中の行には合流しない）。
  const pending = (await d1Query(
    env,
    deps.fetch,
    `UPDATE deletion_requests SET status = 'processing', processed_at = ?
      WHERE id IN (SELECT id FROM deletion_requests
                    WHERE status = 'pending'
                    ORDER BY requested_at ASC
                    LIMIT 500)
      RETURNING id, uuid_hash, url_path_hash`,
    [now]
  )) as DeletionRequestRow[]

  if (pending.length === 0) return { processed: 0 }

  let processed = 0
  for (const req of pending) {
    if (req.url_path_hash) {
      await d1Query(
        env,
        deps.fetch,
        `DELETE FROM reports WHERE uuid_hash = ? AND url_path_hash = ?`,
        [req.uuid_hash, req.url_path_hash]
      )
    } else {
      await d1Query(
        env,
        deps.fetch,
        `DELETE FROM reports WHERE uuid_hash = ?`,
        [req.uuid_hash]
      )
      await d1Query(
        env,
        deps.fetch,
        `DELETE FROM abuse_log WHERE identifier_hash = ? AND identifier_type = 'uuid'`,
        [req.uuid_hash]
      )
      await d1Query(
        env,
        deps.fetch,
        `DELETE FROM bans WHERE identifier_hash = ? AND identifier_type = 'uuid'`,
        [req.uuid_hash]
      )
    }
    await d1Query(
      env,
      deps.fetch,
      `UPDATE deletion_requests SET status = ?, processed_at = ? WHERE id = ?`,
      ['completed', now, req.id]
    )
    processed++
  }

  return { processed }
}

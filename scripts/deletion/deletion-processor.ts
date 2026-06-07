// Plan B Task 4.1: hourly deletion processor (1h SLA).
//
// Pulls pending deletion_requests and removes the requesting uuid_hash's data
// from reports / abuse_log / bans. If url_path_hash is set, only that specific
// report is removed; otherwise everything tied to the uuid is wiped.

import { d1Query, type D1Env } from '../lib/d1-rest'

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
  const pending = (await d1Query(
    env,
    deps.fetch,
    `SELECT id, uuid_hash, url_path_hash
       FROM deletion_requests
      WHERE status = 'pending'
      ORDER BY requested_at ASC
      LIMIT 500`
  )) as DeletionRequestRow[]

  if (pending.length === 0) return { processed: 0 }

  let processed = 0
  const now = deps.now()
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
        `DELETE FROM bans WHERE identifier_hash = ?`,
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

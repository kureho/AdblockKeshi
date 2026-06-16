// Hourly aggregation CLI entry. Called by .github/workflows/hourly-aggregation.yml.
//
// Plan B Task 1.2: rule_candidate aggregation (L2 threshold).
// Plan C Chunk 1 Task 1.2: 4-tier auto-ban level escalation (spec rev4 §4).

import { runAggregation } from './aggregate-reports'
import { runBanEngineViaRest } from './ban-engine-runner'
import { envFromProcess } from '../lib/d1-rest'

async function main() {
  const env = envFromProcess()
  const fetch = globalThis.fetch
  const now = () => Math.floor(Date.now() / 1000)

  // 信頼レポーター(kureho 自身の uuid_hash 等)。GitHub Secret TRUSTED_UUID_HASHES に
  // カンマ区切りで設定すると、その報告は L2 の3人閾値をバイパスして昇格候補になる。
  // 未設定なら通常の閾値のまま（後方互換）。有効化には secret 設定 + workflow 反映が必要。
  const trustedUuidHashes = new Set(
    (process.env.TRUSTED_UUID_HASHES ?? '')
      .split(',')
      .map((s) => s.trim())
      .filter((s) => s.length > 0)
  )

  const aggregation = await runAggregation(env, {
    fetch,
    uuidv4: () => crypto.randomUUID(),
    now,
    trustedUuidHashes,
  })
  console.log(JSON.stringify({ stage: 'aggregation', ok: true, ...aggregation }))

  const ban = await runBanEngineViaRest(env, { fetch, now })
  console.log(JSON.stringify({ stage: 'ban-engine', ok: true, ...ban }))
}

main().catch((e) => {
  console.error('[hourly-aggregation] failed:', e?.message ?? e)
  process.exit(1)
})

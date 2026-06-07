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

  const aggregation = await runAggregation(env, {
    fetch,
    uuidv4: () => crypto.randomUUID(),
    now,
  })
  console.log(JSON.stringify({ stage: 'aggregation', ok: true, ...aggregation }))

  const ban = await runBanEngineViaRest(env, { fetch, now })
  console.log(JSON.stringify({ stage: 'ban-engine', ok: true, ...ban }))
}

main().catch((e) => {
  console.error('[hourly-aggregation] failed:', e?.message ?? e)
  process.exit(1)
})

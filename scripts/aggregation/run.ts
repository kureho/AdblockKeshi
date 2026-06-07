// Plan B Task 1.2 CLI entry. Called by .github/workflows/hourly-aggregation.yml.

import { runAggregation } from './aggregate-reports'
import { envFromProcess } from '../lib/d1-rest'

runAggregation(envFromProcess(), {
  fetch: globalThis.fetch,
  uuidv4: () => crypto.randomUUID(),
  now: () => Math.floor(Date.now() / 1000),
})
  .then((r) => {
    console.log(JSON.stringify({ ok: true, ...r }))
  })
  .catch((e) => {
    console.error('[aggregate-reports] failed:', e?.message ?? e)
    process.exit(1)
  })

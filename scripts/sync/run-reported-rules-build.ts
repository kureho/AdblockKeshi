// Plan B Task 4.2 CLI entry. Called by weekly-cdn-sync.yml.
// Usage: tsx run-reported-rules-build.ts <output-path>

import { runReportedRulesBuild } from './reported-rules-build'
import { envFromProcess } from '../lib/d1-rest'

const outputPath = process.argv[2]
if (!outputPath) {
  console.error('Usage: run-reported-rules-build.ts <output-path>')
  process.exit(2)
}

runReportedRulesBuild(envFromProcess(), {
  fetch: globalThis.fetch,
  outputPath,
})
  .then((r) => {
    console.log(JSON.stringify({ ok: true, ...r }))
  })
  .catch((e) => {
    console.error('[reported-rules-build] failed:', e?.message ?? e)
    process.exit(1)
  })

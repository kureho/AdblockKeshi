// Plan B Task 4.2 CLI entry. Called by weekly-cdn-sync.yml.
// Plan C Chunk 5: now also patches version.json's `reported` section so the
// iOS app's moat row stays in sync with the CDN-published metrics.
// Usage: tsx run-reported-rules-build.ts <rules-output> <version-json-path>

import { runReportedRulesBuild } from './reported-rules-build'
import { envFromProcess } from '../lib/d1-rest'

const outputPath = process.argv[2]
const versionJsonPath = process.argv[3]
if (!outputPath || !versionJsonPath) {
  console.error(
    'Usage: run-reported-rules-build.ts <rules-output> <version-json-path>'
  )
  process.exit(2)
}

runReportedRulesBuild(envFromProcess(), {
  fetch: globalThis.fetch,
  outputPath,
  versionJsonPath,
  now: () => Math.floor(Date.now() / 1000),
})
  .then((r) => {
    console.log(JSON.stringify({ ok: true, ...r }))
  })
  .catch((e) => {
    console.error('[reported-rules-build] failed:', e?.message ?? e)
    process.exit(1)
  })

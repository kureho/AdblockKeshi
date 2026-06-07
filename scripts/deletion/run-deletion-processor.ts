// Plan B Task 4.1 CLI entry. Called by hourly-deletion-processor.yml.

import { runDeletionProcessor } from './deletion-processor'
import { envFromProcess } from '../lib/d1-rest'

runDeletionProcessor(envFromProcess(), {
  fetch: globalThis.fetch,
  now: () => Math.floor(Date.now() / 1000),
})
  .then((r) => {
    console.log(JSON.stringify({ ok: true, ...r }))
  })
  .catch((e) => {
    console.error('[deletion-processor] failed:', e?.message ?? e)
    process.exit(1)
  })

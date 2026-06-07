// Plan B Task 2.4 CLI entry. Called by complaint-monitor.yml.

import { runComplaintRollback } from './complaint-rollback'
import { envFromProcess } from '../lib/d1-rest'

runComplaintRollback(envFromProcess(), {
  fetch: globalThis.fetch,
  now: () => Math.floor(Date.now() / 1000),
})
  .then((r) => {
    console.log(JSON.stringify({ ok: true, ...r }))
  })
  .catch((e) => {
    console.error('[complaint-rollback] failed:', e?.message ?? e)
    process.exit(1)
  })

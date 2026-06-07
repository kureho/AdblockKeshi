// Plan B Task 2.1 CLI entry. Called by .github/workflows/daily-validation.yml
// after tranco-check, before playwright-validate.

import { runCdnCheck } from './cdn-check'
import { envFromProcess } from '../lib/d1-rest'

runCdnCheck(envFromProcess(), { fetch: globalThis.fetch })
  .then((r) => {
    console.log(JSON.stringify({ ok: true, ...r }))
  })
  .catch((e) => {
    console.error('[cdn-check] failed:', e?.message ?? e)
    process.exit(1)
  })

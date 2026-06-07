// Plan B Task 1.3 CLI entry. Called by .github/workflows/daily-validation.yml.

import { runTrancoCheck } from './tranco-check'
import { envFromProcess } from '../lib/d1-rest'

runTrancoCheck(envFromProcess(), { fetch: globalThis.fetch })
  .then((r) => {
    console.log(JSON.stringify({ ok: true, ...r }))
  })
  .catch((e) => {
    console.error('[tranco-check] failed:', e?.message ?? e)
    process.exit(1)
  })

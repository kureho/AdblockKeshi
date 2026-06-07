// Plan B Task 2.2 CLI entry. Called by .github/workflows/daily-validation.yml
// after cdn-check, against status='validating'. Real Playwright is imported
// lazily inside playwright-runner.ts.

import { runPlaywrightValidate } from './playwright-validate'
import { validatePageWithPlaywright } from './playwright-runner'
import { envFromProcess } from '../lib/d1-rest'

runPlaywrightValidate(envFromProcess(), {
  fetch: globalThis.fetch,
  validatePage: validatePageWithPlaywright,
  now: () => Math.floor(Date.now() / 1000),
})
  .then((r) => {
    console.log(JSON.stringify({ ok: true, ...r }))
  })
  .catch((e) => {
    console.error('[playwright-validate] failed:', e?.message ?? e)
    process.exit(1)
  })

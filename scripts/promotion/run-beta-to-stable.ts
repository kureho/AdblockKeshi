// Plan B Task 2.3 CLI entry. Called by weekly-stable-promotion.yml.

import { runBetaPromotion } from './beta-to-stable'
import { envFromProcess } from '../lib/d1-rest'

runBetaPromotion(envFromProcess(), {
  fetch: globalThis.fetch,
  now: () => Math.floor(Date.now() / 1000),
})
  .then((r) => {
    console.log(JSON.stringify({ ok: true, ...r }))
  })
  .catch((e) => {
    console.error('[beta-to-stable] failed:', e?.message ?? e)
    process.exit(1)
  })

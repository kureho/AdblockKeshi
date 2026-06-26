// .github/workflows/hourly-aggregation.yml の aggregation step 後に呼ばれる CLI entry。
// Plan B 層A retention backstop: 14日超の全 url を eTLD+1 / PII redact する。
import { runRetentionBackstop } from './retention-backstop'
import { envFromProcess } from '../lib/d1-rest'

runRetentionBackstop(envFromProcess(), {
  fetch: globalThis.fetch,
  now: () => Math.floor(Date.now() / 1000),
})
  .then((r) => console.log(JSON.stringify({ ok: true, ...r })))
  .catch((e) => {
    console.error('[retention-backstop] failed:', e?.message ?? e)
    process.exit(1)
  })

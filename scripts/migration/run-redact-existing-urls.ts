// Chunk 4 backfill の CLI entry。snapshot + kureho sign-off 後に手動実行する
// （workflow には組まない・1回限り）。CF_* env を envFromProcess() が読む。
import { runBackfillRedaction } from './redact-existing-urls'
import { envFromProcess } from '../lib/d1-rest'

runBackfillRedaction(envFromProcess(), {
  fetch: globalThis.fetch,
  now: () => Math.floor(Date.now() / 1000),
})
  .then((r) => console.log(JSON.stringify({ ok: true, ...r })))
  .catch((e) => {
    console.error('[backfill] failed:', e?.message ?? e)
    process.exit(1)
  })

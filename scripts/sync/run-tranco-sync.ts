// Plan B Task 1.3 CLI entry. Called by .github/workflows/weekly-tranco-sync.yml.
//
// Usage: `tsx run-tranco-sync.ts <csv-file>`. The workflow downloads the
// Tranco zip with curl, unzips with `unzip -p`, and passes the path to the
// extracted CSV here. Keeping unzip in the workflow avoids pulling a zip
// library into Node.js dependencies.

import { readFileSync } from 'node:fs'
import { runTrancoSync } from './tranco-sync'
import { envFromProcess } from '../lib/d1-rest'

const csvPath = process.argv[2]
if (!csvPath) {
  console.error('Usage: run-tranco-sync.ts <csv-file>')
  process.exit(2)
}

runTrancoSync(envFromProcess(), {
  fetch: globalThis.fetch,
  now: () => Math.floor(Date.now() / 1000),
  loadCsv: async () => readFileSync(csvPath, 'utf-8'),
})
  .then((r) => {
    console.log(JSON.stringify({ ok: true, ...r }))
  })
  .catch((e) => {
    console.error('[tranco-sync] failed:', e?.message ?? e)
    process.exit(1)
  })

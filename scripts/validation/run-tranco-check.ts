// Plan B Task 1.3 CLI entry. Called by .github/workflows/daily-validation.yml.
//
// Usage: `tsx run-tranco-check.ts <tranco-csv-file>`
// ワークフローが Tranco の zip を curl + unzip して、その CSV パスを渡す。
// （2026-09-06: D1 の tranco_top_1m を廃止。理由は scripts/lib/tranco-list.ts）

import { readFileSync } from 'node:fs'
import { runTrancoCheck } from './tranco-check'
import { parseTrancoDomains } from '../lib/tranco-list'
import { envFromProcess } from '../lib/d1-rest'

const csvPath = process.argv[2]
if (!csvPath) {
  console.error('Usage: run-tranco-check.ts <tranco-csv-file>')
  process.exit(2)
}

runTrancoCheck(envFromProcess(), {
  fetch: globalThis.fetch,
  loadTrancoSet: async () => parseTrancoDomains(readFileSync(csvPath, 'utf-8')),
})
  .then((r) => {
    console.log(JSON.stringify({ ok: true, ...r }))
  })
  .catch((e) => {
    console.error('[tranco-check] failed:', e?.message ?? e)
    process.exit(1)
  })

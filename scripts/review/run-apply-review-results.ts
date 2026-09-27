// A-88 §2 CLI entry. Called by .github/workflows/apply-review-results.yml.
//
// Usage:
//   tsx run-apply-review-results.ts [--dir <path>] [--dry-run]
//
// --dir   review/results/*.json を探すディレクトリ（既定: リポジトリ直下の review/results）
// --dry-run  D1 に書き込まず、流す予定の SQL/params を stdout に出すだけ
//            （CF_API_TOKEN 等の Secrets が無いローカル環境でも実行できる）

import { readdirSync, readFileSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { applyReviewResultFiles } from './apply-review-results'
import { envFromProcess, type D1Env } from '../lib/d1-rest'

const __dirname = path.dirname(fileURLToPath(import.meta.url))

function parseArgs(argv: string[]) {
  const dryRun = argv.includes('--dry-run')
  const dirFlagIndex = argv.indexOf('--dir')
  const dir =
    dirFlagIndex !== -1 && argv[dirFlagIndex + 1]
      ? argv[dirFlagIndex + 1]
      : path.join(__dirname, '../../review/results')
  return { dryRun, dir }
}

async function main() {
  const { dryRun, dir } = parseArgs(process.argv.slice(2))

  let fileNames: string[]
  try {
    fileNames = readdirSync(dir).filter((f) => f.endsWith('.json')).sort()
  } catch (e) {
    console.error(`[apply-review-results] failed to read dir ${dir}:`, (e as Error).message)
    process.exit(1)
    return
  }

  if (fileNames.length === 0) {
    console.log(JSON.stringify({ ok: true, dry_run: dryRun, results: [] }))
    return
  }

  const files = fileNames.map((name) => ({
    name,
    raw: readFileSync(path.join(dir, name), 'utf-8'),
  }))

  // dry-run はローカルでも動かせる必要がある（Secrets 不要）。
  // 実際に D1 に触るのは applyReviewResultFiles 内の d1Query 呼び出しだけで、
  // dryRun=true のときはそこに到達しないので、ダミー値で足りる。
  const env: D1Env = dryRun ? { CF_API_TOKEN: '', CF_ACCOUNT_ID: '', CF_DATABASE_ID: '' } : envFromProcess()

  const results = await applyReviewResultFiles(env, files, { fetch: globalThis.fetch, dryRun })
  const failed = results.filter((r) => !r.ok)

  console.log(JSON.stringify({ ok: failed.length === 0, dry_run: dryRun, results }, null, dryRun ? 2 : undefined))

  if (failed.length > 0) {
    console.error(`[apply-review-results] ${failed.length} file(s) failed validation:`)
    for (const f of failed) console.error(`  - ${f.fileName}: ${f.error}`)
    process.exit(1)
  }
}

main().catch((e) => {
  console.error('[apply-review-results] failed:', e?.message ?? e)
  process.exit(1)
})

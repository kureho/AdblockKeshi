// scripts/review/check_manual_rules.ts — review/rules/ を配信と同じ検査にかける（自動判定の関門用）
// Usage: tsx check_manual_rules.ts <review/rules のディレクトリ>
// 1 本でも形が外れていれば例外で止まる（weekly-cdn-sync と同じ関数を使う）
import { loadManualRuleFiles, buildReportedRulesJson } from '../sync/reported-rules-build'

const dir = process.argv[2]
if (!dir) {
  console.error('usage: tsx check_manual_rules.ts <dir>')
  process.exit(2)
}
const files = loadManualRuleFiles(dir)
const rules = JSON.parse(buildReportedRulesJson([], files)) as unknown[]
console.log(JSON.stringify({ ok: true, files: files.length, rules: rules.length }))

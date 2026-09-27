// Plan B Task 4.2: build docs/cdn/rules-reported.json from stable rule
// candidates. Pulled by weekly-cdn-sync.yml which then git-commits the file.
//
// Plan C Chunk 5: also patches docs/cdn/version.json with
// `reported.{rule_count, added_last_month}` so that ContentView's moat row
// reflects the actual cumulative + monthly-delta numbers.

import { readdirSync, readFileSync, writeFileSync } from 'node:fs'
import path from 'node:path'
import { d1Query, type D1Env } from '../lib/d1-rest'

export interface StableRuleRow {
  id: string
  rule_text: string
}

export interface ReportedMetrics {
  rule_count: number
  added_last_month: number
}

function flattenRules(rows: StableRuleRow[]): unknown[] {
  const flat: unknown[] = []
  for (const r of rows) {
    if (!r.rule_text) continue
    try {
      const parsed = JSON.parse(r.rule_text)
      if (Array.isArray(parsed)) {
        for (const rule of parsed) flat.push(rule)
      }
    } catch {
      // Skip malformed rule_text rather than poison the entire CDN file.
    }
  }
  return flat
}

// ---------------------------------------------------------------------------
// A-88 §2: 週1回の判定で人（Claude）が書いた「そのサイト限定」のルール。
// review/rules/*.json に置き、D1 の stable 候補の後ろに足して rules-reported.json に載せる
// （旧版も同じファイルを直読みして 2 本目に入れる＝アプリ更新なしで届く）。
// ★公開リポジトリなので、書いてよいのはサイトのドメイン（if-domain）と広告の通信先・要素だけ。
//   報告の URL・パス・メモは入れない。形は review/rules/README.md。
// ---------------------------------------------------------------------------

export interface ManualRuleFile {
  added_at: string
  rules: unknown[]
}

const MANUAL_TRIGGER_KEYS = new Set([
  'url-filter',
  'url-filter-is-case-sensitive',
  'if-domain',
  'resource-type',
  'load-type',
])
const MANUAL_ACTION_TYPES = new Set(['block', 'css-display-none'])
// Safari の if-domain の形（小文字のドメイン・先頭 * でサブドメインも含む）
const IF_DOMAIN_RE = /^\*?[a-z0-9-]+(\.[a-z0-9-]+)*\.[a-z]{2,}$/
// block で「何でも止める」url-filter（サイトごと壊れる）
const CATCH_ALL_FILTERS = new Set(['', '.*', '.+', '^https?://', '^https?://.*'])

function validateManualRule(file: string, index: number, rule: unknown): void {
  const where = `${file} rules[${index}]`
  if (!rule || typeof rule !== 'object') throw new Error(`${where}: オブジェクトではない`)
  const { trigger, action } = rule as { trigger?: Record<string, unknown>; action?: Record<string, unknown> }
  if (!trigger || typeof trigger !== 'object') throw new Error(`${where}: trigger が無い`)
  if (!action || typeof action !== 'object') throw new Error(`${where}: action が無い`)

  for (const key of Object.keys(trigger)) {
    if (!MANUAL_TRIGGER_KEYS.has(key)) throw new Error(`${where}: trigger に ${key} は使えない`)
  }
  const filter = trigger['url-filter']
  if (typeof filter !== 'string') throw new Error(`${where}: url-filter が文字列でない`)
  const domains = trigger['if-domain']
  if (!Array.isArray(domains) || domains.length === 0 || domains.length > 20) {
    throw new Error(`${where}: if-domain（報告されたサイト）が 1〜20 件必要`)
  }
  for (const d of domains) {
    if (typeof d !== 'string' || !IF_DOMAIN_RE.test(d)) {
      throw new Error(`${where}: if-domain の形が不正（${String(d)}）。例: "*example.jp"`)
    }
  }

  const type = action.type
  if (typeof type !== 'string' || !MANUAL_ACTION_TYPES.has(type)) {
    throw new Error(`${where}: action.type は block か css-display-none だけ（${String(type)}）`)
  }
  if (type === 'css-display-none') {
    if (typeof action.selector !== 'string' || action.selector.trim() === '') {
      throw new Error(`${where}: css-display-none には selector が必要`)
    }
  }
  if (type === 'block') {
    const types = trigger['resource-type']
    if (Array.isArray(types) && types.includes('document')) {
      throw new Error(`${where}: document（サイトそのもの）を止める block は使えない`)
    }
    if (CATCH_ALL_FILTERS.has(filter.trim())) {
      throw new Error(`${where}: 何でも止める url-filter の block は使えない（${filter}）`)
    }
  }
}

/** review/rules/<name>.json を 1 本読んで検証する。不正ならファイル名つきで throw（配信を止める）。 */
export function parseManualRuleFile(name: string, raw: string): ManualRuleFile {
  let parsed: unknown
  try {
    parsed = JSON.parse(raw)
  } catch (e) {
    throw new Error(`${name}: JSON として読めない（${(e as Error).message}）`)
  }
  const obj = parsed as { added_at?: unknown; rules?: unknown }
  if (typeof obj?.added_at !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(obj.added_at)) {
    throw new Error(`${name}: added_at は YYYY-MM-DD`)
  }
  if (!Array.isArray(obj.rules) || obj.rules.length === 0) {
    throw new Error(`${name}: rules が空`)
  }
  obj.rules.forEach((r, i) => validateManualRule(name, i, r))
  return { added_at: obj.added_at, rules: obj.rules }
}

/** dir 配下の *.json を名前順に全部読む（README 等は対象外）。dir が無ければ空。 */
export function loadManualRuleFiles(dir: string): ManualRuleFile[] {
  let names: string[]
  try {
    names = readdirSync(dir).filter((f) => f.endsWith('.json')).sort()
  } catch {
    return []
  }
  return names.map((n) => parseManualRuleFile(n, readFileSync(path.join(dir, n), 'utf-8')))
}

function manualRules(files: ManualRuleFile[]): unknown[] {
  return files.flatMap((f) => f.rules)
}

export function buildReportedRulesJson(rows: StableRuleRow[], manual: ManualRuleFile[] = []): string {
  return JSON.stringify([...flattenRules(rows), ...manualRules(manual)])
}

export function computeReportedMetrics(
  allStable: StableRuleRow[],
  recentlyStable: StableRuleRow[],
  manual: ManualRuleFile[] = [],
  recentCutoff?: number
): ReportedMetrics {
  const recentManual =
    recentCutoff === undefined
      ? []
      : manual.filter((f) => Date.parse(`${f.added_at}T00:00:00Z`) / 1000 >= recentCutoff)
  return {
    rule_count: flattenRules(allStable).length + manualRules(manual).length,
    added_last_month: flattenRules(recentlyStable).length + manualRules(recentManual).length,
  }
}

/**
 * Merge the freshly computed reported metrics into an existing version.json
 * payload, preserving every other field. Throws if the input is not valid
 * JSON; callers (the CLI runner / workflow) treat that as fatal.
 */
export function applyReportedToVersionJson(
  versionJson: string,
  metrics: ReportedMetrics
): string {
  const parsed = JSON.parse(versionJson) as Record<string, unknown>
  parsed.reported = metrics
  return JSON.stringify(parsed, null, 2) + '\n'
}

export interface ReportedRulesBuildDeps {
  fetch: typeof globalThis.fetch
  outputPath: string
  /** Path to docs/cdn/version.json. The file's `reported` section is updated. */
  versionJsonPath: string
  /** Returns the current unix timestamp (seconds). Injected for tests. */
  now: () => number
  /** A-88 §2: 人が書いたサイト限定ルールの置き場（review/rules）。省略時は足さない。 */
  manualRulesDir?: string
}

export interface ReportedRulesBuildResult {
  rows_consumed: number
  rules_emitted: number
  reported: ReportedMetrics
}

export async function runReportedRulesBuild(
  env: D1Env,
  deps: ReportedRulesBuildDeps
): Promise<ReportedRulesBuildResult> {
  const recentCutoff = deps.now() - 30 * 24 * 3600
  const stableRows = (await d1Query(
    env,
    deps.fetch,
    `SELECT id, rule_text FROM rule_candidates WHERE status = 'stable' LIMIT 200000`
  )) as StableRuleRow[]
  const recentRows = (await d1Query(
    env,
    deps.fetch,
    `SELECT id, rule_text FROM rule_candidates
       WHERE status = 'stable' AND stable_started_at >= ?
       LIMIT 200000`,
    [recentCutoff]
  )) as StableRuleRow[]

  // 手書きルールが 1 本でも不正なら、ここで throw して配信ファイルを書き換えない
  const manual = deps.manualRulesDir ? loadManualRuleFiles(deps.manualRulesDir) : []

  const rulesJson = buildReportedRulesJson(stableRows, manual)
  writeFileSync(deps.outputPath, rulesJson)

  const metrics = computeReportedMetrics(stableRows, recentRows, manual, recentCutoff)
  const versionJsonRaw = readFileSync(deps.versionJsonPath, 'utf-8')
  writeFileSync(
    deps.versionJsonPath,
    applyReportedToVersionJson(versionJsonRaw, metrics)
  )

  return {
    rows_consumed: stableRows.length,
    rules_emitted: JSON.parse(rulesJson).length as number,
    reported: metrics,
  }
}

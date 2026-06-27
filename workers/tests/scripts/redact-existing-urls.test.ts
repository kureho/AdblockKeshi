import { describe, expect, test } from 'vitest'
import { runBackfillRedaction } from '../../../scripts/migration/redact-existing-urls'

// Chunk 2 (retention-backstop) のテストと同形の D1 REST fetch mock。
// ⚠️ SQL は無視して responses を順番に返すだけなので、SELECT の WHERE 句が
// 実際に絞り込むかは検証できない。検証できるのは「どんな SQL を投げたか」
// （SELECT 形状）と「params の中身」（redact ロジック）まで。
function makeD1FetchMock(responses: Array<{ rows?: any[]; error?: string }>) {
  const calls: Array<{ url: string; body: any }> = []
  let idx = 0
  const fetch = (async (url: string, init: any) => {
    calls.push({ url, body: JSON.parse(init.body) })
    const r = responses[idx++] ?? { rows: [] }
    const payload = r.error
      ? { success: false, errors: [{ message: r.error }] }
      : { success: true, result: [{ results: r.rows ?? [], success: true }] }
    return new Response(JSON.stringify(payload), { status: 200 })
  }) as unknown as typeof fetch
  return { fetch, calls }
}

const ENV = { CF_API_TOKEN: 't', CF_ACCOUNT_ID: 'a', CF_DATABASE_ID: 'd' }
const NOW = 100 * 86400 // day 100 (sec)

describe('runBackfillRedaction', () => {
  test('reports SELECT は terminal(aggregated) かつ未縮約(url LIKE)のみ・in-flight(pending)は構造的に対象外', async () => {
    const { fetch, calls } = makeD1FetchMock([{ rows: [] }, { rows: [] }, { rows: [] }])
    await runBackfillRedaction(ENV, { fetch, now: () => NOW })
    const reportsSelect = calls.find((c) => /FROM reports/i.test(c.body.sql))!
    // whitelist: terminal 'aggregated' のみ。pending(集約待ち=url を集約に使う)は触らない。
    expect(reportsSelect.body.sql).toMatch(/status\s*=\s*'aggregated'/i)
    expect(reportsSelect.body.sql).not.toMatch(/'pending'/i)
    // 既縮約除外（dry-run COUNT を truthful にする + 冪等）
    expect(reportsSelect.body.sql).toMatch(/url\s+LIKE\s+'%\/%'/i)
  })

  test('candidates SELECT は terminal 全列挙・in-flight(aggregating/validating/kureho_queue)は構造的に対象外', async () => {
    const { fetch, calls } = makeD1FetchMock([{ rows: [] }, { rows: [] }, { rows: [] }])
    await runBackfillRedaction(ENV, { fetch, now: () => NOW })
    const candSelect = calls.find((c) => /FROM rule_candidates/i.test(c.body.sql))!
    // terminal を全列挙（plan の例で漏れていた rejected_critical/cdn/rollback も含む）。
    for (const s of [
      'beta',
      'stable',
      'rejected_critical',
      'rejected_cdn',
      'rejected_score_low',
      'rejected_selector_scope',
      'rejected_rollback',
    ]) {
      expect(candSelect.body.sql).toContain(`'${s}'`)
    }
    // in-flight(url を後続処理に使う)を構造的に含めない＝誤縮約(不可逆害)を犯せない設計。
    expect(candSelect.body.sql).not.toMatch(/'aggregating'|'validating'|'kureho_queue'/i)
    expect(candSelect.body.sql).toMatch(/url\s+LIKE\s+'%\/%'/i)
  })

  test('terminal reports.url → eTLD+1 縮約・既縮約は冪等スキップ', async () => {
    const { fetch, calls } = makeD1FetchMock([
      { rows: [
        { id: 't1', url: 'https://x.evil.com/p?q=1' },
        { id: 't2', url: 'evil.com' }, // 既縮約 → 冪等スキップ（UPDATE されない）
      ]}, // [0] SELECT reports
      { rows: [] }, // [1] UPDATE t1
      { rows: [] }, // [2] SELECT candidates
      { rows: [] }, // [3] SELECT abuse_log
    ])
    const r = await runBackfillRedaction(ENV, { fetch, now: () => NOW })
    expect(r.reports_redacted).toBe(1) // t1 のみ
    const upd = calls.find((c) => /UPDATE reports/i.test(c.body.sql))!
    expect(upd.body.params).toEqual(['evil.com', 't1'])
  })

  test('abuse_log は全 url非NULL 対象・broken_site→redactPII / else→normalizeURL', async () => {
    const { fetch, calls } = makeD1FetchMock([
      { rows: [] }, // reports
      { rows: [] }, // candidates
      { rows: [
        { id: 1, reason: 'broken_site', url: '連絡先 0120-111-2222 です' },
        { id: 2, reason: 'critical_domain', url: 'https://bank.example.com/login?s=1' },
      ]},
      { rows: [] }, { rows: [] }, // 2 UPDATE
    ])
    const r = await runBackfillRedaction(ENV, { fetch, now: () => NOW })
    expect(r.abuse_log_redacted).toBe(2)
    const abuseSelect = calls.find((c) => /FROM abuse_log/i.test(c.body.sql))!
    // abuse_log は status を持たない → 全 url非NULL 行が対象（age/status filter 無し）。
    expect(abuseSelect.body.sql).toMatch(/url\s+IS\s+NOT\s+NULL/i)
    const updates = calls.filter((c) => /UPDATE abuse_log/i.test(c.body.sql))
    expect(updates[0].body.params).toEqual(['連絡先 ***-****-**** です', 1]) // redactPII
    expect(updates[1].body.params).toEqual(['example.com', 2]) // normalizeURL
  })
})

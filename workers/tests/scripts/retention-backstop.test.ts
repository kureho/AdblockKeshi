import { describe, expect, test } from 'vitest'
import { runRetentionBackstop } from '../../../scripts/redaction/retention-backstop'

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

describe('runRetentionBackstop', () => {
  test('redacts >14d reports.url to eTLD+1, skips already-reduced (idempotent)', async () => {
    // 実 d1Query 呼び出し順: SELECT reports → (reports ループ内) UPDATE r1
    //   → SELECT rule_candidates → SELECT abuse_log。
    // ⚠️ 応答配列はこの実順で並べること（reports 行を非空にすると直後の応答が
    //    UPDATE に消費されるため、SELECT rule_candidates 用の行をここに混ぜない）。
    const { fetch, calls } = makeD1FetchMock([
      { rows: [
        { id: 'r1', url: 'https://sub.evil.com/track?t=secret' },
        { id: 'r2', url: 'evil.com' }, // 既縮約 → 冪等スキップ（UPDATE されない）
      ]}, // [0] SELECT reports
      { rows: [] }, // [1] UPDATE r1
      { rows: [] }, // [2] SELECT rule_candidates
      { rows: [] }, // [3] SELECT abuse_log
    ])
    const r = await runRetentionBackstop(ENV, { fetch, now: () => NOW })
    expect(r.reports_redacted).toBe(1) // r1 のみ（r2 は冪等スキップ）
    expect(calls[0].body.params[0]).toBe(NOW - 14 * 86400)
    const upd = calls.find((c) => /UPDATE reports/i.test(c.body.sql))!
    expect(upd.body.params).toEqual(['evil.com', 'r1'])
  })

  test('abuse_log: broken_site → redactPII, others → normalizeURL', async () => {
    const { fetch, calls } = makeD1FetchMock([
      { rows: [] }, // reports
      { rows: [] }, // rule_candidates
      { rows: [
        { id: 1, reason: 'broken_site', url: '連絡先 0120-111-2222 です' },
        { id: 2, reason: 'critical_domain', url: 'https://bank.example.com/login?s=1' },
      ]},
      { rows: [] }, { rows: [] }, // 2 UPDATE
    ])
    const r = await runRetentionBackstop(ENV, { fetch, now: () => NOW })
    expect(r.abuse_log_redacted).toBe(2)
    const updates = calls.filter((c) => /UPDATE abuse_log/i.test(c.body.sql))
    expect(updates[0].body.params).toEqual(['連絡先 ***-****-**** です', 1]) // redactPII
    expect(updates[1].body.params).toEqual(['example.com', 2]) // normalizeURL
  })
})

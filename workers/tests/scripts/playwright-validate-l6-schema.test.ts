// Regression test for the L6 schema/code drift bug (migration 0010).
//
// scripts/validation/playwright-validate.ts writes `l6_check` in its UPDATE
// (line ~62), but no migration ever created that column on rule_candidates.
// The mock-fetch test in playwright-validate.test.ts cannot catch this because
// it never runs SQL against a real schema. This test applies the real
// migrations to miniflare D1 (via tests/setup.ts applyD1Migrations) and runs
// the actual UPDATE shape, so a missing column fails loudly.
//
// Before 0010: RED with "no such column: l6_check".
// After  0010: GREEN.

import { describe, it, expect, beforeEach } from 'vitest'
import { env } from 'cloudflare:test'

async function insertValidatingCandidate(id: string): Promise<void> {
  // All NOT NULL columns (0002 schema) must be provided, otherwise the INSERT
  // fails with a NOT NULL constraint and masks the column-existence assertion.
  await env.DB.prepare(
    `INSERT INTO rule_candidates
       (id, domain, rule_text, unique_uuid_count, unique_ip_count,
        first_reported_at, last_reported_at, status, url)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`
  )
    .bind(id, 'ads.example', '[]', 5, 5, 1000, 2000, 'validating', 'https://ads.example/p')
    .run()
}

describe('rule_candidates l6_check column (migration 0010 regression)', () => {
  beforeEach(async () => {
    await env.DB.prepare('DELETE FROM rule_candidates').run()
  })

  it('schema exposes the l6_check column', async () => {
    // Drift-proof, INSERT-independent guard.
    const { results } = await env.DB.prepare('PRAGMA table_info(rule_candidates)').all<{ name: string }>()
    const columns = results.map((r) => r.name)
    expect(columns).toContain('l6_check')
  })

  it('persists l6_check via the playwright-validate UPDATE (matches playwright-validate.ts:60)', async () => {
    await insertValidatingCandidate('test-l6-1')

    // Sanity: prove the INSERT succeeded, so a RED below is the column error,
    // not a setup failure.
    const before = await env.DB.prepare('SELECT status FROM rule_candidates WHERE id = ?')
      .bind('test-l6-1')
      .first<{ status: string }>()
    expect(before?.status).toBe('validating')

    // Exact UPDATE shape from scripts/validation/playwright-validate.ts:60-69.
    // url は normalizeURL で eTLD+1 に縮約済みの値を渡す（層B）。
    await env.DB.prepare(
      `UPDATE rule_candidates
          SET status = ?,
              l6_check = ?,
              validation_score = ?,
              selector = ?,
              rule_text = ?,
              beta_started_at = COALESCE(?, beta_started_at),
              url = ?
        WHERE id = ?`
    )
      .bind('beta', 'pass', 1.0, '.banner-ad-123', '[{"action":"x"}]', 7777, 'ads.example', 'test-l6-1')
      .run()

    const row = await env.DB.prepare(
      'SELECT status, l6_check, validation_score, beta_started_at FROM rule_candidates WHERE id = ?'
    )
      .bind('test-l6-1')
      .first<{ status: string; l6_check: string; validation_score: number; beta_started_at: number }>()

    expect(row?.l6_check).toBe('pass')
    expect(row?.status).toBe('beta')
    expect(row?.validation_score).toBe(1.0)
    expect(row?.beta_started_at).toBe(7777)
  })
})

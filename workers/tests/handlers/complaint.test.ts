// Plan B Task 2.4 — POST /v1/reports/complaint handler tests.

import { describe, it, expect, beforeEach } from 'vitest'
import { env } from 'cloudflare:test'
import { handleComplaint } from '../../src/handlers/complaint'
import { signToken } from '../../src/lib/hmac'

const HEX64 = (c: string) => c.repeat(64)

async function mintComplaintToken(uuidHash: string, expiresInMs = 60_000) {
  return signToken(
    {
      subject: uuidHash,
      expires: Date.now() + expiresInMs,
      scope: 'complaint' as any,
    },
    env.HMAC_KEY
  )
}

function jsonRequest(body: any) {
  return new Request('https://test.local/v1/reports/complaint', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'CF-Connecting-IP': '203.0.113.10',
    },
    body: JSON.stringify(body),
  })
}

describe('handleComplaint', () => {
  beforeEach(async () => {
    await env.DB.prepare('DELETE FROM abuse_log').run()
    await env.DB.prepare('DELETE FROM rule_candidates').run()
  })

  it('rejects non-POST', async () => {
    const r = await handleComplaint(
      new Request('https://test.local/v1/reports/complaint', { method: 'GET' }),
      env
    )
    expect(r.status).toBe(405)
  })

  it('rejects invalid JSON', async () => {
    const r = await handleComplaint(
      new Request('https://test.local/v1/reports/complaint', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: '{ not json',
      }),
      env
    )
    expect(r.status).toBe(400)
  })

  it('rejects missing fields', async () => {
    const token = await mintComplaintToken(HEX64('a'))
    const r = await handleComplaint(jsonRequest({ token, uuid_hash: HEX64('a') }), env)
    expect(r.status).toBe(400)
    const body = (await r.json()) as any
    expect(body.error).toBe('validation_failed')
  })

  it('rejects token with wrong scope', async () => {
    const submitToken = await signToken(
      {
        subject: HEX64('a'),
        expires: Date.now() + 60_000,
        scope: 'submit',
      },
      env.HMAC_KEY
    )
    const r = await handleComplaint(
      jsonRequest({
        token: submitToken,
        uuid_hash: HEX64('a'),
        rule_candidate_id: '11111111-1111-1111-1111-111111111111',
      }),
      env
    )
    expect(r.status).toBe(401)
  })

  it('rejects token with mismatched uuid_hash (IDOR防止)', async () => {
    const token = await mintComplaintToken(HEX64('a'))
    const r = await handleComplaint(
      jsonRequest({
        token,
        uuid_hash: HEX64('b'), // different uuid
        rule_candidate_id: '11111111-1111-1111-1111-111111111111',
      }),
      env
    )
    expect(r.status).toBe(401)
  })

  it('404 when rule_candidate_id does not exist', async () => {
    const token = await mintComplaintToken(HEX64('a'))
    const r = await handleComplaint(
      jsonRequest({
        token,
        uuid_hash: HEX64('a'),
        rule_candidate_id: 'nonexistent-id',
      }),
      env
    )
    expect(r.status).toBe(404)
  })

  it('records complaint: increments complaint_count + inserts abuse_log row', async () => {
    const ruleId = 'rc-test-1'
    await env.DB.prepare(`
      INSERT INTO rule_candidates
        (id, domain, selector, rule_text, unique_uuid_count, unique_ip_count,
         first_reported_at, last_reported_at, status, complaint_count)
      VALUES (?, ?, NULL, '', 5, 3, 1000, 2000, 'beta', 0)
    `).bind(ruleId, 'example.com').run()

    const uuid = HEX64('a')
    const token = await mintComplaintToken(uuid)
    const r = await handleComplaint(
      jsonRequest({ token, uuid_hash: uuid, rule_candidate_id: ruleId, reason: 'site broken' }),
      env
    )
    expect(r.status).toBe(200)
    const body = (await r.json()) as any
    expect(body.ok).toBe(true)
    expect(body.complaint_count).toBe(1)

    const rc = await env.DB.prepare('SELECT complaint_count FROM rule_candidates WHERE id = ?').bind(ruleId).first<any>()
    expect(rc.complaint_count).toBe(1)

    const log = await env.DB.prepare("SELECT * FROM abuse_log WHERE reason = 'broken_site'").first<any>()
    expect(log.identifier_hash).toBe(uuid)
    expect(log.identifier_type).toBe('uuid')
  })

  it('same uuid_hash complaining twice on same rule only counts once', async () => {
    const ruleId = 'rc-test-2'
    await env.DB.prepare(`
      INSERT INTO rule_candidates
        (id, domain, selector, rule_text, unique_uuid_count, unique_ip_count,
         first_reported_at, last_reported_at, status, complaint_count)
      VALUES (?, 'a.com', NULL, '', 5, 3, 1000, 2000, 'beta', 0)
    `).bind(ruleId).run()

    const uuid = HEX64('c')
    const token1 = await mintComplaintToken(uuid)
    await handleComplaint(
      jsonRequest({ token: token1, uuid_hash: uuid, rule_candidate_id: ruleId }),
      env
    )
    const token2 = await mintComplaintToken(uuid)
    const r2 = await handleComplaint(
      jsonRequest({ token: token2, uuid_hash: uuid, rule_candidate_id: ruleId }),
      env
    )
    // Second call returns 200 but does not double-count.
    expect(r2.status).toBe(200)
    const body = (await r2.json()) as any
    expect(body.complaint_count).toBe(1)

    const rc = await env.DB.prepare('SELECT complaint_count FROM rule_candidates WHERE id = ?').bind(ruleId).first<any>()
    expect(rc.complaint_count).toBe(1)
  })
})

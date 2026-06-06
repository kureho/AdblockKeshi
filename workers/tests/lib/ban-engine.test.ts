import { describe, it, expect, beforeEach } from 'vitest'
import { env } from 'cloudflare:test'
import { determineBanLevel, runBanEngine } from '../../src/lib/ban-engine'

describe('determineBanLevel', () => {
  it('returns null for count < 3', () => {
    expect(determineBanLevel(0)).toBeNull()
    expect(determineBanLevel(2)).toBeNull()
  })
  it('returns L1 for count 3-9', () => {
    expect(determineBanLevel(3)?.level).toBe(1)
    expect(determineBanLevel(9)?.level).toBe(1)
  })
  it('returns L2 for count 10-29', () => {
    expect(determineBanLevel(10)?.level).toBe(2)
    expect(determineBanLevel(29)?.level).toBe(2)
  })
  it('returns L3 for count 30-99', () => {
    expect(determineBanLevel(30)?.level).toBe(3)
    expect(determineBanLevel(99)?.level).toBe(3)
  })
  it('returns L4 for count >= 100', () => {
    expect(determineBanLevel(100)?.level).toBe(4)
    expect(determineBanLevel(500)?.level).toBe(4)
  })
})

describe('runBanEngine', () => {
  const HEX64 = (c: string) => c.repeat(64)

  beforeEach(async () => {
    await env.DB.prepare('DELETE FROM abuse_log').run()
    await env.DB.prepare('DELETE FROM bans').run()
  })

  it('does not ban for ban-加算除外 reason pii_redacted', async () => {
    const now = Math.floor(Date.now() / 1000)
    const uuid = HEX64('a')
    for (let i = 0; i < 10; i++) {
      await env.DB.prepare(
        'INSERT INTO abuse_log (identifier_hash, identifier_type, reason, created_at) VALUES (?, ?, ?, ?)'
      ).bind(uuid, 'uuid', 'pii_redacted', now - 100).run()
    }
    const result = await runBanEngine(env.DB, now)
    expect(result.banned).toBe(0)

    const ban = await env.DB.prepare('SELECT * FROM bans WHERE identifier_hash = ?').bind(uuid).first()
    expect(ban).toBeNull()
  })

  it('bans uuid with 3 rate_limit abuses to L1 (24h)', async () => {
    const now = Math.floor(Date.now() / 1000)
    const uuid = HEX64('b')
    for (let i = 0; i < 3; i++) {
      await env.DB.prepare(
        'INSERT INTO abuse_log (identifier_hash, identifier_type, reason, created_at) VALUES (?, ?, ?, ?)'
      ).bind(uuid, 'uuid', 'rate_limit', now - i).run()
    }
    const result = await runBanEngine(env.DB, now)
    expect(result.banned).toBe(1)

    const ban = await env.DB.prepare('SELECT ban_level, expires_at FROM bans WHERE identifier_hash = ?').bind(uuid).first<any>()
    expect(ban.ban_level).toBe(1)
    expect(ban.expires_at).toBe(now + 24 * 3600)
  })

  it('upgrades existing L1 ban to L2 when abuse count crosses 10', async () => {
    const now = Math.floor(Date.now() / 1000)
    const uuid = HEX64('c')
    // 既存 L1 ban
    await env.DB.prepare(`
      INSERT INTO bans (identifier_hash, identifier_type, reason, abuse_count, ban_level, expires_at, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?)
    `).bind(uuid, 'uuid', 'auto_initial', 5, 1, now + 100, now - 100).run()
    // 新規 abuse 10 件
    for (let i = 0; i < 12; i++) {
      await env.DB.prepare(
        'INSERT INTO abuse_log (identifier_hash, identifier_type, reason, created_at) VALUES (?, ?, ?, ?)'
      ).bind(uuid, 'uuid', 'spam_memo', now - i).run()
    }
    const result = await runBanEngine(env.DB, now)
    expect(result.upgraded).toBe(1)

    const ban = await env.DB.prepare('SELECT ban_level FROM bans WHERE identifier_hash = ?').bind(uuid).first<any>()
    expect(ban.ban_level).toBe(2)
  })

  it('mixed reasons: only ban-加算対象 counted', async () => {
    const now = Math.floor(Date.now() / 1000)
    const uuid = HEX64('d')
    // 2 rate_limit + 2 pii_redacted = 加算対象は 2 件 (< 3, no ban)
    for (let i = 0; i < 2; i++) {
      await env.DB.prepare(
        'INSERT INTO abuse_log (identifier_hash, identifier_type, reason, created_at) VALUES (?, ?, ?, ?)'
      ).bind(uuid, 'uuid', 'rate_limit', now - i).run()
      await env.DB.prepare(
        'INSERT INTO abuse_log (identifier_hash, identifier_type, reason, created_at) VALUES (?, ?, ?, ?)'
      ).bind(uuid, 'uuid', 'pii_redacted', now - i - 50).run()
    }
    const result = await runBanEngine(env.DB, now)
    expect(result.banned).toBe(0)
  })

  it('ignores abuses outside 24h window', async () => {
    const now = Math.floor(Date.now() / 1000)
    const uuid = HEX64('e')
    // 古い (25h 前)
    for (let i = 0; i < 5; i++) {
      await env.DB.prepare(
        'INSERT INTO abuse_log (identifier_hash, identifier_type, reason, created_at) VALUES (?, ?, ?, ?)'
      ).bind(uuid, 'uuid', 'rate_limit', now - 25 * 3600 - i).run()
    }
    const result = await runBanEngine(env.DB, now)
    expect(result.banned).toBe(0)
  })
})

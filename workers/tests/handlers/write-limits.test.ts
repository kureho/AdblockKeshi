import { describe, it, expect, beforeEach } from 'vitest'
import { SELF, env } from 'cloudflare:test'
import { signToken } from '../../src/lib/hmac'
import { sha256Hex } from '../../src/lib/hash'
import { hashClientIp } from '../../src/lib/ip-hash'

const HEX64 = (c: string) => c.repeat(64)
const IP = '203.0.113.77'

type Scope = 'submit' | 'history' | 'delete' | 'complaint'
const tok = (uuid: string, scope: Scope) =>
  signToken({ subject: uuid, expires: Date.now() + 60000, scope }, env.HMAC_KEY)

const post = (path: string, body: unknown, raw = false) =>
  SELF.fetch(`https://test/v1/reports/${path}`, {
    method: 'POST',
    body: raw ? (body as string) : JSON.stringify(body),
    headers: { 'Content-Type': 'application/json', 'CF-Connecting-IP': IP },
  })

describe('request body shape (all POST handlers)', () => {
  const paths = ['token', 'submit', 'history', 'delete', 'complaint', 'status']
  for (const path of paths) {
    for (const raw of ['null', '[]', '"str"', '123', 'true']) {
      it(`${path}: body ${raw} -> 400 (not 500)`, async () => {
        const r = await post(path, raw, true)
        expect(r.status).toBe(400)
      })
    }
  }

  it('oversized body -> 413', async () => {
    const r = await post('submit', JSON.stringify({ token: 'x'.repeat(20000) }), true)
    expect(r.status).toBe(413)
  })
})

describe('submit input types and sizes', () => {
  beforeEach(async () => {
    await env.DB.prepare('DELETE FROM reports').run()
    await env.DB.prepare('DELETE FROM abuse_log').run()
    await env.DB.prepare('DELETE FROM bans').run()
  })

  it('rejects non-hex / uppercase uuid_hash (64 chars)', async () => {
    for (const bad of ['g'.repeat(64), 'A'.repeat(64)]) {
      const token = await tok(bad, 'submit')
      const r = await post('submit', { token, uuid_hash: bad, url: 'https://example.com/a' })
      expect(r.status).toBe(400)
    }
  })

  it('rejects non-string url / memo / token without logging', async () => {
    const uuid = HEX64('a')
    const token = await tok(uuid, 'submit')
    expect((await post('submit', { token, uuid_hash: uuid, url: 123 })).status).toBe(400)
    expect((await post('submit', { token, uuid_hash: uuid, url: { a: 1 } })).status).toBe(400)
    expect((await post('submit', { token, uuid_hash: uuid, url: 'https://example.com/a', memo: ['x'] })).status).toBe(400)
    expect((await post('submit', { token: 5, uuid_hash: uuid, url: 'https://example.com/a' })).status).toBe(400)
    const c = await env.DB.prepare('SELECT COUNT(*) AS c FROM abuse_log').first<{ c: number }>()
    expect(c!.c).toBe(0)
  })

  it('rejects a memo that is short in graphemes but huge in bytes', async () => {
    const uuid = HEX64('b')
    const token = await tok(uuid, 'submit')
    // 1 書記素 + 結合文字 5万個 = 見た目 1 文字・約 100KB
    const memo = 'a' + '́'.repeat(50000)
    const r = await post('submit', { token, uuid_hash: uuid, url: 'https://example.com/a', memo })
    expect(r.status).toBe(413)
    // 本体上限内でもバイト上限で弾く
    const memo2 = 'a' + '́'.repeat(4000)
    const r2 = await post('submit', { token, uuid_hash: uuid, url: 'https://example.com/a', memo: memo2 })
    expect(r2.status).toBe(400)
    expect(((await r2.json()) as any).message).toBe('memo_too_long')
  })

  it('accepts a normal Japanese memo of 200 characters', async () => {
    const uuid = HEX64('c')
    const token = await tok(uuid, 'submit')
    const r = await post('submit', { token, uuid_hash: uuid, url: 'https://example.com/a', memo: 'あ'.repeat(200) })
    expect(r.status).toBe(200)
  })
})

describe('abuse_log write cap', () => {
  beforeEach(async () => {
    await env.DB.prepare('DELETE FROM reports').run()
    await env.DB.prepare('DELETE FROM abuse_log').run()
    await env.DB.prepare('DELETE FROM bans').run()
  })

  it('caps abuse_log writes per subject and reason', async () => {
    const uuid = HEX64('d')
    const token = await tok(uuid, 'submit')
    for (let i = 0; i < 40; i++) {
      const r = await post('submit', { token, uuid_hash: uuid, url: 'http://not-https.example.com/' })
      expect(r.status).toBe(400)
    }
    const c = await env.DB.prepare(
      "SELECT COUNT(*) AS c FROM abuse_log WHERE identifier_hash = ? AND reason = 'invalid_url'"
    ).bind(uuid).first<{ c: number }>()
    expect(c!.c).toBe(20)
  })

  it('does not log for a subject that is already banned', async () => {
    const uuid = HEX64('e')
    const now = Math.floor(Date.now() / 1000)
    await env.DB.prepare(
      "INSERT INTO bans (identifier_hash, identifier_type, reason, abuse_count, ban_level, expires_at, created_at) VALUES (?, 'uuid', 'auto_initial', 3, 1, ?, ?)"
    ).bind(uuid, now + 3600, now).run()
    const token = await tok(uuid, 'submit')
    await post('submit', { token, uuid_hash: uuid, url: 'http://not-https.example.com/' })
    const c = await env.DB.prepare('SELECT COUNT(*) AS c FROM abuse_log WHERE identifier_hash = ?').bind(uuid).first<{ c: number }>()
    expect(c!.c).toBe(0)
  })

  it('first rejected submissions are still recorded (ban engine input kept)', async () => {
    const uuid = HEX64('f')
    const token = await tok(uuid, 'submit')
    for (let i = 0; i < 3; i++) await post('submit', { token, uuid_hash: uuid, url: 'http://not-https.example.com/' })
    const c = await env.DB.prepare('SELECT COUNT(*) AS c FROM abuse_log WHERE identifier_hash = ?').bind(uuid).first<{ c: number }>()
    expect(c!.c).toBe(3)
  })
})

describe('delete request dedupe', () => {
  beforeEach(async () => {
    await env.DB.prepare('DELETE FROM deletion_requests').run()
  })

  it('same uuid + same scope returns the existing id and keeps one row', async () => {
    const uuid = HEX64('a')
    const token = await tok(uuid, 'delete')
    const r1 = await post('delete', { token, uuid_hash: uuid })
    const r2 = await post('delete', { token, uuid_hash: uuid })
    expect(r1.status).toBe(202)
    expect(r2.status).toBe(202)
    expect(((await r1.json()) as any).id).toBe(((await r2.json()) as any).id)
    const c = await env.DB.prepare('SELECT COUNT(*) AS c FROM deletion_requests WHERE uuid_hash = ?').bind(uuid).first<{ c: number }>()
    expect(c!.c).toBe(1)
  })

  it('different url_path_hash is a different scope; same one dedupes', async () => {
    const uuid = HEX64('b')
    const token = await tok(uuid, 'delete')
    await post('delete', { token, uuid_hash: uuid, url_path_hash: 'h1' })
    await post('delete', { token, uuid_hash: uuid, url_path_hash: 'h1' })
    await post('delete', { token, uuid_hash: uuid, url_path_hash: 'h2' })
    await post('delete', { token, uuid_hash: uuid })
    const c = await env.DB.prepare('SELECT COUNT(*) AS c FROM deletion_requests WHERE uuid_hash = ?').bind(uuid).first<{ c: number }>()
    expect(c!.c).toBe(3)
  })

  it('completed requests do not block a new request', async () => {
    const uuid = HEX64('c')
    const token = await tok(uuid, 'delete')
    const r1 = await post('delete', { token, uuid_hash: uuid })
    const id1 = ((await r1.json()) as any).id
    await env.DB.prepare("UPDATE deletion_requests SET status = 'completed' WHERE id = ?").bind(id1).run()
    const r2 = await post('delete', { token, uuid_hash: uuid })
    expect(((await r2.json()) as any).id).not.toBe(id1)
  })

  it('caps pending requests per uuid (429)', async () => {
    const uuid = HEX64('d')
    const token = await tok(uuid, 'delete')
    for (let i = 0; i < 20; i++) {
      expect((await post('delete', { token, uuid_hash: uuid, url_path_hash: `h${i}` })).status).toBe(202)
    }
    expect((await post('delete', { token, uuid_hash: uuid, url_path_hash: 'h-over' })).status).toBe(429)
    // 既存と同じ範囲の再送は上限後も既存 id を返す
    expect((await post('delete', { token, uuid_hash: uuid, url_path_hash: 'h0' })).status).toBe(202)
  })

  it('rejects non-string / oversized url_path_hash', async () => {
    const uuid = HEX64('e')
    const token = await tok(uuid, 'delete')
    expect((await post('delete', { token, uuid_hash: uuid, url_path_hash: 5 })).status).toBe(400)
    expect((await post('delete', { token, uuid_hash: uuid, url_path_hash: 'x'.repeat(200) })).status).toBe(400)
  })
})

describe('ip_hash salt separation', () => {
  beforeEach(async () => {
    await env.DB.prepare('DELETE FROM reports').run()
    await env.DB.prepare('DELETE FROM abuse_log').run()
    await env.DB.prepare('DELETE FROM bans').run()
  })

  it('stores ip_hash with IP_HASH_SALT, not the SERVER_SALT returned to clients', async () => {
    const uuid = HEX64('a')
    const token = await tok(uuid, 'submit')
    const r = await post('submit', { token, uuid_hash: uuid, url: 'https://example.com/a' })
    expect(r.status).toBe(200)
    const row = await env.DB.prepare('SELECT ip_hash FROM reports WHERE uuid_hash = ?').bind(uuid).first<{ ip_hash: string }>()
    expect(row!.ip_hash).toBe(await sha256Hex(IP + ':test-ip-hash-salt'))
    expect(row!.ip_hash).not.toBe(await sha256Hex(IP + ':' + env.SERVER_SALT))
  })

  it('still honors an IP ban recorded with the legacy hash (transition)', async () => {
    const uuid = HEX64('b')
    const now = Math.floor(Date.now() / 1000)
    const legacy = await sha256Hex(IP + ':' + env.SERVER_SALT)
    await env.DB.prepare(
      "INSERT INTO bans (identifier_hash, identifier_type, reason, abuse_count, ban_level, expires_at, created_at) VALUES (?, 'ip', 'auto_initial', 3, 1, ?, ?)"
    ).bind(legacy, now + 3600, now).run()
    const token = await tok(uuid, 'submit')
    const r = await post('submit', { token, uuid_hash: uuid, url: 'https://example.com/a' })
    expect(r.status).toBe(403)
  })

  it('counts legacy-hash reports in the 15-minute IP window (transition)', async () => {
    const now = Math.floor(Date.now() / 1000)
    const legacy = await sha256Hex(IP + ':' + env.SERVER_SALT)
    for (let i = 0; i < 5; i++) {
      await env.DB.prepare(
        "INSERT INTO reports (id, uuid_hash, ip_hash, domain, url, url_path_hash, status, created_at) VALUES (?, ?, ?, 'example.com', 'https://example.com/', 'h', 'pending', ?)"
      ).bind(`id-${i}`, HEX64(String(i)), legacy, now).run()
    }
    const uuid = HEX64('c')
    const token = await tok(uuid, 'submit')
    const r = await post('submit', { token, uuid_hash: uuid, url: 'https://example.com/a' })
    expect(r.status).toBe(429)
  })

  it('falls back to SERVER_SALT when IP_HASH_SALT is unset (deploy before secret)', async () => {
    const withSalt = await hashClientIp(env, IP)
    expect(withSalt.legacyIpHash).toBe(await sha256Hex(IP + ':' + env.SERVER_SALT))
    const fallback = await hashClientIp({ ...env, IP_HASH_SALT: undefined } as any, IP)
    expect(fallback.ipHash).toBe(await sha256Hex(IP + ':' + env.SERVER_SALT))
    expect(fallback.legacyIpHash).toBeNull()
  })
})

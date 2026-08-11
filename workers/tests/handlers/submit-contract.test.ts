import { describe, it, expect, beforeEach } from 'vitest'
import { SELF, env } from 'cloudflare:test'
import { signToken } from '../../src/lib/hmac'
import { SEEN_IN_VALUES } from '../../src/lib/seen-in'
// workerd 上で動くので fs は使えない。Vite に JSON をバンドルさせて読み込む。
import contractJSON from '../../../contracts/submit-request.json'

/**
 * iOS ↔ Workers の submit ペイロード契約テスト（サーバ側）。
 *
 * `contracts/submit-request.json` を **両言語が同じ 1 ファイル**として突き合わせる。
 * クライアント側は `Tests/SubmitContractTests.swift` が同じファイルと DTO の一致を検証する。
 * 片側だけキー名を変えたら、どちらかが必ず落ちる。
 */
const contract = contractJSON as Record<string, unknown>

const HEX64 = (c: string) => c.repeat(64)

describe('submit contract (contracts/submit-request.json)', () => {
  beforeEach(async () => {
    await env.DB.prepare('DELETE FROM reports').run()
    await env.DB.prepare('DELETE FROM abuse_log').run()
    await env.DB.prepare('DELETE FROM bans').run()
  })

  async function postContract(overrides: Record<string, unknown> = {}) {
    const uuid = HEX64('c')
    const token = await signToken(
      { subject: uuid, expires: Date.now() + 60000, scope: 'submit' },
      env.HMAC_KEY
    )
    // token / uuid_hash だけは実行時に署名し直す。他のキーは契約ファイルそのまま。
    const body = { ...contract, token, uuid_hash: uuid, ...overrides }
    const response = await SELF.fetch('https://test/v1/reports/submit', {
      method: 'POST',
      body: JSON.stringify(body),
      headers: { 'Content-Type': 'application/json' },
    })
    return { response, uuid }
  }

  it('accepts the iOS payload verbatim and stores every field', async () => {
    const { response } = await postContract()
    expect(response.status).toBe(200)
    const body = (await response.json()) as any
    expect(body.status).toBe('pending')

    const row = await env.DB.prepare('SELECT * FROM reports WHERE id = ?')
      .bind(body.id).first<any>()

    expect(row.url).toBe(contract.url)
    expect(row.memo).toBe(contract.memo)
    expect(row.ad_type).toBe(contract.ad_type)
    expect(row.seen_in).toBe(contract.seen_in)
    // SQLite は boolean を 1/0 で保持する
    expect(row.blocker_enabled).toBe(contract.blocker_enabled ? 1 : 0)
    expect(row.dns_enabled).toBe(contract.dns_enabled ? 1 : 0)
    expect(row.app_version).toBe(contract.app_version)
    expect(row.app_build).toBe(contract.app_build)
    expect(row.filter_version).toBe(contract.filter_version)
  })

  it('uses a seen_in value that the server recognises', () => {
    expect(SEEN_IN_VALUES).toContain(contract.seen_in)
  })

  /** Content Blocker OFF の報告も通り、blocker_enabled=0 として残る。 */
  it('stores blocker_enabled=0 when the client reports the blocker was off', async () => {
    const { response } = await postContract({ blocker_enabled: false })
    expect(response.status).toBe(200)
    const body = (await response.json()) as any
    const row = await env.DB.prepare('SELECT blocker_enabled FROM reports WHERE id = ?')
      .bind(body.id).first<any>()
    expect(row.blocker_enabled).toBe(0)
  })

  /** 診断がひとつも取れなかったクライアント（全 nil = キー省略）でも報告は成立する。 */
  it('accepts the payload with every diagnostic omitted', async () => {
    const uuid = HEX64('d')
    const token = await signToken(
      { subject: uuid, expires: Date.now() + 60000, scope: 'submit' },
      env.HMAC_KEY
    )
    const response = await SELF.fetch('https://test/v1/reports/submit', {
      method: 'POST',
      body: JSON.stringify({
        token, uuid_hash: uuid, url: contract.url, seen_in: contract.seen_in,
      }),
      headers: { 'Content-Type': 'application/json' },
    })
    expect(response.status).toBe(200)
    const body = (await response.json()) as any
    expect(body.status).toBe('pending')

    const row = await env.DB.prepare('SELECT * FROM reports WHERE id = ?')
      .bind(body.id).first<any>()
    expect(row.blocker_enabled).toBeNull()
    expect(row.dns_enabled).toBeNull()
    expect(row.app_version).toBeNull()
    expect(row.app_build).toBeNull()
    expect(row.filter_version).toBeNull()
  })

  /** 保護ドメイン（旧「案 A」で弾いていたもの）も閲覧ページとして正常に受理される。 */
  it('accepts protected domains as the browsed page', async () => {
    for (const url of ['https://www.yahoo.co.jp/news', 'https://www.apple.com/jp/']) {
      const { response, uuid } = await postContract({ url })
      expect(response.status, `${url} は受理されるべき`).toBe(200)

      const abuse = await env.DB.prepare(
        'SELECT COUNT(*) AS n FROM abuse_log WHERE identifier_hash = ?'
      ).bind(uuid).first<any>()
      expect(abuse.n, '誤操作ではないので abuse_log にも記録しない').toBe(0)
    }
  })
})

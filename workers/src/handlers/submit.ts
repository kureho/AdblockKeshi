import type { Env } from '../env'
import { verifyToken } from '../lib/hmac'
import { validateURL, validateMemo } from '../lib/validation'
import { redactPII } from '../lib/pii-redact'
import { checkRateLimit } from '../lib/rate-limit'
import { sha256Hex } from '../lib/hash'
import { isAdType, type AdType } from '../lib/ad-type'
import { isSeenIn, type SeenIn } from '../lib/seen-in'
import { isReportKind, type ReportKind } from '../lib/report-kind'

interface SubmitBody {
  token?: string
  uuid_hash?: string
  url?: string
  memo?: string
  ad_type?: string
  /** v4.2.0: 報告種別。未送信/未知値 = NULL 保存 = 広告報告の意味。 */
  report_kind?: string
  /** D-lite: どこで見た広告か。新クライアントのみ送る（有無が新旧の境界）。 */
  seen_in?: string
  /** 以下は診断用の自動添付。取得できなくても報告を失敗させないため全て任意。 */
  blocker_enabled?: boolean
  dns_enabled?: boolean
  app_version?: string
  app_build?: string
  filter_version?: string
}

/**
 * POST /v1/reports/submit
 * Body: { token, uuid_hash, url, memo? }
 * Chain (spec rev4):
 *   1. body shape
 *   2. HMAC token verify (scope=submit)
 *   3. URL validate (https-only, length, host) — invalid_url abuse_log
 *   4. memo validate (length, no embedded URL) — spam_memo abuse_log
 *   5. PII redact (silent, ban-加算なし) — pii_redacted abuse_log only if redacted
 *   6. rate limit (uuid daily/monthly, ip 15min, banned) — rate_limit abuse_log
 *   7. D1 INSERT（seen_in の有無で status を pending / observation_legacy に振り分け）
 *
 * ★D-lite: 保護ドメインの拒否は廃止した。報告は「広告が消えなかったページ」の改善用データで、
 * yahoo.co.jp 等を送るのは正常な操作。自動昇格を止めるのは L3（critical → kureho_queue）の責務。
 *
 * Each abuse reason (rate_limit/spam_memo/invalid_url) is logged; ban-engine aggregates
 * only BAN_ELIGIBLE_REASONS (ban-engine-core) into 4-tier auto-bans — pii_redacted は記録のみ.
 */
export async function handleSubmit(request: Request, env: Env): Promise<Response> {
  if (request.method !== 'POST') {
    return jsonError(405, 'method_not_allowed', 'POST required')
  }

  let body: SubmitBody
  try {
    body = await request.json() as SubmitBody
  } catch {
    return jsonError(400, 'validation_failed', 'invalid JSON')
  }

  if (!body.token) return jsonError(400, 'validation_failed', 'token required')
  if (!body.uuid_hash || body.uuid_hash.length !== 64) return jsonError(400, 'validation_failed', 'uuid_hash must be 64 hex chars')
  if (!body.url) return jsonError(400, 'validation_failed', 'url required')

  // ad_type は v3.0 build 15 以降のクライアントから送られる任意フィールド。
  // 旧クライアント (build 14 以前) は ad_type を送らないので NULL を許容。
  // 送ってきた場合は AD_TYPES 列に存在する値であることを厳格に検証。
  let adType: AdType | null = null
  if (body.ad_type !== undefined && body.ad_type !== null && body.ad_type !== '') {
    if (!isAdType(body.ad_type)) {
      return jsonError(400, 'validation_failed', `ad_type must be one of the documented values`)
    }
    adType = body.ad_type
  }

  try {
    const payload = await verifyToken(body.token, env.HMAC_KEY)
    if (payload.scope !== 'submit') return jsonError(401, 'unauthorized', 'wrong scope')
    // ★ IDOR防止: token は特定 uuid_hash に紐付き、別 uuid_hash での代理使用不可
    if (payload.subject !== body.uuid_hash) return jsonError(401, 'unauthorized', 'token uuid_hash mismatch')
  } catch {
    return jsonError(401, 'unauthorized', 'invalid or expired token')
  }

  const now = Math.floor(Date.now() / 1000)
  const uuidHash = body.uuid_hash

  const urlCheck = validateURL(body.url)
  if (!urlCheck.ok) {
    await insertAbuseLog(env.DB, uuidHash, 'uuid', 'invalid_url', body.url, now)
    return jsonError(400, 'validation_failed', urlCheck.reason!)
  }

  const parsedURL = new URL(body.url)
  const domain = parsedURL.host
  // D-lite: 保護ドメインでも報告は正常に受け付ける。
  // 報告は「ブロック対象の指定」ではなく「広告が消えなかったページ」の改善用データなので、
  // yahoo.co.jp 等を送るのは正常な操作。自動でブロックルールに昇格させないのは L3 の責務
  // （critical → kureho_queue）。abuse_log にも記録しない（誤操作ではないため）。

  const memoCheck = validateMemo(body.memo)
  if (!memoCheck.ok) {
    await insertAbuseLog(env.DB, uuidHash, 'uuid', 'spam_memo', body.url, now)
    return jsonError(400, 'validation_failed', memoCheck.reason!)
  }

  const { redacted: redactedMemo, didRedact } = redactPII(body.memo ?? '')

  const ipPlain = request.headers.get('CF-Connecting-IP') ?? 'unknown'
  const ipHash = await sha256Hex(ipPlain + ':' + env.SERVER_SALT)

  const rl = await checkRateLimit(env.DB, { uuidHash, ipHash, now })
  if (!rl.allowed) {
    // rate_limit reason は ban-engine が集計する対象。identifier_type は
    // ip_15min_limit のみ 'ip'、それ以外は 'uuid'。
    const isIpScope = rl.reason === 'ip_15min_limit'
    await insertAbuseLog(
      env.DB,
      isIpScope ? ipHash : uuidHash,
      isIpScope ? 'ip' : 'uuid',
      'rate_limit',
      body.url,
      now,
    )
    if (rl.reason === 'banned') return jsonError(403, 'banned', 'temporarily banned')
    const retryAfter =
      rl.reason === 'uuid_daily_limit' ? 86400 :
      rl.reason === 'uuid_monthly_limit' ? 30 * 86400 : 900
    return jsonErrorWithRetry(429, 'rate_limit_exceeded', rl.reason ?? 'unknown', retryAfter)
  }

  const id = crypto.randomUUID()
  const urlPathHash = await sha256Hex(body.url)

  // D-lite: seen_in の **有無** が新旧クライアントの境界。
  // 旧クライアント（および未知の値を送ってきた場合）は seen_in=NULL として保存し、
  // status を observation_legacy にして 3ユーザー/14日 の自動昇格母集団から隔離する。
  // 日時で切らないのは、D-lite 公開後も旧アプリから報告が届き続けるため。
  const seenIn: SeenIn | null = isSeenIn(body.seen_in) ? body.seen_in : null
  const blockerEnabled = toNullableFlag(body.blocker_enabled)
  // v4.2.0: 未知値/未送信は NULL（= 広告扱い・seen_in と同じ前方互換方針）。
  const reportKind: ReportKind | null = isReportKind(body.report_kind) ? body.report_kind : null
  const status = reportStatus(reportKind, seenIn, blockerEnabled)

  await env.DB.prepare(`
    INSERT INTO reports (
      id, uuid_hash, ip_hash, domain, url, url_path_hash, memo, ad_type, status, created_at,
      seen_in, blocker_enabled, dns_enabled, app_version, app_build, filter_version, report_kind
    )
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).bind(
    id, uuidHash, ipHash, domain, body.url, urlPathHash,
    redactedMemo === '' ? null : redactedMemo, adType, status, now,
    seenIn,
    blockerEnabled,
    toNullableFlag(body.dns_enabled),
    toNullableText(body.app_version),
    toNullableText(body.app_build),
    toNullableText(body.filter_version),
    reportKind,
  ).run()

  if (didRedact) {
    await insertAbuseLog(env.DB, uuidHash, 'uuid', 'pii_redacted', body.url, now)
  }

  return new Response(JSON.stringify({
    id,
    status,
    received_at: now,
    memo_redacted: didRedact,
  }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  })
}

async function insertAbuseLog(
  db: D1Database,
  identifierHash: string,
  identifierType: 'uuid' | 'ip',
  reason: 'rate_limit' | 'spam_memo' | 'invalid_url' | 'critical_domain' | 'pii_redacted',
  url: string | null,
  now: number,
): Promise<void> {
  await db.prepare(`
    INSERT INTO abuse_log (identifier_hash, identifier_type, reason, url, created_at)
    VALUES (?, ?, ?, ?, ?)
  `).bind(identifierHash, identifierType, reason, url, now).run()
}

/**
 * 保存時の status を決める。
 *
 * ★不変条件: **`pending` = 自動改善パイプラインが必ず消費する母集団**。
 * 集約（`scripts/aggregation/aggregate-reports.ts`）は
 * `status='pending' AND seen_in='safari' AND blocker_enabled=1` しか取得せず、
 * 消費した行だけを `aggregated` へ進める。したがって条件を満たさない報告を
 * `pending` で入れると **どのランでも消費されず永久に滞留する**。
 * 集約 SQL は `ORDER BY created_at ASC LIMIT 10000`（古い順）なので、滞留が上限を
 * 超えると取得結果が全て 14 日窓の外の古い行で埋まり、新しい報告が集約されなくなる。
 *
 * どの報告も削除はせず、参考データとして observation 系 status で保持する。
 *
 * - `broken_site`            … v4.2.0 壊れ報告。**どんな診断値でも pending に入れない**
 *                                （壊れているサイトをさらにブロックする方向へ誤学習させない）
 * - `observation_legacy`     … 旧クライアント（seen_in を送ってこない）
 * - `observation_out_of_scope` … Safari 以外で見た広告（Safari 用フィルタでは原理的に消せない）
 *                                / Content Blocker が無効だった or 状態不明（取りこぼしとは言えない）
 */
function reportStatus(reportKind: ReportKind | null, seenIn: SeenIn | null, blockerEnabled: 1 | 0 | null): string {
  if (reportKind === 'site_broken') return 'broken_site'
  if (seenIn === null) return 'observation_legacy'
  if (seenIn !== 'safari') return 'observation_out_of_scope'
  if (blockerEnabled !== 1) return 'observation_out_of_scope'
  return 'pending'
}

/** 診断フラグ: true/false 以外（未送信・型違い）は NULL として扱う。 */
function toNullableFlag(value: unknown): 1 | 0 | null {
  if (value === true) return 1
  if (value === false) return 0
  return null
}

/** 診断テキスト: 空文字・長すぎる値・型違いは NULL として扱う（報告は失敗させない）。 */
function toNullableText(value: unknown, maxLength = 64): string | null {
  if (typeof value !== 'string') return null
  const trimmed = value.trim()
  if (trimmed === '' || trimmed.length > maxLength) return null
  return trimmed
}

function jsonError(status: number, error: string, message: string): Response {
  return new Response(JSON.stringify({ error, message }), {
    status, headers: { 'Content-Type': 'application/json' },
  })
}

function jsonErrorWithRetry(status: number, error: string, message: string, retryAfter: number): Response {
  return new Response(JSON.stringify({ error, message, retry_after: retryAfter }), {
    status, headers: { 'Content-Type': 'application/json' },
  })
}

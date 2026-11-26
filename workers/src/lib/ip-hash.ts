import type { Env } from '../env'
import { sha256Hex } from './hash'

/**
 * IP ハッシュ用の salt は Worker 専用の IP_HASH_SALT を使う（SERVER_SALT とは用途を分ける）。
 *
 * 切替の移行（IP_HASH_SALT 未設定のあいだは従来どおり SERVER_SALT を使う）:
 * - 未設定: ipHash = 従来値のまま、legacyIpHash = null（挙動は変わらない）
 * - 設定済み: ipHash = 'v2:' + 新 salt のハッシュ、legacyIpHash = 従来 salt の値
 *   （停止・短窓の照合だけに使う）
 *
 * 'v2:' 接頭辞は「どの salt 世代の値か」を値自身に持たせるためのもの（列追加・設定値は不要）。
 * 集計側は世代ごとに数え、同じ IP が世代をまたいで別 IP として数えられるのを防ぐ。
 * 接頭辞により、64 桁 16 進だけを受け付ける uuid_hash とは値が衝突しない。
 */
export const IP_HASH_V2_PREFIX = 'v2:'

/** ip_hash の salt 世代（接頭辞なし = 旧 salt = 1）。 */
export function ipHashEpoch(ipHash: string): 1 | 2 {
  return ipHash.startsWith(IP_HASH_V2_PREFIX) ? 2 : 1
}

export interface IpHashes {
  ipHash: string
  legacyIpHash: string | null
}

export async function hashClientIp(env: Env, ip: string): Promise<IpHashes> {
  const legacy = await sha256Hex(ip + ':' + env.SERVER_SALT)
  if (!env.IP_HASH_SALT) return { ipHash: legacy, legacyIpHash: null }
  return { ipHash: IP_HASH_V2_PREFIX + await sha256Hex(ip + ':' + env.IP_HASH_SALT), legacyIpHash: legacy }
}

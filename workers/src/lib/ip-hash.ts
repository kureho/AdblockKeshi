import type { Env } from '../env'
import { sha256Hex } from './hash'

/**
 * IP ハッシュ用の salt は Worker 専用の IP_HASH_SALT を使う（SERVER_SALT とは用途を分ける）。
 *
 * 切替の移行（IP_HASH_SALT 未設定のあいだは従来どおり SERVER_SALT を使う）:
 * - 未設定: ipHash = 従来値のまま、legacyIpHash = null（挙動は変わらない）
 * - 設定済み: ipHash = 新 salt、legacyIpHash = 従来 salt の値（停止・短窓の照合だけに使う）
 */
export interface IpHashes {
  ipHash: string
  legacyIpHash: string | null
}

export async function hashClientIp(env: Env, ip: string): Promise<IpHashes> {
  const legacy = await sha256Hex(ip + ':' + env.SERVER_SALT)
  if (!env.IP_HASH_SALT) return { ipHash: legacy, legacyIpHash: null }
  return { ipHash: await sha256Hex(ip + ':' + env.IP_HASH_SALT), legacyIpHash: legacy }
}

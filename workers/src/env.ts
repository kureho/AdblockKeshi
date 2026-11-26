/**
 * Cloudflare Workers env type for AdblockKeshi v3.0.
 * Bindings declared in wrangler.toml; secrets set via `wrangler secret put`.
 */
export interface Env {
  /** D1 binding (database adblockkeshi-reports, APAC region) */
  DB: D1Database

  /** HMAC ephemeral token signing key (5min TTL). secret. */
  HMAC_KEY: string

  /** Salt for SHA-256(uuid + salt). Shipped clients read it from /token, so keep its value stable. secret. */
  SERVER_SALT: string

  /**
   * Salt for SHA-256(ip + salt). Worker-only. secret.
   * Optional during rollout: when unset, the legacy SERVER_SALT is used (see lib/ip-hash.ts).
   */
  IP_HASH_SALT?: string

  /** Cloudflare Turnstile server-side secret. secret. */
  TURNSTILE_SECRET: string

  /** GitHub PAT for triggering monthly/weekly workflows. secret. */
  GH_DISPATCH_TOKEN: string
}

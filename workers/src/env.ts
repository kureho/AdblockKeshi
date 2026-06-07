/**
 * Cloudflare Workers env type for AdblockKeshi v3.0.
 * Bindings declared in wrangler.toml; secrets set via `wrangler secret put`.
 */
export interface Env {
  /** D1 binding (database adblockkeshi-reports, APAC region) */
  DB: D1Database

  /** HMAC ephemeral token signing key (5min TTL). secret. */
  HMAC_KEY: string

  /** Salt for SHA-256(uuid + salt) and SHA-256(ip + salt) hashes. secret. */
  SERVER_SALT: string

  /** Cloudflare Turnstile server-side secret. secret. */
  TURNSTILE_SECRET: string

  /** GitHub PAT for triggering monthly/weekly workflows. secret. */
  GH_DISPATCH_TOKEN: string
}

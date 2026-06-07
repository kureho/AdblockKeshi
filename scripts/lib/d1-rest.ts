// Shared D1 REST API client for scripts/ runners.
// Avoids loading wrangler CLI inside scripts (lighter, faster, easier to test).

export interface D1Env {
  CF_API_TOKEN: string
  CF_ACCOUNT_ID: string
  CF_DATABASE_ID: string
}

interface D1QueryResponse {
  success: boolean
  errors?: Array<{ message: string }>
  result?: Array<{ results?: any[]; meta?: any; success?: boolean }>
}

export async function d1Query(
  env: D1Env,
  fetchFn: typeof fetch,
  sql: string,
  params: any[] = []
): Promise<any[]> {
  const url = `https://api.cloudflare.com/client/v4/accounts/${env.CF_ACCOUNT_ID}/d1/database/${env.CF_DATABASE_ID}/query`
  const res = await fetchFn(url, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${env.CF_API_TOKEN}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ sql, params }),
  })
  const body = (await res.json()) as D1QueryResponse
  if (!body.success) {
    const msg =
      body.errors?.map((e) => e.message).join('; ') ??
      `HTTP ${res.status} ${res.statusText}`
    throw new Error(`D1 query failed: ${msg}`)
  }
  return body.result?.[0]?.results ?? []
}

export function requireEnv(name: string): string {
  const v = process.env[name]
  if (!v) {
    console.error(`missing env var: ${name}`)
    process.exit(2)
  }
  return v
}

export function envFromProcess(): D1Env {
  return {
    CF_API_TOKEN: requireEnv('CF_API_TOKEN'),
    CF_ACCOUNT_ID: requireEnv('CF_ACCOUNT_ID'),
    CF_DATABASE_ID: requireEnv('CF_DATABASE_ID'),
  }
}

/**
 * D1 (SQLite) caps bound parameters at 999 per statement. Use this to chunk
 * an `IN (?, ?, ...)`-style write so it never trips SQLITE_ERROR at runtime.
 */
export const D1_MAX_IN_PARAMS = 90

export async function chunked<T>(
  items: T[],
  size: number,
  fn: (chunk: T[]) => Promise<unknown>
): Promise<void> {
  for (let i = 0; i < items.length; i += size) {
    await fn(items.slice(i, i + size))
  }
}

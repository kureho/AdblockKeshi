import type { Env } from '../env'

/**
 * GET /v1/health — liveness probe.
 * Returns { status: 'ok' } when the Worker is reachable.
 * Note: does not check D1 connectivity (intentionally lightweight to stay
 * under Workers free tier hard cap). Add D1 check via separate endpoint
 * if needed later.
 */
export async function handleHealth(_request: Request, _env: Env): Promise<Response> {
  return new Response(JSON.stringify({ status: 'ok' }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  })
}

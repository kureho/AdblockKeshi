import type { Env } from './env'
import { handleHealth } from './handlers/health'
import { handleToken } from './handlers/token'

export default {
  async fetch(request: Request, env: Env, _ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url)

    if (url.pathname === '/v1/health') {
      if (request.method !== 'GET') {
        return new Response('Method Not Allowed', { status: 405 })
      }
      return handleHealth(request, env)
    }

    if (url.pathname === '/v1/reports/token') {
      return handleToken(request, env)
    }

    return new Response('Not Found', { status: 404 })
  },
}

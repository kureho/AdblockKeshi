import type { Env } from './env'
import { handleHealth } from './handlers/health'

export default {
  async fetch(request: Request, env: Env, _ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url)

    if (url.pathname === '/v1/health') {
      if (request.method !== 'GET') {
        return new Response('Method Not Allowed', { status: 405 })
      }
      return handleHealth(request, env)
    }

    return new Response('Not Found', { status: 404 })
  },
}

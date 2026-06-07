import type { Env } from './env'
import { handleHealth } from './handlers/health'
import { handleToken } from './handlers/token'
import { handleSubmit } from './handlers/submit'
import { handleHistory } from './handlers/history'
import { handleDelete } from './handlers/delete'
import { handleComplaint } from './handlers/complaint'

export default {
  async fetch(request: Request, env: Env, _ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url)

    if (url.pathname === '/v1/health') {
      if (request.method !== 'GET') return new Response('Method Not Allowed', { status: 405 })
      return handleHealth(request, env)
    }
    if (url.pathname === '/v1/reports/token')   return handleToken(request, env)
    if (url.pathname === '/v1/reports/submit')  return handleSubmit(request, env)
    if (url.pathname === '/v1/reports/history') return handleHistory(request, env)
    if (url.pathname === '/v1/reports/delete')  return handleDelete(request, env)
    if (url.pathname === '/v1/reports/complaint') return handleComplaint(request, env)

    return new Response('Not Found', { status: 404 })
  },
}

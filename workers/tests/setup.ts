import { applyD1Migrations, env } from 'cloudflare:test'
import { beforeAll } from 'vitest'

declare module 'cloudflare:test' {
  // eslint-disable-next-line @typescript-eslint/no-empty-interface
  interface ProvidedEnv extends Env {}
}

// グローバル setup: D1 migrations を test 用 in-memory DB に apply
beforeAll(async () => {
  await applyD1Migrations(env.DB, env.TEST_MIGRATIONS)
})

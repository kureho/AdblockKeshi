import { defineWorkersConfig, readD1Migrations } from '@cloudflare/vitest-pool-workers/config'
import path from 'node:path'

export default defineWorkersConfig(async () => {
  const migrationsPath = path.join(__dirname, 'migrations')
  const migrations = await readD1Migrations(migrationsPath)

  return {
    test: {
      setupFiles: ['./tests/setup.ts'],
      poolOptions: {
        workers: {
          wrangler: { configPath: './wrangler.toml' },
          miniflare: {
            bindings: {
              HMAC_KEY: 'test-hmac-key-do-not-use-in-prod',
              SERVER_SALT: 'test-server-salt',
              TURNSTILE_SECRET: '1x0000000000000000000000000000000AA',
              GH_DISPATCH_TOKEN: 'test-gh-token',
              TEST_MIGRATIONS: migrations,
            },
          },
        },
      },
    },
  }
})

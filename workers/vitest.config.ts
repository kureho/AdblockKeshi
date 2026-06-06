import { defineWorkersConfig } from '@cloudflare/vitest-pool-workers/config'

export default defineWorkersConfig({
  test: {
    poolOptions: {
      workers: {
        wrangler: { configPath: './wrangler.toml' },
        miniflare: {
          bindings: {
            HMAC_KEY: 'test-hmac-key-do-not-use-in-prod',
            SERVER_SALT: 'test-server-salt',
            TURNSTILE_SECRET: '1x0000000000000000000000000000000AA',
            GH_DISPATCH_TOKEN: 'test-gh-token',
          },
        },
      },
    },
  },
})

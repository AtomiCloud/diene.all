import { defineConfig, devices } from '@playwright/test';

// Browser journeys run against the REAL standalone server (the same artifact
// the Garden rail boots) — never `next dev` alone (caveat 8's spirit; the
// workerd preview smoke covers the Workers runtime separately).
export default defineConfig({
  testDir: 'tests/e2e',
  fullyParallel: true,
  retries: process.env['CI'] === undefined ? 0 : 1,
  reporter: process.env['CI'] === undefined ? 'list' : [['list'], ['html', { open: 'never' }]],
  use: {
    baseURL: 'http://127.0.0.1:3000',
    trace: 'retain-on-failure',
  },
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],
  webServer: {
    command: 'ATOMI_LANDSCAPE=base HOSTNAME=127.0.0.1 PORT=3000 node .next/standalone/server.js',
    url: 'http://127.0.0.1:3000',
    reuseExistingServer: process.env['CI'] === undefined,
    timeout: 60_000,
  },
});

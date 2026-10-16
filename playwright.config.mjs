import { defineConfig } from '@playwright/test';
export default defineConfig({
  testDir: './tests',
  testMatch: '**/browser.spec.mjs',
  timeout: 180000,
  workers: 1,
  use: { baseURL: 'http://127.0.0.1:4173', headless: true, viewport: { width: 1440, height: 1000 } },
  webServer: { command: 'python3 scripts/serve.py', url: 'http://127.0.0.1:4173', reuseExistingServer: !process.env.CI }
});

import { defineConfig } from '@playwright/test';

const VIEWER_PORT = 4173;
const MARS_HTTP_PORT = 4174;

export default defineConfig({
  testDir: './e2e',
  timeout: 30_000,
  expect: {
    timeout: 5_000,
  },
  projects: [
    {
      name: 'bithub-viewer',
      testMatch: /file-viewer\.spec\.ts/,
      use: {
        baseURL: `http://127.0.0.1:${VIEWER_PORT}`,
        trace: 'on-first-retry',
      },
    },
    {
      name: 'mars-http-ssr',
      testMatch: /mars-http\.spec\.ts/,
      use: {
        baseURL: `http://127.0.0.1:${MARS_HTTP_PORT}`,
        trace: 'on-first-retry',
      },
    },
  ],
  webServer: [
    {
      command: `./bithub . ${VIEWER_PORT}`,
      url: `http://127.0.0.1:${VIEWER_PORT}`,
      reuseExistingServer: !process.env.CI,
      timeout: 120_000,
    },
    {
      command: `moon run src/cmd/main_ssr --target js -- ${MARS_HTTP_PORT}`,
      url: `http://127.0.0.1:${MARS_HTTP_PORT}`,
      reuseExistingServer: !process.env.CI,
      timeout: 120_000,
    },
  ],
});

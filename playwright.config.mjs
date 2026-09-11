import { defineConfig, devices } from '@playwright/test';
import { resolve } from 'node:path';

const baseURL = process.env.LMM_WEB_BASE_URL ?? 'http://127.0.0.1:4173';
const fakeAudioPath = resolve(
  process.env.LMM_FAKE_AUDIO_PATH ?? 'test/browser/fixtures/fake-mic.wav',
);

export default defineConfig({
  testDir: './test/browser',
  timeout: 45_000,
  expect: { timeout: 8_000 },
  fullyParallel: false,
  workers: 1,
  retries: process.env.CI ? 1 : 0,
  outputDir: 'test-results/playwright',
  reporter: [
    ['line'],
    ['html', { outputFolder: 'playwright-report', open: 'never' }],
  ],
  use: {
    baseURL,
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
    acceptDownloads: true,
  },
  projects: [
    {
      name: 'chromium-operator',
      testMatch: /operator\.spec\.mjs/,
      use: {
        ...devices['Desktop Chrome'],
        permissions: ['microphone'],
        launchOptions: {
          args: [
            '--use-fake-device-for-media-stream',
            '--use-fake-ui-for-media-stream',
            `--use-file-for-fake-audio-capture=${fakeAudioPath}`,
            '--mute-audio',
          ],
        },
      },
    },
    {
      name: 'chromium-capability',
      testMatch: /capability\.spec\.mjs/,
      use: { ...devices['Desktop Chrome'] },
    },
    {
      name: 'firefox-capability',
      testMatch: /capability\.spec\.mjs/,
      use: { ...devices['Desktop Firefox'] },
    },
    {
      name: 'webkit-capability',
      testMatch: /capability\.spec\.mjs/,
      use: { ...devices['Desktop Safari'] },
    },
  ],
});

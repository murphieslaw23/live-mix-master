import { test, expect } from '@playwright/test';
import {
  assertNoPageFailures,
  collectPageFailures,
  writeEvidence,
} from './browser_helpers.mjs';

test('records browser audio capability matrix without overclaiming Safari parity', async ({ page, browserName }, testInfo) => {
  const failures = [];
  collectPageFailures(page, failures);

  const response = await page.goto('/', { waitUntil: 'domcontentloaded' });
  expect(response?.ok()).toBe(true);

  const capabilities = await page.evaluate(() => ({
    userAgent: navigator.userAgent,
    secureContext: window.isSecureContext,
    mediaDevices: Boolean(navigator.mediaDevices),
    getUserMedia: typeof navigator.mediaDevices?.getUserMedia === 'function',
    getDisplayMedia: typeof navigator.mediaDevices?.getDisplayMedia === 'function',
    audioContext: typeof globalThis.AudioContext === 'function',
    audioWorkletNode: typeof globalThis.AudioWorkletNode === 'function',
    serviceWorker: 'serviceWorker' in navigator,
    localStorage: typeof globalThis.localStorage !== 'undefined',
  }));

  const evidence = {
    project: testInfo.project.name,
    browserName,
    scope: browserName === 'webkit'
      ? 'Playwright WebKit engine capability probe; this is not native Safari parity evidence.'
      : 'Playwright browser-engine capability probe.',
    ...capabilities,
  };
  const evidencePath = writeEvidence(`capability-${testInfo.project.name}.json`, evidence);
  await testInfo.attach('browser-capability', {
    path: evidencePath,
    contentType: 'application/json',
  });

  expect(capabilities.secureContext).toBe(true);
  expect(capabilities.localStorage).toBe(true);
  assertNoPageFailures(failures);
});

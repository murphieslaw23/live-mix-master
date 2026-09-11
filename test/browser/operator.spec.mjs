import { test, expect } from '@playwright/test';
import { readFileSync } from 'node:fs';
import {
  assertNoPageFailures,
  collectPageFailures,
  enableFlutterAccessibility,
  parseWav,
  readNumericTelemetry,
  writeEvidence,
} from './browser_helpers.mjs';

const sessionSeed = {
  schemaVersion: 1,
  entries: [
    {
      sessionId: 'e2e-session',
      sourceId: 'browser-master',
      cueTimeMilliseconds: 12_000,
      artist: 'Recovered Artist',
      title: 'Recovered Title',
      confidence: 1,
      providerId: null,
      provenance: 'manual',
      createdAt: '2026-09-11T10:00:00.000Z',
      updatedAt: '2026-09-11T10:01:00.000Z',
    },
  ],
};

test('capture, meter, mix, record, recover, persist, and export from the tested artifact', async ({ page }, testInfo) => {
  test.setTimeout(70_000);
  const failures = [];
  collectPageFailures(page, failures);

  await page.goto('/');
  await enableFlutterAccessibility(page);

  const connect = page.getByRole('button', { name: 'CONNECT MIC / USB' });
  await expect(connect).toBeEnabled();
  await connect.click();
  await expect(page.getByText(/CAPTURE ACTIVE —/)).toBeVisible();

  const slider = page.getByRole('slider', { name: 'Channel fader' });
  const mute = page.getByRole('button', { name: 'Mute' });
  const solo = page.getByRole('button', { name: 'Solo' });
  await expect(slider).toBeEnabled();
  await expect(mute).toBeEnabled();
  await expect(solo).toBeEnabled();

  const initialPeak = await expect.poll(
    () => readNumericTelemetry(page, 'Channel peak'),
    { timeout: 10_000 },
  ).toBeGreaterThan(0.01);

  const beforeFader = await slider.getAttribute('aria-valuenow');
  await slider.focus();
  await page.keyboard.press('ArrowLeft');
  await page.keyboard.press('ArrowLeft');
  await expect.poll(() => slider.getAttribute('aria-valuenow')).not.toBe(beforeFader);

  await mute.click();
  await expect.poll(
    () => readNumericTelemetry(page, 'Master peak'),
    { timeout: 8_000 },
  ).toBeLessThan(0.005);
  await mute.click();
  await expect.poll(
    () => readNumericTelemetry(page, 'Master peak'),
    { timeout: 8_000 },
  ).toBeGreaterThan(0.01);

  await solo.click();

  await page.getByRole('button', { name: 'START RECORDING' }).click();
  await expect(page.getByText('RECORDING ACTIVE — POST-MASTER PCM TO WAV')).toBeVisible();
  await page.waitForTimeout(10_500);
  await page.getByRole('button', { name: 'STOP RECORDING' }).click();
  await expect(page.getByText(/WAV FINALIZED —/)).toBeVisible();

  const wavDownloadPromise = page.waitForEvent('download');
  await page.getByRole('button', { name: 'DOWNLOAD WAV' }).click();
  const wavDownload = await wavDownloadPromise;
  const wavPath = testInfo.outputPath('operator-recording.wav');
  await wavDownload.saveAs(wavPath);
  const wav = parseWav(wavPath);
  expect(wav.durationSeconds).toBeGreaterThanOrEqual(10);

  await page.getByRole('button', { name: 'Disconnect source' }).click();
  await expect(
    page.getByText('CAPTURE ENDED / ACCESS REVOKED — RECONNECT REQUIRED'),
  ).toBeVisible();
  await expect(slider).toBeDisabled();

  await connect.click();
  await expect(page.getByText(/CAPTURE ACTIVE —/)).toBeVisible();
  await expect.poll(
    () => readNumericTelemetry(page, 'Channel peak'),
    { timeout: 10_000 },
  ).toBeGreaterThan(0.01);

  await page.evaluate((seed) => {
    localStorage.setItem('lmm.session.active', JSON.stringify(seed));
  }, sessionSeed);
  await page.reload();
  await enableFlutterAccessibility(page);

  await expect(page.getByText('Session tracklist')).toBeVisible();
  await expect(page.getByText('Recovered Artist')).toBeVisible();
  await expect(page.getByText('Recovered Title')).toBeVisible();

  const artist = page.getByRole('textbox', { name: 'Artist' });
  const title = page.getByRole('textbox', { name: 'Title' });
  await artist.fill('Corrected Artist');
  await title.fill('Corrected Title');
  await page.getByRole('button', { name: 'Save correction' }).click();
  await expect(artist).toHaveValue('Corrected Artist');
  await expect(title).toHaveValue('Corrected Title');

  await page.reload();
  await enableFlutterAccessibility(page);
  await expect(page.getByRole('textbox', { name: 'Artist' })).toHaveValue('Corrected Artist');
  await expect(page.getByRole('textbox', { name: 'Title' })).toHaveValue('Corrected Title');

  const jsonDownloadPromise = page.waitForEvent('download');
  await page.getByRole('button', { name: 'Export session JSON' }).click();
  const jsonDownload = await jsonDownloadPromise;
  const jsonPath = testInfo.outputPath('session-export.json');
  await jsonDownload.saveAs(jsonPath);
  const exportedSession = JSON.parse(readFileSync(jsonPath, 'utf8'));
  expect(exportedSession.trackCount).toBe(1);
  expect(exportedSession.entries[0].artist).toBe('Corrected Artist');
  expect(exportedSession.entries[0].title).toBe('Corrected Title');
  expect(exportedSession.entries[0].provenance).toBe('manual');

  const evidencePath = writeEvidence('chromium-operator.json', {
    capture: 'fake microphone via Chromium media switches',
    initialChannelPeak: initialPeak,
    wav,
    reconnect: true,
    sessionRecovery: true,
    sessionCorrectionPersistedAcrossReload: true,
    jsonExportValidated: true,
  });
  await testInfo.attach('chromium-operator-evidence', {
    path: evidencePath,
    contentType: 'application/json',
  });

  assertNoPageFailures(failures);
});

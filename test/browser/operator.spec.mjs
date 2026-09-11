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

async function activateControl(control) {
  await expect(control).toBeEnabled();
  await control.evaluate((element) => element.click());
}

async function activateButton(page, name) {
  const button = page.getByRole('button', { name });
  await activateControl(button);
  return button;
}

async function downloadSessionJson(page, testInfo, fileName) {
  const downloadPromise = page.waitForEvent('download');
  await activateButton(page, 'Export session JSON');
  const download = await downloadPromise;
  const path = testInfo.outputPath(fileName);
  await download.saveAs(path);
  return JSON.parse(readFileSync(path, 'utf8'));
}

test('capture, meter, mix, record, recover, persist, and export from the tested artifact', async ({ page }, testInfo) => {
  test.setTimeout(70_000);
  const failures = [];
  collectPageFailures(page, failures);

  await page.goto('/');
  await enableFlutterAccessibility(page);

  const connect = page.getByRole('button', { name: 'CONNECT MIC / USB' });
  await activateControl(connect);
  await expect(page.getByText(/CAPTURE ACTIVE —/)).toBeVisible();

  const slider = page
    .getByRole('group', { name: /^Channel fader/ })
    .getByRole('slider');
  const mute = page.getByRole('switch', { name: 'Mute' });
  const solo = page.getByRole('switch', { name: 'Solo' });
  await expect(slider).toBeEnabled();
  await expect(mute).toBeEnabled();
  await expect(solo).toBeEnabled();

  await expect.poll(
    () => readNumericTelemetry(page, 'Channel peak'),
    { timeout: 10_000 },
  ).toBeGreaterThan(0.01);
  const initialPeak = await readNumericTelemetry(page, 'Channel peak');

  const beforeFader = await slider.getAttribute('aria-valuenow');
  await slider.focus();
  await page.keyboard.press('ArrowLeft');
  await page.keyboard.press('ArrowLeft');
  await expect.poll(() => slider.getAttribute('aria-valuenow')).not.toBe(beforeFader);

  await activateControl(mute);
  await expect.poll(
    () => readNumericTelemetry(page, 'Master peak'),
    { timeout: 8_000 },
  ).toBeLessThan(0.005);
  await activateControl(mute);
  await expect.poll(
    () => readNumericTelemetry(page, 'Master peak'),
    { timeout: 8_000 },
  ).toBeGreaterThan(0.01);

  await activateControl(solo);

  await activateButton(page, 'START RECORDING');
  await expect(page.getByText('RECORDING ACTIVE — POST-MASTER PCM TO WAV')).toBeVisible();
  await page.waitForTimeout(10_500);
  await activateButton(page, 'STOP RECORDING');
  await expect(page.getByText(/WAV FINALIZED —/)).toBeVisible();

  const wavDownloadPromise = page.waitForEvent('download');
  await activateButton(page, 'DOWNLOAD WAV');
  const wavDownload = await wavDownloadPromise;
  const wavPath = testInfo.outputPath('operator-recording.wav');
  await wavDownload.saveAs(wavPath);
  const wav = parseWav(wavPath);
  expect(wav.durationSeconds).toBeGreaterThanOrEqual(10);

  await activateButton(page, 'Disconnect source');
  await expect(
    page.getByText('CAPTURE ENDED / ACCESS REVOKED — RECONNECT REQUIRED'),
  ).toBeVisible();
  await expect(mute).toBeDisabled();
  await expect(solo).toBeDisabled();
  await expect(
    page.getByRole('group', { name: /^Channel fader/ }).getByRole('slider'),
  ).toHaveCount(0);

  await activateControl(connect);
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
  await expect(page.getByText('SESSION e2e-session — 1 ENTRIES')).toBeVisible();
  const recoveredSession = await downloadSessionJson(
    page,
    testInfo,
    'session-recovered.json',
  );
  expect(recoveredSession.trackCount).toBe(1);
  expect(recoveredSession.entries[0].artist).toBe('Recovered Artist');
  expect(recoveredSession.entries[0].title).toBe('Recovered Title');
  expect(recoveredSession.entries[0].provenance).toBe('manual');

  const artist = page.getByRole('textbox', { name: 'Artist' });
  const title = page.getByRole('textbox', { name: 'Title' });
  await expect(artist).toBeEditable();
  await expect(title).toBeEditable();
  await artist.fill('Corrected Artist');
  await title.fill('Corrected Title');
  await expect(artist).toHaveValue('Corrected Artist');
  await expect(title).toHaveValue('Corrected Title');
  await title.press('Tab');
  await expect(title).not.toBeFocused();
  await activateButton(page, 'Save correction');

  await page.reload();
  await enableFlutterAccessibility(page);
  await expect(page.getByText('SESSION e2e-session — 1 ENTRIES')).toBeVisible();
  const correctedSession = await downloadSessionJson(
    page,
    testInfo,
    'session-corrected.json',
  );
  expect(correctedSession.trackCount).toBe(1);
  expect(correctedSession.entries[0].artist).toBe('Corrected Artist');
  expect(correctedSession.entries[0].title).toBe('Corrected Title');
  expect(correctedSession.entries[0].provenance).toBe('manual');

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

import { expect } from '@playwright/test';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';

export async function enableFlutterAccessibility(page) {
  const appTitle = page.getByText('LIVEMIXMASTER', { exact: true });

  for (let attempt = 0; attempt < 6; attempt += 1) {
    if (await appTitle.isVisible().catch(() => false)) {
      return;
    }

    const placeholder = page.locator('flt-semantics-placeholder');
    if (await placeholder.count()) {
      try {
        await placeholder.click({ timeout: 1_500 });
      } catch {
        try {
          await placeholder.evaluate((node) => node.click());
        } catch {
          // Flutter may replace the placeholder while semantics initializes.
        }
      }
    }

    await page.waitForTimeout(500);
  }

  await expect(appTitle).toBeVisible({ timeout: 8_000 });
}

export function collectPageFailures(page, bucket) {
  page.on('pageerror', (error) => {
    bucket.push(`pageerror: ${error.message}`);
  });
  page.on('console', (message) => {
    if (message.type() === 'error') {
      const text = message.text();
      if (!text.includes('favicon.ico')) {
        bucket.push(`console.error: ${text}`);
      }
    }
  });
}

export function assertNoPageFailures(failures) {
  expect(failures, failures.join('\n')).toEqual([]);
}

export function parseWav(path) {
  const bytes = readFileSync(path);
  expect(bytes.subarray(0, 4).toString('ascii')).toBe('RIFF');
  expect(bytes.subarray(8, 12).toString('ascii')).toBe('WAVE');

  let offset = 12;
  let format;
  let dataBytes;
  while (offset + 8 <= bytes.length) {
    const id = bytes.subarray(offset, offset + 4).toString('ascii');
    const size = bytes.readUInt32LE(offset + 4);
    const payload = offset + 8;
    if (id === 'fmt ') {
      format = {
        audioFormat: bytes.readUInt16LE(payload),
        channels: bytes.readUInt16LE(payload + 2),
        sampleRate: bytes.readUInt32LE(payload + 4),
        bitsPerSample: bytes.readUInt16LE(payload + 14),
      };
    } else if (id === 'data') {
      dataBytes = size;
      break;
    }
    offset = payload + size + (size % 2);
  }

  expect(format).toBeTruthy();
  expect(format.audioFormat).toBe(1);
  expect(dataBytes).toBeGreaterThan(0);
  const bytesPerFrame = format.channels * (format.bitsPerSample / 8);
  const durationSeconds = dataBytes / (format.sampleRate * bytesPerFrame);
  return { ...format, dataBytes, durationSeconds, fileBytes: bytes.length };
}

export function writeEvidence(relativePath, value) {
  const path = resolve('test-results/evidence', relativePath);
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, `${JSON.stringify(value, null, 2)}\n`);
  return path;
}

export async function readNumericTelemetry(page, label) {
  const row = page.getByText(label, { exact: true });
  await expect(row).toBeVisible();
  const valueText = await row.evaluate((element) => {
    const semantics = element.closest('flt-semantics');
    let sibling = semantics?.nextElementSibling ?? null;
    for (let index = 0; sibling && index < 3; index += 1) {
      const text = sibling.textContent?.trim() ?? '';
      if (/^-?\d+(?:\.\d+)?$/.test(text)) {
        return text;
      }
      sibling = sibling.nextElementSibling;
    }
    return null;
  });
  if (valueText == null) {
    throw new Error(`No numeric telemetry semantics sibling found for ${label}`);
  }
  return Number(valueText);
}

import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';
import {pathToFileURL} from 'node:url';

import {
  FIXTURE_CHANNELS,
  FIXTURE_DURATION_SECONDS,
  FIXTURE_SAMPLE_RATE,
  createChromaprintFixturePcm16,
  writePcm16Wav,
} from './fixtures/chromaprint-fixture-generator.mjs';

const modulePath = path.join(
  process.cwd(),
  'build',
  'chromaprint-wasm',
  'livemixmaster-chromaprint.mjs',
);
const wasmPath = path.join(
  process.cwd(),
  'build',
  'chromaprint-wasm',
  'livemixmaster-chromaprint-core.wasm',
);
const fixturePath = path.join(
  process.cwd(),
  'build',
  'chromaprint-fixture',
  'reference.wav',
);

async function loadChromaprintApi() {
  try {
    await fs.access(modulePath);
    await fs.access(wasmPath);
  } catch (_) {
    assert.fail(
      'Chromaprint Wasm build is missing; run tool/build_chromaprint_wasm.sh before the parity contract',
    );
  }

  const imported = await import(`${pathToFileURL(modulePath).href}?test=${Date.now()}`);
  assert.equal(typeof imported.createChromaprint, 'function');
  return imported.createChromaprint({
    wasmUrl: pathToFileURL(wasmPath).href,
  });
}

function referenceFingerprint(wavPath) {
  const fpcalc = process.env.FPCALC_BIN;
  assert.ok(fpcalc, 'FPCALC_BIN must point to official fpcalc v1.6.1');

  const result = spawnSync(
    fpcalc,
    ['-json', '-length', String(FIXTURE_DURATION_SECONDS), wavPath],
    {encoding: 'utf8'},
  );
  assert.equal(
    result.status,
    0,
    `fpcalc failed: ${result.stderr || result.stdout}`,
  );

  const parsed = JSON.parse(result.stdout.trim());
  assert.equal(typeof parsed.fingerprint, 'string');
  assert.ok(parsed.fingerprint.length > 0);
  return parsed.fingerprint;
}

test('Chromaprint Wasm matches official fpcalc 1.6.1 for identical deterministic PCM', async () => {
  const pcm = createChromaprintFixturePcm16();
  await writePcm16Wav(fixturePath, pcm);

  const engine = await loadChromaprintApi();
  assert.equal(engine.version(), '1.6.1');

  const actual = engine.fingerprintPcm16(
    pcm,
    FIXTURE_SAMPLE_RATE,
    FIXTURE_CHANNELS,
  );
  const expected = referenceFingerprint(fixturePath);

  assert.equal(actual, expected);
  assert.match(actual, /^[A-Za-z0-9_-]+$/);
});

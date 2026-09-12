import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import test from 'node:test';

const ciUrl = new URL('../.github/workflows/ci.yml', import.meta.url);
const operatorUrl = new URL('./browser/operator.spec.mjs', import.meta.url);

function requireOrdered(source, before, after, message) {
  const beforeIndex = source.indexOf(before);
  const afterIndex = source.indexOf(after);
  assert.notEqual(beforeIndex, -1, `missing workflow marker: ${before}`);
  assert.notEqual(afterIndex, -1, `missing workflow marker: ${after}`);
  assert.ok(beforeIndex < afterIndex, message);
}

test('release compile builds and verifies canonical DSP Wasm before use and packaging', async () => {
  const ci = await fs.readFile(ciUrl, 'utf8');

  requireOrdered(
    ci,
    '- name: Build canonical DSP Wasm',
    '- name: Verify AudioWorklet processor contract',
    'canonical DSP Wasm must exist before direct worklet tests load it',
  );
  requireOrdered(
    ci,
    '- name: Verify canonical DSP Wasm build contract',
    '- name: Build Flutter Web release artifact',
    'Wasm ABI/parity must be green before Flutter packaging',
  );
  assert.match(
    ci,
    /emscripten\/emsdk:6\.0\.9 bash tool\/build_dsp_wasm\.sh/,
    'release build must use the pinned Emscripten toolchain',
  );
  assert.match(
    ci,
    /cmp -s web\/audio\/livemixmaster-dsp\.wasm build\/web\/audio\/livemixmaster-dsp\.wasm/,
    'packaged DSP bytes must be byte-identical to the tested generated source asset',
  );
  assert.match(
    ci,
    /sha256sum build\/web\/audio\/livemixmaster-dsp\.wasm > test-results-dsp-wasm\.sha256/,
    'release compile must persist non-secret DSP checksum evidence',
  );
});

test('exact-artifact operator E2E proves packaged DSP Wasm was fetched successfully', async () => {
  const operator = await fs.readFile(operatorUrl, 'utf8');

  assert.match(operator, /const dspResponses = \[\];/);
  assert.match(operator, /page\.on\(['"]response['"]/);
  assert.match(operator, /livemixmaster-dsp\.wasm/);
  assert.match(
    operator,
    /dspResponses[\s\S]*status[\s\S]*200/,
    'operator flow must assert at least one successful packaged DSP response',
  );
});

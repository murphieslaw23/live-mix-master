import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import test from 'node:test';

const wasmUrl = new URL('../web/audio/livemixmaster-dsp.wasm', import.meta.url);

test('RED prerequisite: generated DSP Wasm is absent before build implementation', async () => {
  await assert.rejects(
    fs.access(wasmUrl),
    (error) => error?.code === 'ENOENT',
    'generated DSP Wasm should not exist before build implementation',
  );
});

test('built DSP Wasm exposes the ABI v1 surface', async () => {
  const bytes = await fs.readFile(wasmUrl);
  const module = await WebAssembly.compile(bytes);
  const exports = WebAssembly.Module.exports(module).map(({ name }) => name);

  for (const name of [
    'memory',
    'lmm_dsp_abi_version',
    'lmm_dsp_max_channels',
    'lmm_dsp_process_stereo',
  ]) {
    assert.ok(exports.includes(name), `missing Wasm export: ${name}`);
  }
});

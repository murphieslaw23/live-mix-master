import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import test from 'node:test';

const wasmUrl = new URL('../web/audio/livemixmaster-dsp.wasm', import.meta.url);

test('built DSP Wasm exposes the ABI v1 surface without filesystem/network imports', async () => {
  const bytes = await fs.readFile(wasmUrl);
  const module = await WebAssembly.compile(bytes);
  const exports = WebAssembly.Module.exports(module).map(({ name }) => name);

  for (const name of [
    'memory',
    'lmm_dsp_abi_version',
    'lmm_dsp_max_channels',
    'lmm_dsp_process_stereo',
    'malloc',
    'free',
  ]) {
    assert.ok(exports.includes(name), `missing Wasm export: ${name}`);
  }

  for (const imported of WebAssembly.Module.imports(module)) {
    const signature = `${imported.module}.${imported.name}`;
    for (const forbidden of ['fd_', 'path_', 'sock_', 'fetch', 'filesystem']) {
      assert.equal(signature.includes(forbidden), false, `forbidden Wasm import: ${signature}`);
    }
  }
});

test('DSP Wasm memory cannot grow after initialization', async () => {
  const bytes = await fs.readFile(wasmUrl);
  const { instance } = await WebAssembly.instantiate(bytes, {});
  const memory = instance.exports.memory;
  assert.ok(memory instanceof WebAssembly.Memory, 'memory export is required');
  assert.throws(() => memory.grow(1), /maximum memory size|Unable to grow|could not grow/i);
});

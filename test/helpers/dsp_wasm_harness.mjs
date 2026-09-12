import assert from 'node:assert/strict';
import fs from 'node:fs/promises';

const defaultWasmUrl = new URL('../../web/audio/livemixmaster-dsp.wasm', import.meta.url);
const CONFIG_SIZE = 20;
const METER_SIZE = 24;
const MASTER_SIZE = 12;

function requireExport(exports, name) {
  const value = exports[name];
  assert.ok(value, `missing Wasm export: ${name}`);
  return value;
}

export async function createDspWasmHarness({ wasmUrl = defaultWasmUrl } = {}) {
  const bytes = await fs.readFile(wasmUrl);
  const module = await WebAssembly.compile(bytes);
  const instance = await WebAssembly.instantiate(module, {});
  const exports = instance.exports;
  const memory = requireExport(exports, 'memory');
  const malloc = requireExport(exports, 'malloc');
  const free = requireExport(exports, 'free');
  const abiVersion = requireExport(exports, 'lmm_dsp_abi_version');
  const maxChannels = requireExport(exports, 'lmm_dsp_max_channels');
  const processStereo = requireExport(exports, 'lmm_dsp_process_stereo');

  assert.equal(abiVersion(), 1, 'DSP ABI version must be 1');
  assert.equal(maxChannels(), 8, 'DSP ABI max channels must be 8');

  function allocate(byteLength) {
    const pointer = malloc(byteLength);
    assert.notEqual(pointer, 0, `Wasm allocation failed for ${byteLength} bytes`);
    return pointer;
  }

  function runVector(vector) {
    const channelCount = vector.channels.length;
    assert.ok(channelCount <= 8, 'fixture exceeds ABI channel limit');
    const frames = vector.expected.length / 2;
    assert.equal(Number.isInteger(frames), true, 'expected output must be interleaved stereo');

    const allocations = [];
    const alloc = (bytes) => {
      const pointer = allocate(bytes);
      allocations.push(pointer);
      return pointer;
    };

    try {
      const configPtr = alloc(Math.max(1, channelCount * CONFIG_SIZE));
      const inputPtrTable = alloc(Math.max(4, channelCount * 4));
      const outputPtr = alloc(Math.max(4, frames * 2 * 4));
      const metersPtr = alloc(Math.max(METER_SIZE, channelCount * METER_SIZE));
      const masterPtr = alloc(MASTER_SIZE);
      const inputPointers = [];

      for (const channel of vector.channels) {
        const pointer = alloc(Math.max(4, channel.interleaved.length * 4));
        inputPointers.push(pointer);
      }

      const view = new DataView(memory.buffer);
      for (let index = 0; index < channelCount; index += 1) {
        const channel = vector.channels[index];
        const configOffset = configPtr + index * CONFIG_SIZE;
        view.setUint32(configOffset + 0, 1, true);
        view.setUint32(configOffset + 4, channel.muted ? 1 : 0, true);
        view.setUint32(configOffset + 8, channel.solo ? 1 : 0, true);
        view.setFloat32(configOffset + 12, channel.linearTrim, true);
        view.setFloat32(configOffset + 16, channel.fader, true);

        const inputPointer = inputPointers[index];
        new Float32Array(memory.buffer, inputPointer, channel.interleaved.length).set(channel.interleaved);
        view.setUint32(inputPtrTable + index * 4, inputPointer, true);
      }

      const status = processStereo(
        configPtr,
        inputPtrTable,
        channelCount,
        frames,
        vector.masterGainLinear,
        outputPtr,
        metersPtr,
        masterPtr,
      );
      assert.equal(status, 0, `${vector.name}: DSP process status ${status}`);

      const output = Array.from(new Float32Array(memory.buffer, outputPtr, frames * 2));
      const meters = vector.channels.map((channel, index) => {
        const offset = metersPtr + index * METER_SIZE;
        return {
          id: channel.id,
          processed: view.getUint32(offset + 0, true) !== 0,
          peakLeft: view.getFloat32(offset + 4, true),
          peakRight: view.getFloat32(offset + 8, true),
          rmsLeft: view.getFloat32(offset + 12, true),
          rmsRight: view.getFloat32(offset + 16, true),
          clipping: view.getUint32(offset + 20, true) !== 0,
        };
      });

      return {
        output,
        meters,
        masterPeakLeft: view.getFloat32(masterPtr + 0, true),
        masterPeakRight: view.getFloat32(masterPtr + 4, true),
        limiterActive: view.getUint32(masterPtr + 8, true) !== 0,
      };
    } finally {
      for (let index = allocations.length - 1; index >= 0; index -= 1) {
        free(allocations[index]);
      }
    }
  }

  return Object.freeze({
    module,
    instance,
    memory,
    abiVersion: 1,
    maxChannels: 8,
    runVector,
  });
}

export async function runWasmVector(vector) {
  const harness = await createDspWasmHarness();
  return harness.runVector(vector);
}

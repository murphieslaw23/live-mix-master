import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import test from 'node:test';

class MockPort {
  constructor() {
    this.messages = [];
    this.onmessage = null;
  }

  postMessage(message) {
    this.messages.push(message);
  }

  dispatch(message) {
    this.onmessage?.({ data: message });
  }
}

let Processor;

globalThis.sampleRate = 48000;
globalThis.AudioWorkletProcessor = class {
  constructor() {
    this.port = new MockPort();
  }
};
globalThis.registerProcessor = (_name, ctor) => {
  Processor = ctor;
};

const workletUrl = new URL('../web/audio/livemixmaster-worklet.js', import.meta.url);
const dspWasmUrl = new URL('../web/audio/livemixmaster-dsp.wasm', import.meta.url);
const gatewayUrl = new URL(
  '../lib/audio/web/browser_audio_worklet_gateway_web.dart',
  import.meta.url,
);

await import(workletUrl);

const dspBytes = await fs.readFile(dspWasmUrl);
const exactArrayBuffer = dspBytes.buffer.slice(
  dspBytes.byteOffset,
  dspBytes.byteOffset + dspBytes.byteLength,
);

test('AudioWorklet initializes canonical DSP from clone-safe raw Wasm bytes', () => {
  const processor = new Processor();

  processor.port.dispatch({
    type: 'dspInit',
    abiVersion: 1,
    wasmBytes: exactArrayBuffer,
  });

  assert.equal(
    processor.port.messages.filter((message) => message.type === 'dspReady').length,
    1,
  );
  assert.equal(
    processor.port.messages.some((message) => message.type === 'dspError'),
    false,
  );
});

test('browser gateway never posts a compiled WebAssembly.Module across the AudioWorklet port', async () => {
  const gateway = await fs.readFile(gatewayUrl, 'utf8');
  const worklet = await fs.readFile(workletUrl, 'utf8');

  assert.doesNotMatch(gateway, /WebAssembly\.compile/);
  assert.doesNotMatch(gateway, /initMessage\['module'\]/);
  assert.match(gateway, /initMessage\['wasmBytes'\]/);
  assert.match(worklet, /new WebAssembly\.Module\(message\.wasmBytes\)/);
});

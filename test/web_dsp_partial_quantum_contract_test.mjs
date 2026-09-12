import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import test from 'node:test';

class MockPort {
  constructor() {
    this.messages = [];
    this.onmessage = null;
  }

  postMessage(message) {
    this.messages.push(structuredClone(message));
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
const wasmUrl = new URL('../web/audio/livemixmaster-dsp.wasm', import.meta.url);
await import(workletUrl);
const canonicalDspModule = await WebAssembly.compile(await fs.readFile(wasmUrl));

function stereoOutput(frames) {
  return [[new Float32Array(frames), new Float32Array(frames)]];
}

function initialize(processor) {
  processor.port.dispatch({ type: 'dspInit', abiVersion: 1, module: canonicalDspModule });
  assert.ok(processor.port.messages.some((message) => message.type === 'dspReady'));
  processor.port.dispatch({
    type: 'configure',
    telemetryEvery: 1000,
    channels: [
      { id: 'input-1', linearTrim: 1, fader: 1, muted: false, solo: false },
    ],
  });
}

test('partial render quantum publishes exact-length reusable PCM views', () => {
  const processor = new Processor();
  initialize(processor);
  processor.port.dispatch({ type: 'analysis', enabled: true, maxOutstandingPcm: 1 });
  processor.port.dispatch({ type: 'recording', enabled: true, maxOutstandingPcm: 1 });

  const output = stereoOutput(1);
  assert.equal(
    processor.process(
      [[Float32Array.of(0.4), Float32Array.of(-0.4)]],
      output,
      {},
    ),
    true,
  );

  const analysis = processor.port.messages.find((message) => message.type === 'analysisPcm');
  const recording = processor.port.messages.find((message) => message.type === 'pcm');
  assert.ok(analysis);
  assert.ok(recording);

  for (const message of [analysis, recording]) {
    assert.equal(message.frames, 1);
    assert.equal(message.samples.length, 2, 'worker envelope must contain only declared stereo frames');
    assert.deepEqual(
      Array.from(message.samples),
      [output[0][0][0], output[0][1][0]],
      'worker envelope must carry the canonical post-master frame only',
    );
  }
});

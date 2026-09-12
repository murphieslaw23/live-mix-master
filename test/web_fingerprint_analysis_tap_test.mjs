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

await import(new URL('../web/audio/livemixmaster-worklet.js', import.meta.url));
const validDspModule = await WebAssembly.compile(
  await fs.readFile(new URL('../web/audio/livemixmaster-dsp.wasm', import.meta.url)),
);

function initializeDsp(processor) {
  processor.port.dispatch({ type: 'dspInit', abiVersion: 1, module: validDspModule });
  assert.ok(
    processor.port.messages.some((message) => message.type === 'dspReady'),
    'fingerprint tap test requires canonical DSP readiness',
  );
}

function stereoOutput(frames) {
  return [[new Float32Array(frames), new Float32Array(frames)]];
}

function channel(left, right = left) {
  return [Float32Array.from(left), Float32Array.from(right)];
}

test('fingerprint analysis tap is bounded independently from recording handoff', () => {
  const processor = new Processor();
  initializeDsp(processor);
  processor.port.dispatch({
    type: 'configure',
    telemetryEvery: 1000,
    channels: [{ id: 'a', linearTrim: 1, fader: 1, muted: false, solo: false }],
  });
  processor.port.dispatch({ type: 'analysis', enabled: true, maxOutstandingPcm: 1 });

  processor.process([channel([2], [-2])], stereoOutput(1), {});

  let analysis = processor.port.messages.filter((message) => message.type === 'analysisPcm');
  assert.equal(analysis.length, 1, 'analysis must run while recording is disabled');
  assert.equal(processor.port.messages.filter((message) => message.type === 'pcm').length, 0);
  assert.deepEqual(
    Array.from(analysis[0].samples).slice(0, 2),
    Array.from(Float32Array.of(0.98, -0.98)),
    'analysis must receive canonical post-master PCM',
  );
  assert.equal(analysis[0].frames, 1);
  assert.equal(analysis[0].sampleRate, 48000);
  assert.equal(analysis[0].channels, 2);

  processor.process([channel([0.25])], stereoOutput(1), {});
  analysis = processor.port.messages.filter((message) => message.type === 'analysisPcm');
  assert.equal(analysis.length, 1, 'analysis backpressure must skip rather than queue');
  assert.equal(processor.port.messages.filter((message) => message.type === 'recordingError').length, 0);

  processor.port.dispatch({ type: 'analysisAck' });
  processor.port.dispatch({ type: 'recording', enabled: true, maxOutstandingPcm: 1 });
  processor.process([channel([0.4])], stereoOutput(1), {});

  assert.equal(processor.port.messages.filter((message) => message.type === 'analysisPcm').length, 2);
  assert.equal(processor.port.messages.filter((message) => message.type === 'pcm').length, 1);

  processor.port.dispatch({ type: 'analysisAck' });
  processor.process([channel([0.5])], stereoOutput(1), {});

  assert.equal(
    processor.port.messages.filter((message) => message.type === 'analysisPcm').length,
    3,
    'analysis ACK must not depend on recorder ACK state',
  );
  const recordingFailures = processor.port.messages.filter((message) => message.type === 'recordingError');
  assert.equal(recordingFailures.length, 1, 'recorder backpressure remains independently fail-closed');
  assert.equal(recordingFailures[0].reason, 'BACKPRESSURE');
});

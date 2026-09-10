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

let processorName;
let Processor;

globalThis.sampleRate = 48000;
globalThis.AudioWorkletProcessor = class {
  constructor() {
    this.port = new MockPort();
  }
};
globalThis.registerProcessor = (name, ctor) => {
  processorName = name;
  Processor = ctor;
};

const moduleUrl = new URL('../web/audio/livemixmaster-worklet.js', import.meta.url);
await import(moduleUrl);

function stereoOutput(frames) {
  return [[new Float32Array(frames), new Float32Array(frames)]];
}

function channel(left, right = left) {
  return [Float32Array.from(left), Float32Array.from(right)];
}

test('registers the LiveMixMaster AudioWorklet processor', () => {
  assert.equal(processorName, 'livemixmaster-dsp');
  assert.equal(typeof Processor, 'function');
});

test('executes native-parity fader, summing and limiter semantics in the worklet', () => {
  const processor = new Processor();
  processor.port.dispatch({
    type: 'configure',
    masterGainLinear: 1,
    telemetryEvery: 1,
    channels: [
      { id: 'a', linearTrim: 1, fader: 0.5, muted: false, solo: false },
      { id: 'b', linearTrim: 1, fader: 1, muted: true, solo: false },
    ],
  });

  const output = stereoOutput(2);
  const keepAlive = processor.process(
    [channel([1, 0.5], [-1, -0.5]), channel([1, 1])],
    output,
    {},
  );

  assert.equal(keepAlive, true);
  assert.deepEqual(Array.from(output[0][0]), [0.25, 0.125]);
  assert.deepEqual(Array.from(output[0][1]), [-0.25, -0.125]);

  processor.port.dispatch({
    type: 'configure',
    masterGainLinear: 1,
    telemetryEvery: 1,
    channels: [
      { id: 'hot', linearTrim: 1, fader: 1, muted: false, solo: false },
    ],
  });
  const hotOutput = stereoOutput(1);
  processor.process([channel([2], [-2])], hotOutput, {});
  assert.ok(Math.abs(hotOutput[0][0][0] - 0.98) < 1e-6);
  assert.ok(Math.abs(hotOutput[0][1][0] + 0.98) < 1e-6);
});

test('allows at most one unacknowledged telemetry message', () => {
  const processor = new Processor();
  processor.port.dispatch({
    type: 'configure',
    telemetryEvery: 1,
    channels: [{ id: 'a', linearTrim: 1, fader: 1, muted: false, solo: false }],
  });

  for (let i = 0; i < 8; i += 1) {
    processor.process([channel([0.25])], stereoOutput(1), {});
  }
  assert.equal(processor.port.messages.filter((m) => m.type === 'telemetry').length, 1);

  processor.port.dispatch({ type: 'telemetryAck' });
  processor.process([channel([0.25])], stereoOutput(1), {});
  assert.equal(processor.port.messages.filter((m) => m.type === 'telemetry').length, 2);
});

test('recording PCM handoff is bounded and fails closed on backpressure', () => {
  const processor = new Processor();
  processor.port.dispatch({
    type: 'configure',
    telemetryEvery: 1000,
    channels: [{ id: 'a', linearTrim: 1, fader: 1, muted: false, solo: false }],
  });
  processor.port.dispatch({ type: 'recording', enabled: true, maxOutstandingPcm: 2 });

  processor.process([channel([0.1])], stereoOutput(1), {});
  processor.process([channel([0.2])], stereoOutput(1), {});
  processor.process([channel([0.3])], stereoOutput(1), {});
  processor.process([channel([0.4])], stereoOutput(1), {});

  const pcm = processor.port.messages.filter((m) => m.type === 'pcm');
  const failures = processor.port.messages.filter((m) => m.type === 'recordingError');
  assert.equal(pcm.length, 2);
  assert.equal(failures.length, 1);
  assert.equal(failures[0].reason, 'BACKPRESSURE');
  assert.equal(failures[0].droppedFrames, 1);
});

test('worklet source contains no network or storage APIs', async () => {
  const source = await fs.readFile(moduleUrl, 'utf8');
  for (const forbidden of ['fetch(', 'XMLHttpRequest', 'localStorage', 'sessionStorage', 'indexedDB']) {
    assert.equal(source.includes(forbidden), false, `forbidden worklet API: ${forbidden}`);
  }
});

import assert from 'node:assert/strict';
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

await import(new URL('../web/audio/livemixmaster-worklet.js', import.meta.url));

function stereoOutput(frames) {
  return [[new Float32Array(frames), new Float32Array(frames)]];
}

function channel(left, right = left) {
  return [Float32Array.from(left), Float32Array.from(right)];
}

test('configure emits the stereo telemetry schema consumed by Dart', () => {
  const processor = new Processor();
  processor.port.dispatch({
    type: 'configure',
    masterGainLinear: 0.5,
    telemetryEvery: 1,
    channels: [
      { id: 'mic-1', linearTrim: 1, fader: 0.5, muted: false, solo: true },
    ],
  });

  processor.process([channel([1, -0.5], [0.5, -1])], stereoOutput(2), {});

  const telemetry = processor.port.messages.find((message) => message.type === 'telemetry');
  assert.ok(telemetry);
  assert.equal(telemetry.channelMeters.length, 1);
  assert.deepEqual(Object.keys(telemetry.channelMeters[0]).sort(), [
    'channelId',
    'clipping',
    'peakLeft',
    'peakRight',
    'rmsLeft',
    'rmsRight',
  ]);
  assert.equal(telemetry.channelMeters[0].channelId, 'mic-1');
  assert.equal(typeof telemetry.channelMeters[0].peakLeft, 'number');
  assert.equal(typeof telemetry.channelMeters[0].peakRight, 'number');
  assert.equal(typeof telemetry.channelMeters[0].rmsLeft, 'number');
  assert.equal(typeof telemetry.channelMeters[0].rmsRight, 'number');
  assert.equal(typeof telemetry.channelMeters[0].clipping, 'boolean');
  assert.equal(typeof telemetry.masterPeakLeft, 'number');
  assert.equal(typeof telemetry.masterPeakRight, 'number');
  assert.equal(typeof telemetry.limiterActive, 'boolean');
});

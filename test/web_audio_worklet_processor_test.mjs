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
const parityFixtureUrl = new URL('./fixtures/dsp_parity_vectors.tsv', import.meta.url);
await import(moduleUrl);

function stereoOutput(frames) {
  return [[new Float32Array(frames), new Float32Array(frames)]];
}

function channel(left, right = left) {
  return [Float32Array.from(left), Float32Array.from(right)];
}

function parseFloatList(value) {
  return value.split(',').map((token) => Number.parseFloat(token));
}

function parseParityChannel(value) {
  const [id, linearTrim, fader, muted, solo, interleaved] = value.split(';');
  return {
    id,
    linearTrim: Number.parseFloat(linearTrim),
    fader: Number.parseFloat(fader),
    muted: muted === '1',
    solo: solo === '1',
    interleaved: parseFloatList(interleaved),
  };
}

async function loadParityVectors() {
  const raw = await fs.readFile(parityFixtureUrl, 'utf8');
  return raw
    .split(/\r?\n/)
    .filter((line) => line.length > 0 && !line.startsWith('#'))
    .map((line) => {
      const [name, masterGain, channels, expected, limiterActive, peakLeft, peakRight] = line.split('\t');
      return {
        name,
        masterGainLinear: Number.parseFloat(masterGain),
        channels: channels.split('|').map(parseParityChannel),
        expected: parseFloatList(expected),
        limiterActive: limiterActive === '1',
        peakLeft: Number.parseFloat(peakLeft),
        peakRight: Number.parseFloat(peakRight),
      };
    });
}

function deinterleave(interleaved) {
  const left = [];
  const right = [];
  for (let index = 0; index < interleaved.length; index += 2) {
    left.push(interleaved[index]);
    right.push(interleaved[index + 1]);
  }
  return channel(left, right);
}

function outputInterleaved(output) {
  const left = output[0][0];
  const right = output[0][1];
  const interleaved = [];
  for (let frame = 0; frame < left.length; frame += 1) {
    interleaved.push(left[frame], right[frame]);
  }
  return interleaved;
}

function assertClose(actual, expected, message) {
  assert.ok(Math.abs(actual - expected) <= 1e-6, `${message}: expected ${expected}, got ${actual}`);
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

test('AudioWorklet executes the shared native DSP parity vectors', async () => {
  const vectors = await loadParityVectors();
  assert.ok(vectors.length >= 4, 'shared DSP parity fixture must include at least four cases');

  for (const vector of vectors) {
    const processor = new Processor();
    processor.port.dispatch({
      type: 'configure',
      masterGainLinear: vector.masterGainLinear,
      telemetryEvery: 1,
      channels: vector.channels.map(({ id, linearTrim, fader, muted, solo }) => ({
        id,
        linearTrim,
        fader,
        muted,
        solo,
      })),
    });

    const frames = vector.expected.length / 2;
    const output = stereoOutput(frames);
    const keepAlive = processor.process(
      vector.channels.map(({ interleaved }) => deinterleave(interleaved)),
      output,
      {},
    );
    assert.equal(keepAlive, true, `${vector.name}: processor must stay alive`);

    const actual = outputInterleaved(output);
    assert.equal(actual.length, vector.expected.length, `${vector.name}: sample length mismatch`);
    actual.forEach((sample, index) => {
      assertClose(sample, vector.expected[index], `${vector.name}: output sample ${index}`);
    });

    const telemetry = processor.port.messages.find((message) => message.type === 'telemetry');
    assert.ok(telemetry, `${vector.name}: telemetry required for parity evidence`);
    assert.equal(telemetry.limiterActive, vector.limiterActive, `${vector.name}: limiter state mismatch`);
    assertClose(telemetry.masterPeakLeft, vector.peakLeft, `${vector.name}: master left peak`);
    assertClose(telemetry.masterPeakRight, vector.peakRight, `${vector.name}: master right peak`);
  }
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

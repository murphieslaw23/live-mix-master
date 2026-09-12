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

function extractMethod(source, signature) {
  const signatureIndex = source.indexOf(signature);
  assert.notEqual(signatureIndex, -1, `missing method signature: ${signature}`);
  const bodyStart = source.indexOf('{', signatureIndex);
  assert.notEqual(bodyStart, -1, `missing method body: ${signature}`);
  let depth = 0;
  for (let index = bodyStart; index < source.length; index += 1) {
    if (source[index] === '{') depth += 1;
    if (source[index] === '}') {
      depth -= 1;
      if (depth === 0) return source.slice(bodyStart + 1, index);
    }
  }
  assert.fail(`unterminated method body: ${signature}`);
}

function stereoOutput(frames) {
  return [[new Float32Array(frames), new Float32Array(frames)]];
}

function channel(left, right = left) {
  return [Float32Array.from(left), Float32Array.from(right)];
}

function initializeCanonicalDsp(processor) {
  processor.port.dispatch({
    type: 'dspInit',
    abiVersion: 1,
    module: canonicalDspModule,
  });
  assert.ok(
    processor.port.messages.some((message) => message.type === 'dspReady'),
    'canonical generated DSP module must initialize in the worklet',
  );
}

function configureSingleChannel(processor, overrides = {}) {
  processor.port.dispatch({
    type: 'configure',
    masterGainLinear: overrides.masterGainLinear ?? 1,
    telemetryEvery: overrides.telemetryEvery ?? 1,
    channels: [
      {
        id: 'input-1',
        linearTrim: overrides.linearTrim ?? 1,
        fader: overrides.fader ?? 1,
        muted: false,
        solo: false,
      },
    ],
  });
}

function assertClose(actual, expected, message) {
  assert.ok(Math.abs(actual - expected) <= 1e-6, `${message}: expected ${expected}, got ${actual}`);
}

test('production process callback delegates arithmetic to preallocated canonical Wasm state', async () => {
  const source = await fs.readFile(workletUrl, 'utf8');
  const processSource = extractMethod(source, 'process(inputs, outputs)');

  for (const forbidden of [
    'new Float32Array(',
    '.push(',
    'Math.max(',
    'Math.min(',
    'linearTrim *',
    'fader * config.fader',
    'LIMITER_CEILING',
    'new WebAssembly.Instance(',
    'fetch(',
    'localStorage',
    'sessionStorage',
    'indexedDB',
    'console.',
  ]) {
    assert.equal(
      processSource.includes(forbidden),
      false,
      `duplicate/allocation pattern in process(): ${forbidden}`,
    );
  }

  assert.equal(
    processSource.includes('this.dspProcess('),
    true,
    'process() must invoke the cached lmm_dsp_process_stereo export',
  );
  assert.equal(
    source.includes('instance.exports.lmm_dsp_process_stereo'),
    true,
    'dspInit must bind the canonical lmm_dsp_process_stereo export outside process()',
  );
  assert.equal(source.includes('this.recordingScratch = new Float32Array(256)'), true);
  assert.equal(source.includes('this.analysisScratch = new Float32Array(256)'), true);
});

test('canonical Wasm render handles a full 128-frame stereo quantum', () => {
  const processor = new Processor();
  initializeCanonicalDsp(processor);
  configureSingleChannel(processor, { fader: 0.5 });

  const left = Array.from({ length: 128 }, (_, index) => (index % 2 === 0 ? 0.8 : -0.4));
  const right = Array.from({ length: 128 }, (_, index) => (index % 2 === 0 ? -0.6 : 0.2));
  const output = stereoOutput(128);
  assert.equal(processor.process([channel(left, right)], output, {}), true);

  for (let frame = 0; frame < 128; frame += 1) {
    assertClose(output[0][0][frame], left[frame] * 0.25, `left frame ${frame}`);
    assertClose(output[0][1][frame], right[frame] * 0.25, `right frame ${frame}`);
  }
});

test('mono browser input is mirrored to stereo before canonical Wasm processing', () => {
  const processor = new Processor();
  initializeCanonicalDsp(processor);
  configureSingleChannel(processor);

  const mono = Array.from({ length: 128 }, (_, index) => (index % 3 === 0 ? 0.35 : -0.2));
  const output = stereoOutput(128);
  assert.equal(processor.process([[Float32Array.from(mono)]], output, {}), true);

  assert.deepEqual(Array.from(output[0][0]), Array.from(output[0][1]));
  for (let frame = 0; frame < 128; frame += 1) {
    assertClose(output[0][0][frame], mono[frame], `mono frame ${frame}`);
  }
});

test('configured channel with missing browser input reports a deterministic zero meter', () => {
  const processor = new Processor();
  initializeCanonicalDsp(processor);
  configureSingleChannel(processor);

  const output = stereoOutput(128);
  assert.equal(processor.process([], output, {}), true);
  const telemetry = processor.port.messages.find((message) => message.type === 'telemetry');
  assert.ok(telemetry, 'missing input still requires deterministic telemetry');
  assert.deepEqual(telemetry.channelMeters, [
    {
      channelId: 'input-1',
      peakLeft: 0,
      peakRight: 0,
      rmsLeft: 0,
      rmsRight: 0,
      clipping: false,
    },
  ]);
});

test('oversized render quantum fails closed without an out-of-bounds write', () => {
  const processor = new Processor();
  initializeCanonicalDsp(processor);
  configureSingleChannel(processor);

  const output = stereoOutput(129);
  const input = Array.from({ length: 129 }, () => 0.5);
  assert.equal(processor.process([channel(input)], output, {}), true);
  assert.deepEqual(Array.from(output[0][0]), Array.from({ length: 129 }, () => 0));
  assert.deepEqual(Array.from(output[0][1]), Array.from({ length: 129 }, () => 0));
  assert.deepEqual(
    processor.port.messages.find((message) => message.type === 'dspError'),
    { type: 'dspError', code: 'RENDER_QUANTUM_EXCEEDED' },
  );
});

test('recording and analysis messages carry the exact canonical post-master Wasm output', () => {
  const processor = new Processor();
  initializeCanonicalDsp(processor);
  configureSingleChannel(processor, { masterGainLinear: 2 });
  processor.port.dispatch({ type: 'analysis', enabled: true, maxOutstandingPcm: 1 });
  processor.port.dispatch({ type: 'recording', enabled: true, maxOutstandingPcm: 1 });

  const output = stereoOutput(128);
  const input = Array.from({ length: 128 }, (_, index) => (index % 2 === 0 ? 0.75 : -0.75));
  assert.equal(processor.process([channel(input)], output, {}), true);

  const expected = [];
  for (let frame = 0; frame < 128; frame += 1) {
    expected.push(output[0][0][frame], output[0][1][frame]);
  }
  const analysis = processor.port.messages.find((message) => message.type === 'analysisPcm');
  const recording = processor.port.messages.find((message) => message.type === 'pcm');
  assert.ok(analysis);
  assert.ok(recording);
  assert.deepEqual(Array.from(analysis.samples).slice(0, 256), expected);
  assert.deepEqual(Array.from(recording.samples).slice(0, 256), expected);

  processor.process([channel(input)], stereoOutput(128), {});
  assert.equal(
    processor.port.messages.filter((message) => message.type === 'analysisPcm').length,
    1,
    'analysis queue must remain bounded until ACK',
  );
  assert.equal(
    processor.port.messages.filter((message) => message.type === 'pcm').length,
    1,
    'recording queue must remain bounded until ACK/fail-closed',
  );
});

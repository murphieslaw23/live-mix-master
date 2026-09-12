import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

import {
  LiveMixMasterFingerprintWindow,
  createLiveMixMasterFingerprintWorkerHandler,
  float32ToPcm16,
} from '../web/fingerprint/livemixmaster-fingerprint-worker.js';

const workerUrl = new URL(
  '../web/fingerprint/livemixmaster-fingerprint-worker.js',
  import.meta.url,
);

function makeStereoSamples({ seconds, sampleRate, left = 0.25, right = -0.25 }) {
  const frames = seconds * sampleRate;
  const samples = new Float32Array(frames * 2);
  for (let frame = 0; frame < frames; frame += 1) {
    samples[frame * 2] = left;
    samples[frame * 2 + 1] = right;
  }
  return samples;
}

test('fingerprint Worker converts Float32 to deterministic signed PCM16', () => {
  const pcm = float32ToPcm16(
    new Float32Array([-1.25, -1, -0.5, -0, 0, 0.5, 1, 1.25, Number.NaN]),
  );

  assert.deepEqual(
    Array.from(pcm),
    [-32768, -32768, -16384, 0, 0, 16384, 32767, 32767, 0],
  );
});

test('fingerprint rolling window consumes only declared frames from reusable AudioWorklet scratch', () => {
  const window = new LiveMixMasterFingerprintWindow({ maximumWindowSeconds: 10 });
  const scratch = new Float32Array(256);
  scratch[0] = 0.35;
  scratch[1] = -0.35;
  scratch.fill(0.9, 2);

  window.append({
    samples: scratch,
    frames: 1,
    sampleRate: 48000,
    channels: 2,
  });

  assert.equal(window.frames, 1);
  assert.deepEqual(
    Array.from(window.snapshot()),
    Array.from(Float32Array.of(0.35, -0.35)),
  );
});

test('fingerprint Worker keeps only the newest 10 seconds of stereo PCM', async () => {
  const sampleRate = 4;
  const messages = [];
  let capturedPcm = null;
  let fingerprintCalls = 0;
  const handle = createLiveMixMasterFingerprintWorkerHandler({
    postMessage: (message) => messages.push(message),
    loadChromaprint: async () => ({
      version: () => '1.6.1',
      fingerprintPcm16(pcm, rate, channels) {
        fingerprintCalls += 1;
        capturedPcm = new Int16Array(pcm);
        assert.equal(rate, sampleRate);
        assert.equal(channels, 2);
        return 'fixture-fingerprint';
      },
    }),
    minimumWindowSeconds: 10,
    maximumWindowSeconds: 10,
  });

  await handle({
    data: {
      type: 'init',
      moduleUrl: '/fingerprint/vendor/livemixmaster-chromaprint.mjs',
      wasmUrl: '/fingerprint/vendor/livemixmaster-chromaprint-core.wasm',
    },
  });

  const first = makeStereoSamples({ seconds: 6, sampleRate, left: 0.1, right: -0.1 });
  const second = makeStereoSamples({ seconds: 6, sampleRate, left: 0.5, right: -0.5 });

  await handle({
    data: { type: 'pcm', requestId: 1, samples: first, frames: first.length / 2, sampleRate, channels: 2 },
  });
  await handle({
    data: { type: 'pcm', requestId: 2, samples: second, frames: second.length / 2, sampleRate, channels: 2 },
  });
  await handle({ data: { type: 'flush', requestId: 3 } });

  assert.equal(fingerprintCalls, 1);
  assert.equal(capturedPcm.length, sampleRate * 10 * 2);
  const firstRetainedFrames = sampleRate * 4;
  assert.ok(
    capturedPcm.subarray(0, firstRetainedFrames * 2).every((sample, index) =>
      index % 2 === 0 ? sample === 3277 : sample === -3277,
    ),
  );
  assert.ok(
    capturedPcm.subarray(firstRetainedFrames * 2).every((sample, index) =>
      index % 2 === 0 ? sample === 16384 : sample === -16384,
    ),
  );
  assert.deepEqual(messages.filter((message) => message.type === 'pcmAck'), [
    { type: 'pcmAck', requestId: 1, frames: 24 },
    { type: 'pcmAck', requestId: 2, frames: 24 },
  ]);
  assert.deepEqual(messages.at(-1), {
    type: 'fingerprint',
    requestId: 3,
    fingerprint: 'fixture-fingerprint',
    durationSeconds: 10,
  });
});

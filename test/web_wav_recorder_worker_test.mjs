import assert from 'node:assert/strict';
import test from 'node:test';

import { LiveMixMasterWavWriter } from '../web/audio/livemixmaster-recorder-worker.js';

function ascii(bytes, start, length) {
  return String.fromCharCode(...bytes.subarray(start, start + length));
}

test('Web recording worker produces an independently valid >=10s 48kHz stereo PCM24 WAV', () => {
  const sampleRate = 48000;
  const channels = 2;
  const seconds = 10;
  const frames = sampleRate * seconds;
  const interleaved = new Float32Array(frames * channels);

  for (let frame = 0; frame < frames; frame += 1) {
    const phase = (frame % 200) / 200;
    interleaved[frame * 2] = phase * 1.8 - 0.9;
    interleaved[frame * 2 + 1] = 0.9 - phase * 1.8;
  }

  const writer = new LiveMixMasterWavWriter({
    sampleRate,
    channels,
    sampleFormat: 'pcm24',
    maxBytes: 4 * 1024 * 1024,
  });
  writer.appendInterleaved(interleaved);
  const wav = writer.finalize();

  const bytes = wav instanceof Uint8Array ? wav : new Uint8Array(wav);
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const expectedDataBytes = frames * channels * 3;

  assert.equal(ascii(bytes, 0, 4), 'RIFF');
  assert.equal(ascii(bytes, 8, 4), 'WAVE');
  assert.equal(ascii(bytes, 12, 4), 'fmt ');
  assert.equal(ascii(bytes, 36, 4), 'data');
  assert.equal(view.getUint32(4, true), bytes.byteLength - 8);
  assert.equal(view.getUint16(20, true), 1);
  assert.equal(view.getUint16(22, true), channels);
  assert.equal(view.getUint32(24, true), sampleRate);
  assert.equal(view.getUint16(34, true), 24);
  assert.equal(view.getUint32(40, true), expectedDataBytes);

  const byteRate = view.getUint32(28, true);
  const durationSeconds = view.getUint32(40, true) / byteRate;
  assert.equal(byteRate, sampleRate * channels * 3);
  assert.ok(durationSeconds >= 10, `expected >=10 s WAV, got ${durationSeconds}`);
});

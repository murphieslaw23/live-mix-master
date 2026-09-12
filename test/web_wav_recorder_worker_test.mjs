import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

import * as recorderWorker from '../web/audio/livemixmaster-recorder-worker.js';

const { LiveMixMasterWavWriter } = recorderWorker;
const recorderWorkerUrl = new URL('../web/audio/livemixmaster-recorder-worker.js', import.meta.url);

function ascii(bytes, start, length) {
  return String.fromCharCode(...bytes.subarray(start, start + length));
}

class MemoryRandomAccessSink {
  constructor() {
    this.bytes = new Uint8Array(0);
    this.maxWriteSize = 0;
    this.flushCount = 0;
    this.closeCount = 0;
  }

  write(buffer, options = {}) {
    const input = buffer instanceof Uint8Array
      ? buffer
      : new Uint8Array(buffer.buffer ?? buffer, buffer.byteOffset ?? 0, buffer.byteLength);
    const at = options.at ?? 0;
    const required = at + input.byteLength;
    if (required > this.bytes.byteLength) {
      const grown = new Uint8Array(required);
      grown.set(this.bytes);
      this.bytes = grown;
    }
    this.bytes.set(input, at);
    this.maxWriteSize = Math.max(this.maxWriteSize, input.byteLength);
    return input.byteLength;
  }

  truncate(size) {
    const resized = new Uint8Array(size);
    resized.set(this.bytes.subarray(0, Math.min(size, this.bytes.byteLength)));
    this.bytes = resized;
  }

  flush() {
    this.flushCount += 1;
  }

  close() {
    this.closeCount += 1;
  }
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

test('Worker protocol ACKs accepted PCM and fails closed when storage capacity is exceeded', () => {
  assert.equal(
    typeof recorderWorker.createLiveMixMasterRecorderWorkerHandler,
    'function',
    'recorder Worker message handler must exist',
  );

  const messages = [];
  const handle = recorderWorker.createLiveMixMasterRecorderWorkerHandler(
    (message) => messages.push(message),
  );

  handle({
    data: {
      type: 'start',
      sampleRate: 48000,
      channels: 2,
      sampleFormat: 'pcm24',
      maxBytes: 50,
    },
  });
  handle({
    data: {
      type: 'pcm',
      sequence: 7,
      samples: new Float32Array([0.25, -0.25]),
    },
  });

  assert.deepEqual(messages[0], { type: 'recordingStarted' });
  assert.deepEqual(messages[1], { type: 'pcmAck', sequence: 7, frames: 1 });

  handle({
    data: {
      type: 'pcm',
      sequence: 8,
      samples: new Float32Array([0, 0]),
    },
  });
  handle({
    data: {
      type: 'pcm',
      sequence: 9,
      samples: new Float32Array([0, 0]),
    },
  });

  assert.deepEqual(messages[2], {
    type: 'recordingError',
    reason: 'STORAGE_FULL',
    failureCode: 'storageFull',
  });
  assert.equal(
    messages.some((message) => message.type === 'pcmAck' && message.sequence >= 8),
    false,
    'rejected PCM must never be ACKed after fail-closed storage failure',
  );
});

test('Streaming WAV writer emits post-master PCM incrementally and patches RIFF header without session buffering', () => {
  assert.equal(
    typeof recorderWorker.LiveMixMasterStreamingWavWriter,
    'function',
    'streaming WAV writer must exist',
  );

  const sampleRate = 48000;
  const channels = 2;
  const frames = sampleRate * 10;
  const quantumFrames = 128;
  const sink = new MemoryRandomAccessSink();
  const writer = new recorderWorker.LiveMixMasterStreamingWavWriter({
    sampleRate,
    channels,
    sampleFormat: 'pcm24',
    maxBytes: 4 * 1024 * 1024,
    sink,
  });

  for (let offset = 0; offset < frames; offset += quantumFrames) {
    const chunkFrames = Math.min(quantumFrames, frames - offset);
    const samples = new Float32Array(chunkFrames * channels);
    for (let frame = 0; frame < chunkFrames; frame += 1) {
      samples[frame * 2] = 0.25;
      samples[frame * 2 + 1] = -0.25;
    }
    writer.appendInterleaved(samples);
  }

  const result = writer.finalize();
  const bytes = sink.bytes;
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const expectedDataBytes = frames * channels * 3;

  assert.deepEqual(result, {
    bytesWritten: expectedDataBytes + 44,
    dataBytes: expectedDataBytes,
  });
  assert.equal(ascii(bytes, 0, 4), 'RIFF');
  assert.equal(ascii(bytes, 8, 4), 'WAVE');
  assert.equal(view.getUint32(4, true), bytes.byteLength - 8);
  assert.equal(view.getUint32(40, true), expectedDataBytes);
  assert.ok(
    sink.maxWriteSize <= quantumFrames * channels * 3,
    `streaming writer performed an oversized ${sink.maxWriteSize}-byte write`,
  );
  assert.equal(sink.flushCount, 1);
  assert.equal(sink.closeCount, 1);
});

test('Browser recorder storage factory prefers OPFS sync access handles in the Dedicated Worker', async () => {
  assert.equal(
    typeof recorderWorker.createLiveMixMasterBrowserWavWriter,
    'function',
    'browser storage factory must exist',
  );

  const sink = new MemoryRandomAccessSink();
  let requestedName = null;
  let requestedCreate = null;
  const storage = {
    async getDirectory() {
      return {
        async getFileHandle(name, options) {
          requestedName = name;
          requestedCreate = options?.create;
          return {
            async createSyncAccessHandle() {
              return sink;
            },
          };
        },
      };
    },
  };

  const writer = await recorderWorker.createLiveMixMasterBrowserWavWriter(
    {
      sampleRate: 48000,
      channels: 2,
      sampleFormat: 'pcm24',
      maxBytes: 4 * 1024 * 1024,
    },
    { storage, fileName: 'acceptance.wav' },
  );

  assert.ok(writer instanceof recorderWorker.LiveMixMasterStreamingWavWriter);
  assert.equal(requestedName, 'acceptance.wav');
  assert.equal(requestedCreate, true);
});

test('Recorder module installs its OPFS-backed protocol handler in a real Worker global scope', async () => {
  const source = await readFile(recorderWorkerUrl, 'utf8');

  assert.match(
    source,
    /typeof self !== 'undefined'[\s\S]*self\.addEventListener\([\s\S]*'message'[\s\S]*createLiveMixMasterRecorderWorkerHandler/,
    'module Worker must install the exported recorder protocol handler at runtime',
  );
  assert.match(
    source,
    /navigator\.storage[\s\S]*getDirectory\([\s\S]*createSyncAccessHandle\(/,
    'real Worker path must prefer OPFS sync access for production-length recording',
  );
  assert.match(
    source,
    /writerFactory:[\s\S]*createLiveMixMasterBrowserWavWriter/,
    'real Worker bootstrap must inject the browser storage writer factory',
  );
});

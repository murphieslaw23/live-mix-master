import assert from 'node:assert/strict';
import test from 'node:test';

import {
  LiveMixMasterStreamingWavWriter,
  createLiveMixMasterRecorderWorkerHandler,
} from '../web/audio/livemixmaster-recorder-worker.js';

class FailingRandomAccessSink {
  constructor() {
    this.bytes = new Uint8Array(0);
    this.closeCount = 0;
    this.flushCount = 0;
    this.dataWriteAttempts = 0;
  }

  write(buffer, options = {}) {
    const input = buffer instanceof Uint8Array
      ? buffer
      : new Uint8Array(buffer.buffer ?? buffer, buffer.byteOffset ?? 0, buffer.byteLength);
    const at = options.at ?? 0;

    if (at >= 44) {
      this.dataWriteAttempts += 1;
      const error = new Error('quota exhausted');
      error.name = 'QuotaExceededError';
      throw error;
    }

    const required = at + input.byteLength;
    if (required > this.bytes.byteLength) {
      const grown = new Uint8Array(required);
      grown.set(this.bytes);
      this.bytes = grown;
    }
    this.bytes.set(input, at);
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

test('streaming write failure closes the OPFS-style sync handle exactly once and exposes no partial artifact', async () => {
  const sink = new FailingRandomAccessSink();
  const writer = new LiveMixMasterStreamingWavWriter({
    sampleRate: 48000,
    channels: 2,
    sampleFormat: 'pcm24',
    maxBytes: 4 * 1024 * 1024,
    sink,
  });
  const messages = [];
  const handle = createLiveMixMasterRecorderWorkerHandler(
    (message) => messages.push(message),
    { writerFactory: () => writer },
  );

  handle({
    data: {
      type: 'start',
      sampleRate: 48000,
      channels: 2,
      sampleFormat: 'pcm24',
      maxBytes: 4 * 1024 * 1024,
    },
  });
  handle({
    data: {
      type: 'pcm',
      sequence: 41,
      samples: new Float32Array([0.25, -0.25]),
    },
  });

  assert.equal(sink.dataWriteAttempts, 1);
  assert.equal(
    sink.closeCount,
    1,
    'failed streaming writer must close its sync access handle immediately',
  );
  assert.deepEqual(messages[0], { type: 'recordingStarted' });
  assert.deepEqual(messages[1], {
    type: 'recordingError',
    reason: 'STORAGE_FULL',
    failureCode: 'storageFull',
  });
  assert.equal(
    messages.some((message) => message.type === 'pcmAck' && message.sequence === 41),
    false,
    'failed PCM must never be acknowledged',
  );
  assert.equal(
    messages.some((message) => message.type === 'recordingStopped'),
    false,
    'failed recording must not be presented as a finalized artifact',
  );

  handle({ data: { type: 'export' } });
  await new Promise((resolve) => setImmediate(resolve));

  assert.equal(
    messages.some((message) => message.type === 'recordingExport'),
    false,
    'failed partial recording must not become exportable',
  );
});

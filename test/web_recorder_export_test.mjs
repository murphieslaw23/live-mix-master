import assert from 'node:assert/strict';
import test from 'node:test';

import {
  createLiveMixMasterBrowserWavWriter,
  createLiveMixMasterRecorderWorkerHandler,
} from '../web/audio/livemixmaster-recorder-worker.js';

class MemoryRandomAccessSink {
  constructor() {
    this.bytes = new Uint8Array(0);
    this.closed = false;
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
    return input.byteLength;
  }

  truncate(size) {
    const resized = new Uint8Array(size);
    resized.set(this.bytes.subarray(0, Math.min(size, this.bytes.byteLength)));
    this.bytes = resized;
  }

  flush() {}

  close() {
    this.closed = true;
  }
}

test('OPFS writer exposes the finalized File after closing the sync access handle', async () => {
  const sink = new MemoryRandomAccessSink();
  const finalizedFile = new Blob(['final-wav'], { type: 'audio/wav' });
  const fileHandle = {
    async createSyncAccessHandle() {
      return sink;
    },
    async getFile() {
      assert.equal(sink.closed, true, 'getFile must run only after the sync access handle is closed');
      return finalizedFile;
    },
  };
  const storage = {
    async getDirectory() {
      return {
        async getFileHandle(name, options) {
          assert.equal(name, 'acceptance.wav');
          assert.equal(options?.create, true);
          return fileHandle;
        },
      };
    },
  };

  const writer = await createLiveMixMasterBrowserWavWriter(
    {
      sampleRate: 48000,
      channels: 2,
      sampleFormat: 'pcm24',
      maxBytes: 4 * 1024 * 1024,
    },
    { storage, fileName: 'acceptance.wav' },
  );

  assert.equal(writer.fileName, 'acceptance.wav');
  assert.equal(typeof writer.exportFile, 'function', 'OPFS writer must expose finalized-file export');
  writer.appendInterleaved(new Float32Array([0.25, -0.25]));
  writer.finalize();
  assert.equal(await writer.exportFile(), finalizedFile);
});

test('Worker stop exposes artifact metadata and export returns the finalized File/Blob', async () => {
  const messages = [];
  const finalizedFile = new Blob(['final-wav'], { type: 'audio/wav' });
  const writer = {
    channels: 2,
    fileName: 'acceptance.wav',
    appendInterleaved() {},
    finalize() {
      return { bytesWritten: 50, dataBytes: 6 };
    },
    async exportFile() {
      return finalizedFile;
    },
  };

  const handle = createLiveMixMasterRecorderWorkerHandler(
    (message) => messages.push(message),
    { writerFactory: () => writer },
  );

  handle({ data: { type: 'start', sampleRate: 48000, channels: 2, sampleFormat: 'pcm24' } });
  handle({ data: { type: 'pcm', sequence: 1, samples: new Float32Array([0.1, -0.1]) } });
  handle({ data: { type: 'stop' } });

  const stopped = messages.find((message) => message.type === 'recordingStopped');
  assert.deepEqual(stopped, {
    type: 'recordingStopped',
    fileName: 'acceptance.wav',
    bytesWritten: 50,
    dataBytes: 6,
  });

  handle({ data: { type: 'export' } });
  await new Promise((resolve) => setImmediate(resolve));

  const exported = messages.find((message) => message.type === 'recordingExport');
  assert.ok(exported, 'worker must emit recordingExport after explicit export request');
  assert.equal(exported.fileName, 'acceptance.wav');
  assert.equal(exported.file, finalizedFile);
  assert.equal(exported.mimeType, 'audio/wav');
});

import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

import {
  LiveMixMasterStreamingWavWriter,
  createLiveMixMasterRecorderWorkerHandler,
} from '../web/audio/livemixmaster-recorder-worker.js';

const gatewayUrl = new URL(
  '../lib/audio/web/browser_audio_worklet_gateway_web.dart',
  import.meta.url,
);

class MemoryRandomAccessSink {
  constructor() {
    this.bytes = new Uint8Array(0);
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

function ascii(bytes, start, length) {
  return String.fromCharCode(...bytes.subarray(start, start + length));
}

test('Worker stop finalizes the streaming WAV before refusing further PCM', () => {
  const sink = new MemoryRandomAccessSink();
  const messages = [];
  const handle = createLiveMixMasterRecorderWorkerHandler(
    (message) => messages.push(message),
    {
      writerFactory: (options) => new LiveMixMasterStreamingWavWriter({
        ...options,
        maxBytes: 4096,
        sink,
      }),
    },
  );

  handle({
    data: {
      type: 'start',
      sampleRate: 48000,
      channels: 2,
      sampleFormat: 'pcm24',
      maxBytes: 4096,
    },
  });
  handle({
    data: {
      type: 'pcm',
      sequence: 1,
      samples: new Float32Array([0.25, -0.25]),
    },
  });
  handle({ data: { type: 'stop' } });

  assert.deepEqual(messages[0], { type: 'recordingStarted' });
  assert.deepEqual(messages[1], { type: 'pcmAck', sequence: 1, frames: 1 });
  assert.deepEqual(messages[2], {
    type: 'recordingStopped',
    bytesWritten: 50,
    dataBytes: 6,
  });
  assert.equal(ascii(sink.bytes, 0, 4), 'RIFF');
  assert.equal(ascii(sink.bytes, 8, 4), 'WAVE');
  assert.equal(new DataView(sink.bytes.buffer).getUint32(40, true), 6);
  assert.equal(sink.flushCount, 1);
  assert.equal(sink.closeCount, 1);

  handle({
    data: {
      type: 'pcm',
      sequence: 2,
      samples: new Float32Array([0, 0]),
    },
  });
  assert.equal(
    messages.some((message) => message.type === 'pcmAck' && message.sequence === 2),
    false,
    'PCM received after stop must never be ACKed',
  );
});

test('Web gateway waits for recorderStopped before terminating the Worker', async () => {
  const gateway = await readFile(gatewayUrl, 'utf8');

  assert.match(
    gateway,
    /case 'recordingStopped':[\s\S]*complete/,
    'Worker recordingStopped must complete the graceful shutdown handshake',
  );
  assert.match(
    gateway,
    /recorderWorker\.postMessage\([\s\S]*'type': 'stop'[\s\S]*await[\s\S]*recorderWorker\.terminate\(\)/,
    'gateway must request stop and await finalization before Worker termination',
  );
});

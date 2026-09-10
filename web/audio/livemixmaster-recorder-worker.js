const WAV_HEADER_BYTES = 44;
const PCM24_BYTES_PER_SAMPLE = 3;
const MAX_RIFF_FILE_BYTES = 0xffffffff;

function positiveInteger(value, name) {
  if (!Number.isInteger(value) || value <= 0) {
    throw new RangeError(`${name} must be a positive integer`);
  }
  return value;
}

function clampSample(value) {
  if (!Number.isFinite(value)) {
    return 0;
  }
  return Math.max(-1, Math.min(1, value));
}

function writeAscii(bytes, offset, value) {
  for (let index = 0; index < value.length; index += 1) {
    bytes[offset + index] = value.charCodeAt(index);
  }
}

function encodePcm24(samples) {
  const encoded = new Uint8Array(samples.length * PCM24_BYTES_PER_SAMPLE);
  for (let index = 0; index < samples.length; index += 1) {
    const sample = Math.round(clampSample(samples[index]) * 8388607);
    const offset = index * PCM24_BYTES_PER_SAMPLE;
    encoded[offset] = sample & 0xff;
    encoded[offset + 1] = (sample >> 8) & 0xff;
    encoded[offset + 2] = (sample >> 16) & 0xff;
  }
  return encoded;
}

function createPcm24WavHeader({ sampleRate, channels, dataBytes }) {
  const bytes = new Uint8Array(WAV_HEADER_BYTES);
  const view = new DataView(bytes.buffer);
  const blockAlign = channels * PCM24_BYTES_PER_SAMPLE;
  const byteRate = sampleRate * blockAlign;

  writeAscii(bytes, 0, 'RIFF');
  view.setUint32(4, dataBytes + 36, true);
  writeAscii(bytes, 8, 'WAVE');
  writeAscii(bytes, 12, 'fmt ');
  view.setUint32(16, 16, true);
  view.setUint16(20, 1, true);
  view.setUint16(22, channels, true);
  view.setUint32(24, sampleRate, true);
  view.setUint32(28, byteRate, true);
  view.setUint16(32, blockAlign, true);
  view.setUint16(34, 24, true);
  writeAscii(bytes, 36, 'data');
  view.setUint32(40, dataBytes, true);
  return bytes;
}

function isStorageFullError(error) {
  return (
    (error instanceof RangeError && error.message === 'WAV_MAX_BYTES_EXCEEDED') ||
    error?.name === 'QuotaExceededError'
  );
}

function recordingFailureMessage(error) {
  const storageFull = isStorageFullError(error);
  return {
    type: 'recordingError',
    reason: storageFull ? 'STORAGE_FULL' : 'WRITE_FAILED',
    failureCode: storageFull ? 'storageFull' : 'writeFailed',
  };
}

function defaultMemoryWriterFactory(options) {
  return new LiveMixMasterWavWriter(options);
}

export class LiveMixMasterWavWriter {
  constructor({
    sampleRate = 48000,
    channels = 2,
    sampleFormat = 'pcm24',
    maxBytes = Number.MAX_SAFE_INTEGER,
  } = {}) {
    this.sampleRate = positiveInteger(sampleRate, 'sampleRate');
    this.channels = positiveInteger(channels, 'channels');
    this.maxBytes = positiveInteger(maxBytes, 'maxBytes');

    if (sampleFormat !== 'pcm24') {
      throw new RangeError('sampleFormat must be pcm24');
    }

    this.sampleFormat = sampleFormat;
    this.bytesPerSample = PCM24_BYTES_PER_SAMPLE;
    this._chunks = [];
    this._dataBytes = 0;
    this._finalized = false;
  }

  appendInterleaved(samples) {
    if (this._finalized) {
      throw new Error('WAV writer is already finalized');
    }
    if (!(samples instanceof Float32Array)) {
      throw new TypeError('samples must be a Float32Array');
    }
    if (samples.length % this.channels !== 0) {
      throw new RangeError('interleaved samples must align to channel count');
    }

    const byteLength = samples.length * this.bytesPerSample;
    if (WAV_HEADER_BYTES + this._dataBytes + byteLength > this.maxBytes) {
      throw new RangeError('WAV_MAX_BYTES_EXCEEDED');
    }

    const encoded = encodePcm24(samples);
    this._chunks.push(encoded);
    this._dataBytes += encoded.byteLength;
  }

  finalize() {
    if (this._finalized) {
      throw new Error('WAV writer is already finalized');
    }
    this._finalized = true;

    const output = new Uint8Array(WAV_HEADER_BYTES + this._dataBytes);
    output.set(
      createPcm24WavHeader({
        sampleRate: this.sampleRate,
        channels: this.channels,
        dataBytes: this._dataBytes,
      }),
      0,
    );

    let offset = WAV_HEADER_BYTES;
    for (const chunk of this._chunks) {
      output.set(chunk, offset);
      offset += chunk.byteLength;
    }

    return output;
  }
}

export class LiveMixMasterStreamingWavWriter {
  constructor({
    sampleRate = 48000,
    channels = 2,
    sampleFormat = 'pcm24',
    maxBytes = MAX_RIFF_FILE_BYTES,
    sink,
  } = {}) {
    this.sampleRate = positiveInteger(sampleRate, 'sampleRate');
    this.channels = positiveInteger(channels, 'channels');
    this.maxBytes = positiveInteger(maxBytes, 'maxBytes');

    if (sampleFormat !== 'pcm24') {
      throw new RangeError('sampleFormat must be pcm24');
    }
    for (const method of ['write', 'truncate', 'flush', 'close']) {
      if (typeof sink?.[method] !== 'function') {
        throw new TypeError(`sink.${method} must be a function`);
      }
    }

    this.sampleFormat = sampleFormat;
    this.bytesPerSample = PCM24_BYTES_PER_SAMPLE;
    this._sink = sink;
    this._dataBytes = 0;
    this._finalized = false;

    this._sink.truncate(0);
    this._writeExactly(
      createPcm24WavHeader({
        sampleRate: this.sampleRate,
        channels: this.channels,
        dataBytes: 0,
      }),
      0,
    );
  }

  appendInterleaved(samples) {
    if (this._finalized) {
      throw new Error('WAV writer is already finalized');
    }
    if (!(samples instanceof Float32Array)) {
      throw new TypeError('samples must be a Float32Array');
    }
    if (samples.length % this.channels !== 0) {
      throw new RangeError('interleaved samples must align to channel count');
    }

    const encoded = encodePcm24(samples);
    if (WAV_HEADER_BYTES + this._dataBytes + encoded.byteLength > this.maxBytes) {
      throw new RangeError('WAV_MAX_BYTES_EXCEEDED');
    }

    this._writeExactly(encoded, WAV_HEADER_BYTES + this._dataBytes);
    this._dataBytes += encoded.byteLength;
  }

  finalize() {
    if (this._finalized) {
      throw new Error('WAV writer is already finalized');
    }
    this._finalized = true;

    const totalBytes = WAV_HEADER_BYTES + this._dataBytes;
    try {
      this._writeExactly(
        createPcm24WavHeader({
          sampleRate: this.sampleRate,
          channels: this.channels,
          dataBytes: this._dataBytes,
        }),
        0,
      );
      this._sink.truncate(totalBytes);
      this._sink.flush();
      return {
        bytesWritten: totalBytes,
        dataBytes: this._dataBytes,
      };
    } finally {
      this._sink.close();
    }
  }

  _writeExactly(bytes, at) {
    const written = this._sink.write(bytes, { at });
    if (written !== bytes.byteLength) {
      throw new Error('WAV_SHORT_WRITE');
    }
  }
}

export async function createLiveMixMasterBrowserWavWriter(
  options,
  { storage, fileName } = {},
) {
  const storageManager =
    storage ?? (typeof navigator !== 'undefined' ? navigator.storage : null);

  if (storageManager && typeof storageManager.getDirectory === 'function') {
    try {
      const root = await storageManager.getDirectory();
      const resolvedFileName =
        fileName ?? `livemixmaster-${Date.now().toString(36)}.wav`;
      const fileHandle = await root.getFileHandle(resolvedFileName, { create: true });
      if (typeof fileHandle.createSyncAccessHandle === 'function') {
        const accessHandle = await fileHandle.createSyncAccessHandle();
        return new LiveMixMasterStreamingWavWriter({
          ...options,
          maxBytes: MAX_RIFF_FILE_BYTES,
          sink: accessHandle,
        });
      }
    } catch (error) {
      if (isStorageFullError(error)) {
        throw error;
      }
    }
  }

  return new LiveMixMasterWavWriter(options);
}

export function createLiveMixMasterRecorderWorkerHandler(
  postMessage,
  { writerFactory = defaultMemoryWriterFactory } = {},
) {
  if (typeof postMessage !== 'function') {
    throw new TypeError('postMessage must be a function');
  }
  if (typeof writerFactory !== 'function') {
    throw new TypeError('writerFactory must be a function');
  }

  let writer = null;
  let failed = false;
  let startGeneration = 0;

  const activateWriter = (candidate, generation) => {
    if (generation !== startGeneration) {
      candidate?.finalize?.();
      return;
    }
    writer = candidate;
    failed = false;
    postMessage({ type: 'recordingStarted' });
  };

  const failWriter = (error, generation) => {
    if (generation !== startGeneration) {
      return;
    }
    writer = null;
    failed = true;
    postMessage(recordingFailureMessage(error));
  };

  return (event) => {
    const message = event?.data ?? event;
    if (message == null || typeof message !== 'object') {
      return;
    }

    if (message.type === 'start') {
      const generation = ++startGeneration;
      writer = null;
      failed = false;
      try {
        const candidate = writerFactory({
          sampleRate: message.sampleRate,
          channels: message.channels,
          sampleFormat: message.sampleFormat,
          maxBytes: message.maxBytes,
        });
        if (candidate && typeof candidate.then === 'function') {
          candidate.then(
            (resolvedWriter) => activateWriter(resolvedWriter, generation),
            (error) => failWriter(error, generation),
          );
        } else {
          activateWriter(candidate, generation);
        }
      } catch (error) {
        failWriter(error, generation);
      }
      return;
    }

    if (message.type === 'pcm') {
      if (failed || writer == null) {
        return;
      }

      try {
        writer.appendInterleaved(message.samples);
        postMessage({
          type: 'pcmAck',
          sequence: message.sequence,
          frames: message.samples.length / writer.channels,
        });
      } catch (error) {
        writer = null;
        failed = true;
        postMessage(recordingFailureMessage(error));
      }
    }
  };
}

if (
  typeof self !== 'undefined' &&
  typeof self.addEventListener === 'function' &&
  typeof self.postMessage === 'function'
) {
  self.addEventListener(
    'message',
    createLiveMixMasterRecorderWorkerHandler(
      (message) => self.postMessage(message),
      { writerFactory: createLiveMixMasterBrowserWavWriter },
    ),
  );
}

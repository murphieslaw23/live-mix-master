const WAV_HEADER_BYTES = 44;
const PCM24_BYTES_PER_SAMPLE = 3;

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

    const encoded = new Uint8Array(byteLength);
    for (let index = 0; index < samples.length; index += 1) {
      const sample = Math.round(clampSample(samples[index]) * 8388607);
      const offset = index * PCM24_BYTES_PER_SAMPLE;
      encoded[offset] = sample & 0xff;
      encoded[offset + 1] = (sample >> 8) & 0xff;
      encoded[offset + 2] = (sample >> 16) & 0xff;
    }

    this._chunks.push(encoded);
    this._dataBytes += encoded.byteLength;
  }

  finalize() {
    if (this._finalized) {
      throw new Error('WAV writer is already finalized');
    }
    this._finalized = true;

    const output = new Uint8Array(WAV_HEADER_BYTES + this._dataBytes);
    const view = new DataView(output.buffer);
    const blockAlign = this.channels * this.bytesPerSample;
    const byteRate = this.sampleRate * blockAlign;

    writeAscii(output, 0, 'RIFF');
    view.setUint32(4, this._dataBytes + 36, true);
    writeAscii(output, 8, 'WAVE');
    writeAscii(output, 12, 'fmt ');
    view.setUint32(16, 16, true);
    view.setUint16(20, 1, true);
    view.setUint16(22, this.channels, true);
    view.setUint32(24, this.sampleRate, true);
    view.setUint32(28, byteRate, true);
    view.setUint16(32, blockAlign, true);
    view.setUint16(34, 24, true);
    writeAscii(output, 36, 'data');
    view.setUint32(40, this._dataBytes, true);

    let offset = WAV_HEADER_BYTES;
    for (const chunk of this._chunks) {
      output.set(chunk, offset);
      offset += chunk.byteLength;
    }

    return output;
  }
}

export function createLiveMixMasterRecorderWorkerHandler(postMessage) {
  if (typeof postMessage !== 'function') {
    throw new TypeError('postMessage must be a function');
  }

  let writer = null;
  let failed = false;

  return (event) => {
    const message = event?.data ?? event;
    if (message == null || typeof message !== 'object') {
      return;
    }

    if (message.type === 'start') {
      try {
        writer = new LiveMixMasterWavWriter({
          sampleRate: message.sampleRate,
          channels: message.channels,
          sampleFormat: message.sampleFormat,
          maxBytes: message.maxBytes,
        });
        failed = false;
        postMessage({ type: 'recordingStarted' });
      } catch (_) {
        writer = null;
        failed = true;
        postMessage({
          type: 'recordingError',
          reason: 'WRITE_FAILED',
          failureCode: 'writeFailed',
        });
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
        const storageFull =
          error instanceof RangeError && error.message === 'WAV_MAX_BYTES_EXCEEDED';
        postMessage({
          type: 'recordingError',
          reason: storageFull ? 'STORAGE_FULL' : 'WRITE_FAILED',
          failureCode: storageFull ? 'storageFull' : 'writeFailed',
        });
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
    createLiveMixMasterRecorderWorkerHandler((message) => self.postMessage(message)),
  );
}

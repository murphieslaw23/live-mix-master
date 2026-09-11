const DEFAULT_MODULE_URL = '/fingerprint/vendor/livemixmaster-chromaprint.mjs';
const DEFAULT_WASM_URL = '/fingerprint/vendor/livemixmaster-chromaprint-core.wasm';
const EXPECTED_CHROMAPRINT_VERSION = '1.6.1';

function sanitizedFailureCode(error) {
  if (error instanceof RangeError) return 'invalidAudio';
  return 'unavailable';
}

function validateAssetUrl(value, expectedPath, trustedOrigin = null) {
  if (typeof value !== 'string' || value.length === 0) {
    throw new RangeError('fingerprint asset URL is invalid');
  }
  const base = trustedOrigin ?? 'https://livemixmaster.invalid';
  const url = new URL(value, base);
  if (url.pathname !== expectedPath) {
    throw new RangeError('fingerprint asset URL is not an approved release asset');
  }
  if (trustedOrigin != null && url.origin !== trustedOrigin) {
    throw new RangeError('fingerprint asset URL must be same-origin');
  }
  return url.href;
}

export function float32ToPcm16(samples) {
  if (!(samples instanceof Float32Array)) {
    throw new TypeError('samples must be a Float32Array');
  }
  const pcm = new Int16Array(samples.length);
  for (let index = 0; index < samples.length; index += 1) {
    let sample = samples[index];
    if (!Number.isFinite(sample)) sample = 0;
    sample = Math.max(-1, Math.min(1, sample));
    pcm[index] = Math.round(sample < 0 ? sample * 32768 : sample * 32767);
  }
  return pcm;
}

export class LiveMixMasterFingerprintWindow {
  constructor({ maximumWindowSeconds = 10 } = {}) {
    if (!Number.isFinite(maximumWindowSeconds) || maximumWindowSeconds <= 0) {
      throw new RangeError('maximumWindowSeconds must be positive');
    }
    this.maximumWindowSeconds = maximumWindowSeconds;
    this.sampleRate = null;
    this.channels = null;
    this.samples = new Float32Array(0);
  }

  get frames() {
    if (this.channels == null || this.channels <= 0) return 0;
    return Math.floor(this.samples.length / this.channels);
  }

  get durationSeconds() {
    if (this.sampleRate == null || this.sampleRate <= 0) return 0;
    return this.frames / this.sampleRate;
  }

  append({ samples, frames, sampleRate, channels }) {
    if (!(samples instanceof Float32Array)) {
      throw new TypeError('samples must be a Float32Array');
    }
    if (!Number.isInteger(sampleRate) || sampleRate <= 0) {
      throw new RangeError('sampleRate must be a positive integer');
    }
    if (channels !== 1 && channels !== 2) {
      throw new RangeError('channels must be 1 or 2');
    }
    if (!Number.isInteger(frames) || frames <= 0 || frames * channels !== samples.length) {
      throw new RangeError('frames do not match interleaved sample length');
    }

    if (this.sampleRate == null) {
      this.sampleRate = sampleRate;
      this.channels = channels;
    } else if (this.sampleRate !== sampleRate || this.channels !== channels) {
      throw new RangeError('fingerprint audio format changed');
    }

    const maxSamples = Math.floor(this.maximumWindowSeconds * sampleRate * channels);
    if (samples.length >= maxSamples) {
      this.samples = samples.slice(samples.length - maxSamples);
      return;
    }

    const retained = Math.max(0, maxSamples - samples.length);
    const previous = this.samples.length > retained
      ? this.samples.subarray(this.samples.length - retained)
      : this.samples;
    const next = new Float32Array(previous.length + samples.length);
    next.set(previous, 0);
    next.set(samples, previous.length);
    this.samples = next;
  }

  snapshot() {
    return new Float32Array(this.samples);
  }

  clear() {
    this.sampleRate = null;
    this.channels = null;
    this.samples = new Float32Array(0);
  }
}

async function loadDefaultChromaprint({ moduleUrl, wasmUrl }) {
  const module = await import(moduleUrl);
  if (typeof module.createChromaprint !== 'function') {
    throw new Error('Chromaprint adapter is unavailable');
  }
  return module.createChromaprint({ wasmUrl });
}

export function createLiveMixMasterFingerprintWorkerHandler({
  postMessage,
  loadChromaprint = loadDefaultChromaprint,
  minimumWindowSeconds = 10,
  maximumWindowSeconds = 10,
  trustedOrigin = null,
} = {}) {
  if (typeof postMessage !== 'function') {
    throw new TypeError('postMessage callback is required');
  }
  if (!Number.isFinite(minimumWindowSeconds) || minimumWindowSeconds <= 0) {
    throw new RangeError('minimumWindowSeconds must be positive');
  }
  if (maximumWindowSeconds < minimumWindowSeconds) {
    throw new RangeError('maximumWindowSeconds must cover the minimum window');
  }

  const rollingWindow = new LiveMixMasterFingerprintWindow({ maximumWindowSeconds });
  let chromaprint = null;
  let busy = false;
  let disposed = false;

  const fail = (requestId, failureCode) => {
    postMessage({ type: 'fingerprintError', requestId, failureCode });
  };

  return async function handleFingerprintWorkerMessage(event) {
    const message = event?.data ?? {};
    const requestId = message.requestId;

    if (disposed && message.type !== 'dispose') {
      fail(requestId, 'disposed');
      return;
    }

    switch (message.type) {
      case 'init': {
        try {
          const moduleUrl = validateAssetUrl(
            message.moduleUrl ?? DEFAULT_MODULE_URL,
            DEFAULT_MODULE_URL,
            trustedOrigin,
          );
          const wasmUrl = validateAssetUrl(
            message.wasmUrl ?? DEFAULT_WASM_URL,
            DEFAULT_WASM_URL,
            trustedOrigin,
          );
          chromaprint = await loadChromaprint({ moduleUrl, wasmUrl });
          if (chromaprint?.version?.() !== EXPECTED_CHROMAPRINT_VERSION) {
            chromaprint = null;
            fail(requestId, 'versionMismatch');
            return;
          }
          postMessage({ type: 'ready' });
        } catch (error) {
          chromaprint = null;
          fail(requestId, sanitizedFailureCode(error));
        }
        return;
      }

      case 'pcm': {
        if (chromaprint == null) {
          fail(requestId, 'notReady');
          return;
        }
        try {
          rollingWindow.append({
            samples: message.samples,
            frames: message.frames,
            sampleRate: message.sampleRate,
            channels: message.channels,
          });
          postMessage({ type: 'pcmAck', requestId, frames: message.frames });
        } catch (error) {
          fail(requestId, sanitizedFailureCode(error));
        }
        return;
      }

      case 'flush': {
        if (chromaprint == null) {
          fail(requestId, 'notReady');
          return;
        }
        if (busy) {
          fail(requestId, 'busy');
          return;
        }
        if (rollingWindow.durationSeconds < minimumWindowSeconds) {
          fail(requestId, 'tooShort');
          return;
        }

        busy = true;
        const samples = rollingWindow.snapshot();
        const sampleRate = rollingWindow.sampleRate;
        const channels = rollingWindow.channels;
        const durationSeconds = Math.round(rollingWindow.durationSeconds);
        try {
          const pcm = float32ToPcm16(samples);
          const fingerprint = await chromaprint.fingerprintPcm16(pcm, sampleRate, channels);
          if (typeof fingerprint !== 'string' || fingerprint.length === 0) {
            fail(requestId, 'unavailable');
            return;
          }
          postMessage({
            type: 'fingerprint',
            requestId,
            fingerprint,
            durationSeconds,
          });
        } catch (_) {
          fail(requestId, 'unavailable');
        } finally {
          busy = false;
        }
        return;
      }

      case 'dispose': {
        disposed = true;
        busy = false;
        chromaprint = null;
        rollingWindow.clear();
        return;
      }

      default:
        fail(requestId, 'invalidRequest');
    }
  };
}

if (
  typeof self !== 'undefined' &&
  typeof self.addEventListener === 'function' &&
  typeof self.postMessage === 'function'
) {
  const handleMessage = createLiveMixMasterFingerprintWorkerHandler({
    postMessage: (message) => self.postMessage(message),
    trustedOrigin: self.location?.origin ?? null,
  });
  self.addEventListener('message', (event) => {
    Promise.resolve(handleMessage(event)).catch(() => {
      self.postMessage({
        type: 'fingerprintError',
        requestId: event?.data?.requestId,
        failureCode: 'unavailable',
      });
    });
  });
}

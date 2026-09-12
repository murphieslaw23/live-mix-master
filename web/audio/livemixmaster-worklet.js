const LIMITER_CEILING = 0.98;
const DEFAULT_TELEMETRY_EVERY = 20;
const DEFAULT_MAX_OUTSTANDING_PCM = 4;
const DEFAULT_MAX_OUTSTANDING_ANALYSIS_PCM = 1;
const DSP_ABI_VERSION = 1;
const DSP_MAX_CHANNELS = 8;

function finiteNumber(value, fallback) {
  return typeof value === 'number' && Number.isFinite(value) ? value : fallback;
}

function positiveInteger(value, fallback) {
  const numeric = finiteNumber(value, fallback);
  return Math.max(1, Math.floor(numeric));
}

function normalizedChannel(channel, index) {
  const source = channel && typeof channel === 'object' ? channel : {};
  return {
    id: typeof source.id === 'string' && source.id.length > 0 ? source.id : `channel-${index}`,
    linearTrim: finiteNumber(source.linearTrim, 1),
    fader: finiteNumber(source.fader, 0.8),
    muted: source.muted === true,
    solo: source.solo === true,
  };
}

class LiveMixMasterProcessor extends AudioWorkletProcessor {
  constructor() {
    super();
    this.channels = [];
    this.masterGainLinear = 1;
    this.telemetryEvery = DEFAULT_TELEMETRY_EVERY;
    this.telemetryCounter = 0;
    this.telemetryOutstanding = false;
    this.recordingEnabled = false;
    this.recordingFaulted = false;
    this.maxOutstandingPcm = DEFAULT_MAX_OUTSTANDING_PCM;
    this.outstandingPcm = 0;
    this.analysisEnabled = false;
    this.analysisMaxOutstandingPcm = DEFAULT_MAX_OUTSTANDING_ANALYSIS_PCM;
    this.analysisOutstandingPcm = 0;
    this.dspReady = false;
    this.dspInstance = null;

    this.port.onmessage = (event) => this.handleMessage(event?.data);
  }

  handleMessage(message) {
    if (!message || typeof message !== 'object') {
      return;
    }

    switch (message.type) {
      case 'dspInit':
        this.initializeDsp(message);
        break;
      case 'configure':
        this.masterGainLinear = finiteNumber(message.masterGainLinear, this.masterGainLinear);
        this.telemetryEvery = positiveInteger(message.telemetryEvery, this.telemetryEvery);
        this.channels = Array.isArray(message.channels)
          ? message.channels.map((channel, index) => normalizedChannel(channel, index))
          : this.channels;
        break;
      case 'telemetryAck':
        this.telemetryOutstanding = false;
        break;
      case 'recording':
        this.recordingEnabled = message.enabled === true;
        this.maxOutstandingPcm = positiveInteger(
          message.maxOutstandingPcm,
          this.maxOutstandingPcm,
        );
        this.outstandingPcm = 0;
        this.recordingFaulted = false;
        break;
      case 'pcmAck':
        if (this.outstandingPcm > 0) {
          this.outstandingPcm -= 1;
        }
        break;
      case 'analysis':
        this.analysisEnabled = message.enabled === true;
        this.analysisMaxOutstandingPcm = positiveInteger(
          message.maxOutstandingPcm,
          this.analysisMaxOutstandingPcm,
        );
        this.analysisOutstandingPcm = 0;
        break;
      case 'analysisAck':
        if (this.analysisOutstandingPcm > 0) {
          this.analysisOutstandingPcm -= 1;
        }
        break;
      default:
        break;
    }
  }

  initializeDsp(message) {
    this.dspReady = false;
    this.dspInstance = null;

    if (message.abiVersion !== DSP_ABI_VERSION) {
      this.port.postMessage({ type: 'dspError', code: 'VERSION_MISMATCH' });
      return;
    }

    try {
      const instance = new WebAssembly.Instance(message.module, {});
      const abiVersion = instance.exports?.lmm_dsp_abi_version;
      const maxChannels = instance.exports?.lmm_dsp_max_channels;
      if (
        typeof abiVersion !== 'function' ||
        typeof maxChannels !== 'function' ||
        abiVersion() !== DSP_ABI_VERSION ||
        maxChannels() !== DSP_MAX_CHANNELS
      ) {
        this.port.postMessage({ type: 'dspError', code: 'VERSION_MISMATCH' });
        return;
      }
      this.dspInstance = instance;
      this.dspReady = true;
      this.port.postMessage({ type: 'dspReady' });
    } catch (_) {
      this.port.postMessage({ type: 'dspError', code: 'INITIALIZATION_FAILED' });
    }
  }

  process(inputs, outputs) {
    const outputBus = outputs?.[0];
    if (!outputBus || outputBus.length === 0) {
      return true;
    }

    const leftOutput = outputBus[0];
    const rightOutput = outputBus[1] ?? outputBus[0];
    if (!leftOutput || !rightOutput) {
      return true;
    }

    leftOutput.fill(0);
    if (rightOutput !== leftOutput) {
      rightOutput.fill(0);
    }

    if (!this.dspReady) {
      return true;
    }

    const frameCount = Math.min(leftOutput.length, rightOutput.length);
    const anySolo = this.channels.some((channel) => channel.solo);
    const channelMeters = [];

    for (let channelIndex = 0; channelIndex < this.channels.length; channelIndex += 1) {
      const config = this.channels[channelIndex];
      if (config.muted || (anySolo && !config.solo)) {
        continue;
      }

      const inputBus = inputs?.[channelIndex];
      const inputLeft = inputBus?.[0];
      if (!inputLeft) {
        continue;
      }
      const inputRight = inputBus?.[1] ?? inputLeft;
      const gain = config.linearTrim * config.fader * config.fader;
      let peakLeft = 0;
      let peakRight = 0;
      let squareLeft = 0;
      let squareRight = 0;
      const channelFrameCount = Math.min(frameCount, inputLeft.length, inputRight.length);

      for (let frame = 0; frame < channelFrameCount; frame += 1) {
        const left = inputLeft[frame] * gain;
        const right = inputRight[frame] * gain;
        leftOutput[frame] += left;
        rightOutput[frame] += right;
        peakLeft = Math.max(peakLeft, Math.abs(left));
        peakRight = Math.max(peakRight, Math.abs(right));
        squareLeft += left * left;
        squareRight += right * right;
      }

      channelMeters.push({
        channelId: config.id,
        peakLeft,
        peakRight,
        rmsLeft: channelFrameCount === 0 ? 0 : Math.sqrt(squareLeft / channelFrameCount),
        rmsRight: channelFrameCount === 0 ? 0 : Math.sqrt(squareRight / channelFrameCount),
        clipping: peakLeft >= 1 || peakRight >= 1,
      });
    }

    let masterPeakLeft = 0;
    let masterPeakRight = 0;
    let limiterActive = false;

    for (let frame = 0; frame < frameCount; frame += 1) {
      let left = leftOutput[frame] * this.masterGainLinear;
      let right = rightOutput[frame] * this.masterGainLinear;

      if (Math.abs(left) > LIMITER_CEILING || Math.abs(right) > LIMITER_CEILING) {
        limiterActive = true;
        left = Math.max(-LIMITER_CEILING, Math.min(LIMITER_CEILING, left));
        right = Math.max(-LIMITER_CEILING, Math.min(LIMITER_CEILING, right));
      }

      leftOutput[frame] = left;
      rightOutput[frame] = right;
      masterPeakLeft = Math.max(masterPeakLeft, Math.abs(left));
      masterPeakRight = Math.max(masterPeakRight, Math.abs(right));
    }

    this.telemetryCounter += 1;
    if (
      this.telemetryCounter >= this.telemetryEvery &&
      !this.telemetryOutstanding
    ) {
      this.telemetryCounter = 0;
      this.telemetryOutstanding = true;
      this.port.postMessage({
        type: 'telemetry',
        channelMeters,
        masterPeakLeft,
        masterPeakRight,
        limiterActive,
      });
    }

    if (
      this.analysisEnabled &&
      this.analysisOutstandingPcm < this.analysisMaxOutstandingPcm
    ) {
      const interleaved = new Float32Array(frameCount * 2);
      for (let frame = 0; frame < frameCount; frame += 1) {
        interleaved[frame * 2] = leftOutput[frame];
        interleaved[frame * 2 + 1] = rightOutput[frame];
      }
      this.analysisOutstandingPcm += 1;
      this.port.postMessage({
        type: 'analysisPcm',
        samples: interleaved,
        frames: frameCount,
        sampleRate,
        channels: 2,
      });
    }

    if (this.recordingEnabled && !this.recordingFaulted) {
      if (this.outstandingPcm >= this.maxOutstandingPcm) {
        this.recordingEnabled = false;
        this.recordingFaulted = true;
        this.port.postMessage({
          type: 'recordingError',
          reason: 'BACKPRESSURE',
          droppedFrames: frameCount,
        });
      } else {
        const interleaved = new Float32Array(frameCount * 2);
        for (let frame = 0; frame < frameCount; frame += 1) {
          interleaved[frame * 2] = leftOutput[frame];
          interleaved[frame * 2 + 1] = rightOutput[frame];
        }
        this.outstandingPcm += 1;
        this.port.postMessage({
          type: 'pcm',
          samples: interleaved,
          frames: frameCount,
          sampleRate,
        });
      }
    }

    return true;
  }
}

registerProcessor('livemixmaster-dsp', LiveMixMasterProcessor);

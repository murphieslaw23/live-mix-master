const DEFAULT_TELEMETRY_EVERY = 20;
const DEFAULT_MAX_OUTSTANDING_PCM = 4;
const DEFAULT_MAX_OUTSTANDING_ANALYSIS_PCM = 1;
const DSP_ABI_VERSION = 1;
const DSP_MAX_CHANNELS = 8;
const DSP_RENDER_QUANTUM_FRAMES = 128;
const DSP_CHANNEL_CONFIG_BYTES = 20;
const DSP_CHANNEL_METER_BYTES = 24;
const DSP_MASTER_METER_BYTES = 12;
const DSP_STEREO_SAMPLES_PER_QUANTUM = DSP_RENDER_QUANTUM_FRAMES * 2;
const DSP_STEREO_BYTES_PER_QUANTUM = DSP_STEREO_SAMPLES_PER_QUANTUM * 4;

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

function createChannelMeter(channel) {
  return {
    channelId: channel.id,
    peakLeft: 0,
    peakRight: 0,
    rmsLeft: 0,
    rmsRight: 0,
    clipping: false,
  };
}

class LiveMixMasterProcessor extends AudioWorkletProcessor {
  constructor() {
    super();
    this.channels = [];
    this.channelMeters = [];
    this.masterGainLinear = 1;
    this.telemetryEvery = DEFAULT_TELEMETRY_EVERY;
    this.telemetryCounter = 0;
    this.telemetryOutstanding = false;
    this.telemetryMessage = {
      type: 'telemetry',
      channelMeters: this.channelMeters,
      masterPeakLeft: 0,
      masterPeakRight: 0,
      limiterActive: false,
    };

    this.recordingEnabled = false;
    this.recordingFaulted = false;
    this.maxOutstandingPcm = DEFAULT_MAX_OUTSTANDING_PCM;
    this.outstandingPcm = 0;
    this.recordingScratch = null;
    this.recordingScratchViews = null;
    this.recordingMessage = null;
    this.recordingBackpressureMessage = {
      type: 'recordingError',
      reason: 'BACKPRESSURE',
      droppedFrames: 0,
    };

    this.analysisEnabled = false;
    this.analysisMaxOutstandingPcm = DEFAULT_MAX_OUTSTANDING_ANALYSIS_PCM;
    this.analysisOutstandingPcm = 0;
    this.analysisScratch = null;
    this.analysisScratchViews = null;
    this.analysisMessage = null;

    this.dspReady = false;
    this.dspInstance = null;
    this.dspMemory = null;
    this.dspMemoryBuffer = null;
    this.dspMalloc = null;
    this.dspProcess = null;
    this.dspConfigPointer = 0;
    this.dspInputPointersPointer = 0;
    this.dspInputBasePointer = 0;
    this.dspOutputPointer = 0;
    this.dspChannelMetersPointer = 0;
    this.dspMasterMeterPointer = 0;
    this.dspConfigView = null;
    this.dspInputPointerView = null;
    this.dspInputViews = null;
    this.dspOutputView = null;
    this.dspChannelMeterView = null;
    this.dspMasterMeterView = null;
    this.dspErrorMessages = {
      VERSION_MISMATCH: { type: 'dspError', code: 'VERSION_MISMATCH' },
      INITIALIZATION_FAILED: { type: 'dspError', code: 'INITIALIZATION_FAILED' },
      CHANNEL_LIMIT_EXCEEDED: { type: 'dspError', code: 'CHANNEL_LIMIT_EXCEEDED' },
      RENDER_QUANTUM_EXCEEDED: { type: 'dspError', code: 'RENDER_QUANTUM_EXCEEDED' },
      MEMORY_CHANGED: { type: 'dspError', code: 'MEMORY_CHANGED' },
      PROCESS_FAILED: { type: 'dspError', code: 'PROCESS_FAILED' },
    };

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
        this.configure(message);
        break;
      case 'telemetryAck':
        this.telemetryOutstanding = false;
        break;
      case 'recording':
        this.recordingEnabled = message.enabled === true && this.dspReady;
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
        this.analysisEnabled = message.enabled === true && this.dspReady;
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

  configure(message) {
    this.masterGainLinear = finiteNumber(message.masterGainLinear, this.masterGainLinear);
    this.telemetryEvery = positiveInteger(message.telemetryEvery, this.telemetryEvery);
    if (!Array.isArray(message.channels)) {
      return;
    }
    if (message.channels.length > DSP_MAX_CHANNELS) {
      this.failDsp('CHANNEL_LIMIT_EXCEEDED');
      return;
    }
    this.channels = message.channels.map((channel, index) => normalizedChannel(channel, index));
    this.channelMeters = this.channels.map((channel) => createChannelMeter(channel));
    this.telemetryMessage.channelMeters = this.channelMeters;
  }

  initializeDsp(message) {
    this.dspReady = false;
    this.dspInstance = null;
    this.dspMemory = null;
    this.dspMemoryBuffer = null;
    this.dspMalloc = null;
    this.dspProcess = null;
    this.dspInputViews = null;
    this.dspOutputView = null;
    this.recordingScratch = null;
    this.recordingScratchViews = null;
    this.analysisScratch = null;
    this.analysisScratchViews = null;
    this.recordingMessage = null;
    this.analysisMessage = null;

    if (message.abiVersion !== DSP_ABI_VERSION) {
      this.port.postMessage(this.dspErrorMessages.VERSION_MISMATCH);
      return;
    }

    try {
      const instance = new WebAssembly.Instance(message.module, {});
      const abiVersion = instance.exports.lmm_dsp_abi_version;
      const maxChannels = instance.exports.lmm_dsp_max_channels;
      const memory = instance.exports.memory;
      const malloc = instance.exports.malloc;
      const processStereo = instance.exports.lmm_dsp_process_stereo;
      if (
        typeof abiVersion !== 'function' ||
        typeof maxChannels !== 'function' ||
        abiVersion() !== DSP_ABI_VERSION ||
        maxChannels() !== DSP_MAX_CHANNELS
      ) {
        this.port.postMessage(this.dspErrorMessages.VERSION_MISMATCH);
        return;
      }
      if (
        !(memory instanceof WebAssembly.Memory) ||
        typeof malloc !== 'function' ||
        typeof processStereo !== 'function'
      ) {
        this.port.postMessage(this.dspErrorMessages.INITIALIZATION_FAILED);
        return;
      }

      const configPointer = this.allocateWasm(malloc, DSP_MAX_CHANNELS * DSP_CHANNEL_CONFIG_BYTES);
      const inputPointersPointer = this.allocateWasm(malloc, DSP_MAX_CHANNELS * 4);
      const inputBasePointer = this.allocateWasm(
        malloc,
        DSP_MAX_CHANNELS * DSP_STEREO_BYTES_PER_QUANTUM,
      );
      const outputPointer = this.allocateWasm(malloc, DSP_STEREO_BYTES_PER_QUANTUM);
      const channelMetersPointer = this.allocateWasm(
        malloc,
        DSP_MAX_CHANNELS * DSP_CHANNEL_METER_BYTES,
      );
      const masterMeterPointer = this.allocateWasm(malloc, DSP_MASTER_METER_BYTES);
      const memoryBuffer = memory.buffer;

      this.dspInstance = instance;
      this.dspMemory = memory;
      this.dspMemoryBuffer = memoryBuffer;
      this.dspMalloc = malloc;
      this.dspProcess = processStereo;
      this.dspConfigPointer = configPointer;
      this.dspInputPointersPointer = inputPointersPointer;
      this.dspInputBasePointer = inputBasePointer;
      this.dspOutputPointer = outputPointer;
      this.dspChannelMetersPointer = channelMetersPointer;
      this.dspMasterMeterPointer = masterMeterPointer;
      this.dspConfigView = new DataView(
        memoryBuffer,
        configPointer,
        DSP_MAX_CHANNELS * DSP_CHANNEL_CONFIG_BYTES,
      );
      this.dspInputPointerView = new DataView(
        memoryBuffer,
        inputPointersPointer,
        DSP_MAX_CHANNELS * 4,
      );
      this.dspInputViews = new Array(DSP_MAX_CHANNELS);
      for (let channelIndex = 0; channelIndex < DSP_MAX_CHANNELS; channelIndex += 1) {
        this.dspInputViews[channelIndex] = new Float32Array(
          memoryBuffer,
          inputBasePointer + channelIndex * DSP_STEREO_BYTES_PER_QUANTUM,
          DSP_STEREO_SAMPLES_PER_QUANTUM,
        );
      }
      this.dspOutputView = new Float32Array(
        memoryBuffer,
        outputPointer,
        DSP_STEREO_SAMPLES_PER_QUANTUM,
      );
      this.dspChannelMeterView = new DataView(
        memoryBuffer,
        channelMetersPointer,
        DSP_MAX_CHANNELS * DSP_CHANNEL_METER_BYTES,
      );
      this.dspMasterMeterView = new DataView(
        memoryBuffer,
        masterMeterPointer,
        DSP_MASTER_METER_BYTES,
      );

      this.recordingScratch = new Float32Array(256);
      this.analysisScratch = new Float32Array(256);
      this.recordingScratchViews = new Array(DSP_RENDER_QUANTUM_FRAMES + 1);
      this.analysisScratchViews = new Array(DSP_RENDER_QUANTUM_FRAMES + 1);
      for (let frames = 0; frames <= DSP_RENDER_QUANTUM_FRAMES; frames += 1) {
        const sampleCount = frames * 2;
        this.recordingScratchViews[frames] = new Float32Array(
          this.recordingScratch.buffer,
          0,
          sampleCount,
        );
        this.analysisScratchViews[frames] = new Float32Array(
          this.analysisScratch.buffer,
          0,
          sampleCount,
        );
      }
      this.recordingMessage = {
        type: 'pcm',
        samples: this.recordingScratchViews[0],
        frames: 0,
        sampleRate,
      };
      this.analysisMessage = {
        type: 'analysisPcm',
        samples: this.analysisScratchViews[0],
        frames: 0,
        sampleRate,
        channels: 2,
      };

      this.dspReady = true;
      this.port.postMessage({ type: 'dspReady' });
    } catch (_) {
      this.dspReady = false;
      this.port.postMessage(this.dspErrorMessages.INITIALIZATION_FAILED);
    }
  }

  allocateWasm(malloc, bytes) {
    const pointer = malloc(bytes);
    if (!Number.isInteger(pointer) || pointer <= 0) {
      throw new Error('WASM_ALLOCATION_FAILED');
    }
    return pointer;
  }

  failDsp(code) {
    this.dspReady = false;
    this.recordingEnabled = false;
    this.analysisEnabled = false;
    const message = this.dspErrorMessages[code];
    if (message) {
      this.port.postMessage(message);
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

    let frameCount = leftOutput.length;
    if (rightOutput.length < frameCount) {
      frameCount = rightOutput.length;
    }
    if (frameCount > DSP_RENDER_QUANTUM_FRAMES) {
      this.failDsp('RENDER_QUANTUM_EXCEEDED');
      return true;
    }
    if (this.dspMemory.buffer !== this.dspMemoryBuffer) {
      this.failDsp('MEMORY_CHANGED');
      return true;
    }

    const channelCount = this.channels.length;
    for (let channelIndex = 0; channelIndex < channelCount; channelIndex += 1) {
      const config = this.channels[channelIndex];
      const inputBus = inputs?.[channelIndex];
      const inputLeft = inputBus?.[0];
      const inputRight = inputBus?.[1] ?? inputLeft;
      const active = inputLeft && inputLeft.length > 0 ? 1 : 0;
      const inputView = this.dspInputViews[channelIndex];
      inputView.fill(0);

      if (active !== 0) {
        let channelFrames = frameCount;
        if (inputLeft.length < channelFrames) {
          channelFrames = inputLeft.length;
        }
        if (inputRight.length < channelFrames) {
          channelFrames = inputRight.length;
        }
        for (let frame = 0; frame < channelFrames; frame += 1) {
          inputView[frame * 2] = inputLeft[frame];
          inputView[frame * 2 + 1] = inputRight[frame];
        }
      }

      const configOffset = channelIndex * DSP_CHANNEL_CONFIG_BYTES;
      this.dspConfigView.setUint32(configOffset, active, true);
      this.dspConfigView.setUint32(configOffset + 4, config.muted ? 1 : 0, true);
      this.dspConfigView.setUint32(configOffset + 8, config.solo ? 1 : 0, true);
      this.dspConfigView.setFloat32(configOffset + 12, config.linearTrim, true);
      this.dspConfigView.setFloat32(configOffset + 16, config.fader, true);
      this.dspInputPointerView.setUint32(
        channelIndex * 4,
        active === 0
          ? 0
          : this.dspInputBasePointer + channelIndex * DSP_STEREO_BYTES_PER_QUANTUM,
        true,
      );
    }

    const status = this.dspProcess(
      this.dspConfigPointer,
      this.dspInputPointersPointer,
      channelCount,
      frameCount,
      this.masterGainLinear,
      this.dspOutputPointer,
      this.dspChannelMetersPointer,
      this.dspMasterMeterPointer,
    );
    if (status !== 0) {
      this.failDsp('PROCESS_FAILED');
      return true;
    }

    for (let frame = 0; frame < frameCount; frame += 1) {
      leftOutput[frame] = this.dspOutputView[frame * 2];
      rightOutput[frame] = this.dspOutputView[frame * 2 + 1];
    }

    for (let channelIndex = 0; channelIndex < channelCount; channelIndex += 1) {
      const meterOffset = channelIndex * DSP_CHANNEL_METER_BYTES;
      const meter = this.channelMeters[channelIndex];
      meter.peakLeft = this.dspChannelMeterView.getFloat32(meterOffset + 4, true);
      meter.peakRight = this.dspChannelMeterView.getFloat32(meterOffset + 8, true);
      meter.rmsLeft = this.dspChannelMeterView.getFloat32(meterOffset + 12, true);
      meter.rmsRight = this.dspChannelMeterView.getFloat32(meterOffset + 16, true);
      meter.clipping = this.dspChannelMeterView.getUint32(meterOffset + 20, true) !== 0;
    }

    this.telemetryMessage.masterPeakLeft = this.dspMasterMeterView.getFloat32(0, true);
    this.telemetryMessage.masterPeakRight = this.dspMasterMeterView.getFloat32(4, true);
    this.telemetryMessage.limiterActive = this.dspMasterMeterView.getUint32(8, true) !== 0;

    this.telemetryCounter += 1;
    if (
      this.telemetryCounter >= this.telemetryEvery &&
      !this.telemetryOutstanding
    ) {
      this.telemetryCounter = 0;
      this.telemetryOutstanding = true;
      this.port.postMessage(this.telemetryMessage);
    }

    if (
      this.analysisEnabled &&
      this.analysisOutstandingPcm < this.analysisMaxOutstandingPcm
    ) {
      this.analysisScratch.fill(0);
      for (let sampleIndex = 0; sampleIndex < frameCount * 2; sampleIndex += 1) {
        this.analysisScratch[sampleIndex] = this.dspOutputView[sampleIndex];
      }
      this.analysisMessage.samples = this.analysisScratchViews[frameCount];
      this.analysisMessage.frames = frameCount;
      this.analysisOutstandingPcm += 1;
      this.port.postMessage(this.analysisMessage);
    }

    if (this.recordingEnabled && !this.recordingFaulted) {
      if (this.outstandingPcm >= this.maxOutstandingPcm) {
        this.recordingEnabled = false;
        this.recordingFaulted = true;
        this.recordingBackpressureMessage.droppedFrames = frameCount;
        this.port.postMessage(this.recordingBackpressureMessage);
      } else {
        this.recordingScratch.fill(0);
        for (let sampleIndex = 0; sampleIndex < frameCount * 2; sampleIndex += 1) {
          this.recordingScratch[sampleIndex] = this.dspOutputView[sampleIndex];
        }
        this.recordingMessage.samples = this.recordingScratchViews[frameCount];
        this.recordingMessage.frames = frameCount;
        this.outstandingPcm += 1;
        this.port.postMessage(this.recordingMessage);
      }
    }

    return true;
  }
}

registerProcessor('livemixmaster-dsp', LiveMixMasterProcessor);
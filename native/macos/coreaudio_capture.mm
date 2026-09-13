#include "lmm_capture.h"

// Keep the already-reviewed Core Audio implementation intact and rename only
// the entry points that require channel-pair awareness. The include fragment is
// the exact pre-pair-selection implementation from the forward-port branch.
#define captureIoProc captureIoProcLegacy
#define lmm_capture_start lmm_capture_start_legacy
#include "coreaudio_capture_legacy.inc"
#undef lmm_capture_start
#undef captureIoProc

namespace {

std::atomic<std::uint32_t> g_channel_pair_index{0};

bool selectedPairChannels(
    std::uint32_t total_channels,
    std::uint32_t channel_pair_index,
    std::uint32_t& left_global_channel,
    std::uint32_t& right_global_channel) {
  if (total_channels == 0 ||
      channel_pair_index > std::numeric_limits<std::uint32_t>::max() / 2U) {
    return false;
  }

  left_global_channel = channel_pair_index * 2U;
  if (left_global_channel >= total_channels) return false;

  if (total_channels == 1U && channel_pair_index == 0U) {
    right_global_channel = left_global_channel;
    return true;
  }

  if (left_global_channel + 1U >= total_channels) return false;
  right_global_channel = left_global_channel + 1U;
  return true;
}

bool convertPcmPairToStereo(
    const PcmBufferView* buffers,
    std::uint32_t buffer_count,
    const PcmFormatDescriptor& format,
    std::uint32_t channel_pair_index,
    std::uint32_t frames,
    float* out_stereo,
    std::uint32_t output_sample_capacity) {
  if (!buffers || buffer_count == 0 || !out_stereo || frames == 0 ||
      format.total_channels == 0 || format.bytes_per_sample == 0) {
    return false;
  }

  const std::uint64_t required_samples = static_cast<std::uint64_t>(frames) * 2U;
  if (required_samples > output_sample_capacity ||
      required_samples > std::numeric_limits<std::uint32_t>::max()) {
    return false;
  }

  std::uint32_t left_global_channel = 0;
  std::uint32_t right_global_channel = 0;
  if (!selectedPairChannels(
          format.total_channels,
          channel_pair_index,
          left_global_channel,
          right_global_channel)) {
    return false;
  }

  std::uint32_t left_buffer = 0;
  std::uint32_t left_channel = 0;
  if (!channelLocation(
          buffers,
          buffer_count,
          left_global_channel,
          left_buffer,
          left_channel)) {
    return false;
  }

  std::uint32_t right_buffer = left_buffer;
  std::uint32_t right_channel = left_channel;
  if (right_global_channel != left_global_channel &&
      !channelLocation(
          buffers,
          buffer_count,
          right_global_channel,
          right_buffer,
          right_channel)) {
    return false;
  }

  for (std::uint32_t index = 0; index < buffer_count; ++index) {
    if (!buffers[index].data || buffers[index].channels == 0 ||
        buffers[index].bytes_per_frame <
            buffers[index].channels * format.bytes_per_sample) {
      return false;
    }
  }

  const auto* left_base =
      static_cast<const std::uint8_t*>(buffers[left_buffer].data);
  const auto* right_base =
      static_cast<const std::uint8_t*>(buffers[right_buffer].data);

  for (std::uint32_t frame = 0; frame < frames; ++frame) {
    const auto* left_bytes = left_base +
        static_cast<std::size_t>(frame) * buffers[left_buffer].bytes_per_frame +
        static_cast<std::size_t>(left_channel) * format.bytes_per_sample;
    const auto* right_bytes = right_base +
        static_cast<std::size_t>(frame) * buffers[right_buffer].bytes_per_frame +
        static_cast<std::size_t>(right_channel) * format.bytes_per_sample;

    float left = 0.0F;
    float right = 0.0F;
    if (!decodeSample(left_bytes, format, left) ||
        !decodeSample(right_bytes, format, right)) {
      return false;
    }
    out_stereo[frame * 2U] = left;
    out_stereo[frame * 2U + 1U] = right;
  }
  return true;
}

OSStatus captureIoProc(
    AudioObjectID,
    const AudioTimeStamp*,
    const AudioBufferList* input_data,
    const AudioTimeStamp*,
    AudioBufferList*,
    const AudioTimeStamp*,
    void*) {
  const std::uint64_t started = mach_absolute_time();

  if (g_state.load(std::memory_order_acquire) != LMM_CAPTURE_RUNNING ||
      !input_data || input_data->mNumberBuffers == 0) {
    recordCurrentCallbackDuration(started);
    return noErr;
  }

  if (input_data->mNumberBuffers > kMaxAudioBuffers) {
    g_state.store(LMM_CAPTURE_FAILED, std::memory_order_release);
    recordCurrentCallbackDuration(started);
    return noErr;
  }

  std::array<PcmBufferView, kMaxAudioBuffers> views{};
  std::uint32_t available_frames = std::numeric_limits<std::uint32_t>::max();
  std::uint32_t observed_channels = 0;

  for (UInt32 index = 0; index < input_data->mNumberBuffers; ++index) {
    const AudioBuffer& buffer = input_data->mBuffers[index];
    if (!buffer.mData || buffer.mDataByteSize == 0 ||
        buffer.mNumberChannels == 0) {
      recordCurrentCallbackDuration(started);
      return noErr;
    }

    const std::uint32_t bytes_per_frame =
        g_pcm_format.bytes_per_sample * buffer.mNumberChannels;
    if (bytes_per_frame == 0) {
      g_state.store(LMM_CAPTURE_FAILED, std::memory_order_release);
      recordCurrentCallbackDuration(started);
      return noErr;
    }

    views[index] = PcmBufferView{
        buffer.mData,
        buffer.mNumberChannels,
        bytes_per_frame,
    };
    observed_channels += buffer.mNumberChannels;
    available_frames = std::min(
        available_frames,
        static_cast<std::uint32_t>(buffer.mDataByteSize / bytes_per_frame));
  }

  if (observed_channels < g_pcm_format.total_channels || available_frames == 0) {
    recordCurrentCallbackDuration(started);
    return noErr;
  }

  const std::uint32_t reserved_frames =
      g_buffer_frames.load(std::memory_order_relaxed);
  const std::uint64_t required_samples =
      static_cast<std::uint64_t>(available_frames) * 2U;
  if (available_frames > reserved_frames ||
      required_samples > g_stereo_scratch.size()) {
    g_state.store(LMM_CAPTURE_FORMAT_CHANGED, std::memory_order_release);
    recordCurrentCallbackDuration(started);
    return noErr;
  }

  if (!convertPcmPairToStereo(
          views.data(),
          input_data->mNumberBuffers,
          g_pcm_format,
          g_channel_pair_index.load(std::memory_order_relaxed),
          available_frames,
          g_stereo_scratch.data(),
          static_cast<std::uint32_t>(g_stereo_scratch.size()))) {
    g_state.store(LMM_CAPTURE_FAILED, std::memory_order_release);
    recordCurrentCallbackDuration(started);
    return noErr;
  }

  (void)forwardConvertedStereo(g_stereo_scratch.data(), available_frames);
  recordCurrentCallbackDuration(started);
  return noErr;
}

bool mapTestSampleKind(
    std::uint32_t raw_kind,
    PcmSampleKind& out_kind) {
  switch (raw_kind) {
    case LMM_PCM_FLOAT32:
      out_kind = PcmSampleKind::float32;
      return true;
    case LMM_PCM_FLOAT64:
      out_kind = PcmSampleKind::float64;
      return true;
    case LMM_PCM_SIGNED16:
      out_kind = PcmSampleKind::signed16;
      return true;
    case LMM_PCM_SIGNED24:
      out_kind = PcmSampleKind::signed24;
      return true;
    case LMM_PCM_SIGNED32:
      out_kind = PcmSampleKind::signed32;
      return true;
    default:
      return false;
  }
}

}  // namespace

extern "C" bool lmm_capture_start(
    const char* device_uid,
    std::uint32_t channel_pair_index) {
  stopCaptureInternal(false);
  clearTelemetry();
  clearFormat();
  g_state.store(LMM_CAPTURE_STARTING, std::memory_order_release);

  AudioDeviceID device_id = kAudioObjectUnknown;
  if (!resolveDeviceUid(device_uid, device_id)) {
    g_state.store(LMM_CAPTURE_FAILED, std::memory_order_release);
    return false;
  }

  LmmCaptureFormat capture_format{};
  PcmFormatDescriptor pcm_format{};
  if (!readCaptureConfiguration(device_id, capture_format, pcm_format)) {
    g_state.store(LMM_CAPTURE_FAILED, std::memory_order_release);
    return false;
  }

  std::uint32_t ignored_left = 0;
  std::uint32_t ignored_right = 0;
  if (!selectedPairChannels(
          capture_format.input_channels,
          channel_pair_index,
          ignored_left,
          ignored_right)) {
    g_state.store(LMM_CAPTURE_FAILED, std::memory_order_release);
    return false;
  }

  const std::uint64_t scratch_samples =
      static_cast<std::uint64_t>(capture_format.buffer_frames) * 2U;
  if (scratch_samples == 0 ||
      scratch_samples > std::numeric_limits<std::uint32_t>::max()) {
    g_state.store(LMM_CAPTURE_FAILED, std::memory_order_release);
    return false;
  }

  try {
    g_stereo_scratch.assign(static_cast<std::size_t>(scratch_samples), 0.0F);
  } catch (...) {
    g_state.store(LMM_CAPTURE_FAILED, std::memory_order_release);
    return false;
  }
  g_pcm_format = pcm_format;
  g_channel_pair_index.store(channel_pair_index, std::memory_order_relaxed);
  publishFormat(capture_format);

  mach_timebase_info(&g_timebase);
  if (g_timebase.denom == 0) g_timebase = mach_timebase_info_data_t{1, 1};

  g_device_id.store(device_id, std::memory_order_release);
  g_capture_active.store(true, std::memory_order_release);

  if (!installDeviceListeners(device_id)) {
    stopCaptureInternal(false);
    g_state.store(LMM_CAPTURE_FAILED, std::memory_order_release);
    return false;
  }

  AudioDeviceIOProcID io_proc_id = nullptr;
  if (AudioDeviceCreateIOProcID(
          device_id,
          captureIoProc,
          nullptr,
          &io_proc_id) != noErr ||
      io_proc_id == nullptr) {
    stopCaptureInternal(false);
    g_state.store(LMM_CAPTURE_FAILED, std::memory_order_release);
    return false;
  }
  g_io_proc_id = io_proc_id;

  if (AudioDeviceStart(device_id, io_proc_id) != noErr) {
    stopCaptureInternal(false);
    g_state.store(LMM_CAPTURE_FAILED, std::memory_order_release);
    return false;
  }

  g_state.store(LMM_CAPTURE_RUNNING, std::memory_order_release);
  return true;
}

#if defined(LMM_BUILD_TESTING)

extern "C" bool lmm_capture_test_convert_pcm_pair(
    const LmmPcmBufferView* buffers,
    std::uint32_t buffer_count,
    const LmmPcmFormat* format,
    std::uint32_t channel_pair_index,
    std::uint32_t frames,
    float* out_stereo,
    std::uint32_t output_sample_capacity) {
  if (!buffers || !format || buffer_count == 0 ||
      buffer_count > kMaxAudioBuffers) {
    return false;
  }

  PcmSampleKind sample_kind{};
  if (!mapTestSampleKind(format->sample_kind, sample_kind)) return false;

  std::array<PcmBufferView, kMaxAudioBuffers> views{};
  for (std::uint32_t index = 0; index < buffer_count; ++index) {
    views[index] = PcmBufferView{
        buffers[index].data,
        buffers[index].channels,
        buffers[index].bytes_per_frame,
    };
  }

  const PcmFormatDescriptor descriptor{
      sample_kind,
      format->big_endian != 0,
      format->total_channels,
      format->bytes_per_sample,
  };
  return convertPcmPairToStereo(
      views.data(),
      buffer_count,
      descriptor,
      channel_pair_index,
      frames,
      out_stereo,
      output_sample_capacity);
}

#endif

#include "lmm_capture.h"
#include "lmm_pcm_handoff.h"

#include <CoreAudio/CoreAudio.h>
#include <CoreFoundation/CoreFoundation.h>
#include <mach/mach_time.h>

#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <limits>
#include <vector>

namespace {

constexpr std::size_t kMaxAudioBuffers = 64;

enum class PcmSampleKind : std::uint32_t {
  float32 = 1,
  float64 = 2,
  signed16 = 3,
  signed24 = 4,
  signed32 = 5,
};

struct PcmBufferView {
  const void* data = nullptr;
  std::uint32_t channels = 0;
  std::uint32_t bytes_per_frame = 0;
};

struct PcmFormatDescriptor {
  PcmSampleKind sample_kind = PcmSampleKind::float32;
  bool big_endian = false;
  std::uint32_t total_channels = 0;
  std::uint32_t bytes_per_sample = 0;
};

std::atomic<std::uint32_t> g_state{LMM_CAPTURE_IDLE};
std::atomic<double> g_sample_rate{0.0};
std::atomic<std::uint32_t> g_buffer_frames{0};
std::atomic<std::uint32_t> g_input_channels{0};
std::atomic<std::uint32_t> g_format_flags{0};
std::atomic<std::uint64_t> g_callback_count{0};
std::atomic<std::uint64_t> g_xrun_count{0};
std::atomic<std::uint64_t> g_total_callback_ns{0};
std::atomic<std::uint64_t> g_max_callback_ns{0};
std::atomic<bool> g_capture_active{false};
std::atomic<AudioDeviceID> g_device_id{kAudioObjectUnknown};

AudioDeviceIOProcID g_io_proc_id = nullptr;
mach_timebase_info_data_t g_timebase{1, 1};
PcmFormatDescriptor g_pcm_format{};
std::vector<float> g_stereo_scratch;

AudioObjectPropertyAddress addressFor(
    AudioObjectPropertySelector selector,
    AudioObjectPropertyScope scope = kAudioObjectPropertyScopeGlobal) {
  return AudioObjectPropertyAddress{
      selector,
      scope,
      kAudioObjectPropertyElementMain,
  };
}

template <typename T>
bool readScalar(
    AudioObjectID object_id,
    AudioObjectPropertySelector selector,
    AudioObjectPropertyScope scope,
    T& out_value) {
  const auto address = addressFor(selector, scope);
  if (!AudioObjectHasProperty(object_id, &address)) return false;
  UInt32 size = static_cast<UInt32>(sizeof(T));
  return AudioObjectGetPropertyData(
             object_id,
             &address,
             0,
             nullptr,
             &size,
             &out_value) == noErr &&
      size == sizeof(T);
}

std::uint32_t inputChannelCount(AudioObjectID device_id) {
  const auto address = addressFor(
      kAudioDevicePropertyStreamConfiguration,
      kAudioDevicePropertyScopeInput);
  if (!AudioObjectHasProperty(device_id, &address)) return 0;

  UInt32 size = 0;
  if (AudioObjectGetPropertyDataSize(
          device_id,
          &address,
          0,
          nullptr,
          &size) != noErr ||
      size < sizeof(AudioBufferList)) {
    return 0;
  }

  std::vector<std::uint8_t> storage(size);
  auto* buffer_list = reinterpret_cast<AudioBufferList*>(storage.data());
  if (AudioObjectGetPropertyData(
          device_id,
          &address,
          0,
          nullptr,
          &size,
          buffer_list) != noErr) {
    return 0;
  }

  std::uint32_t channels = 0;
  for (UInt32 index = 0; index < buffer_list->mNumberBuffers; ++index) {
    channels += buffer_list->mBuffers[index].mNumberChannels;
  }
  return channels;
}

bool mapLinearPcmFormat(
    const AudioStreamBasicDescription& stream_format,
    std::uint32_t input_channels,
    PcmFormatDescriptor& out_format) {
  if (stream_format.mFormatID != kAudioFormatLinearPCM ||
      input_channels == 0 ||
      stream_format.mBitsPerChannel == 0 ||
      stream_format.mBitsPerChannel % 8 != 0) {
    return false;
  }

  const std::uint32_t bytes_per_sample = stream_format.mBitsPerChannel / 8;
  PcmSampleKind sample_kind{};
  if ((stream_format.mFormatFlags & kAudioFormatFlagIsFloat) != 0) {
    if (stream_format.mBitsPerChannel == 32) {
      sample_kind = PcmSampleKind::float32;
    } else if (stream_format.mBitsPerChannel == 64) {
      sample_kind = PcmSampleKind::float64;
    } else {
      return false;
    }
  } else if ((stream_format.mFormatFlags & kAudioFormatFlagIsSignedInteger) != 0) {
    if (stream_format.mBitsPerChannel == 16) {
      sample_kind = PcmSampleKind::signed16;
    } else if (stream_format.mBitsPerChannel == 24) {
      sample_kind = PcmSampleKind::signed24;
    } else if (stream_format.mBitsPerChannel == 32) {
      sample_kind = PcmSampleKind::signed32;
    } else {
      return false;
    }
  } else {
    return false;
  }

  const bool non_interleaved =
      (stream_format.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0;
  const std::uint32_t expected_bytes_per_frame =
      bytes_per_sample * (non_interleaved ? 1U : input_channels);
  if (stream_format.mBytesPerFrame != expected_bytes_per_frame) {
    // Padded/aligned-high integer containers require a separate explicit
    // converter. Reject them rather than interpreting bytes ambiguously.
    return false;
  }

  if (stream_format.mChannelsPerFrame != 0 &&
      stream_format.mChannelsPerFrame != input_channels) {
    return false;
  }

  out_format.sample_kind = sample_kind;
  out_format.big_endian =
      (stream_format.mFormatFlags & kAudioFormatFlagIsBigEndian) != 0;
  out_format.total_channels = input_channels;
  out_format.bytes_per_sample = bytes_per_sample;
  return true;
}

bool readCaptureConfiguration(
    AudioDeviceID device_id,
    LmmCaptureFormat& out_capture_format,
    PcmFormatDescriptor& out_pcm_format) {
  Float64 nominal_sample_rate = 0.0;
  UInt32 buffer_frames = 0;
  AudioStreamBasicDescription stream_format{};

  if (!readScalar(
          device_id,
          kAudioDevicePropertyNominalSampleRate,
          kAudioObjectPropertyScopeGlobal,
          nominal_sample_rate) ||
      nominal_sample_rate <= 0.0) {
    return false;
  }

  if (!readScalar(
          device_id,
          kAudioDevicePropertyBufferFrameSize,
          kAudioObjectPropertyScopeGlobal,
          buffer_frames) ||
      buffer_frames == 0) {
    return false;
  }

  const auto stream_address = addressFor(
      kAudioDevicePropertyStreamFormat,
      kAudioDevicePropertyScopeInput);
  if (!AudioObjectHasProperty(device_id, &stream_address)) return false;

  UInt32 stream_size = static_cast<UInt32>(sizeof(stream_format));
  if (AudioObjectGetPropertyData(
          device_id,
          &stream_address,
          0,
          nullptr,
          &stream_size,
          &stream_format) != noErr ||
      stream_size != sizeof(stream_format)) {
    return false;
  }

  const std::uint32_t channels = inputChannelCount(device_id);
  if (!mapLinearPcmFormat(stream_format, channels, out_pcm_format)) return false;

  out_capture_format.sample_rate =
      stream_format.mSampleRate > 0.0
          ? stream_format.mSampleRate
          : nominal_sample_rate;
  out_capture_format.buffer_frames = buffer_frames;
  out_capture_format.input_channels = channels;
  out_capture_format.format_flags =
      static_cast<std::uint32_t>(stream_format.mFormatFlags);
  return true;
}

void publishFormat(const LmmCaptureFormat& format) {
  g_sample_rate.store(format.sample_rate, std::memory_order_relaxed);
  g_buffer_frames.store(format.buffer_frames, std::memory_order_relaxed);
  g_input_channels.store(format.input_channels, std::memory_order_relaxed);
  g_format_flags.store(format.format_flags, std::memory_order_relaxed);
}

void clearFormat() {
  g_sample_rate.store(0.0, std::memory_order_relaxed);
  g_buffer_frames.store(0, std::memory_order_relaxed);
  g_input_channels.store(0, std::memory_order_relaxed);
  g_format_flags.store(0, std::memory_order_relaxed);
}

void clearTelemetry() {
  g_callback_count.store(0, std::memory_order_relaxed);
  g_xrun_count.store(0, std::memory_order_relaxed);
  g_total_callback_ns.store(0, std::memory_order_relaxed);
  g_max_callback_ns.store(0, std::memory_order_relaxed);
}

void recordCallbackNanoseconds(std::uint64_t duration_ns, bool xrun) {
  g_callback_count.fetch_add(1, std::memory_order_relaxed);
  g_total_callback_ns.fetch_add(duration_ns, std::memory_order_relaxed);
  if (xrun) g_xrun_count.fetch_add(1, std::memory_order_relaxed);

  auto previous = g_max_callback_ns.load(std::memory_order_relaxed);
  while (duration_ns > previous &&
         !g_max_callback_ns.compare_exchange_weak(
             previous,
             duration_ns,
             std::memory_order_relaxed,
             std::memory_order_relaxed)) {
  }
}

std::uint64_t readUnsignedSample(
    const std::uint8_t* bytes,
    std::uint32_t byte_count,
    bool big_endian) {
  std::uint64_t value = 0;
  if (big_endian) {
    for (std::uint32_t index = 0; index < byte_count; ++index) {
      value = (value << 8U) | bytes[index];
    }
  } else {
    for (std::uint32_t index = 0; index < byte_count; ++index) {
      value |= static_cast<std::uint64_t>(bytes[index]) << (index * 8U);
    }
  }
  return value;
}

bool decodeSample(
    const std::uint8_t* bytes,
    const PcmFormatDescriptor& format,
    float& out_sample) {
  if (!bytes) return false;

  switch (format.sample_kind) {
    case PcmSampleKind::float32: {
      if (format.bytes_per_sample != 4) return false;
      const std::uint32_t bits = static_cast<std::uint32_t>(
          readUnsignedSample(bytes, 4, format.big_endian));
      float value = 0.0F;
      std::memcpy(&value, &bits, sizeof(value));
      out_sample = std::isfinite(value) ? value : 0.0F;
      return true;
    }
    case PcmSampleKind::float64: {
      if (format.bytes_per_sample != 8) return false;
      const std::uint64_t bits = readUnsignedSample(bytes, 8, format.big_endian);
      double value = 0.0;
      std::memcpy(&value, &bits, sizeof(value));
      out_sample = std::isfinite(value) ? static_cast<float>(value) : 0.0F;
      return true;
    }
    case PcmSampleKind::signed16:
    case PcmSampleKind::signed24:
    case PcmSampleKind::signed32: {
      const std::uint32_t expected_bytes =
          format.sample_kind == PcmSampleKind::signed16
              ? 2U
              : format.sample_kind == PcmSampleKind::signed24 ? 3U : 4U;
      if (format.bytes_per_sample != expected_bytes) return false;

      const std::uint32_t bits_per_sample = expected_bytes * 8U;
      const std::uint64_t raw =
          readUnsignedSample(bytes, expected_bytes, format.big_endian);
      const std::uint64_t sign_bit = std::uint64_t{1} << (bits_per_sample - 1U);
      const std::int64_t signed_value = (raw & sign_bit) != 0
          ? static_cast<std::int64_t>(raw - (std::uint64_t{1} << bits_per_sample))
          : static_cast<std::int64_t>(raw);
      const double divisor = static_cast<double>(sign_bit);
      out_sample = static_cast<float>(static_cast<double>(signed_value) / divisor);
      return true;
    }
  }

  return false;
}

bool channelLocation(
    const PcmBufferView* buffers,
    std::uint32_t buffer_count,
    std::uint32_t global_channel,
    std::uint32_t& out_buffer_index,
    std::uint32_t& out_local_channel) {
  std::uint32_t channel_base = 0;
  for (std::uint32_t index = 0; index < buffer_count; ++index) {
    const std::uint32_t channel_end = channel_base + buffers[index].channels;
    if (global_channel < channel_end) {
      out_buffer_index = index;
      out_local_channel = global_channel - channel_base;
      return true;
    }
    channel_base = channel_end;
  }
  return false;
}

bool convertPcmToStereo(
    const PcmBufferView* buffers,
    std::uint32_t buffer_count,
    const PcmFormatDescriptor& format,
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

  std::uint32_t left_buffer = 0;
  std::uint32_t left_channel = 0;
  if (!channelLocation(
          buffers,
          buffer_count,
          0,
          left_buffer,
          left_channel)) {
    return false;
  }

  std::uint32_t right_buffer = left_buffer;
  std::uint32_t right_channel = left_channel;
  if (format.total_channels > 1 &&
      !channelLocation(
          buffers,
          buffer_count,
          1,
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

bool forwardConvertedStereo(const float* interleaved_stereo, std::size_t frames) {
  return lmm_process_bound_capture_stereo(interleaved_stereo, frames);
}

bool resolveDeviceUid(const char* device_uid, AudioDeviceID& out_device_id) {
  if (!device_uid || device_uid[0] == '\0') return false;

  CFStringRef uid = CFStringCreateWithCString(
      kCFAllocatorDefault,
      device_uid,
      kCFStringEncodingUTF8);
  if (!uid) return false;

  AudioDeviceID device_id = kAudioObjectUnknown;
  AudioValueTranslation translation{
      &uid,
      static_cast<UInt32>(sizeof(uid)),
      &device_id,
      static_cast<UInt32>(sizeof(device_id)),
  };
  UInt32 size = static_cast<UInt32>(sizeof(translation));
  const auto address = addressFor(kAudioHardwarePropertyDeviceForUID);
  const OSStatus status = AudioObjectGetPropertyData(
      kAudioObjectSystemObject,
      &address,
      0,
      nullptr,
      &size,
      &translation);
  CFRelease(uid);

  if (status != noErr || device_id == kAudioObjectUnknown) return false;
  out_device_id = device_id;
  return true;
}

void markFormatChanged(AudioDeviceID device_id) {
  if (!g_capture_active.load(std::memory_order_acquire) ||
      g_state.load(std::memory_order_acquire) != LMM_CAPTURE_RUNNING) {
    return;
  }

  // Stop callback-side staging before reading new metadata. The converter and
  // scratch buffer remain frozen until an explicit stop/start renegotiates them.
  g_state.store(LMM_CAPTURE_FORMAT_CHANGED, std::memory_order_release);

  LmmCaptureFormat capture_format{};
  PcmFormatDescriptor ignored_pcm_format{};
  if (!readCaptureConfiguration(
          device_id,
          capture_format,
          ignored_pcm_format)) {
    g_state.store(LMM_CAPTURE_FAILED, std::memory_order_release);
    return;
  }
  publishFormat(capture_format);
}

OSStatus devicePropertyListener(
    AudioObjectID object_id,
    UInt32 number_addresses,
    const AudioObjectPropertyAddress addresses[],
    void*) {
  if (!g_capture_active.load(std::memory_order_acquire)) return noErr;

  for (UInt32 index = 0; index < number_addresses; ++index) {
    const auto selector = addresses[index].mSelector;

    if (selector == kAudioDeviceProcessorOverload) {
      g_xrun_count.fetch_add(1, std::memory_order_relaxed);
      continue;
    }

    if (selector == kAudioDevicePropertyDeviceIsAlive) {
      UInt32 is_alive = 0;
      if (!readScalar(
              object_id,
              kAudioDevicePropertyDeviceIsAlive,
              kAudioObjectPropertyScopeGlobal,
              is_alive) ||
          is_alive == 0) {
        g_state.store(LMM_CAPTURE_DEVICE_REMOVED, std::memory_order_release);
      }
      // Device return does not auto-resume stale conversion state. A later
      // controlled reconnect can call stop/start and renegotiate explicitly.
      continue;
    }

    if (selector == kAudioDevicePropertyNominalSampleRate ||
        selector == kAudioDevicePropertyBufferFrameSize ||
        selector == kAudioDevicePropertyStreamConfiguration ||
        selector == kAudioDevicePropertyStreamFormat) {
      markFormatChanged(object_id);
    }
  }

  return noErr;
}

bool addListenerIfSupported(
    AudioDeviceID device_id,
    const AudioObjectPropertyAddress& address) {
  if (!AudioObjectHasProperty(device_id, &address)) return true;
  return AudioObjectAddPropertyListener(
             device_id,
             &address,
             devicePropertyListener,
             nullptr) == noErr;
}

void removeListenerIfSupported(
    AudioDeviceID device_id,
    const AudioObjectPropertyAddress& address) {
  if (!AudioObjectHasProperty(device_id, &address)) return;
  AudioObjectRemovePropertyListener(
      device_id,
      &address,
      devicePropertyListener,
      nullptr);
}

bool installDeviceListeners(AudioDeviceID device_id) {
  const AudioObjectPropertyAddress listeners[] = {
      addressFor(kAudioDevicePropertyDeviceIsAlive),
      addressFor(kAudioDevicePropertyNominalSampleRate),
      addressFor(kAudioDevicePropertyBufferFrameSize),
      addressFor(
          kAudioDevicePropertyStreamConfiguration,
          kAudioDevicePropertyScopeInput),
      addressFor(
          kAudioDevicePropertyStreamFormat,
          kAudioDevicePropertyScopeInput),
      addressFor(kAudioDeviceProcessorOverload),
  };

  std::size_t installed = 0;
  for (const auto& address : listeners) {
    if (!addListenerIfSupported(device_id, address)) {
      for (std::size_t index = 0; index < installed; ++index) {
        removeListenerIfSupported(device_id, listeners[index]);
      }
      return false;
    }
    ++installed;
  }
  return true;
}

void removeDeviceListeners(AudioDeviceID device_id) {
  const AudioObjectPropertyAddress listeners[] = {
      addressFor(kAudioDevicePropertyDeviceIsAlive),
      addressFor(kAudioDevicePropertyNominalSampleRate),
      addressFor(kAudioDevicePropertyBufferFrameSize),
      addressFor(
          kAudioDevicePropertyStreamConfiguration,
          kAudioDevicePropertyScopeInput),
      addressFor(
          kAudioDevicePropertyStreamFormat,
          kAudioDevicePropertyScopeInput),
      addressFor(kAudioDeviceProcessorOverload),
  };

  for (const auto& address : listeners) {
    removeListenerIfSupported(device_id, address);
  }
}

void recordCurrentCallbackDuration(std::uint64_t started) {
  const std::uint64_t ended = mach_absolute_time();
  const std::uint64_t ticks = ended - started;
  const std::uint64_t duration_ns =
      g_timebase.denom == 0
          ? 0
          : (ticks * static_cast<std::uint64_t>(g_timebase.numer)) /
                static_cast<std::uint64_t>(g_timebase.denom);
  recordCallbackNanoseconds(duration_ns, false);
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
      // A zero-data callback is not a format failure; it simply contributes no
      // staged PCM for this cycle.
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

  if (!convertPcmToStereo(
          views.data(),
          input_data->mNumberBuffers,
          g_pcm_format,
          available_frames,
          g_stereo_scratch.data(),
          static_cast<std::uint32_t>(g_stereo_scratch.size()))) {
    g_state.store(LMM_CAPTURE_FAILED, std::memory_order_release);
    recordCurrentCallbackDuration(started);
    return noErr;
  }

  // No active mixer binding and saturated downstream queues are both safe,
  // observable drop conditions. Neither may block or fail the Core Audio IOProc.
  (void)forwardConvertedStereo(g_stereo_scratch.data(), available_frames);
  recordCurrentCallbackDuration(started);
  return noErr;
}

void stopCaptureInternal(bool reset_state) {
  g_capture_active.store(false, std::memory_order_release);

  const AudioDeviceID device_id = g_device_id.exchange(
      kAudioObjectUnknown,
      std::memory_order_acq_rel);
  AudioDeviceIOProcID io_proc_id = g_io_proc_id;
  g_io_proc_id = nullptr;

  if (device_id != kAudioObjectUnknown) {
    if (io_proc_id != nullptr) {
      AudioDeviceStop(device_id, io_proc_id);
    }
    removeDeviceListeners(device_id);
    if (io_proc_id != nullptr) {
      AudioDeviceDestroyIOProcID(device_id, io_proc_id);
    }
  }

  // The callback is stopped before mutable conversion state is changed.
  g_stereo_scratch.clear();
  g_pcm_format = {};

  if (reset_state) {
    g_state.store(LMM_CAPTURE_IDLE, std::memory_order_release);
  }
}

}  // namespace

extern "C" bool lmm_capture_start(const char* device_uid) {
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

extern "C" void lmm_capture_stop() {
  stopCaptureInternal(true);
}

extern "C" bool lmm_capture_get_status(LmmCaptureStatus* out_status) {
  if (!out_status) return false;

  out_status->state = g_state.load(std::memory_order_acquire);
  out_status->sample_rate = g_sample_rate.load(std::memory_order_relaxed);
  out_status->buffer_frames = g_buffer_frames.load(std::memory_order_relaxed);
  out_status->input_channels = g_input_channels.load(std::memory_order_relaxed);
  out_status->format_flags = g_format_flags.load(std::memory_order_relaxed);
  out_status->callback_count = g_callback_count.load(std::memory_order_relaxed);
  out_status->xrun_count = g_xrun_count.load(std::memory_order_relaxed);

  const std::uint64_t callback_count = out_status->callback_count;
  const std::uint64_t total_ns = g_total_callback_ns.load(std::memory_order_relaxed);
  const std::uint64_t max_ns = g_max_callback_ns.load(std::memory_order_relaxed);
  out_status->average_callback_us = callback_count == 0
      ? 0.0
      : static_cast<double>(total_ns) /
            static_cast<double>(callback_count) /
            1000.0;
  out_status->max_callback_us = static_cast<double>(max_ns) / 1000.0;
  return true;
}

#if defined(LMM_BUILD_TESTING)

extern "C" void lmm_capture_test_reset() {
  stopCaptureInternal(false);
  clearTelemetry();
  clearFormat();
  g_state.store(LMM_CAPTURE_IDLE, std::memory_order_release);
}

extern "C" bool lmm_capture_test_apply_event(
    std::uint32_t event,
    const LmmCaptureFormat* format) {
  switch (event) {
    case LMM_CAPTURE_TEST_BEGIN:
      g_state.store(LMM_CAPTURE_STARTING, std::memory_order_release);
      return true;
    case LMM_CAPTURE_TEST_RUNNING:
      if (!format) return false;
      publishFormat(*format);
      g_state.store(LMM_CAPTURE_RUNNING, std::memory_order_release);
      return true;
    case LMM_CAPTURE_TEST_REMOVED:
      g_state.store(LMM_CAPTURE_DEVICE_REMOVED, std::memory_order_release);
      return true;
    case LMM_CAPTURE_TEST_FORMAT_CHANGED:
      if (!format) return false;
      publishFormat(*format);
      g_state.store(LMM_CAPTURE_FORMAT_CHANGED, std::memory_order_release);
      return true;
    case LMM_CAPTURE_TEST_RECOVERED:
      if (!format) return false;
      publishFormat(*format);
      g_state.store(LMM_CAPTURE_RUNNING, std::memory_order_release);
      return true;
    case LMM_CAPTURE_TEST_STOPPED:
      g_state.store(LMM_CAPTURE_IDLE, std::memory_order_release);
      return true;
    case LMM_CAPTURE_TEST_FAILED:
      g_state.store(LMM_CAPTURE_FAILED, std::memory_order_release);
      return true;
    default:
      return false;
  }
}

extern "C" void lmm_capture_test_record_callback(
    double duration_us,
    bool xrun) {
  if (duration_us < 0.0) duration_us = 0.0;
  const auto duration_ns = static_cast<std::uint64_t>(duration_us * 1000.0);
  recordCallbackNanoseconds(duration_ns, xrun);
}

extern "C" bool lmm_capture_test_convert_pcm(
    const LmmPcmBufferView* buffers,
    std::uint32_t buffer_count,
    const LmmPcmFormat* format,
    std::uint32_t frames,
    float* out_stereo,
    std::uint32_t output_sample_capacity) {
  if (!buffers || !format || buffer_count == 0 ||
      buffer_count > kMaxAudioBuffers) {
    return false;
  }

  PcmSampleKind sample_kind{};
  switch (format->sample_kind) {
    case LMM_PCM_FLOAT32:
      sample_kind = PcmSampleKind::float32;
      break;
    case LMM_PCM_FLOAT64:
      sample_kind = PcmSampleKind::float64;
      break;
    case LMM_PCM_SIGNED16:
      sample_kind = PcmSampleKind::signed16;
      break;
    case LMM_PCM_SIGNED24:
      sample_kind = PcmSampleKind::signed24;
      break;
    case LMM_PCM_SIGNED32:
      sample_kind = PcmSampleKind::signed32;
      break;
    default:
      return false;
  }

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
  return convertPcmToStereo(
      views.data(),
      buffer_count,
      descriptor,
      frames,
      out_stereo,
      output_sample_capacity);
}

extern "C" bool lmm_capture_test_forward_stereo(
    const float* interleaved_stereo,
    std::size_t frames) {
  return forwardConvertedStereo(interleaved_stereo, frames);
}

#endif

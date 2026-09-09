#include "lmm_capture.h"

#include <CoreAudio/CoreAudio.h>
#include <CoreFoundation/CoreFoundation.h>
#include <mach/mach_time.h>

#include <atomic>
#include <cstdint>
#include <vector>

namespace {

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

bool readCaptureFormat(AudioDeviceID device_id, LmmCaptureFormat& out_format) {
  Float64 sample_rate = 0.0;
  UInt32 buffer_frames = 0;
  AudioStreamBasicDescription stream_format{};

  if (!readScalar(
          device_id,
          kAudioDevicePropertyNominalSampleRate,
          kAudioObjectPropertyScopeGlobal,
          sample_rate) ||
      sample_rate <= 0.0) {
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
  if (channels == 0) return false;

  out_format.sample_rate = sample_rate;
  out_format.buffer_frames = buffer_frames;
  out_format.input_channels = channels;
  out_format.format_flags = static_cast<std::uint32_t>(stream_format.mFormatFlags);
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
  if (!g_capture_active.load(std::memory_order_acquire)) return;

  LmmCaptureFormat format{};
  if (!readCaptureFormat(device_id, format)) {
    g_state.store(LMM_CAPTURE_FAILED, std::memory_order_release);
    return;
  }
  publishFormat(format);

  if (g_state.load(std::memory_order_acquire) == LMM_CAPTURE_RUNNING) {
    g_state.store(LMM_CAPTURE_FORMAT_CHANGED, std::memory_order_release);
  }
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
        continue;
      }

      if (g_state.load(std::memory_order_acquire) == LMM_CAPTURE_DEVICE_REMOVED) {
        LmmCaptureFormat format{};
        if (readCaptureFormat(object_id, format)) {
          publishFormat(format);
          g_state.store(LMM_CAPTURE_RUNNING, std::memory_order_release);
        } else {
          g_state.store(LMM_CAPTURE_FAILED, std::memory_order_release);
        }
      }
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

OSStatus captureIoProc(
    AudioObjectID,
    const AudioTimeStamp*,
    const AudioBufferList*,
    const AudioTimeStamp*,
    AudioBufferList*,
    const AudioTimeStamp*,
    void*) {
  const std::uint64_t started = mach_absolute_time();

  // The first capture task intentionally performs no PCM fan-out here yet.
  // The callback contract is established and measured; bounded queue handoff to
  // mixer/recording/fingerprinting is introduced in the next task.

  const std::uint64_t ended = mach_absolute_time();
  const std::uint64_t ticks = ended - started;
  const std::uint64_t duration_ns =
      g_timebase.denom == 0
          ? 0
          : (ticks * static_cast<std::uint64_t>(g_timebase.numer)) /
                static_cast<std::uint64_t>(g_timebase.denom);
  recordCallbackNanoseconds(duration_ns, false);
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

  LmmCaptureFormat format{};
  if (!readCaptureFormat(device_id, format)) {
    g_state.store(LMM_CAPTURE_FAILED, std::memory_order_release);
    return false;
  }
  publishFormat(format);

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

#endif

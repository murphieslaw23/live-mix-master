#include "lmm_capture.h"
#include "lmm_device_catalog.h"
#include "lmm_pcm_handoff.h"

#include <pipewire/pipewire.h>
#include <spa/param/audio/format-utils.h>
#include <spa/pod/builder.h>

#include <algorithm>
#include <array>
#include <atomic>
#include <cerrno>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <limits>
#include <mutex>
#include <string_view>
#include <time.h>

namespace {

constexpr std::string_view kSourceUidPrefix = "pipewire:source:";
constexpr std::string_view kSinkUidPrefix = "pipewire:sink:";
constexpr std::uint32_t kFormatFlagFloat32Interleaved = 1;
constexpr std::uint32_t kInitialBufferFrames = LMM_PCM_BLOCK_FRAMES;
constexpr std::uint32_t kStartTimeoutSeconds = 5;

struct CaptureSession {
  pw_thread_loop* loop = nullptr;
  pw_stream* stream = nullptr;
  spa_hook streamListener{};
  std::atomic<std::uint32_t> state{LMM_CAPTURE_IDLE};
  std::atomic<double> sampleRate{0.0};
  std::atomic<std::uint32_t> bufferFrames{0};
  std::atomic<std::uint32_t> inputChannels{0};
  std::atomic<std::uint32_t> formatFlags{0};
  std::atomic<std::uint64_t> callbackCount{0};
  std::atomic<std::uint64_t> xrunCount{0};
  std::atomic<std::uint64_t> callbackDurationNanoseconds{0};
  std::atomic<std::uint64_t> maxCallbackNanoseconds{0};
  std::atomic<bool> formatReady{false};
  std::atomic<bool> runningObserved{false};
  std::atomic<bool> stopping{false};
  std::atomic<bool> startPending{false};
  std::uint32_t channelPairIndex = 0;
  bool captureSink = false;
};

CaptureSession gSession;

void ensurePipeWireInitialized() {
  static std::once_flag initialized;
  std::call_once(initialized, [] { pw_init(nullptr, nullptr); });
}

std::uint64_t monotonicNanoseconds() {
  timespec value{};
  if (clock_gettime(CLOCK_MONOTONIC, &value) != 0) return 0;
  return static_cast<std::uint64_t>(value.tv_sec) * 1000000000ULL +
      static_cast<std::uint64_t>(value.tv_nsec);
}

void recordCallbackDuration(std::uint64_t startedAt) {
  const std::uint64_t finishedAt = monotonicNanoseconds();
  const std::uint64_t duration = finishedAt >= startedAt ? finishedAt - startedAt : 0;
  gSession.callbackCount.fetch_add(1, std::memory_order_relaxed);
  gSession.callbackDurationNanoseconds.fetch_add(duration, std::memory_order_relaxed);

  std::uint64_t previous = gSession.maxCallbackNanoseconds.load(std::memory_order_relaxed);
  while (duration > previous &&
      !gSession.maxCallbackNanoseconds.compare_exchange_weak(
          previous,
          duration,
          std::memory_order_relaxed,
          std::memory_order_relaxed)) {
  }
}

bool hasPrefix(std::string_view value, std::string_view prefix) {
  return value.size() >= prefix.size() && value.compare(0, prefix.size(), prefix) == 0;
}

bool parseEndpointUid(const char* uid, std::string_view& target, bool& captureSink) {
  if (!uid) return false;
  const std::string_view value(uid);
  if (hasPrefix(value, kSourceUidPrefix)) {
    target = value.substr(kSourceUidPrefix.size());
    captureSink = false;
  } else if (hasPrefix(value, kSinkUidPrefix)) {
    target = value.substr(kSinkUidPrefix.size());
    captureSink = true;
  } else {
    return false;
  }
  return !target.empty() && target.size() < LMM_DEVICE_UID_CAPACITY;
}

bool selectedPairIsValid(std::uint32_t channels, std::uint32_t pairIndex) {
  if (channels == 0 || pairIndex > std::numeric_limits<std::uint32_t>::max() / 2U) {
    return false;
  }
  const std::uint32_t left = pairIndex * 2U;
  if (left >= channels) return false;
  return channels == 1 || left + 1U < channels;
}

void signalStartWaiter() {
  if (gSession.loop && gSession.startPending.load(std::memory_order_acquire)) {
    pw_thread_loop_signal(gSession.loop, false);
  }
}

void onStreamStateChanged(
    void*,
    pw_stream_state,
    pw_stream_state state,
    const char*) {
  if (gSession.stopping.load(std::memory_order_acquire)) return;

  switch (state) {
    case PW_STREAM_STATE_STREAMING:
      if (gSession.formatReady.load(std::memory_order_acquire)) {
        gSession.runningObserved.store(true, std::memory_order_release);
        gSession.state.store(LMM_CAPTURE_RUNNING, std::memory_order_release);
      } else {
        gSession.state.store(LMM_CAPTURE_FAILED, std::memory_order_release);
      }
      signalStartWaiter();
      return;
    case PW_STREAM_STATE_ERROR:
      gSession.xrunCount.fetch_add(1, std::memory_order_relaxed);
      gSession.state.store(
          gSession.runningObserved.load(std::memory_order_acquire)
              ? LMM_CAPTURE_DEVICE_REMOVED
              : LMM_CAPTURE_FAILED,
          std::memory_order_release);
      signalStartWaiter();
      return;
    case PW_STREAM_STATE_UNCONNECTED:
      gSession.state.store(
          gSession.runningObserved.load(std::memory_order_acquire)
              ? LMM_CAPTURE_DEVICE_REMOVED
              : LMM_CAPTURE_FAILED,
          std::memory_order_release);
      signalStartWaiter();
      return;
    case PW_STREAM_STATE_PAUSED:
      if (gSession.runningObserved.load(std::memory_order_acquire)) {
        gSession.state.store(LMM_CAPTURE_DEVICE_REMOVED, std::memory_order_release);
      }
      return;
    case PW_STREAM_STATE_CONNECTING:
      return;
  }
}

void onStreamParamChanged(void*, std::uint32_t id, const spa_pod* parameter) {
  if (id != SPA_PARAM_Format || !parameter) return;

  std::uint32_t mediaType = 0;
  std::uint32_t mediaSubtype = 0;
  spa_audio_info_raw format{};
  if (spa_format_parse(parameter, &mediaType, &mediaSubtype) < 0 ||
      mediaType != SPA_MEDIA_TYPE_audio || mediaSubtype != SPA_MEDIA_SUBTYPE_raw ||
      spa_format_audio_raw_parse(parameter, &format) < 0 ||
      format.format != SPA_AUDIO_FORMAT_F32 || format.rate == 0 ||
      !selectedPairIsValid(format.channels, gSession.channelPairIndex)) {
    gSession.state.store(LMM_CAPTURE_FORMAT_CHANGED, std::memory_order_release);
    signalStartWaiter();
    return;
  }

  gSession.sampleRate.store(static_cast<double>(format.rate), std::memory_order_release);
  gSession.inputChannels.store(format.channels, std::memory_order_release);
  gSession.bufferFrames.store(kInitialBufferFrames, std::memory_order_release);
  gSession.formatFlags.store(kFormatFlagFloat32Interleaved, std::memory_order_release);
  gSession.formatReady.store(true, std::memory_order_release);
}

void onStreamProcess(void*) {
  const std::uint64_t startedAt = monotonicNanoseconds();
  if (!gSession.stream ||
      gSession.state.load(std::memory_order_acquire) != LMM_CAPTURE_RUNNING) {
    recordCallbackDuration(startedAt);
    return;
  }

  pw_buffer* buffer = pw_stream_dequeue_buffer(gSession.stream);
  if (!buffer) {
    gSession.xrunCount.fetch_add(1, std::memory_order_relaxed);
    recordCallbackDuration(startedAt);
    return;
  }

  spa_buffer* spaBuffer = buffer->buffer;
  if (!spaBuffer || spaBuffer->n_datas == 0 || !spaBuffer->datas[0].data ||
      !spaBuffer->datas[0].chunk) {
    gSession.xrunCount.fetch_add(1, std::memory_order_relaxed);
    pw_stream_queue_buffer(gSession.stream, buffer);
    recordCallbackDuration(startedAt);
    return;
  }

  const std::uint32_t channels = gSession.inputChannels.load(std::memory_order_relaxed);
  const std::uint32_t pairIndex = gSession.channelPairIndex;
  const std::uint32_t leftChannel = pairIndex * 2U;
  const std::uint32_t rightChannel = channels == 1 ? 0 : leftChannel + 1U;
  const spa_data& data = spaBuffer->datas[0];
  const std::uint32_t bytesPerFrame = channels * sizeof(float);
  const std::uint32_t frameCount = bytesPerFrame == 0
      ? 0
      : data.chunk->size / bytesPerFrame;
  const auto* source = static_cast<const float*>(data.data) +
      data.chunk->offset / sizeof(float);

  if (!selectedPairIsValid(channels, pairIndex) || frameCount == 0) {
    gSession.xrunCount.fetch_add(1, std::memory_order_relaxed);
    pw_stream_queue_buffer(gSession.stream, buffer);
    recordCallbackDuration(startedAt);
    return;
  }

  std::array<float, LMM_PCM_BLOCK_FRAMES * 2> stereo{};
  std::uint32_t offset = 0;
  while (offset < frameCount) {
    const std::uint32_t frames = std::min<std::uint32_t>(
        LMM_PCM_BLOCK_FRAMES,
        frameCount - offset);
    for (std::uint32_t frame = 0; frame < frames; ++frame) {
      const auto* inputFrame = source + static_cast<std::size_t>(offset + frame) * channels;
      stereo[frame * 2U] = inputFrame[leftChannel];
      stereo[frame * 2U + 1U] = inputFrame[rightChannel];
    }
    (void)lmm_process_bound_capture_stereo(stereo.data(), frames);
    offset += frames;
  }

  if (gSession.bufferFrames.load(std::memory_order_relaxed) != frameCount) {
    gSession.bufferFrames.store(frameCount, std::memory_order_relaxed);
  }
  pw_stream_queue_buffer(gSession.stream, buffer);
  recordCallbackDuration(startedAt);
}

const pw_stream_events kStreamEvents = [] {
  pw_stream_events events{};
  events.version = PW_VERSION_STREAM_EVENTS;
  events.state_changed = onStreamStateChanged;
  events.param_changed = onStreamParamChanged;
  events.process = onStreamProcess;
  return events;
}();

void resetTelemetry() {
  gSession.sampleRate.store(0.0, std::memory_order_relaxed);
  gSession.bufferFrames.store(0, std::memory_order_relaxed);
  gSession.inputChannels.store(0, std::memory_order_relaxed);
  gSession.formatFlags.store(0, std::memory_order_relaxed);
  gSession.callbackCount.store(0, std::memory_order_relaxed);
  gSession.xrunCount.store(0, std::memory_order_relaxed);
  gSession.callbackDurationNanoseconds.store(0, std::memory_order_relaxed);
  gSession.maxCallbackNanoseconds.store(0, std::memory_order_relaxed);
  gSession.formatReady.store(false, std::memory_order_relaxed);
  gSession.runningObserved.store(false, std::memory_order_relaxed);
}

void destroyCaptureSession(bool publishIdle) {
  gSession.stopping.store(true, std::memory_order_release);
  if (gSession.loop && gSession.stream) {
    pw_thread_loop_lock(gSession.loop);
    pw_stream_destroy(gSession.stream);
    gSession.stream = nullptr;
    pw_thread_loop_unlock(gSession.loop);
  }
  spa_hook_remove(&gSession.streamListener);
  if (gSession.loop) {
    pw_thread_loop_stop(gSession.loop);
    pw_thread_loop_destroy(gSession.loop);
    gSession.loop = nullptr;
  }
  gSession.startPending.store(false, std::memory_order_release);
  if (publishIdle) gSession.state.store(LMM_CAPTURE_IDLE, std::memory_order_release);
}

}  // namespace

extern "C" bool lmm_capture_start(
    const char* device_uid,
    std::uint32_t channel_pair_index) {
  ensurePipeWireInitialized();
  lmm_capture_stop();
  resetTelemetry();
  gSession.channelPairIndex = channel_pair_index;
  gSession.captureSink = false;
  gSession.stopping.store(false, std::memory_order_release);
  gSession.state.store(LMM_CAPTURE_STARTING, std::memory_order_release);

  std::string_view target;
  if (!parseEndpointUid(device_uid, target, gSession.captureSink)) {
    gSession.state.store(LMM_CAPTURE_FAILED, std::memory_order_release);
    return false;
  }

  gSession.loop = pw_thread_loop_new("live-mix-master-capture", nullptr);
  if (!gSession.loop) {
    gSession.state.store(LMM_CAPTURE_FAILED, std::memory_order_release);
    return false;
  }

  pw_properties* properties = pw_properties_new(
      PW_KEY_APP_NAME, "LiveMixMaster",
      PW_KEY_MEDIA_TYPE, "Audio",
      PW_KEY_MEDIA_CATEGORY, "Capture",
      PW_KEY_MEDIA_ROLE, "Production",
      PW_KEY_TARGET_OBJECT, target.data(),
      nullptr);
  if (!properties) {
    destroyCaptureSession(false);
    gSession.state.store(LMM_CAPTURE_FAILED, std::memory_order_release);
    return false;
  }
  if (gSession.captureSink) {
    pw_properties_set(properties, PW_KEY_STREAM_CAPTURE_SINK, "true");
  }

  gSession.stream = pw_stream_new_simple(
      pw_thread_loop_get_loop(gSession.loop),
      "live-mix-master-capture",
      properties,
      &kStreamEvents,
      nullptr);
  if (!gSession.stream || pw_thread_loop_start(gSession.loop) < 0) {
    destroyCaptureSession(false);
    gSession.state.store(LMM_CAPTURE_FAILED, std::memory_order_release);
    return false;
  }

  std::array<std::uint8_t, 1024> parameterStorage{};
  spa_pod_builder builder = SPA_POD_BUILDER_INIT(
      parameterStorage.data(),
      parameterStorage.size());
  spa_audio_info_raw rawFormat{};
  rawFormat.format = SPA_AUDIO_FORMAT_F32;
  const spa_pod* parameters[] = {
      spa_format_audio_raw_build(
          &builder,
          SPA_PARAM_EnumFormat,
          &rawFormat),
  };

  gSession.startPending.store(true, std::memory_order_release);
  pw_thread_loop_lock(gSession.loop);
  const int connectResult = pw_stream_connect(
      gSession.stream,
      PW_DIRECTION_INPUT,
      PW_ID_ANY,
      static_cast<pw_stream_flags>(
          PW_STREAM_FLAG_AUTOCONNECT |
          PW_STREAM_FLAG_MAP_BUFFERS |
          PW_STREAM_FLAG_RT_PROCESS |
          PW_STREAM_FLAG_DONT_RECONNECT),
      parameters,
      1);
  if (connectResult >= 0) {
    for (std::uint32_t attempt = 0;
         attempt < kStartTimeoutSeconds &&
             gSession.state.load(std::memory_order_acquire) == LMM_CAPTURE_STARTING;
         ++attempt) {
      (void)pw_thread_loop_timed_wait(gSession.loop, 1);
    }
  }
  gSession.startPending.store(false, std::memory_order_release);
  pw_thread_loop_unlock(gSession.loop);

  const bool started = connectResult >= 0 &&
      gSession.state.load(std::memory_order_acquire) == LMM_CAPTURE_RUNNING &&
      gSession.sampleRate.load(std::memory_order_acquire) > 0.0;
  if (!started) {
    destroyCaptureSession(false);
    gSession.state.store(LMM_CAPTURE_FAILED, std::memory_order_release);
  }
  return started;
}

extern "C" void lmm_capture_stop() {
  destroyCaptureSession(true);
}

extern "C" bool lmm_capture_get_status(LmmCaptureStatus* out_status) {
  if (!out_status) return false;
  const std::uint64_t callbacks = gSession.callbackCount.load(std::memory_order_relaxed);
  const std::uint64_t totalDuration =
      gSession.callbackDurationNanoseconds.load(std::memory_order_relaxed);
  out_status->state = gSession.state.load(std::memory_order_acquire);
  out_status->sample_rate = gSession.sampleRate.load(std::memory_order_relaxed);
  out_status->buffer_frames = gSession.bufferFrames.load(std::memory_order_relaxed);
  out_status->input_channels = gSession.inputChannels.load(std::memory_order_relaxed);
  out_status->format_flags = gSession.formatFlags.load(std::memory_order_relaxed);
  out_status->callback_count = callbacks;
  out_status->xrun_count = gSession.xrunCount.load(std::memory_order_relaxed);
  out_status->average_callback_us = callbacks == 0
      ? 0.0
      : static_cast<double>(totalDuration) / static_cast<double>(callbacks) / 1000.0;
  out_status->max_callback_us = static_cast<double>(
      gSession.maxCallbackNanoseconds.load(std::memory_order_relaxed)) / 1000.0;
  return true;
}

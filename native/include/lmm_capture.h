#pragma once

#include <cstdint>

extern "C" {

enum LmmCaptureState : std::uint32_t {
  LMM_CAPTURE_IDLE = 0,
  LMM_CAPTURE_STARTING = 1,
  LMM_CAPTURE_RUNNING = 2,
  LMM_CAPTURE_DEVICE_REMOVED = 3,
  LMM_CAPTURE_FORMAT_CHANGED = 4,
  LMM_CAPTURE_FAILED = 5,
};

struct LmmCaptureFormat {
  double sample_rate;
  std::uint32_t buffer_frames;
  std::uint32_t input_channels;
  std::uint32_t format_flags;
};

struct LmmCaptureStatus {
  std::uint32_t state;
  double sample_rate;
  std::uint32_t buffer_frames;
  std::uint32_t input_channels;
  std::uint32_t format_flags;
  std::uint64_t callback_count;
  std::uint64_t xrun_count;
  double average_callback_us;
  double max_callback_us;
};

// Starts capture from the Core Audio input endpoint identified by stable UID.
// Returns only after the device IOProc has been created and started.
bool lmm_capture_start(const char* device_uid);

// Stops capture if active and returns the lifecycle state to idle.
void lmm_capture_stop();

// Reads a lock-free snapshot of capture lifecycle, negotiated format and
// callback telemetry.
bool lmm_capture_get_status(LmmCaptureStatus* out_status);

#if defined(LMM_BUILD_TESTING)

enum LmmCaptureTestEvent : std::uint32_t {
  LMM_CAPTURE_TEST_BEGIN = 1,
  LMM_CAPTURE_TEST_RUNNING = 2,
  LMM_CAPTURE_TEST_REMOVED = 3,
  LMM_CAPTURE_TEST_FORMAT_CHANGED = 4,
  LMM_CAPTURE_TEST_RECOVERED = 5,
  LMM_CAPTURE_TEST_STOPPED = 6,
  LMM_CAPTURE_TEST_FAILED = 7,
};

enum LmmPcmSampleKind : std::uint32_t {
  LMM_PCM_FLOAT32 = 1,
  LMM_PCM_FLOAT64 = 2,
  LMM_PCM_SIGNED16 = 3,
  LMM_PCM_SIGNED24 = 4,
  LMM_PCM_SIGNED32 = 5,
};

struct LmmPcmBufferView {
  const void* data;
  std::uint32_t channels;
  std::uint32_t bytes_per_frame;
};

struct LmmPcmFormat {
  std::uint32_t sample_kind;
  std::uint32_t big_endian;
  std::uint32_t total_channels;
  std::uint32_t bytes_per_sample;
};

// Deterministic hooks compiled only when BUILD_TESTING is enabled. They expose
// the same lifecycle and allocation-free PCM conversion used by the Core Audio
// callback without requiring a physical device on hosted CI.
void lmm_capture_test_reset();
bool lmm_capture_test_apply_event(
    std::uint32_t event,
    const LmmCaptureFormat* format);
void lmm_capture_test_record_callback(double duration_us, bool xrun);
bool lmm_capture_test_convert_pcm(
    const LmmPcmBufferView* buffers,
    std::uint32_t buffer_count,
    const LmmPcmFormat* format,
    std::uint32_t frames,
    float* out_stereo,
    std::uint32_t output_sample_capacity);

#endif

}  // extern "C"

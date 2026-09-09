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

struct LmmCaptureFormat {
  double sample_rate;
  std::uint32_t buffer_frames;
  std::uint32_t input_channels;
  std::uint32_t format_flags;
};

// Deterministic lifecycle hooks compiled only when BUILD_TESTING is enabled.
void lmm_capture_test_reset();
bool lmm_capture_test_apply_event(
    std::uint32_t event,
    const LmmCaptureFormat* format);
void lmm_capture_test_record_callback(double duration_us, bool xrun);

#endif

}  // extern "C"

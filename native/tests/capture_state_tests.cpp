#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <string>

#if defined(_WIN32)
#include <windows.h>
#else
#include <dlfcn.h>
#endif

namespace {

class DynamicLibrary {
 public:
  explicit DynamicLibrary(const char* path) {
#if defined(_WIN32)
    handle_ = LoadLibraryA(path);
#else
    handle_ = dlopen(path, RTLD_NOW | RTLD_LOCAL);
#endif
  }

  ~DynamicLibrary() {
#if defined(_WIN32)
    if (handle_) FreeLibrary(static_cast<HMODULE>(handle_));
#else
    if (handle_) dlclose(handle_);
#endif
  }

  bool isOpen() const { return handle_ != nullptr; }

  template <typename Fn>
  Fn symbol(const char* name) const {
#if defined(_WIN32)
    return reinterpret_cast<Fn>(GetProcAddress(static_cast<HMODULE>(handle_), name));
#else
    return reinterpret_cast<Fn>(dlsym(handle_, name));
#endif
  }

 private:
  void* handle_ = nullptr;
};

enum CaptureState : std::uint32_t {
  kIdle = 0,
  kStarting = 1,
  kRunning = 2,
  kDeviceRemoved = 3,
  kFormatChanged = 4,
  kFailed = 5,
};

enum TestEvent : std::uint32_t {
  kBegin = 1,
  kRunningEvent = 2,
  kRemoved = 3,
  kFormatChangedEvent = 4,
  kRecovered = 5,
  kStopped = 6,
  kFailedEvent = 7,
};

struct CaptureFormat {
  double sample_rate;
  std::uint32_t buffer_frames;
  std::uint32_t input_channels;
  std::uint32_t format_flags;
};

struct CaptureStatus {
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

struct Checks {
  int failures = 0;

  void expect(bool value, const std::string& label) {
    if (!value) {
      ++failures;
      std::cerr << "FAIL: " << label << '\n';
    }
  }

  void near(double actual, double expected, double tolerance, const std::string& label) {
    if (std::abs(actual - expected) > tolerance) {
      ++failures;
      std::cerr << "FAIL: " << label << " expected=" << expected << " actual=" << actual << '\n';
    }
  }
};

using StartFn = bool (*)(const char*);
using StopFn = void (*)();
using GetStatusFn = bool (*)(CaptureStatus*);
using TestResetFn = void (*)();
using TestApplyEventFn = bool (*)(std::uint32_t, const CaptureFormat*);
using TestRecordCallbackFn = void (*)(double, bool);

struct Api {
  StartFn start = nullptr;
  StopFn stop = nullptr;
  GetStatusFn status = nullptr;
  TestResetFn reset = nullptr;
  TestApplyEventFn applyEvent = nullptr;
  TestRecordCallbackFn recordCallback = nullptr;
};

template <typename Fn>
void bindRequired(const DynamicLibrary& library, const char* name, Fn& out, Checks& checks) {
  out = library.symbol<Fn>(name);
  if (!out) {
    ++checks.failures;
    std::cerr << "FAIL: required capture ABI symbol is missing: " << name << '\n';
  }
}

CaptureStatus status(const Api& api, Checks& checks, const std::string& label) {
  CaptureStatus result{};
  checks.expect(api.status(&result), label);
  return result;
}

}  // namespace

int main(int argc, char** argv) {
  if (argc != 2) {
    std::cerr << "usage: capture_state_tests <path-to-live-mixer-engine>\n";
    return EXIT_FAILURE;
  }

  Checks checks;
  DynamicLibrary library(argv[1]);
  checks.expect(library.isOpen(), "open native engine dynamic library");
  if (!library.isOpen()) return EXIT_FAILURE;

  Api api;
  bindRequired(library, "lmm_capture_start", api.start, checks);
  bindRequired(library, "lmm_capture_stop", api.stop, checks);
  bindRequired(library, "lmm_capture_get_status", api.status, checks);
  bindRequired(library, "lmm_capture_test_reset", api.reset, checks);
  bindRequired(library, "lmm_capture_test_apply_event", api.applyEvent, checks);
  bindRequired(library, "lmm_capture_test_record_callback", api.recordCallback, checks);
  if (checks.failures != 0) return EXIT_FAILURE;

  api.reset();
  auto current = status(api, checks, "read reset status");
  checks.expect(current.state == kIdle, "reset state is idle");
  checks.expect(current.callback_count == 0, "reset callback count is zero");
  checks.expect(current.xrun_count == 0, "reset xrun count is zero");

  checks.expect(api.applyEvent(kBegin, nullptr), "begin capture state transition");
  current = status(api, checks, "read starting status");
  checks.expect(current.state == kStarting, "begin transitions to starting");

  const CaptureFormat initial{44100.0, 128, 1, 0x29};
  checks.expect(api.applyEvent(kRunningEvent, &initial), "mark capture running");
  current = status(api, checks, "read running status");
  checks.expect(current.state == kRunning, "running event transitions to running");
  checks.near(current.sample_rate, 44100.0, 0.001, "negotiated sample rate is preserved");
  checks.expect(current.buffer_frames == 128, "negotiated buffer frames are preserved");
  checks.expect(current.input_channels == 1, "negotiated channel count is preserved");
  checks.expect(current.format_flags == 0x29, "negotiated format flags are preserved");

  api.recordCallback(125.0, false);
  api.recordCallback(375.0, true);
  current = status(api, checks, "read callback telemetry");
  checks.expect(current.callback_count == 2, "callback count is observable");
  checks.expect(current.xrun_count == 1, "xrun count is observable");
  checks.near(current.average_callback_us, 250.0, 0.001, "average callback duration is observable");
  checks.near(current.max_callback_us, 375.0, 0.001, "max callback duration is observable");

  checks.expect(api.applyEvent(kRemoved, nullptr), "inject device removal");
  current = status(api, checks, "read removed status");
  checks.expect(current.state == kDeviceRemoved, "device removal is distinct lifecycle state");

  const CaptureFormat changed{48000.0, 256, 2, 0x2d};
  checks.expect(api.applyEvent(kRecovered, &changed), "recover removed capture");
  current = status(api, checks, "read recovered status");
  checks.expect(current.state == kRunning, "recovery returns to running");
  checks.near(current.sample_rate, 48000.0, 0.001, "recovery records current sample rate");
  checks.expect(current.buffer_frames == 256, "recovery records current buffer frames");
  checks.expect(current.input_channels == 2, "recovery records current channel count");

  const CaptureFormat changedAgain{96000.0, 512, 2, 0x2d};
  checks.expect(api.applyEvent(kFormatChangedEvent, &changedAgain), "inject format change");
  current = status(api, checks, "read format-change status");
  checks.expect(current.state == kFormatChanged, "format change is distinct lifecycle state");
  checks.near(current.sample_rate, 96000.0, 0.001, "format-change metadata is preserved");
  checks.expect(current.buffer_frames == 512, "format-change buffer size is preserved");

  checks.expect(api.applyEvent(kRecovered, &changedAgain), "recover format-changed capture");
  current = status(api, checks, "read format recovery status");
  checks.expect(current.state == kRunning, "format recovery returns to running");

  checks.expect(api.applyEvent(kStopped, nullptr), "inject stop transition");
  current = status(api, checks, "read stopped status");
  checks.expect(current.state == kIdle, "stop returns capture to idle");

  api.reset();
  checks.expect(!api.start("__lmm_invalid_device_uid__"), "invalid device UID is rejected");
  current = status(api, checks, "read invalid-UID status");
  checks.expect(current.state == kFailed, "invalid UID transitions to failed");
  api.stop();

  if (checks.failures != 0) {
    std::cerr << checks.failures << " capture lifecycle checks failed\n";
    return EXIT_FAILURE;
  }
  std::cout << "capture lifecycle contract passed\n";
  return EXIT_SUCCESS;
}

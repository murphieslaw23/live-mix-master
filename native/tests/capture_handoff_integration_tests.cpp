#include "lmm_pcm_handoff.h"

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

struct Checks {
  int failures = 0;
  void expect(bool value, const std::string& label) {
    if (!value) {
      ++failures;
      std::cerr << "FAIL: " << label << '\n';
    }
  }
  void near(float actual, float expected, float tolerance, const std::string& label) {
    if (std::fabs(actual - expected) > tolerance) {
      ++failures;
      std::cerr << "FAIL: " << label << " expected=" << expected
                << " actual=" << actual << '\n';
    }
  }
};

using InitFn = bool (*)(std::uint32_t, std::uint32_t);
using AddChannelFn = bool (*)(const char*);
using SetFaderFn = bool (*)(const char*, float);
using BindFn = bool (*)(const char*);
using ForwardFn = bool (*)(const float*, std::size_t);
using PopFn = bool (*)(LmmPcmBlock*);

template <typename Fn>
void bindRequired(
    const DynamicLibrary& library,
    const char* name,
    Fn& out,
    Checks& checks) {
  out = library.symbol<Fn>(name);
  if (!out) {
    ++checks.failures;
    std::cerr << "FAIL: required capture handoff symbol is missing: " << name << '\n';
  }
}

}  // namespace

int main(int argc, char** argv) {
  if (argc != 2) {
    std::cerr << "usage: capture_handoff_integration_tests <path-to-live-mixer-engine>\n";
    return EXIT_FAILURE;
  }

  Checks checks;
  DynamicLibrary library(argv[1]);
  checks.expect(library.isOpen(), "open native engine dynamic library");
  if (!library.isOpen()) return EXIT_FAILURE;

  InitFn init = nullptr;
  AddChannelFn add_channel = nullptr;
  SetFaderFn set_fader = nullptr;
  BindFn bind_capture = nullptr;
  ForwardFn forward_stereo = nullptr;
  PopFn pop_recording = nullptr;
  PopFn pop_fingerprint = nullptr;

  bindRequired(library, "lmm_init", init, checks);
  bindRequired(library, "lmm_add_channel", add_channel, checks);
  bindRequired(library, "lmm_set_channel_fader", set_fader, checks);
  bindRequired(library, "lmm_bind_capture_channel", bind_capture, checks);
  bindRequired(library, "lmm_capture_test_forward_stereo", forward_stereo, checks);
  bindRequired(library, "lmm_pop_recording_pcm", pop_recording, checks);
  bindRequired(library, "lmm_pop_fingerprint_pcm", pop_fingerprint, checks);
  if (checks.failures != 0) return EXIT_FAILURE;

  checks.expect(init(48000, 256), "initialize engine");
  checks.expect(add_channel("capture-io"), "add IOProc capture channel");
  checks.expect(set_fader("capture-io", 1.0F), "set capture channel unity fader");
  checks.expect(bind_capture("capture-io"), "bind IOProc capture route");

  const float stereo[] = {0.25F, -0.5F, 2.0F, -2.0F};
  checks.expect(forward_stereo(stereo, 2), "capture forwarder accepts converted stereo");

  LmmPcmBlock recorder{};
  LmmPcmBlock fingerprint{};
  checks.expect(pop_recording(&recorder), "IOProc forwarder reaches recorder queue");
  checks.expect(pop_fingerprint(&fingerprint), "IOProc forwarder reaches fingerprint queue");
  checks.expect(recorder.frames == 2, "recorder receives forwarded frame count");
  checks.expect(fingerprint.frames == 2, "fingerprint receives forwarded frame count");
  checks.near(recorder.interleaved_stereo[0], 0.25F, 0.0001F, "first left sample preserved");
  checks.near(recorder.interleaved_stereo[1], -0.5F, 0.0001F, "first right sample preserved");
  checks.near(recorder.interleaved_stereo[2], 0.98F, 0.0001F, "hot left sample is post-limiter");
  checks.near(recorder.interleaved_stereo[3], -0.98F, 0.0001F, "hot right sample is post-limiter");
  checks.near(
      fingerprint.interleaved_stereo[2],
      recorder.interleaved_stereo[2],
      0.0001F,
      "fingerprint receives same post-master PCM");

  checks.expect(!forward_stereo(nullptr, 2), "capture forwarder rejects null PCM");
  checks.expect(!forward_stereo(stereo, 0), "capture forwarder rejects zero frames");

  if (checks.failures != 0) {
    std::cerr << checks.failures << " capture-to-handoff integration checks failed\n";
    return EXIT_FAILURE;
  }

  std::cout << "capture IOProc handoff contract passed\n";
  return EXIT_SUCCESS;
}

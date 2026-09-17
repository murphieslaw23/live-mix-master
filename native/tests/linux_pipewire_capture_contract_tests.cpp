#include "lmm_capture.h"

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

  void expect(bool condition, const std::string& label) {
    if (!condition) {
      ++failures;
      std::cerr << "FAIL: " << label << '\n';
    }
  }
};

using CaptureStartFn = bool (*)(const char*, std::uint32_t);
using CaptureStopFn = void (*)();
using CaptureStatusFn = bool (*)(LmmCaptureStatus*);

}  // namespace

int main(int argc, char** argv) {
  if (argc != 2) {
    std::cerr << "usage: linux_pipewire_capture_contract_tests <path-to-live-mixer-engine>\n";
    return EXIT_FAILURE;
  }

  Checks checks;
  DynamicLibrary library(argv[1]);
  checks.expect(library.isOpen(), "open native engine dynamic library");
  if (!library.isOpen()) return EXIT_FAILURE;

  const auto start = library.symbol<CaptureStartFn>("lmm_capture_start");
  const auto stop = library.symbol<CaptureStopFn>("lmm_capture_stop");
  const auto status = library.symbol<CaptureStatusFn>("lmm_capture_get_status");
  checks.expect(start != nullptr, "PipeWire capture start ABI is exported");
  checks.expect(stop != nullptr, "PipeWire capture stop ABI is exported");
  checks.expect(status != nullptr, "PipeWire capture status ABI is exported");
  if (checks.failures != 0) return EXIT_FAILURE;

  stop();
  LmmCaptureStatus current{};
  checks.expect(status(&current), "read initial PipeWire capture status");
  checks.expect(current.state == LMM_CAPTURE_IDLE, "stop leaves PipeWire capture idle");

  checks.expect(!start("", 0), "empty PipeWire endpoint UID is rejected without opening a device");
  checks.expect(status(&current), "read rejected endpoint status");
  checks.expect(current.state == LMM_CAPTURE_FAILED, "invalid endpoint moves capture to failed");

  checks.expect(!start("pipewire:source:", 0), "missing PipeWire node name is rejected");
  checks.expect(status(&current), "read missing-node status");
  checks.expect(current.state == LMM_CAPTURE_FAILED, "missing node keeps capture failed");

  stop();
  checks.expect(status(&current), "read stopped PipeWire status");
  checks.expect(current.state == LMM_CAPTURE_IDLE, "explicit stop recovers failed setup to idle");

  if (checks.failures != 0) {
    std::cerr << checks.failures << " PipeWire capture ABI checks failed\n";
    return EXIT_FAILURE;
  }
  std::cout << "PipeWire capture ABI contract passed\n";
  return EXIT_SUCCESS;
}

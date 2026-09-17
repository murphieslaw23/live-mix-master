#include "lmm_permissions.h"

#include <cstdint>
#include <cstdlib>
#include <iostream>

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

using PermissionStatusFn = std::uint32_t (*)();
using PermissionRequestFn = bool (*)();

bool isValidStatus(std::uint32_t value) {
  return value == LMM_AUDIO_PERMISSION_UNKNOWN ||
      value == LMM_AUDIO_PERMISSION_GRANTED ||
      value == LMM_AUDIO_PERMISSION_DENIED ||
      value == LMM_AUDIO_PERMISSION_RESTRICTED ||
      value == LMM_AUDIO_PERMISSION_UNAVAILABLE;
}

}  // namespace

int main(int argc, char** argv) {
  if (argc != 2) {
    std::cerr << "usage: audio_permission_contract_tests <path-to-live-mixer-engine>\n";
    return EXIT_FAILURE;
  }

  DynamicLibrary library(argv[1]);
  if (!library.isOpen()) {
    std::cerr << "FAIL: could not open native engine\n";
    return EXIT_FAILURE;
  }

  const auto permissionStatus =
      library.symbol<PermissionStatusFn>("lmm_audio_input_permission_status");
  const auto permissionRequest =
      library.symbol<PermissionRequestFn>("lmm_audio_input_permission_request");

  if (!permissionStatus || !permissionRequest) {
    std::cerr << "FAIL: required audio permission ABI symbols are missing\n";
    return EXIT_FAILURE;
  }

  const auto status = permissionStatus();
  if (!isValidStatus(status)) {
    std::cerr << "FAIL: permission ABI returned an invalid status value\n";
    return EXIT_FAILURE;
  }

  // Hosted CI must never trigger the macOS microphone consent dialog. The
  // request symbol is presence-checked only; physical-device acceptance owns
  // the actual consent flow.
  std::cout << "Audio input permission status: " << status << '\n';
  std::cout << "Audio permission ABI contract passed without requesting consent\n";
  return EXIT_SUCCESS;
}

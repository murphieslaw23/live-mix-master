#include "lmm_device_catalog.h"

#include <array>
#include <cstddef>
#include <cstdlib>
#include <cstring>
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

bool isNullTerminated(const char* value, std::size_t capacity) {
  return std::memchr(value, '\0', capacity) != nullptr;
}

bool bytesEqual(const void* left, const void* right, std::size_t bytes) {
  return std::memcmp(left, right, bytes) == 0;
}

using ListInputDevicesFn = std::size_t (*)(LmmInputDeviceRecord*, std::size_t);

}  // namespace

int main(int argc, char** argv) {
  if (argc != 2) {
    std::cerr << "usage: device_catalog_contract_tests <path-to-live-mixer-engine>\n";
    return EXIT_FAILURE;
  }

  Checks checks;
  DynamicLibrary library(argv[1]);
  checks.expect(library.isOpen(), "open native engine dynamic library");
  if (!library.isOpen()) return EXIT_FAILURE;

  const auto listInputDevices = library.symbol<ListInputDevicesFn>("lmm_list_input_devices");
  checks.expect(listInputDevices != nullptr, "required ABI symbol is present: lmm_list_input_devices");
  if (!listInputDevices) {
    std::cerr << "FAIL: required ABI symbol is missing: lmm_list_input_devices\n";
    return EXIT_FAILURE;
  }

  const std::size_t total = listInputDevices(nullptr, 0);
  std::cout << "Core Audio eligible input endpoint count: " << total << '\n';

  std::array<LmmInputDeviceRecord, 2> records{};
  std::memset(records.data(), 0xA5, sizeof(records));
  const LmmInputDeviceRecord sentinel = records[1];

  const std::size_t written = listInputDevices(records.data(), 1);
  checks.expect(written <= 1, "fill query never reports more records than capacity");
  checks.expect(
      bytesEqual(&records[1], &sentinel, sizeof(sentinel)),
      "fill query never writes beyond caller capacity");

  if (total == 0) {
    checks.expect(written == 0, "zero-endpoint infrastructure query writes zero records");
    std::cout << "No Core Audio input endpoints are visible on this host; this is infrastructure evidence only, not device-E2E success.\n";
  } else {
    checks.expect(written == 1, "non-empty catalog fills one record at capacity one");
    const auto& record = records[0];
    checks.expect(record.object_id != 0, "input endpoint exposes a non-zero Core Audio object ID");
    checks.expect(isNullTerminated(record.uid, LMM_DEVICE_UID_CAPACITY), "device UID is NUL terminated");
    checks.expect(record.uid[0] != '\0', "device UID is non-empty and stable-selection capable");
    checks.expect(isNullTerminated(record.name, LMM_DEVICE_NAME_CAPACITY), "device display name is NUL terminated");
    checks.expect(record.input_channels > 0, "catalog excludes zero-input-channel endpoints");
    checks.expect(record.nominal_sample_rate > 0.0, "device exposes a positive nominal sample rate");
    checks.expect(record.buffer_frame_size > 0, "device exposes a positive buffer frame size");
  }

  if (checks.failures != 0) {
    std::cerr << checks.failures << " device catalog contract checks failed\n";
    return EXIT_FAILURE;
  }

  std::cout << "Core Audio input catalog ABI/bounds contract passed\n";
  return EXIT_SUCCESS;
}

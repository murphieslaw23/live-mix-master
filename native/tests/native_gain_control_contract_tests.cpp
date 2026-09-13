#include <cmath>
#include <cstddef>
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

using InitFn = bool (*)(std::uint32_t, std::uint32_t);
using AddChannelFn = bool (*)(const char*);
using RemoveChannelFn = bool (*)(const char*);
using SetFaderFn = bool (*)(const char*, float);
using SetTrimDbFn = bool (*)(const char*, float);
using SetMasterGainDbFn = bool (*)(float);
using ProcessFn = bool (*)(const float* const*, std::size_t, float*, std::size_t);

template <typename Fn>
Fn requireSymbol(const DynamicLibrary& library, const char* name) {
  const auto symbol = library.symbol<Fn>(name);
  if (!symbol) {
    std::cerr << "FAIL: required ABI symbol is missing: " << name << '\n';
    std::exit(EXIT_FAILURE);
  }
  return symbol;
}
}  // namespace

int main(int argc, char** argv) {
  if (argc != 2) {
    std::cerr << "usage: native_gain_control_contract_tests <path-to-live-mixer-engine>\n";
    return EXIT_FAILURE;
  }

  DynamicLibrary library(argv[1]);
  if (!library.isOpen()) {
    std::cerr << "FAIL: native engine dynamic library could not be opened\n";
    return EXIT_FAILURE;
  }

  const auto init = requireSymbol<InitFn>(library, "lmm_init");
  const auto add = requireSymbol<AddChannelFn>(library, "lmm_add_channel");
  const auto remove = requireSymbol<RemoveChannelFn>(library, "lmm_remove_channel");
  const auto setFader = requireSymbol<SetFaderFn>(library, "lmm_set_channel_fader");
  const auto setTrimDb = requireSymbol<SetTrimDbFn>(library, "lmm_set_channel_trim_db");
  const auto setMasterGainDb = requireSymbol<SetMasterGainDbFn>(library, "lmm_set_master_gain_db");
  const auto process = requireSymbol<ProcessFn>(library, "lmm_process_interleaved_stereo");

  if (!init(48000, 128) || !add("gain-contract") ||
      !setFader("gain-contract", 1.0F) ||
      !setTrimDb("gain-contract", -6.0206F) ||
      !setMasterGainDb(-6.0206F)) {
    std::cerr << "FAIL: gain controls rejected valid configuration\n";
    return EXIT_FAILURE;
  }

  const float input[] = {1.0F, 1.0F};
  const float* channels[] = {input};
  float output[] = {0.0F, 0.0F};
  if (!process(channels, 1, output, 1)) {
    std::cerr << "FAIL: deterministic gain block was rejected\n";
    return EXIT_FAILURE;
  }

  constexpr float kExpected = 0.25F;
  constexpr float kTolerance = 1.0e-4F;
  if (std::abs(output[0] - kExpected) > kTolerance ||
      std::abs(output[1] - kExpected) > kTolerance) {
    std::cerr << "FAIL: trim/master gain must produce 0.25, got "
              << output[0] << ", " << output[1] << '\n';
    return EXIT_FAILURE;
  }

  if (!remove("gain-contract")) {
    std::cerr << "FAIL: gain-contract channel could not be removed\n";
    return EXIT_FAILURE;
  }

  std::cout << "native gain control contract passed\n";
  return EXIT_SUCCESS;
}

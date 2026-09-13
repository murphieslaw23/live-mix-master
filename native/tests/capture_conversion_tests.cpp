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

enum SampleKind : std::uint32_t {
  kFloat32 = 1,
  kFloat64 = 2,
  kSigned16 = 3,
  kSigned24 = 4,
  kSigned32 = 5,
};

struct PcmBufferView {
  const void* data;
  std::uint32_t channels;
  std::uint32_t bytes_per_frame;
};

struct PcmFormat {
  std::uint32_t sample_kind;
  std::uint32_t big_endian;
  std::uint32_t total_channels;
  std::uint32_t bytes_per_sample;
};

using ConvertFn = bool (*)(
    const PcmBufferView*,
    std::uint32_t,
    const PcmFormat*,
    std::uint32_t,
    float*,
    std::uint32_t);

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

}  // namespace

int main(int argc, char** argv) {
  if (argc != 2) {
    std::cerr << "usage: capture_conversion_tests <path-to-live-mixer-engine>\n";
    return EXIT_FAILURE;
  }

  Checks checks;
  DynamicLibrary library(argv[1]);
  checks.expect(library.isOpen(), "open native engine dynamic library");
  if (!library.isOpen()) return EXIT_FAILURE;

  const auto convert = library.symbol<ConvertFn>("lmm_capture_test_convert_pcm");
  checks.expect(convert != nullptr, "capture conversion test ABI is exported");
  if (!convert) return EXIT_FAILURE;

  {
    const float samples[] = {0.25F, -0.5F, 0.5F, -0.25F};
    const PcmBufferView buffers[] = {{samples, 2, 8}};
    const PcmFormat format{kFloat32, 0, 2, 4};
    float output[4]{};
    checks.expect(
        convert(buffers, 1, &format, 2, output, 4),
        "convert interleaved float32 stereo");
    checks.near(output[0], 0.25F, 0.00001F, "float32 stereo frame0 left");
    checks.near(output[1], -0.5F, 0.00001F, "float32 stereo frame0 right");
    checks.near(output[2], 0.5F, 0.00001F, "float32 stereo frame1 left");
    checks.near(output[3], -0.25F, 0.00001F, "float32 stereo frame1 right");
  }

  {
    const float mono[] = {0.125F, -0.375F};
    const PcmBufferView buffers[] = {{mono, 1, 4}};
    const PcmFormat format{kFloat32, 0, 1, 4};
    float output[4]{};
    checks.expect(
        convert(buffers, 1, &format, 2, output, 4),
        "duplicate mono float32 to stereo");
    checks.near(output[0], 0.125F, 0.00001F, "mono frame0 left");
    checks.near(output[1], 0.125F, 0.00001F, "mono frame0 right");
    checks.near(output[2], -0.375F, 0.00001F, "mono frame1 left");
    checks.near(output[3], -0.375F, 0.00001F, "mono frame1 right");
  }

  {
    const float left[] = {0.1F, 0.2F};
    const float right[] = {-0.1F, -0.2F};
    const PcmBufferView buffers[] = {
        {left, 1, 4},
        {right, 1, 4},
    };
    const PcmFormat format{kFloat32, 0, 2, 4};
    float output[4]{};
    checks.expect(
        convert(buffers, 2, &format, 2, output, 4),
        "convert non-interleaved float32 stereo");
    checks.near(output[0], 0.1F, 0.00001F, "planar frame0 left");
    checks.near(output[1], -0.1F, 0.00001F, "planar frame0 right");
    checks.near(output[2], 0.2F, 0.00001F, "planar frame1 left");
    checks.near(output[3], -0.2F, 0.00001F, "planar frame1 right");
  }

  {
    const std::int16_t samples[] = {16384, -16384, 32767, -32768};
    const PcmBufferView buffers[] = {{samples, 2, 4}};
    const PcmFormat format{kSigned16, 0, 2, 2};
    float output[4]{};
    checks.expect(
        convert(buffers, 1, &format, 2, output, 4),
        "convert signed16 stereo");
    checks.near(output[0], 0.5F, 0.0001F, "signed16 frame0 left");
    checks.near(output[1], -0.5F, 0.0001F, "signed16 frame0 right");
    checks.near(output[2], 32767.0F / 32768.0F, 0.0001F, "signed16 frame1 left");
    checks.near(output[3], -1.0F, 0.0001F, "signed16 frame1 right");
  }

  {
    const float samples[] = {0.0F, 0.0F};
    const PcmBufferView buffers[] = {{samples, 2, 8}};
    const PcmFormat unsupported{999, 0, 2, 4};
    float output[2]{};
    checks.expect(
        !convert(buffers, 1, &unsupported, 1, output, 2),
        "reject unsupported PCM sample kind");
    checks.expect(
        !convert(buffers, 1, &unsupported, 1, output, 1),
        "reject undersized stereo output capacity");
  }

  if (checks.failures != 0) {
    std::cerr << checks.failures << " capture conversion checks failed\n";
    return EXIT_FAILURE;
  }

  std::cout << "capture PCM conversion contract passed\n";
  return EXIT_SUCCESS;
}

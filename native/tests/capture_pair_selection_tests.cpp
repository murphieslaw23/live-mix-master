#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <iostream>

#include <dlfcn.h>

namespace {

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

using ConvertPairFn = bool (*)(
    const PcmBufferView*,
    std::uint32_t,
    const PcmFormat*,
    std::uint32_t,
    std::uint32_t,
    float*,
    std::uint32_t);

bool near(float actual, float expected) {
  return std::fabs(actual - expected) <= 0.00001F;
}

}  // namespace

int main(int argc, char** argv) {
  if (argc != 2) return EXIT_FAILURE;
  void* library = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
  if (!library) return EXIT_FAILURE;

  const auto convert = reinterpret_cast<ConvertPairFn>(
      dlsym(library, "lmm_capture_test_convert_pcm_pair"));
  if (!convert) {
    std::cerr << "missing lmm_capture_test_convert_pcm_pair\n";
    dlclose(library);
    return EXIT_FAILURE;
  }

  const float samples[] = {
      0.10F, 0.20F, 0.30F, 0.40F,
      0.50F, 0.60F, 0.70F, 0.80F,
  };
  const PcmBufferView buffers[] = {{samples, 4, 16}};
  const PcmFormat format{1, 0, 4, 4};
  float output[4]{};

  const bool ok = convert(buffers, 1, &format, 1, 2, output, 4);
  const bool correct = ok &&
      near(output[0], 0.30F) && near(output[1], 0.40F) &&
      near(output[2], 0.70F) && near(output[3], 0.80F);

  dlclose(library);
  if (!correct) {
    std::cerr << "selected CH 3-4 were not converted to stereo output\n";
    return EXIT_FAILURE;
  }

  std::cout << "capture channel-pair selection contract passed\n";
  return EXIT_SUCCESS;
}

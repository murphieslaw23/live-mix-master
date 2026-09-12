#include "dsp_wasm_abi.h"

#include <cmath>
#include <cstdint>
#include <iostream>
#include <stdexcept>
#include <string>

namespace {

void require(bool condition, const std::string& message) {
  if (!condition) {
    throw std::runtime_error(message);
  }
}

bool closeEnough(float actual, float expected) {
  return std::fabs(actual - expected) <= 1.0e-6F;
}

}  // namespace

int main() {
  static_assert(sizeof(LmmDspChannelConfigAbi) == 20);
  static_assert(sizeof(LmmDspChannelMeterAbi) == 24);
  static_assert(sizeof(LmmDspMasterMeterAbi) == 12);

  try {
    require(lmm_dsp_abi_version() == 1u, "ABI version mismatch");
    require(lmm_dsp_max_channels() == 8u, "max channel count mismatch");

    float output[4] = {};
    LmmDspChannelMeterAbi meters[2] = {};
    LmmDspMasterMeterAbi master{};
    std::uint32_t offsets[2] = {};
    LmmDspChannelConfigAbi configs[2] = {
        {1u, 0u, 0u, 1.0F, 0.5F},
        {1u, 0u, 0u, 1.0F, 1.0F},
    };

    require(
        lmm_dsp_process_stereo(nullptr, offsets, 1u, 2u, 1.0F, output, meters, &master) ==
            LMM_DSP_INVALID_ARGUMENT,
        "null configs must fail closed");
    require(
        lmm_dsp_process_stereo(configs, nullptr, 1u, 2u, 1.0F, output, meters, &master) ==
            LMM_DSP_INVALID_ARGUMENT,
        "null input pointer table must fail closed");
    require(
        lmm_dsp_process_stereo(configs, offsets, 9u, 2u, 1.0F, output, meters, &master) ==
            LMM_DSP_CHANNEL_LIMIT_EXCEEDED,
        "channel count above ABI ceiling must fail closed");

#ifdef LMM_DSP_ABI_TESTING
    const float nominalInput[4] = {1.0F, -1.0F, 0.5F, -0.5F};
    const float* nominalInputs[1] = {nominalInput};
    require(
        lmm_dsp_process_stereo_host(configs, nominalInputs, 1u, 2u, 1.0F, output, meters, &master) ==
            LMM_DSP_OK,
        "host nominal processing failed");
    require(closeEnough(output[0], 0.25F), "nominal left sample 0 mismatch");
    require(closeEnough(output[1], -0.25F), "nominal right sample 0 mismatch");
    require(closeEnough(output[2], 0.125F), "nominal left sample 1 mismatch");
    require(closeEnough(output[3], -0.125F), "nominal right sample 1 mismatch");
    require(meters[0].processed == 1u, "nominal meter processed mismatch");
    require(closeEnough(meters[0].peak_left, 0.25F), "nominal left peak mismatch");
    require(closeEnough(meters[0].peak_right, 0.25F), "nominal right peak mismatch");
    require(master.limiter_active == 0u, "nominal limiter state mismatch");

    const float soloInput[2] = {0.25F, 0.25F};
    const float otherInput[2] = {0.5F, 0.5F};
    const float* soloInputs[2] = {soloInput, otherInput};
    configs[0] = {1u, 0u, 1u, 1.0F, 1.0F};
    configs[1] = {1u, 0u, 0u, 1.0F, 1.0F};
    require(
        lmm_dsp_process_stereo_host(configs, soloInputs, 2u, 1u, 1.0F, output, meters, &master) ==
            LMM_DSP_OK,
        "host solo processing failed");
    require(closeEnough(output[0], 0.25F) && closeEnough(output[1], 0.25F), "solo output mismatch");
    require(meters[0].processed == 1u, "solo channel should be processed");
    require(meters[1].processed == 0u, "non-solo channel should be skipped");
#endif

    std::cout << "DSP Wasm ABI v1 tests passed\n";
  } catch (const std::exception& error) {
    std::cerr << error.what() << '\n';
    return 1;
  }

  return 0;
}

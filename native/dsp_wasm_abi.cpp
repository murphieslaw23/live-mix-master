#include "dsp_wasm_abi.h"

#include "dsp_kernel.hpp"

#include <array>
#include <cstddef>
#include <cstdint>

namespace {

std::int32_t processResolved(
    const LmmDspChannelConfigAbi* configs,
    const float* const* inputs,
    std::uint32_t channel_count,
    std::uint32_t frames,
    float master_gain,
    float* interleaved_output,
    LmmDspChannelMeterAbi* channel_meters,
    LmmDspMasterMeterAbi* master_meter) {
  if (channel_count > LMM_DSP_MAX_CHANNELS) {
    return LMM_DSP_CHANNEL_LIMIT_EXCEEDED;
  }
  if (interleaved_output == nullptr || master_meter == nullptr) {
    return LMM_DSP_INVALID_ARGUMENT;
  }
  if (channel_count > 0u &&
      (configs == nullptr || inputs == nullptr || channel_meters == nullptr)) {
    return LMM_DSP_INVALID_ARGUMENT;
  }

  std::array<lmm::DspChannelConfig, LMM_DSP_MAX_CHANNELS> native_configs{};
  std::array<const float*, LMM_DSP_MAX_CHANNELS> native_inputs{};
  std::array<lmm::DspChannelMeter, LMM_DSP_MAX_CHANNELS> native_meters{};

  for (std::uint32_t index = 0; index < channel_count; ++index) {
    native_configs[index] = lmm::DspChannelConfig{
        configs[index].active != 0u,
        configs[index].muted != 0u,
        configs[index].solo != 0u,
        configs[index].linear_trim,
        configs[index].fader,
    };
    native_inputs[index] = inputs[index];
  }

  const auto master = lmm::processStereoBlock(
      native_configs.data(),
      native_inputs.data(),
      static_cast<std::size_t>(channel_count),
      interleaved_output,
      static_cast<std::size_t>(frames),
      master_gain,
      native_meters.data());

  for (std::uint32_t index = 0; index < channel_count; ++index) {
    const auto& source = native_meters[index];
    channel_meters[index] = LmmDspChannelMeterAbi{
        source.processed ? 1u : 0u,
        source.peakLeft,
        source.peakRight,
        source.rmsLeft,
        source.rmsRight,
        source.clipping ? 1u : 0u,
    };
  }

  *master_meter = LmmDspMasterMeterAbi{
      master.peakLeft,
      master.peakRight,
      master.limiterActive ? 1u : 0u,
  };
  return LMM_DSP_OK;
}

}  // namespace

extern "C" std::uint32_t lmm_dsp_abi_version() {
  return LMM_DSP_ABI_VERSION;
}

extern "C" std::uint32_t lmm_dsp_max_channels() {
  return LMM_DSP_MAX_CHANNELS;
}

extern "C" std::int32_t lmm_dsp_process_stereo(
    const LmmDspChannelConfigAbi* configs,
    const std::uint32_t* input_ptrs,
    std::uint32_t channel_count,
    std::uint32_t frames,
    float master_gain,
    float* interleaved_output,
    LmmDspChannelMeterAbi* channel_meters,
    LmmDspMasterMeterAbi* master_meter) {
  if (channel_count > LMM_DSP_MAX_CHANNELS) {
    return LMM_DSP_CHANNEL_LIMIT_EXCEEDED;
  }
  if (interleaved_output == nullptr || master_meter == nullptr) {
    return LMM_DSP_INVALID_ARGUMENT;
  }
  if (channel_count > 0u &&
      (configs == nullptr || input_ptrs == nullptr || channel_meters == nullptr)) {
    return LMM_DSP_INVALID_ARGUMENT;
  }

  std::array<const float*, LMM_DSP_MAX_CHANNELS> resolved_inputs{};
  for (std::uint32_t index = 0; index < channel_count; ++index) {
    const auto offset = input_ptrs[index];
    if (offset == 0u || configs[index].active == 0u) {
      resolved_inputs[index] = nullptr;
      continue;
    }
#ifdef __EMSCRIPTEN__
    resolved_inputs[index] = reinterpret_cast<const float*>(static_cast<std::uintptr_t>(offset));
#else
    return LMM_DSP_INVALID_ARGUMENT;
#endif
  }

  return processResolved(
      configs,
      resolved_inputs.data(),
      channel_count,
      frames,
      master_gain,
      interleaved_output,
      channel_meters,
      master_meter);
}

#ifdef LMM_DSP_ABI_TESTING
std::int32_t lmm_dsp_process_stereo_host(
    const LmmDspChannelConfigAbi* configs,
    const float* const* inputs,
    std::uint32_t channel_count,
    std::uint32_t frames,
    float master_gain,
    float* interleaved_output,
    LmmDspChannelMeterAbi* channel_meters,
    LmmDspMasterMeterAbi* master_meter) {
  return processResolved(
      configs,
      inputs,
      channel_count,
      frames,
      master_gain,
      interleaved_output,
      channel_meters,
      master_meter);
}
#endif

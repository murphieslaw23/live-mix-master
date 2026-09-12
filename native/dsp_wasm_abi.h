#pragma once

#include <cstdint>

#define LMM_DSP_ABI_VERSION 1u
#define LMM_DSP_MAX_CHANNELS 8u

struct LmmDspChannelConfigAbi {
  std::uint32_t active;
  std::uint32_t muted;
  std::uint32_t solo;
  float linear_trim;
  float fader;
};

struct LmmDspChannelMeterAbi {
  std::uint32_t processed;
  float peak_left;
  float peak_right;
  float rms_left;
  float rms_right;
  std::uint32_t clipping;
};

struct LmmDspMasterMeterAbi {
  float peak_left;
  float peak_right;
  std::uint32_t limiter_active;
};

enum LmmDspStatus : std::int32_t {
  LMM_DSP_OK = 0,
  LMM_DSP_INVALID_ARGUMENT = 1,
  LMM_DSP_CHANNEL_LIMIT_EXCEEDED = 2,
};

static_assert(sizeof(LmmDspChannelConfigAbi) == 20);
static_assert(sizeof(LmmDspChannelMeterAbi) == 24);
static_assert(sizeof(LmmDspMasterMeterAbi) == 12);

extern "C" std::uint32_t lmm_dsp_abi_version();
extern "C" std::uint32_t lmm_dsp_max_channels();
extern "C" std::int32_t lmm_dsp_process_stereo(
    const LmmDspChannelConfigAbi* configs,
    const std::uint32_t* input_ptrs,
    std::uint32_t channel_count,
    std::uint32_t frames,
    float master_gain,
    float* interleaved_output,
    LmmDspChannelMeterAbi* channel_meters,
    LmmDspMasterMeterAbi* master_meter);

#ifdef LMM_DSP_ABI_TESTING
std::int32_t lmm_dsp_process_stereo_host(
    const LmmDspChannelConfigAbi* configs,
    const float* const* inputs,
    std::uint32_t channel_count,
    std::uint32_t frames,
    float master_gain,
    float* interleaved_output,
    LmmDspChannelMeterAbi* channel_meters,
    LmmDspMasterMeterAbi* master_meter);
#endif

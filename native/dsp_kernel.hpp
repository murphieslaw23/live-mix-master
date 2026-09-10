#pragma once

#include <algorithm>
#include <cmath>
#include <cstddef>

namespace lmm {

constexpr float kLimiterCeiling = 0.98F;

struct DspChannelConfig {
  bool active = false;
  bool muted = false;
  bool solo = false;
  float linearTrim = 1.0F;
  float fader = 0.8F;
};

struct DspChannelMeter {
  bool processed = false;
  float peakLeft = 0.0F;
  float peakRight = 0.0F;
  float rmsLeft = 0.0F;
  float rmsRight = 0.0F;
  bool clipping = false;
};

struct DspMasterMeter {
  float peakLeft = 0.0F;
  float peakRight = 0.0F;
  bool limiterActive = false;
};

inline DspMasterMeter processStereoBlock(
    const DspChannelConfig* configs,
    const float* const* channelInput,
    std::size_t channelCount,
    float* output,
    std::size_t frames,
    float masterGain,
    DspChannelMeter* channelMeters) {
  std::fill(output, output + frames * 2, 0.0F);

  bool soloed = false;
  for (std::size_t channelIndex = 0; channelIndex < channelCount; ++channelIndex) {
    channelMeters[channelIndex] = DspChannelMeter{};
    soloed = soloed || (configs[channelIndex].active && configs[channelIndex].solo);
  }

  for (std::size_t channelIndex = 0; channelIndex < channelCount; ++channelIndex) {
    const auto& config = configs[channelIndex];
    if (!config.active || config.muted || (soloed && !config.solo) || channelInput[channelIndex] == nullptr) {
      continue;
    }

    const float gain = config.linearTrim * config.fader * config.fader;
    float squareLeft = 0.0F;
    float squareRight = 0.0F;
    float peakLeft = 0.0F;
    float peakRight = 0.0F;

    for (std::size_t frame = 0; frame < frames; ++frame) {
      const float left = channelInput[channelIndex][frame * 2] * gain;
      const float right = channelInput[channelIndex][frame * 2 + 1] * gain;
      output[frame * 2] += left;
      output[frame * 2 + 1] += right;
      peakLeft = std::max(peakLeft, std::abs(left));
      peakRight = std::max(peakRight, std::abs(right));
      squareLeft += left * left;
      squareRight += right * right;
    }

    auto& meter = channelMeters[channelIndex];
    meter.processed = true;
    meter.peakLeft = peakLeft;
    meter.peakRight = peakRight;
    meter.rmsLeft = frames == 0 ? 0.0F : std::sqrt(squareLeft / static_cast<float>(frames));
    meter.rmsRight = frames == 0 ? 0.0F : std::sqrt(squareRight / static_cast<float>(frames));
    meter.clipping = peakLeft >= 1.0F || peakRight >= 1.0F;
  }

  DspMasterMeter master;
  for (std::size_t frame = 0; frame < frames; ++frame) {
    float left = output[frame * 2] * masterGain;
    float right = output[frame * 2 + 1] * masterGain;

    if (std::abs(left) > kLimiterCeiling || std::abs(right) > kLimiterCeiling) {
      master.limiterActive = true;
      left = std::clamp(left, -kLimiterCeiling, kLimiterCeiling);
      right = std::clamp(right, -kLimiterCeiling, kLimiterCeiling);
    }

    output[frame * 2] = left;
    output[frame * 2 + 1] = right;
    master.peakLeft = std::max(master.peakLeft, std::abs(left));
    master.peakRight = std::max(master.peakRight, std::abs(right));
  }

  return master;
}

}  // namespace lmm

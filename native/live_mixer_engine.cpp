#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>
#include <cstdint>
#include <cstring>

// LiveMixMaster native prototype. This file exports a small C ABI for Dart FFI.
// A production backend must attach platform-specific capture devices and replace
// the temporary source reads with a lock-free per-channel PCM ring buffer.

namespace lmm {
constexpr size_t kMaxChannels = 16;
constexpr float kLimiterCeiling = 0.98F;

struct Meter {
  std::atomic<float> peakLeft {0};
  std::atomic<float> peakRight {0};
  std::atomic<float> rmsLeft {0};
  std::atomic<float> rmsRight {0};
  std::atomic<bool> clipping {false};
};

struct Channel {
  bool active = false;
  bool muted = false;
  bool solo = false;
  char id[64] {};
  std::atomic<float> linearTrim {1};
  std::atomic<float> fader {0.8F};
  Meter meter;
};

struct Master {
  std::atomic<float> gain {1};
  std::atomic<float> truePeakLeft {0};
  std::atomic<float> truePeakRight {0};
  std::atomic<bool> limiterActive {false};
};

class Engine {
 public:
  bool init(uint32_t sampleRate, uint32_t framesPerBuffer) {
    sampleRate_ = sampleRate;
    framesPerBuffer_ = framesPerBuffer;
    return sampleRate_ > 0 && framesPerBuffer_ > 0;
  }

  bool addChannel(const char* id) {
    if (!id) return false;
    for (auto& channel : channels_) {
      if (!channel.active) {
        std::strncpy(channel.id, id, sizeof(channel.id) - 1);
        channel.active = true;
        channel.muted = false;
        channel.solo = false;
        channel.linearTrim.store(1);
        channel.fader.store(0.8F);
        return true;
      }
    }
    return false;
  }

  bool removeChannel(const char* id) {
    if (!id) return false;
    for (auto& channel : channels_) {
      if (channel.active && std::strncmp(channel.id, id, sizeof(channel.id)) == 0) {
        channel.active = false;
        return true;
      }
    }
    return false;
  }

  // Called only by the audio callback. `channelInput` must point to an
  // interleaved stereo block already fetched from the selected source.
  void sumBlock(const float* const* channelInput, float* masterOutput, size_t frames) {
    std::fill(masterOutput, masterOutput + frames * 2, 0.0F);
    bool soloed = false;
    for (const auto& channel : channels_) soloed |= channel.active && channel.solo;

    for (size_t c = 0; c < channels_.size(); ++c) {
      auto& channel = channels_[c];
      if (!channel.active || channel.muted || (soloed && !channel.solo) || !channelInput[c]) continue;
      const float gain = channel.linearTrim.load(std::memory_order_relaxed) *
          std::pow(channel.fader.load(std::memory_order_relaxed), 2.0F);
      float squareL = 0, squareR = 0, peakL = 0, peakR = 0;
      for (size_t frame = 0; frame < frames; ++frame) {
        const float left = channelInput[c][frame * 2] * gain;
        const float right = channelInput[c][frame * 2 + 1] * gain;
        masterOutput[frame * 2] += left;
        masterOutput[frame * 2 + 1] += right;
        peakL = std::max(peakL, std::abs(left)); peakR = std::max(peakR, std::abs(right));
        squareL += left * left; squareR += right * right;
      }
      channel.meter.peakLeft.store(peakL, std::memory_order_relaxed);
      channel.meter.peakRight.store(peakR, std::memory_order_relaxed);
      channel.meter.rmsLeft.store(std::sqrt(squareL / frames), std::memory_order_relaxed);
      channel.meter.rmsRight.store(std::sqrt(squareR / frames), std::memory_order_relaxed);
      channel.meter.clipping.store(peakL >= 1 || peakR >= 1, std::memory_order_relaxed);
    }
    limit(masterOutput, frames);
  }

  void limit(float* output, size_t frames) {
    float peakL = 0, peakR = 0;
    bool limited = false;
    const float gain = master_.gain.load(std::memory_order_relaxed);
    for (size_t frame = 0; frame < frames; ++frame) {
      float left = output[frame * 2] * gain;
      float right = output[frame * 2 + 1] * gain;
      if (std::abs(left) > kLimiterCeiling || std::abs(right) > kLimiterCeiling) {
        limited = true;
        left = std::clamp(left, -kLimiterCeiling, kLimiterCeiling);
        right = std::clamp(right, -kLimiterCeiling, kLimiterCeiling);
      }
      output[frame * 2] = left; output[frame * 2 + 1] = right;
      peakL = std::max(peakL, std::abs(left)); peakR = std::max(peakR, std::abs(right));
    }
    master_.truePeakLeft.store(peakL, std::memory_order_relaxed);
    master_.truePeakRight.store(peakR, std::memory_order_relaxed);
    master_.limiterActive.store(limited, std::memory_order_relaxed);
  }

 private:
  uint32_t sampleRate_ = 48000;
  uint32_t framesPerBuffer_ = 256;
  std::array<Channel, kMaxChannels> channels_ {};
  Master master_;
};

Engine engine;
}  // namespace lmm

extern "C" {
bool lmm_init(uint32_t sampleRate, uint32_t framesPerBuffer) { return lmm::engine.init(sampleRate, framesPerBuffer); }
bool lmm_add_channel(const char* id) { return lmm::engine.addChannel(id); }
bool lmm_remove_channel(const char* id) { return lmm::engine.removeChannel(id); }
}

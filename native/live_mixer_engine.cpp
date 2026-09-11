#include "dsp_kernel.hpp"

#include <array>
#include <atomic>
#include <cstddef>
#include <cstdint>
#include <cstring>

// LiveMixMaster native prototype. This file exports a small C ABI for Dart FFI.
// A production backend must attach platform-specific capture devices and replace
// the temporary source reads with a lock-free per-channel PCM ring buffer.

namespace lmm {
constexpr std::size_t kMaxChannels = 16;

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
  void sumBlock(const float* const* channelInput, float* masterOutput, std::size_t frames) {
    std::array<DspChannelConfig, kMaxChannels> configs {};
    std::array<DspChannelMeter, kMaxChannels> meters {};

    for (std::size_t channelIndex = 0; channelIndex < channels_.size(); ++channelIndex) {
      const auto& channel = channels_[channelIndex];
      configs[channelIndex] = DspChannelConfig{
          channel.active,
          channel.muted,
          channel.solo,
          channel.linearTrim.load(std::memory_order_relaxed),
          channel.fader.load(std::memory_order_relaxed),
      };
    }

    const auto masterMeter = processStereoBlock(
        configs.data(),
        channelInput,
        configs.size(),
        masterOutput,
        frames,
        master_.gain.load(std::memory_order_relaxed),
        meters.data());

    for (std::size_t channelIndex = 0; channelIndex < channels_.size(); ++channelIndex) {
      if (!meters[channelIndex].processed) {
        continue;
      }
      auto& meter = channels_[channelIndex].meter;
      const auto& result = meters[channelIndex];
      meter.peakLeft.store(result.peakLeft, std::memory_order_relaxed);
      meter.peakRight.store(result.peakRight, std::memory_order_relaxed);
      meter.rmsLeft.store(result.rmsLeft, std::memory_order_relaxed);
      meter.rmsRight.store(result.rmsRight, std::memory_order_relaxed);
      meter.clipping.store(result.clipping, std::memory_order_relaxed);
    }

    master_.truePeakLeft.store(masterMeter.peakLeft, std::memory_order_relaxed);
    master_.truePeakRight.store(masterMeter.peakRight, std::memory_order_relaxed);
    master_.limiterActive.store(masterMeter.limiterActive, std::memory_order_relaxed);
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

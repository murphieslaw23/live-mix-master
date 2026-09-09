#include "lmm_engine.h"

#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>

// LiveMixMaster native engine core. Platform capture backends feed preallocated
// interleaved stereo blocks into this engine. The callback path performs only
// bounded arithmetic and atomic snapshot writes; device discovery/capture and
// PCM fan-out are added in later Issue #3 tasks.

namespace lmm {
constexpr std::size_t kMaxChannels = 16;
constexpr float kLimiterCeiling = 0.98F;

struct Meter {
  std::atomic<float> peakLeft{0};
  std::atomic<float> peakRight{0};
  std::atomic<float> rmsLeft{0};
  std::atomic<float> rmsRight{0};
  std::atomic<bool> clipping{false};
};

struct Channel {
  std::atomic<bool> active{false};
  std::atomic<bool> muted{false};
  std::atomic<bool> solo{false};
  char id[64]{};
  std::atomic<float> linearTrim{1};
  std::atomic<float> fader{0.8F};
  Meter meter;
};

struct Master {
  std::atomic<float> gain{1};
  std::atomic<float> truePeakLeft{0};
  std::atomic<float> truePeakRight{0};
  std::atomic<bool> limiterActive{false};
};

class Engine {
 public:
  bool init(std::uint32_t sampleRate, std::uint32_t framesPerBuffer) {
    if (sampleRate == 0 || framesPerBuffer == 0) return false;
    sampleRate_ = sampleRate;
    framesPerBuffer_ = framesPerBuffer;
    master_.gain.store(1.0F, std::memory_order_relaxed);
    master_.truePeakLeft.store(0.0F, std::memory_order_relaxed);
    master_.truePeakRight.store(0.0F, std::memory_order_relaxed);
    master_.limiterActive.store(false, std::memory_order_relaxed);
    return true;
  }

  bool addChannel(const char* id) {
    if (!id || id[0] == '\0') return false;
    if (findChannel(id) != nullptr) return false;

    for (auto& channel : channels_) {
      if (!channel.active.load(std::memory_order_acquire)) {
        std::strncpy(channel.id, id, sizeof(channel.id) - 1);
        channel.id[sizeof(channel.id) - 1] = '\0';
        channel.muted.store(false, std::memory_order_relaxed);
        channel.solo.store(false, std::memory_order_relaxed);
        channel.linearTrim.store(1.0F, std::memory_order_relaxed);
        channel.fader.store(0.8F, std::memory_order_relaxed);
        clearMeter(channel.meter);
        channel.active.store(true, std::memory_order_release);
        return true;
      }
    }
    return false;
  }

  bool removeChannel(const char* id) {
    Channel* channel = findChannel(id);
    if (!channel) return false;
    channel->active.store(false, std::memory_order_release);
    channel->muted.store(false, std::memory_order_relaxed);
    channel->solo.store(false, std::memory_order_relaxed);
    clearMeter(channel->meter);
    return true;
  }

  bool setFader(const char* id, float normalizedFader) {
    if (!std::isfinite(normalizedFader) || normalizedFader < 0.0F || normalizedFader > 1.0F) {
      return false;
    }
    Channel* channel = findChannel(id);
    if (!channel) return false;
    channel->fader.store(normalizedFader, std::memory_order_relaxed);
    return true;
  }

  bool setMuted(const char* id, bool muted) {
    Channel* channel = findChannel(id);
    if (!channel) return false;
    channel->muted.store(muted, std::memory_order_relaxed);
    return true;
  }

  bool setSolo(const char* id, bool solo) {
    Channel* channel = findChannel(id);
    if (!channel) return false;
    channel->solo.store(solo, std::memory_order_relaxed);
    return true;
  }

  // Called only by the native audio callback. Inputs are already normalized to
  // float32 interleaved stereo by the platform capture layer.
  bool sumBlock(
      const float* const* channelInput,
      std::size_t channelCount,
      float* masterOutput,
      std::size_t frames) {
    if (!masterOutput || frames == 0 || (channelCount > 0 && !channelInput)) return false;
    if (channelCount > channels_.size()) return false;

    std::fill(masterOutput, masterOutput + frames * 2, 0.0F);

    bool soloed = false;
    for (const auto& channel : channels_) {
      soloed |= channel.active.load(std::memory_order_acquire) &&
          channel.solo.load(std::memory_order_relaxed);
    }

    for (std::size_t c = 0; c < channels_.size(); ++c) {
      auto& channel = channels_[c];
      if (!channel.active.load(std::memory_order_acquire)) continue;

      const bool muted = channel.muted.load(std::memory_order_relaxed);
      const bool solo = channel.solo.load(std::memory_order_relaxed);
      const float* input = c < channelCount ? channelInput[c] : nullptr;
      if (muted || (soloed && !solo) || !input) {
        clearMeter(channel.meter);
        continue;
      }

      const float fader = channel.fader.load(std::memory_order_relaxed);
      const float gain = channel.linearTrim.load(std::memory_order_relaxed) * fader * fader;
      float squareL = 0.0F;
      float squareR = 0.0F;
      float peakL = 0.0F;
      float peakR = 0.0F;

      for (std::size_t frame = 0; frame < frames; ++frame) {
        const float left = input[frame * 2] * gain;
        const float right = input[frame * 2 + 1] * gain;
        masterOutput[frame * 2] += left;
        masterOutput[frame * 2 + 1] += right;
        peakL = std::max(peakL, std::abs(left));
        peakR = std::max(peakR, std::abs(right));
        squareL += left * left;
        squareR += right * right;
      }

      channel.meter.peakLeft.store(peakL, std::memory_order_relaxed);
      channel.meter.peakRight.store(peakR, std::memory_order_relaxed);
      channel.meter.rmsLeft.store(std::sqrt(squareL / static_cast<float>(frames)), std::memory_order_relaxed);
      channel.meter.rmsRight.store(std::sqrt(squareR / static_cast<float>(frames)), std::memory_order_relaxed);
      channel.meter.clipping.store(peakL >= 1.0F || peakR >= 1.0F, std::memory_order_relaxed);
    }

    limit(masterOutput, frames);
    return true;
  }

  bool getChannelMeter(const char* id, LmmChannelMeterSnapshot* outSnapshot) const {
    if (!outSnapshot) return false;
    const Channel* channel = findChannel(id);
    if (!channel) return false;

    outSnapshot->peak_left = channel->meter.peakLeft.load(std::memory_order_relaxed);
    outSnapshot->peak_right = channel->meter.peakRight.load(std::memory_order_relaxed);
    outSnapshot->rms_left = channel->meter.rmsLeft.load(std::memory_order_relaxed);
    outSnapshot->rms_right = channel->meter.rmsRight.load(std::memory_order_relaxed);
    outSnapshot->clipping = channel->meter.clipping.load(std::memory_order_relaxed) ? 1 : 0;
    outSnapshot->reserved[0] = 0;
    outSnapshot->reserved[1] = 0;
    outSnapshot->reserved[2] = 0;
    return true;
  }

  bool getMasterMeter(LmmMasterMeterSnapshot* outSnapshot) const {
    if (!outSnapshot) return false;
    outSnapshot->true_peak_left = master_.truePeakLeft.load(std::memory_order_relaxed);
    outSnapshot->true_peak_right = master_.truePeakRight.load(std::memory_order_relaxed);
    outSnapshot->limiter_active = master_.limiterActive.load(std::memory_order_relaxed) ? 1 : 0;
    outSnapshot->reserved[0] = 0;
    outSnapshot->reserved[1] = 0;
    outSnapshot->reserved[2] = 0;
    return true;
  }

 private:
  static void clearMeter(Meter& meter) {
    meter.peakLeft.store(0.0F, std::memory_order_relaxed);
    meter.peakRight.store(0.0F, std::memory_order_relaxed);
    meter.rmsLeft.store(0.0F, std::memory_order_relaxed);
    meter.rmsRight.store(0.0F, std::memory_order_relaxed);
    meter.clipping.store(false, std::memory_order_relaxed);
  }

  Channel* findChannel(const char* id) {
    if (!id) return nullptr;
    for (auto& channel : channels_) {
      if (channel.active.load(std::memory_order_acquire) && std::strcmp(channel.id, id) == 0) {
        return &channel;
      }
    }
    return nullptr;
  }

  const Channel* findChannel(const char* id) const {
    if (!id) return nullptr;
    for (const auto& channel : channels_) {
      if (channel.active.load(std::memory_order_acquire) && std::strcmp(channel.id, id) == 0) {
        return &channel;
      }
    }
    return nullptr;
  }

  void limit(float* output, std::size_t frames) {
    float peakL = 0.0F;
    float peakR = 0.0F;
    bool limited = false;
    const float gain = master_.gain.load(std::memory_order_relaxed);

    for (std::size_t frame = 0; frame < frames; ++frame) {
      float left = output[frame * 2] * gain;
      float right = output[frame * 2 + 1] * gain;
      if (std::abs(left) > kLimiterCeiling || std::abs(right) > kLimiterCeiling) {
        limited = true;
        left = std::clamp(left, -kLimiterCeiling, kLimiterCeiling);
        right = std::clamp(right, -kLimiterCeiling, kLimiterCeiling);
      }
      output[frame * 2] = left;
      output[frame * 2 + 1] = right;
      peakL = std::max(peakL, std::abs(left));
      peakR = std::max(peakR, std::abs(right));
    }

    master_.truePeakLeft.store(peakL, std::memory_order_relaxed);
    master_.truePeakRight.store(peakR, std::memory_order_relaxed);
    master_.limiterActive.store(limited, std::memory_order_relaxed);
  }

  std::uint32_t sampleRate_ = 48000;
  std::uint32_t framesPerBuffer_ = 256;
  std::array<Channel, kMaxChannels> channels_{};
  Master master_;
};

Engine engine;
}  // namespace lmm

extern "C" {
bool lmm_init(std::uint32_t sampleRate, std::uint32_t framesPerBuffer) {
  return lmm::engine.init(sampleRate, framesPerBuffer);
}

bool lmm_add_channel(const char* id) {
  return lmm::engine.addChannel(id);
}

bool lmm_remove_channel(const char* id) {
  return lmm::engine.removeChannel(id);
}

bool lmm_set_channel_fader(const char* id, float normalizedFader) {
  return lmm::engine.setFader(id, normalizedFader);
}

bool lmm_set_channel_muted(const char* id, bool muted) {
  return lmm::engine.setMuted(id, muted);
}

bool lmm_set_channel_solo(const char* id, bool solo) {
  return lmm::engine.setSolo(id, solo);
}

bool lmm_process_interleaved_stereo(
    const float* const* channelInput,
    std::size_t channelCount,
    float* masterOutput,
    std::size_t frames) {
  return lmm::engine.sumBlock(channelInput, channelCount, masterOutput, frames);
}

bool lmm_get_channel_meter(const char* id, LmmChannelMeterSnapshot* outSnapshot) {
  return lmm::engine.getChannelMeter(id, outSnapshot);
}

bool lmm_get_master_meter(LmmMasterMeterSnapshot* outSnapshot) {
  return lmm::engine.getMasterMeter(outSnapshot);
}
}

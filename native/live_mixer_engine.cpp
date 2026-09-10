#include "lmm_engine.h"
#include "lmm_pcm_handoff.h"
#include "spsc_ring_buffer.h"

#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <limits>

// LiveMixMaster native engine core. Platform capture backends feed preallocated
// interleaved stereo blocks into this engine. The callback path performs only
// bounded arithmetic, atomic state reads/writes, and bounded SPSC queue writes.

namespace lmm {
constexpr std::size_t kMaxChannels = 16;
constexpr float kLimiterCeiling = 0.98F;
constexpr std::size_t kPcmQueueCapacity = 64;
constexpr std::size_t kInvalidChannelIndex = std::numeric_limits<std::size_t>::max();

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
  std::atomic<std::uint64_t> generation{0};
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
    boundCaptureIndex_.store(kInvalidChannelIndex, std::memory_order_release);
    boundCaptureGeneration_.store(0, std::memory_order_relaxed);
    nextPcmSequence_.store(1, std::memory_order_relaxed);
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
        channel.generation.fetch_add(1, std::memory_order_relaxed);
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
    channel->generation.fetch_add(1, std::memory_order_relaxed);
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

  bool bindCaptureChannel(const char* id) {
    const std::size_t index = findChannelIndex(id);
    if (index == kInvalidChannelIndex) return false;
    const auto generation = channels_[index].generation.load(std::memory_order_acquire);
    boundCaptureGeneration_.store(generation, std::memory_order_relaxed);
    boundCaptureIndex_.store(index, std::memory_order_release);
    return true;
  }

  bool processBoundCaptureStereo(const float* input, std::size_t frames) {
    if (!input || frames == 0) return false;

    const std::size_t boundIndex = boundCaptureIndex_.load(std::memory_order_acquire);
    if (!captureBindingIsValid(boundIndex)) return false;

    std::array<const float*, kMaxChannels> inputs{};
    std::array<float, LMM_PCM_BLOCK_FRAMES * 2> masterOutput{};

    std::size_t offset = 0;
    while (offset < frames) {
      if (!captureBindingIsValid(boundIndex)) return false;

      const std::size_t chunkFrames = std::min<std::size_t>(
          LMM_PCM_BLOCK_FRAMES,
          frames - offset);
      inputs.fill(nullptr);
      inputs[boundIndex] = input + offset * 2;

      if (!sumBlock(
              inputs.data(),
              inputs.size(),
              masterOutput.data(),
              chunkFrames)) {
        return false;
      }

      LmmPcmBlock block{};
      block.frames = static_cast<std::uint32_t>(chunkFrames);
      block.sequence = nextPcmSequence_.fetch_add(1, std::memory_order_relaxed);
      std::copy_n(
          masterOutput.data(),
          chunkFrames * 2,
          block.interleaved_stereo);

      // Queue saturation is observable but never blocks or fails the callback.
      recordingQueue_.tryPush(block);
      fingerprintQueue_.tryPush(block);
      offset += chunkFrames;
    }

    return true;
  }

  bool popRecordingPcm(LmmPcmBlock* outBlock) {
    return outBlock != nullptr && recordingQueue_.tryPop(*outBlock);
  }

  bool popFingerprintPcm(LmmPcmBlock* outBlock) {
    return outBlock != nullptr && fingerprintQueue_.tryPop(*outBlock);
  }

  bool getPcmHandoffStatus(LmmPcmHandoffStatus* outStatus) const {
    if (!outStatus) return false;
    outStatus->recorder_queue_depth = recordingQueue_.size();
    outStatus->fingerprint_queue_depth = fingerprintQueue_.size();
    outStatus->recorder_rejected_blocks = recordingQueue_.rejectedWrites();
    outStatus->fingerprint_rejected_blocks = fingerprintQueue_.rejectedWrites();
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

  std::size_t findChannelIndex(const char* id) const {
    if (!id) return kInvalidChannelIndex;
    for (std::size_t index = 0; index < channels_.size(); ++index) {
      const auto& channel = channels_[index];
      if (channel.active.load(std::memory_order_acquire) &&
          std::strcmp(channel.id, id) == 0) {
        return index;
      }
    }
    return kInvalidChannelIndex;
  }

  bool captureBindingIsValid(std::size_t index) const {
    if (index >= channels_.size()) return false;
    const auto& channel = channels_[index];
    if (!channel.active.load(std::memory_order_acquire)) return false;
    return channel.generation.load(std::memory_order_acquire) ==
        boundCaptureGeneration_.load(std::memory_order_relaxed);
  }

  Channel* findChannel(const char* id) {
    const std::size_t index = findChannelIndex(id);
    return index == kInvalidChannelIndex ? nullptr : &channels_[index];
  }

  const Channel* findChannel(const char* id) const {
    const std::size_t index = findChannelIndex(id);
    return index == kInvalidChannelIndex ? nullptr : &channels_[index];
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
  std::atomic<std::size_t> boundCaptureIndex_{kInvalidChannelIndex};
  std::atomic<std::uint64_t> boundCaptureGeneration_{0};
  std::atomic<std::uint64_t> nextPcmSequence_{1};
  SpscRingBuffer<LmmPcmBlock, kPcmQueueCapacity> recordingQueue_;
  SpscRingBuffer<LmmPcmBlock, kPcmQueueCapacity> fingerprintQueue_;
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

bool lmm_bind_capture_channel(const char* channelId) {
  return lmm::engine.bindCaptureChannel(channelId);
}

bool lmm_process_bound_capture_stereo(
    const float* interleavedStereo,
    std::size_t frames) {
  return lmm::engine.processBoundCaptureStereo(interleavedStereo, frames);
}

bool lmm_pop_recording_pcm(LmmPcmBlock* outBlock) {
  return lmm::engine.popRecordingPcm(outBlock);
}

bool lmm_pop_fingerprint_pcm(LmmPcmBlock* outBlock) {
  return lmm::engine.popFingerprintPcm(outBlock);
}

bool lmm_get_pcm_handoff_status(LmmPcmHandoffStatus* outStatus) {
  return lmm::engine.getPcmHandoffStatus(outStatus);
}
}

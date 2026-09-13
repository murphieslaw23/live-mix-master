#include "dsp_kernel.hpp"
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

namespace lmm {
namespace {
constexpr std::size_t kMaxChannels = 16;
constexpr std::size_t kPcmQueueCapacity = 64;
constexpr std::size_t kInvalidChannelIndex = std::numeric_limits<std::size_t>::max();

float dbToLinear(float db) {
  return std::pow(10.0F, db / 20.0F);
}

struct Meter {
  std::atomic<float> peakLeft{0.0F};
  std::atomic<float> peakRight{0.0F};
  std::atomic<float> rmsLeft{0.0F};
  std::atomic<float> rmsRight{0.0F};
  std::atomic<bool> clipping{false};
};

struct Channel {
  std::atomic<bool> active{false};
  std::atomic<bool> muted{false};
  std::atomic<bool> solo{false};
  std::atomic<std::uint64_t> generation{0};
  char id[64]{};
  std::atomic<float> linearTrim{1.0F};
  std::atomic<float> fader{0.8F};
  Meter meter;
};

struct Master {
  std::atomic<float> gain{1.0F};
  std::atomic<float> peakLeft{0.0F};
  std::atomic<float> peakRight{0.0F};
  std::atomic<bool> limiterActive{false};
};
}  // namespace

class Engine {
 public:
  bool init(std::uint32_t sampleRate, std::uint32_t framesPerBuffer) {
    if (sampleRate == 0 || framesPerBuffer == 0) return false;
    sampleRate_ = sampleRate;
    framesPerBuffer_ = framesPerBuffer;
    master_.gain.store(1.0F, std::memory_order_relaxed);
    master_.peakLeft.store(0.0F, std::memory_order_relaxed);
    master_.peakRight.store(0.0F, std::memory_order_relaxed);
    master_.limiterActive.store(false, std::memory_order_relaxed);
    boundCaptureIndex_.store(kInvalidChannelIndex, std::memory_order_release);
    boundCaptureGeneration_.store(0, std::memory_order_relaxed);
    nextPcmSequence_.store(1, std::memory_order_relaxed);
    return true;
  }

  bool addChannel(const char* id) {
    if (!id || id[0] == '\0' || findChannel(id) != nullptr) return false;
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
    const std::size_t index = findChannelIndex(id);
    if (index == kInvalidChannelIndex) return false;
    auto& channel = channels_[index];
    channel.active.store(false, std::memory_order_release);
    channel.generation.fetch_add(1, std::memory_order_relaxed);
    channel.muted.store(false, std::memory_order_relaxed);
    channel.solo.store(false, std::memory_order_relaxed);
    clearMeter(channel.meter);
    if (boundCaptureIndex_.load(std::memory_order_acquire) == index) {
      boundCaptureIndex_.store(kInvalidChannelIndex, std::memory_order_release);
      boundCaptureGeneration_.store(0, std::memory_order_relaxed);
    }
    return true;
  }

  bool setFader(const char* id, float value) {
    if (!std::isfinite(value) || value < 0.0F || value > 1.0F) return false;
    Channel* channel = findChannel(id);
    if (!channel) return false;
    channel->fader.store(value, std::memory_order_relaxed);
    return true;
  }

  bool setTrimDb(const char* id, float db) {
    if (!std::isfinite(db)) return false;
    Channel* channel = findChannel(id);
    if (!channel) return false;
    channel->linearTrim.store(dbToLinear(db), std::memory_order_relaxed);
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

  bool setMasterGainDb(float db) {
    if (!std::isfinite(db)) return false;
    master_.gain.store(dbToLinear(db), std::memory_order_relaxed);
    return true;
  }

  bool sumBlock(
      const float* const* channelInput,
      std::size_t channelCount,
      float* masterOutput,
      std::size_t frames) {
    if (!masterOutput || frames == 0 || channelCount > channels_.size()) return false;
    if (channelCount > 0 && !channelInput) return false;

    std::array<DspChannelConfig, kMaxChannels> configs{};
    std::array<DspChannelMeter, kMaxChannels> meters{};
    for (std::size_t index = 0; index < channelCount; ++index) {
      const auto& channel = channels_[index];
      configs[index] = DspChannelConfig{
          channel.active.load(std::memory_order_acquire),
          channel.muted.load(std::memory_order_relaxed),
          channel.solo.load(std::memory_order_relaxed),
          channel.linearTrim.load(std::memory_order_relaxed),
          channel.fader.load(std::memory_order_relaxed),
      };
    }

    const auto masterMeter = processStereoBlock(
        configs.data(),
        channelInput,
        channelCount,
        masterOutput,
        frames,
        master_.gain.load(std::memory_order_relaxed),
        meters.data());

    for (std::size_t index = 0; index < channelCount; ++index) {
      auto& meter = channels_[index].meter;
      if (!meters[index].processed) {
        clearMeter(meter);
        continue;
      }
      meter.peakLeft.store(meters[index].peakLeft, std::memory_order_relaxed);
      meter.peakRight.store(meters[index].peakRight, std::memory_order_relaxed);
      meter.rmsLeft.store(meters[index].rmsLeft, std::memory_order_relaxed);
      meter.rmsRight.store(meters[index].rmsRight, std::memory_order_relaxed);
      meter.clipping.store(meters[index].clipping, std::memory_order_relaxed);
    }

    master_.peakLeft.store(masterMeter.peakLeft, std::memory_order_relaxed);
    master_.peakRight.store(masterMeter.peakRight, std::memory_order_relaxed);
    master_.limiterActive.store(masterMeter.limiterActive, std::memory_order_relaxed);
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
    std::array<float, LMM_PCM_BLOCK_FRAMES * 2> output{};
    std::size_t offset = 0;
    while (offset < frames) {
      if (!captureBindingIsValid(boundIndex)) return false;
      const std::size_t chunkFrames = std::min<std::size_t>(LMM_PCM_BLOCK_FRAMES, frames - offset);
      inputs.fill(nullptr);
      inputs[boundIndex] = input + offset * 2;
      if (!sumBlock(inputs.data(), inputs.size(), output.data(), chunkFrames)) return false;

      LmmPcmBlock block{};
      block.frames = static_cast<std::uint32_t>(chunkFrames);
      block.sequence = nextPcmSequence_.fetch_add(1, std::memory_order_relaxed);
      std::copy_n(output.data(), chunkFrames * 2, block.interleaved_stereo);
      recordingQueue_.tryPush(block);
      fingerprintQueue_.tryPush(block);
      offset += chunkFrames;
    }
    return true;
  }

  bool getChannelMeter(const char* id, LmmChannelMeterSnapshot* out) const {
    if (!out) return false;
    const Channel* channel = findChannel(id);
    if (!channel) return false;
    out->peak_left = channel->meter.peakLeft.load(std::memory_order_relaxed);
    out->peak_right = channel->meter.peakRight.load(std::memory_order_relaxed);
    out->rms_left = channel->meter.rmsLeft.load(std::memory_order_relaxed);
    out->rms_right = channel->meter.rmsRight.load(std::memory_order_relaxed);
    out->clipping = channel->meter.clipping.load(std::memory_order_relaxed) ? 1 : 0;
    out->reserved[0] = out->reserved[1] = out->reserved[2] = 0;
    return true;
  }

  bool getMasterMeter(LmmMasterMeterSnapshot* out) const {
    if (!out) return false;
    out->true_peak_left = master_.peakLeft.load(std::memory_order_relaxed);
    out->true_peak_right = master_.peakRight.load(std::memory_order_relaxed);
    out->limiter_active = master_.limiterActive.load(std::memory_order_relaxed) ? 1 : 0;
    out->reserved[0] = out->reserved[1] = out->reserved[2] = 0;
    return true;
  }

  bool popRecordingPcm(LmmPcmBlock* out) {
    return out != nullptr && recordingQueue_.tryPop(*out);
  }

  bool popFingerprintPcm(LmmPcmBlock* out) {
    return out != nullptr && fingerprintQueue_.tryPop(*out);
  }

  bool getPcmHandoffStatus(LmmPcmHandoffStatus* out) const {
    if (!out) return false;
    out->recorder_queue_depth = recordingQueue_.size();
    out->fingerprint_queue_depth = fingerprintQueue_.size();
    out->recorder_rejected_blocks = recordingQueue_.rejectedWrites();
    out->fingerprint_rejected_blocks = fingerprintQueue_.rejectedWrites();
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

  Channel* findChannel(const char* id) {
    const auto index = findChannelIndex(id);
    return index == kInvalidChannelIndex ? nullptr : &channels_[index];
  }

  const Channel* findChannel(const char* id) const {
    const auto index = findChannelIndex(id);
    return index == kInvalidChannelIndex ? nullptr : &channels_[index];
  }

  bool captureBindingIsValid(std::size_t index) const {
    if (index >= channels_.size()) return false;
    const auto& channel = channels_[index];
    return channel.active.load(std::memory_order_acquire) &&
        channel.generation.load(std::memory_order_acquire) ==
            boundCaptureGeneration_.load(std::memory_order_relaxed);
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
bool lmm_add_channel(const char* id) { return lmm::engine.addChannel(id); }
bool lmm_remove_channel(const char* id) { return lmm::engine.removeChannel(id); }
bool lmm_set_channel_fader(const char* id, float value) { return lmm::engine.setFader(id, value); }
bool lmm_set_channel_trim_db(const char* id, float db) { return lmm::engine.setTrimDb(id, db); }
bool lmm_set_channel_muted(const char* id, bool value) { return lmm::engine.setMuted(id, value); }
bool lmm_set_channel_solo(const char* id, bool value) { return lmm::engine.setSolo(id, value); }
bool lmm_set_master_gain_db(float db) { return lmm::engine.setMasterGainDb(db); }
bool lmm_process_interleaved_stereo(
    const float* const* channelInput,
    std::size_t channelCount,
    float* masterOutput,
    std::size_t frames) {
  return lmm::engine.sumBlock(channelInput, channelCount, masterOutput, frames);
}
bool lmm_get_channel_meter(const char* id, LmmChannelMeterSnapshot* out) {
  return lmm::engine.getChannelMeter(id, out);
}
bool lmm_get_master_meter(LmmMasterMeterSnapshot* out) {
  return lmm::engine.getMasterMeter(out);
}
bool lmm_bind_capture_channel(const char* id) { return lmm::engine.bindCaptureChannel(id); }
bool lmm_process_bound_capture_stereo(const float* input, std::size_t frames) {
  return lmm::engine.processBoundCaptureStereo(input, frames);
}
bool lmm_pop_recording_pcm(LmmPcmBlock* out) { return lmm::engine.popRecordingPcm(out); }
bool lmm_pop_fingerprint_pcm(LmmPcmBlock* out) { return lmm::engine.popFingerprintPcm(out); }
bool lmm_get_pcm_handoff_status(LmmPcmHandoffStatus* out) {
  return lmm::engine.getPcmHandoffStatus(out);
}
}

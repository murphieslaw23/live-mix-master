#pragma once

#include <cstddef>
#include <cstdint>

extern "C" {

struct LmmChannelMeterSnapshot {
  float peak_left;
  float peak_right;
  float rms_left;
  float rms_right;
  std::uint8_t clipping;
  std::uint8_t reserved[3];
};

struct LmmMasterMeterSnapshot {
  float true_peak_left;
  float true_peak_right;
  std::uint8_t limiter_active;
  std::uint8_t reserved[3];
};

bool lmm_init(std::uint32_t sample_rate, std::uint32_t frames_per_buffer);
bool lmm_add_channel(const char* id);
bool lmm_remove_channel(const char* id);

// Task 1 ABI contract. These declarations intentionally precede their
// implementation so the RED test run proves the existing prototype is missing
// the required real-time control and deterministic block-processing surface.
bool lmm_set_channel_fader(const char* id, float normalized_fader);
bool lmm_set_channel_muted(const char* id, bool muted);
bool lmm_set_channel_solo(const char* id, bool solo);
bool lmm_process_interleaved_stereo(
    const float* const* channel_input,
    std::size_t channel_count,
    float* master_output,
    std::size_t frames);
bool lmm_get_channel_meter(const char* id, LmmChannelMeterSnapshot* out_snapshot);
bool lmm_get_master_meter(LmmMasterMeterSnapshot* out_snapshot);

}  // extern "C"

#pragma once

#include <cstddef>
#include <cstdint>

extern "C" {

constexpr std::size_t LMM_PCM_BLOCK_FRAMES = 256;

struct LmmPcmBlock {
  std::uint32_t frames;
  std::uint32_t reserved;
  std::uint64_t sequence;
  float interleaved_stereo[LMM_PCM_BLOCK_FRAMES * 2];
};

struct LmmPcmHandoffStatus {
  std::uint64_t recorder_queue_depth;
  std::uint64_t fingerprint_queue_depth;
  std::uint64_t recorder_rejected_blocks;
  std::uint64_t fingerprint_rejected_blocks;
};

// Binds the single active native capture route to an existing dynamic mixer
// channel. Removing that channel invalidates the binding until explicitly set
// again, preventing stale capture from reaching a recycled channel slot.
bool lmm_bind_capture_channel(const char* channel_id);

// Real-time-safe boundary used by the platform capture callback after source
// conversion. It applies mixer controls + master limiting, then performs
// bounded non-blocking fan-out of post-master PCM.
bool lmm_process_bound_capture_stereo(
    const float* interleaved_stereo,
    std::size_t frames);

bool lmm_pop_recording_pcm(LmmPcmBlock* out_block);
bool lmm_pop_fingerprint_pcm(LmmPcmBlock* out_block);
bool lmm_get_pcm_handoff_status(LmmPcmHandoffStatus* out_status);

}  // extern "C"

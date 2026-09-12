#include "lmm_capture.h"
#include "lmm_device_catalog.h"
#include "lmm_engine.h"
#include "lmm_pcm_handoff.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <iomanip>
#include <iostream>
#include <string>
#include <thread>
#include <vector>

namespace {

constexpr const char* kProbeChannelId = "issue3-acceptance-probe";

const char* captureStateName(std::uint32_t state) {
  switch (state) {
    case LMM_CAPTURE_IDLE:
      return "idle";
    case LMM_CAPTURE_STARTING:
      return "starting";
    case LMM_CAPTURE_RUNNING:
      return "running";
    case LMM_CAPTURE_DEVICE_REMOVED:
      return "device_removed";
    case LMM_CAPTURE_FORMAT_CHANGED:
      return "format_changed";
    case LMM_CAPTURE_FAILED:
      return "failed";
    default:
      return "unknown";
  }
}

std::vector<LmmInputDeviceRecord> listDevices() {
  const std::size_t count = lmm_list_input_devices(nullptr, 0);
  std::vector<LmmInputDeviceRecord> records(count);
  if (count == 0) return records;

  const std::size_t written = lmm_list_input_devices(records.data(), records.size());
  records.resize(std::min(written, records.size()));
  return records;
}

void printDevices(const std::vector<LmmInputDeviceRecord>& records) {
  std::cout << "eligible_input_count=" << records.size() << '\n';
  for (std::size_t index = 0; index < records.size(); ++index) {
    const auto& device = records[index];
    std::cout << "device[" << index << "].name=" << device.name << '\n'
              << "device[" << index << "].uid=" << device.uid << '\n'
              << "device[" << index << "].input_channels=" << device.input_channels << '\n'
              << "device[" << index << "].nominal_sample_rate="
              << device.nominal_sample_rate << '\n'
              << "device[" << index << "].buffer_frames="
              << device.buffer_frame_size << '\n';
  }
}

const LmmInputDeviceRecord* findByUid(
    const std::vector<LmmInputDeviceRecord>& records,
    const std::string& uid) {
  for (const auto& record : records) {
    if (uid == record.uid) return &record;
  }
  return nullptr;
}

int captureFor(const LmmInputDeviceRecord& device, int seconds) {
  if (device.nominal_sample_rate <= 0.0 || device.buffer_frame_size == 0 ||
      device.input_channels == 0) {
    std::cerr << "probe_error=invalid_device_format\n";
    return 3;
  }

  const auto sampleRate = static_cast<std::uint32_t>(
      std::llround(device.nominal_sample_rate));
  if (!lmm_init(sampleRate, device.buffer_frame_size) ||
      !lmm_add_channel(kProbeChannelId) ||
      !lmm_set_channel_fader(kProbeChannelId, 1.0F) ||
      !lmm_bind_capture_channel(kProbeChannelId)) {
    std::cerr << "probe_error=engine_setup_failed\n";
    return 4;
  }

  if (!lmm_capture_start(device.uid)) {
    std::cerr << "probe_error=capture_start_failed\n";
    lmm_remove_channel(kProbeChannelId);
    return 5;
  }

  std::uint64_t recorderFrames = 0;
  std::uint64_t fingerprintFrames = 0;
  LmmCaptureStatus capture{};
  const auto deadline = std::chrono::steady_clock::now() +
      std::chrono::seconds(seconds);

  while (std::chrono::steady_clock::now() < deadline) {
    LmmPcmBlock block{};
    while (lmm_pop_recording_pcm(&block)) {
      recorderFrames += block.frames;
    }
    while (lmm_pop_fingerprint_pcm(&block)) {
      fingerprintFrames += block.frames;
    }

    if (!lmm_capture_get_status(&capture)) {
      std::cerr << "probe_error=capture_status_unavailable\n";
      break;
    }
    if (capture.state != LMM_CAPTURE_RUNNING) break;
    std::this_thread::sleep_for(std::chrono::milliseconds(20));
  }

  LmmPcmBlock block{};
  while (lmm_pop_recording_pcm(&block)) recorderFrames += block.frames;
  while (lmm_pop_fingerprint_pcm(&block)) fingerprintFrames += block.frames;

  LmmCaptureStatus finalCapture{};
  LmmPcmHandoffStatus handoff{};
  LmmChannelMeterSnapshot channelMeter{};
  LmmMasterMeterSnapshot masterMeter{};
  const bool haveCapture = lmm_capture_get_status(&finalCapture);
  const bool haveHandoff = lmm_get_pcm_handoff_status(&handoff);
  const bool haveChannelMeter =
      lmm_get_channel_meter(kProbeChannelId, &channelMeter);
  const bool haveMasterMeter = lmm_get_master_meter(&masterMeter);

  lmm_capture_stop();
  lmm_remove_channel(kProbeChannelId);

  if (!haveCapture || !haveHandoff) {
    std::cerr << "probe_error=final_telemetry_unavailable\n";
    return 6;
  }

  std::cout << std::fixed << std::setprecision(3)
            << "capture_state=" << captureStateName(finalCapture.state) << '\n'
            << "sample_rate=" << finalCapture.sample_rate << '\n'
            << "buffer_frames=" << finalCapture.buffer_frames << '\n'
            << "input_channels=" << finalCapture.input_channels << '\n'
            << "callback_count=" << finalCapture.callback_count << '\n'
            << "xrun_count=" << finalCapture.xrun_count << '\n'
            << "average_callback_us=" << finalCapture.average_callback_us << '\n'
            << "maximum_callback_us=" << finalCapture.max_callback_us << '\n'
            << "recorder_queue_depth=" << handoff.recorder_queue_depth << '\n'
            << "fingerprint_queue_depth=" << handoff.fingerprint_queue_depth << '\n'
            << "recorder_rejected_blocks=" << handoff.recorder_rejected_blocks << '\n'
            << "fingerprint_rejected_blocks="
            << handoff.fingerprint_rejected_blocks << '\n'
            << "recorder_drained_frames=" << recorderFrames << '\n'
            << "fingerprint_drained_frames=" << fingerprintFrames << '\n';

  if (haveChannelMeter) {
    std::cout << "channel_peak_left=" << channelMeter.peak_left << '\n'
              << "channel_peak_right=" << channelMeter.peak_right << '\n'
              << "channel_rms_left=" << channelMeter.rms_left << '\n'
              << "channel_rms_right=" << channelMeter.rms_right << '\n'
              << "channel_clipping=" << static_cast<int>(channelMeter.clipping) << '\n';
  }
  if (haveMasterMeter) {
    // ABI names are historical. These values are current post-limiter sample
    // peaks, not oversampled standards-based dBTP measurements.
    std::cout << "master_post_limiter_sample_peak_left="
              << masterMeter.true_peak_left << '\n'
              << "master_post_limiter_sample_peak_right="
              << masterMeter.true_peak_right << '\n'
              << "limiter_active=" << static_cast<int>(masterMeter.limiter_active)
              << '\n';
  }

  if (finalCapture.state != LMM_CAPTURE_RUNNING ||
      finalCapture.callback_count == 0 || recorderFrames == 0 ||
      fingerprintFrames == 0) {
    std::cerr << "probe_error=no_complete_live_pcm_path\n";
    return 7;
  }

  return 0;
}

void usage(const char* executable) {
  std::cerr << "usage: " << executable << " [--list | --capture <stable-uid> [seconds]]\n";
}

}  // namespace

int main(int argc, char** argv) {
  const auto records = listDevices();

  if (argc == 1 || (argc == 2 && std::strcmp(argv[1], "--list") == 0)) {
    printDevices(records);
    return 0;
  }

  if (argc >= 3 && std::strcmp(argv[1], "--capture") == 0) {
    int seconds = 10;
    if (argc >= 4) {
      const long parsed = std::strtol(argv[3], nullptr, 10);
      if (parsed < 1 || parsed > 3600) {
        std::cerr << "probe_error=invalid_duration\n";
        return 2;
      }
      seconds = static_cast<int>(parsed);
    }

    const std::string uid(argv[2]);
    const auto* device = findByUid(records, uid);
    if (!device) {
      std::cerr << "probe_error=stable_uid_not_found\n";
      printDevices(records);
      return 2;
    }
    return captureFor(*device, seconds);
  }

  usage(argv[0]);
  return 2;
}

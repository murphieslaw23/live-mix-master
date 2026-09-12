#include "lmm_engine.h"
#include "lmm_pcm_handoff.h"

#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <string>
#include <vector>

#if defined(_WIN32)
#include <windows.h>
#else
#include <dlfcn.h>
#endif

namespace {

class DynamicLibrary {
 public:
  explicit DynamicLibrary(const char* path) {
#if defined(_WIN32)
    handle_ = LoadLibraryA(path);
#else
    handle_ = dlopen(path, RTLD_NOW | RTLD_LOCAL);
#endif
  }

  ~DynamicLibrary() {
#if defined(_WIN32)
    if (handle_) FreeLibraryA(static_cast<HMODULE>(handle_));
#else
    if (handle_) dlclose(handle_);
#endif
  }

  bool isOpen() const { return handle_ != nullptr; }

  template <typename Fn>
  Fn symbol(const char* name) const {
#if defined(_WIN32)
    return reinterpret_cast<Fn>(GetProcAddress(static_cast<HMODULE>(handle_), name));
#else
    return reinterpret_cast<Fn>(dlsym(handle_, name));
#endif
  }

 private:
  void* handle_ = nullptr;
};

struct Checks {
  int failures = 0;

  void expect(bool value, const std::string& label) {
    if (!value) {
      ++failures;
      std::cerr << "FAIL: " << label << '\n';
    }
  }

  void near(float actual, float expected, float tolerance, const std::string& label) {
    if (std::fabs(actual - expected) > tolerance) {
      ++failures;
      std::cerr << "FAIL: " << label << " expected=" << expected
                << " actual=" << actual << '\n';
    }
  }
};

using InitFn = bool (*)(std::uint32_t, std::uint32_t);
using AddChannelFn = bool (*)(const char*);
using RemoveChannelFn = bool (*)(const char*);
using SetFaderFn = bool (*)(const char*, float);
using SetBoolFn = bool (*)(const char*, bool);
using BindFn = bool (*)(const char*);
using ProcessFn = bool (*)(const float*, std::size_t);
using PopFn = bool (*)(LmmPcmBlock*);
using StatusFn = bool (*)(LmmPcmHandoffStatus*);

template <typename Fn>
void bindRequired(
    const DynamicLibrary& library,
    const char* name,
    Fn& out,
    Checks& checks) {
  out = library.symbol<Fn>(name);
  if (!out) {
    ++checks.failures;
    std::cerr << "FAIL: required PCM handoff ABI symbol is missing: " << name << '\n';
  }
}

void expectStereoSample(
    const LmmPcmBlock& block,
    std::size_t frame,
    float left,
    float right,
    Checks& checks,
    const std::string& label) {
  checks.near(block.interleaved_stereo[frame * 2], left, 0.0001F, label + " left");
  checks.near(block.interleaved_stereo[frame * 2 + 1], right, 0.0001F, label + " right");
}

}  // namespace

int main(int argc, char** argv) {
  if (argc != 2) {
    std::cerr << "usage: pcm_handoff_tests <path-to-live-mixer-engine>\n";
    return EXIT_FAILURE;
  }

  Checks checks;
  DynamicLibrary library(argv[1]);
  checks.expect(library.isOpen(), "open native engine dynamic library");
  if (!library.isOpen()) return EXIT_FAILURE;

  InitFn init = nullptr;
  AddChannelFn add_channel = nullptr;
  RemoveChannelFn remove_channel = nullptr;
  SetFaderFn set_fader = nullptr;
  SetBoolFn set_muted = nullptr;
  SetBoolFn set_solo = nullptr;
  BindFn bind_capture = nullptr;
  ProcessFn process_capture = nullptr;
  PopFn pop_recording = nullptr;
  PopFn pop_fingerprint = nullptr;
  StatusFn get_status = nullptr;

  bindRequired(library, "lmm_init", init, checks);
  bindRequired(library, "lmm_add_channel", add_channel, checks);
  bindRequired(library, "lmm_remove_channel", remove_channel, checks);
  bindRequired(library, "lmm_set_channel_fader", set_fader, checks);
  bindRequired(library, "lmm_set_channel_muted", set_muted, checks);
  bindRequired(library, "lmm_set_channel_solo", set_solo, checks);
  bindRequired(library, "lmm_bind_capture_channel", bind_capture, checks);
  bindRequired(library, "lmm_process_bound_capture_stereo", process_capture, checks);
  bindRequired(library, "lmm_pop_recording_pcm", pop_recording, checks);
  bindRequired(library, "lmm_pop_fingerprint_pcm", pop_fingerprint, checks);
  bindRequired(library, "lmm_get_pcm_handoff_status", get_status, checks);
  if (checks.failures != 0) return EXIT_FAILURE;

  checks.expect(init(48000, 256), "initialize engine");
  checks.expect(add_channel("capture-a"), "add captured source channel");
  checks.expect(set_fader("capture-a", 1.0F), "set unity capture fader");
  checks.expect(bind_capture("capture-a"), "bind capture to dynamic mixer channel");
  checks.expect(!bind_capture("missing-channel"), "reject binding to missing mixer channel");

  // 300 frames proves bounded chunking into the fixed 256-frame service blocks.
  std::vector<float> input(300 * 2);
  for (std::size_t frame = 0; frame < 300; ++frame) {
    input[frame * 2] = 0.5F;
    input[frame * 2 + 1] = -0.25F;
  }
  checks.expect(process_capture(input.data(), 300), "process 300 captured frames");

  LmmPcmBlock recorder_first{};
  LmmPcmBlock recorder_second{};
  LmmPcmBlock fingerprint_first{};
  LmmPcmBlock fingerprint_second{};
  checks.expect(pop_recording(&recorder_first), "pop first recorder block");
  checks.expect(pop_recording(&recorder_second), "pop second recorder block");
  checks.expect(pop_fingerprint(&fingerprint_first), "pop first fingerprint block");
  checks.expect(pop_fingerprint(&fingerprint_second), "pop second fingerprint block");
  checks.expect(recorder_first.frames == 256, "first recorder block is capacity-sized");
  checks.expect(recorder_second.frames == 44, "second recorder block contains remainder");
  checks.expect(fingerprint_first.frames == 256, "first fingerprint block is capacity-sized");
  checks.expect(fingerprint_second.frames == 44, "second fingerprint block contains remainder");
  checks.expect(recorder_first.sequence == fingerprint_first.sequence, "paired first block sequence matches");
  checks.expect(recorder_second.sequence == fingerprint_second.sequence, "paired remainder sequence matches");
  expectStereoSample(recorder_first, 0, 0.5F, -0.25F, checks, "unity post-master sample");
  expectStereoSample(fingerprint_first, 255, 0.5F, -0.25F, checks, "fingerprint receives same post-master sample");

  LmmPcmHandoffStatus handoff{};
  checks.expect(get_status(&handoff), "read empty handoff status");
  checks.expect(handoff.recorder_queue_depth == 0, "recorder queue drained");
  checks.expect(handoff.fingerprint_queue_depth == 0, "fingerprint queue drained");
  checks.expect(handoff.recorder_rejected_blocks == 0, "no recorder overflow yet");
  checks.expect(handoff.fingerprint_rejected_blocks == 0, "no fingerprint overflow yet");

  const float one_frame[] = {0.8F, -0.4F};
  LmmPcmBlock recorder{};
  LmmPcmBlock fingerprint{};

  checks.expect(set_fader("capture-a", 0.5F), "set half capture fader");
  checks.expect(process_capture(one_frame, 1), "process fader-law frame");
  checks.expect(pop_recording(&recorder), "pop fader recorder block");
  checks.expect(pop_fingerprint(&fingerprint), "pop fader fingerprint block");
  expectStereoSample(recorder, 0, 0.2F, -0.1F, checks, "square fader law reaches master PCM");
  expectStereoSample(fingerprint, 0, 0.2F, -0.1F, checks, "square fader law reaches fingerprint PCM");

  checks.expect(set_muted("capture-a", true), "mute captured source");
  checks.expect(process_capture(one_frame, 1), "process muted frame");
  checks.expect(pop_recording(&recorder), "pop muted recorder block");
  checks.expect(pop_fingerprint(&fingerprint), "pop muted fingerprint block");
  expectStereoSample(recorder, 0, 0.0F, 0.0F, checks, "mute reaches post-master PCM");
  checks.expect(set_muted("capture-a", false), "unmute captured source");

  checks.expect(add_channel("other"), "add second mixer channel");
  checks.expect(set_solo("other", true), "solo other channel");
  checks.expect(process_capture(one_frame, 1), "process capture while another channel is soloed");
  checks.expect(pop_recording(&recorder), "pop solo-suppressed recorder block");
  checks.expect(pop_fingerprint(&fingerprint), "pop solo-suppressed fingerprint block");
  expectStereoSample(recorder, 0, 0.0F, 0.0F, checks, "other-channel solo suppresses captured source");
  checks.expect(set_solo("capture-a", true), "solo capture channel too");
  checks.expect(process_capture(one_frame, 1), "process capture while capture is soloed");
  checks.expect(pop_recording(&recorder), "pop capture-solo recorder block");
  checks.expect(pop_fingerprint(&fingerprint), "pop capture-solo fingerprint block");
  expectStereoSample(recorder, 0, 0.2F, -0.1F, checks, "capture solo restores its post-master signal");
  checks.expect(set_solo("capture-a", false), "clear capture solo");
  checks.expect(set_solo("other", false), "clear other solo");

  checks.expect(set_fader("capture-a", 1.0F), "restore unity capture fader");
  const float hot_frame[] = {2.0F, -2.0F};
  checks.expect(process_capture(hot_frame, 1), "process hot capture frame");
  checks.expect(pop_recording(&recorder), "pop limited recorder block");
  checks.expect(pop_fingerprint(&fingerprint), "pop limited fingerprint block");
  expectStereoSample(recorder, 0, 0.98F, -0.98F, checks, "recorder receives post-limiter PCM");
  expectStereoSample(fingerprint, 0, 0.98F, -0.98F, checks, "fingerprint receives post-limiter PCM");

  checks.expect(remove_channel("capture-a"), "remove bound capture channel");
  checks.expect(!process_capture(one_frame, 1), "removed channel invalidates stale capture binding");
  checks.expect(get_status(&handoff), "read status after stale route rejection");
  checks.expect(handoff.recorder_queue_depth == 0, "stale source does not enqueue recorder PCM");
  checks.expect(handoff.fingerprint_queue_depth == 0, "stale source does not enqueue fingerprint PCM");

  checks.expect(add_channel("capture-a"), "re-add capture channel");
  checks.expect(!process_capture(one_frame, 1), "recycled channel slot is not implicitly rebound");
  checks.expect(bind_capture("capture-a"), "explicitly rebind recreated capture channel");
  checks.expect(set_fader("capture-a", 1.0F), "set recreated channel unity fader");

  // Overflow is observable but does not make real-time processing block/fail.
  for (int index = 0; index < 256; ++index) {
    checks.expect(process_capture(one_frame, 1), "bounded queue overflow remains non-blocking");
  }
  checks.expect(get_status(&handoff), "read overflow handoff status");
  checks.expect(handoff.recorder_queue_depth > 0, "recorder queue retains bounded blocks");
  checks.expect(handoff.fingerprint_queue_depth > 0, "fingerprint queue retains bounded blocks");
  checks.expect(handoff.recorder_rejected_blocks > 0, "recorder overflow is observable");
  checks.expect(handoff.fingerprint_rejected_blocks > 0, "fingerprint overflow is observable");
  checks.expect(
      handoff.recorder_rejected_blocks == handoff.fingerprint_rejected_blocks,
      "paired bounded queues reject equally when neither is drained");

  if (checks.failures != 0) {
    std::cerr << checks.failures << " PCM handoff checks failed\n";
    return EXIT_FAILURE;
  }

  std::cout << "captured PCM mixer/fan-out contract passed\n";
  return EXIT_SUCCESS;
}

#include "lmm_engine.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
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
    if (handle_) FreeLibrary(static_cast<HMODULE>(handle_));
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

  void expectTrue(bool value, const std::string& label) {
    if (!value) {
      ++failures;
      std::cerr << "FAIL: " << label << '\n';
    }
  }

  void expectNear(float actual, float expected, float tolerance, const std::string& label) {
    if (std::abs(actual - expected) > tolerance) {
      ++failures;
      std::cerr << "FAIL: " << label << " expected=" << expected << " actual=" << actual << '\n';
    }
  }
};

using InitFn = bool (*)(std::uint32_t, std::uint32_t);
using AddChannelFn = bool (*)(const char*);
using RemoveChannelFn = bool (*)(const char*);
using SetFaderFn = bool (*)(const char*, float);
using SetMutedFn = bool (*)(const char*, bool);
using SetSoloFn = bool (*)(const char*, bool);
using ProcessFn = bool (*)(const float* const*, std::size_t, float*, std::size_t);
using GetChannelMeterFn = bool (*)(const char*, LmmChannelMeterSnapshot*);
using GetMasterMeterFn = bool (*)(LmmMasterMeterSnapshot*);

struct Api {
  InitFn init = nullptr;
  AddChannelFn add = nullptr;
  RemoveChannelFn remove = nullptr;
  SetFaderFn setFader = nullptr;
  SetMutedFn setMuted = nullptr;
  SetSoloFn setSolo = nullptr;
  ProcessFn process = nullptr;
  GetChannelMeterFn getChannelMeter = nullptr;
  GetMasterMeterFn getMasterMeter = nullptr;
};

template <typename Fn>
void bindRequired(const DynamicLibrary& library, const char* name, Fn& out, Checks& checks) {
  out = library.symbol<Fn>(name);
  if (!out) {
    ++checks.failures;
    std::cerr << "FAIL: required ABI symbol is missing: " << name << '\n';
  }
}

std::vector<float> constantStereo(std::size_t frames, float value) {
  return std::vector<float>(frames * 2, value);
}

std::vector<float> sineStereo(std::size_t frames, float amplitude, std::size_t cycles) {
  constexpr double kPi = 3.14159265358979323846;
  std::vector<float> block(frames * 2);
  for (std::size_t frame = 0; frame < frames; ++frame) {
    const float sample = static_cast<float>(
        amplitude * std::sin(2.0 * kPi * static_cast<double>(cycles * frame) /
                             static_cast<double>(frames)));
    block[frame * 2] = sample;
    block[frame * 2 + 1] = sample;
  }
  return block;
}

void prepareChannel(const Api& api, const char* id, Checks& checks) {
  checks.expectTrue(api.add(id), std::string("add channel ") + id);
  checks.expectTrue(api.setFader(id, 1.0F), std::string("set unity fader ") + id);
  checks.expectTrue(api.setMuted(id, false), std::string("clear mute ") + id);
  checks.expectTrue(api.setSolo(id, false), std::string("clear solo ") + id);
}

bool processOne(
    const Api& api,
    const std::vector<float>& input,
    std::vector<float>& output,
    std::size_t frames) {
  const float* inputs[1] = {input.data()};
  return api.process(inputs, 1, output.data(), frames);
}

void testSilence(const Api& api, Checks& checks, std::size_t frames) {
  const char* id = "signal-silence";
  prepareChannel(api, id, checks);
  const auto input = constantStereo(frames, 0.0F);
  auto output = constantStereo(frames, 9.0F);
  checks.expectTrue(processOne(api, input, output, frames), "process silence");
  checks.expectTrue(
      std::all_of(output.begin(), output.end(), [](float value) { return value == 0.0F; }),
      "silence produces zero master PCM");
  LmmChannelMeterSnapshot meter{};
  checks.expectTrue(api.getChannelMeter(id, &meter), "read silence channel meter");
  checks.expectNear(meter.peak_left, 0.0F, 1e-6F, "silence peak left");
  checks.expectNear(meter.rms_left, 0.0F, 1e-6F, "silence RMS left");
  checks.expectTrue(meter.clipping == 0, "silence is not clipping");
  checks.expectTrue(api.remove(id), "remove silence channel");
}

void testMinusTwelveDbfsSine(const Api& api, Checks& checks, std::size_t frames) {
  const char* id = "signal-minus12";
  prepareChannel(api, id, checks);
  const float amplitude = std::pow(10.0F, -12.0F / 20.0F);
  const auto input = sineStereo(frames, amplitude, 16);
  auto output = constantStereo(frames, 0.0F);
  checks.expectTrue(processOne(api, input, output, frames), "process -12 dBFS sine");
  LmmChannelMeterSnapshot meter{};
  checks.expectTrue(api.getChannelMeter(id, &meter), "read -12 dBFS meter");
  checks.expectNear(meter.peak_left, amplitude, 1e-4F, "-12 dBFS peak");
  checks.expectNear(meter.rms_left, amplitude / std::sqrt(2.0F), 1e-4F, "-12 dBFS RMS");
  checks.expectTrue(meter.clipping == 0, "-12 dBFS sine is not clipping");
  checks.expectTrue(api.remove(id), "remove -12 dBFS channel");
}

void testFullScaleAndClippedSine(const Api& api, Checks& checks, std::size_t frames) {
  const char* fullId = "signal-full-scale";
  prepareChannel(api, fullId, checks);
  auto input = sineStereo(frames, 1.0F, 16);
  auto output = constantStereo(frames, 0.0F);
  checks.expectTrue(processOne(api, input, output, frames), "process full-scale sine");
  LmmChannelMeterSnapshot channel{};
  LmmMasterMeterSnapshot master{};
  checks.expectTrue(api.getChannelMeter(fullId, &channel), "read full-scale channel meter");
  checks.expectTrue(api.getMasterMeter(&master), "read full-scale master meter");
  checks.expectNear(channel.peak_left, 1.0F, 1e-4F, "full-scale channel peak");
  checks.expectTrue(channel.clipping == 1, "full-scale channel marks clipping");
  checks.expectTrue(master.true_peak_left <= 0.980001F, "full-scale master respects limiter ceiling");
  checks.expectTrue(master.limiter_active == 1, "full-scale sine engages limiter");
  checks.expectTrue(api.remove(fullId), "remove full-scale channel");

  const char* clippedId = "signal-clipped";
  prepareChannel(api, clippedId, checks);
  input = sineStereo(frames, 1.5F, 16);
  std::fill(output.begin(), output.end(), 0.0F);
  checks.expectTrue(processOne(api, input, output, frames), "process clipped sine");
  channel = {};
  master = {};
  checks.expectTrue(api.getChannelMeter(clippedId, &channel), "read clipped channel meter");
  checks.expectTrue(api.getMasterMeter(&master), "read clipped master meter");
  checks.expectNear(channel.peak_left, 1.5F, 1e-4F, "clipped channel peak remains observable");
  checks.expectTrue(channel.clipping == 1, "clipped sine marks clipping");
  checks.expectTrue(master.true_peak_left <= 0.980001F, "clipped master respects limiter ceiling");
  checks.expectTrue(api.remove(clippedId), "remove clipped channel");
}

void testImpulse(const Api& api, Checks& checks, std::size_t frames) {
  const char* id = "signal-impulse";
  prepareChannel(api, id, checks);
  auto input = constantStereo(frames, 0.0F);
  input[0] = 0.5F;
  input[1] = -0.5F;
  auto output = constantStereo(frames, 0.0F);
  checks.expectTrue(processOne(api, input, output, frames), "process impulse");
  LmmChannelMeterSnapshot meter{};
  checks.expectTrue(api.getChannelMeter(id, &meter), "read impulse meter");
  checks.expectNear(meter.peak_left, 0.5F, 1e-6F, "impulse peak");
  checks.expectNear(meter.rms_left, 0.5F / std::sqrt(static_cast<float>(frames)), 1e-5F, "impulse RMS");
  checks.expectTrue(api.remove(id), "remove impulse channel");
}

void testTwoChannelSumMuteSoloAndFader(const Api& api, Checks& checks, std::size_t frames) {
  const char* left = "signal-sum-a";
  const char* right = "signal-sum-b";
  prepareChannel(api, left, checks);
  prepareChannel(api, right, checks);
  const auto a = constantStereo(frames, 0.2F);
  const auto b = constantStereo(frames, 0.3F);
  auto output = constantStereo(frames, 0.0F);
  const float* inputs[2] = {a.data(), b.data()};
  checks.expectTrue(api.process(inputs, 2, output.data(), frames), "process two-channel sum");
  checks.expectNear(output[0], 0.5F, 1e-6F, "two-channel master sum");

  checks.expectTrue(api.setMuted(right, true), "mute second channel");
  checks.expectTrue(api.process(inputs, 2, output.data(), frames), "process muted channel");
  checks.expectNear(output[0], 0.2F, 1e-6F, "mute removes second channel from sum");
  checks.expectTrue(api.setMuted(right, false), "unmute second channel");

  checks.expectTrue(api.setSolo(right, true), "solo second channel");
  checks.expectTrue(api.process(inputs, 2, output.data(), frames), "process solo channel");
  checks.expectNear(output[0], 0.3F, 1e-6F, "solo excludes non-solo channel");
  checks.expectTrue(api.setSolo(right, false), "clear solo second channel");

  checks.expectTrue(api.setFader(left, 0.5F), "set half fader");
  checks.expectTrue(api.setMuted(right, true), "mute second channel for fader-law test");
  checks.expectTrue(api.process(inputs, 2, output.data(), frames), "process fader-law block");
  checks.expectNear(output[0], 0.05F, 1e-6F, "0.5 normalized fader follows square law");

  checks.expectTrue(api.remove(left), "remove sum channel A");
  checks.expectTrue(api.remove(right), "remove sum channel B");
}

void testLimiterCeiling(const Api& api, Checks& checks, std::size_t frames) {
  const char* id = "signal-limiter";
  prepareChannel(api, id, checks);
  const auto input = constantStereo(frames, 2.0F);
  auto output = constantStereo(frames, 0.0F);
  checks.expectTrue(processOne(api, input, output, frames), "process limiter stress block");
  const float maxMagnitude = std::accumulate(
      output.begin(), output.end(), 0.0F,
      [](float current, float sample) { return std::max(current, std::abs(sample)); });
  checks.expectTrue(maxMagnitude <= 0.980001F, "limiter output never exceeds configured ceiling");
  LmmMasterMeterSnapshot master{};
  checks.expectTrue(api.getMasterMeter(&master), "read limiter master meter");
  checks.expectTrue(master.limiter_active == 1, "limiter stress block reports limiter active");
  checks.expectTrue(api.remove(id), "remove limiter channel");
}

}  // namespace

int main(int argc, char** argv) {
  if (argc != 2) {
    std::cerr << "usage: engine_signal_tests <path-to-live-mixer-engine>\n";
    return EXIT_FAILURE;
  }

  Checks checks;
  DynamicLibrary library(argv[1]);
  checks.expectTrue(library.isOpen(), "open native engine dynamic library");
  if (!library.isOpen()) return EXIT_FAILURE;

  Api api;
  bindRequired(library, "lmm_init", api.init, checks);
  bindRequired(library, "lmm_add_channel", api.add, checks);
  bindRequired(library, "lmm_remove_channel", api.remove, checks);
  bindRequired(library, "lmm_set_channel_fader", api.setFader, checks);
  bindRequired(library, "lmm_set_channel_muted", api.setMuted, checks);
  bindRequired(library, "lmm_set_channel_solo", api.setSolo, checks);
  bindRequired(library, "lmm_process_interleaved_stereo", api.process, checks);
  bindRequired(library, "lmm_get_channel_meter", api.getChannelMeter, checks);
  bindRequired(library, "lmm_get_master_meter", api.getMasterMeter, checks);
  if (checks.failures != 0) return EXIT_FAILURE;

  constexpr std::size_t kFrames = 1024;
  checks.expectTrue(api.init(48000, static_cast<std::uint32_t>(kFrames)), "initialize deterministic engine");
  testSilence(api, checks, kFrames);
  testMinusTwelveDbfsSine(api, checks, kFrames);
  testFullScaleAndClippedSine(api, checks, kFrames);
  testImpulse(api, checks, kFrames);
  testTwoChannelSumMuteSoloAndFader(api, checks, kFrames);
  testLimiterCeiling(api, checks, kFrames);

  if (checks.failures != 0) {
    std::cerr << checks.failures << " deterministic engine checks failed\n";
    return EXIT_FAILURE;
  }
  std::cout << "deterministic engine signal contract passed\n";
  return EXIT_SUCCESS;
}

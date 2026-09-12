# Issue #3 Current-Main Forward-Port Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Forward-port the macOS Core Audio/device-capture work from stale PR #15 onto current `main`, close all seven review findings, preserve the current Web/shared-DSP architecture, and merge only after exact-head CI plus real-device acceptance are green.

**Architecture:** Keep `lib/main.dart` platform-neutral. The current conditional audio factory continues to choose desktop vs Web; the desktop implementation gains a `NativeDesktopRuntime` that owns the FFI-backed native engine, bounded PCM handoff, negotiated-format service coordinator, and telemetry. `MixerDeskView` receives optional native control/service ports on desktop while Web keeps its current browser surface. Native capture/lifecycle code is forward-ported, but DSP arithmetic remains centralized in `native/dsp_kernel.hpp` and is consumed by both desktop and Web paths.

**Tech Stack:** Flutter/Dart 3.5+, C++20/CMake, Core Audio Objective-C++, Dart FFI, lock-free SPSC queues, GitHub Actions, Vercel exact-artifact release flow.

**Spec:** `docs/superpowers/specs/2026-09-12-issue-3-forward-port-design.md`

## Global Constraints

- Base the implementation branch on current `main`; do not merge or force-rewrite stale PR #15.
- Keep `lib/main.dart` platform-neutral and preserve the current `audio_engine_factory_*` plus `app_surface_*` conditional split.
- `native/dsp_kernel.hpp` remains the canonical DSP kernel for desktop and Web.
- Preserve ABI-v1 Web DSP constraints: maximum 8 Web channels, 128-frame render quantum ceiling, `0.98` sample ceiling, `1.0e-6` parity tolerance, Emscripten 6.0.9, no production JavaScript DSP fallback, and no committed generated Wasm.
- The native callback performs no heap allocation, locks, disk/network I/O, logging, JSON serialization, or Dart calls.
- The macOS backend supports exactly one active Core Audio capture route in this forward-port. A second route is rejected explicitly.
- No resampling is introduced. Recording and fingerprint consumers use the negotiated capture sample rate.
- Hosted CI is not physical-input/BlackHole E2E evidence.
- Do not claim standards-based True Peak/dBTP or LUFS from the current sample-peak ABI.

---

### Task 1: Re-establish the native runtime behind the current platform split

**Files:**
- Create: `lib/audio/native_desktop_runtime.dart`
- Port/create: `lib/audio/audio_engine_bridge.dart`
- Port/create: `lib/audio/native_audio_bindings.dart`
- Port/create: `lib/audio/native_audio_engine.dart`
- Port/create: `lib/audio/native_audio_runtime.dart`
- Port/create: `lib/audio/native_audio_permission_bindings.dart`
- Port/create: `lib/audio/native_audio_permission_ffi.dart`
- Modify: `lib/audio/audio_engine_factory_desktop.dart`
- Modify: `lib/app/app_surface.dart`
- Modify: `lib/app/app_surface_desktop.dart`
- Modify: `lib/app/app_surface_web_reference.dart`
- Modify: `lib/main.dart`
- Modify: `lib/features/mixer/mixer_desk_view.dart`
- Test: `test/native_startup_gate_test.dart`
- Create test: `test/native_desktop_runtime_factory_test.dart`

**Interfaces:**
- Port the historical `AudioEngine` asynchronous control contract from PR #15.
- Extend `InputChannelConfig` with `int channelPairIndex = 0`.
- `NativeDesktopRuntime` owns `NativeAudioEngine audioEngine`; later tasks add services, pump, and telemetry.
- `DesktopNativeAudioEngine.prepareRuntime()` returns `Future<NativeDesktopRuntime>` after `initialize()` loaded a library.
- Conditional surface signature becomes `Widget buildPrimaryOperatorSurface(AudioEnginePort audioEngine)`.

- [ ] **Step 1: Create the replacement branch from the accepted production main SHA**

Create `feat/issue-3-forward-port` at `b2dcd03c13230cf7a832b51d75b0caf79f29cc4d` with `force=false`.

- [ ] **Step 2: Write the failing desktop-factory test**

```dart
import 'dart:ffi';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_mix_master/audio/audio_engine_factory_desktop.dart';
import 'package:live_mix_master/audio/native_desktop_runtime.dart';
import 'package:live_mix_master/audio/native_library_loader.dart';

void main() {
  test('desktop factory exposes runtime preparation after bootstrap', () async {
    final fakeRuntime = NativeDesktopRuntime.testing();
    final engine = DesktopNativeAudioEngine(
      loadNativeLibrary: () => NativeLibraryLoadResult.loaded(
        library: DynamicLibrary.process(),
        path: '/tmp/liblive_mixer_engine.dylib',
        searchedPaths: const ['/tmp/liblive_mixer_engine.dylib'],
      ),
      runtimeBuilder: (_) async => fakeRuntime,
    );

    expect(engine.initialize().isAvailable, isTrue);
    expect(await engine.prepareRuntime(), same(fakeRuntime));
  });
}
```

`NativeDesktopRuntime.testing()` is a test-only constructor containing a fake `AudioEngine`; it is defined in the new runtime file and never opens FFI symbols.

- [ ] **Step 3: Verify RED**

```bash
flutter test test/native_desktop_runtime_factory_test.dart test/native_startup_gate_test.dart
```

Expected: compile failure because `NativeDesktopRuntime`, `runtimeBuilder`, and `prepareRuntime()` do not exist.

- [ ] **Step 4: Port the pure-Dart contracts and add `channelPairIndex`**

```dart
class InputChannelConfig {
  const InputChannelConfig({
    required this.id,
    required this.name,
    required this.kind,
    required this.endpointId,
    this.channelPairIndex = 0,
    this.trimDb = 0,
    this.fader = .8,
    this.muted = false,
    this.solo = false,
  });

  final String id;
  final String name;
  final AudioInputKind kind;
  final String endpointId;
  final int channelPairIndex;
  final double trimDb;
  final double fader;
  final bool muted;
  final bool solo;
}
```

- [ ] **Step 5: Implement the desktop factory without changing current bootstrap semantics**

```dart
class DesktopNativeAudioEngine implements AudioEnginePort {
  DesktopNativeAudioEngine({
    NativeLibraryLoadResult Function()? loadNativeLibrary,
    Future<NativeDesktopRuntime> Function(DynamicLibrary)? runtimeBuilder,
  })  : _loadNativeLibrary = loadNativeLibrary ?? NativeLibraryLoader.tryLoad,
        _runtimeBuilder = runtimeBuilder ?? NativeDesktopRuntime.create;

  final NativeLibraryLoadResult Function() _loadNativeLibrary;
  final Future<NativeDesktopRuntime> Function(DynamicLibrary) _runtimeBuilder;
  NativeLibraryLoadResult? _nativeLibraryResult;

  @override
  AudioEngineKind get kind => AudioEngineKind.desktopNative;

  @override
  AudioEngineBootstrapResult initialize() {
    final result = _loadNativeLibrary();
    _nativeLibraryResult = result;
    if (result.isLoaded) {
      return AudioEngineBootstrapResult.available(
        kind: kind,
        message: result.message,
        diagnostics: result.loadedPath == null ? const [] : [result.loadedPath!],
      );
    }
    return AudioEngineBootstrapResult.unavailable(
      kind: kind,
      message: result.message,
      diagnostics: result.searchedPaths,
    );
  }

  Future<NativeDesktopRuntime> prepareRuntime() {
    final library = _nativeLibraryResult?.library;
    if (library == null) {
      return Future.error(StateError('Native library is not loaded.'));
    }
    return _runtimeBuilder(library);
  }
}
```

- [ ] **Step 6: Route only the available desktop surface through runtime preparation**

Change current `main.dart` to:

```dart
home: result == null || result.isAvailable
    ? buildPrimaryOperatorSurface(audioEngine)
    : _AudioEngineUnavailable(result: result),
```

Desktop `app_surface_desktop.dart` uses a `FutureBuilder<NativeDesktopRuntime>` and builds `MixerDeskView(audioEngine: runtime.audioEngine)`. Web ignores the port argument and returns its existing browser reference surface.

- [ ] **Step 7: Verify GREEN**

```bash
flutter test test/native_desktop_runtime_factory_test.dart test/native_startup_gate_test.dart test/web_release_compile_boundary_test.dart
```

- [ ] **Step 8: Commit**

```bash
git add lib/audio lib/app lib/main.dart lib/features/mixer/mixer_desk_view.dart test/native_desktop_runtime_factory_test.dart test/native_startup_gate_test.dart
git commit -m "feat(audio): forward-port desktop native runtime seam"
```

---

### Task 2: Forward-port native capture while keeping shared DSP canonical

**Files:**
- Port/create: `native/include/lmm_engine.h`, `lmm_capture.h`, `lmm_device_catalog.h`, `lmm_permissions.h`, `lmm_pcm_handoff.h`, `spsc_ring_buffer.h`
- Modify: `native/live_mixer_engine.cpp`
- Port/create: `native/macos/coreaudio_capture.mm`, `coreaudio_device_catalog.mm`, `audio_input_permissions.mm`
- Modify: `native/CMakeLists.txt`
- Port/create tests: `native/tests/engine_signal_tests.cpp`, `capture_state_tests.cpp`, `capture_handoff_integration_tests.cpp`, `pcm_handoff_tests.cpp`, `realtime_atomic_contract_tests.cpp`, `spsc_ring_buffer_tests.cpp`, `device_catalog_contract_tests.cpp`, `audio_permission_contract_tests.cpp`
- Preserve unchanged: `native/dsp_kernel.hpp`

**Interfaces:**

```cpp
bool lmm_set_channel_fader(const char* id, float normalized_fader);
bool lmm_set_channel_muted(const char* id, bool muted);
bool lmm_set_channel_solo(const char* id, bool solo);
bool lmm_set_channel_trim_db(const char* id, float trim_db);
bool lmm_set_master_gain_db(float gain_db);
```

- [ ] **Step 1: Add RED native assertions for trim/master behavior**

```cpp
REQUIRE(lmm_add_channel("ch1"));
REQUIRE(lmm_set_channel_fader("ch1", 1.0F));
REQUIRE(lmm_set_channel_trim_db("ch1", -6.0206F));
REQUIRE(lmm_set_master_gain_db(-6.0206F));
const float input[] = {1.0F, 1.0F};
const float* channels[] = {input};
float output[] = {0.0F, 0.0F};
REQUIRE(lmm_process_interleaved_stereo(channels, 1, output, 1));
REQUIRE(output[0] == Approx(0.25F).margin(1.0e-4F));
REQUIRE(output[1] == Approx(0.25F).margin(1.0e-4F));
```

- [ ] **Step 2: Verify RED**

```bash
cmake -S native -B build/native -DBUILD_TESTING=ON -DCMAKE_BUILD_TYPE=Debug
cmake --build build/native --parallel
ctest --test-dir build/native --output-on-failure
```

- [ ] **Step 3: Integrate lifecycle/SPSC logic around the canonical kernel**

`live_mixer_engine.cpp` builds `DspChannelConfig`/`DspChannelMeter` arrays and calls:

```cpp
const auto master_meter = processStereoBlock(
    configs.data(), channel_input, configs.size(), master_output, frames,
    master_.gain.load(std::memory_order_relaxed), meters.data());
```

Do not duplicate limiter/fader/solo arithmetic from PR #15.

- [ ] **Step 4: Implement control-thread trim/master setters**

```cpp
bool setTrimDb(const char* id, float trim_db) {
  if (!std::isfinite(trim_db) || trim_db < -18.0F || trim_db > 12.0F) return false;
  Channel* channel = findChannel(id);
  if (!channel) return false;
  channel->linearTrim.store(std::pow(10.0F, trim_db / 20.0F), std::memory_order_relaxed);
  return true;
}

bool setMasterGainDb(float gain_db) {
  if (!std::isfinite(gain_db) || gain_db < -90.0F || gain_db > 12.0F) return false;
  master_.gain.store(std::pow(10.0F, gain_db / 20.0F), std::memory_order_relaxed);
  return true;
}
```

- [ ] **Step 5: Verify GREEN**

Run the CMake/CTest commands again; require all deterministic DSP, SPSC, atomic-safety, device-catalog, and permission tests to pass.

- [ ] **Step 6: Commit**

```bash
git add native
git commit -m "feat(audio): forward-port Core Audio engine on shared DSP kernel"
```

---

### Task 3: Fix single-route semantics, channel-pair capture, and FFI parity

**Files:**
- Modify: `native/include/lmm_capture.h`, `native/macos/coreaudio_capture.mm`, `native/live_mixer_engine.cpp`
- Modify/create: `lib/audio/native_audio_bindings.dart`, `lib/audio/native_audio_ffi_bindings.dart`, `lib/audio/native_audio_engine.dart`, `lib/audio/audio_engine_bridge.dart`
- Test: `native/tests/capture_conversion_tests.cpp`, `test/native_audio_engine_contract_test.dart`, `test/native_audio_ffi_bindings_test.dart`

**Interfaces:**

```cpp
bool lmm_capture_start(const char* device_uid, std::uint32_t channel_pair_index);
```

```dart
bool captureStart(String uid, int channelPairIndex);
```

- [ ] **Step 1: Add RED native CH 3-4 conversion coverage**

Update the testing hook to accept `channel_pair_index` and call it directly:

```cpp
const float interleaved[] = {
    0.1F, 0.2F, 0.3F, 0.4F,
    0.5F, 0.6F, 0.7F, 0.8F,
};
LmmPcmBufferView view{interleaved, 4, sizeof(float) * 4};
LmmPcmFormat format{LMM_PCM_FLOAT32, 0, 4, sizeof(float)};
float out[4]{};
REQUIRE(lmm_capture_test_convert_pcm(&view, 1, &format, 2, 1, out, 4));
REQUIRE(out[0] == Approx(0.3F));
REQUIRE(out[1] == Approx(0.4F));
REQUIRE(out[2] == Approx(0.7F));
REQUIRE(out[3] == Approx(0.8F));
```

- [ ] **Step 2: Add RED Dart second-route test**

```dart
test('second native route is rejected before rebinding capture', () async {
  final bindings = FakeNativeAudioBindings.withOneInput();
  final engine = NativeAudioEngine(
    bindings: bindings,
    permissionState: AudioPermissionState.granted,
    pollInterval: null,
  );
  await engine.initialize();
  await engine.refreshInputDevices();
  await engine.addChannel(testChannel(id: 'a', pair: 0));
  await expectLater(
    engine.addChannel(testChannel(id: 'b', pair: 1)),
    throwsA(isA<StateError>()),
  );
  expect(bindings.captureStartCalls, [(bindings.inputUid, 0)]);
  expect(bindings.boundChannelIds, ['a']);
});
```

Define `FakeNativeAudioBindings.withOneInput()` and `testChannel({required String id, required int pair})` in `test/native_audio_engine_contract_test.dart`; both are test-only helpers in that file.

- [ ] **Step 3: Verify RED**

```bash
flutter test test/native_audio_engine_contract_test.dart test/native_audio_ffi_bindings_test.dart
ctest --test-dir build/native --output-on-failure -R capture_conversion
```

- [ ] **Step 4: Implement pair-aware callback conversion**

```cpp
const std::uint32_t left_channel = channel_pair_index * 2;
const std::uint32_t right_channel = left_channel + 1;
if (left_channel >= total_channels) return false;
const std::uint32_t effective_right =
    right_channel < total_channels ? right_channel : left_channel;
```

Use these indices in both interleaved and non-interleaved branches; add no callback allocation.

- [ ] **Step 5: Reject a second live route before native mutation**

At the beginning of `NativeAudioEngine.addChannel` after permission/device validation:

```dart
if (_channels.isNotEmpty) {
  throw StateError('The macOS native backend currently supports one active capture route.');
}
```

Then apply trim/fader/mute/solo, bind the channel, and call `captureStart(channel.endpointId, channel.channelPairIndex)`.

- [ ] **Step 6: Verify GREEN and commit**

```bash
flutter test test/native_audio_engine_contract_test.dart test/native_audio_ffi_bindings_test.dart
ctest --test-dir build/native --output-on-failure
git add native lib/audio test/native_audio_engine_contract_test.dart test/native_audio_ffi_bindings_test.dart
git commit -m "fix(audio): preserve native route and selected channel pair"
```

---

### Task 4: Bind recorder/fingerprinting to negotiated capture rate with stable UI ports

**Files:**
- Create: `lib/services/mixer_service_ports.dart`
- Create: `lib/audio/native_pcm_service_coordinator.dart`
- Modify: `lib/services/lossless_recording_writer.dart`, `lib/services/fingerprint_service.dart`
- Modify: `lib/audio/native_desktop_runtime.dart`
- Port/create: `lib/audio/native_pcm_handoff_bindings.dart`, `lib/audio/native_recording_drain.dart`, `lib/audio/native_pcm_runtime_pump.dart`
- Modify: `lib/features/mixer/mixer_desk_view.dart`
- Test: `test/native_recording_drain_test.dart`, `test/native_runtime_acceptance_wiring_contract_test.dart`
- Create test: `test/native_pcm_service_coordinator_test.dart`

**Interfaces:**

```dart
abstract interface class MixerRecordingPort {
  Stream<RecordingStats> get onStatsUpdated;
  Future<String> startRecording();
  Future<RecordingStats> stopRecording();
}

abstract interface class MixerFingerprintPort {
  Stream<IdentifiedTrack> get onTrackIdentified;
  Stream<bool> get onAnalyzingStatusChanged;
}
```

`LosslessRecordingWriter` implements `MixerRecordingPort`; `FingerprintService` implements `MixerFingerprintPort`.

`NativePcmServiceCoordinator` implements both UI ports, exposes stable streams for the lifetime of `MixerDeskView`, owns replaceable concrete recorder/fingerprint consumers, and adds:

```dart
int? get sampleRate;
Future<void> activateForCapture(NativeCaptureStatus status);
void pushRecordingPcm(Float32List samples);
void pushFingerprintPcm(Float32List samples);
Future<void> dispose();
```

- [ ] **Step 1: Write RED 44.1 kHz activation test**

Use injected consumer factories returning test fakes that record the received config:

```dart
test('PCM consumers use negotiated 44100 Hz rate', () async {
  int? recordingRate;
  int? fingerprintRate;
  final coordinator = NativePcmServiceCoordinator(
    destinationDirectory: '/tmp/lmm-test',
    acoustIdApiKey: '',
    createRecordingConsumer: (config) {
      recordingRate = config.sampleRate;
      return FakeRecordingConsumer();
    },
    createFingerprintConsumer: (config) async {
      fingerprintRate = config.sampleRate;
      return FakeFingerprintConsumer();
    },
  );

  await coordinator.activateForCapture(testRunningStatus(sampleRate: 44100));
  expect(coordinator.sampleRate, 44100);
  expect(recordingRate, 44100);
  expect(fingerprintRate, 44100);
});
```

Define `FakeRecordingConsumer`, `FakeFingerprintConsumer`, and `testRunningStatus` in the same test file against the coordinator's internal consumer interfaces.

- [ ] **Step 2: Verify RED**

```bash
flutter test test/native_pcm_service_coordinator_test.dart
```

- [ ] **Step 3: Implement fail-closed negotiated-rate activation**

```dart
final rate = status.sampleRate.round();
if (status.state != NativeCaptureState.running || rate <= 0) {
  throw StateError('Capture format is not ready for PCM consumers.');
}
```

Construct both consumers with `sampleRate: rate`, `channels: 2`. If recording is already active, reject reconfiguration rather than changing the WAV format mid-file.

- [ ] **Step 4: Enforce startup ordering in `NativeDesktopRuntime`**

The only allowed order is:

```text
captureStart -> captureStatus(running + negotiated rate)
-> services.activateForCapture(status)
-> enable NativePcmRuntimePump delivery
```

If service activation fails, stop capture and publish a failed route state; do not continue at a default 48 kHz.

- [ ] **Step 5: Pass the coordinator's stable UI ports to `MixerDeskView`**

```dart
MixerDeskView(
  audioEngine: runtime.audioEngine,
  recordingService: runtime.services,
  fingerprintService: runtime.services,
)
```

The widget subscribes to stable coordinator streams once; concrete service replacement does not replace the widget-facing stream objects.

- [ ] **Step 6: Verify GREEN and commit**

```bash
flutter test test/native_pcm_service_coordinator_test.dart test/native_recording_drain_test.dart test/native_runtime_acceptance_wiring_contract_test.dart
git add lib/audio lib/services lib/features/mixer/mixer_desk_view.dart test/native_pcm_service_coordinator_test.dart test/native_recording_drain_test.dart test/native_runtime_acceptance_wiring_contract_test.dart
git commit -m "fix(audio): bind PCM services to negotiated capture rate"
```

---

### Task 5: Make permission recovery live and open the real macOS Settings pane

**Files:**
- Modify: `lib/audio/native_audio_engine.dart`, `lib/audio/native_desktop_runtime.dart`
- Create: `lib/audio/macos_audio_settings_launcher.dart`
- Port/modify: `lib/features/patchbay/audio_route_recovery_banner.dart`
- Modify: `lib/features/mixer/mixer_desk_view.dart`
- Test: `test/native_audio_permission_refresh_test.dart`, `test/audio_route_recovery_ui_test.dart`
- Create test: `test/macos_audio_settings_launcher_test.dart`

- [ ] **Step 1: Write RED live-permission test**

```dart
test('refresh re-reads permission after System Settings changes it', () async {
  var permission = AudioPermissionState.denied;
  final engine = NativeAudioEngine(
    bindings: FakeNativeAudioBindings.withOneInput(),
    permissionState: permission,
    permissionStateProvider: () => permission,
    pollInterval: null,
  );
  await engine.initialize();
  expect(await engine.refreshInputDevices(), isEmpty);
  permission = AudioPermissionState.granted;
  expect(await engine.refreshInputDevices(), isNotEmpty);
});
```

- [ ] **Step 2: Write RED Settings launcher test**

```dart
test('opens macOS microphone privacy settings', () async {
  final calls = <(String, List<String>)>[];
  final launcher = MacosAudioSettingsLauncher(
    runProcess: (executable, args) async {
      calls.add((executable, args));
      return 0;
    },
  );
  await launcher.openMicrophonePrivacy();
  expect(calls.single.$1, 'open');
  expect(
    calls.single.$2,
    ['x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone'],
  );
});
```

- [ ] **Step 3: Verify RED**

```bash
flutter test test/native_audio_permission_refresh_test.dart test/macos_audio_settings_launcher_test.dart test/audio_route_recovery_ui_test.dart
```

- [ ] **Step 4: Wire production live permission provider**

```dart
final permissions = FfiAudioInputPermissionBindings(library);
final engine = NativeAudioEngine(
  bindings: bindings,
  permissionState: permissions.currentState(),
  permissionStateProvider: permissions.currentState,
  requestPermission: permissions.requestAccess,
);
```

- [ ] **Step 5: Implement the launcher outside the audio callback**

```dart
class MacosAudioSettingsLauncher {
  MacosAudioSettingsLauncher({this.runProcess = _run});
  final Future<int> Function(String, List<String>) runProcess;

  static Future<int> _run(String executable, List<String> args) async {
    final result = await Process.run(executable, args);
    return result.exitCode;
  }

  Future<void> openMicrophonePrivacy() async {
    final exitCode = await runProcess(
      'open',
      const ['x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone'],
    );
    if (exitCode != 0) throw StateError('Unable to open macOS microphone settings.');
  }
}
```

`OPEN AUDIO SETTINGS` invokes this method; refresh remains explicit after the user returns.

- [ ] **Step 6: Verify GREEN and commit**

```bash
flutter test test/native_audio_permission_refresh_test.dart test/macos_audio_settings_launcher_test.dart test/audio_route_recovery_ui_test.dart
git add lib/audio lib/features test/native_audio_permission_refresh_test.dart test/macos_audio_settings_launcher_test.dart test/audio_route_recovery_ui_test.dart
git commit -m "fix(audio): make macOS permission recovery live"
```

---

### Task 6: Wire patchbay/channel/master controls into native PCM

**Files:**
- Create: `lib/features/patchbay/native_channel_config_mapper.dart`
- Modify: `lib/features/mixer/mixer_desk_view.dart`, `lib/features/patchbay/patchbay_routing_modal.dart`
- Modify: `lib/audio/native_audio_engine.dart`, `lib/audio/native_audio_bindings.dart`, `lib/audio/native_audio_ffi_bindings.dart`
- Create test: `test/native_channel_config_mapper_test.dart`, `test/mixer_native_control_wiring_test.dart`
- Test: `test/mixer_audio_route_lifecycle_test.dart`, `test/mixer_native_meter_stream_test.dart`, `test/native_audio_engine_contract_test.dart`

**Interfaces:**

```dart
InputChannelConfig mapPatchbayResultToNativeConfig({
  required PatchbayChannelResult result,
  required String channelId,
});

double masterFaderToDb(double normalized);
```

The mixer adds testable keys: `ValueKey('channel-fader-$id')`, `ValueKey('channel-mute-$id')`, `ValueKey('channel-solo-$id')`, and `ValueKey('master-fader')`.

- [ ] **Step 1: Write RED mapping test**

```dart
test('patchbay mapping preserves endpoint, pair and trim', () {
  final result = PatchbayChannelResult(
    channelName: 'DECK',
    endpoint: const AudioEndpoint(
      id: 'device-uid',
      name: 'Four Channel Device',
      type: AudioSourceType.hardwareInput,
      channelCount: 4,
      deviceDriver: 'CoreAudio',
    ),
    channelPairIndex: 1,
    initialTrimDb: -3,
    channelColor: const Color(0xFFFFFFFF),
  );
  final config = mapPatchbayResultToNativeConfig(result: result, channelId: 'ch1');
  expect(config.endpointId, 'device-uid');
  expect(config.channelPairIndex, 1);
  expect(config.trimDb, -3);
});
```

- [ ] **Step 2: Write RED engine-control assertions**

Extend `test/native_audio_engine_contract_test.dart` so `addChannel` records exactly one trim call before capture start, and direct `setTrim`/`setMasterGain` calls reach FFI bindings.

- [ ] **Step 3: Verify RED**

```bash
flutter test test/native_channel_config_mapper_test.dart test/native_audio_engine_contract_test.dart test/mixer_native_control_wiring_test.dart
```

- [ ] **Step 4: Implement mapping and normalized-master conversion**

```dart
double masterFaderToDb(double normalized) {
  final value = normalized.clamp(0.0, 1.0);
  if (value == 0) return -90.0;
  return 20 * (math.log(value) / math.ln10);
}
```

- [ ] **Step 5: Wire native mode optimistically only after successful Futures**

For fader/mute/solo/trim/master changes, call the engine first. Update local widget state only after success. On error, retain the old value and show the existing error UI.

- [ ] **Step 6: Replace synthetic desktop meters when a native engine is present**

Subscribe to `audioEngine.channelMeters` and `audioEngine.masterMeters`. Static reference values remain only when `audioEngine == null`. Label native master values as sample peak, not dBTP/LUFS.

- [ ] **Step 7: Verify GREEN and commit**

```bash
flutter test test/native_channel_config_mapper_test.dart test/mixer_native_control_wiring_test.dart test/mixer_audio_route_lifecycle_test.dart test/mixer_native_meter_stream_test.dart test/native_audio_engine_contract_test.dart
git add lib/features lib/audio test/native_channel_config_mapper_test.dart test/mixer_native_control_wiring_test.dart test/mixer_audio_route_lifecycle_test.dart test/mixer_native_meter_stream_test.dart test/native_audio_engine_contract_test.dart
git commit -m "fix(audio): wire desktop mixer controls to native PCM"
```

---

### Task 7: Restore acceptance telemetry/docs and prove current-main CI

**Files:**
- Port/create: `lib/audio/native_acceptance_telemetry.dart`, `lib/features/mixer/native_acceptance_telemetry_panel.dart`
- Port/update: `docs/audio/macos-device-e2e.md`, `docs/audio/issue3-device-acceptance-record.md`, `docs/audio/dsp-safety-evidence.md`
- Modify: `.github/workflows/macos-ci.yml`
- Test: `test/native_acceptance_evidence_copy_test.dart`, `test/macos_device_acceptance_contract_test.dart`, `test/native_runtime_acceptance_wiring_contract_test.dart`

- [ ] **Step 1: Port the acceptance contract first and verify RED**

The contract requires these literal fields in copied evidence:

```text
average callback duration (us)
maximum callback duration (us)
callback count
xrun count
recorder queue depth observed
fingerprint queue depth observed
recorder rejected blocks
fingerprint rejected blocks
```

Run:

```bash
flutter test test/macos_device_acceptance_contract_test.dart test/native_acceptance_evidence_copy_test.dart
```

- [ ] **Step 2: Port non-real-time telemetry and copy-evidence UI**

Poll `NativeAudioEngine.captureStatus` and `NativePcmRuntimePump.status` from Dart. Do not add callback-side logging or string formatting.

- [ ] **Step 3: Update macOS CI**

Require, in order where dependencies demand it:

```text
flutter analyze --no-fatal-warnings --no-fatal-infos
Flutter non-golden tests
CMake native configure/build with BUILD_TESTING=ON
ctest --output-on-failure
Core Audio discovery probe
built-dylib Dart FFI smoke
flutter build macos --debug
packaged app launch smoke
```

Hosted virtual/null endpoints remain explicitly non-acceptance evidence.

- [ ] **Step 4: Run/require the full exact-head matrix**

```bash
flutter analyze --no-fatal-warnings --no-fatal-infos
flutter test
cmake -S native -B build/native -DBUILD_TESTING=ON -DCMAKE_BUILD_TYPE=Release
cmake --build build/native --parallel
ctest --test-dir build/native --output-on-failure
npm test
```

Then require GitHub workflows on the same SHA: `CI`, `macOS Desktop CI`, `Web PWA Contract`, `Web Session Contract`, `Web Fingerprint Analysis Contract`, `Web Operator Contract`, `Web Chromaprint Package Contract`, `Web Mixer Contract`, and `Shared DSP Wasm Contract`.

- [ ] **Step 5: Open the replacement PR**

Title: `feat(audio): forward-port verified macOS capture path`.

The PR body maps each of the seven PR #15 review findings to its replacement test/commit and states that real-device evidence is still required before merge.

- [ ] **Step 6: Reply to PR #15 review threads**

Each reply names the replacement PR, exact fixing commit, and regression test. Resolve a PR #15 thread only after the replacement behavior is green; do not resolve merely because a replacement PR exists.

- [ ] **Step 7: Commit**

```bash
git add lib/audio lib/features/mixer docs/audio .github/workflows/macos-ci.yml test
git commit -m "test(audio): restore macOS acceptance and CI evidence"
```

---

### Task 8: Run physical/BlackHole acceptance and merge with provenance

**Files:**
- Update after a real run: `docs/audio/issue3-device-acceptance-record.md`
- Update only if evidence changes: `docs/audio/dsp-safety-evidence.md`

**Required evidence:** real physical macOS input or user-installed BlackHole-compatible endpoint; at least 10 seconds; WAV rate equals negotiated rate; zero recorder/fingerprint rejected blocks in the clean run; device removal prevents stale PCM; stable-UID reconnect recovers; post-limiter sample peak `<= 0.98`.

- [ ] **Step 1: Execute `docs/audio/macos-device-e2e.md` on a real Mac**

Use the app's `COPY EVIDENCE` output plus required visible observations. Do not commit credentials, endpoint UIDs, private paths, serial numbers, or raw secret-bearing logs.

- [ ] **Step 2: Independently validate WAV output**

Confirm the WAV opens, contains non-silent program audio, lasts at least 10 seconds, and its header sample rate equals the negotiated same-process telemetry rate.

- [ ] **Step 3: Exercise removal/reconnect**

Remove/unroute the source, observe device-loss state and no stale audio, restore the stable-UID source, then verify capture/meters recover.

- [ ] **Step 4: Mark PASS only when every field passes**

The record may contain:

```text
- Final result: PASS
- recorder rejected blocks: 0
- fingerprint rejected blocks: 0
```

only when those values were actually observed. Otherwise keep the result failed/pending and investigate.

- [ ] **Step 5: Push the acceptance commit and require fresh exact-head checks**

Re-read the replacement PR immediately before merge. Require: open, non-draft, base `main`, mergeable, exact expected head SHA, all required workflows green, real-device record PASS, and no unresolved blocking review threads.

- [ ] **Step 6: Squash-merge with expected-head guard**

Use the fresh replacement head SHA as `expected_head_sha`. Title: `feat(audio): forward-port verified macOS capture path (#<replacement PR number>)`.

- [ ] **Step 7: Verify post-merge main**

Require `main` to point to the returned merge SHA and relevant `main` CI/macOS workflows to succeed. Preserve the Web exact-tested-artifact/Vercel provenance path; do not manually rebuild or bypass it.

- [ ] **Step 8: Close superseded work and sync records**

Close Issue #3 with non-secret acceptance evidence and merge SHA; close PR #15 as superseded rather than merging it; update the Notion `LiveMixMaster — Implementation Plan & Delivery Tracker` with replacement PR, exact head, physical acceptance summary, merge SHA, CI run IDs, and relevant production deployment evidence. Keep repository-admin Issue #34 separate.

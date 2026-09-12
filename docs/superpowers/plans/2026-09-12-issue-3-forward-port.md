# Issue #3 Current-Main Forward-Port Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Forward-port the macOS Core Audio/device-capture work from stale PR #15 onto current `main`, close all seven review findings, preserve the current Web/shared-DSP architecture, and merge only after exact-head CI plus real-device acceptance are green.

**Architecture:** Keep `lib/main.dart` platform-neutral. The current conditional audio factory continues to choose desktop vs Web; the desktop implementation gains a `NativeDesktopRuntime` that owns the FFI-backed native engine, bounded PCM handoff, negotiated-format service coordinator, and telemetry. `MixerDeskView` receives an optional native `AudioEngine`/service facade on desktop while Web keeps its current browser surface. Native capture and lifecycle code are forward-ported, but DSP arithmetic remains centralized in `native/dsp_kernel.hpp` and is consumed by both desktop and Web paths.

**Tech Stack:** Flutter/Dart 3.5+, C++20/CMake, Core Audio Objective-C++, Dart FFI, lock-free SPSC queues, GitHub Actions, Vercel exact-artifact release flow.

**Spec:** `docs/superpowers/specs/2026-09-12-issue-3-forward-port-design.md`

## Global Constraints

- Base the implementation branch on current `main`; do not merge or force-rewrite stale PR #15.
- Keep `lib/main.dart` platform-neutral and preserve the current `audio_engine_factory_*` plus `app_surface_*` conditional split.
- `native/dsp_kernel.hpp` remains the canonical DSP kernel for desktop and Web.
- Preserve ABI-v1 Web DSP constraints: maximum 8 Web channels, 128-frame render quantum ceiling, `0.98` sample ceiling, `1.0e-6` parity tolerance, Emscripten 6.0.9, no production JavaScript DSP fallback, and no committed generated Wasm.
- The native callback performs no heap allocation, locks, disk/network I/O, logging, JSON serialization, or Dart calls.
- The current macOS capture backend supports exactly one active Core Audio capture route. A second route is rejected explicitly until independent capture routes exist.
- No resampling is introduced in this forward-port. Recording and fingerprint consumers must use the negotiated capture sample rate.
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
- `AudioEngine` keeps the historical asynchronous control surface used by PR #15: `initialize`, `refreshInputDevices`, `addChannel`, `removeChannel`, `setTrim`, `setFader`, `setMute`, `setSolo`, `setMasterGain`, meter streams, route-state stream, and `dispose`.
- Extend `InputChannelConfig` with `int channelPairIndex = 0`.
- `NativeDesktopRuntime` owns `NativeAudioEngine audioEngine` plus later tasks' service coordinator, PCM pump, and telemetry.
- `DesktopNativeAudioEngine.prepareRuntime()` returns `Future<NativeDesktopRuntime>` after the library has been loaded successfully.
- Change the conditional app surface signature to `Widget buildPrimaryOperatorSurface(AudioEnginePort audioEngine)`; the Web implementation may ignore the argument, while desktop type-checks `DesktopNativeAudioEngine` and builds a `FutureBuilder<NativeDesktopRuntime>`.

- [ ] **Step 1: Create the replacement implementation branch from the accepted production `main` SHA**

Run conceptually through the GitHub API:

```text
branch: feat/issue-3-forward-port
base: b2dcd03c13230cf7a832b51d75b0caf79f29cc4d
force: false
```

Expected: the new branch has no ancestry from `feat/issue-3-macos-audio-path` beyond commits already present on `main`.

- [ ] **Step 2: Write a failing platform-seam test**

Add to `test/native_desktop_runtime_factory_test.dart`:

```dart
test('desktop factory exposes native runtime preparation without changing main bootstrap contract', () {
  final engine = DesktopNativeAudioEngine(
    loadNativeLibrary: () => NativeLibraryLoadResult.loaded(
      library: fakeDynamicLibrary,
      loadedPath: '/tmp/liblive_mixer_engine.dylib',
    ),
    runtimeBuilder: (_) async => fakeRuntime,
  );

  expect(engine.initialize().isAvailable, isTrue);
  expect(engine.prepareRuntime(), completion(same(fakeRuntime)));
});
```

The production change that makes this pass is the new `prepareRuntime()` seam; the test must fail first because current `DesktopNativeAudioEngine` exposes only `initialize()`.

- [ ] **Step 3: Run the focused test and verify RED**

Run:

```bash
flutter test test/native_desktop_runtime_factory_test.dart test/native_startup_gate_test.dart
```

Expected: FAIL because `prepareRuntime`, `runtimeBuilder`, and `NativeDesktopRuntime` do not yet exist.

- [ ] **Step 4: Port the pure-Dart native contracts without changing Web behavior**

Create/port the historical `AudioEngine` and binding models, with the channel-pair addition:

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

Keep the rest of the PR #15 bridge semantics, but do not copy its old `main.dart` bootstrap.

- [ ] **Step 5: Add the desktop runtime seam**

Implement the concrete factory shape:

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
  AudioEngineBootstrapResult initialize() { /* preserve current behavior */ }

  Future<NativeDesktopRuntime> prepareRuntime() {
    final library = _nativeLibraryResult?.library;
    if (library == null) {
      return Future.error(StateError('Native library is not loaded.'));
    }
    return _runtimeBuilder(library);
  }
}
```

- [ ] **Step 6: Route the available desktop surface through `prepareRuntime()` while keeping `main.dart` platform-neutral**

Change only the available branch in `LiveMixMasterApp`:

```dart
home: result == null || result.isAvailable
    ? buildPrimaryOperatorSurface(audioEngine)
    : _AudioEngineUnavailable(result: result),
```

Desktop `buildPrimaryOperatorSurface` uses a `FutureBuilder<NativeDesktopRuntime>` and ultimately constructs:

```dart
MixerDeskView(
  audioEngine: runtime.audioEngine,
  recordingWriter: runtime.services.recordingWriter,
  fingerprintService: runtime.services.fingerprintService,
)
```

For Task 1, `runtime.services` may be a stable facade with unavailable/no-op service state until Task 4 implements negotiated-format activation. Web continues returning the existing Web reference surface and must not import `dart:io`/FFI code.

- [ ] **Step 7: Run platform/bootstrap tests and verify GREEN**

Run:

```bash
flutter test test/native_desktop_runtime_factory_test.dart test/native_startup_gate_test.dart test/web_release_compile_boundary_test.dart
```

Expected: PASS and no Web import boundary regression.

- [ ] **Step 8: Commit Task 1**

```bash
git add lib/audio lib/app lib/main.dart lib/features/mixer/mixer_desk_view.dart test/native_desktop_runtime_factory_test.dart test/native_startup_gate_test.dart
git commit -m "feat(audio): forward-port desktop native runtime seam"
```

---

### Task 2: Forward-port the native capture engine and keep shared DSP canonical

**Files:**
- Port/create: `native/include/lmm_engine.h`
- Port/create: `native/include/lmm_capture.h`
- Port/create: `native/include/lmm_device_catalog.h`
- Port/create: `native/include/lmm_permissions.h`
- Port/create: `native/include/lmm_pcm_handoff.h`
- Port/create: `native/include/spsc_ring_buffer.h`
- Modify: `native/live_mixer_engine.cpp`
- Port/create: `native/macos/coreaudio_capture.mm`
- Port/create: `native/macos/coreaudio_device_catalog.mm`
- Port/create: `native/macos/audio_input_permissions.mm`
- Modify: `native/CMakeLists.txt`
- Port/create tests: `native/tests/engine_signal_tests.cpp`, `capture_state_tests.cpp`, `capture_handoff_integration_tests.cpp`, `pcm_handoff_tests.cpp`, `realtime_atomic_contract_tests.cpp`, `spsc_ring_buffer_tests.cpp`, `device_catalog_contract_tests.cpp`, `audio_permission_contract_tests.cpp`
- Preserve: `native/dsp_kernel.hpp`

**Interfaces:**
- Native engine control setters:

```cpp
bool lmm_set_channel_fader(const char* id, float normalized_fader);
bool lmm_set_channel_muted(const char* id, bool muted);
bool lmm_set_channel_solo(const char* id, bool solo);
bool lmm_set_channel_trim_db(const char* id, float trim_db);
bool lmm_set_master_gain_db(float gain_db);
```

- The callback reads precomputed atomic linear gains; `std::pow`/dB conversion happens only in the control setter.
- Bound Core Audio PCM is still handed to the native engine through a fixed-capacity callback-safe path and then to recorder/fingerprint SPSC queues.

- [ ] **Step 1: Write RED tests for trim and master gain affecting the shared DSP output**

Add deterministic assertions to `native/tests/engine_signal_tests.cpp`:

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

- [ ] **Step 2: Run native test and verify RED**

Run:

```bash
cmake -S native -B build/native -DBUILD_TESTING=ON -DCMAKE_BUILD_TYPE=Debug
cmake --build build/native --parallel
ctest --test-dir build/native --output-on-failure
```

Expected: compile/test failure because trim/master setters are absent.

- [ ] **Step 3: Integrate PR #15 lifecycle/SPSC code around `dsp_kernel.hpp`, not instead of it**

In `live_mixer_engine.cpp`, build `DspChannelConfig` arrays from native channel atomics and call the canonical helper:

```cpp
const auto master_meter = processStereoBlock(
    configs.data(),
    channel_input,
    configs.size(),
    master_output,
    frames,
    master_.gain.load(std::memory_order_relaxed),
    meters.data());
```

Do not duplicate limiter/fader/solo arithmetic from stale PR #15.

- [ ] **Step 4: Implement control-thread trim/master setters**

Use bounded validation and store linear values atomically:

```cpp
bool setTrimDb(const char* id, float trim_db) {
  if (!std::isfinite(trim_db) || trim_db < -18.0F || trim_db > 12.0F) return false;
  Channel* channel = findChannel(id);
  if (!channel) return false;
  const float linear = std::pow(10.0F, trim_db / 20.0F);
  channel->linearTrim.store(linear, std::memory_order_relaxed);
  return true;
}

bool setMasterGainDb(float gain_db) {
  if (!std::isfinite(gain_db) || gain_db < -90.0F || gain_db > 12.0F) return false;
  master_.gain.store(std::pow(10.0F, gain_db / 20.0F), std::memory_order_relaxed);
  return true;
}
```

- [ ] **Step 5: Run all native deterministic/callback-safety tests and verify GREEN**

Run the same CMake/CTest commands. Expected: all tests pass, including lock-free atomic and SPSC tests.

- [ ] **Step 6: Commit Task 2**

```bash
git add native
git commit -m "feat(audio): forward-port Core Audio engine on shared DSP kernel"
```

---

### Task 3: Fix single-route semantics, channel-pair capture, and FFI parity

**Files:**
- Modify: `native/include/lmm_capture.h`
- Modify: `native/macos/coreaudio_capture.mm`
- Modify: `native/live_mixer_engine.cpp`
- Modify/create: `lib/audio/native_audio_bindings.dart`
- Port/modify: `lib/audio/native_audio_ffi_bindings.dart`
- Modify: `lib/audio/native_audio_engine.dart`
- Modify: `lib/audio/audio_engine_bridge.dart`
- Test: `native/tests/capture_conversion_tests.cpp`
- Test: `test/native_audio_engine_contract_test.dart`
- Test: `test/native_audio_ffi_bindings_test.dart`

**Interfaces:**
- Change capture start to carry the selected pair:

```cpp
bool lmm_capture_start(const char* device_uid, std::uint32_t channel_pair_index);
```

and Dart:

```dart
bool captureStart(String uid, int channelPairIndex);
```

- Exactly one live native route is supported. `NativeAudioEngine.addChannel` rejects a second configured channel before mutating native state.

- [ ] **Step 1: Add RED native conversion test for CH 3-4**

Add a four-channel interleaved fixture to `capture_conversion_tests.cpp`:

```cpp
const float interleaved[] = {
  0.1F, 0.2F, 0.3F, 0.4F,
  0.5F, 0.6F, 0.7F, 0.8F,
};
// pair index 1 means channels 3-4
REQUIRE(convert_test_pcm(interleaved, 4, 2, /*pair=*/1, out));
REQUIRE(out[0] == Approx(0.3F));
REQUIRE(out[1] == Approx(0.4F));
REQUIRE(out[2] == Approx(0.7F));
REQUIRE(out[3] == Approx(0.8F));
```

Update the testing hook signature to accept the pair index as well, so hosted CI exercises the same conversion selector used by Core Audio.

- [ ] **Step 2: Add RED Dart test for second-route rejection**

In `test/native_audio_engine_contract_test.dart`:

```dart
test('second native live route is rejected before capture is rebound', () async {
  final bindings = FakeNativeAudioBindings();
  final engine = NativeAudioEngine(
    bindings: bindings,
    permissionState: AudioPermissionState.granted,
    pollInterval: null,
  );
  await engine.initialize();
  await engine.refreshInputDevices();
  await engine.addChannel(channel('a', pair: 0));

  await expectLater(
    engine.addChannel(channel('b', pair: 1)),
    throwsA(isA<StateError>()),
  );
  expect(bindings.captureStartCalls, hasLength(1));
  expect(bindings.boundChannelIds, ['a']);
});
```

- [ ] **Step 3: Run focused tests and verify RED**

Run:

```bash
flutter test test/native_audio_engine_contract_test.dart test/native_audio_ffi_bindings_test.dart
ctest --test-dir build/native --output-on-failure -R capture_conversion
```

Expected: failures because pair routing and deterministic second-route rejection are absent.

- [ ] **Step 4: Implement pair-aware Core Audio conversion**

Resolve left/right source channels as:

```cpp
const std::uint32_t left_channel = channel_pair_index * 2;
const std::uint32_t right_channel = left_channel + 1;
if (left_channel >= total_channels) return false;
const std::uint32_t effective_right =
    right_channel < total_channels ? right_channel : left_channel;
```

Use those indices for interleaved and non-interleaved conversion paths. No dynamic allocation may be added in the callback.

- [ ] **Step 5: Implement explicit single-route behavior in Dart host adapter**

Before any native mutation:

```dart
if (_channels.isNotEmpty) {
  throw StateError(
    'The macOS native backend currently supports one active capture route.',
  );
}
```

Then configure trim, fader, mute, solo, bind channel, and call `captureStart(channel.endpointId, channel.channelPairIndex)`.

- [ ] **Step 6: Run native + Dart FFI tests and verify GREEN**

Run:

```bash
flutter test test/native_audio_engine_contract_test.dart test/native_audio_ffi_bindings_test.dart
ctest --test-dir build/native --output-on-failure
```

Expected: PASS.

- [ ] **Step 7: Commit Task 3**

```bash
git add native lib/audio test/native_audio_engine_contract_test.dart test/native_audio_ffi_bindings_test.dart
git commit -m "fix(audio): preserve native route and selected channel pair"
```

---

### Task 4: Bind recorder and fingerprinting to the negotiated sample rate

**Files:**
- Create: `lib/audio/native_pcm_service_coordinator.dart`
- Modify: `lib/audio/native_desktop_runtime.dart`
- Port/create: `lib/audio/native_pcm_handoff_bindings.dart`
- Port/create: `lib/audio/native_recording_drain.dart`
- Port/create: `lib/audio/native_pcm_runtime_pump.dart`
- Test: `test/native_runtime_acceptance_wiring_contract_test.dart`
- Create test: `test/native_pcm_service_coordinator_test.dart`
- Test: `test/native_recording_drain_test.dart`

**Interfaces:**
- `NativePcmServiceCoordinator` is a stable facade used by the desktop mixer. It creates the concrete `LosslessRecordingWriter` and `FingerprintService` only after native capture reports a valid negotiated sample rate.
- Public members:

```dart
abstract interface class NativePcmServices {
  LosslessRecordingWriter? get recordingWriter;
  FingerprintService? get fingerprintService;
  int? get sampleRate;
  Future<void> activateForCapture(NativeCaptureStatus status);
  Future<void> dispose();
}
```

- Reconfiguration while recording is active fails closed; it does not silently change WAV format mid-file.

- [ ] **Step 1: Write RED negotiated-rate service test**

```dart
test('creates recorder and fingerprint services at negotiated capture rate', () async {
  final coordinator = NativePcmServiceCoordinator(
    destinationDirectory: '/tmp/lmm-test',
    acoustIdApiKey: '',
    fingerprintFactory: (config) => FakeFingerprintService(config),
    recordingFactory: (config) => LosslessRecordingWriter(config: config),
  );

  await coordinator.activateForCapture(
    const NativeCaptureStatus(
      state: NativeCaptureState.running,
      sampleRate: 44100,
      bufferFrames: 512,
      inputChannels: 2,
      formatFlags: 0,
      callbackCount: 1,
      xrunCount: 0,
      averageCallbackUs: 100,
      maxCallbackUs: 120,
    ),
  );

  expect(coordinator.sampleRate, 44100);
  expect(coordinator.recordingWriter!.config.sampleRate, 44100);
  expect(coordinator.fingerprintService!.config.sampleRate, 44100);
});
```

- [ ] **Step 2: Run test and verify RED**

Run:

```bash
flutter test test/native_pcm_service_coordinator_test.dart
```

Expected: FAIL because coordinator does not exist.

- [ ] **Step 3: Implement the coordinator with no resampler**

Validate negotiated rate strictly:

```dart
final rate = status.sampleRate.round();
if (status.state != NativeCaptureState.running || rate <= 0) {
  throw StateError('Capture format is not ready for PCM consumers.');
}
```

Construct both consumers with `sampleRate: rate`, `channels: 2`, and the existing recording bit-depth policy. Start fingerprinting only after this configuration exists.

- [ ] **Step 4: Activate services immediately after successful `captureStart` and before the PCM pump is allowed to deliver blocks**

`NativeDesktopRuntime` coordinates the ordering:

```text
captureStart -> captureStatus(running + negotiated rate)
-> services.activateForCapture(status)
-> start/enable NativePcmRuntimePump
```

If service activation fails, stop capture and surface a failed route state; do not continue with a guessed 48 kHz consumer.

- [ ] **Step 5: Run focused service/handoff tests and verify GREEN**

```bash
flutter test \
  test/native_pcm_service_coordinator_test.dart \
  test/native_recording_drain_test.dart \
  test/native_runtime_acceptance_wiring_contract_test.dart
```

Expected: PASS, including 44.1 kHz and 96 kHz fixtures.

- [ ] **Step 6: Commit Task 4**

```bash
git add lib/audio test/native_pcm_service_coordinator_test.dart test/native_recording_drain_test.dart test/native_runtime_acceptance_wiring_contract_test.dart
git commit -m "fix(audio): bind PCM services to negotiated capture rate"
```

---

### Task 5: Make macOS permission recovery live and functional

**Files:**
- Modify: `lib/audio/native_audio_engine.dart`
- Modify: `lib/audio/native_desktop_runtime.dart`
- Create: `lib/audio/macos_audio_settings_launcher.dart`
- Port/modify: `lib/features/patchbay/audio_route_recovery_banner.dart`
- Modify: `lib/features/mixer/mixer_desk_view.dart`
- Test: `test/native_audio_permission_refresh_test.dart`
- Test: `test/audio_route_recovery_ui_test.dart`
- Create test: `test/macos_audio_settings_launcher_test.dart`

**Interfaces:**
- `NativeAudioEngine.permissionStateProvider` is always supplied in production and calls `FfiAudioInputPermissionBindings.currentState()` on refresh/poll.
- `MacosAudioSettingsLauncher.openMicrophonePrivacy()` runs the macOS Settings deep-link from non-real-time Dart code.

- [ ] **Step 1: Write RED test for permission re-read after external Settings change**

```dart
test('refresh re-reads permission after it changes without restarting', () async {
  var permission = AudioPermissionState.denied;
  final engine = NativeAudioEngine(
    bindings: fakeBindings,
    permissionState: permission,
    permissionStateProvider: () => permission,
    pollInterval: null,
  );

  await engine.initialize();
  expect(await engine.refreshInputDevices(), isEmpty);

  permission = AudioPermissionState.granted;
  expect(await engine.refreshInputDevices(), isNotEmpty);
  expect(engine.routeState, AudioRouteState.idle);
});
```

- [ ] **Step 2: Write RED launcher test**

Inject a process runner and assert the exact macOS deep link:

```dart
test('opens microphone privacy settings', () async {
  final calls = <List<String>>[];
  final launcher = MacosAudioSettingsLauncher(
    runProcess: (executable, arguments) async {
      calls.add([executable, ...arguments]);
      return 0;
    },
  );

  await launcher.openMicrophonePrivacy();
  expect(calls.single.first, 'open');
  expect(
    calls.single[1],
    'x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone',
  );
});
```

- [ ] **Step 3: Run tests and verify RED**

```bash
flutter test \
  test/native_audio_permission_refresh_test.dart \
  test/macos_audio_settings_launcher_test.dart \
  test/audio_route_recovery_ui_test.dart
```

Expected: launcher test fails because the launcher is absent; production wiring test fails because current PR #15 constructor used a permission snapshot.

- [ ] **Step 4: Wire the live permission provider and real Settings action**

Production desktop runtime must construct:

```dart
final permissions = FfiAudioInputPermissionBindings(library);
final engine = NativeAudioEngine(
  bindings: bindings,
  permissionState: permissions.currentState(),
  permissionStateProvider: permissions.currentState,
  requestPermission: permissions.requestAccess,
);
```

`OPEN AUDIO SETTINGS` calls `await settingsLauncher.openMicrophonePrivacy()` and then leaves refresh as an explicit follow-up action when the user returns.

- [ ] **Step 5: Run permission/UI tests and verify GREEN**

Run the same Flutter test command. Expected: PASS.

- [ ] **Step 6: Commit Task 5**

```bash
git add lib/audio lib/features test/native_audio_permission_refresh_test.dart test/macos_audio_settings_launcher_test.dart test/audio_route_recovery_ui_test.dart
git commit -m "fix(audio): make macOS permission recovery live"
```

---

### Task 6: Wire patchbay, channel controls, trim, and master fader into native PCM

**Files:**
- Modify: `lib/features/mixer/mixer_desk_view.dart`
- Modify: `lib/features/patchbay/patchbay_routing_modal.dart`
- Modify: `lib/audio/native_audio_engine.dart`
- Modify: `lib/audio/native_audio_bindings.dart`
- Modify: `lib/audio/native_audio_ffi_bindings.dart`
- Test: `test/mixer_audio_route_lifecycle_test.dart`
- Test: `test/mixer_native_meter_stream_test.dart`
- Test: `test/native_audio_engine_contract_test.dart`
- Create test: `test/mixer_native_control_wiring_test.dart`

**Interfaces:**
- `MixerDeskView` gains optional `AudioEngine? audioEngine` while retaining the existing no-engine behavior used by Web/reference tests.
- A configured patchbay result becomes an `InputChannelConfig` including `endpoint.id`, `channelPairIndex`, `initialTrimDb`, and current fader/mute/solo state.
- Normalized master fader maps to dB before `AudioEngine.setMasterGain` using one helper shared by UI tests:

```dart
double masterFaderToDb(double normalized) {
  final value = normalized.clamp(0.0, 1.0);
  if (value == 0) return -90.0;
  return 20 * (math.log(value) / math.ln10);
}
```

- [ ] **Step 1: Write RED native-control widget test**

```dart
testWidgets('desktop mixer forwards patchbay pair, trim, fader, mute, solo and master controls', (tester) async {
  final engine = FakeAudioEngine();
  await tester.pumpWidget(MaterialApp(home: MixerDeskView(audioEngine: engine)));

  await configureEndpoint(tester, endpointId: 'device-uid', pair: 1, trimDb: -3);
  expect(engine.added.single.endpointId, 'device-uid');
  expect(engine.added.single.channelPairIndex, 1);
  expect(engine.added.single.trimDb, -3);

  await moveFirstChannelFader(tester, 0.5);
  expect(engine.lastFaderValue, 0.5);

  await toggleFirstChannelMute(tester);
  expect(engine.lastMuteValue, isTrue);

  await toggleFirstChannelSolo(tester);
  expect(engine.lastSoloValue, isTrue);

  await moveMasterFader(tester, 0.5);
  expect(engine.lastMasterGainDb, closeTo(-6.0206, 1.0e-3));
});
```

- [ ] **Step 2: Run widget/native control tests and verify RED**

```bash
flutter test \
  test/mixer_native_control_wiring_test.dart \
  test/native_audio_engine_contract_test.dart \
  test/mixer_audio_route_lifecycle_test.dart
```

Expected: FAIL because current-main `MixerDeskView` mutates only local widget state.

- [ ] **Step 3: Wire patchbay add/remove and strip controls**

For desktop/native mode, call the engine first and update local UI state only after the Future succeeds. On failure, retain the prior visible state and show the existing error surface/snackbar.

Initial attach must call native trim during channel setup:

```dart
await audioEngine.addChannel(config);
await audioEngine.setTrim(config.id, config.trimDb);
```

or equivalently perform trim inside `NativeAudioEngine.addChannel` before capture starts; use exactly one path to avoid duplicate setters.

- [ ] **Step 4: Wire master fader**

```dart
onChanged: (value) async {
  final engine = widget.audioEngine;
  if (engine != null) {
    await engine.setMasterGain(masterFaderToDb(value));
  }
  if (mounted) setState(() => _masterFader = value);
}
```

The native setter stores a precomputed atomic linear gain, so no dB conversion happens in the callback.

- [ ] **Step 5: Replace synthetic desktop meter values with native meter streams when an engine is supplied**

Subscribe to `audioEngine.channelMeters` and `audioEngine.masterMeters`; preserve static reference values only when `audioEngine == null`. Do not display sample-peak values as standards-based dBTP/LUFS.

- [ ] **Step 6: Run control/lifecycle/meter tests and verify GREEN**

```bash
flutter test \
  test/mixer_native_control_wiring_test.dart \
  test/mixer_audio_route_lifecycle_test.dart \
  test/mixer_native_meter_stream_test.dart \
  test/native_audio_engine_contract_test.dart
```

Expected: PASS.

- [ ] **Step 7: Commit Task 6**

```bash
git add lib/features lib/audio test/mixer_native_control_wiring_test.dart test/mixer_audio_route_lifecycle_test.dart test/mixer_native_meter_stream_test.dart test/native_audio_engine_contract_test.dart
git commit -m "fix(audio): wire desktop mixer controls to native PCM"
```

---

### Task 7: Restore acceptance telemetry, docs, and current-main CI coverage

**Files:**
- Port/create: `lib/audio/native_acceptance_telemetry.dart`
- Port/create: `lib/features/mixer/native_acceptance_telemetry_panel.dart`
- Port docs: `docs/audio/macos-device-e2e.md`
- Port docs: `docs/audio/issue3-device-acceptance-record.md`
- Port/update: `docs/audio/dsp-safety-evidence.md`
- Modify: `.github/workflows/macos-ci.yml`
- Test: `test/native_acceptance_evidence_copy_test.dart`
- Test: `test/macos_device_acceptance_contract_test.dart`
- Test: `test/native_runtime_acceptance_wiring_contract_test.dart`
- Preserve/execute: all current Web/PWA/shared-DSP workflows and tests.

**Interfaces:**
- Same-process telemetry reports callback count, average/max callback duration, xrun count, negotiated sample rate/buffer/channels, recorder/fingerprint queue depths, and rejected-block counters.
- `COPY EVIDENCE` output remains non-secret: no endpoint UID, filesystem path, credentials, account data, hardware serial, or unrelated device identifiers.

- [ ] **Step 1: Write/port the acceptance contract first and verify the forward-port is incomplete**

The contract must require these literal evidence fields:

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

Expected: RED until the files/UI are forward-ported.

- [ ] **Step 2: Port telemetry and copy-evidence behavior**

Use non-real-time polling of `NativeAudioEngine.captureStatus` and `NativePcmRuntimePump.status`. Do not add callback-side logging or string formatting.

- [ ] **Step 3: Update macOS CI to exercise native and shared-main boundaries**

The macOS workflow must run at minimum:

```text
flutter analyze --no-fatal-warnings --no-fatal-infos
flutter test (non-golden suite)
cmake configure/build native with BUILD_TESTING=ON
ctest --output-on-failure
Core Audio discovery probe
built-dylib Dart FFI smoke
flutter build macos --debug
packaged app launch smoke
```

It must not claim the hosted Core Audio virtual/null endpoints satisfy physical/BlackHole acceptance.

- [ ] **Step 4: Run the full candidate test matrix on exact head**

Run locally where available and require GitHub checks for the same SHA:

```bash
flutter analyze --no-fatal-warnings --no-fatal-infos
flutter test
cmake -S native -B build/native -DBUILD_TESTING=ON -DCMAKE_BUILD_TYPE=Release
cmake --build build/native --parallel
ctest --test-dir build/native --output-on-failure
npm test
```

Then require the current-main repository workflows to pass, including:

```text
CI
macOS Desktop CI
Web PWA Contract
Web Session Contract
Web Fingerprint Analysis Contract
Web Operator Contract
Web Chromaprint Package Contract
Web Mixer Contract
Shared DSP Wasm Contract
```

Do not repeat separately-green compile/E2E checks outside the workflow unless a changed boundary requires debugging.

- [ ] **Step 5: Open the replacement PR and map the seven PR #15 findings to exact tests/commits**

PR title:

```text
feat(audio): forward-port verified macOS capture path
```

PR body must state that PR #15 is superseded only after the replacement merges and that real-device evidence is still required.

- [ ] **Step 6: Reply to PR #15 review threads with replacement evidence, but do not resolve them merely because a new PR exists**

Each reply names the replacement PR, test, and commit that fixes the finding. Resolve a thread only after the corresponding replacement behavior is green and review has no remaining objection.

- [ ] **Step 7: Commit Task 7**

```bash
git add lib/audio lib/features/mixer docs/audio .github/workflows/macos-ci.yml test
git commit -m "test(audio): restore macOS acceptance and CI evidence"
```

---

### Task 8: Execute the physical/BlackHole acceptance gate and merge with provenance

**Files:**
- Update only after a real run: `docs/audio/issue3-device-acceptance-record.md`
- Possibly update after findings: `docs/audio/dsp-safety-evidence.md`
- No secret-bearing logs or raw device dumps are committed.

**Interfaces / required evidence:**
- Source: physical macOS input or user-installed BlackHole-compatible endpoint.
- Duration: at least 10 seconds of actual capture/recording.
- Clean run: recorder and fingerprint rejected-block counters both remain zero.
- WAV sample rate equals negotiated capture sample rate.
- Device removal prevents stale audio; stable UID rediscovery and reconnect recover meters.
- Post-limiter sample peak is `<= 0.98`; no standards-based dBTP/LUFS claim.

- [ ] **Step 1: Run `docs/audio/macos-device-e2e.md` on a real macOS host**

Record only the non-secret values generated by the app's `COPY EVIDENCE` action plus the required visible observations.

- [ ] **Step 2: Independently validate the produced WAV**

Confirm it opens, contains non-silent program audio, lasts at least 10 seconds, and its WAV header sample rate exactly matches the negotiated rate shown in same-process telemetry.

- [ ] **Step 3: Exercise device loss and recovery**

Remove/unroute the source, verify `deviceLost`/recovery state without stale PCM, restore the same stable UID route, and verify meters/capture resume.

- [ ] **Step 4: Update the acceptance record from PENDING to PASS only if every required field passed**

The final section must read:

```text
- Final result: PASS
- recorder rejected blocks: 0
- fingerprint rejected blocks: 0
```

If either rejected-block count is non-zero, leave the record failed/pending and investigate; never rewrite the value to zero.

- [ ] **Step 5: Push the acceptance-record commit and require fresh exact-head CI**

All replacement-PR checks must complete successfully on the acceptance-record head SHA. Verify no unresolved blocking review threads remain.

- [ ] **Step 6: Merge with an expected-head SHA guard**

Use squash merge only after exact-head verification:

```text
merge method: squash
expected_head_sha: <exact replacement PR head>
commit title: feat(audio): forward-port verified macOS capture path (#<replacement PR>)
```

The expected SHA is taken from the fresh PR readback immediately before merge; never hard-code a stale candidate.

- [ ] **Step 7: Verify `main` and post-merge workflows**

Require `main` to point to the returned merge SHA and require the relevant `main` CI/macOS jobs to succeed. Web production promotion must continue to use its exact tested artifact/provenance path; do not manually rebuild or bypass it.

- [ ] **Step 8: Close the superseded work only after the replacement is merged and verified**

- Close Issue #3 with the non-secret acceptance evidence and replacement merge SHA.
- Close PR #15 as superseded by the merged replacement; do not merge PR #15 itself.
- Update the Notion `LiveMixMaster — Implementation Plan & Delivery Tracker` with the replacement PR, exact head, real-device acceptance summary, merge SHA, CI runs, and any relevant production deployment evidence.
- Leave repository-admin Issue #34 separate; do not weaken or conflate its branch-protection gate with the audio acceptance gate.

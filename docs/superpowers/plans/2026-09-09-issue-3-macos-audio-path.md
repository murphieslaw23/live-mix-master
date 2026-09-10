# Issue #3 macOS Audio Path Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish the first real LiveMixMaster audio path on macOS: stable Core Audio endpoint discovery and capture, real-time-safe mixing/DSP handoff, Flutter-visible lifecycle/permission state, and an evidence-backed physical-or-BlackHole device E2E run.

**Architecture:** macOS is the only initial verified device target. Core Audio owns endpoint discovery and capture using stable device UIDs; captured PCM enters a fixed-capacity native path and is mixed on the native audio thread. Dart receives control/status snapshots only and never participates in the callback. Deterministic DSP/queue/device-catalog tests are CI gates; a physical or BlackHole device run is a separate acceptance gate and must not be simulated.

**Tech Stack:** Flutter 3.47.2 / Dart FFI, C++17 native engine, Objective-C++ Core Audio/HAL, CMake/CTest, macOS App Sandbox, GitHub Actions.

**Spec:** GitHub Issue #3 and `docs/product-spec.md`.

## Global Constraints

- Initial device-E2E target is macOS only.
- Enumerate by stable Core Audio UID; never route by display-name matching.
- Do not assume 48 kHz, stereo, interleaved layout, or a fixed buffer size.
- Audio callback: no heap allocation, mutex/lock, disk I/O, HTTP, logging, or Dart/isolate communication.
- Recorder/fingerprint/meter transfer uses preallocated bounded lock-free storage with observable overflow counters.
- Physical microphone access requires a usage description and sandbox audio-input entitlement.
- Loopback setup is an explicit user-installed virtual input route (BlackHole-compatible); no claim of native system-audio capture is made by this phase.
- Device E2E evidence is mandatory before Issue #3 closes.

---

### Task 1: Define deterministic native DSP and queue contracts

**Files:**
- Create: `native/include/lmm_engine.h`
- Create: `native/tests/engine_signal_tests.cpp`
- Create: `native/tests/spsc_ring_buffer_tests.cpp`
- Create: `native/include/spsc_ring_buffer.h`
- Modify: `native/CMakeLists.txt`
- Modify: `native/live_mixer_engine.cpp`

**Interfaces:**
- Produces stable C ABI controls for init/channel controls/block processing and meter snapshots.
- Produces `SpscRingBuffer<T, Capacity>` with no allocation after construction and observable rejected-write count.

- [ ] Write deterministic tests for silence, -12 dBFS sine, full-scale/clipped sine, impulse, two-channel sum, mute, solo, fader law, and limiter ceiling.
- [ ] Verify tests fail against the current three-function prototype.
- [ ] Add the smallest test-only/native ABI needed to process supplied interleaved stereo blocks and read channel/master meters.
- [ ] Add fixed-capacity SPSC ring-buffer tests for FIFO order, full rejection, wraparound, and overflow counter.
- [ ] Implement ring buffer using atomics and compile-time storage only.
- [ ] Run CTest and keep all callback-path structures allocation-free after initialization.

### Task 2: Add macOS Core Audio endpoint catalog with stable IDs

**Files:**
- Create: `native/include/lmm_device_catalog.h`
- Create: `native/macos/coreaudio_device_catalog.mm`
- Create: `native/tests/device_catalog_contract_tests.cpp`
- Modify: `native/CMakeLists.txt`

**Interfaces:**
- `lmm_list_input_devices(...)` returns capacity-bounded endpoint records containing Core Audio object ID, UID, display name, input-channel count, nominal sample rate, and current buffer-frame size.
- Endpoint selection consumes UID, not display name.

- [ ] Write ABI/record-boundary tests first.
- [ ] Enumerate `kAudioHardwarePropertyDevices` and query input scope/channel configuration with `AudioObjectGetPropertyData`.
- [ ] Resolve stable `kAudioDevicePropertyDeviceUID` and human-readable name separately.
- [ ] Exclude devices with zero input channels.
- [ ] Add a macOS CI probe that records endpoint count but treats zero hosted-runner endpoints as infrastructure information, not device-E2E success.

### Task 3: Add microphone permission and sandbox capability

**Files:**
- Modify: `macos/Runner/Info.plist`
- Modify: `macos/Runner/DebugProfile.entitlements`
- Modify: `macos/Runner/Release.entitlements`
- Create: `lib/audio/audio_permission_state.dart`
- Test: `test/audio_permission_contract_test.dart`

**Interfaces:**
- Native status maps to `unknown`, `granted`, `denied`, `restricted`/unavailable without conflating no-device with permission denial.

- [ ] Add failing repository contract test for `NSMicrophoneUsageDescription` and sandbox audio-input entitlement.
- [ ] Add the keys with operator-facing rationale copy.
- [ ] Add typed Dart permission/lifecycle vocabulary.

### Task 4: Implement Core Audio capture with negotiated format

**Files:**
- Create: `native/macos/coreaudio_capture.mm`
- Create: `native/include/lmm_capture.h`
- Modify: `native/CMakeLists.txt`
- Test: `native/tests/capture_state_tests.cpp`

**Interfaces:**
- Start capture by device UID.
- Report actual sample rate, buffer frames, channel count, format flags, callback count/duration, xruns, and lifecycle state.
- Convert selected endpoint input to the engine's internal float32 stereo bus outside any Dart boundary while preserving source-format metadata.

- [ ] Write state-machine tests for start/stop/remove/format-change/recover and invalid UID.
- [ ] Query device stream format and buffer frame size before starting.
- [ ] Preallocate capture buffers and channel-map/conversion state before callback start.
- [ ] Register/start Core Audio IOProc; callback performs bounded copies/conversion/mixing only.
- [ ] On removal/format change, stop stale routing, emit lifecycle state, and require explicit or controlled reconnect.

### Task 5: Connect capture to mixer controls and PCM fan-out

**Files:**
- Modify: `native/live_mixer_engine.cpp`
- Modify: `native/include/lmm_engine.h`
- Create: `native/include/lmm_pcm_handoff.h`
- Test: `native/tests/pcm_handoff_tests.cpp`

**Interfaces:**
- One captured source maps to one dynamic mixer channel.
- Master PCM is copied into bounded recorder/fingerprint queues after limiting; meter snapshots use a separate bounded snapshot path.

- [ ] Write tests proving mute/solo/fader affect captured-source master output.
- [ ] Write tests proving recorder/fingerprint queues receive post-master PCM and overflow is observable without blocking.
- [ ] Implement bounded fan-out and zero/stale-source behavior after device loss.

### Task 6: Implement Dart FFI host adapter and actionable UI lifecycle

**Files:**
- Create: `lib/audio/native_audio_engine.dart`
- Create: `lib/audio/native_audio_bindings.dart`
- Modify: `lib/audio/audio_engine_bridge.dart`
- Modify: patchbay/mixer recovery UI files under `lib/features/`
- Test: `test/native_audio_engine_contract_test.dart`
- Test: relevant widget/state tests

**Interfaces:**
- Dart enumerates endpoints, selects by UID, configures controls, polls compact status/meter snapshots, and receives typed lifecycle state without callback crossing.

- [ ] Write failing FFI-adapter tests around a fake bindings surface.
- [ ] Bind device catalog/capture/meter/control ABI.
- [ ] Surface no-device, permission-denied, no-signal, removed, format-error, overrun, and recovered states using existing repository design vocabulary.

### Task 7: Document BlackHole-compatible loopback and device E2E procedure

**Files:**
- Create: `docs/audio/macos-device-e2e.md`
- Modify: `README.md`
- Modify: `DEVELOPMENT.md`

- [ ] Document physical-input setup and explicit BlackHole-compatible virtual-input route by stable UID.
- [ ] Record that BlackHole is user-installed infrastructure and not bundled by LiveMixMaster.
- [ ] Provide exact 10+ second E2E evidence procedure: enumerate → select → meter → fader/mute/solo → record → inspect output → disconnect/reconnect.
- [ ] Define evidence fields: OS, hardware/virtual endpoint UID (non-secret), sample rate, buffer frames, channels/layout, average/max callback duration, callback count, xrun/overflow count, recording duration/format, disconnect/reconnect result.

### Task 8: CI, PR evidence, and final device gate

**Files:**
- Modify: `.github/workflows/ci.yml`
- Modify: `.github/workflows/macos-ci.yml`

- [ ] Add CTest native deterministic signal/queue/catalog gates to macOS CI.
- [ ] Build and run Core Audio catalog probe; zero endpoints on hosted CI is allowed but recorded.
- [ ] Keep PR draft while physical/BlackHole E2E evidence is absent.
- [ ] Run the documented device E2E on a real macOS host and attach non-secret evidence to Issue #3.
- [ ] Only after device E2E passes: mark PR ready, merge exact verified head, verify `main`, close Issue #3, and sync Notion.

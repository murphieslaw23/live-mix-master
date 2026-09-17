# Linux PipeWire desktop path implementation plan

**Goal:** Make LiveMixMaster a runnable, evidence-scoped Linux desktop target on PipeWire, with native input and sink-monitor selection, real-time-safe capture into the existing DSP/PCM handoff ABI, recording/fingerprinting service wiring, and a reproducible Zorin OS acceptance path.

**Architecture:** Preserve the current platform-neutral C ABI and Dart `NativeAudioEngine`. Add a Linux-only PipeWire implementation of the existing device, capture, and permission entry points. PipeWire registry discovery supplies stable `node.name`-based endpoint IDs; capture uses a targeted `PW_DIRECTION_INPUT` stream, negotiated `F32` audio, and a fixed stereo scratch buffer before calling `lmm_process_bound_capture_stereo`. Flutter Linux packages the shared object beside the executable and uses a platform-aware native-library loader/settings recovery action.

**Target host:** Zorin OS 18.1, Wayland, PipeWire 1.0.5. The host currently exposes `alsa_input.pci-0000_00_1f.3.analog-stereo` and a system sink monitor path. Flutter 3.47.2 is available only at `/tmp/flutter-3.47.2/bin/flutter`; permanent development prerequisites must be documented rather than assumed.

**Scope boundary:** PipeWire is the verified Linux backend. Direct ALSA capture is not added in this path: PipeWire owns device policy, virtual devices, and sink-monitor loopback. On ALSA-only distributions, the documented fallback is installing/running PipeWire (including its ALSA compatibility layer), not silently opening hardware outside the session manager.

## Task 1: Define Linux build and runtime prerequisites

**Files:**
- Modify: `native/CMakeLists.txt`
- Modify: `native/README.md`
- Modify: `DEVELOPMENT.md`

1. Require `libpipewire-0.3` through CMake/pkg-config only on Linux; link its imported target and `Threads::Threads`.
2. Remove the unsupported implicit `asound` link; do not claim a direct ALSA backend that does not exist.
3. Document required packages: `libpipewire-0.3-dev`, `libspa-0.2-dev`, `clang`, `ninja-build`, and `libgtk-3-dev`.
4. State the PipeWire/ALSA compatibility constraint and the exact Linux native artifact name: `liblive_mixer_engine.so`.

**Verification:** configure native CMake with a real PipeWire pkg-config package; ensure non-Linux branches remain unchanged.

## Task 2: Implement PipeWire device enumeration

**Files:**
- Create: `native/linux/pipewire_device_catalog.cpp`
- Modify: `native/CMakeLists.txt`
- Test: `native/tests/device_catalog_contract_tests.cpp`

1. Add a bounded PipeWire registry round-trip that collects only `Audio/Source` and `Audio/Sink` nodes.
2. Use `node.name` as selection identity and encode endpoint role as `pipewire:source:<node.name>` or `pipewire:sink:<node.name>`. Keep display labels independent from identity.
3. Populate channels/rate from node properties; provide non-zero conservative defaults where PipeWire omits optional properties.
4. Return source records and sink-monitor records without writing past the caller capacity. Never treat an empty catalog as physical-device success.
5. Make the device catalog ABI/bounds test platform-neutral and execute it on Linux as well as macOS.

**Verification:** on the Zorin host, `ctest -R device_catalog_contract_tests` lists a non-empty catalog and preserves the one-record sentinel; on a headless host it passes with an explicit zero-device infrastructure result.

## Task 3: Implement real-time-safe PipeWire capture and lifecycle reporting

**Files:**
- Create: `native/linux/pipewire_capture.cpp`
- Create: `native/linux/audio_input_permissions.cpp`
- Modify: `native/CMakeLists.txt`
- Test: `native/tests/linux_pipewire_capture_contract_tests.cpp`

1. Implement all existing `lmm_capture_*` ABI symbols on Linux; retain the ABI and capture-state numeric values unchanged.
2. Request `F32` raw audio via a PipeWire `PW_DIRECTION_INPUT` stream. Target the selected `node.name` using `PW_KEY_TARGET_OBJECT`, `PW_STREAM_FLAG_AUTOCONNECT`, `PW_STREAM_FLAG_MAP_BUFFERS`, `PW_STREAM_FLAG_RT_PROCESS`, and `PW_STREAM_FLAG_DONT_RECONNECT`.
3. For sink-monitor records, set `PW_KEY_STREAM_CAPTURE_SINK=true`; for sources, omit that property.
4. On `param_changed`, publish negotiated sample rate/channel count and reject unsupported/malformed formats. Validate the requested channel pair before a stream is exposed as running.
5. In `process`, dequeue and always requeue a PipeWire buffer; select or duplicate the requested mono/stereo pair into fixed-size stack/static storage and call `lmm_process_bound_capture_stereo` in bounded blocks. Do not allocate, lock, log, access Dart, or perform I/O in the callback.
6. Track callback duration and PipeWire stream discontinuities through atomics; map target removal/state error to `device_removed`/`failed` and never auto-route stale audio to another source.
7. Linux has no macOS-style global microphone consent API at this layer. Return `granted` when a PipeWire session is reachable; return `unavailable` when it is not. Permission request is side-effect free and re-reads session availability.
8. Add an invalid-UID/start-stop/status ABI contract test that never opens a physical input in CI; keep real capture in an explicit host acceptance procedure.

**Verification:** native build and CTest pass on Zorin; a manually selected real source reaches `running`, reports negotiated format and incrementing callbacks; stopping/restart and source loss do not crash or produce stale PCM.

## Task 4: Generate and package the Flutter Linux runner

**Files:**
- Create: `linux/` via Flutter 3.47.2 Linux runner generation
- Modify: `linux/CMakeLists.txt`
- Modify: `lib/audio/native_library_loader.dart`
- Modify: `test/native_library_loader_test.dart`

1. Generate only the missing Linux runner from Flutter 3.47.2; do not regenerate macOS/web hosts.
2. Add an explicit `linux/CMakeLists.txt` native-engine target/dependency that builds `native/` and copies `liblive_mixer_engine.so` into the Flutter bundle next to the executable.
3. Make native library resolution select the platform filename at runtime. Search override, repository Debug build, and the Linux bundle executable directory; retain the macOS Frameworks fallback exactly.
4. Add Linux loader unit tests without weakening existing macOS assertions.

**Verification:** `flutter build linux --debug` loads the packaged `.so` from the bundle and no longer exposes a missing-symbol FFI startup failure.

## Task 5: Make desktop recovery actions platform-aware

**Files:**
- Create: `lib/audio/audio_settings_launcher.dart`
- Create: `lib/audio/audio_settings_launcher_linux.dart`
- Create: `lib/audio/audio_settings_launcher_macos.dart`
- Modify: `lib/app/app_surface_desktop.dart`
- Replace/extend tests: `test/desktop_audio_settings_wiring_test.dart`, `test/macos_audio_settings_launcher_test.dart`, Linux launcher tests

1. Keep the existing macOS deep link behavior behind a macOS implementation.
2. On Linux, open the desktop system sound settings through `xdg-open` only from the non-real-time recovery action; fail closed on non-zero exit status.
3. Do not show macOS-specific copy or invoke `open` on Linux.

**Verification:** focused widget/source wiring and launcher tests pass on both conditional implementations; a Linux manual invocation opens the sound settings panel or reports the failed recovery action clearly.

## Task 6: Add reproducible Linux acceptance evidence

**Files:**
- Create: `tool/linux_device_acceptance.sh`
- Create: `docs/audio/linux-pipewire-device-e2e.md`
- Create: `docs/audio/linux-pipewire-device-acceptance-record.md`
- Modify: `README.md`
- Modify: `DEVELOPMENT.md`

1. Add a host-only helper that refuses CI, a dirty tracked checkout, a missing PipeWire session, missing library, or a wrong Flutter version.
2. Document the real run: choose physical source and sink monitor, verify meters/fader/mute/solo, record at least 10 seconds, inspect WAV format/rate/duration/non-silence, remove/recover source, and capture callback/xrun/queue telemetry.
3. Keep the acceptance record `PENDING REAL DEVICE RUN` until an actual interactive run provides non-secret evidence. Automated tests and a local library load do not satisfy it.
4. Update the README platform matrix to say Linux build/runner/native capture are verified only after the exact applicable evidence exists; do not overstate ALSA/direct-loopback or distribution packaging support.

**Verification:** repository contracts, native CTest, focused Flutter tests, Flutter analysis, Linux debug build, and a documented physical PipeWire run all succeed on the same source revision.

## Known prerequisites and blockers

- This host lacks the globally installed Flutter SDK and Linux desktop development packages. The local pinned Flutter SDK in `/tmp` is suitable for generation and verification but is intentionally not a permanent machine configuration.
- `sudo` requires user interaction, so `libpipewire-0.3-dev`, `libspa-0.2-dev`, `clang`, `ninja-build`, and `libgtk-3-dev` cannot be installed by this agent non-interactively. The implementation must fail clearly at CMake/Flutter prerequisite checks until those packages are installed.
- Real microphone/sink-monitor capture remains an explicit user-operated acceptance step; it must not be inferred from synthetic tests or a device catalog result.

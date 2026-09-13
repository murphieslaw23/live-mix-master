# macOS physical and BlackHole device E2E acceptance

Status: **procedure ready; real device evidence is still pending**.

This is the canonical Issue #3 acceptance procedure for the first verified desktop target. Hosted GitHub Actions can prove build, ABI, DSP, queue, UI-control, packaging, and launch-smoke contracts, but they do **not** satisfy the physical input or BlackHole device E2E gate.

## Preconditions

- Use a real macOS host with Flutter 3.47.2, Xcode, CMake, and this PR head checked out.
- For a physical input, connect a microphone/interface that appears as a Core Audio input endpoint.
- For loopback, install/configure BlackHole-compatible virtual audio infrastructure. BlackHole is user-installed infrastructure and is not bundled with LiveMixMaster.
- Route the source application/system output into the BlackHole virtual input in Audio MIDI Setup. A Multi-Output Device may be used for local monitoring.
- Select and record the endpoint by its stable UID, never by display name alone.
- Keep credentials, account names, private paths, hardware serial numbers, and unrelated identifiers out of evidence.

## Build and preflight

```sh
bash tool/bootstrap_fonts.sh
flutter pub get
cmake -S native -B build/native -DBUILD_TESTING=ON -DCMAKE_BUILD_TYPE=Debug
cmake --build build/native --config Debug --parallel
ctest --test-dir build/native --output-on-failure
build/native/macos_device_probe --list
```

The probe reports eligible Core Audio inputs with stable UID, input-channel count, nominal sample rate, and buffer frames. Zero endpoints on a hosted runner is infrastructure information only; it is not device acceptance evidence.

An optional native-only diagnostic can exercise the production ABI and bounded PCM queues for 10 seconds:

```sh
build/native/macos_device_probe --capture '<stable-uid>' 10
```

This CLI diagnostic is not the canonical physical-microphone permission test because macOS TCC authorization can differ between a terminal process and the Flutter app bundle.

## Canonical 10-second live path

1. Start the app with `flutter run -d macos` and grant microphone/audio-input permission when macOS requests it.
2. Confirm the app exposes **E2E TELEMETRY** from the same Flutter process used for acceptance.
3. Open the native patchbay, refresh inputs, select the intended physical input or BlackHole endpoint, and record its stable UID in the acceptance record.
4. Select the intended channel pair. For a multichannel endpoint, verify a non-default pair such as CH 3-4 when available.
5. Attach that route. Confirm the route reaches active state and visible peak/RMS meters move with known program signal.
6. Move the channel fader, toggle MUTE and SOLO, adjust/reset trim, and move the master fader. Confirm each control changes the actual live native path rather than only the widget state.
7. Arm local recording and run continuous program audio for at least **10 seconds**. During the run inspect **E2E TELEMETRY**, choose **COPY EVIDENCE**, and paste the generated `## Same-process E2E telemetry` block into `docs/audio/issue3-device-acceptance-record.md`.
8. The copied block must contain negotiated sample rate/buffer/channels, callback count, average and maximum callback duration, xrun count, recorder/fingerprint queue depths, rejected-block counters, and queue-overflow result. It deliberately excludes endpoint UID, filesystem paths, credentials, account data, and serial numbers.
9. Stop/finalize recording. Inspect the WAV independently: it must open, report the negotiated sample rate and stereo writer format, contain expected non-silent program audio, and have duration >=10 seconds.
10. While the route is active, disconnect the physical interface or remove/disable the virtual endpoint. Confirm device-loss state is actionable, the app does not crash, and stale PCM is not silently routed.
11. Reconnect/re-enable the endpoint, refresh discovery, reselect by stable UID, reconnect the route, and confirm live meters recover. Record the disconnect/reconnect result.

## Required non-secret evidence

Record the following in `docs/audio/issue3-device-acceptance-record.md`:

- exact PR head SHA, macOS version/architecture, Flutter version, date/time;
- source class: physical input or BlackHole-compatible loopback;
- endpoint display label and stable UID, without serial numbers;
- actual negotiated sample rate, buffer frames, input channels and relevant format/layout information;
- pasted **COPY EVIDENCE** block from the same Flutter app process;
- channel meter behavior plus fader/MUTE/SOLO/trim/master observations;
- recorder/fingerprint queue depths and rejected-block counters; a clean run requires both rejected counters to remain zero;
- recording duration and independent WAV inspection result;
- disconnect/reconnect state sequence and stale-audio result.

## Metering evidence boundary

The native ABI fields historically named `true_peak_left/right` currently carry post-limiter **sample peaks**. They are not oversampled inter-sample measurements and must not be reported as standards-based True Peak, dBTP, or LUFS conformance.

The presently provable limiter property is the deterministic sample ceiling enforced by the shared native DSP kernel.

## Pass/fail rule

Do not change the acceptance record from `PENDING REAL DEVICE RUN` to PASS based on hosted CI, source inspection, screenshots, app launch smoke, or the standalone probe. PASS requires the full real macOS path above, including >=10 seconds of recording, same-process telemetry, zero rejected blocks for the clean run, and disconnect/reconnect recovery evidence.

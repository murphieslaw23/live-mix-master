# macOS physical and BlackHole device E2E acceptance

Status: **procedure ready; real device evidence is still pending**.

This is the canonical Issue #3 acceptance procedure for the first verified desktop target. Hosted GitHub Actions can prove build, ABI, DSP, queue, and Core Audio catalog contracts, but it does not satisfy the physical input or BlackHole device E2E gate.

## Preconditions

- Use a real macOS host with the committed Flutter 3.47.2 runner.
- For a physical input, connect a microphone/interface that appears as a Core Audio input endpoint.
- For loopback, install and configure BlackHole-compatible virtual audio infrastructure yourself. BlackHole is user-installed infrastructure and is not bundled with LiveMixMaster.
- Route the source application/system output into the BlackHole virtual input in Audio MIDI Setup. A Multi-Output Device may be used if local monitoring is also required.
- Never select an endpoint by display name. Record and route using its stable UID.
- Keep credentials, account names, filesystem home paths, hardware serial numbers, and unrelated device identifiers out of evidence.

## Build and preflight

From the repository root:

```sh
bash tool/bootstrap_fonts.sh
flutter pub get
cmake -S native -B build/native -DCMAKE_BUILD_TYPE=Debug
cmake --build build/native --config Debug --parallel
ctest --test-dir build/native --output-on-failure
build/native/macos_device_probe --list
```

The probe prints eligible Core Audio inputs including their stable UID, negotiated input-channel count, nominal sample rate, and buffer frames. Zero endpoints on a hosted CI runner is infrastructure information only and is not a failure or a device acceptance result.

An optional native-only diagnostic can exercise the production ABI for 10 seconds while draining both bounded PCM queues:

```sh
build/native/macos_device_probe --capture '<stable-uid>' 10
```

The CLI diagnostic is not the canonical physical-microphone permission test. macOS TCC authorization can differ between a terminal executable and the signed/sandboxed Flutter application. Use the app bundle for the final physical-input acceptance.

## Canonical 10-second live path

1. Start the app with `flutter run -d macos` and grant microphone/audio-input permission when macOS requests it.
2. Confirm the app shows the **E2E TELEMETRY** surface above the mixer. This surface must be read from the same Flutter app process used for the acceptance run; do not substitute telemetry from the standalone CLI probe.
3. Open the patchbay and enumerate inputs. Confirm the intended physical input or BlackHole endpoint is present and capture its stable UID.
4. Route that exact stable UID to a dynamic mixer channel. Confirm the route reaches `active` and visible peak/RMS meters move with a known signal.
5. Change the fader and confirm the master level follows the configured fader law. Toggle MUTE and SOLO and confirm routing semantics without stale audio.
6. Arm local recording and run a continuous live signal for at least **10 seconds**. During the run read the **E2E TELEMETRY** surface and capture callback count, average/maximum callback duration, xrun count, recorder/fingerprint queue depths, and recorder/fingerprint rejected-block counters. These values are sampled on the non-real-time Dart host side from state published by the native engine and PCM pump; the telemetry path must never execute on the Core Audio callback.
7. Stop/finalize the recording. Inspect the resulting WAV independently: it must open, have the negotiated sample rate/channel representation expected by the writer, contain non-silent program audio where expected, and have a recording duration of at least 10 seconds.
8. While a route is active, disconnect the physical interface or remove/disable the virtual endpoint. Confirm `deviceLost`/removed state is actionable, the process does not crash, and stale PCM is not silently routed.
9. Reconnect/re-enable the endpoint, refresh discovery, reselect the endpoint by stable UID, and confirm the route can reconnect and return to live metering. Record the disconnect/reconnect result.

## Required non-secret evidence

Record the following in `docs/audio/issue3-device-acceptance-record.md` and attach the completed record to GitHub Issue #3:

- PR head SHA and macOS version/architecture.
- Source class: physical input or BlackHole-compatible loopback.
- Endpoint display label for operator context and endpoint stable UID; omit serial numbers or unrelated identifiers.
- Actual sample rate, buffer frames, and input channels/layout reported by capture.
- Callback count, average callback duration, maximum callback duration, and xrun count from the same Flutter app process.
- Recorder/fingerprint queue depths observed during the run plus recorder rejected blocks and fingerprint rejected blocks. A clean acceptance run expects zero queue overflow/rejected blocks; any non-zero rejected-block value must be treated as a failed clean run and investigated.
- Channel peak/RMS behavior, limiter-active observation when intentionally driven above the ceiling, and master post-limiter sample peak.
- Recording duration, WAV format inspection result, and a non-sensitive evidence path or artifact name.
- Disconnect/reconnect state sequence and whether stale audio was prevented.

## Limiter and True Peak evidence boundary

The current limiter deterministically clamps output samples to `0.98` linear amplitude. The historical `LmmMasterMeterSnapshot.true_peak_left/right` ABI fields currently carry **post-limiter sample peaks**. They are not oversampled inter-sample measurements and must not be reported as LUFS, dBTP, or standards-based True Peak conformance.

For Issue #3, the presently provable limiter property is: deterministic test buffers and live output samples do not exceed the configured sample ceiling. Standards-based True Peak/dBTP remains an explicit unresolved conformance item unless the implementation is upgraded and independently tested.

## Pass/fail rule

Do not convert the acceptance record from `PENDING REAL DEVICE RUN` to PASS based on hosted CI, screenshots, source inspection, or the native `--list` probe. PASS requires the full real macOS route above, including at least 10 seconds of recording, same-process app telemetry, queue-overflow check, and disconnect/reconnect recovery evidence.

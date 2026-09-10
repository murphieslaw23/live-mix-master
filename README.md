# LiveMixMaster

LiveMixMaster is a Flutter-driven control surface for live audio input routing, mixing, metering, recording, acoustic track identification, and metadata delivery to broadcast endpoints.

## Product boundary

- Dynamic hardware and software-loopback input strips
- Channel trim, fader, mute, solo, and peak/RMS metering
- Master bus with deterministic sample-peak limiting; standards-based True Peak/loudness conformance remains unverified
- Local recording and broadcast output adapters
- Rolling PCM analysis windows for track-identification providers
- Session tracklist with manual correction and export

## Repository layout

```text
lib/
  audio/audio_engine_bridge.dart  # Native engine contract and UI models
  audio/native_library_loader.dart
  features/mixer/mixer_desk_view.dart
macos/                             # Committed Flutter 3.47.2 desktop host
native/
  live_mixer_engine.cpp           # C ABI, channel DSP, sample limiter, bounded PCM fan-out
  macos/                           # Core Audio catalog/capture/permission backend
  tools/macos_device_probe.cpp    # Non-secret device catalog/live-path diagnostic
docs/
  product-spec.md
  design/
  audio/                           # Issue #3 safety and real-device acceptance evidence
DEVELOPMENT.md                     # Clean-clone macOS development path
```

## Architecture

Flutter owns the application shell and controls. The real-time audio thread remains native. Dart receives only compact control and meter events over FFI/isolate boundaries; it must never perform capture, summing, limiting, or fingerprint computation on the UI thread.

```text
Physical devices + application loopback
            -> native capture / channel ring buffers
            -> channel DSP + master bus
            -> recorder / broadcast / fingerprint window
            -> FFI meter & status events
            -> Flutter mixer UI + session tracklist
```

## Desktop support matrix

`Verified` means the repository contains execution evidence for that specific capability. `Contract only` means source/tests exist but no real device/provider E2E is claimed.

| Platform | Committed runner | Native engine build | Physical capture | System/app loopback | Recording | Fingerprinting | Broadcast metadata | E2E verification |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| macOS | Verified | Verified | Pending #3 real-device E2E | Pending #3 BlackHole E2E | Contract only; E2E pending | Contract only; E2E pending | Contract only; E2E pending | Pending #6 |
| Windows | Not verified | Not verified | Pending | Pending | Not verified | Not verified | Not verified | Not verified |
| Linux | Not verified | Not verified | Pending | Pending | Not verified | Not verified | Not verified | Not verified |

The initial supported desktop development target is macOS. Windows and Linux remain planned and must not be inferred as runnable from platform-specific code branches alone.

## Development

See [`DEVELOPMENT.md`](DEVELOPMENT.md) for the pinned Flutter 3.47.2 clean-clone workflow, native-library lookup order, and current limitations.

For Issue #3 physical-input/BlackHole acceptance, follow [`docs/audio/macos-device-e2e.md`](docs/audio/macos-device-e2e.md). The committed acceptance record remains pending until that procedure runs on a real macOS host.

## Current status

The branch for Issue #3 now contains Core Audio stable-UID discovery/capture, negotiated PCM conversion, native mixer controls/meters, bounded recorder/fingerprint fan-out, Flutter lifecycle/permission integration, and deterministic native/FFI tests. Hosted CI can verify those contracts and app launch, but physical-input or BlackHole 10-second E2E evidence is still mandatory before Issue #3 or PR #15 can be treated as complete. Standards-based True Peak/dBTP conformance is also not claimed by the current sample-peak limiter.

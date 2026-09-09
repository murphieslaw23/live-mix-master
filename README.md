# LiveMixMaster

LiveMixMaster is a Flutter-driven control surface for live audio input routing, mixing, metering, recording, acoustic track identification, and metadata delivery to broadcast endpoints.

## Product boundary

- Dynamic hardware and software-loopback input strips
- Channel trim, fader, mute, solo, and peak/RMS metering
- Master bus with true-peak safety limiting and loudness telemetry
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
  live_mixer_engine.cpp           # C ABI and DSP/metering prototype
docs/
  product-spec.md
  design/
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
| macOS | Verified | Verified | Pending #3 | Pending #3 | Contract only; E2E pending | Contract only; E2E pending | Contract only; E2E pending | Pending #6 |
| Windows | Not verified | Not verified | Pending | Pending | Not verified | Not verified | Not verified | Not verified |
| Linux | Not verified | Not verified | Pending | Pending | Not verified | Not verified | Not verified | Not verified |

The initial supported desktop development target is macOS. Windows and Linux remain planned and must not be inferred as runnable from platform-specific code branches alone.

## Development

See [`DEVELOPMENT.md`](DEVELOPMENT.md) for the pinned Flutter 3.47.2 clean-clone workflow, native-library lookup order, focused Issue #2 tests, and current limitations.

## Current status

The repository now contains the repository-first hybrid design contract, responsive Flutter operator UI, a native C ABI/DSP prototype, service/reliability contracts, and a committed macOS desktop host baseline. Production work remains for device-backed capture and loopback, audio-thread-safe production DSP, recording conformance, provider-backed fingerprinting/metadata E2E, persistent operational state, and release-gate verification.

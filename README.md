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
  features/mixer/mixer_desk_view.dart
native/
  live_mixer_engine.cpp           # C ABI and DSP/metering prototype
docs/
  product-spec.md
  figma-handoff.md
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

## Current status

This is a deliberately scoped foundation: domain contracts, mixer UI scaffold, native C ABI prototype, product specification, and Figma implementation handoff are present. Production work remains for per-platform capture backends, audio-thread-safe lock-free queues, standards-compliant EBU R128 measurement, a look-ahead limiter, persistent sessions, provider credentials, and integration tests.

# LiveMixMaster Product Specification

## Purpose

LiveMixMaster is a desktop-first Flutter console for DJs, internet-radio operators, and live electronic-music sessions. It combines physical audio interfaces and application loopback sources into a configurable mixer while recording, streaming, and generating a reliable played-track history.

## Core flows

### Patchbay

1. Enumerate hardware inputs and virtual/application loopback endpoints.
2. Add a source as a named strip and select its stereo channel pair.
3. Set input trim, nominal headroom, and routing destination.
4. Persist the route; surface a clear degraded state when the device disappears.

### Live mixer

1. Monitor stereo peak and RMS on every active strip.
2. Adjust trim, fader, mute, and solo without rebuilding the whole Flutter widget tree.
3. Sum eligible strips to the master bus.
4. Display master peak, limiter state, and loudness telemetry.

### Session capture and identification

1. Start recording and/or broadcast only after output preflight succeeds.
2. Copy the post-master stereo signal to an analysis ring buffer.
3. Query a fingerprint provider asynchronously; do not block the audio callback.
4. Store the candidate, confidence, detection timestamp, and manual corrections in the session timeline.
5. Publish approved metadata through an adapter, preserving retry status and provider response.

## Non-negotiable engineering constraints

- No allocation, blocking I/O, network request, mutex contention, or Dart callback from the real-time audio callback.
- Meter UI is sampled at a bounded cadence, normally 30–60 Hz, from atomic snapshots.
- Use platform capture adapters: CoreAudio on macOS, WASAPI on Windows, and PipeWire/ALSA on Linux.
- Keep native DSP and Flutter presentation independently testable.
- Treat artist/title recognition as probabilistic: keep confidence, provenance, and manual override.

## Initial UI surfaces

- Device patchbay and channel creation modal
- Landscape desktop mixer deck with horizontally scrollable channel strips
- Master output / limiter / loudness panel
- Broadcast and record control panel
- Track-identification notification and editable session timeline
- Compact monitor mode for narrow windows

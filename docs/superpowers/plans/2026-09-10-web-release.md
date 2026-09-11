# LiveMixMaster Web/PWA Release Plan

Date: 2026-09-10
Tracking issue: #16
Branch: `plan/web-release`

## Goal

Add Web/PWA as a first-class LiveMixMaster release target alongside macOS, Windows, and Linux without weakening the native desktop architecture or overstating browser capabilities.

The web target reuses the repository-owned design tokens, component/state vocabulary, operator journey, and Flutter UI. It introduces a browser-specific audio backend and browser-specific capability states.

## Current architecture gap

`lib/main.dart` currently calls `NativeLibraryLoader.tryLoad()` unconditionally. `lib/audio/native_library_loader.dart` imports `dart:ffi` and `dart:io`. Those native APIs cannot be invoked by Flutter Web, so the first implementation step is a platform backend boundary and conditional imports.

The existing native engine remains authoritative for desktop targets. The web target must not route through the current dynamic-library loader.

## Release boundary

### Web-capable

- Flutter UI, responsive layout, design tokens, component states, accessibility semantics, and operator journey.
- Microphone/USB/virtual browser audio inputs through `getUserMedia()` where exposed by the browser.
- User-selected tab/window/display audio through `getDisplayMedia()` only when an audio track is actually returned.
- Web Audio/AudioWorklet processing for low-latency meter/mix behavior.
- Browser recording, session metadata, correction, and export.
- Installable PWA shell.
- Provider and public broadcast-metadata operations through server-side endpoints so secrets stay out of the client bundle.

### Not equivalent to desktop

- Arbitrary native system/application loopback is not guaranteed in browsers.
- Browser device identifiers are origin/permission scoped, not native stable UIDs.
- Direct filesystem access is not universal.
- LAN-only OBS/Icecast targets may need a local bridge.
- Hosted web acceptance does not satisfy the macOS physical-input/BlackHole gate in Issue #3.

## Target architecture

```text
Flutter UI / domain / operator journey
               |
        AudioEnginePort
        /             \
Desktop native        Web
Dart FFI              MediaDevices
CoreAudio/WASAPI      Web Audio graph
PipeWire              AudioWorklet
native DSP            optional shared DSP Wasm
        \             /
       shared service contracts
 recording / fingerprint / metadata / session
```

### Shared port

Introduce an `AudioEnginePort` (name can change during implementation) with the minimum cross-platform contract needed by the existing UI:

- capability discovery
- input enumeration
- permission state
- attach/detach source
- fader/trim/mute/solo
- meter snapshots/events
- source lifecycle events
- post-master PCM handoff
- start/stop/recovery state

Use conditional imports/exports so `dart:ffi` and `dart:io` are absent from the web compile graph.

### Desktop implementation

Wrap the existing FFI path in `DesktopNativeAudioEngine` without behavior changes. The web release must not destabilize PR #15 or the macOS real-device acceptance path.

### Web implementation

Implement `WebAudioEngine` using Dart web interop and the browser Media APIs:

- `enumerateDevices()` for available `audioinput` endpoints after required permission flow.
- `getUserMedia()` for microphone/USB/virtual audio endpoints.
- `getDisplayMedia()` for explicit user-selected display/tab/window capture.
- Treat a display capture with zero audio tracks as an explicit unsupported/no-audio state.
- Listen for `MediaStreamTrack.ended`, permission revocation, and device changes.

## Real-time DSP strategy

### Web Beta baseline

Run browser audio work in an `AudioWorklet`, not on the Flutter UI thread. Keep the same safety boundary as desktop:

- no network requests in the worklet
- no storage writes in the worklet
- no unbounded message queues
- no synchronous UI calls
- bounded PCM/telemetry handoff only

Implement deterministic fader, mute, solo, channel sum, peak/RMS, and sample-ceiling behavior.

### Preferred parity path

Extract platform-neutral DSP primitives from the C++ engine so the same deterministic test vectors can be compiled for desktop and WebAssembly. Load the Wasm DSP into the AudioWorklet where browser support allows it.

Do not claim standards-based LUFS or oversampled True Peak/dBTP until independently implemented and verified.

## Recording and session persistence

Route post-master PCM from the AudioWorklet to a non-real-time Worker/streaming writer.

Requirements:

- independently valid WAV output
- at least 10-second release-gate recording
- storage pressure and write-failure state
- production-length strategy that does not buffer an entire long session in RAM
- session/track correction persistence in IndexedDB or equivalent
- browser download fallback
- File System Access API only as progressive enhancement

## Fingerprinting and broadcast metadata

Client-side bundles must contain no provider or broadcast credentials.

Use server-side endpoints for:

- fingerprint provider lookup
- public Icecast/SHOUTcast/webhook metadata delivery where the target is reachable from cloud infrastructure
- credential redaction, retry/backoff, and timeout behavior

If a destination exists only on the operator's LAN, mark it as requiring a local/desktop bridge instead of attempting an unsafe or impossible cloud route.

## Browser-specific UI contract

Add deterministic Flutter states and goldens for:

- browser audio permission required
- permission denied
- microphone/USB capture available
- tab/window audio available
- display selected but no audio track returned
- system audio unavailable on current browser/OS
- active capture ended
- reconnect required
- PWA install available / installed / unavailable
- browser storage quota/write failure
- provider/broadcast backend unavailable

Critical states retain the repository rule: icon + text + shape/border + color; color alone is never sufficient.

## Picsart web assets

Picsart Drive folder: **LiveMixMaster — Web Release**

- `LiveMixMaster-web-maskable-pwa-icon.png`
  - source: https://gcdn.picsart.com/pipeline-output/b1b775f3-3cb3-4b11-807c-9407ae970f74.png
- `LiveMixMaster-web-release-browser-states-board.png`
  - source: https://gcdn.picsart.com/pipeline-output/d222d87e-e19a-4448-ac62-54573524d52e.png

The generated board is art-direction only. Repository tokens, component states, operator journey, and deterministic Flutter goldens remain semantic/pixel acceptance truth.

Before the PWA icon is committed as release artwork, inspect mask-safe cropping and legibility at 48, 192, and 512 px and generate deterministic resized outputs from one approved master.

## Vercel release path

Existing project: `live-mix-master`
Project ID: `prj_DeQFFyYAUHEotogFlolPXAs62uqH`
Current production deployment at planning time: `dpl_DBnHc7vqzAKFpnkMWSKy4QeF2wnx` (READY)

The current Vercel surface is QA/evidence only and is not Git-linked.

Preferred release flow:

1. GitHub Actions checks out the exact commit.
2. Run Flutter analyze/tests/browser tests.
3. Run `flutter build web --wasm` and preserve the exact `build/web` artifact.
4. If Wasm threading is enabled, configure required COOP/COEP response headers and verify all cross-origin assets still load.
5. Deploy the already-tested artifact to the existing Vercel project.
6. Record Git SHA, workflow run, Vercel deployment ID/URL, browser matrix, and non-secret acceptance evidence.

Do not promote the current Vercel placeholder/QA deployment as the Web release.

## Implementation order

### W1 — Compile boundary and web runner

1. Add `AudioEnginePort`.
2. Wrap current FFI implementation as desktop backend.
3. Add conditional imports/exports.
4. Generate and commit Flutter `web/` runner.
5. Add manifest and PWA bootstrap.
6. Prove clean-clone `flutter build web`.
7. Re-run desktop/macOS tests to prove no regression.

Exit: web compiles and launches into a deterministic capability state without loading native-only code.

### W2 — Browser source capture and lifecycle

1. Add capability probe.
2. Implement permission flow.
3. Implement `getUserMedia()` source attach.
4. Implement `getDisplayMedia()` source attach behind user gesture.
5. Add no-audio-track, ended, revoked, and device-change events.
6. Bind those events to existing recovery UI vocabulary.
7. Add deterministic browser fixtures/tests.

Exit: supported browser input can be attached and lifecycle failures are explicit.

### W3 — DSP, meters, and recording

1. Create AudioWorklet pipeline.
2. Port/share fader, mute, solo, summing, peak/RMS, limiter sample ceiling.
3. Add bounded telemetry/PCM handoff.
4. Add Worker-based WAV writer.
5. Verify WAV independently.
6. Add backpressure/storage failure tests.
7. Compare deterministic DSP vectors with native output.

Exit: capture -> meter/mix -> >=10s valid WAV works in a supported browser.

### W4 — Fingerprinting, persistence, and metadata delivery

1. Add browser Worker/Wasm fingerprint preparation boundary.
2. Add server-side provider proxy.
3. Add session persistence/recovery.
4. Add public broadcast metadata proxy.
5. Enforce secret redaction and retry contracts.
6. Document LAN/local bridge requirement.
7. Verify manual correction/export.

Exit: browser session data is durable and external services work without client-side secrets.

### W5 — PWA, browser matrix, and production release

1. Finalize maskable icons and manifest.
2. Add service worker/offline shell policy.
3. Test keyboard/focus/semantics/goldens.
4. Run Chromium, Firefox, and Safari capability matrix.
5. Run full Web E2E.
6. Deploy exact tested artifact to Vercel.
7. Record deployment + acceptance evidence.
8. Update README platform matrix and Notion tracker.

Exit: evidence-backed Web/PWA release candidate.

## CI / test gates

- `flutter analyze`
- current Dart/widget/golden/contract suites
- web-specific unit/widget tests
- Chrome browser tests for capability/state behavior
- `flutter build web`
- `flutter build web --wasm` compatibility gate
- deterministic DSP cross-platform vectors
- independent WAV parser validation
- no-secret client bundle scan
- static deployment smoke
- browser E2E on at least one supported capture path

## Release acceptance record

Record only non-secret evidence:

- exact Git SHA
- GitHub workflow run
- browser + OS versions
- input method (`getUserMedia` mic/USB or `getDisplayMedia` tab/window)
- negotiated sample rate/channel count if available
- capture duration
- meter/fader/mute/solo result
- WAV duration/format inspection
- source-ended/recovery result
- storage behavior
- Vercel deployment ID/URL
- known unsupported capabilities

## Dependencies and non-dependencies

Depends on:

- repository design/source-of-truth contract from #1/#5
- service reliability contracts from #4
- release evidence discipline from #6

Does not depend on:

- completion of Windows/Linux native capture before web work starts
- completion of macOS real-device E2E for compiling/building the web target

However, Web work must not change the acceptance status of #3/PR #15.

## Definition of done

- Web is listed as a first-class platform with its own evidence-backed support matrix.
- No native-only library is loaded on Web.
- Browser capability differences are surfaced before routing.
- Supported capture completes the critical path through valid recording and source-loss recovery.
- Secrets remain server-side.
- PWA assets are approved and deterministic.
- GitHub CI and exact Vercel deployment evidence are linked.
- README and Notion are synchronized from evidence, not assumptions.

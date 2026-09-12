# LiveMixMaster Shared Native/Web DSP Wasm Design

Date: 2026-09-12
Tracking: Issue #16
Status: proposed — architecture approved, implementation not yet approved

## Goal

Remove production DSP duplication between the desktop-native engine and the browser AudioWorklet by making the existing C++ DSP kernel the canonical algorithm for both native and Web execution, while preserving the current browser real-time, recording, fingerprint, release-artifact, and capability boundaries.

This design covers only the W3/W5 DSP parity boundary: fader, trim, mute, solo, stereo summing, channel peak/RMS, master peak, and the existing deterministic `0.98` sample ceiling. It does not add LUFS, dBTP, resampling, EQ, dynamics beyond the current ceiling clamp, new capture capabilities, or new provider/network behavior.

## Problem statement

LiveMixMaster currently maintains the same mixer DSP semantics in three places:

- `native/dsp_kernel.hpp` — native C++ production kernel;
- `lib/audio/web/web_dsp_kernel.dart` — Dart reference/test kernel;
- `web/audio/livemixmaster-worklet.js` — browser production AudioWorklet kernel.

The implementations currently agree on the important semantics:

- channel gain = `linearTrim * fader * fader`;
- mute removes the channel from the sum;
- if any channel is soloed, only soloed channels are included;
- channel peak and RMS are measured after channel gain and before master gain;
- stereo channels are summed independently;
- master gain is applied after channel summing;
- samples beyond the current limiter ceiling are clamped to `[-0.98, +0.98]`;
- master peak is measured after the ceiling clamp.

The duplication is nevertheless a release risk: a later change can land in C++ and not JavaScript, or vice versa, while each platform still appears locally correct. Issue #16 already identifies the preferred parity path as extracting/using platform-neutral native DSP through WebAssembly inside the AudioWorklet. The existing `native/tests/dsp_parity_vectors_test.cpp` and shared fixture path provide the beginning of an executable parity oracle.

## Selected architecture

Keep `native/dsp_kernel.hpp` as the canonical source implementation and compile a small C ABI wrapper around it to WebAssembly. Native desktop continues to call the C++ kernel directly. Browser production calls the same kernel through Wasm from the AudioWorklet.

```text
                           canonical source
                    native/dsp_kernel.hpp
                              |
              +---------------+---------------+
              |                               |
              v                               v
     desktop native engine              Wasm C ABI wrapper
     direct C++ invocation                    |
                                              v
                                  livemixmaster-dsp.wasm
                                              |
                                 preloaded by browser host
                                              |
                         compiled module transferred/handed off
                                              |
                                              v
                                    AudioWorkletProcessor
                                              |
                               fixed preallocated Wasm memory
                                              |
                                              v
                                   lmm_dsp_process_stereo
```

`lib/audio/web/web_dsp_kernel.dart` remains a deterministic reference/test oracle during migration, not a third production engine. After Wasm production parity is proven, it may remain for fast unit tests as long as CI explicitly proves it against the canonical fixture vectors.

## Canonical DSP contract

The canonical semantics remain exactly the behavior currently expressed by `native/dsp_kernel.hpp`.

### Channel configuration

Each channel has:

- `active: bool` — native-side participation gate;
- `muted: bool`;
- `solo: bool`;
- `linearTrim: float`;
- `fader: float`.

The Web wrapper maps browser channel presence to `active=true` only for channels with an attached input for the current render quantum. Missing browser inputs are not represented as zero-filled active channels for metering purposes.

### Channel gain

For a participating channel:

```text
gain = linearTrim * fader * fader
```

No logarithmic conversion or smoothing is introduced in this slice.

### Solo/mute

A channel is skipped when any of these is true:

- `active == false`;
- `muted == true`;
- at least one active channel is soloed and this channel is not soloed;
- input pointer is null / browser input is absent.

### Channel meters

For processed samples, channel peak and RMS are calculated after channel gain and before master gain. Clipping means either pre-master channel peak is `>= 1.0`.

The Web-facing telemetry schema remains the existing channel ID plus peak/RMS/clipping values; Wasm does not introduce a competing telemetry model.

### Master stage

After summing processed channels, multiply both channels by `masterGainLinear`, then clamp any sample whose absolute value exceeds the current ceiling:

```text
LIMITER_CEILING = 0.98
```

This remains a deterministic sample ceiling, not a standards-based true-peak limiter. The UI and docs must not relabel it as LUFS/dBTP or mastering-grade limiting.

## Wasm ABI boundary

Add a tiny C-compatible wrapper around the canonical C++ kernel. The ABI must be minimal, versioned, and independent of C++ name mangling.

Proposed exported ABI:

```c
uint32_t lmm_dsp_abi_version(void);
size_t lmm_dsp_required_bytes(uint32_t channel_count, uint32_t frames);
int32_t lmm_dsp_process_stereo(
    const LmmDspChannelConfig* configs,
    const float* interleaved_channel_input,
    uint32_t channel_count,
    uint32_t frames,
    float master_gain,
    float* interleaved_output,
    LmmDspChannelMeter* channel_meters,
    LmmDspMasterMeter* master_meter);
```

The exact layout must use fixed-width scalar fields and an explicitly documented memory layout. Boolean values cross the ABI as `uint32_t` `0/1`, never implementation-defined C++ `bool` layout.

The first ABI version is `1`. Any incompatible layout or semantic change increments the ABI version and must fail closed when the worklet and module disagree.

The wrapper must not allocate, log, open files, access clocks, call network APIs, or own thread primitives while processing a block.

## Memory model

Real-time safety is the primary constraint.

### Initialization phase

Before audio processing starts:

1. the browser host fetches the same-origin Wasm asset;
2. the host calls `WebAssembly.compile(...)` outside the AudioWorklet render callback;
3. the AudioWorklet receives the compiled module or equivalent supported initialization payload;
4. the worklet instantiates the module during setup, before marking the DSP backend ready;
5. fixed memory regions are allocated once for the configured maximum channel count and AudioWorklet render-quantum size;
6. typed-array views over Wasm memory are cached and refreshed only if a deliberate memory-growth event is ever permitted.

The initial implementation should configure enough memory up front and disable/avoid memory growth during steady-state processing so typed-array references remain stable.

### Render phase

Inside `AudioWorkletProcessor.process()`:

- no `fetch`;
- no network/storage access;
- no DOM access;
- no dynamic Wasm instantiation;
- no unbounded queueing;
- no new Wasm heap allocation;
- no C/C++ heap allocation;
- no logging;
- no JSON serialization for the sample path.

The worklet copies each participating browser input bus into the preallocated Wasm input region, writes channel configuration into the fixed config region, invokes `lmm_dsp_process_stereo`, then copies the returned stereo output into the browser output bus. Meter telemetry is read from the fixed meter region and continues through the existing bounded/acknowledged telemetry path.

A small amount of JavaScript control work per render quantum is acceptable; DSP arithmetic itself is canonical C++/Wasm.

## Module loading and browser boundary

The Wasm asset path is a fixed, same-origin release asset. It is not supplied by user/session data.

The browser host layer owns module fetch/compile because the current worklet must remain free of network work. The host passes initialization state to the worklet before capture/mixing is considered ready.

If the browser cannot compile or instantiate the module, the Web audio backend must surface a deterministic unsupported/unavailable state and must not silently claim canonical-DSP parity.

The migration may retain the current JavaScript DSP path behind an explicit development/test fallback flag, but production release configuration must fail closed rather than silently falling back once Wasm parity is declared production-ready.

## Worklet integration

`web/audio/livemixmaster-worklet.js` keeps responsibility for:

- AudioWorklet lifecycle;
- browser input/output bus marshaling;
- configuration message handling;
- telemetry cadence and ACK/backpressure;
- recording PCM handoff;
- analysis PCM handoff.

It stops owning mixer arithmetic once the Wasm path is accepted.

The recording and fingerprint handoffs continue to consume post-master samples after the canonical Wasm DSP call. Their existing bounded outstanding-message limits remain unchanged.

The worklet must not create a second gain/limiter pass around the Wasm output. Browser-only channel-layout fallback (mono input mirrored to stereo) remains marshaling behavior, not a second DSP algorithm.

## Build and artifact model

Add an Emscripten build target for the small DSP wrapper plus `native/dsp_kernel.hpp`.

Requirements:

- pin the Emscripten SDK version in repository build tooling;
- compile only the DSP wrapper/kernel needed by this module;
- no filesystem runtime;
- no pthread dependency for the first version;
- export only the minimal ABI/memory symbols required by the worklet;
- deterministic output path under the Web release assets;
- `flutter build web --release` must package the already-built Wasm asset;
- the exact-artifact workflow must test and deploy the same packaged Wasm bytes without rebuilding Flutter during Vercel promotion.

Generated Wasm is a build artifact. The C++ wrapper and build script are source-controlled; the binary should follow the repository's existing generated-asset policy established for other Wasm assets.

## Parity oracle

Parity is defined by deterministic fixture vectors, not by visual meter similarity.

The existing `native/tests/dsp_parity_vectors_test.cpp` fixture contract becomes the canonical vector source. The fixture set must cover at least:

1. one-channel nominal gain without limiter activity;
2. mute removal;
3. solo isolation with multiple channels;
4. stereo summing across multiple channels;
5. master gain causing `0.98` ceiling activation;
6. negative-polarity clamp;
7. clipping telemetry before master clamp;
8. zero/empty-frame behavior where supported by each harness;
9. asymmetric left/right samples;
10. non-default trim and fader values.

For every vector, compare:

- output samples;
- channel processed state where the harness exposes it;
- channel peaks;
- channel RMS;
- channel clipping state;
- master left/right peak;
- limiter-active state.

Numeric tolerance remains `1.0e-6` unless cross-compiler evidence shows a narrowly justified adjustment. Any tolerance change must be explicit and reviewed; do not loosen it simply to make CI green.

Required implementations under the parity gate:

- native C++ direct kernel;
- browser Wasm kernel;
- Dart reference kernel while it remains in the repository.

The JavaScript production arithmetic path is removed from the parity set once it is no longer production code.

## Test strategy and TDD boundary

Implementation must proceed red-first.

### Contract red phase

Add tests that fail because the Wasm ABI/module and browser loader do not yet exist. The red evidence should be isolated to the new shared-DSP contract, not produced by breaking unrelated mixer behavior.

### Native/Wasm parity

Build the native fixture runner and Wasm fixture harness from the same vectors. Run both and compare deterministic outputs/telemetry.

### Worklet integration

Add browser tests that prove:

- the worklet initializes only after a valid ABI-v1 module is provided;
- ABI mismatch fails closed;
- module initialization failure surfaces the existing safe unavailable-state vocabulary;
- input marshaling handles stereo and mono browser buses deterministically;
- post-master recording/analysis PCM is sourced from the Wasm output;
- existing telemetry ACK/backpressure remains bounded;
- production worklet source no longer contains duplicate mixer gain/sum/clamp arithmetic after cutover.

### Release artifact

The exact Web artifact must contain the expected Wasm asset and the browser E2E must exercise the packaged artifact, not a dev-server-only module.

## Error model

Failures must be deterministic and non-secret. Suggested operator-facing state:

- `DSP MODULE UNAVAILABLE — AUDIO ENGINE NOT READY`
- `DSP MODULE VERSION MISMATCH — AUDIO ENGINE NOT READY`
- `DSP MODULE INITIALIZATION FAILED — AUDIO ENGINE NOT READY`

Do not expose raw Wasm stack traces, local build paths, binary dumps, PCM contents, internal pointers, or browser exception objects in operator UI/evidence.

A DSP initialization failure is different from a fingerprint-preparation failure: because DSP is on the live audio path, the browser mix must not start until the canonical module is ready.

## Performance and real-time acceptance

Correct parity is necessary but not sufficient. Acceptance also requires evidence that the integration preserves bounded real-time behavior.

At minimum CI/browser evidence must prove:

- no per-block Wasm heap allocation in the process path;
- no network/storage API reachable from DSP process code;
- bounded telemetry/recording/analysis outstanding messages remain intact;
- the worklet renders continuously through a deterministic multi-second synthetic fixture without dropped/invalid output;
- limiter/meter behavior remains stable under a high-amplitude multi-channel vector.

This design does not promise a hard universal browser latency number. Browser/OS scheduling differs and should be measured separately rather than encoded as a false cross-platform guarantee.

## Security and provenance

- Wasm asset is same-origin and produced by repository-controlled build tooling.
- No runtime-selectable arbitrary Wasm URL.
- No provider credentials or user secrets in the module.
- No network/storage in the canonical DSP wrapper.
- Release evidence records source SHA, build-tool version, Wasm artifact checksum, and exact Web artifact digest without recording PCM/user media.
- Existing Vercel exact-artifact promotion remains authoritative; this design does not introduce a separate deployment path.

## Migration sequence

1. Add parity fixtures/contract extensions and obtain red evidence for missing Wasm implementation.
2. Add C ABI wrapper and native ABI unit tests without changing production Web DSP.
3. Add pinned Emscripten build and Wasm parity harness; make vector parity green.
4. Add browser host loader + worklet initialization handshake behind a non-production feature gate.
5. Run the existing Web mixer/operator/session/recording/fingerprint contracts with Wasm enabled in CI.
6. Switch production Web configuration to canonical Wasm DSP and remove duplicate arithmetic from the production worklet.
7. Keep the old JS arithmetic only if needed as an explicitly non-production test fixture; otherwise delete it.
8. Run `flutter build web --release`, exact-artifact browser E2E, and macOS Desktop CI on one exact head.
9. Promote to `preview`, verify the exact artifact and Vercel deployment, then merge only after review/approval.
10. Let the existing `main` push pipeline build/test the merge commit and promote that exact tested artifact to production.

## Explicit non-goals

This slice does not:

- add LUFS or dBTP;
- claim true-peak limiting;
- add sample-rate conversion;
- change capture device policy;
- change recording file format;
- change Chromaprint/AcoustID architecture;
- change broadcast/provider credential boundaries;
- implement native macOS/BlackHole physical-device acceptance;
- replace the existing release provenance or Vercel deployment workflow;
- introduce Rust or another DSP language/toolchain.

## Acceptance criteria

This slice is complete only when all of the following are true on one exact Git SHA:

1. `native/dsp_kernel.hpp` remains the canonical DSP implementation for desktop and Web.
2. A versioned C ABI wrapper exposes the kernel to Wasm without process-time allocation, networking, storage, logging, or filesystem work.
3. The browser host preloads/compiles the same-origin Wasm module before live audio starts; the worklet does not fetch or instantiate Wasm during `process()`.
4. The worklet uses fixed/preallocated Wasm buffers and no duplicate production mixer arithmetic remains after cutover.
5. Native C++, browser Wasm, and the retained Dart reference kernel pass the same parity vectors within the reviewed tolerance.
6. Existing Web recording, fingerprint, telemetry-backpressure, session, mixer, and operator contracts remain green with Wasm enabled.
7. `flutter build web --release` packages the Wasm asset, and exact-artifact browser E2E exercises that packaged artifact.
8. macOS Desktop CI remains green on the same head through native engine build, package, and launch smoke.
9. Preview promotion deploys the exact tested artifact with non-secret Wasm/source/artifact provenance recorded.
10. No new claim is made for LUFS/dBTP, native loopback parity, or physical-device acceptance.

## Spec approval gate

No implementation plan or production code change should be generated from this design until this spec is explicitly approved. After approval, create a separate implementation plan under `docs/superpowers/plans/` using red-green TDD tasks and the existing exact-artifact release gates.
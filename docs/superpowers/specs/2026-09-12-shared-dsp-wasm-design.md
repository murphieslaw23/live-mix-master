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

The implementations currently agree on these semantics:

- channel gain = `linearTrim * fader * fader`;
- mute removes the channel from the sum;
- if any channel is soloed, only soloed channels are included;
- channel peak and RMS are measured after channel gain and before master gain;
- stereo channels are summed independently;
- master gain is applied after channel summing;
- samples beyond the current limiter ceiling are clamped to `[-0.98, +0.98]`;
- master peak is measured after the ceiling clamp.

The duplication is still a release risk: a later change can land in C++ and not JavaScript, or vice versa, while each platform still appears locally correct. Issue #16 already identifies the preferred parity path as platform-neutral native DSP compiled to WebAssembly inside the AudioWorklet. The existing `native/tests/dsp_parity_vectors_test.cpp` fixture contract is the starting executable parity oracle.

## Selected architecture

Keep `native/dsp_kernel.hpp` as the canonical source implementation and compile a small C ABI wrapper around it to WebAssembly. Native desktop continues to call the C++ kernel directly. Browser production calls that same kernel through Wasm from the AudioWorklet.

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
                           fetched + compiled by browser host
                                              |
                     compiled WebAssembly.Module via worklet port
                                              |
                                              v
                                    AudioWorkletProcessor
                                              |
                          fixed preallocated Wasm/sample buffers
                                              |
                                              v
                                   lmm_dsp_process_stereo
```

`lib/audio/web/web_dsp_kernel.dart` remains a deterministic reference/test oracle during migration, not a third production engine. After Wasm production parity is proven, it may remain for fast unit tests only while CI continues to prove it against the canonical fixture vectors.

## Canonical DSP contract

The canonical semantics remain exactly the behavior currently expressed by `native/dsp_kernel.hpp`.

### Channel configuration

Each channel has:

- `active: bool` — native-side participation gate;
- `muted: bool`;
- `solo: bool`;
- `linearTrim: float`;
- `fader: float`.

The Web wrapper maps browser channel presence to `active=true` only for channels with an attached input for the current render quantum. Missing browser inputs are not represented as processed channels.

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

The Web-facing telemetry remains the existing channel ID plus peak/RMS/clipping fields. The Wasm ABI carries an internal `processed` bit because the native kernel already exposes it; the current Dart browser telemetry contract does not need a new public field for this slice.

### Master stage

After summing processed channels, multiply both channels by `masterGainLinear`, then clamp any sample whose absolute value exceeds the current ceiling:

```text
LIMITER_CEILING = 0.98
```

This remains a deterministic sample ceiling, not a standards-based true-peak limiter. UI and docs must not relabel it as LUFS/dBTP or mastering-grade limiting.

## Wasm ABI boundary

Add a tiny C-compatible wrapper around the canonical C++ kernel. ABI v1 is byte-exact and independent of implementation-defined C++ `bool` layout.

```c
#define LMM_DSP_ABI_VERSION 1u
#define LMM_DSP_MAX_CHANNELS 8u

typedef struct {
  uint32_t active;
  uint32_t muted;
  uint32_t solo;
  float linear_trim;
  float fader;
} LmmDspChannelConfigAbi;          // 20 bytes

typedef struct {
  uint32_t processed;
  float peak_left;
  float peak_right;
  float rms_left;
  float rms_right;
  uint32_t clipping;
} LmmDspChannelMeterAbi;           // 24 bytes

typedef struct {
  float peak_left;
  float peak_right;
  uint32_t limiter_active;
} LmmDspMasterMeterAbi;            // 12 bytes

enum LmmDspStatus {
  LMM_DSP_OK = 0,
  LMM_DSP_INVALID_ARGUMENT = 1,
  LMM_DSP_CHANNEL_LIMIT_EXCEEDED = 2
};

uint32_t lmm_dsp_abi_version(void);
uint32_t lmm_dsp_max_channels(void);
int32_t lmm_dsp_process_stereo(
    const LmmDspChannelConfigAbi* configs,
    const uint32_t* input_ptrs,
    uint32_t channel_count,
    uint32_t frames,
    float master_gain,
    float* interleaved_output,
    LmmDspChannelMeterAbi* channel_meters,
    LmmDspMasterMeterAbi* master_meter);
```

All ABI fields are 4-byte aligned. C/C++ compile-time `static_assert` checks must verify the three struct sizes above.

`input_ptrs` points to `channel_count` wasm32 byte offsets. Each offset identifies one preallocated interleaved stereo `float` buffer of exactly `frames * 2` samples. The wrapper converts the ABI configs into fixed stack storage, builds the native pointer table in fixed stack storage, invokes `lmm::processStereoBlock`, and copies the native meters back to ABI structs. The wrapper uses no heap allocation.

`LMM_DSP_MAX_CHANNELS=8` is the v1 ABI ceiling. The current approved mixer surface exposes four channels, so v1 has explicit headroom without an unbounded stack contract. Requests above eight channels fail with `LMM_DSP_CHANNEL_LIMIT_EXCEEDED`; increasing the ABI ceiling requires a reviewed ABI change.

Configuration values reaching this ABI must already be finite. Existing browser protocol normalization remains responsible for rejecting/replacing non-finite values before the real-time path.

The wrapper must not allocate, log, open files, access clocks, call network APIs, or own thread primitives while processing a block.

## Toolchain and build flags

Reuse the repository's already-pinned WebAssembly toolchain rather than introducing a second compiler version:

- Emscripten SDK: `6.0.9`;
- C++ standard: C++17;
- optimization: release `-O3`;
- `ALLOW_MEMORY_GROWTH=0` for the production DSP module;
- filesystem disabled;
- pthreads disabled;
- no JS DSP glue generated as a second arithmetic implementation;
- export only linear memory, init-time allocation/free symbols if required by the chosen standalone build, and the three `lmm_dsp_*` ABI functions above.

The source-controlled build wrapper must fail if the expected Emscripten version is not active.

## Memory model

Real-time safety is the primary constraint.

### Initialization phase

The browser gateway in `lib/audio/web/browser_audio_worklet_gateway_web.dart` currently creates the `AudioContext`, loads `audio/livemixmaster-worklet.js`, creates the node, wires workers, connects the graph, and resumes the context. The Wasm initialization inserts an explicit handshake before graph connection/resume:

1. create `AudioContext`;
2. fetch fixed same-origin `audio/livemixmaster-dsp.wasm` from the browser host layer;
3. reject non-success HTTP responses;
4. read bytes and call `WebAssembly.compile(...)` in the browser host, outside the AudioWorklet callback;
5. load `audio/livemixmaster-worklet.js` with `audioWorklet.addModule(...)`;
6. create `AudioWorkletNode`;
7. send `{type: 'dspInit', abiVersion: 1, module: compiledModule}` through `workletNode.port`;
8. the worklet instantiates the supplied module during initialization, validates `lmm_dsp_abi_version()==1` and `lmm_dsp_max_channels()==8`, allocates all fixed Wasm/sample/control buffers once, then replies `{type: 'dspReady'}`;
9. the Dart gateway waits for `dspReady` with a bounded startup timeout;
10. only then connect source -> worklet -> destination, start optional analysis, and resume the context.

Initialization errors map to a deterministic browser-audio failure before the live graph is marked started.

### Fixed render contract

The current browser recorder calculations already encode `_recorderRenderQuantumFrames = 128`. ABI v1 therefore preallocates for a 128-frame render quantum and treats any larger worklet output quantum as an unsupported DSP runtime condition rather than risking out-of-bounds writes.

A later variable-quantum design can raise this explicit limit through a reviewed ABI/build change. This slice does not silently introduce a second dynamic allocation path to handle larger blocks.

### Render phase

After initialization, application code in `AudioWorkletProcessor.process()` must perform no explicit dynamic allocation. Specifically, after cutover the steady-state callback must contain no application-owned:

- `new Float32Array(...)`;
- array growth via `push` for channel meters;
- Wasm `malloc/free`;
- C/C++ heap allocation;
- Wasm instantiation/compilation;
- `fetch` or other network API;
- storage or DOM access;
- logging;
- JSON serialization.

Browser-internal structured-clone/copy behavior performed by `postMessage` is outside application allocation control, but the worklet must reuse precreated message envelopes and preallocated typed-array sample buffers.

Required preallocation/reuse:

- Wasm config array for eight channels;
- eight interleaved stereo input buffers of `128 * 2` floats;
- Wasm input pointer table;
- one interleaved stereo Wasm output buffer of `128 * 2` floats;
- eight ABI channel meter slots + one master meter slot;
- one JavaScript telemetry entry per configured channel, created when configuration changes rather than in `process()`;
- one reusable 128-frame interleaved recording scratch buffer;
- one reusable 128-frame interleaved analysis scratch buffer;
- reusable message envelope objects for telemetry/recording/analysis notifications.

Because the existing recorder/analysis `postMessage` paths do not transfer ownership of their typed arrays, structured clone captures the sent contents and the application-owned scratch arrays can be refilled on the next eligible quantum. Existing outstanding-message counters continue to provide backpressure.

The worklet copies browser inputs into preallocated Wasm input regions, writes channel configuration, invokes `lmm_dsp_process_stereo`, then copies the returned stereo output into the browser output bus. Meter fields are read from the fixed meter region and written into the precreated telemetry entries.

## Module loading and browser boundary

The Wasm asset path is fixed as:

```text
audio/livemixmaster-dsp.wasm
```

It is same-origin and never supplied by user/session data.

The browser host owns fetch/compile so the worklet performs no network work. ABI validation and Wasm instantiation occur during the `dspInit` handshake, never during `process()`.

If fetch, compilation, structured clone, instantiation, ABI validation, or startup timeout fails, the Web audio backend must surface a deterministic unavailable state and must not silently claim canonical-DSP parity.

During migration, the current JavaScript arithmetic may exist only behind an explicit non-production test/development flag. Once Wasm parity is declared production-ready, release builds fail closed rather than silently falling back to JavaScript arithmetic.

## Worklet integration

`web/audio/livemixmaster-worklet.js` keeps responsibility for:

- AudioWorklet lifecycle;
- browser input/output bus marshaling;
- configuration message handling;
- Wasm initialization handshake;
- telemetry cadence and ACK/backpressure;
- recording PCM handoff;
- analysis PCM handoff.

It stops owning mixer arithmetic after cutover.

The recording and fingerprint handoffs consume post-master samples copied from the canonical Wasm output. Their existing bounded outstanding-message limits remain unchanged.

The worklet must not create a second gain/limiter pass around the Wasm output. Browser-only mono-input mirroring remains marshaling behavior, not a second DSP algorithm.

For telemetry, the worklet may report configured-but-unprocessed channels as zero peak/RMS with `clipping=false`; this avoids dynamic meter-array construction in `process()` while preserving truthful absence of signal. The Dart telemetry map remains keyed by the configured channel IDs.

## Build and artifact model

Add an Emscripten build target for the DSP wrapper plus `native/dsp_kernel.hpp`.

Requirements:

- compiler version check for Emscripten `6.0.9`;
- compile only the DSP wrapper/kernel needed by this module;
- no filesystem runtime;
- no pthread dependency;
- no memory growth in production module;
- export only the minimal ABI/memory/init symbols;
- deterministic output at `web/audio/livemixmaster-dsp.wasm` during source/build preparation and under the corresponding `build/web/audio/` release path;
- `flutter build web --release` packages the already-built Wasm asset;
- exact-artifact workflow tests and deploys the same packaged Wasm bytes without rebuilding Flutter during Vercel promotion.

Generated Wasm is a build artifact. The C++ wrapper and build script are source-controlled. If the repository elects not to commit generated Wasm bytes, CI must reproducibly build them before Flutter Web packaging and then checksum the packaged result; if generated bytes are committed under the existing asset policy, CI must still rebuild-and-compare them before release. The implementation plan must choose one of those two policies explicitly based on the current Chromaprint asset pattern rather than allowing both in production.

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
8. zero/empty-frame behavior in non-worklet harnesses;
9. asymmetric left/right samples;
10. non-default trim and fader values.

For every applicable vector, compare:

- output samples;
- channel processed state in native/Wasm harnesses;
- channel peaks;
- channel RMS;
- channel clipping state;
- master left/right peak;
- limiter-active state.

Numeric tolerance remains `1.0e-6` unless cross-compiler evidence shows a narrowly justified adjustment. Any tolerance change must be explicit and reviewed; it must not be loosened simply to make CI green.

Required implementations under the parity gate:

- native C++ direct kernel;
- browser Wasm kernel;
- Dart reference kernel while it remains in the repository.

The JavaScript production arithmetic path leaves the parity set once it is no longer production code.

## Test strategy and TDD boundary

Implementation must proceed red-first.

### Contract red phase

Add tests that fail because the Wasm ABI/module, build target, and browser initialization handshake do not yet exist. The red evidence must be isolated to the new shared-DSP contract rather than produced by breaking unrelated mixer behavior.

### ABI/native phase

Tests must verify:

- ABI version is exactly `1`;
- max channels is exactly `8`;
- compile-time struct-size assertions hold;
- `channel_count > 8` returns `LMM_DSP_CHANNEL_LIMIT_EXCEEDED`;
- valid input pointer table/configs map to the current native kernel output without semantic changes.

### Native/Wasm parity

Build the native fixture runner and Wasm fixture harness from the same vector file. Run both and compare deterministic outputs/telemetry.

### Worklet integration

Browser tests must prove:

- gateway sends one `dspInit` with ABI version `1` before graph connection;
- the worklet does not report ready before successful module instantiation + ABI checks;
- ABI mismatch fails closed;
- module initialization failure surfaces deterministic safe unavailable state;
- 128-frame stereo and mono-input marshaling are deterministic;
- a render quantum larger than the v1 allocation ceiling fails safely rather than writing out of bounds;
- post-master recording/analysis PCM is copied from Wasm output;
- existing telemetry/recording/analysis ACK/backpressure remains bounded;
- production `process()` contains no application-owned dynamic sample-buffer allocation or duplicate gain/sum/clamp arithmetic after cutover.

### Release artifact

The exact Web artifact must contain `build/web/audio/livemixmaster-dsp.wasm`, and exact-artifact browser E2E must exercise that packaged asset rather than a dev-server-only module.

## Error model

Failures are deterministic and non-secret. Operator-facing states are:

- `DSP MODULE UNAVAILABLE — AUDIO ENGINE NOT READY`
- `DSP MODULE VERSION MISMATCH — AUDIO ENGINE NOT READY`
- `DSP MODULE INITIALIZATION FAILED — AUDIO ENGINE NOT READY`
- `DSP RENDER QUANTUM UNSUPPORTED — AUDIO ENGINE NOT READY`

Do not expose raw Wasm stack traces, local build paths, binary dumps, PCM contents, internal pointers, or browser exception objects in operator UI/evidence.

A DSP initialization/runtime contract failure is different from a fingerprint-preparation failure: because DSP is on the live audio path, the browser mix must not start or continue under a falsely canonical state when the Wasm DSP contract is unavailable.

## Performance and real-time acceptance

Correct parity is necessary but not sufficient. Acceptance also requires evidence that bounded real-time behavior is preserved.

At minimum CI/browser evidence must prove:

- no application-owned per-block allocation in `process()` after initialization;
- no network/storage API reachable from DSP process code;
- bounded telemetry/recording/analysis outstanding messages remain intact;
- the worklet renders continuously through a deterministic multi-second synthetic fixture without invalid output;
- limiter/meter behavior remains stable under a high-amplitude multi-channel vector;
- no Wasm memory growth occurs after `dspReady`.

This design does not promise a universal browser latency number. Browser/OS scheduling differs and must be measured separately rather than encoded as a false cross-platform guarantee.

## Security and provenance

- Wasm asset is same-origin and produced by repository-controlled build tooling.
- No runtime-selectable arbitrary Wasm URL.
- No provider credentials or user secrets in the module.
- No network/storage in the canonical DSP wrapper.
- Release evidence records source SHA, Emscripten version, Wasm artifact SHA-256, and exact Web artifact digest without recording PCM/user media.
- Existing Vercel exact-artifact promotion remains authoritative; this design does not introduce a separate deployment path.

## Migration sequence

1. Extend parity fixtures/contracts and obtain red evidence for the missing Wasm implementation.
2. Add C ABI wrapper + native ABI unit tests without changing production Web DSP.
3. Add pinned Emscripten 6.0.9 build and Wasm parity harness; make native/Dart/Wasm vectors green.
4. Add browser host fetch/compile + worklet `dspInit`/`dspReady` handshake behind a non-production feature gate.
5. Remove explicit per-block sample/meter allocations by introducing the fixed/reused buffers specified above.
6. Run existing Web mixer/operator/session/recording/fingerprint contracts with Wasm enabled in CI.
7. Switch production Web configuration to canonical Wasm DSP and remove duplicate arithmetic from the production worklet.
8. Keep old JS arithmetic only if needed as an explicitly non-production test fixture; otherwise delete it.
9. Run `flutter build web --release`, exact-artifact browser E2E, and macOS Desktop CI on one exact head.
10. Promote to `preview`, verify Wasm checksum + exact artifact + Vercel deployment, then merge only after review/approval.
11. Let the existing `main` push pipeline build/test the merge commit and promote that exact tested artifact to production.

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
- replace existing release provenance or Vercel deployment workflow;
- introduce Rust or another DSP language/toolchain.

## Acceptance criteria

This slice is complete only when all of the following are true on one exact Git SHA:

1. `native/dsp_kernel.hpp` remains the canonical DSP implementation for desktop and Web.
2. ABI v1 exports the exact fixed-width layout and channel limit documented above and wraps the kernel without process-time allocation/network/storage/logging/filesystem work.
3. Emscripten `6.0.9` produces the same-origin Wasm release asset with memory growth/filesystem/pthreads disabled as specified.
4. The browser gateway fetches/compiles the module before graph start, and the worklet completes `dspInit`/`dspReady` + ABI validation before source connection/resume.
5. Steady-state `process()` uses fixed/reused application buffers and contains no duplicate production mixer arithmetic after cutover.
6. Native C++, browser Wasm, and retained Dart reference kernel pass the same parity vectors within `1.0e-6` unless a separately reviewed tolerance change is evidenced.
7. Existing Web recording, fingerprint, telemetry-backpressure, session, mixer, and operator contracts remain green with Wasm enabled.
8. `flutter build web --release` packages `audio/livemixmaster-dsp.wasm`, and exact-artifact browser E2E exercises that packaged asset.
9. macOS Desktop CI remains green on the same head through native engine build, package, and launch smoke.
10. Preview promotion deploys the exact tested artifact with non-secret Wasm/source/artifact provenance recorded.
11. No new claim is made for LUFS/dBTP, native loopback parity, or physical-device acceptance.

## Spec approval gate

No implementation plan or production code change should be generated from this design until this spec is explicitly approved. After approval, create a separate implementation plan under `docs/superpowers/plans/` using red-green TDD tasks and the existing exact-artifact release gates.
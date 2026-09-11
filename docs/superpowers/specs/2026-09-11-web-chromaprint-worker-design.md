# LiveMixMaster Web Chromaprint Worker Design

Date: 2026-09-11
Tracking: #16 / PR #20
Parent plan: `docs/superpowers/plans/2026-09-10-web-release.md`

## Goal

Replace the placeholder Web fingerprint-preparation gap with a reproducible, evidence-backed Chromaprint pipeline that converts post-master browser PCM into a real AcoustID-compatible fingerprint without blocking the AudioWorklet, shipping provider credentials, or inventing a proprietary fingerprint format.

## Problem statement

The existing desktop `FingerprintService` currently labels its preparation path as Chromaprint but base64-encodes a slice of raw PCM. That payload is not a Chromaprint fingerprint and must not be copied into the Web implementation. The Web branch already has a verified server-side AcoustID proxy and a Flutter `BrowserFingerprintLookupController` that accepts a prepared fingerprint. The missing boundary is therefore strictly: post-master PCM -> real Chromaprint fingerprint -> existing proxy client/controller.

## Selected architecture

Use official Chromaprint v1.6.1 compiled to WebAssembly with Emscripten 6.0.9 and run it only inside a Dedicated Worker.

```text
AudioWorklet post-master Float32 stereo PCM
                 |
       bounded analysis handoff
                 v
Dedicated fingerprint Worker
  - rolling 10 s window
  - Float32 -> signed PCM16
  - Chromaprint WASM call
  - no provider/network credentials
                 |
       {duration,fingerprint}
                 v
Flutter Web fingerprint bridge
                 |
BrowserFingerprintLookupController
                 |
POST /api/fingerprint-lookup
                 |
AcoustID (credential server-side only)
```

The AudioWorklet remains a real-time component and performs no fingerprint computation, Wasm allocation, networking, storage, or unbounded buffering. Fingerprinting occurs in a separate Worker and is allowed to be slower than real time as long as the mix and recording paths continue.

## Version and source pinning

- Chromaprint: `v1.6.1`.
- Official source archive SHA-256: `3368805af0ee47b9df74df10b5001a44569e01df2844dab520031720dde9ad23`.
- Emscripten SDK: `6.0.9`.
- FFT backend: bundled KissFFT path; do not add FFTW.
- Chromaprint build: `BUILD_TOOLS=OFF`, `BUILD_TESTS=OFF`, `BUILD_SHARED_LIBS=OFF`, `FFT_LIB=kissfft`.

The build script must fail if the source digest does not match. Generated Wasm/JS output is a build artifact, not hand-edited source.

## Wasm wrapper boundary

Add a tiny C++ wrapper around the public Chromaprint C API. The exported function accepts a pointer to interleaved signed PCM16, sample count, sample rate, and channel count. It creates a default Chromaprint context, calls `chromaprint_start`, `chromaprint_feed`, `chromaprint_finish`, then `chromaprint_get_fingerprint`, copies the returned UTF-8 fingerprint into Emscripten-managed memory, and frees all Chromaprint allocations before returning.

Expose only the minimum ABI required by the Worker:

- `lmm_chromaprint_fingerprint(...)`
- `lmm_chromaprint_free(...)`
- `_malloc`
- `_free`

The wrapper returns explicit failure/null rather than partial fingerprints.

## PCM contract

The existing AudioWorklet emits post-master interleaved `Float32Array` stereo blocks and the runtime sample rate. The fingerprint Worker owns conversion to signed PCM16 using deterministic clipping and quantization:

- non-finite input -> `0`
- clamp to `[-1.0, 1.0]`
- negative samples multiply by `32768`
- non-negative samples multiply by `32767`
- round to nearest integer

The Worker preserves the original sample rate and channel count when invoking Chromaprint. It does not implement a second resampler. This keeps format conversion inside official Chromaprint rather than creating an additional unverified DSP path.

## Windowing and backpressure

The Worker keeps at most one 10-second stereo analysis window plus one in-flight fingerprint request. It must not accumulate unbounded session PCM.

- Target window: 10 seconds.
- Analysis cadence: at most once every 8 seconds.
- If a fingerprint computation is already in progress, additional analysis triggers are skipped rather than queued.
- The Worker accepts bounded PCM messages and returns an ACK so the sender can cap outstanding analysis buffers independently from the recording Worker.
- Fingerprint failure must never stop mixing or recording.

## Golden parity evidence

A deterministic PCM fixture is required. CI generates or stores a short WAV with known sample rate/channels and derives a reference fingerprint using official `fpcalc` v1.6.1. The same decoded PCM samples are sent through the WebAssembly wrapper. The encoded fingerprint strings must match exactly.

The parity test is authoritative for accepting the Wasm build. A test that merely checks for a non-empty string is insufficient.

CI must additionally verify:

- the source archive SHA-256 before compilation;
- the Wasm module reports Chromaprint 1.6.1;
- no AcoustID credential appears in Worker/Wasm assets;
- the Worker has no direct `fetch`, XHR, WebSocket, storage, or DOM dependency;
- invalid/short PCM yields an explicit failure state rather than a fabricated fingerprint.

## Flutter/browser integration

Add a browser-only fingerprint preparation gateway behind conditional imports. VM/widget tests use a deterministic stub. The browser gateway owns Worker startup, request IDs, timeout/failure mapping, and disposal. It forwards only the Worker result `{fingerprint, durationSeconds}` to the existing `BrowserFingerprintLookupController.lookupPreparedFingerprint` method.

The UI/operator state remains controlled by the existing lookup controller. This slice must not introduce a second competing provider-state model.

## Error model

Worker/preparation failures map to deterministic non-secret messages such as:

- `FINGERPRINT PREPARATION UNAVAILABLE — MIX / RECORDING CONTINUE`
- `FINGERPRINT PREPARATION TIMEOUT — MIX / RECORDING CONTINUE`
- `FINGERPRINT AUDIO WINDOW TOO SHORT — SESSION CONTINUES`

No raw Wasm stack, filesystem/build path, provider credential, endpoint URL, or PCM content is surfaced to the operator.

## Security and real-time constraints

- No provider credentials in Flutter, Worker, Wasm, manifest, or `build/web`.
- No provider network request from Worker/Wasm.
- No fingerprint computation on the AudioWorklet thread.
- No unbounded queue between AudioWorklet and fingerprint Worker.
- No arbitrary module URL supplied from browser state; asset paths are fixed same-origin release assets.
- Existing server proxy timeout/retry/redaction remains authoritative for provider traffic.

## Licensing/provenance gate

Chromaprint v1.6.1 documents LGPL-2.1 considerations for the project as a whole and its bundled FFmpeg-derived code. The repository must retain source/version/digest provenance and a third-party notice for the distributed WebAssembly artifact. W5 production promotion must not proceed until the release package's third-party notices and source/relinkability obligations are reviewed and satisfied. This design does not make a legal-compliance determination.

## Desktop interaction

Do not silently reuse the current desktop pseudo-fingerprint implementation as reference behavior. The Web parity test is based on official Chromaprint/fpcalc behavior. Desktop correctness is a separate follow-up so this W4 slice does not destabilize PR #15 or broaden into native audio changes.

## Acceptance criteria

This slice is complete only when all of the following are true on one exact Git SHA:

1. CI builds Chromaprint v1.6.1 to Wasm from checksum-verified source with Emscripten 6.0.9.
2. Golden PCM produces exactly the same encoded fingerprint through Wasm and official `fpcalc` v1.6.1.
3. Dedicated Worker prepares fingerprints without networking/storage/DOM access and with bounded buffering.
4. Browser gateway calls the existing fingerprint lookup controller using only prepared fingerprint + duration.
5. `flutter build web --release` packages the generated Worker/Wasm assets.
6. Existing W3 recording/DSP and W4 server-proxy contracts remain green.
7. macOS Desktop CI is green on the same head through launch smoke.
8. GitHub Issue #16, PR #20, and the Notion Web/PWA tracker record only non-secret evidence.
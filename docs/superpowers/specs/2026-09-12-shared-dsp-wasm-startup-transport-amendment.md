# LiveMixMaster Shared Native/Web DSP Wasm Design — Startup Transport Amendment

Date: 2026-09-12
Status: approved normative amendment
Amends: `docs/superpowers/specs/2026-09-12-shared-dsp-wasm-design.md`
Tracking: PR #37 / Issue #16

## Decision

The production browser startup boundary transports the fixed same-origin canonical DSP **Wasm bytes**, not a compiled `WebAssembly.Module`.

The normative startup sequence is:

1. create the browser `AudioContext`;
2. fetch fixed same-origin `audio/livemixmaster-dsp.wasm` in the browser host and reject non-success responses;
3. materialize the response as clone-safe `ArrayBuffer` bytes; the browser host does **not** call `WebAssembly.compile(...)` and does not construct a `WebAssembly.Module`;
4. load `audio/livemixmaster-worklet.js` with `audioWorklet.addModule(...)`;
5. create the `AudioWorkletNode`;
6. send `{type: 'dspInit', abiVersion: 1, wasmBytes: <ArrayBuffer>}` through the worklet port;
7. in the worklet `dspInit` message handler, before any live graph connection or resume, synchronously construct the module from those bytes and instantiate it;
8. validate `lmm_dsp_abi_version()==1` and `lmm_dsp_max_channels()==8`, allocate all fixed Wasm/sample/control buffers once, then reply `{type: 'dspReady'}`;
9. the Dart gateway waits for `dspReady` with the existing bounded startup timeout;
10. only after readiness may the source/worklet/destination graph be connected, optional analysis enabled, and the `AudioContext` resumed.

The production gateway must not send a `module` field. A compiled `WebAssembly.Module` is therefore not part of the production transport contract.

Compilation and instantiation remain **initialization-only** work. `AudioWorkletProcessor.process()` must never compile or instantiate Wasm and retains every no-allocation/no-network/no-storage/no-logging/no-JSON steady-state constraint from the approved design.

## Rationale

PR #37 execution reproduced an AudioWorklet startup transport failure when relying on a compiled `WebAssembly.Module` crossing the worklet message boundary. Transporting the deterministic Wasm bytes uses the ordinary clone-safe `ArrayBuffer` boundary and keeps the browser host free of compiled-module transfer assumptions. The change affects startup transport only; it does not create a second DSP implementation or modify arithmetic.

## Superseded clauses

This amendment replaces only the following wording in the approved design:

- the selected-architecture path `fetched + compiled by browser host -> compiled WebAssembly.Module via worklet port` becomes `fetched as bytes by browser host -> clone-safe Wasm bytes via worklet port -> compiled/instantiated by AudioWorklet during dspInit`;
- Initialization Phase step 4 no longer calls `WebAssembly.compile(...)` in the browser host;
- Initialization Phase step 7 uses `wasmBytes` instead of `module`;
- Initialization Phase step 8 performs both module construction/compilation and instantiation before ABI validation and fixed-buffer allocation;
- under Module loading and browser boundary, the browser host owns **fetch and byte loading** while the AudioWorklet owns **initialization-time compile/instantiate**; neither operation may occur in `process()`.

All other design clauses remain authoritative.

## Invariants explicitly unchanged

- `native/dsp_kernel.hpp` remains the canonical DSP arithmetic source for desktop and Web.
- ABI version remains exactly `1`.
- `LMM_DSP_MAX_CHANNELS` remains exactly `8`.
- ABI struct sizes remain exactly 20-byte channel config, 24-byte channel meter, and 12-byte master meter.
- ABI-v1 render quantum ceiling remains exactly 128 frames.
- Sample ceiling remains exactly `0.98`.
- Numeric parity tolerance remains exactly `1.0e-6`; this amendment does not authorize any tolerance widening.
- Emscripten remains pinned to `6.0.9` with the approved production Wasm constraints.
- Production JavaScript mixer arithmetic remains removed/fail-closed after cutover.
- Generated `web/audio/livemixmaster-dsp.wasm` bytes remain uncommitted; CI/build tooling generates them before Flutter Web packaging and byte/checksum-verifies the packaged artifact.
- Exact-artifact browser E2E and Vercel promotion must continue to operate on the same tested Web artifact without rebuilding it.
- Recording, analysis, telemetry, fingerprint, session, provider, capture, LUFS/dBTP, resampling, loopback, and physical-device scope are unchanged.

## Acceptance additions

Merge-readiness evidence must prove all of the following on the exact PR head:

- the production gateway posts `wasmBytes` and does not post a compiled-module field;
- the production gateway does not call `WebAssembly.compile(...)`;
- the worklet constructs/instantiates Wasm only during `dspInit`, before `dspReady`;
- `process()` contains no Wasm compilation or instantiation;
- ABI v1, 8-channel ceiling, 128-frame ceiling, `0.98` sample ceiling, and `1.0e-6` parity checks remain green;
- the generated-Wasm and exact-artifact policies remain green;
- after any amendment commit changes the PR SHA, preview acceptance is repeated for that exact new SHA rather than inheriting evidence from an older head.

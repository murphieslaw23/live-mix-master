# Shared Native/Web DSP Wasm Implementation Plan — Startup Transport Amendment

Date: 2026-09-12
Status: approved execution amendment
Amends: `docs/superpowers/plans/2026-09-12-shared-dsp-wasm.md`
Normative design amendment: `docs/superpowers/specs/2026-09-12-shared-dsp-wasm-startup-transport-amendment.md`
Tracking: PR #37 / Issue #16

## Scope

This amendment changes only the Task 4 startup transport from a compiled `WebAssembly.Module` to clone-safe raw Wasm bytes. The canonical native kernel, ABI-v1 layout, exact parity tolerance, real-time constraints, and generated-artifact policy are unchanged.

## Architecture paragraph replacement

For execution purposes, replace the implementation plan's architecture statement that the browser host compiles and sends a `WebAssembly.Module` with this contract:

> Desktop continues calling the native C++ kernel directly. Web builds a raw Wasm module from the same C++ kernel with Emscripten 6.0.9. The browser host fetches the fixed same-origin Wasm asset as `ArrayBuffer` bytes and sends those bytes to the AudioWorklet through `dspInit`. The worklet compiles/constructs and instantiates the module synchronously in the `dspInit` initialization handler, validates ABI v1 and the 8-channel ceiling, allocates all fixed buffers, and only then replies `dspReady`. The live graph is connected/resumed only after `dspReady`. Compilation/instantiation is forbidden from `process()`.

## Task 4 replacement contract

### Interfaces

- Consumes: fixed same-origin `audio/livemixmaster-dsp.wasm` bytes and ABI version `1`.
- Produces: exactly one production startup message `{type:'dspInit', abiVersion:1, wasmBytes:<ArrayBuffer>}` and exactly one success reply `{type:'dspReady'}` before source/worklet/destination connection/resume.
- The production gateway must not send `module:<WebAssembly.Module>` and must not call `WebAssembly.compile(...)`.

### RED/contract assertions

Task 4 tests must require this order:

```text
fetch Wasm bytes
addModule(worklet)
create AudioWorkletNode
postMessage(dspInit with wasmBytes)
worklet constructs/instantiates Wasm during initialization
validate ABI v1 / max channels 8
receive dspReady
connect source -> worklet -> destination
resume AudioContext
```

The transport regression contract must additionally assert:

- fixed literal asset path `audio/livemixmaster-dsp.wasm`;
- gateway source contains the byte-loading boundary and `wasmBytes` startup field;
- gateway source does not contain `WebAssembly.compile` for the DSP startup path;
- gateway source does not populate a production `module` startup field;
- worklet initialization constructs a `WebAssembly.Module` from received bytes and creates the instance before readiness;
- worklet `process()` contains neither Wasm compilation nor instantiation;
- `process()` before readiness remains fail-closed/silent and never claims canonical-DSP telemetry parity.

### Implementation replacement

Task 4 Step 4 is replaced by:

1. add/retain `_dspHandshakeTimeout`, `_dspAssetPath = 'audio/livemixmaster-dsp.wasm'`, and `_dspAbiVersion = 1`;
2. fetch the fixed asset in the browser host;
3. reject non-success responses and materialize a clone-safe `ArrayBuffer`;
4. send that `ArrayBuffer` as `wasmBytes` in `dspInit`;
5. retain sanitized operator failures without raw exception text.

Task 4 Step 5 is replaced by:

1. initialize the worklet DSP state as not-ready;
2. on `dspInit`, require ABI version `1` and valid Wasm bytes;
3. synchronously construct/compile the module and instantiate it in the message handler, never in `process()`;
4. validate exported ABI version and max channels;
5. allocate all steady-state Wasm/control/sample buffers once;
6. post `dspReady` only after successful validation/allocation; otherwise post the existing sanitized `dspError` code.

## Verification commands

The focused transport gate remains part of the Shared DSP Wasm Contract and must include the startup regression test that enforces clone-safe bytes. At minimum, exact-head CI must execute the equivalent of:

```bash
node --test \
  test/web_audio_graph_integration_test.mjs \
  test/web_audio_worklet_processor_test.mjs \
  test/web_audio_worklet_wasm_transport_contract_test.mjs
flutter test test/web_dsp_startup_boundary_test.dart
```

The broader ABI/parity/build/release gates from the original plan remain mandatory; this amendment does not replace them.

## Generated artifact and exact-head policy

Generated DSP Wasm remains a build artifact and must not be committed. CI must generate it with pinned Emscripten, package those exact bytes into Flutter Web, byte/checksum-verify the packaged copy, and pass the same tested Web artifact into browser E2E and Vercel promotion without rebuilding.

Because this amendment itself changes the PR commit SHA, any older preview acceptance belongs only to its older exact head. After committing this amendment, fast-forward `preview` non-force to the new accepted PR head and rerun the repository's existing exact-artifact preview path. Merge readiness requires the resulting GitHub success record and a READY Vercel preview whose Git metadata matches that new head.

## Constraints that may not be relaxed to make the gate green

- Do not edit `native/dsp_kernel.hpp` for this transport amendment.
- Do not change ABI version `1`, max channels `8`, or 20/24/12-byte layouts.
- Do not increase the 128-frame ABI-v1 quantum ceiling.
- Do not change the `0.98` sample ceiling.
- Do not widen `1.0e-6` parity tolerance.
- Do not restore production JavaScript mixer arithmetic.
- Do not commit generated `.wasm` bytes.
- Do not rebuild the Web artifact between accepted browser E2E and Vercel promotion.

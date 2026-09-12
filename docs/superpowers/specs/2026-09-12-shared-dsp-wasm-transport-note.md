# Shared DSP Wasm transport implementation note

Date: 2026-09-12
Tracking: Issue #16, PR #36, PR #37
Status: verified implementation amendment to the approved shared-DSP design

## Amendment

The approved design originally described compiling `audio/livemixmaster-dsp.wasm` on the browser host and posting a compiled `WebAssembly.Module` to the `AudioWorkletProcessor` during the `dspInit` handshake.

Exact-artifact Chromium acceptance exposed that transport as unsafe in the browser version exercised by CI: the Wasm asset and worklet both loaded successfully, but the compiled module did not reliably cross the `AudioWorkletNode.port` structured-clone boundary, so `dspReady` was never observed and the mixer correctly remained fail-closed.

The verified production transport is therefore:

1. the browser gateway fetches the fixed same-origin `audio/livemixmaster-dsp.wasm` asset before graph connection;
2. the gateway reads the response as a raw `ArrayBuffer`;
3. the gateway loads `audio/livemixmaster-worklet.js` and creates the `AudioWorkletNode`;
4. the gateway posts `{type: 'dspInit', abiVersion: 1, wasmBytes: <ArrayBuffer>}`;
5. the worklet constructs `new WebAssembly.Module(message.wasmBytes)` and instantiates it during initialization, outside `process()`;
6. the worklet validates ABI version/channel ceiling, performs all fixed allocations, and emits `dspReady`;
7. only after the bounded `dspReady` handshake does the gateway connect the live graph and resume the `AudioContext`.

## Unchanged architecture

This amendment does **not** change the canonical DSP architecture or arithmetic contract:

- `native/dsp_kernel.hpp` remains the single canonical DSP implementation;
- ABI v1 remains unchanged, including the 8-channel ceiling and 20/24/12-byte structures;
- Emscripten remains pinned to 6.0.9 with fixed memory/no pthreads/no filesystem;
- the AudioWorklet still performs no Wasm compilation, instantiation, network I/O, or application-owned allocation inside `process()`;
- release builds still fail closed on fetch, initialization, ABI, render, memory, or process failure;
- JavaScript mixer arithmetic remains removed from the production worklet;
- generated Wasm remains a CI-built artifact whose packaged bytes are compared and checksummed before exact-artifact browser testing and promotion.

## Verification evidence

On implementation head `001fc5d9c2750a5d6af66aed7d753b3af550bd3c`:

- `Shared DSP Wasm Contract` run `34705556386` passed the clone-safe transport/startup, parity, render-allocation, fail-closed, and provenance contracts;
- aggregate CI run `34705556525` built Web artifact `10300813831` with artifact digest `sha256:2a2202378ca72df359bdb215ee909e68c4cbdcce09be5c33c955789d3e97b0d9`;
- generated and packaged `audio/livemixmaster-dsp.wasm` share SHA-256 `1b7f7a019a5102d59587bb172b9ecaf76953aea6aee8c789adcd9caeaed52526`;
- exact-artifact browser job `103585175018` downloaded that artifact without rebuilding and passed all four Playwright tests: Chromium operator flow plus Chromium, Firefox, and WebKit capability evidence;
- browser acceptance evidence artifact: `10301139840`.

This note supersedes only the compiled-`WebAssembly.Module` transport wording in the original design/plan. All other approved design constraints remain authoritative.

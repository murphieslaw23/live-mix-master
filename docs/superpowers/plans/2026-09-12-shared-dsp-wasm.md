# Shared Native/Web DSP Wasm Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `native/dsp_kernel.hpp` the single production mixer-DSP implementation for desktop and Flutter Web by compiling a versioned C ABI wrapper to WebAssembly and executing it inside the AudioWorklet with fixed, bounded real-time buffers.

**Architecture:** Desktop continues calling the native C++ kernel directly. Web builds a raw Wasm module from the same C++ kernel with Emscripten 6.0.9; the browser host fetches and compiles the fixed same-origin module, passes the compiled `WebAssembly.Module` to the AudioWorklet through a `dspInit` handshake, and only starts the live graph after `dspReady`. The current Dart kernel stays as a deterministic reference oracle, while duplicate production JavaScript gain/sum/clamp arithmetic is removed after native/Wasm/Dart parity is proven.

**Tech Stack:** C++17, Emscripten 6.0.9, WebAssembly, JavaScript AudioWorklet, Dart/Flutter Web 3.47.2, Node 24 `node:test`, Playwright 1.63.0, GitHub Actions, Vercel exact-artifact promotion.

**Spec:** `docs/superpowers/specs/2026-09-12-shared-dsp-wasm-design.md`

## Global Constraints

- `native/dsp_kernel.hpp` remains the canonical DSP arithmetic source.
- ABI version is exactly `1`; `LMM_DSP_MAX_CHANNELS` is exactly `8`.
- ABI struct sizes are fixed at 20-byte channel config, 24-byte channel meter, and 12-byte master meter.
- Browser render quantum ceiling for ABI v1 is exactly 128 frames.
- Limiter/sample ceiling remains exactly `0.98`; do not relabel it as true-peak limiting.
- Parity tolerance remains `1.0e-6` unless a separately reviewed evidence-backed change is approved.
- Emscripten is pinned to `6.0.9`; C++ standard is C++17; production Wasm uses `ALLOW_MEMORY_GROWTH=0`, no filesystem, and no pthreads.
- Production Wasm asset path is exactly `audio/livemixmaster-dsp.wasm`.
- No production JavaScript DSP fallback after cutover. Initialization or ABI failure must fail closed before the Web audio graph is considered started.
- `AudioWorkletProcessor.process()` must perform no application-owned steady-state dynamic sample-buffer allocation, Wasm heap allocation/free, fetch/network, storage, DOM, logging, or JSON serialization.
- Recording, analysis, telemetry ACK/backpressure, fingerprint, session, and provider boundaries remain unchanged except for consuming canonical Wasm post-master samples.
- Generated DSP Wasm bytes are **not committed**. Match the existing Chromaprint policy: CI/build tooling generates the asset before `flutter build web --release`; `.gitignore` excludes the generated file; CI verifies the packaged checksum.
- No LUFS, dBTP, resampling, new capture behavior, native loopback claims, provider changes, or physical macOS/BlackHole acceptance are part of this plan.

---

## File Structure

### New files

- `native/dsp_wasm_abi.h` — fixed-width ABI v1 types, status codes, constants, and exported C function declarations.
- `native/dsp_wasm_abi.cpp` — heap-free bridge from ABI memory to `lmm::processStereoBlock`.
- `native/tests/dsp_wasm_abi_test.cpp` — native ABI contract and error-path tests.
- `tool/build_dsp_wasm.sh` — pinned Emscripten 6.0.9 build producing `web/audio/livemixmaster-dsp.wasm` and checksum evidence.
- `test/helpers/dsp_wasm_harness.mjs` — Node helper for instantiating the raw Wasm module, allocating fixed test buffers, invoking ABI v1, and decoding meters/output.
- `test/web_dsp_wasm_build_contract_test.mjs` — build/export/import/memory-growth/source-contract checks.
- `test/web_dsp_wasm_parity_test.mjs` — shared TSV parity vectors against the Wasm ABI.
- `test/web_dsp_worklet_allocation_contract_test.mjs` — source-level steady-state no-allocation/no-duplicate-arithmetic gate.

### Modified files

- `test/fixtures/dsp_parity_vectors.tsv` — expand to all approved parity cases.
- `native/tests/dsp_parity_vectors_test.cpp` — expose/check processed channel state and expanded meter expectations where the fixture format requires it.
- `lib/audio/web/web_dsp_kernel.dart` — remain a reference oracle; only extend its tests/fixture adapter if required by the expanded vectors.
- `test/web_dsp_kernel_test.dart` — verify Dart reference parity against the expanded fixture set.
- `web/audio/livemixmaster-worklet.js` — add Wasm init, ABI validation, preallocated memory/views/message envelopes, mono/stereo marshaling, and canonical process call; remove production JS mixer arithmetic after cutover.
- `lib/audio/web/browser_audio_worklet_gateway_web.dart` — fetch/compile the fixed Wasm asset, perform bounded `dspInit`/`dspReady` startup, sanitize failures, and connect/resume only after readiness.
- `test/web_audio_worklet_processor_test.mjs` — switch production-path tests to initialized Wasm and add ABI/render/backpressure/post-master cases.
- `test/web_audio_graph_integration_test.mjs` — assert host compilation and `dspReady` occur before graph connection/resume.
- `test/web_release_compile_boundary_test.dart` — require the fixed Wasm asset/loading boundary and safe error vocabulary.
- `test/browser/operator.spec.mjs` — record successful packaged Wasm fetch/use during exact-artifact operator flow.
- `.gitignore` — ignore generated `web/audio/livemixmaster-dsp.wasm`.
- `.github/workflows/ci.yml` — build/verify DSP Wasm before worklet tests, package it into Flutter Web, record checksum, and preserve exact-artifact deployment.

---

### Task 1: Expand the canonical parity oracle and establish the RED gate

**Files:**
- Modify: `test/fixtures/dsp_parity_vectors.tsv`
- Modify: `native/tests/dsp_parity_vectors_test.cpp`
- Modify: `test/web_dsp_kernel_test.dart`
- Create: `test/web_dsp_wasm_build_contract_test.mjs`
- Create: `test/web_dsp_wasm_parity_test.mjs`

**Interfaces:**
- Consumes: existing TSV columns and `lmm::processStereoBlock` semantics.
- Produces: one fixture set used by native C++, Dart reference, and Wasm tests; initial Wasm tests intentionally fail because `tool/build_dsp_wasm.sh`, ABI files, and module output do not exist yet.

- [ ] **Step 1: Expand the fixture set without changing expected semantics**

Keep the existing tab-separated row shape for output/master fields and add cases covering nominal gain, mute, solo isolation, multi-channel stereo sum, positive limiter clamp, negative clamp, clipping-before-master, asymmetric stereo, and non-default trim/fader. Example new rows:

```text
negative-clamp\t1.0\thot;1.0;1.0;0;0;-2.0,2.0\t-0.98,0.98\t1\t0.98\t0.98
asymmetric-trim-fader\t1.0\ta;0.5;0.5;0;0;0.8,-0.4,0.2,-0.1\t0.1,-0.05,0.025,-0.0125\t0\t0.1\t0.05
```

Use the canonical formula `linearTrim * fader * fader` when calculating expected channel/output values.

- [ ] **Step 2: Extend native fixture assertions to channel meters/processed state**

Introduce expected channel-meter parsing only if needed via an additional fixture column rather than hard-coding case names. The parser must reject malformed row widths. The comparison helper remains:

```cpp
bool closeEnough(float actual, float expected) {
  return std::fabs(actual - expected) <= 1.0e-6F;
}
```

Assert `processed`, `peakLeft`, `peakRight`, `rmsLeft`, `rmsRight`, and `clipping` for every configured channel where the fixture declares meter expectations.

- [ ] **Step 3: Make the Dart reference consume the same expanded vectors**

In `test/web_dsp_kernel_test.dart`, parse the same fixture rows into `WebDspChannelBlock` values and assert output, channel meter, master peak, and limiter state with `1.0e-6` tolerance.

- [ ] **Step 4: Add the missing-Wasm RED contract**

`test/web_dsp_wasm_build_contract_test.mjs` must require the future generated asset and ABI exports:

```js
const wasmUrl = new URL('../web/audio/livemixmaster-dsp.wasm', import.meta.url);
await assert.rejects(
  fs.access(wasmUrl),
  /ENOENT/,
  'RED prerequisite: DSP Wasm asset should not exist before build implementation',
);
```

Then add the future GREEN assertions in a separate test that will fail once the RED guard is flipped during Task 3:

```js
const bytes = await fs.readFile(wasmUrl);
const module = await WebAssembly.compile(bytes);
const exports = WebAssembly.Module.exports(module).map(({ name }) => name);
for (const name of ['memory', 'lmm_dsp_abi_version', 'lmm_dsp_max_channels', 'lmm_dsp_process_stereo']) {
  assert.ok(exports.includes(name), `missing Wasm export: ${name}`);
}
```

- [ ] **Step 5: Add the initial Wasm parity test skeleton**

`test/web_dsp_wasm_parity_test.mjs` imports `./helpers/dsp_wasm_harness.mjs`, loads the TSV vectors, and expects `runWasmVector(vector)` to return output/meters/master values. Do not create the helper yet.

```js
test('Wasm DSP matches canonical parity vectors', async () => {
  const vectors = await loadParityVectors();
  for (const vector of vectors) {
    const actual = await runWasmVector(vector);
    assertVectorClose(actual, vector, 1e-6);
  }
});
```

- [ ] **Step 6: Verify the RED phase**

Run:

```bash
c++ -std=c++17 -O2 -I native native/tests/dsp_parity_vectors_test.cpp -o /tmp/lmm-dsp-parity
/tmp/lmm-dsp-parity test/fixtures/dsp_parity_vectors.tsv
flutter test test/web_dsp_kernel_test.dart
node --test test/web_dsp_wasm_build_contract_test.mjs test/web_dsp_wasm_parity_test.mjs
```

Expected: native and Dart reference tests PASS; Wasm contract/parity tests FAIL only because the ABI/build/module/harness are not implemented.

- [ ] **Step 7: Commit the isolated RED evidence**

```bash
git add test/fixtures/dsp_parity_vectors.tsv native/tests/dsp_parity_vectors_test.cpp test/web_dsp_kernel_test.dart test/web_dsp_wasm_build_contract_test.mjs test/web_dsp_wasm_parity_test.mjs
git commit -m "test: define shared DSP Wasm parity contract"
```

---

### Task 2: Implement ABI v1 around the canonical C++ kernel

**Files:**
- Create: `native/dsp_wasm_abi.h`
- Create: `native/dsp_wasm_abi.cpp`
- Create: `native/tests/dsp_wasm_abi_test.cpp`

**Interfaces:**
- Consumes: `lmm::processStereoBlock(...)` from `native/dsp_kernel.hpp`.
- Produces: C exports `lmm_dsp_abi_version`, `lmm_dsp_max_channels`, and `lmm_dsp_process_stereo` with the approved fixed struct layout/status codes.

- [ ] **Step 1: Write the ABI unit test first**

The test must assert constants/layout before behavior:

```cpp
static_assert(sizeof(LmmDspChannelConfigAbi) == 20);
static_assert(sizeof(LmmDspChannelMeterAbi) == 24);
static_assert(sizeof(LmmDspMasterMeterAbi) == 12);

require(lmm_dsp_abi_version() == 1u, "ABI version mismatch");
require(lmm_dsp_max_channels() == 8u, "max channel count mismatch");
```

Add cases for null required pointers, channel count `9`, nominal one-channel processing, mute/solo mapping, and meter/result copying.

- [ ] **Step 2: Verify RED**

Run:

```bash
c++ -std=c++17 -O2 -I native native/tests/dsp_wasm_abi_test.cpp native/dsp_wasm_abi.cpp -o /tmp/lmm-dsp-abi-test
```

Expected: compile FAIL because `native/dsp_wasm_abi.h/.cpp` do not exist.

- [ ] **Step 3: Create the exact ABI header**

`native/dsp_wasm_abi.h` must contain the approved layout verbatim:

```cpp
#pragma once
#include <cstdint>

#define LMM_DSP_ABI_VERSION 1u
#define LMM_DSP_MAX_CHANNELS 8u

struct LmmDspChannelConfigAbi {
  std::uint32_t active;
  std::uint32_t muted;
  std::uint32_t solo;
  float linear_trim;
  float fader;
};

struct LmmDspChannelMeterAbi {
  std::uint32_t processed;
  float peak_left;
  float peak_right;
  float rms_left;
  float rms_right;
  std::uint32_t clipping;
};

struct LmmDspMasterMeterAbi {
  float peak_left;
  float peak_right;
  std::uint32_t limiter_active;
};

enum LmmDspStatus : std::int32_t {
  LMM_DSP_OK = 0,
  LMM_DSP_INVALID_ARGUMENT = 1,
  LMM_DSP_CHANNEL_LIMIT_EXCEEDED = 2,
};

extern "C" std::uint32_t lmm_dsp_abi_version();
extern "C" std::uint32_t lmm_dsp_max_channels();
extern "C" std::int32_t lmm_dsp_process_stereo(
    const LmmDspChannelConfigAbi* configs,
    const std::uint32_t* input_ptrs,
    std::uint32_t channel_count,
    std::uint32_t frames,
    float master_gain,
    float* interleaved_output,
    LmmDspChannelMeterAbi* channel_meters,
    LmmDspMasterMeterAbi* master_meter);
```

Add compile-time size assertions in the header or `.cpp`.

- [ ] **Step 4: Implement the heap-free wrapper**

Use fixed stack arrays sized by `LMM_DSP_MAX_CHANNELS`:

```cpp
std::array<lmm::DspChannelConfig, LMM_DSP_MAX_CHANNELS> native_configs{};
std::array<const float*, LMM_DSP_MAX_CHANNELS> native_inputs{};
std::array<lmm::DspChannelMeter, LMM_DSP_MAX_CHANNELS> native_meters{};
```

For wasm32, interpret each `input_ptrs[i]` as a byte offset into linear memory:

```cpp
const auto base = reinterpret_cast<std::uintptr_t>(0);
native_inputs[i] = configs[i].active == 0 || input_ptrs[i] == 0
    ? nullptr
    : reinterpret_cast<const float*>(base + input_ptrs[i]);
```

For native unit tests, isolate pointer conversion behind a small inline helper guarded by `#ifdef __EMSCRIPTEN__`; native tests may pass host pointers through a dedicated test-only call path in the `.cpp`, not by weakening the public wasm32 ABI.

- [ ] **Step 5: Verify GREEN**

Run:

```bash
c++ -std=c++17 -O2 -I native native/tests/dsp_wasm_abi_test.cpp native/dsp_wasm_abi.cpp -o /tmp/lmm-dsp-abi-test
/tmp/lmm-dsp-abi-test
c++ -std=c++17 -O2 -I native native/tests/dsp_parity_vectors_test.cpp -o /tmp/lmm-dsp-parity
/tmp/lmm-dsp-parity test/fixtures/dsp_parity_vectors.tsv
```

Expected: ABI test PASS and existing canonical native parity remains PASS.

- [ ] **Step 6: Commit**

```bash
git add native/dsp_wasm_abi.h native/dsp_wasm_abi.cpp native/tests/dsp_wasm_abi_test.cpp
git commit -m "feat(native): expose canonical DSP ABI v1"
```

---

### Task 3: Build raw Wasm deterministically and make native/Dart/Wasm parity green

**Files:**
- Create: `tool/build_dsp_wasm.sh`
- Create: `test/helpers/dsp_wasm_harness.mjs`
- Modify: `test/web_dsp_wasm_build_contract_test.mjs`
- Modify: `test/web_dsp_wasm_parity_test.mjs`
- Modify: `.gitignore`

**Interfaces:**
- Consumes: ABI v1 C exports and canonical TSV fixture.
- Produces: generated `web/audio/livemixmaster-dsp.wasm`, checksum file `build/dsp-wasm/livemixmaster-dsp.wasm.sha256`, and Node test harness.

- [ ] **Step 1: Change the build contract from expected-missing to expected-present**

Remove the temporary `assert.rejects(fs.access(...))` RED assertion. Require an actual module, exact exports, no imported filesystem/network helpers, and fixed memory behavior.

- [ ] **Step 2: Verify RED because build tooling is still absent**

Run:

```bash
node --test test/web_dsp_wasm_build_contract_test.mjs test/web_dsp_wasm_parity_test.mjs
```

Expected: FAIL because `web/audio/livemixmaster-dsp.wasm` and harness are missing.

- [ ] **Step 3: Implement the pinned build script**

`tool/build_dsp_wasm.sh` follows the existing Chromaprint script style:

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXPECTED_EMSCRIPTEN_VERSION="6.0.9"
OUTPUT_DIR="$ROOT_DIR/build/dsp-wasm"
WEB_OUTPUT="$ROOT_DIR/web/audio/livemixmaster-dsp.wasm"

EMSCRIPTEN_VERSION="$(emcc --version | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
[[ "$EMSCRIPTEN_VERSION" == "$EXPECTED_EMSCRIPTEN_VERSION" ]] || {
  echo "expected Emscripten $EXPECTED_EMSCRIPTEN_VERSION, got ${EMSCRIPTEN_VERSION:-unknown}" >&2
  exit 2
}

mkdir -p "$OUTPUT_DIR"
em++ -O3 -std=c++17 -I"$ROOT_DIR/native" \
  "$ROOT_DIR/native/dsp_wasm_abi.cpp" \
  -sSTANDALONE_WASM=1 \
  -sALLOW_MEMORY_GROWTH=0 \
  -sFILESYSTEM=0 \
  -sUSE_PTHREADS=0 \
  -sEXPORTED_FUNCTIONS='["_lmm_dsp_abi_version","_lmm_dsp_max_channels","_lmm_dsp_process_stereo","_malloc","_free"]' \
  -Wl,--no-entry \
  -o "$OUTPUT_DIR/livemixmaster-dsp.wasm"

cp "$OUTPUT_DIR/livemixmaster-dsp.wasm" "$WEB_OUTPUT"
sha256sum "$WEB_OUTPUT" > "$OUTPUT_DIR/livemixmaster-dsp.wasm.sha256"
```

If Emscripten requires one additional runtime import/export for standalone allocation, add only that symbol and assert it explicitly in the build contract; do not introduce generated JS arithmetic glue.

- [ ] **Step 4: Ignore generated DSP Wasm bytes**

Append exactly:

```gitignore
web/audio/livemixmaster-dsp.wasm
```

- [ ] **Step 5: Implement the Node Wasm harness**

`test/helpers/dsp_wasm_harness.mjs` must:

1. read/compile/instantiate the generated module;
2. verify ABI version/max channels;
3. use exported `_malloc/_free` only during test initialization;
4. write exact ABI structs with `DataView(..., true)` little-endian access;
5. write interleaved float input blocks;
6. create/write the wasm32 input-pointer table;
7. call `lmm_dsp_process_stereo`;
8. read output/channel meters/master meter;
9. free test allocations after the vector completes.

Expose:

```js
export async function createDspWasmHarness();
export async function runWasmVector(vector);
```

- [ ] **Step 6: Verify three-way parity GREEN**

Run:

```bash
docker run --rm -v "$PWD:/src" -w /src emscripten/emsdk:6.0.9 bash tool/build_dsp_wasm.sh
node --test test/web_dsp_wasm_build_contract_test.mjs test/web_dsp_wasm_parity_test.mjs
c++ -std=c++17 -O2 -I native native/tests/dsp_parity_vectors_test.cpp -o /tmp/lmm-dsp-parity
/tmp/lmm-dsp-parity test/fixtures/dsp_parity_vectors.tsv
flutter test test/web_dsp_kernel_test.dart
```

Expected: all PASS with tolerance `1.0e-6`.

- [ ] **Step 7: Commit**

```bash
git add .gitignore tool/build_dsp_wasm.sh test/helpers/dsp_wasm_harness.mjs test/web_dsp_wasm_build_contract_test.mjs test/web_dsp_wasm_parity_test.mjs
git commit -m "feat(web): build canonical DSP Wasm module"
```

---

### Task 4: Add browser-host preload/compile and a fail-closed `dspInit`/`dspReady` handshake

**Files:**
- Modify: `lib/audio/web/browser_audio_worklet_gateway_web.dart`
- Modify: `test/web_audio_graph_integration_test.mjs`
- Modify: `test/web_release_compile_boundary_test.dart`
- Modify: `test/web_audio_worklet_processor_test.mjs`

**Interfaces:**
- Consumes: fixed same-origin `audio/livemixmaster-dsp.wasm`, ABI version 1.
- Produces: exactly one startup message `{type:'dspInit', abiVersion:1, module:<compiled module>}` and exactly one success reply `{type:'dspReady'}` before source/worklet/destination connection/resume.

- [ ] **Step 1: Write graph-order RED tests**

Extend the source/integration tests to require this order:

```text
fetch/compile Wasm
addModule(worklet)
create AudioWorkletNode
postMessage(dspInit)
receive dspReady
connect source -> worklet -> destination
resume AudioContext
```

Assert the asset URL is literal `audio/livemixmaster-dsp.wasm` and is not derived from user/session input.

- [ ] **Step 2: Add worklet handshake RED tests**

In `test/web_audio_worklet_processor_test.mjs`, require:

- no `dspReady` before `dspInit`;
- valid compiled module yields `dspReady`;
- ABI version mismatch yields `dspError` with code `VERSION_MISMATCH`;
- initialization failure yields `dspError` with code `INITIALIZATION_FAILED`;
- `process()` before ready returns `true` but outputs silence and does not claim telemetry parity.

- [ ] **Step 3: Verify RED**

Run:

```bash
node --test test/web_audio_graph_integration_test.mjs test/web_audio_worklet_processor_test.mjs
flutter test test/web_release_compile_boundary_test.dart
```

Expected: FAIL only on missing Wasm preload/handshake behavior.

- [ ] **Step 4: Implement host fetch/compile in the Dart Web gateway**

Inside `start(...)`, before `audioWorklet.addModule`, use a fixed `web.Request`/`web.window.fetch` path and `WebAssembly.compile` through JS interop. Add a startup timeout constant:

```dart
const Duration _dspHandshakeTimeout = Duration(seconds: 2);
const String _dspAssetPath = 'audio/livemixmaster-dsp.wasm';
const int _dspAbiVersion = 1;
```

Map failures to exactly:

```text
DSP MODULE UNAVAILABLE — AUDIO ENGINE NOT READY
DSP MODULE VERSION MISMATCH — AUDIO ENGINE NOT READY
DSP MODULE INITIALIZATION FAILED — AUDIO ENGINE NOT READY
```

Do not include raw exception text in operator-facing state.

- [ ] **Step 5: Implement worklet initialization state**

Add worklet fields initialized in the constructor:

```js
this.dspReady = false;
this.dsp = null;
this.dspBuffers = null;
```

Handle `dspInit` outside `process()`, instantiate the supplied module, validate ABI `1` and max channels `8`, allocate all steady-state Wasm/control buffers once, then post `{type:'dspReady'}`.

- [ ] **Step 6: Verify GREEN without switching mixer arithmetic yet**

Keep current JS DSP arithmetic temporarily behind the migration gate after readiness so this task proves startup only.

Run the same tests from Step 3. Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/audio/web/browser_audio_worklet_gateway_web.dart web/audio/livemixmaster-worklet.js test/web_audio_graph_integration_test.mjs test/web_audio_worklet_processor_test.mjs test/web_release_compile_boundary_test.dart
git commit -m "feat(web): gate audio graph on canonical DSP module readiness"
```

---

### Task 5: Preallocate steady-state buffers and move AudioWorklet arithmetic to Wasm

**Files:**
- Modify: `web/audio/livemixmaster-worklet.js`
- Create: `test/web_dsp_worklet_allocation_contract_test.mjs`
- Modify: `test/web_audio_worklet_processor_test.mjs`
- Modify: `test/web_recorder_pipeline_integration_test.mjs`
- Modify: `test/web_fingerprint_worker_test.mjs` only if its post-master source assertion needs the new fixture setup.

**Interfaces:**
- Consumes: initialized Wasm instance/memory and current `configure`, recording, analysis, telemetry messages.
- Produces: canonical Wasm output plus unchanged outward telemetry/recording/analysis message schemas.

- [ ] **Step 1: Write RED allocation/cutover source contract**

Parse only the text of `process(inputs, outputs)` and reject these production patterns after cutover:

```js
for (const forbidden of [
  'new Float32Array(',
  '.push(',
  'Math.max(',
  'Math.min(',
  'linearTrim *',
  'fader * config.fader',
  'LIMITER_CEILING',
]) {
  assert.equal(processSource.includes(forbidden), false, `duplicate/allocation pattern in process(): ${forbidden}`);
}
```

Also assert `processSource` contains `lmm_dsp_process_stereo` (or the exact exported function binding name) and does not contain `fetch(`, storage APIs, logging, or Wasm instantiation.

- [ ] **Step 2: Add runtime RED cases**

Require initialized Wasm to handle:

- 128-frame stereo input;
- mono input mirrored to stereo;
- missing channel input -> unprocessed/zero meter;
- 129-frame output quantum -> deterministic `dspError` / safe engine-not-ready transition with no OOB write;
- recording PCM equals canonical post-master Wasm output;
- analysis PCM equals canonical post-master Wasm output;
- telemetry ACK still limits one outstanding telemetry message;
- recorder and analysis outstanding counters remain bounded.

- [ ] **Step 3: Verify RED**

Run:

```bash
node --test test/web_dsp_worklet_allocation_contract_test.mjs test/web_audio_worklet_processor_test.mjs test/web_recorder_pipeline_integration_test.mjs
```

Expected: FAIL because `process()` still owns JS arithmetic and allocates PCM/meter arrays.

- [ ] **Step 4: Preallocate Wasm regions during `dspInit`**

Allocate once for:

```text
8 × channel config structs
8 × 128 × 2 Float32 input samples
8 × wasm32 input pointers
128 × 2 Float32 output samples
8 × channel meter structs
1 × master meter struct
```

Cache typed views and exported process function. With `ALLOW_MEMORY_GROWTH=0`, assert `memory.buffer` identity remains stable after readiness.

- [ ] **Step 5: Precreate JS control/message state outside `process()`**

On `configure`, create fixed telemetry entry objects for each configured channel. During `dspInit`, create reusable `Float32Array(256)` recording and analysis scratch buffers and reusable message envelopes.

Do not transfer these arrays; preserve current structured-clone behavior so they can be reused on the next eligible render quantum.

- [ ] **Step 6: Replace production JS mixer arithmetic**

Within `process()`:

1. validate ready + frame count <= 128;
2. copy browser input buses to preallocated Wasm input buffers, mirroring mono right from left;
3. write ABI configs/pointer table;
4. call canonical Wasm process;
5. copy interleaved Wasm output to browser left/right outputs;
6. read meter structs into precreated telemetry entries;
7. copy post-master Wasm output into reusable recording/analysis scratch only when their bounded gates permit sending.

No extra gain/clamp pass is allowed.

- [ ] **Step 7: Verify GREEN**

Run:

```bash
node --test test/web_dsp_worklet_allocation_contract_test.mjs test/web_audio_worklet_processor_test.mjs test/web_recorder_pipeline_integration_test.mjs test/web_wav_recorder_worker_test.mjs test/web_fingerprint_worker_test.mjs
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add web/audio/livemixmaster-worklet.js test/web_dsp_worklet_allocation_contract_test.mjs test/web_audio_worklet_processor_test.mjs test/web_recorder_pipeline_integration_test.mjs test/web_fingerprint_worker_test.mjs
git commit -m "feat(web): run production mixer DSP through canonical Wasm"
```

---

### Task 6: Remove the migration fallback and prove the full Web operator/controller contracts

**Files:**
- Modify: `web/audio/livemixmaster-worklet.js`
- Modify: `lib/audio/web/browser_audio_worklet_gateway_web.dart`
- Modify: `test/browser_audio_processing_controller_test.dart`
- Modify: `test/browser_mixer_controller_test.dart`
- Modify: `test/browser_recording_controller_test.dart`
- Modify: `test/web_recording_operator_gateway_test.mjs`
- Modify: `test/web_recorder_failure_cleanup_test.mjs`

**Interfaces:**
- Consumes: Wasm-only production path from Task 5.
- Produces: no silent JS DSP fallback in release behavior; safe unavailable state on module/runtime failure.

- [ ] **Step 1: Write a RED fallback-removal assertion**

The worklet source contract must reject any release branch such as:

```js
if (!this.dspReady) {
  return this.processWithJavaScriptDsp(...);
}
```

and require safe silence/error behavior instead.

- [ ] **Step 2: Add controller failure-state tests**

Exercise gateway/controller mapping for module unavailable, ABI mismatch, init failure, and render-quantum failure. Assert recording cannot start when DSP is unavailable and no fingerprint/analysis path claims readiness.

- [ ] **Step 3: Verify RED if fallback or unsanitized errors remain**

Run:

```bash
flutter test test/browser_audio_processing_controller_test.dart test/browser_mixer_controller_test.dart test/browser_recording_controller_test.dart
node --test test/web_recording_operator_gateway_test.mjs test/web_recorder_failure_cleanup_test.mjs test/web_dsp_worklet_allocation_contract_test.mjs
```

- [ ] **Step 4: Remove migration-only production fallback**

Delete duplicate release arithmetic and any flag that would permit it in production. Test-only reference arithmetic may live only in test helpers, never in `web/audio/livemixmaster-worklet.js`.

- [ ] **Step 5: Verify the focused Web suite GREEN**

Run:

```bash
flutter test test/web_release_compile_boundary_test.dart test/browser_capture_controller_test.dart test/browser_media_gateway_test.dart test/web_dsp_kernel_test.dart test/browser_audio_processing_controller_test.dart test/browser_mixer_controller_test.dart test/browser_recording_controller_test.dart
node --test test/web_audio_worklet_processor_test.mjs test/web_audio_graph_integration_test.mjs test/web_wav_recorder_worker_test.mjs test/web_recorder_failure_cleanup_test.mjs test/web_recorder_export_test.mjs test/web_recording_operator_gateway_test.mjs test/web_recorder_finalize_test.mjs test/web_recorder_pipeline_integration_test.mjs
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add web/audio/livemixmaster-worklet.js lib/audio/web/browser_audio_worklet_gateway_web.dart test/browser_audio_processing_controller_test.dart test/browser_mixer_controller_test.dart test/browser_recording_controller_test.dart test/web_recording_operator_gateway_test.mjs test/web_recorder_failure_cleanup_test.mjs
git commit -m "refactor(web): fail closed on canonical DSP availability"
```

---

### Task 7: Integrate DSP Wasm into the release artifact and CI provenance chain

**Files:**
- Modify: `.github/workflows/ci.yml`
- Modify: `test/browser/operator.spec.mjs`
- Modify: `test/web_pwa_offline_accessibility_contract_test.mjs` only if offline caching must include the DSP asset.

**Interfaces:**
- Consumes: build script + all focused green tests.
- Produces: `build/web/audio/livemixmaster-dsp.wasm`, SHA-256 evidence, exact-artifact browser use, unchanged Vercel no-rebuild promotion.

- [ ] **Step 1: Add a CI-source RED contract if workflow ordering is not otherwise testable**

Require `.github/workflows/ci.yml` to build DSP Wasm before `Verify AudioWorklet processor contract` and before `flutter build web --release`.

- [ ] **Step 2: Modify `web-release-compile` ordering**

After native parity and before worklet tests, add:

```yaml
- name: Build canonical DSP Wasm
  run: docker run --rm -v "$PWD:/src" -w /src emscripten/emsdk:6.0.9 bash tool/build_dsp_wasm.sh

- name: Verify canonical DSP Wasm build contract
  run: node --test test/web_dsp_wasm_build_contract_test.mjs test/web_dsp_wasm_parity_test.mjs
```

Keep the existing Chromaprint build separately; do not merge the two Wasm toolchains or outputs.

- [ ] **Step 3: Verify packaged asset after Flutter build**

Extend `Verify built PWA offline shell` with:

```bash
test -s build/web/audio/livemixmaster-dsp.wasm
sha256sum web/audio/livemixmaster-dsp.wasm build/web/audio/livemixmaster-dsp.wasm
cmp -s web/audio/livemixmaster-dsp.wasm build/web/audio/livemixmaster-dsp.wasm
sha256sum build/web/audio/livemixmaster-dsp.wasm > test-results-dsp-wasm.sha256
```

The source and packaged digest lines must identify equal bytes; use `cmp` as the authoritative equality check.

- [ ] **Step 4: Make exact-artifact Playwright prove the packaged Wasm is exercised**

In `test/browser/operator.spec.mjs`, attach a response listener before starting browser audio:

```js
const dspResponses = [];
page.on('response', (response) => {
  if (new URL(response.url()).pathname.endsWith('/audio/livemixmaster-dsp.wasm')) {
    dspResponses.push({ status: response.status(), url: response.url() });
  }
});
```

After capture/mixer startup:

```js
expect(dspResponses.some(({ status }) => status === 200)).toBe(true);
```

Keep all existing capture, fader/mute/solo, >=10 s recording/export, disconnect/reconnect, session persistence/correction/export assertions.

- [ ] **Step 5: Run the local release-equivalent checks**

Run:

```bash
docker run --rm -v "$PWD:/src" -w /src emscripten/emsdk:6.0.9 bash tool/build_dsp_wasm.sh
node --test test/web_dsp_wasm_build_contract_test.mjs test/web_dsp_wasm_parity_test.mjs test/web_audio_worklet_processor_test.mjs test/web_audio_graph_integration_test.mjs
flutter test test/web_release_compile_boundary_test.dart test/browser_audio_processing_controller_test.dart test/browser_mixer_controller_test.dart test/browser_recording_controller_test.dart
flutter build web --release
test -s build/web/audio/livemixmaster-dsp.wasm
cmp -s web/audio/livemixmaster-dsp.wasm build/web/audio/livemixmaster-dsp.wasm
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add .github/workflows/ci.yml test/browser/operator.spec.mjs test/web_pwa_offline_accessibility_contract_test.mjs
git commit -m "ci(web): verify canonical DSP Wasm exact artifact"
```

---

### Task 8: Full verification, preview promotion, review, and merge readiness

**Files:**
- Modify documentation/evidence only if implementation changed any documented contract:
  - `docs/superpowers/specs/2026-09-12-shared-dsp-wasm-design.md`
  - `docs/superpowers/plans/2026-09-12-shared-dsp-wasm.md`
- Update GitHub Issue #16 and the Notion delivery tracker with non-secret evidence.

**Interfaces:**
- Consumes: one exact feature-head SHA containing Tasks 1–7.
- Produces: reviewable PR evidence, exact Web artifact ID/digest, Wasm checksum, macOS CI result, preview deployment ID/URL, and explicit remaining non-goals.

- [ ] **Step 1: Run focused verification before claiming completion**

```bash
c++ -std=c++17 -O2 -I native native/tests/dsp_wasm_abi_test.cpp native/dsp_wasm_abi.cpp -o /tmp/lmm-dsp-abi-test
/tmp/lmm-dsp-abi-test
c++ -std=c++17 -O2 -I native native/tests/dsp_parity_vectors_test.cpp -o /tmp/lmm-dsp-parity
/tmp/lmm-dsp-parity test/fixtures/dsp_parity_vectors.tsv
docker run --rm -v "$PWD:/src" -w /src emscripten/emsdk:6.0.9 bash tool/build_dsp_wasm.sh
node --test test/web_dsp_wasm_build_contract_test.mjs test/web_dsp_wasm_parity_test.mjs test/web_dsp_worklet_allocation_contract_test.mjs test/web_audio_worklet_processor_test.mjs test/web_audio_graph_integration_test.mjs
flutter test test/web_dsp_kernel_test.dart test/web_release_compile_boundary_test.dart test/browser_audio_processing_controller_test.dart test/browser_mixer_controller_test.dart test/browser_recording_controller_test.dart
flutter analyze --no-fatal-warnings --no-fatal-infos
flutter build web --release
```

Expected: all PASS; generated Wasm source/package bytes match.

- [ ] **Step 2: Push the feature branch and require GitHub CI on that exact head**

Do not reuse older CI evidence. Required green jobs include at minimum:

```text
Web Release Compile Contract
Web Browser E2E — Exact Artifact
Flutter Analyze
Native Engine Build (macos-latest)
macOS Desktop CI
existing mixer/session/recording/fingerprint contracts
```

- [ ] **Step 3: Record non-secret artifact evidence**

Capture from GitHub Actions:

```text
feature head SHA
live-mix-master-web artifact ID
GitHub artifact digest
build/web/audio/livemixmaster-dsp.wasm SHA-256
Emscripten version 6.0.9
browser E2E evidence artifact ID/digest
```

Do not record PCM, device labels beyond synthetic fixtures, provider secrets, raw Wasm memory, or local filesystem paths.

- [ ] **Step 4: Promote the exact accepted head to `preview`**

Move `preview` only after all feature-head checks are green. Verify the independent push workflow builds/tests the preview SHA, then confirm the Vercel Preview deployment is `READY` and its Git metadata matches the same SHA.

- [ ] **Step 5: Review before merge**

Check:

```text
no duplicate production JS mixer arithmetic
no generated Wasm binary accidentally committed
no workflow regression to exact-artifact digest/provenance logic
no LUFS/dBTP/native-loopback claim added
no unresolved review thread
preview exact-artifact deployment READY
```

- [ ] **Step 6: Merge only after explicit user approval**

Use the repository's merge-commit convention where appropriate and pin the expected PR head SHA.

- [ ] **Step 7: Verify post-merge production promotion**

The `main` merge commit must independently pass the same build/exact-artifact browser E2E, then the existing promotion workflow must deploy that exact tested artifact to Vercel Production without rebuilding Flutter.

- [ ] **Step 8: Update evidence trackers**

Update GitHub Issue #16 and `LiveMixMaster — Implementation Plan & Delivery Tracker` with exact non-secret values and retain these unresolved boundaries:

```text
physical macOS/BlackHole E2E still separate
LUFS/dBTP still unsupported unless independently implemented/verified
browser arbitrary native loopback parity still not claimed
Issue #34 repository-admin protection remains separate until readback proves it
```

- [ ] **Step 9: Final commit for documentation-only evidence changes if required**

```bash
git add docs/superpowers/specs/2026-09-12-shared-dsp-wasm-design.md docs/superpowers/plans/2026-09-12-shared-dsp-wasm.md
git commit -m "docs: record shared DSP Wasm acceptance evidence"
```

---

## Self-Review Checklist

- Spec coverage: every approved requirement maps to Tasks 1–8: canonical C++, ABI v1, Emscripten pin, fixed memory, host compile, handshake, no steady-state allocation, parity, release packaging, exact-artifact E2E, macOS CI, preview/production evidence, and non-goals.
- Placeholder scan: no `TBD`, `TODO`, “similar to”, or unspecified “add tests/error handling” steps remain.
- Type consistency: ABI names/field sizes/status codes and `dspInit`/`dspReady` vocabulary match the approved spec; Web asset path is consistently `audio/livemixmaster-dsp.wasm`; max channels is consistently `8`; quantum is consistently `128`.
- Build policy: generated DSP Wasm is not committed; it is produced before Flutter Web packaging and byte-compared with the packaged artifact.
- TDD ordering: every production behavior task has a failing-test step and explicit RED verification before implementation.
- Release safety: no task bypasses the existing exact-artifact browser E2E or Vercel no-rebuild promotion workflow.

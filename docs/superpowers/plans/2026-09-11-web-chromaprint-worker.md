# Web Chromaprint Worker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an official Chromaprint v1.6.1 WebAssembly fingerprint-preparation path in a Dedicated Worker and connect it to the existing Web fingerprint provider proxy without blocking the AudioWorklet or exposing credentials.

**Architecture:** A reproducible Emscripten build compiles official Chromaprint to Wasm behind a minimal C++ ABI. A Dedicated Worker receives bounded post-master PCM, converts Float32 to PCM16, invokes the Wasm module, and returns only `{fingerprint,durationSeconds}`. A browser-only Dart gateway forwards that prepared fingerprint into the existing `BrowserFingerprintLookupController`; provider traffic remains server-side.

**Tech Stack:** Flutter/Dart 3, package:web, JavaScript Dedicated Worker, WebAssembly, Chromaprint v1.6.1, Emscripten 6.0.9, CMake/KissFFT, Node test runner, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-11-web-chromaprint-worker-design.md`

## Global Constraints

- Chromaprint source is pinned to `v1.6.1` with SHA-256 `3368805af0ee47b9df74df10b5001a44569e01df2844dab520031720dde9ad23`.
- Emscripten is pinned to `6.0.9`; no `latest` tag in CI/build scripts.
- Fingerprint preparation runs only outside the AudioWorklet.
- No AcoustID/broadcast credential may appear in browser assets.
- No unbounded PCM queue or full-session analysis buffering.
- Official `fpcalc` parity is required; non-empty fingerprint tests are not sufficient.
- Existing server-side `/api/fingerprint-lookup` contract remains authoritative for provider lookup.
- W4 changes must preserve W3 DSP/recording contracts and same-head macOS launch-smoke evidence.

---

### Task 1: Establish RED parity and provenance contract

**Files:**
- Create: `test/web_chromaprint_wasm_parity_test.mjs`
- Create: `test/fixtures/chromaprint-fixture-generator.mjs`
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: no new production interface.
- Produces: a CI contract that expects `build/chromaprint-wasm/livemixmaster-chromaprint.mjs`, its `.wasm`, a version API, and `fingerprintPcm16(...)`.

- [ ] **Step 1: Write the failing parity test**

Generate deterministic 12-second stereo PCM16 at 48 kHz from several fixed sine components plus deterministic amplitude modulation. Write a WAV fixture under `build/chromaprint-fixture/reference.wav` during the test. The test imports the generated Wasm JS module, asserts its reported version is `1.6.1`, sends the exact PCM16 buffer through `fingerprintPcm16`, invokes official `fpcalc` 1.6.1 against the same WAV, and asserts strict fingerprint-string equality.

- [ ] **Step 2: Add the CI step before existing fingerprint proxy tests**

Run:
```bash
node --test test/web_chromaprint_wasm_parity_test.mjs
```

Expected RED: module/build script is absent; the failure must identify the missing Wasm fingerprint build, not an unrelated syntax error.

- [ ] **Step 3: Commit the RED contract**

Commit message:
```text
test(web): require official Chromaprint Wasm parity
```

---

### Task 2: Build official Chromaprint v1.6.1 to Wasm reproducibly

**Files:**
- Create: `tool/build_chromaprint_wasm.sh`
- Create: `web/fingerprint/chromaprint/lmm_chromaprint_wrapper.cpp`
- Create: `docs/contracts/web-chromaprint-provenance.md`
- Modify: `.gitignore`
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: signed interleaved PCM16, sample count, sample rate, channel count.
- Produces: generated module `build/chromaprint-wasm/livemixmaster-chromaprint.mjs` and `build/chromaprint-wasm/livemixmaster-chromaprint.wasm` with JS helper exports `chromaprintVersion()` and `fingerprintPcm16(pcm, sampleRate, channels)`.

- [ ] **Step 1: Add the checksum-pinned build script**

The script must:
```bash
CHROMAPRINT_VERSION=1.6.1
CHROMAPRINT_SHA256=3368805af0ee47b9df74df10b5001a44569e01df2844dab520031720dde9ad23
EMSCRIPTEN_VERSION=6.0.9
```

Download `chromaprint-1.6.1.tar.gz` only when absent, run `sha256sum --check`, extract to `build/vendor/chromaprint-1.6.1`, configure using Emscripten/CMake with `-DFFT_LIB=kissfft -DBUILD_SHARED_LIBS=OFF -DBUILD_TOOLS=OFF -DBUILD_TESTS=OFF`, then compile the wrapper and static Chromaprint library into an ES module + Wasm artifact. CI runs the script inside the pinned `emscripten/emsdk:6.0.9` image.

- [ ] **Step 2: Implement the minimal C++ wrapper**

The wrapper must call only public Chromaprint APIs:
```cpp
chromaprint_new(CHROMAPRINT_ALGORITHM_DEFAULT);
chromaprint_start(ctx, sample_rate, channels);
chromaprint_feed(ctx, pcm, sample_count);
chromaprint_finish(ctx);
chromaprint_get_fingerprint(ctx, &fingerprint);
chromaprint_dealloc(fingerprint);
chromaprint_free(ctx);
```

Return failure for invalid pointers/count/rate/channel values and free all native allocations on every exit path.

- [ ] **Step 3: Verify GREEN parity**

Run build + parity test. Expected: version `1.6.1`; Wasm encoded fingerprint exactly equals official fpcalc v1.6.1 output for the deterministic WAV.

- [ ] **Step 4: Record provenance**

Document release URL/tag, source SHA-256, Emscripten version, build flags, generated filenames, and the LGPL-2.1 review gate. Do not make a legal-compliance claim.

- [ ] **Step 5: Commit**

Commit message:
```text
feat(web): build official Chromaprint Wasm module
```

---

### Task 3: Add bounded Dedicated Worker fingerprint preparation

**Files:**
- Create: `web/fingerprint/livemixmaster-fingerprint-worker.js`
- Create: `test/web_fingerprint_worker_test.mjs`
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes Worker messages:
```js
{type: 'init', moduleUrl, wasmUrl}
{type: 'pcm', requestId, samples: Float32Array, frames, sampleRate, channels}
{type: 'flush', requestId}
{type: 'dispose'}
```
- Produces:
```js
{type: 'ready'}
{type: 'pcmAck', requestId}
{type: 'fingerprint', requestId, fingerprint, durationSeconds}
{type: 'fingerprintError', requestId, failureCode}
```

- [ ] **Step 1: Write Worker RED tests**

Test deterministic Float32->PCM16 conversion, 10-second bounded rolling window, maximum one in-flight calculation, ACK behavior, short-window rejection, and absence of direct `fetch`, XHR, WebSocket, IndexedDB/localStorage, or DOM references.

- [ ] **Step 2: Verify RED**

Run:
```bash
node --test test/web_fingerprint_worker_test.mjs
```
Expected: missing Worker implementation.

- [ ] **Step 3: Implement the Worker**

Conversion contract:
```js
if (!Number.isFinite(sample)) sample = 0;
sample = Math.max(-1, Math.min(1, sample));
pcm16 = Math.round(sample < 0 ? sample * 32768 : sample * 32767);
```

Keep no more than 10 seconds of stereo Float32 input plus the PCM16 conversion buffer for one calculation. Skip new analysis triggers while busy rather than queueing them. Load only fixed same-origin module paths supplied by the trusted Dart gateway.

- [ ] **Step 4: Verify GREEN**

Run Worker tests plus the Wasm parity test. Both must pass.

- [ ] **Step 5: Commit**

Commit message:
```text
feat(web): add bounded Chromaprint fingerprint worker
```

---

### Task 4: Connect Worker preparation to the existing Flutter lookup controller

**Files:**
- Create: `lib/services/web/browser_fingerprint_preparation_controller.dart`
- Create: `lib/services/web/browser_fingerprint_preparation_gateway.dart`
- Create: `lib/services/web/browser_fingerprint_preparation_gateway_stub.dart`
- Create: `lib/services/web/browser_fingerprint_preparation_gateway_web.dart`
- Create: `test/browser_fingerprint_preparation_controller_test.dart`
- Create: `test/web_fingerprint_preparation_gateway_contract_test.dart`
- Modify: `lib/audio/web/browser_audio_worklet_gateway_web.dart`
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Produces Dart model:
```dart
class PreparedBrowserFingerprint {
  final String fingerprint;
  final int durationSeconds;
}
```
- Controller exposes deterministic statuses `idle`, `collecting`, `preparing`, `prepared`, `tooShort`, `failed` and listeners matching the existing Web controller pattern.
- Gateway method:
```dart
Future<PreparedBrowserFingerprint> prepare({
  required List<double> interleavedSamples,
  required int sampleRate,
  int channels = 2,
});
```

- [ ] **Step 1: Write RED Dart tests**

Test state transitions, sanitized timeout/failure messages, prepared result forwarding, and no provider knowledge/credentials in the preparation controller.

- [ ] **Step 2: Verify RED**

Run:
```bash
flutter test test/browser_fingerprint_preparation_controller_test.dart test/web_fingerprint_preparation_gateway_contract_test.dart
```
Expected: missing preparation classes/gateway.

- [ ] **Step 3: Implement conditional gateway**

VM stub returns an explicit unsupported failure. Web implementation creates `fingerprint/livemixmaster-fingerprint-worker.js`, waits for `ready`, uses request IDs/completers with bounded timeout, maps `fingerprint` and `fingerprintError`, and terminates on dispose.

- [ ] **Step 4: Add a bounded analysis tap to the existing Worklet gateway**

Reuse the already-created post-master PCM messages. Forward a bounded copy to the fingerprint preparation gateway independently from the recorder ACK path. Never make fingerprint progress a prerequisite for `pcmAck`, recording, or audio graph operation.

- [ ] **Step 5: Forward prepared fingerprints to the existing lookup controller**

On `prepared`, call:
```dart
lookupPreparedFingerprint(
  fingerprint: result.fingerprint,
  durationSeconds: result.durationSeconds,
);
```
Do not duplicate provider status logic.

- [ ] **Step 6: Verify GREEN**

Run preparation tests, existing fingerprint proxy/operator tests, Web audio state contracts, and `flutter analyze`.

- [ ] **Step 7: Commit**

Commit message:
```text
feat(web): connect Chromaprint worker to fingerprint lookup
```

---

### Task 5: Package assets and produce exact-SHA release evidence

**Files:**
- Modify: `tool/build_chromaprint_wasm.sh`
- Modify: `.github/workflows/ci.yml`
- Modify: `docs/superpowers/specs/2026-09-11-web-chromaprint-worker-design.md` only if implementation evidence exposes a specification correction.

**Interfaces:**
- Produces final static assets under `web/fingerprint/vendor/` before `flutter build web --release`, copied from the checksum-verified build output.

- [ ] **Step 1: Package generated artifacts**

The build script copies only the generated `.mjs` and `.wasm` files into `web/fingerprint/vendor/` during CI/local build preparation. Generated files remain ignored in Git; `flutter build web --release` must copy them to `build/web/fingerprint/vendor/`.

- [ ] **Step 2: Add client-bundle secret/static safety checks**

After Flutter build, fail if browser assets contain known secret variable names/credential material or if the fingerprint Worker contains prohibited direct network/storage APIs.

- [ ] **Step 3: Run full exact-head CI**

Required green gates on one SHA:
```text
Flutter Analyze
Design Contract Test
Golden Fixture Contract
Reliability Models Test
Broadcast Pipeline Test
Mixer User Flow Test
Web Release Compile Contract
Native Engine Build
macOS Desktop CI through launch smoke
```

- [ ] **Step 4: Capture artifacts**

Record Web artifact ID/digest and macOS launch-evidence artifact ID/digest. Do not record secrets, provider keys, PCM content, or private endpoint configuration.

- [ ] **Step 5: Synchronize project tracking**

Update PR #20, Issue #16, and Notion page `LiveMixMaster — Web/PWA Release Plan — 2026-09-10` with the exact verified head and evidence. Keep PR #20 Draft until the remaining W4 persistence/recovery slice and stack/integration ordering are resolved.

- [ ] **Step 6: Preserve Vercel W5 gate**

Verify the existing Vercel production deployment is unchanged. Do not promote this W4 artifact to production.

- [ ] **Step 7: Commit documentation-only evidence changes if required**

Commit message:
```text
docs(web): record Chromaprint worker verification
```

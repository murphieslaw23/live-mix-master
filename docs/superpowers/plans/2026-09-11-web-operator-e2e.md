# LiveMixMaster Web Operator Bridge + Browser E2E Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the remaining W5 Web/PWA blocker by exposing the existing AudioWorklet mixer controls and telemetry to Flutter Web, adding browser-safe session recovery/export, validating the complete operator path in real browsers, and preserving exact tested-artifact provenance through Vercel promotion.

**Architecture:** Keep the current DSP, recording Worker, capture lifecycle, fingerprint proxy, PWA service worker, and desktop file store. Add a typed Dart mixer protocol/controller around the existing Worklet `configure`/`telemetry` messages, introduce a storage interface that preserves the current `List<TracklistEntry>` persistence shape, provide a Web `localStorage` adapter plus download adapter, and wire these into the Web release shell. Browser acceptance runs against the already-built `build/web` artifact; it must never rebuild the app in the E2E job.

**Tech Stack:** Flutter 3.47.2, Dart 3.5+, `package:web` JS interop, Web Audio/AudioWorklet, browser `localStorage`, existing WAV Worker, Node.js test runner, Playwright, GitHub Actions, Vercel exact-artifact promotion.

**Spec:** `docs/superpowers/specs/2026-09-11-web-operator-e2e-design.md`

## Global Constraints

- Base implementation from `2cc6335ebc66825ed552994842dbe87fd422e0d4`; design/plan branch starts from that commit.
- Do not rewrite `web/audio/livemixmaster-worklet.js` DSP behavior unless a failing contract test proves the existing protocol itself is defective.
- Do not alter the existing PWA service-worker ownership model: `lmm-service-worker.js` remains the sole application service worker.
- Do not add a test-only production build mode such as `LMM_E2E_TEST_MODE`.
- Do not require live fingerprint-provider credentials in browser E2E.
- Browser session storage contains only non-secret tracklist/correction state; no audio blobs, credentials, tokens, or provider secrets.
- Browser E2E must consume the exact artifact built by `web-release-compile`; a second `flutter build web` in the browser job is forbidden.
- Existing desktop `SessionTracklistStore` atomic file/backup behavior remains unchanged behind an interface.
- Exact-artifact promotion remains gated by artifact ID, SHA-256 digest, exact commit SHA, and successful CI on that commit.
- Commit author/committer identity must remain `Murphies Law <emilach82@gmail.com>`.
- Implementation uses RED -> GREEN -> refactor; run the smallest relevant test first, then the affected suite.
- Type-level refinement from the approved design: `BrowserChannelMeter` mirrors the actual Worklet payload (`peakLeft`, `peakRight`, `rmsLeft`, `rmsRight`, `clipping`) rather than collapsing stereo telemetry to one peak/RMS value.
- Persistence-interface refinement from the approved design: preserve the existing entry-list shape (`Future<List<TracklistEntry>> load()` / `Future<void> save(Iterable<TracklistEntry>)`) so desktop storage is adapted rather than rewritten.

---

## File Structure

### New Dart files

- `lib/audio/web/browser_mixer_controller.dart` — platform-neutral mixer configuration, telemetry types, gateway contract, controller state/actions.
- `lib/audio/web/browser_mixer_protocol.dart` — pure-Dart serialization/parsing helpers for Worklet messages so protocol tests run on the VM.
- `lib/services/session_tracklist_repository.dart` — platform-neutral persistence contract used by `SessionTracklistPersister`.
- `lib/services/web/browser_session_tracklist_repository.dart` — `localStorage` implementation using the existing `SessionTracklistCodec` payload.
- `lib/services/web/browser_tracklist_download_gateway.dart` — Blob/object-URL download adapter for JSON/CSV/M3U.
- `lib/services/web/browser_session_controller.dart` — active local session recovery, correction, persistence warning state, and export orchestration.

### New tests

- `test/browser_mixer_controller_test.dart`
- `test/browser_mixer_protocol_test.dart`
- `test/browser_session_controller_test.dart`
- `test/browser_session_tracklist_repository_contract_test.dart` — source/compile contract for the Web adapter plus pure codec tests; browser behavior itself is proven in Playwright.
- `test/web_release_shell_operator_test.dart`
- `test/web_operator_e2e.spec.mjs`
- `test/web_browser_capability_matrix.spec.mjs`
- `test/fixtures/web-fake-mic.wav`
- `test/fixtures/generate-web-fake-mic.mjs`
- `tool/web-e2e-server.mjs`
- `package.json` / `package-lock.json` — only Playwright test dependency and scripts required for browser acceptance.

### Existing files to modify

- `lib/audio/web/browser_audio_worklet_gateway_web.dart` — implement mixer gateway, parse telemetry, preserve ACK and recording behavior.
- `lib/audio/web/browser_audio_processing_controller.dart` — coordinate mixer attach/detach after processing start/stop without changing capture semantics.
- `lib/audio/web/browser_capture_runtime_web.dart` — expose one shared runtime containing capture, processing, mixer, and recording controllers backed by the same Worklet gateway.
- `lib/audio/web/browser_capture_runtime_stub.dart` — keep non-Web compile boundary compatible with the expanded runtime shape.
- `lib/services/session_tracklist_store.dart` — implement repository interface; retain `dart:io` behavior.
- `lib/services/session_tracklist_persister.dart` — depend on repository interface instead of concrete file store.
- `lib/services/live_session_tracklist_controller.dart` — no behavior rewrite; compile against repository-backed persister and expose the same correction/accept flow.
- `lib/app/app_surface_web.dart` — add compact mixer panel, recovered session panel, correction/export controls, and stable semantics.
- `test/browser_audio_processing_controller_test.dart` — prove source-ended teardown also detaches mixer.
- `test/session_tracklist_persister_test.dart` — use fake repository for abstraction behavior while retaining file-store tests separately.
- `test/live_session_tracklist_controller_test.dart` — verify corrections schedule repository persistence.
- `test/web_audio_worklet_processor_test.mjs` — lock existing configure/telemetry schema.
- `test/web_release_compile_boundary_test.dart` — prove Web compile graph does not import `dart:io` storage implementation through shared code.
- `.github/workflows/ci.yml` — make browser E2E download and consume the `web-release-compile` artifact; add browser matrix evidence.
- `docs/release/tested-web-artifact-promotion.md` — record the browser-gate prerequisite before preview promotion.

---

### Task 1: Add the pure Dart mixer protocol and controller

**Files:**
- Create: `lib/audio/web/browser_mixer_protocol.dart`
- Create: `lib/audio/web/browser_mixer_controller.dart`
- Create: `test/browser_mixer_protocol_test.dart`
- Create: `test/browser_mixer_controller_test.dart`

**Interfaces:**
- Produces `BrowserMixerGateway`, `BrowserMixerConfiguration`, `BrowserMixerChannelConfiguration`, `BrowserMixerTelemetry`, `BrowserChannelMeter`, `BrowserMixerState`, `BrowserMixerController`.
- `BrowserMixerGateway.telemetry` is `Stream<BrowserMixerTelemetry>`.
- `BrowserMixerGateway.configure(...)` accepts one `BrowserMixerConfiguration`.
- `BrowserMixerController.attach(String channelId)` enables controls and sends neutral configuration; `detach()` disables controls and clears live meters.

- [ ] **Step 1: Write failing protocol tests for the exact Worklet schema**

```dart
test('configuration serializes the existing Worklet configure schema', () {
  const configuration = BrowserMixerConfiguration(
    masterGainLinear: 1,
    telemetryEvery: 20,
    channels: [BrowserMixerChannelConfiguration(
      id: 'mic-1', linearTrim: 1, fader: .5, muted: true, solo: false,
    )],
  );
  expect(configuration.toMessage(), {
    'type': 'configure',
    'masterGainLinear': 1.0,
    'telemetryEvery': 20,
    'channels': [{
      'id': 'mic-1', 'linearTrim': 1.0, 'fader': .5,
      'muted': true, 'solo': false,
    }],
  });
});

test('telemetry preserves stereo peak RMS and clipping fields', () {
  final telemetry = BrowserMixerTelemetry.tryParse({
    'type': 'telemetry',
    'channelMeters': [{
      'channelId': 'mic-1', 'peakLeft': .4, 'peakRight': .5,
      'rmsLeft': .2, 'rmsRight': .25, 'clipping': false,
    }],
    'masterPeakLeft': .4,
    'masterPeakRight': .5,
    'limiterActive': false,
  });
  expect(telemetry!.channelMeters['mic-1']!.peakRight, .5);
});
```

- [ ] **Step 2: Run the protocol tests and confirm RED**

Run: `flutter test test/browser_mixer_protocol_test.dart`

Expected: FAIL because mixer protocol types do not exist.

- [ ] **Step 3: Implement immutable protocol types and strict `tryParse` validation**

Reject telemetry if the root type is not `telemetry`, `channelMeters` is not a list, a channel lacks a non-empty `channelId`, any numeric field is non-finite/non-numeric, or `limiterActive`/`clipping` are not booleans. Return `null` instead of throwing on malformed browser messages.

- [ ] **Step 4: Write failing controller tests for attach, fader, mute, solo, telemetry, and detach**

```dart
await controller.attach('mic-1');
expect(gateway.configurations.single.channels.single.fader, 1.0);
await controller.setFader(.6);
await controller.setMuted(true);
await controller.setSolo(true);
gateway.emit(const BrowserMixerTelemetry(/* mic-1 stereo meter values */));
expect(controller.state.enabled, isTrue);
expect(controller.state.fader, .6);
expect(controller.state.muted, isTrue);
expect(controller.state.solo, isTrue);
await controller.detach();
expect(controller.state.enabled, isFalse);
```

- [ ] **Step 5: Run controller tests and confirm RED**

Run: `flutter test test/browser_mixer_controller_test.dart`

Expected: FAIL because `BrowserMixerController` does not exist.

- [ ] **Step 6: Implement the minimal controller**

Use neutral defaults exactly: `linearTrim=1`, `fader=1`, `muted=false`, `solo=false`, `masterGainLinear=1`, `telemetryEvery=20`. Clamp fader to `0..1`. Keep one telemetry subscription for the controller lifetime; ignore meters for other channel IDs. Configuration sends must be serialized through a single future chain so rapid slider changes cannot reorder Worklet commands.

- [ ] **Step 7: Run both new test files GREEN**

Run: `flutter test test/browser_mixer_protocol_test.dart test/browser_mixer_controller_test.dart`

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add lib/audio/web/browser_mixer_protocol.dart lib/audio/web/browser_mixer_controller.dart test/browser_mixer_protocol_test.dart test/browser_mixer_controller_test.dart
git commit -m "feat(web): add typed mixer control protocol"
```

---

### Task 2: Bridge Worklet configure/telemetry through the shared Web runtime

**Files:**
- Modify: `lib/audio/web/browser_audio_worklet_gateway_web.dart`
- Modify: `lib/audio/web/browser_audio_processing_controller.dart`
- Modify: `lib/audio/web/browser_capture_runtime_web.dart`
- Modify: `lib/audio/web/browser_capture_runtime_stub.dart`
- Modify: `test/browser_audio_processing_controller_test.dart`
- Modify: `test/web_audio_worklet_processor_test.mjs`

**Interfaces:**
- Consumes Task 1 `BrowserMixerGateway` and `BrowserMixerController`.
- Produces `BrowserWebRuntime.mixerController` and `BrowserWebRuntime.processingController` using the same `WebAudioWorkletGateway` instance as recording.

- [ ] **Step 1: Extend the Node Worklet contract test before Dart gateway changes**

Assert a `configure` message with `id/fader/muted/solo` changes processor state and emitted telemetry contains `channelId`, stereo peak/RMS, `clipping`, master L/R peak, and `limiterActive`.

Run: `node --test test/web_audio_worklet_processor_test.mjs`

Expected: PASS against current Worklet. This is a characterization test, not a reason to edit DSP code.

- [ ] **Step 2: Add RED coordinator tests for mixer attach/detach**

After `capture.requestMicrophone()` + `coordinator.synchronize()`, assert `mixer.state.enabled == true` and `activeChannelId == 'mic-1'`. After `endActiveTrack()` + synchronize, assert processing is idle and mixer is disabled.

Run: `flutter test test/browser_audio_processing_controller_test.dart`

Expected: FAIL because coordinator does not own mixer lifecycle.

- [ ] **Step 3: Implement `BrowserMixerGateway` in `WebAudioWorkletGateway`**

Add a broadcast `StreamController<BrowserMixerTelemetry>`. On Worklet `telemetry`, dartify the message, parse with `BrowserMixerTelemetry.tryParse`, add valid telemetry to the stream, then send the existing `telemetryAck`. `configure()` must fail with a sanitized not-ready error when `_workletNode` is null and otherwise post `configuration.toMessage().jsify()`.

- [ ] **Step 4: Wire runtime and coordinator**

Construct one `WebAudioWorkletGateway`, then one processing controller, mixer controller, and recording controller from it. Extend `BrowserAudioRuntimeCoordinator` with `BrowserMixerController mixerController`; after successful processing start call `mixer.attach(source.id)`, and after stop/failure call `mixer.detach()`.

- [ ] **Step 5: Run focused GREEN tests**

Run: `flutter test test/browser_audio_processing_controller_test.dart test/browser_mixer_controller_test.dart`

Expected: PASS.

- [ ] **Step 6: Run existing recording/Worklet regression contracts**

Run: `node --test test/web_audio_worklet_processor_test.mjs test/web_recording_operator_gateway_test.mjs test/web_recorder_pipeline_integration_test.mjs && flutter test test/browser_recording_controller_test.dart`

Expected: PASS with no recording regressions.

- [ ] **Step 7: Commit**

```bash
git add lib/audio/web/browser_audio_worklet_gateway_web.dart lib/audio/web/browser_audio_processing_controller.dart lib/audio/web/browser_capture_runtime_web.dart lib/audio/web/browser_capture_runtime_stub.dart test/browser_audio_processing_controller_test.dart test/web_audio_worklet_processor_test.mjs
git commit -m "feat(web): bridge mixer controls and telemetry"
```

---

### Task 3: Introduce a platform-neutral session repository without changing desktop persistence

**Files:**
- Create: `lib/services/session_tracklist_repository.dart`
- Modify: `lib/services/session_tracklist_store.dart`
- Modify: `lib/services/session_tracklist_persister.dart`
- Modify: `test/session_tracklist_store_test.dart`
- Modify: `test/session_tracklist_persister_test.dart`
- Modify: `test/live_session_tracklist_controller_test.dart`

**Interfaces:**

```dart
abstract interface class SessionTracklistRepository {
  Stream<ServiceStatus> get onStatus;
  Future<List<TracklistEntry>> load();
  Future<void> save(Iterable<TracklistEntry> entries);
  Future<void> dispose();
}
```

- [ ] **Step 1: Rewrite persister tests to use a fake repository and confirm RED**

The fake records `save()` snapshots and exposes a broadcast status stream. Assert rapid schedules persist only the latest snapshot and `flush()` writes immediately.

Run: `flutter test test/session_tracklist_persister_test.dart`

Expected: FAIL until `SessionTracklistPersister.store` accepts `SessionTracklistRepository`.

- [ ] **Step 2: Add the repository interface and make `SessionTracklistStore implements SessionTracklistRepository`**

Do not alter temporary-file, backup, malformed-file recovery, or status behavior in `SessionTracklistStore`.

- [ ] **Step 3: Change `SessionTracklistPersister` constructor/field to the interface**

No debounce semantics change.

- [ ] **Step 4: Run persistence and live-session tests GREEN**

Run: `flutter test test/session_tracklist_store_test.dart test/session_tracklist_persister_test.dart test/live_session_tracklist_controller_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/session_tracklist_repository.dart lib/services/session_tracklist_store.dart lib/services/session_tracklist_persister.dart test/session_tracklist_store_test.dart test/session_tracklist_persister_test.dart test/live_session_tracklist_controller_test.dart
git commit -m "refactor(session): isolate persistence repository"
```

---

### Task 4: Add Web session recovery, correction, and export adapters

**Files:**
- Create: `lib/services/web/browser_session_tracklist_repository.dart`
- Create: `lib/services/web/browser_tracklist_download_gateway.dart`
- Create: `lib/services/web/browser_session_controller.dart`
- Create: `test/browser_session_controller_test.dart`
- Create: `test/browser_session_tracklist_repository_contract_test.dart`
- Modify: `test/web_release_compile_boundary_test.dart`

**Interfaces:**
- `BrowserSessionTracklistRepository(storageKey: 'lmm.session.active')` implements `SessionTracklistRepository` with `SessionTracklistCodec` JSON.
- `BrowserTracklistDownloadGateway.download({required String fileName, required String mimeType, required String contents})` creates Blob -> object URL -> anchor click -> revoke.
- `BrowserSessionController.initialize()` loads entries; `correct(...)` delegates to `LiveSessionTracklistController`; `exportJson/Csv/M3u()` delegates to existing `TracklistExporter` plus download gateway.

- [ ] **Step 1: Add RED pure controller tests with fake repository/download gateway**

Seed repository with one synthetic entry, initialize, correct its title, flush, then assert the saved snapshot contains the corrected title. Export JSON and assert the fake download receives a `.json` filename and exporter output containing the corrected title.

Run: `flutter test test/browser_session_controller_test.dart`

Expected: FAIL because controller/adapters do not exist.

- [ ] **Step 2: Implement `BrowserSessionController` without Web APIs**

Keep Web APIs outside this file so unit tests remain VM-safe. Generate a stable session ID only when no recovered entries exist; recovered entries keep their stored `sessionId`.

- [ ] **Step 3: Implement the `localStorage` repository**

Use the existing `SessionTracklistCodec` document (`schemaVersion: 1`, `entries`). Namespace the one active document at `lmm.session.active`. `load()` returns `[]` for absent storage, emits malformed-response status and throws `FormatException` for invalid data, and emits write-failed status for browser storage exceptions.

- [ ] **Step 4: Implement Blob download adapter**

Always revoke the object URL in `finally` after `anchor.click()`. Use MIME types `application/json`, `text/csv;charset=utf-8`, and `audio/x-mpegurl`.

- [ ] **Step 5: Strengthen Web compile-boundary test**

Assert shared Web imports reference `session_tracklist_repository.dart` and Web adapter files, while `session_tracklist_store.dart` remains the only session persistence file importing `dart:io`.

Run: `flutter test test/web_release_compile_boundary_test.dart test/browser_session_controller_test.dart test/browser_session_tracklist_repository_contract_test.dart`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/services/web/browser_session_tracklist_repository.dart lib/services/web/browser_tracklist_download_gateway.dart lib/services/web/browser_session_controller.dart test/browser_session_controller_test.dart test/browser_session_tracklist_repository_contract_test.dart test/web_release_compile_boundary_test.dart
git commit -m "feat(web): persist and export local sessions"
```

---

### Task 5: Expose mixer, recovery, correction, and export in the Web operator shell

**Files:**
- Modify: `lib/app/app_surface_web.dart`
- Modify: `lib/audio/web/browser_capture_runtime_web.dart`
- Create: `test/web_release_shell_operator_test.dart`

**Interfaces:**
- `WebReleaseShell` receives injectable `BrowserMixerController? mixerController` and `BrowserSessionController? sessionController` for widget tests.
- Stable semantic labels: `Channel fader`, `Mute`, `Solo`, `Channel peak`, `Channel RMS`, `Master peak`, `Limiter`, `Session tracklist`, `Export session JSON`, `Export session CSV`, `Export session M3U`.

- [ ] **Step 1: Write RED widget tests for disabled and active mixer states**

Pump shell with fake controllers. Assert fader/mute/solo are disabled when mixer is detached. Attach `mic-1`, pump, assert controls enabled, set fader to `.5`, press mute/solo, emit telemetry, and assert rendered meter text changes.

- [ ] **Step 2: Write RED widget tests for recovered session and correction/export**

Seed a fake session with `Artist / Original`, initialize, pump shell, edit title to `Corrected`, submit correction, and assert `Corrected` renders. Tap each export button and assert the fake download gateway records JSON/CSV/M3U requests.

- [ ] **Step 3: Run widget test and confirm RED**

Run: `flutter test test/web_release_shell_operator_test.dart`

Expected: FAIL because the operator/session panels are absent.

- [ ] **Step 4: Implement compact mixer panel**

Place it between capture and recording panels. Use existing `LiveMixTokens`/text styles. Render stereo telemetry as an accessible combined display such as `PEAK L 0.42 / R 0.44` and `RMS L 0.21 / R 0.22`; do not invent a new meter algorithm in Flutter.

- [ ] **Step 5: Implement session panel**

Show recovered entries, artist/title correction fields for the selected entry, non-fatal persistence warning text, and JSON/CSV/M3U export buttons. The panel must remain usable when fingerprint provider status is failed/offline.

- [ ] **Step 6: Preserve source-ended recovery semantics**

When capture enters `reconnectRequired`, processing/mixer disable automatically through the coordinator; session panel remains available. Reconnect must re-enable mixer and send neutral config to the new Worklet.

- [ ] **Step 7: Run widget + lifecycle regression tests GREEN**

Run: `flutter test test/web_release_shell_operator_test.dart test/browser_audio_processing_controller_test.dart test/browser_capture_controller_test.dart test/browser_recording_controller_test.dart`

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add lib/app/app_surface_web.dart lib/audio/web/browser_capture_runtime_web.dart test/web_release_shell_operator_test.dart
git commit -m "feat(web): expose W5 operator controls and session export"
```

---

### Task 6: Add deterministic browser fixtures and Playwright acceptance harness

**Files:**
- Create: `package.json`
- Create: `package-lock.json`
- Create: `test/fixtures/generate-web-fake-mic.mjs`
- Create: `test/fixtures/web-fake-mic.wav`
- Create: `tool/web-e2e-server.mjs`
- Create: `test/web_operator_e2e.spec.mjs`
- Create: `test/web_browser_capability_matrix.spec.mjs`

**Interfaces:**
- NPM scripts: `test:web:e2e` and `test:web:matrix`.
- Static server serves only a supplied artifact directory and returns SPA fallback to `index.html`; it does not rebuild Flutter.
- Chromium fake mic uses repository-owned deterministic WAV.

- [ ] **Step 1: Add deterministic WAV generator**

Generate 16-bit PCM mono, 48 kHz, 440 Hz sine, 15 seconds, amplitude `0.25`. The generator must produce the committed fixture byte-for-byte.

Run: `node test/fixtures/generate-web-fake-mic.mjs && git diff --exit-code test/fixtures/web-fake-mic.wav`

Expected after committing the fixture: no diff.

- [ ] **Step 2: Add Playwright dependency and browser install script**

`package.json` contains only repository metadata, `@playwright/test`, and scripts needed for these two test files. Pin the resolved version in `package-lock.json`.

- [ ] **Step 3: Implement artifact-only static server**

Require `LMM_WEB_ARTIFACT_DIR`; exit non-zero if `index.html` is missing. Bind to `127.0.0.1`, default port `4173`, and serve correct content types for `.js`, `.wasm`, `.json`, `.wav`, `.html`.

- [ ] **Step 4: Write Chromium functional E2E**

Launch Chromium with fake-device flags and `test/fixtures/web-fake-mic.wav`. Flow:
1. open artifact;
2. press `CONNECT MIC / USB`;
3. wait for `CAPTURE ACTIVE` and non-zero Peak/RMS text;
4. set `Channel fader` below unity;
5. toggle `Mute`, verify master peak reaches zero/near-zero while input meter remains valid, restore mute;
6. toggle `Solo` and verify pressed state;
7. start recording, wait at least 10 seconds, stop, download WAV;
8. parse RIFF/WAVE header and compute PCM duration >=10 seconds;
9. stop the active browser capture track through the page's standards-visible `MediaStreamTrack.stop()` path if reachable; otherwise use the production disconnect action from the approved design fallback;
10. verify `RECONNECT REQUIRED`, reconnect, and verify meters recover;
11. pre-seed `lmm.session.active` with one valid synthetic entry before reload, verify recovery, correct it through the production UI, reload, verify correction persists;
12. export JSON and validate corrected content.

The test fails on uncaught page errors and unexpected console `error` messages.

- [ ] **Step 5: Write Firefox/WebKit capability matrix**

For each browser: load shell, assert accessibility semantics/controls render, capability state is explicit, no page error occurs, and offline shell request returns the verified fallback where supported. Record unsupported capture as evidence instead of skipping the browser.

- [ ] **Step 6: Run locally only where browser navigation is permitted**

Run: `npm ci && npx playwright install chromium firefox webkit && LMM_WEB_ARTIFACT_DIR=build/web npm run test:web:e2e && LMM_WEB_ARTIFACT_DIR=build/web npm run test:web:matrix`

Expected: PASS in a normal CI/browser environment. In the current constrained container, `ERR_BLOCKED_BY_ADMINISTRATOR` is environment policy and is not accepted as product evidence.

- [ ] **Step 7: Commit**

```bash
git add package.json package-lock.json test/fixtures/generate-web-fake-mic.mjs test/fixtures/web-fake-mic.wav tool/web-e2e-server.mjs test/web_operator_e2e.spec.mjs test/web_browser_capability_matrix.spec.mjs
git commit -m "test(web): add deterministic browser acceptance"
```

---

### Task 7: Make GitHub Actions test the exact built artifact

**Files:**
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- `web-release-compile` remains the only Flutter Web build producer.
- New `web-browser-e2e` job has `needs: web-release-compile` and downloads artifact `live-mix-master-web` into `build/web`.
- No `flutter build web` command exists in `web-browser-e2e`.

- [ ] **Step 1: Add a failing workflow contract check before editing CI**

Add a shell check in the PR review process:

```bash
python - <<'PY'
from pathlib import Path
text = Path('.github/workflows/ci.yml').read_text()
assert 'web-browser-e2e:' in text
assert 'name: live-mix-master-web' in text
PY
```

Expected initially: FAIL because browser job does not exist.

- [ ] **Step 2: Add `web-browser-e2e` job**

Steps: checkout exact SHA, setup Node, `npm ci`, install Playwright browsers/deps, download `live-mix-master-web` with `actions/download-artifact@v4`, start `tool/web-e2e-server.mjs`, run Chromium functional E2E, run Firefox/WebKit matrix, upload Playwright report/downloaded WAV/browser logs as non-secret artifacts on failure and success where useful.

- [ ] **Step 3: Add same-artifact guard**

Before Playwright, require `build/web/index.html`, `build/web/main.dart.js`, `build/web/lmm-service-worker.js`, and `build/web/offline.html`. Print `sha256sum` for `index.html`, `main.dart.js`, and manifest into the job log for evidence; do not create a replacement release ZIP.

- [ ] **Step 4: Run YAML/source validation**

Run the Python contract above and inspect the job to confirm there is no `flutter build web` under `web-browser-e2e`.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci(web): gate release artifact with browser E2E"
```

---

### Task 8: Run full verification without repeating irrelevant green work

**Files:**
- Modify only if a failing verification requires a scoped fix.

- [ ] **Step 1: Run focused Flutter suites**

```bash
flutter test test/browser_mixer_protocol_test.dart test/browser_mixer_controller_test.dart test/browser_audio_processing_controller_test.dart test/browser_capture_controller_test.dart test/browser_recording_controller_test.dart test/browser_session_controller_test.dart test/session_tracklist_store_test.dart test/session_tracklist_persister_test.dart test/live_session_tracklist_controller_test.dart test/web_release_shell_operator_test.dart test/web_release_compile_boundary_test.dart
```

Expected: PASS.

- [ ] **Step 2: Run affected Node contracts**

```bash
node --test test/web_audio_worklet_processor_test.mjs test/web_audio_graph_integration_test.mjs test/web_recording_operator_gateway_test.mjs test/web_recorder_pipeline_integration_test.mjs test/web_pwa_manifest_contract_test.mjs test/web_pwa_offline_accessibility_contract_test.mjs
```

Expected: PASS.

- [ ] **Step 3: Run analyze and one release build**

```bash
bash tool/bootstrap_fonts.sh
flutter pub get
flutter analyze --no-fatal-warnings --no-fatal-infos
flutter build web --release
```

Expected: PASS. This local build is developer verification only; release evidence still comes from CI's exact artifact.

- [ ] **Step 4: Verify PWA ownership did not regress**

Confirm built `index.html` registers `lmm-service-worker.js`, `offline.html` exists, maskable icons remain valid, and generated Flutter bootstrap does not opt into Flutter service-worker registration.

- [ ] **Step 5: Push branch and wait for PR CI**

Do not manually deploy a local build. Use CI results to prove the exact branch commit and artifact.

---

### Task 9: PR, merge, exact artifact evidence, and Vercel Preview promotion

**Files:**
- Modify: `docs/release/tested-web-artifact-promotion.md`
- Update: GitHub Issue #16 and matching Notion W5 page with non-secret evidence after verification.

- [ ] **Step 1: Update release documentation**

Document that Preview promotion requires: exact merged SHA, successful standard CI including `web-browser-e2e`, artifact name/ID/digest, and browser matrix evidence. Keep the existing `promote-tested-web-artifact.yml` inputs unchanged.

- [ ] **Step 2: Open PR from implementation branch to `main`**

PR summary must distinguish new W5 operator/browser evidence from already-green W1-W4/PWA checks. Do not claim Safari native-device equivalence from Playwright WebKit.

- [ ] **Step 3: Verify PR checks and merge only when green**

Required new evidence: Flutter/Node focused contracts plus `web-browser-e2e`. Existing standard CI and PWA contract must remain green; do not manually rerun unrelated historical workflows.

- [ ] **Step 4: Verify post-merge exact main artifact**

Record merged commit SHA, CI run ID, `live-mix-master-web` artifact ID, GitHub artifact digest/SHA-256, browser E2E job conclusion, and PWA contract conclusion.

- [ ] **Step 5: Promote that exact artifact to Vercel Preview**

Invoke the existing promotion workflow with the exact artifact ID, exact digest, exact 40-character merged SHA, and target `preview`. If connector tooling still cannot dispatch `workflow_dispatch`, use an authorized GitHub UI/CLI execution path rather than bypassing provenance with an ad-hoc Vercel deploy.

- [ ] **Step 6: Validate Preview**

Record Vercel deployment ID/URL and verify boot, capture capability state, operator controls, recording download, session recovery/export, `/api/` behavior, and no service-worker regression. Secrets remain out of notes/logs.

- [ ] **Step 7: Sync trackers**

Mark the W5 browser matrix, Web E2E, and exact tested-artifact Preview gates complete in Issue #16 and the Notion release page only after evidence exists. Leave production promotion open until Preview acceptance is explicit.

---

## Self-Review Results

- **Spec coverage:** typed mixer bridge, telemetry, compact Web UI, source-ended recovery, persistence, correction/export, Chromium functional E2E, Firefox/WebKit matrix, exact-artifact CI, and Vercel Preview gating all have explicit tasks.
- **Already-green preservation:** no task rebuilds the DSP algorithm, fingerprint proxy, recorder Worker, PWA icon/service-worker system, or desktop file-store semantics.
- **No live-provider dependency:** browser session acceptance uses valid synthetic local session data and production correction/export UI; fingerprint credentials are not required.
- **Type consistency:** Worklet telemetry fields are consistently stereo (`peakLeft/Right`, `rmsLeft/Right`, `clipping`) from protocol through controller/UI/tests.
- **Persistence consistency:** repository/persister/store all use `List<TracklistEntry>` snapshots and the current `SessionTracklistCodec` document.
- **Exact artifact:** only `web-release-compile` builds; browser E2E downloads its uploaded artifact and promotion uses its artifact ID/digest.
- **Placeholder scan:** no implementation step depends on TBD/TODO behavior.

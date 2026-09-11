# LiveMixMaster Web Operator Bridge + Browser E2E Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the remaining W5 Web/PWA blocker by exposing the existing AudioWorklet mixer controls and telemetry to Flutter Web, adding browser-safe session recovery/export, validating the complete operator path in real browsers, and preserving exact tested-artifact provenance through Vercel promotion.

**Architecture:** Keep the current DSP, recorder Worker, capture lifecycle, fingerprint proxy, PWA service worker, and desktop file store. Add a typed Dart mixer protocol/controller around the existing Worklet `configure`/`telemetry` messages, introduce a persistence interface that preserves the existing `List<TracklistEntry>` snapshot shape, provide Web `localStorage` and download adapters, and wire these into the Web release shell. GitHub Actions browser acceptance downloads the artifact produced by `web-release-compile`; it never rebuilds Flutter Web.

**Tech Stack:** Flutter 3.47.2, Dart 3.5+, `package:web`, Web Audio/AudioWorklet, browser `localStorage`, existing WAV Worker, Node.js, Playwright, GitHub Actions, Vercel exact-artifact promotion.

**Spec:** `docs/superpowers/specs/2026-09-11-web-operator-e2e-design.md`

## Global Constraints

- Implementation baseline: `2cc6335ebc66825ed552994842dbe87fd422e0d4`.
- Do not rewrite `web/audio/livemixmaster-worklet.js` DSP behavior unless a characterization test proves the current protocol is defective.
- `lmm-service-worker.js` remains the sole application service worker.
- Do not add a test-only production build mode.
- Browser E2E must not require fingerprint-provider credentials.
- Browser storage contains only non-secret tracklist/correction state; no audio blobs or credentials.
- Existing desktop `SessionTracklistStore` atomic temp/backup behavior remains unchanged behind an interface.
- Exact-artifact promotion remains keyed by artifact ID, SHA-256 digest, exact commit SHA, and successful CI.
- Author/committer identity remains `Murphies Law <emilach82@gmail.com>`.
- Use RED -> GREEN -> refactor and commit after each independently testable slice.
- Type refinement: `BrowserChannelMeter` mirrors the actual Worklet fields `peakLeft`, `peakRight`, `rmsLeft`, `rmsRight`, `clipping`.
- Persistence refinement: repository methods preserve the current entry-list shape rather than replacing it with a new session aggregate type.
- Deterministic browser source teardown uses a production-safe `DISCONNECT SOURCE` action that stops the active stream and drives the same `BrowserCaptureController.handleTrackEnded()` recovery transition. The native `MediaStreamTrack.ended` callback remains covered separately by lifecycle tests.

---

## File Map

**Create**
- `lib/audio/web/browser_mixer_protocol.dart` — pure-Dart Worklet message types/parser.
- `lib/audio/web/browser_mixer_controller.dart` — operator state and serialized configure writes.
- `lib/services/session_tracklist_repository.dart` — persistence interface.
- `lib/services/web/browser_session_tracklist_repository.dart` — Web `localStorage` adapter.
- `lib/services/web/browser_tracklist_download_gateway.dart` — Blob/object-URL export adapter.
- `lib/services/web/browser_session_controller.dart` — recovery/correction/export orchestration.
- `test/browser_mixer_protocol_test.dart`
- `test/browser_mixer_controller_test.dart`
- `test/browser_session_controller_test.dart`
- `test/browser_session_tracklist_repository_contract_test.dart`
- `test/web_release_shell_operator_test.dart`
- `test/web_operator_e2e.spec.mjs`
- `test/web_browser_capability_matrix.spec.mjs`
- `test/fixtures/generate-web-fake-mic.mjs`
- `test/fixtures/web-fake-mic.wav`
- `tool/web-e2e-server.mjs`
- `package.json`, `package-lock.json`

**Modify**
- `lib/audio/web/browser_audio_worklet_gateway_web.dart`
- `lib/audio/web/browser_audio_processing_controller.dart`
- `lib/audio/web/browser_capture_controller.dart`
- `lib/audio/web/browser_media_gateway.dart`
- `lib/audio/web/browser_media_client_web.dart`
- `lib/audio/web/browser_capture_runtime_web.dart`
- `lib/audio/web/browser_capture_runtime_stub.dart`
- `lib/services/session_tracklist_store.dart`
- `lib/services/session_tracklist_persister.dart`
- `lib/app/app_surface_web.dart`
- `test/browser_audio_processing_controller_test.dart`
- `test/browser_capture_controller_test.dart`
- `test/session_tracklist_store_test.dart`
- `test/session_tracklist_persister_test.dart`
- `test/live_session_tracklist_controller_test.dart`
- `test/web_audio_worklet_processor_test.mjs`
- `test/web_release_compile_boundary_test.dart`
- `.github/workflows/ci.yml`
- `docs/release/tested-web-artifact-promotion.md`

---

### Task 1: Pure Dart mixer protocol and controller

**Files:** create `lib/audio/web/browser_mixer_protocol.dart`, `lib/audio/web/browser_mixer_controller.dart`, `test/browser_mixer_protocol_test.dart`, `test/browser_mixer_controller_test.dart`.

**Interfaces:**

```dart
abstract interface class BrowserMixerGateway {
  Stream<BrowserMixerTelemetry> get telemetry;
  Future<void> configure(BrowserMixerConfiguration configuration);
}
```

`BrowserMixerController.attach(String channelId)` sends neutral state. `detach()` disables controls and clears live meters. `setFader`, `setMuted`, `setSolo` serialize writes through one future chain.

- [ ] **Step 1: Write RED protocol tests**

```dart
test('configure message matches Worklet schema', () {
  const value = BrowserMixerConfiguration(
    masterGainLinear: 1,
    telemetryEvery: 20,
    channels: [BrowserMixerChannelConfiguration(
      id: 'mic-1', linearTrim: 1, fader: .5, muted: true, solo: false,
    )],
  );
  expect(value.toMessage(), {
    'type': 'configure',
    'masterGainLinear': 1.0,
    'telemetryEvery': 20,
    'channels': [{
      'id': 'mic-1', 'linearTrim': 1.0, 'fader': .5,
      'muted': true, 'solo': false,
    }],
  });
});

test('telemetry preserves stereo fields', () {
  final value = BrowserMixerTelemetry.tryParse({
    'type': 'telemetry',
    'channelMeters': [{
      'channelId': 'mic-1',
      'peakLeft': .4, 'peakRight': .5,
      'rmsLeft': .2, 'rmsRight': .25,
      'clipping': false,
    }],
    'masterPeakLeft': .4,
    'masterPeakRight': .5,
    'limiterActive': false,
  });
  expect(value!.channelMeters['mic-1']!.rmsRight, .25);
});
```

Run: `flutter test test/browser_mixer_protocol_test.dart`

Expected: FAIL because the protocol types are absent.

- [ ] **Step 2: Implement protocol types/parser**

`tryParse` returns `null` for wrong `type`, non-list `channelMeters`, empty `channelId`, non-numeric/non-finite meter values, or non-boolean `clipping`/`limiterActive`.

- [ ] **Step 3: Write RED controller test**

```dart
await controller.attach('mic-1');
await controller.setFader(.6);
await controller.setMuted(true);
await controller.setSolo(true);
gateway.emit(const BrowserMixerTelemetry(
  channelMeters: {
    'mic-1': BrowserChannelMeter(
      peakLeft: .4, peakRight: .5,
      rmsLeft: .2, rmsRight: .25,
      clipping: false,
    ),
  },
  masterPeakLeft: .4,
  masterPeakRight: .5,
  limiterActive: false,
));
expect(controller.state.fader, .6);
expect(controller.state.muted, isTrue);
expect(controller.state.solo, isTrue);
expect(controller.state.channelMeter!.peakRight, .5);
await controller.detach();
expect(controller.state.enabled, isFalse);
```

Run: `flutter test test/browser_mixer_controller_test.dart`

Expected: FAIL because the controller is absent.

- [ ] **Step 4: Implement controller**

Defaults: `linearTrim=1`, `fader=1`, `muted=false`, `solo=false`, `masterGainLinear=1`, `telemetryEvery=20`. Clamp fader to `0..1`; ignore telemetry from other channel IDs.

- [ ] **Step 5: Verify and commit**

Run: `flutter test test/browser_mixer_protocol_test.dart test/browser_mixer_controller_test.dart`

Expected: PASS.

```bash
git add lib/audio/web/browser_mixer_protocol.dart lib/audio/web/browser_mixer_controller.dart test/browser_mixer_protocol_test.dart test/browser_mixer_controller_test.dart
git commit -m "feat(web): add typed mixer control protocol"
```

---

### Task 2: Worklet gateway and shared runtime wiring

**Files:** modify `browser_audio_worklet_gateway_web.dart`, `browser_audio_processing_controller.dart`, `browser_capture_runtime_web.dart`, `browser_capture_runtime_stub.dart`, `test/browser_audio_processing_controller_test.dart`, `test/web_audio_worklet_processor_test.mjs`.

**Consumes:** Task 1 `BrowserMixerGateway` / `BrowserMixerController`.

**Produces:** one `BrowserWebRuntime` whose capture, processing, mixer, and recording controllers share the same `WebAudioWorkletGateway`.

- [ ] **Step 1: Characterize current Worklet contract**

Extend the Node test so a `configure` message changes `id/fader/muted/solo`, and emitted telemetry contains `channelId`, stereo peak/RMS, `clipping`, master L/R peak, `limiterActive`.

Run: `node --test test/web_audio_worklet_processor_test.mjs`

Expected: PASS before Dart gateway edits.

- [ ] **Step 2: Add RED coordinator test**

After microphone capture + `coordinator.synchronize()`, assert mixer enabled with `mic-1`; after lifecycle `endActiveTrack()` + synchronize, assert processing idle and mixer disabled.

Run: `flutter test test/browser_audio_processing_controller_test.dart`

Expected: FAIL because mixer lifecycle is not wired.

- [ ] **Step 3: Implement `BrowserMixerGateway` in `WebAudioWorkletGateway`**

Add a broadcast telemetry controller. On Worklet `telemetry`: `dartify`, parse, publish valid telemetry, then send the existing `telemetryAck`. `configure()` posts `configuration.toMessage().jsify()` and throws a sanitized not-ready state if no Worklet node exists.

- [ ] **Step 4: Wire coordinator/runtime**

After successful processing start call `mixer.attach(source.id)`. After processing stop/failure call `mixer.detach()`. Expose `processingController` and `mixerController` from `BrowserWebRuntime`.

- [ ] **Step 5: Verify recording regressions and commit**

Run:

```bash
flutter test test/browser_audio_processing_controller_test.dart test/browser_mixer_controller_test.dart test/browser_recording_controller_test.dart
node --test test/web_audio_worklet_processor_test.mjs test/web_recording_operator_gateway_test.mjs test/web_recorder_pipeline_integration_test.mjs
```

Expected: PASS.

Commit: `feat(web): bridge mixer controls and telemetry`.

---

### Task 3: Production-safe source disconnect and native-ended convergence

**Files:** modify `browser_capture_controller.dart`, `browser_media_gateway.dart`, `browser_media_client_web.dart`, `browser_capture_runtime_web.dart`, `test/browser_capture_controller_test.dart`, `test/browser_audio_processing_controller_test.dart`.

**Interfaces:**

```dart
abstract interface class BrowserMediaDisconnectGateway {
  void disconnectActiveStream();
}
```

`DefaultBrowserMediaGateway` implements it when its client can stop the active stream. `BrowserCaptureController.disconnect()` stops the stream and then calls the same `handleTrackEnded()` transition used by the native `ended` callback.

- [ ] **Step 1: Add RED controller test**

```dart
await controller.requestMicrophone();
controller.disconnect();
expect(gateway.disconnectCount, 1);
expect(controller.state.status, BrowserCaptureStatus.reconnectRequired);
expect(controller.state.source, isNull);
```

Run: `flutter test test/browser_capture_controller_test.dart`

Expected: FAIL because disconnect is absent.

- [ ] **Step 2: Implement client/gateway disconnect**

Expose a public `disconnectActiveStream()` in `WebBrowserMediaClient` that calls existing `_stopActiveStream()`. Gateway delegates when supported. Controller invokes gateway disconnect and `handleTrackEnded()` exactly once.

- [ ] **Step 3: Prove native and operator teardown converge**

Keep the existing lifecycle fake test for `endActiveTrack()`. Add one coordinator assertion showing both native ended and explicit disconnect leave processing idle and mixer disabled.

Run: `flutter test test/browser_capture_controller_test.dart test/browser_audio_processing_controller_test.dart`

Expected: PASS.

Commit: `feat(web): add deterministic source disconnect recovery`.

---

### Task 4: Platform-neutral session persistence and Web adapters

**Files:** create `session_tracklist_repository.dart`, `browser_session_tracklist_repository.dart`, `browser_tracklist_download_gateway.dart`, `browser_session_controller.dart`; modify store/persister tests and compile-boundary test.

**Repository interface:**

```dart
abstract interface class SessionTracklistRepository {
  Stream<ServiceStatus> get onStatus;
  Future<List<TracklistEntry>> load();
  Future<void> save(Iterable<TracklistEntry> entries);
  Future<void> dispose();
}
```

- [ ] **Step 1: RED persister abstraction test**

Replace direct `SessionTracklistStore` dependency in `test/session_tracklist_persister_test.dart` with a fake repository that records snapshots. Assert debounce writes only the newest entry and `flush()` writes immediately.

Run: `flutter test test/session_tracklist_persister_test.dart`

Expected: FAIL until persister accepts the interface.

- [ ] **Step 2: Add interface and adapt desktop store**

`SessionTracklistStore implements SessionTracklistRepository`; do not change temp-file/backup/recovery behavior. Change `SessionTracklistPersister.store` type only.

Run: `flutter test test/session_tracklist_store_test.dart test/session_tracklist_persister_test.dart test/live_session_tracklist_controller_test.dart`

Expected: PASS.

- [ ] **Step 3: RED browser session controller test**

Seed fake repository with one entry, initialize, correct title, flush, export JSON through a fake download gateway; assert saved/exported title is corrected.

Run: `flutter test test/browser_session_controller_test.dart`

Expected: FAIL because Web session orchestration is absent.

- [ ] **Step 4: Implement Web adapters**

`BrowserSessionTracklistRepository` uses key `lmm.session.active` and existing `SessionTracklistCodec`. Missing key loads `[]`; malformed data emits malformed-response status and throws `FormatException`; storage exceptions emit write-failed status. Download gateway creates Blob -> object URL -> anchor click -> revoke in `finally`. MIME types: JSON `application/json`, CSV `text/csv;charset=utf-8`, M3U `audio/x-mpegurl`.

- [ ] **Step 5: Strengthen compile boundary**

`test/web_release_compile_boundary_test.dart` must prove Web/shared files use the repository interface/Web adapter while `session_tracklist_store.dart` remains the only session persistence implementation importing `dart:io`.

Run:

```bash
flutter test test/browser_session_controller_test.dart test/browser_session_tracklist_repository_contract_test.dart test/web_release_compile_boundary_test.dart test/session_tracklist_store_test.dart test/session_tracklist_persister_test.dart
```

Expected: PASS.

Commit: `feat(web): persist and export local sessions`.

---

### Task 5: Web operator shell UI and semantics

**Files:** modify `lib/app/app_surface_web.dart`, `browser_capture_runtime_web.dart`; create `test/web_release_shell_operator_test.dart`.

**Stable semantics:** `Channel fader`, `Mute`, `Solo`, `Channel peak`, `Channel RMS`, `Master peak`, `Limiter`, `Disconnect source`, `Session tracklist`, `Export session JSON`, `Export session CSV`, `Export session M3U`.

- [ ] **Step 1: RED mixer widget tests**

Pump injected fake controllers. Detached state: fader/mute/solo disabled. Attached state: controls enabled; move fader to `.5`; press mute/solo; emit stereo telemetry; assert rendered peak/RMS text changes.

- [ ] **Step 2: RED session widget tests**

Seed `Artist / Original`, initialize, edit title to `Corrected`, submit correction, assert `Corrected` renders, and assert all three export actions reach fake download gateway.

- [ ] **Step 3: RED disconnect widget test**

With active capture, tap `Disconnect source`; assert capture state text becomes `CAPTURE ENDED / ACCESS REVOKED — RECONNECT REQUIRED` and mixer controls disable while session panel remains visible.

Run: `flutter test test/web_release_shell_operator_test.dart`

Expected: FAIL because panels/actions are absent.

- [ ] **Step 4: Implement compact mixer/session panels**

Use current `LiveMixTokens`/styles. Render `PEAK L 0.42 / R 0.44` and `RMS L 0.21 / R 0.22`; Flutter displays telemetry only and does not calculate replacement DSP meters. Mute/solo expose pressed state; slider exposes value semantics; controls disable unless mixer is attached.

- [ ] **Step 5: Implement disconnect button and reconnect behavior**

Button calls `BrowserCaptureController.disconnect()`. Reconnect through existing capture action must recreate Worklet processing, reattach mixer, and send neutral configuration.

- [ ] **Step 6: Verify**

Run:

```bash
flutter test test/web_release_shell_operator_test.dart test/browser_capture_controller_test.dart test/browser_audio_processing_controller_test.dart test/browser_recording_controller_test.dart
```

Expected: PASS.

Commit: `feat(web): expose W5 operator controls and session export`.

---

### Task 6: Deterministic Playwright acceptance

**Files:** create `package.json`, lockfile, fixture generator/WAV, static server, Chromium E2E, Firefox/WebKit matrix.

- [ ] **Step 1: Generate deterministic fake microphone WAV**

Generator output: PCM16 mono, 48,000 Hz, 440 Hz sine, 15 seconds, amplitude `0.25`.

Run: `node test/fixtures/generate-web-fake-mic.mjs && git diff --exit-code test/fixtures/web-fake-mic.wav`

Expected after fixture commit: no diff.

- [ ] **Step 2: Add Playwright dependency/scripts**

`package.json` adds only `@playwright/test` and scripts `test:web:e2e`, `test:web:matrix`; lock exact resolution in `package-lock.json`.

- [ ] **Step 3: Add artifact-only server**

Require `LMM_WEB_ARTIFACT_DIR`, fail if `index.html` is absent, bind `127.0.0.1:4173`, serve `.html/.js/.wasm/.json/.wav` correctly, and use `index.html` for SPA fallback. It must contain no build command.

- [ ] **Step 4: Chromium functional E2E**

Launch with fake-device flags and `web-fake-mic.wav`. Execute exact visible path:
1. `CONNECT MIC / USB`;
2. assert `CAPTURE ACTIVE`;
3. wait for non-zero Peak/RMS;
4. set `Channel fader` below unity;
5. mute and assert master output reaches zero/near-zero, then unmute;
6. toggle solo and assert pressed state;
7. record for >=10 seconds;
8. stop/download WAV and validate RIFF/WAVE header + PCM duration >=10 seconds;
9. press `Disconnect source` and assert `RECONNECT REQUIRED`;
10. reconnect and assert telemetry resumes;
11. seed valid `lmm.session.active` data with one synthetic entry before reload;
12. correct entry through production UI, reload, assert correction persists;
13. export JSON and validate corrected content.

Fail on uncaught page errors or unexpected console errors.

- [ ] **Step 5: Firefox/WebKit capability matrix**

For each browser: boot exact artifact, verify semantics/controls, explicit capability state, no page error, and offline fallback where supported. Unsupported capture is recorded as a capability result, not skipped or reported as parity.

- [ ] **Step 6: Browser verification command**

```bash
npm ci
npx playwright install chromium firefox webkit
LMM_WEB_ARTIFACT_DIR=build/web npm run test:web:e2e
LMM_WEB_ARTIFACT_DIR=build/web npm run test:web:matrix
```

Expected: PASS on a normal browser runner. Current-container `ERR_BLOCKED_BY_ADMINISTRATOR` is environment policy and is not product evidence.

Commit: `test(web): add deterministic browser acceptance`.

---

### Task 7: GitHub Actions exact-artifact browser gate

**File:** modify `.github/workflows/ci.yml`.

**Invariant:** `web-release-compile` is the only Flutter Web build producer. `web-browser-e2e` has `needs: web-release-compile`, downloads `live-mix-master-web` into `build/web`, and contains no `flutter build web` command.

- [ ] **Step 1: RED workflow source contract**

```bash
python - <<'PY'
from pathlib import Path
text = Path('.github/workflows/ci.yml').read_text()
assert 'web-browser-e2e:' in text
assert 'needs: web-release-compile' in text
assert 'actions/download-artifact@v4' in text
PY
```

Expected: FAIL before job is added.

- [ ] **Step 2: Add browser job**

Steps: checkout exact SHA, setup Node, `npm ci`, install Playwright browser dependencies, download artifact name `live-mix-master-web`, assert `build/web/index.html`, `main.dart.js`, `lmm-service-worker.js`, `offline.html`, print SHA-256 for index/main/manifest, run both Playwright scripts, upload report/WAV/browser logs as non-secret evidence.

- [ ] **Step 3: Validate source and commit**

Run the Python contract and inspect the `web-browser-e2e` block to confirm no Flutter build command appears.

Commit: `ci(web): gate release artifact with browser E2E`.

---

### Task 8: Verification, PR, merge, exact artifact, Preview promotion

**Files:** update `docs/release/tested-web-artifact-promotion.md`; then update Issue #16 + matching Notion W5 page only with verified evidence.

- [ ] **Step 1: Focused Flutter verification**

```bash
flutter test test/browser_mixer_protocol_test.dart test/browser_mixer_controller_test.dart test/browser_audio_processing_controller_test.dart test/browser_capture_controller_test.dart test/browser_recording_controller_test.dart test/browser_session_controller_test.dart test/session_tracklist_store_test.dart test/session_tracklist_persister_test.dart test/live_session_tracklist_controller_test.dart test/web_release_shell_operator_test.dart test/web_release_compile_boundary_test.dart
```

Expected: PASS.

- [ ] **Step 2: Affected Node/PWA regression verification**

```bash
node --test test/web_audio_worklet_processor_test.mjs test/web_audio_graph_integration_test.mjs test/web_recording_operator_gateway_test.mjs test/web_recorder_pipeline_integration_test.mjs test/web_pwa_manifest_contract_test.mjs test/web_pwa_offline_accessibility_contract_test.mjs
```

Expected: PASS.

- [ ] **Step 3: Analyze + one developer release build**

```bash
bash tool/bootstrap_fonts.sh
flutter pub get
flutter analyze --no-fatal-warnings --no-fatal-infos
flutter build web --release
```

Expected: PASS. This local output is never promoted.

- [ ] **Step 4: Verify PWA ownership unchanged**

Built `index.html` references `lmm-service-worker.js`; `offline.html` and maskable icons exist; generated Flutter bootstrap does not opt into Flutter service-worker registration.

- [ ] **Step 5: Update release doc and open PR**

Document the new prerequisite: successful exact-artifact browser E2E + browser matrix. PR description distinguishes new W5 evidence from already-green W1-W4/PWA checks and does not claim native Safari capture parity from Playwright WebKit.

- [ ] **Step 6: Merge only after required checks are green**

After merge, record exact main SHA, CI run ID, browser E2E job conclusion, PWA contract conclusion, `live-mix-master-web` artifact ID, and artifact digest.

- [ ] **Step 7: Promote exact artifact to Vercel Preview**

Invoke existing `promote-tested-web-artifact.yml` with exact artifact ID, exact digest, exact merged SHA, target `preview`. If the connector still cannot dispatch `workflow_dispatch`, use an authorized GitHub UI/CLI route; do not replace this with ad-hoc `vercel deploy`.

- [ ] **Step 8: Preview acceptance and tracker sync**

Record Vercel deployment ID/URL and verify boot, capability state, operator controls, recording download, session recovery/export, `/api/` behavior, and service-worker ownership. Then mark W5 browser matrix, E2E, and exact tested-artifact Preview gates complete in Issue #16 and Notion. Leave production promotion open until Preview acceptance is explicit.

---

## Self-Review Results

- Spec coverage: mixer bridge, telemetry, UI, source-ended recovery, browser persistence/export, Chromium functional E2E, Firefox/WebKit matrix, exact-artifact CI, and Vercel Preview promotion all map to concrete tasks.
- Placeholder scan: no TBD/TODO/example placeholders remain in executable test snippets.
- Type consistency: telemetry fields stay stereo from Worklet -> parser -> controller -> UI -> E2E.
- Lifecycle consistency: native track-ended and explicit disconnect converge on `handleTrackEnded()`; E2E uses the explicit production action deterministically.
- Persistence consistency: repository/persister/store use `List<TracklistEntry>` and existing `SessionTracklistCodec`.
- Exact-artifact consistency: browser job downloads the sole Web artifact and never rebuilds it.

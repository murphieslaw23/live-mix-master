# LiveMixMaster Web Operator Bridge + Browser E2E Design

Date: 2026-09-11
Status: Proposed for implementation after explicit review approval
Scope: W5 Web/PWA release blocker
Base commit: `2cc6335ebc66825ed552994842dbe87fd422e0d4`

## 1. Problem statement

The current Web shell can connect browser capture sources, record WAV output, and perform fingerprint lookup, but it does not expose the complete operator path required by the W5 release acceptance gate. In particular, the browser UI has no operator controls for channel fader, mute, solo, or live metering, and Web session persistence/export is not yet wired through a browser-safe storage boundary.

The DSP implementation already contains the required mixer behavior. `web/audio/livemixmaster-worklet.js` accepts `configure` messages containing per-channel fader/mute/solo state and emits `telemetry` messages containing channel peak/RMS plus master peak/limiter state. The blocker is therefore not a DSP rewrite; it is the missing Dart runtime bridge, presentation state, browser persistence adapter, and end-to-end acceptance harness.

This design adds the smallest operator bridge needed to satisfy W5 without expanding into a desktop/Web mixer rewrite.

## 2. Goals

1. Expose the existing AudioWorklet mixer configuration channel to Dart without changing the DSP algorithm.
2. Expose worklet telemetry to Dart as a typed stream suitable for live meters and test assertions.
3. Add a compact Web-only operator control surface for one active browser capture channel:
   - fader
   - mute
   - solo
   - peak/RMS meters
   - master peak/limiter state
4. Add a platform-neutral session persistence boundary and a browser implementation backed by same-origin browser storage.
5. Reuse the existing `TracklistExporter` for browser CSV/JSON/M3U export.
6. Add deterministic browser E2E that validates the complete W5 operator flow on the exact built Web artifact.
7. Keep the already-green W1-W4 and PWA/offline/accessibility behavior unchanged unless a change is required by this operator bridge.
8. Preserve exact-artifact provenance so the artifact validated by CI is the artifact promoted through the existing Vercel promotion workflow.

## 3. Non-goals

- Rebuild the full desktop mixer UI for Web.
- Introduce a new DSP implementation, limiter, mixer engine, or metering algorithm.
- Add multiple simultaneous browser input channels in this slice.
- Replace the existing recording worker or WAV encoder.
- Replace the fingerprint provider/proxy architecture.
- Replace the existing exact-artifact Vercel promotion workflow.
- Add a second service worker or alter the already-verified PWA service-worker ownership model.
- Make browser persistence authoritative for secrets, credentials, or remote account state.

## 4. Existing baseline to preserve

At the W5 base commit:

- `BrowserCaptureController` owns browser microphone/display capture state.
- `BrowserRecordingController` owns browser recording lifecycle and WAV export.
- `BrowserFingerprintLookupController` owns browser fingerprint lookup state.
- `BrowserAudioRuntimeCoordinator` starts/stops the browser audio processing gateway from capture state.
- `WebAudioWorkletGateway` creates the `AudioContext`, media source, `AudioWorkletNode`, media destination, and recording worker.
- The worklet already supports `configure` messages and emits `telemetry`.
- `TracklistExporter` is pure Dart and can produce CSV, JSON, and M3U.
- `SessionTracklistStore` is currently desktop-bound through `dart:io` and `File`.
- W5 PWA/offline/accessibility checks are green on main and must remain green.

## 5. Architecture

### 5.1 Typed operator bridge

Introduce a browser-audio operator contract beside the current processing gateway instead of overloading lifecycle methods.

Proposed concepts:

```dart
abstract interface class BrowserMixerGateway {
  Stream<BrowserMixerTelemetry> get telemetry;

  Future<void> configure(BrowserMixerConfiguration configuration);
}

final class BrowserMixerConfiguration {
  const BrowserMixerConfiguration({
    required this.masterGainLinear,
    required this.telemetryEvery,
    required this.channels,
  });

  final double masterGainLinear;
  final int telemetryEvery;
  final List<BrowserMixerChannelConfiguration> channels;
}

final class BrowserMixerChannelConfiguration {
  const BrowserMixerChannelConfiguration({
    required this.id,
    required this.linearTrim,
    required this.fader,
    required this.muted,
    required this.solo,
  });

  final String id;
  final double linearTrim;
  final double fader;
  final bool muted;
  final bool solo;
}
```

Telemetry should mirror the worklet payload, but the Dart layer must validate and normalize browser message data before publishing it:

```dart
final class BrowserMixerTelemetry {
  const BrowserMixerTelemetry({
    required this.channelMeters,
    required this.masterPeakLeft,
    required this.masterPeakRight,
    required this.limiterActive,
  });

  final Map<String, BrowserChannelMeter> channelMeters;
  final double masterPeakLeft;
  final double masterPeakRight;
  final bool limiterActive;
}

final class BrowserChannelMeter {
  const BrowserChannelMeter({required this.peak, required this.rms});

  final double peak;
  final double rms;
}
```

`WebAudioWorkletGateway` implements this new contract in addition to its current processing/recording contracts.

### 5.2 Runtime message flow

Configuration path:

`Web operator state -> BrowserMixerController -> BrowserMixerGateway.configure() -> AudioWorkletNode.port.postMessage({type: 'configure', ...}) -> existing worklet DSP`

Telemetry path:

`existing worklet DSP -> AudioWorkletNode.port message {type: 'telemetry'} -> WebAudioWorkletGateway parser -> typed telemetry stream -> BrowserMixerController -> Web UI + E2E assertions`

The current telemetry ACK behavior may remain if the worklet still needs it, but ACK must not consume or hide meter data from Dart.

### 5.3 Mixer controller

Add a presentation/runtime controller with a small immutable state model. It owns operator intent, not DSP behavior.

Required state:

- active channel ID
- fader value
- mute state
- solo state
- latest channel peak/RMS
- latest master L/R peak
- limiter activity
- processing readiness/error state

Required actions:

- `setFader(double value)`
- `setMuted(bool value)`
- `setSolo(bool value)`
- runtime attach/detach to telemetry
- reset to neutral defaults on a new capture source

Defaults:

- `linearTrim = 1.0`
- `fader = 1.0`
- `muted = false`
- `solo = false`
- `masterGainLinear = 1.0`

The controller should coalesce configuration writes if slider events are more frequent than the worklet needs. It must not block the Flutter UI thread waiting for telemetry.

### 5.4 Web operator UI

Extend `lib/app/app_surface_web.dart` with one compact mixer panel between capture and recording/session controls.

Minimum controls:

- semantic label: `Channel fader`
- fader slider with deterministic min/max and normalized value
- semantic toggle: `Mute`
- semantic toggle: `Solo`
- text or progress-based `Peak` meter
- text or progress-based `RMS` meter
- master peak display
- limiter status indicator

The controls are disabled while no processing node is active. The panel should preserve existing visual hierarchy rather than introducing a new design system.

Accessibility requirements:

- all interactive controls reachable by keyboard
- focus indication remains visible
- semantic labels are stable for Playwright locators
- mute/solo expose selected/pressed state
- fader exposes a value suitable for accessibility APIs
- meter text remains available to assistive technology even if a visual bar is added

### 5.5 Session persistence boundary

Replace concrete dependence on the `dart:io` session store with a platform-neutral repository contract.

Proposed contract:

```dart
abstract interface class SessionTracklistRepository {
  Future<SessionTracklist?> load(String sessionId);
  Future<void> save(SessionTracklist tracklist);
  Future<void> delete(String sessionId);
}
```

Adapters:

- desktop adapter wraps the current file-backed behavior with no schema change
- Web adapter stores serialized non-secret session/tracklist state in same-origin browser storage

Preferred browser storage for this slice: `localStorage`, because the data is small JSON state and the requirement is deterministic reload recovery rather than large binary persistence. If actual serialized session size exceeds practical `localStorage` limits during implementation, switch only the Web adapter to IndexedDB while preserving the same repository interface.

Storage rules:

- namespace keys, e.g. `lmm.session.<sessionId>`
- store only non-secret session/tracklist/correction state
- version serialized payloads
- malformed or unsupported versions fail closed and surface a recoverable error; they do not crash app startup
- writes are replacement/atomic at the browser-storage API level

`SessionTracklistPersister` and `LiveSessionTracklistController` should depend on the repository interface, not a `File` implementation.

### 5.6 Session recovery and export UI

The Web shell should create or recover one active local session for the connected capture workflow.

Required behavior:

1. On Web app startup, load the latest local session pointer if present.
2. If valid session data exists, reconstruct the tracklist state.
3. Persist accepted/corrected tracklist state after mutations through the repository boundary.
4. Provide `EXPORT SESSION` with format choices or separate buttons for JSON/CSV/M3U.
5. Use existing `TracklistExporter` output and a small Web download adapter that creates a same-origin Blob/object URL, triggers a browser download, then revokes the object URL.

No raw audio is persisted in browser storage by this session layer.

### 5.7 Browser capture source-ended recovery

The production artifact must handle the real browser `MediaStreamTrack` lifecycle. When the active track reaches `ended`:

- capture state transitions out of active state
- audio processing node is stopped/detached
- recording cannot continue against a dead source
- mixer controls disable
- existing session/tracklist state remains recoverable
- user can reconnect capture without reloading the app
- after reconnection, mixer defaults are sent to the new worklet node and telemetry resumes

The E2E acceptance must trigger the real application source-ended path, not only a Dart unit-test fake. The implementation should expose no permanent debug-only production UI. The browser test harness may stop the active track through browser page execution using the same `MediaStreamTrack` instance already owned by the production app only if this can be achieved through standards-visible page state without introducing a deploy-time code variant. If direct access is not available from the test harness, add a production-safe `Disconnect source` operator action that calls the same capture teardown path; acceptance then combines that UI path with a controller-level test that explicitly verifies the native `ended` event maps to the same recovery transition.

This preserves exact-artifact identity: there is no `LMM_E2E_TEST_MODE` build variant.

## 6. Browser E2E design

### 6.1 Test location

Run browser E2E in GitHub Actions against the exact Web build directory produced for the release artifact. The current interactive environment blocks local browser navigation by policy, so acceptance evidence must come from the reproducible CI runner rather than from this container.

### 6.2 Framework

Use Playwright from a small repository-owned Web acceptance harness. Do not add a second application runtime.

The harness should:

- serve the built `build/web` directory over HTTP
- launch supported browsers with deterministic test media where available
- interact through visible/semantic UI
- collect browser console errors and page errors
- save only non-secret evidence artifacts

### 6.3 Deterministic audio fixture

Add a short repository-owned synthetic audio fixture suitable for fake microphone input. It should contain a stable non-silent tone or deterministic waveform so peak/RMS assertions can distinguish live signal from silence.

The fixture must be generated or licensed for repository inclusion; do not commit copyrighted music.

### 6.4 Functional acceptance path

The primary functional E2E runs in Chromium because Chromium supports deterministic fake capture devices well in CI.

Sequence:

1. Load the exact built Web artifact.
2. Connect the fake microphone through the production `CONNECT MIC / USB` UI.
3. Assert processing becomes active.
4. Assert channel peak/RMS become non-zero within a bounded timeout.
5. Move fader below unity and assert UI state plus updated mixer configuration behavior.
6. Toggle mute and assert mute state; meter input may remain non-zero while output/master response reflects muted processing.
7. Toggle solo and assert solo state is carried through configuration.
8. Restore a non-muted state.
9. Start recording.
10. Keep recording for at least 10 seconds.
11. Stop recording and download/export WAV.
12. Validate WAV header, PCM format metadata, and duration >=10 seconds using a test-side parser; do not rely only on file extension/size.
13. Trigger source teardown/recovery using the production path defined in section 5.7.
14. Reconnect fake microphone and assert processing plus telemetry recover without full page reload.
15. Mutate session tracklist data through the production session/fingerprint/correction path available to the Web shell.
16. Reload the page and assert the session state recovers from browser storage.
17. Export session JSON (minimum required machine-verifiable format) and validate schema/content. CSV/M3U remain covered by unit tests if the UI exposes all three formats.

### 6.5 Cross-browser capability matrix

W5 requires Chromium + Firefox + Safari-family evidence. The matrix is split intentionally:

- Chromium: complete deterministic functional E2E including fake capture and WAV validation.
- Firefox: boot, accessibility/semantics, PWA shell behavior that Firefox supports, capture capability detection, and operator-control state; run real capture only if CI fake-media support is deterministic.
- WebKit: boot, accessibility/semantics, offline-shell behavior where supported by Playwright WebKit, capability detection, and graceful unsupported/permission states. Do not claim Safari-specific native capture parity from Playwright WebKit when the runner cannot reproduce Safari device permissions.

Any browser-specific capability limitation must be recorded as a capability result, not hidden by skipping the entire browser job.

## 7. Test strategy

Implementation follows RED -> GREEN -> refactor.

### 7.1 Unit tests

Add tests for:

- mixer configuration serialization
- telemetry payload parsing, including malformed/partial payload rejection
- fader/mute/solo state transitions
- limiter/master meter state propagation
- session repository contract behavior
- browser serialization versioning
- session recovery from valid data
- graceful handling of corrupt/unsupported persisted data
- `SessionTracklistPersister` using the abstraction instead of concrete file storage
- export content for JSON/CSV/M3U through the existing exporter
- source-ended transition mapping to recovery state

### 7.2 Widget tests

Verify:

- controls disabled with no active processing source
- keyboard and semantic labels
- mute/solo pressed state
- fader state updates
- meter values render from controller state
- session export controls expose deterministic labels

### 7.3 Worklet contract tests

Keep tests focused on the existing worklet contract:

- Dart `configure` payload matches worklet input schema
- worklet telemetry maps back to typed Dart state
- no duplicate DSP logic is introduced in Dart

### 7.4 Browser acceptance tests

The browser job is a release gate, not a smoke-only job. It must fail on:

- no input telemetry
- control/configuration failure
- recording shorter than 10 seconds
- invalid WAV output
- source recovery failure
- persistence/reload failure
- invalid session export
- uncaught browser/page errors relevant to the acceptance path

## 8. CI and exact-artifact provenance

The build/promotion chain must preserve artifact identity.

Required order:

1. Standard CI builds the Web artifact once for the commit.
2. Browser E2E consumes that built artifact, not a separately rebuilt Web app.
3. PWA contract checks consume/inspect the same release artifact where practical.
4. CI publishes artifact ID + SHA-256 digest.
5. Existing `promote-tested-web-artifact.yml` receives:
   - exact artifact ID
   - exact artifact SHA-256
   - exact 40-character commit SHA
   - target `preview` first
6. Promotion workflow verifies successful CI on the exact commit, verifies artifact ownership/digest, downloads that artifact, then performs the existing Vercel prebuilt deployment path.
7. Preview evidence is recorded before any production promotion.

No manual `vercel deploy` from an unverified local directory is accepted as W5 evidence.

## 9. Failure handling

### Audio bridge

- If `configure` is called before worklet readiness, controller retains desired state and sends it when processing becomes active.
- Malformed telemetry is ignored with bounded diagnostic logging; last valid meter state remains available until reset.
- Worklet/AudioContext failure moves processing to existing error state and disables mixer controls.

### Persistence

- Storage quota or write errors do not terminate audio processing.
- Persistence failure is surfaced as a non-fatal session warning.
- Corrupt persisted JSON is quarantined/ignored and a fresh local session can start.

### Export

- Blob/download creation failures are surfaced to the operator.
- Object URLs are always revoked after download initiation.

### E2E

- Browser tests capture console/page errors, screenshots on failure, and machine-readable test results.
- Evidence artifacts must contain no credentials, tokens, captured private media, or environment secrets.

## 10. Security and privacy

- Browser storage contains only non-secret session/tracklist metadata and corrections.
- No microphone PCM fixture or real user capture is persisted by the session repository.
- The existing recording output remains an explicit user action.
- No new remote telemetry endpoint is introduced.
- No secret/token values are printed into GitHub Actions logs or evidence.

## 11. Expected file-level change map

Likely implementation areas:

- `lib/audio/web/browser_audio_processing_controller.dart`
  - add/compose typed mixer gateway/controller abstractions
- `lib/audio/web/browser_audio_worklet_gateway_web.dart`
  - send `configure`; parse/publish `telemetry`
- new browser mixer model/controller files under `lib/audio/web/`
- `lib/app/app_surface_web.dart`
  - add compact operator panel and session export/recovery surface
- `lib/services/session_tracklist_store.dart`
  - retain file adapter but move behind repository abstraction
- `lib/services/session_tracklist_persister.dart`
  - depend on repository interface
- new conditional Web session storage adapter under `lib/services/web/`
- new browser download adapter under `lib/services/web/`
- tests under existing Dart/Flutter test structure
- repository-owned browser acceptance harness/config
- `.github/workflows/...`
  - add or extend exact-artifact browser E2E gate without weakening existing CI/PWA gates

Exact filenames may change during implementation to fit existing repository conventions, but the boundaries above should remain.

## 12. Acceptance criteria

Implementation is ready to merge only when all of the following are true:

1. Existing W1-W4 and PWA/offline/accessibility tests remain green.
2. WebAudioWorklet configuration for fader/mute/solo is controlled from typed Dart state.
3. Worklet peak/RMS/master/limiter telemetry is visible through typed Dart state and Web UI.
4. Keyboard/semantic accessibility exists for all new controls.
5. Session persistence no longer requires `dart:io` at the domain/controller boundary.
6. Web session state survives a real browser reload.
7. Session JSON export is validated in browser E2E; CSV/M3U exporter behavior remains covered.
8. Chromium browser E2E proves:
   `connect -> meters -> fader -> mute -> solo -> record >=10s -> valid WAV -> source recovery -> reload recovery -> session export`.
9. Firefox and WebKit capability jobs run and report supported/unsupported behavior explicitly.
10. The E2E gate consumes the same built artifact that is published for promotion.
11. The exact artifact ID, SHA-256, commit SHA, and successful workflow evidence are available for Vercel preview promotion.
12. Vercel is not promoted until the exact-artifact browser gate is green.

## 13. Implementation order after design approval

1. Introduce repository/mixer contracts and failing unit tests.
2. Implement worklet configure + telemetry bridge.
3. Implement mixer controller and tests.
4. Refactor session persistence behind the platform-neutral repository and preserve desktop behavior.
5. Implement Web storage adapter + reload-recovery tests.
6. Add Web operator UI + accessibility/widget tests.
7. Add browser download/export adapter.
8. Add deterministic audio fixture and Chromium functional E2E.
9. Add Firefox/WebKit capability jobs.
10. Wire E2E to consume the exact CI Web artifact.
11. Run fresh merge-gate verification.
12. Promote the exact green artifact to Vercel Preview and record non-secret evidence.
13. Promote to production only after preview acceptance.

## 14. Risks and controls

### Risk: Flutter Web semantics are hard to target reliably
Control: assign stable semantic labels and test through accessibility roles/names rather than canvas coordinates.

### Risk: fake media behavior differs by browser
Control: make Chromium the deterministic full functional gate and keep Firefox/WebKit as explicit capability matrices without overstating parity.

### Risk: session persistence refactor regresses desktop
Control: adapter interface wraps existing file store first; retain existing desktop tests before adding Web adapter.

### Risk: high-frequency telemetry rebuilds too much UI
Control: publish bounded telemetry cadence from existing `telemetryEvery` setting and isolate meter rebuilds from the rest of the shell.

### Risk: exact-artifact provenance is lost by rebuilding in E2E or deployment
Control: browser E2E consumes the CI artifact and the Vercel workflow verifies artifact ID/digest/commit before deployment.

### Risk: test-only hooks create a different production artifact
Control: do not use build-time E2E feature flags. Exercise production-safe UI/runtime paths and cover native `ended` event mapping separately when browser automation cannot stop the exact internal track directly.

## 15. Decision summary

Proceed with the minimal Web operator bridge, not a full mixer rewrite. Reuse the existing AudioWorklet DSP, recording worker, fingerprint controller, and `TracklistExporter`. Add only the missing typed bridge, compact operator UI, platform-neutral session persistence, deterministic browser acceptance, and exact-artifact release gating needed to close W5.

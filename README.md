# LiveMixMaster

LiveMixMaster is a Flutter-driven control surface for live audio input routing, mixing, metering, recording, acoustic track identification, session tracklists, and metadata delivery to broadcast endpoints.

## Release targets

LiveMixMaster has separate browser and desktop execution paths. Support claims are evidence-scoped: a capability is called verified only when the repository contains execution evidence for that platform and path.

### Web / PWA

The Web/PWA target is deployed in production at <https://live-mix-master.vercel.app>.

The current promoted Web release is the immutable CI artifact produced from commit `4f97a354dac54cf7c103f477d65002e7dff87213`:

- GitHub Actions source run: `34617452995`
- artifact ID: `10270868244`
- artifact digest: `sha256:eb919bafdc9519e56f09d0d5acaaac28ec568391b55f04ed6b398a799ec7a77a`
- production promotion run: `34622067734`
- Vercel deployment: `dpl_BV4vsKBS6Bnzu2Uk5J75nhpHfv9L`

The promotion workflow deploys the already-tested `build/web` artifact; it does not rebuild Flutter during promotion.

Verified Web release behavior includes:

- browser-provided microphone/USB capture and explicit display/tab-audio capability reporting;
- AudioWorklet-based mix controls with fader, mute, solo, channel summing, peak/RMS metering, and a deterministic sample ceiling;
- Worker-based PCM-to-WAV recording with an exercised recording duration of at least 10 seconds, source-ended recovery, and WAV export;
- browser-origin session/correction persistence and reload recovery using local storage, plus JSON/CSV/M3U export;
- server-side fingerprint-provider and broadcast-metadata proxy boundaries, with provider credentials kept out of the browser contract;
- installable PWA manifest, maskable icons, service-worker/offline shell, keyboard/focus/semantics contracts, and exact-artifact browser E2E in Chromium, Firefox, and Playwright WebKit.

### Desktop

The initial verified desktop development target remains macOS. Windows and Linux are planned targets and must not be inferred as runnable from platform-specific branches alone.

| Platform | Committed runner | Native engine build | Physical capture | System/app loopback | Recording | Fingerprinting | Broadcast metadata | E2E verification |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| macOS | Verified | Verified | Pending #3 | Pending #3 | Contract only; device E2E pending | Contract only; provider/device E2E pending | Contract only; destination E2E pending | Pending #6 |
| Windows | Not verified | Not verified | Pending | Pending | Not verified | Not verified | Not verified | Not verified |
| Linux | Not verified | Not verified | Pending | Pending | Not verified | Not verified | Not verified | Not verified |

## Architecture

Flutter owns the application shell and control state, while the real-time path is platform-specific.

Desktop uses the native C++ engine behind FFI. Web uses browser capture APIs plus an AudioWorklet/Worker pipeline selected through conditional platform boundaries; Web compilation does not require `dart:io`, `dart:ffi`, or the desktop native library.

```text
Desktop: devices / loopback -> native engine -> recorder / services -> Flutter UI
Web: browser-provided sources -> AudioWorklet mix/meter -> recorder Worker -> Flutter UI
                                                   \-> server-side service proxies
```

The Web and native DSP implementations share deterministic parity vectors for the currently supported mix/meter behavior. They are not yet a single shared Wasm/native DSP implementation.

## Web capability and release limitations

- Browser capture is permission- and capability-gated. The Web app does not claim arbitrary system-wide or application-loopback capture parity with native desktop.
- Display/tab audio is available only when the browser/OS supplies an audio track for the user-selected capture surface. The UI must not present unsupported display audio as available.
- Browser device identifiers and permissions are origin/browser scoped and may change after permission changes, browser resets, or device reconnects.
- Session/correction recovery currently uses browser `localStorage`. It is origin scoped, quota/eviction dependent, and can be removed by the user or browser; it is not a durable cross-device database.
- Download/export behavior depends on browser download APIs. Native-style unrestricted filesystem access is not assumed.
- Private/LAN broadcast targets such as local OBS/Icecast endpoints are not directly contacted from the hosted browser release; they require the documented local-bridge pattern. Approved public HTTPS destinations remain server-side.
- Fingerprint provider lookup is server-side. Official Chromaprint 1.6.1 Wasm parity is verified as a build contract, but the planned Dedicated Worker fingerprint-preparation runtime is not yet wired into the production browser operator path; the current browser lookup controller accepts an already-prepared fingerprint.
- Standards-based LUFS and dBTP/true-peak conformance are **not** claimed for the Web release. Current Web evidence covers peak/RMS metering and the deterministic sample-ceiling contract only.
- The WebKit browser matrix is Playwright WebKit evidence; it is not a claim of native Safari/device parity.
- Offline support is an application-shell fallback. Live capture, provider lookup, and broadcast delivery still require their underlying browser/network capabilities.
- Provider keys and broadcast credentials belong only in server-side configuration and must never be embedded in browser assets or checked into the repository.

## Repository layout

```text
lib/
  audio/                           # platform audio boundary
  audio/web/                       # browser capture, Worklet, mixer, recorder control
  services/web/                    # browser session + server-proxy clients
  features/mixer/mixer_desk_view.dart
macos/                             # committed Flutter 3.47.2 desktop host
native/                            # desktop C ABI/DSP prototype + parity vectors
web/                               # PWA shell, Worklet/Worker assets, icons
api/                               # Vercel server-side service proxies
docs/
  release/tested-web-artifact-promotion.md
  product-spec.md
DEVELOPMENT.md                     # clean-clone Web + macOS development paths
```

## Development and release evidence

See [`DEVELOPMENT.md`](DEVELOPMENT.md) for the pinned Flutter 3.47.2 clean-clone workflows and platform boundaries. See [`docs/release/tested-web-artifact-promotion.md`](docs/release/tested-web-artifact-promotion.md) for the immutable-artifact Vercel promotion contract.

The current production Web deployment is intentionally tied to the tested artifact from `4f97a354dac54cf7c103f477d65002e7dff87213`. Later documentation/tooling commits on `main` do not change that deployed artifact unless a new tested artifact is explicitly promoted.

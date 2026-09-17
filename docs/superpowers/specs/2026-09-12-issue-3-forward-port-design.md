# Issue #3 Current-Main Forward-Port Design

Approved design: forward-port the stale macOS native-audio work from PR #15 onto current `main` without regressing the platform factory/Web/shared-Wasm architecture, resolve all seven open review findings with test-first changes, and retain the real macOS physical-input/BlackHole run as the final P0 merge gate.

## Invariants
- Base on current `main`; do not merge or force-rewrite stale PR #15.
- Keep `lib/main.dart` platform-neutral and integrate native runtime behind the current desktop factory/surface split.
- Keep `native/dsp_kernel.hpp` canonical; do not fork DSP arithmetic.
- Preserve ABI-v1 Web DSP constraints, 128-frame quantum ceiling, `0.98` sample ceiling, `1.0e-6` parity tolerance, exact-artifact release flow, and no committed generated Wasm.
- No heap allocation, locks, disk/network I/O, logging, or Dart calls in the native callback.
- Hosted CI is not physical/BlackHole E2E evidence.

## Forward-port architecture
1. Create a clean replacement branch from current `main`; use PR #15 only as historical implementation/reference evidence.
2. Port Core Audio device catalog, permission, capture, PCM handoff, telemetry, tests, and docs behind `audio_engine_factory_desktop.dart` and `app_surface_desktop.dart`.
3. Reuse the canonical shared DSP kernel for mixer/limiter semantics while keeping capture lifecycle and bounded SPSC queues separate.
4. Enforce the current single global Core Audio capture limitation explicitly: a second native live route must be deterministically rejected or explicitly replace the first; silent rebinding is forbidden.
5. Propagate negotiated sample rate to recording/fingerprint consumers; no resampling is introduced.
6. Propagate patchbay `channelPairIndex` into native capture so CH 3-4 and later pairs do not silently capture CH 1-2.
7. Use a live permission-state provider; permission refresh must work after System Settings changes without app restart. `OPEN AUDIO SETTINGS` must actually open macOS privacy/audio-input settings.
8. Native-mode trim and master controls must either affect native PCM through atomic ABI setters or be disabled explicitly; Flutter-only state changes are forbidden.

## Historical review findings that must be closed
- negotiated capture rate -> recorder/fingerprint;
- one active native capture route;
- selected channel pair -> capture conversion;
- live permission re-read;
- functional System Settings recovery action;
- native trim wired or disabled;
- native master fader wired or disabled.

Each finding gets a focused RED regression before the minimal GREEN implementation.

## Acceptance
Automated gates must include current-main Web/PWA/shared-DSP contracts, native deterministic DSP/safety tests, capture conversion for non-zero channel pair, Dart/native binding coverage, single-route behavior, negotiated-rate service wiring, permission recovery, settings launcher behavior, trim/master behavior, SPSC/callback safety, macOS dylib build, Flutter tests, packaged app, and launch smoke.

The replacement PR remains non-mergeable until `docs/audio/macos-device-e2e.md` is executed on a real macOS host with a physical input or user-installed BlackHole-compatible endpoint for at least 10 seconds and `docs/audio/issue3-device-acceptance-record.md` records non-secret PASS evidence for live meters, fader/mute/solo, valid WAV with correct negotiated sample rate, same-process callback/xrun/queue telemetry, zero rejected blocks in the clean run, device-loss/reconnect behavior, stable-UID rediscovery, and post-limiter sample peak <= `0.98` without claiming standards-based True Peak/dBTP.

## Merge strategy
The replacement PR targets `main`. After exact-head CI is green, the real-device acceptance record is PASS, and no blocking review threads remain, merge with an expected-head SHA guard, verify `main`, close Issue #3, then close PR #15 as superseded and sync non-secret evidence to Notion.

# Issue #3 macOS device acceptance record

Status: **PENDING REAL DEVICE RUN**

This file is a non-secret evidence template. Do not mark it PASS until `docs/audio/macos-device-e2e.md` has been executed on a real macOS host with a physical input or BlackHole-compatible endpoint.

## Hosted preflight identity

- verified PR head SHA: `a6611e5f19fa63878a7f8ac8e8c260866594b960`
- Standard CI: #214 (`34490780750`) — GREEN
- macOS Desktop CI: #97 (`34490780889`) — GREEN
- same-process acceptance telemetry contract: GREEN
- macOS hosted suite: 111 tests passed; 2 built-library-dependent tests skipped in the pre-build suite and exercised later by the dedicated FFI smoke
- native CTest: 9/9 passed
- dedicated built-dylib Dart FFI smoke: 3/3 passed
- hosted evidence artifact: `issue3-macos-launch-evidence`, ID `10157730428`, SHA-256 `07f0467d75078cf384deae9936fe43c7c32b2a63fa96c12ca0b60c5161318f6b`

Hosted preflight evidence does not satisfy the device E2E fields below.

## Build/runtime identity

- PR head SHA: PENDING REAL DEVICE RUN
- macOS version: PENDING
- architecture: PENDING
- Flutter version: 3.47.2
- evidence date/time: PENDING

## Endpoint and negotiated format

- source class (physical input / BlackHole): PENDING
- endpoint display label: PENDING
- endpoint UID: PENDING
- sample rate: PENDING
- buffer frames: PENDING
- input channels: PENDING
- channel layout/format flags: PENDING

## Live-path observations

- visible channel meters: PENDING
- fader behavior: PENDING
- MUTE semantics: PENDING
- SOLO semantics: PENDING
- limiter activation under intentional over-ceiling signal: PENDING
- post-limiter sample peak <= 0.98: PENDING

## Same-process E2E telemetry

Read these values from the **E2E TELEMETRY** surface in the same Flutter app process used for this acceptance run. Do not replace them with values from the standalone CLI probe.

- average callback duration (us): PENDING
- maximum callback duration (us): PENDING
- callback count: PENDING
- xrun count: PENDING
- recorder queue depth observed: PENDING
- fingerprint queue depth observed: PENDING
- recorder rejected blocks: PENDING
- fingerprint rejected blocks: PENDING
- queue overflow result: PENDING

A clean acceptance run expects both rejected-block counters to remain zero. Non-zero counters fail the clean run and require investigation; they must never be hidden or rewritten as success.

## Recording

- recording duration: PENDING
- WAV opens independently: PENDING
- WAV format matches expected writer output: PENDING
- non-silent program audio present where expected: PENDING
- non-secret artifact/evidence name: PENDING

## disconnect/reconnect

- removal trigger used: PENDING
- device-loss state observed: PENDING
- stale audio prevented: PENDING
- endpoint rediscovered by stable UID: PENDING
- route reconnected and meters recovered: PENDING
- disconnect/reconnect result: PENDING

## DSP conformance note

The current `true_peak_left/right` ABI fields are post-limiter **sample-peak** values. They are not an oversampled dBTP measurement. This record must not claim standards-based True Peak or LUFS conformance unless that implementation and its tests are added separately.

## Final result

- Final result: PENDING
- Issue #3 evidence comment: PENDING
- Reviewer/verification note: PENDING

Forbidden evidence: credentials, access tokens, private keys, home-directory paths, hardware serial numbers, unrelated device identifiers, or raw logs containing secrets.

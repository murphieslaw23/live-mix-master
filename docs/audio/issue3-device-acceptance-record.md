# Issue #3 macOS device acceptance record

Status: **PENDING REAL DEVICE RUN**

This file is a non-secret evidence template. Do not mark it PASS until `docs/audio/macos-device-e2e.md` has been executed on a real macOS host with a physical input or BlackHole-compatible endpoint.

## Hosted preflight evidence

The app-side same-process acceptance telemetry implementation and its non-secret **COPY EVIDENCE** formatter/UI action are hosted-verified. The final copy-evidence head `4bf8921016d3dbee920a6ec4d63b055dd4486069` passed Standard CI #220 (`34493904574`) and macOS Desktop CI #103 (`34493904540`). Do not copy hosted values into the real-device fields below.

- same-process acceptance telemetry contract: GREEN
- deterministic non-secret Markdown evidence formatter: GREEN
- `COPY EVIDENCE` clipboard action: GREEN
- macOS hosted suite on final copy-evidence head: 113 tests passed; 2 built-library-dependent tests skipped in the pre-build suite and exercised later by the dedicated FFI smoke
- native CTest: 9/9 passed
- dedicated built-dylib Dart FFI smoke: 3/3 passed
- final hosted evidence artifact: `issue3-macos-launch-evidence`, ID `10159005712`, SHA-256 `1e405a2125a981a9dc2567af0caa535bd1f47f0ac4fcd73bf2b3f1db10e50dcf`

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

Use **COPY EVIDENCE** in the running Flutter app and paste the generated `## Same-process E2E telemetry` block below. The copied block deliberately excludes endpoint UIDs, filesystem paths, credentials, account data, and hardware serial numbers. Do not replace these values with standalone CLI-probe output.

PENDING REAL DEVICE RUN

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

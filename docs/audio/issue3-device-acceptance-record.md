# Issue #3 macOS device acceptance record

Status: **PENDING REAL DEVICE RUN**

This is a non-secret evidence template. Do not mark it PASS until `docs/audio/macos-device-e2e.md` has been executed on a real macOS host with a physical input or BlackHole-compatible endpoint.

## Hosted preflight evidence

Hosted CI may be recorded here only as preflight proof. It does not satisfy the device-backed fields below.

- current replacement PR: #38
- verified implementation head: `a0bd2f449f005df7e9d137a982fe7f027883f4f3`
- CI #730 (`34761349988`): GREEN, including Flutter analyze, the full non-golden suite, native release build, design/golden/mixer/reliability/broadcast contracts, Web release/shared-DSP contracts, and exact-artifact browser E2E
- macOS Desktop CI #573 (`34761349911`): GREEN, including 201 passing Flutter tests with 1 expected generic-suite skip, 11/11 native CTests, Core Audio discovery probe, built-dylib Dart FFI smoke, Flutter macOS build, dylib packaging, and launch smoke
- same-process acceptance telemetry formatter/UI: exact-head hosted regression coverage GREEN; hosted values are not copied into the real-device fields below
- non-secret hosted evidence artifact: `issue2-macos-launch-evidence`, artifact ID `10319021900`, digest `sha256:f4df1821664f19ee0b2dfcba5b462798d584f8093ce7e7d1cafdd3a3aa872a55`
- hosted Core Audio probe enumerated runner-provided virtual/null inputs only; that is infrastructure proof and **not** physical/BlackHole acceptance
- real physical/BlackHole run: **PENDING REAL DEVICE RUN**

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
- selected channel pair: PENDING
- sample rate: PENDING
- buffer frames: PENDING
- input channels: PENDING
- channel layout/format flags: PENDING

## Live-path observations

- visible channel meters: PENDING
- fader behavior: PENDING
- MUTE semantics: PENDING
- SOLO semantics: PENDING
- trim behavior: PENDING
- master gain behavior: PENDING
- limiter activation under intentional over-ceiling signal: PENDING
- post-limiter sample peak <= configured ceiling: PENDING

## Same-process E2E telemetry

Use **COPY EVIDENCE** in the running Flutter app and paste the generated `## Same-process E2E telemetry` block below. Do not substitute hosted values or standalone CLI-probe output.

Required fields before acceptance:

- average callback duration (us): PENDING
- maximum callback duration (us): PENDING
- callback count: PENDING
- xrun count: PENDING
- recorder queue depth observed: PENDING
- fingerprint queue depth observed: PENDING
- recorder rejected blocks: PENDING
- fingerprint rejected blocks: PENDING
- queue overflow result: PENDING

Paste the generated block here, replacing the next line only:

PENDING REAL DEVICE RUN

A clean acceptance run requires both rejected-block counters to remain zero. Non-zero values fail the clean run and must not be rewritten as success.

## Recording

- recording duration: PENDING
- WAV opens independently: PENDING
- WAV sample rate matches negotiated capture rate: PENDING
- WAV format matches stereo writer output: PENDING
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

The current `true_peak_left/right` ABI fields are post-limiter **sample-peak** values. They are not oversampled dBTP measurements. This record must not claim standards-based True Peak or LUFS conformance unless a separate implementation and test suite establishes it.

## Final result

- Final result: PENDING
- Issue #3 evidence comment: PENDING
- Reviewer/verification note: PENDING

Forbidden evidence: credentials, access tokens, private keys, private home-directory paths, hardware serial numbers, unrelated device identifiers, or raw logs containing secrets.

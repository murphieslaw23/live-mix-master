# ADR 0001: macOS is the initial desktop target

- Status: Accepted
- Date: 2026-09-08
- GitHub issue: #2

## Decision

LiveMixMaster will establish and verify macOS before adding other desktop hosts. The initial supported runtime is a local development build; distribution signing, notarization, and App Store packaging are explicitly out of scope for this baseline.

## Why this matters

The product needs a real desktop host before validating native audio capture, device selection, gain, recording, and fingerprinting. A macOS runner gives the next native-audio milestone a concrete integration point rather than treating the Dart UI as proof that audio is working.

## Bootstrap the Flutter host

From the repository root on a macOS development machine with Flutter and Xcode installed, generate the committed host files:

```sh
flutter create --platforms=macos .
flutter pub get
flutter analyze
flutter test
flutter build macos --debug
```

Commit the generated `macos/` directory in the same pull request that first enables the host. Do not hand-create generated Xcode project files. The app must compile and launch before Issue #2 can be considered complete.

## Native audio boundary

- Flutter/Dart owns UI state, permissions messaging, device presentation, and stable service contracts.
- The macOS host owns OS-specific capture/session implementation and translates native errors to typed Dart-facing errors.
- The initial loopback/system-audio spike must use a documented macOS capture API and must surface required user permission states in the UI.
- Do not claim reliable system or application audio capture until a device-backed test records actual PCM and documents the permission path.
- Keep capture, DSP, disk writing, and network/fingerprinting work off the UI thread.

## Acceptance evidence

Issue #2 needs all of the following:

1. A committed `macos/` Flutter runner that builds with `flutter build macos --debug`.
2. A GitHub Actions macOS job that runs dependency resolution, analysis, tests, and the debug macOS build.
3. A local launch record identifying the macOS and Flutter versions used.
4. Any build, entitlement, or permission limitation recorded on Issue #2 rather than hidden behind a status change.

## Consequences

Windows and Linux support remain planned, not implied. The abstractions introduced now must avoid exposing macOS framework types across the Dart application boundary.
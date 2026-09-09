# LiveMixMaster Development

## Supported development baseline

The first verified desktop host is macOS. Windows and Linux remain planned targets and are not implied as runnable by this document.

Issue #2 validates a local debug-development baseline only. Distribution signing, notarization, App Store packaging, physical audio capture, loopback capture, recording correctness, fingerprint-provider E2E, and broadcast-delivery E2E are separate gates.

## Prerequisites

- macOS with Xcode and the Xcode command-line tools
- Flutter 3.47.2
- Dart supplied by Flutter 3.47.2
- CMake 3.20+
- a C++17-capable compiler (Apple Clang on macOS)

Check the toolchain:

```sh
sw_vers
xcodebuild -version
flutter --version
cmake --version
```

## Clean-clone setup

From the repository root:

```sh
bash tool/bootstrap_fonts.sh
flutter pub get
cmake -S native -B build/native -DCMAKE_BUILD_TYPE=Debug
cmake --build build/native --config Debug --parallel
test -f build/native/liblive_mixer_engine.dylib
flutter analyze --no-fatal-warnings --no-fatal-infos
flutter test
flutter run -d macos
```

The committed `macos/` host was generated with Flutter 3.47.2. A clean checkout must not require uncommitted generated Xcode files before `flutter run -d macos`.

## Native library lookup

macOS startup resolves `liblive_mixer_engine.dylib` in this order:

1. `LMM_NATIVE_LIBRARY`, when explicitly set;
2. `<repository>/build/native/liblive_mixer_engine.dylib` for local development;
3. `<app>.app/Contents/Frameworks/liblive_mixer_engine.dylib` for a packaged application.

For an explicit local override:

```sh
export LMM_NATIVE_LIBRARY="$PWD/build/native/liblive_mixer_engine.dylib"
flutter run -d macos
```

If no candidate can be loaded, the Flutter application must show `NATIVE ENGINE UNAVAILABLE` with the CMake recovery commands instead of exposing a raw dynamic-loader exception.

## Build the macOS debug application

```sh
bash tool/bootstrap_fonts.sh
flutter pub get
cmake -S native -B build/native -DCMAKE_BUILD_TYPE=Debug
cmake --build build/native --config Debug --parallel
flutter build macos --debug
```

The Flutter debug bundle is expected at:

```text
build/macos/Build/Products/Debug/live_mix_master.app
```

The permanent macOS CI workflow copies the native debug engine to:

```text
build/macos/Build/Products/Debug/live_mix_master.app/Contents/Frameworks/liblive_mixer_engine.dylib
```

and then launches the application executable as a process-level smoke test.

## Tests

Run the full Flutter suite:

```sh
flutter test --reporter expanded
```

Focused Issue #2 contracts:

```sh
flutter test test/native_library_loader_test.dart
flutter test test/native_startup_gate_test.dart
```

Native build verification:

```sh
cmake -S native -B build/native -DCMAKE_BUILD_TYPE=Debug
cmake --build build/native --config Debug --parallel
test -f build/native/liblive_mixer_engine.dylib
```

## Known limits

- macOS is the only desktop runner verified by Issue #2.
- The generated debug runner is sandboxed; audio-input and loopback permission/capture work belongs to Issue #3.
- The native C++ engine is still a prototype; this baseline verifies build/load/host startup, not device-backed PCM correctness.
- Recording, fingerprinting, and broadcast-metadata modules have source/contract tests, but real service/device E2E remains outside this baseline.
- Signing/notarization/distribution are not part of Issue #2.

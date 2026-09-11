# LiveMixMaster Development

## Supported development baseline

The first verified desktop host is macOS. Windows and Linux remain planned targets and are not implied as runnable by this document.

Flutter Web/PWA is a separate release target tracked by Issue #16. Its compile boundary is intentionally independent from the native FFI loader: Web builds select the browser audio backend through conditional exports and must not require the native C++ engine or `dart:io` / `dart:ffi` at compile time.

Issue #2 validates a local macOS debug-development baseline only. Distribution signing, notarization, App Store packaging, physical audio capture, loopback capture, recording correctness, fingerprint-provider E2E, and broadcast-delivery E2E are separate gates.

## Prerequisites

Shared:

- Flutter 3.47.2
- Dart supplied by Flutter 3.47.2

For the verified macOS desktop path:

- macOS with Xcode and the Xcode command-line tools
- CMake 3.20+
- a C++17-capable compiler (Apple Clang on macOS)

Check the toolchain:

```sh
flutter --version
```

For macOS desktop work also check:

```sh
sw_vers
xcodebuild -version
cmake --version
```

## Clean-clone setup

### Web / PWA — Issue #16 W1

From a fresh checkout at the repository root:

```sh
bash tool/bootstrap_fonts.sh
flutter pub get
flutter analyze --no-fatal-warnings --no-fatal-infos
TEST_FILES=$(find test -maxdepth 1 -name '*_test.dart' ! -name 'golden_fixture_render_test.dart' -print | sort)
flutter test --reporter expanded $TEST_FILES
flutter build web --release
test -f build/web/index.html
test -f build/web/manifest.json
```

The committed `web/` runner and `web/manifest.json` are repository inputs. Do not run `flutter create .` as part of the Web build: a clean clone must build the committed runner without regenerating or rewriting desktop host files.

The Web build does not require CMake or `liblive_mixer_engine.dylib`. `lib/audio/audio_engine_factory.dart` selects the browser implementation for Web and keeps `native_library_loader.dart` behind the desktop-only conditional branch. This is the W1 compile boundary that prevents Web compilation from loading native-only libraries while preserving the existing desktop startup path.

The GitHub Actions **Web Release Compile Contract** is the authoritative clean-checkout reproduction of this path and uploads the resulting `build/web` artifact. Browser capture, AudioWorklet DSP, recording, installability, browser E2E, and Vercel promotion are later release gates and are not implied by a successful W1 compile.

### macOS desktop — Issue #2

From the repository root:

```sh
bash tool/bootstrap_fonts.sh
flutter pub get
cmake -S native -B build/native -DCMAKE_BUILD_TYPE=Debug
cmake --build build/native --config Debug --parallel
test -f build/native/liblive_mixer_engine.dylib
flutter analyze --no-fatal-warnings --no-fatal-infos
TEST_FILES=$(find test -maxdepth 1 -name '*_test.dart' ! -name 'golden_fixture_render_test.dart' -print | sort)
flutter test --reporter expanded $TEST_FILES
flutter run -d macos
```

The committed `macos/` host was generated with Flutter 3.47.2. A clean checkout must not require uncommitted generated Xcode files before `flutter run -d macos`.

The Issue #5 golden renderer is intentionally excluded from the generic clean-clone test command because its PNGs are generated during the dedicated Golden Fixture Contract workflow and validated against `test/goldens/issue5-approved-sha256.txt`; the PNG files themselves are not repository inputs.

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

Run the clean-clone non-golden suite:

```sh
TEST_FILES=$(find test -maxdepth 1 -name '*_test.dart' ! -name 'golden_fixture_render_test.dart' -print | sort)
flutter test --reporter expanded $TEST_FILES
```

Verify Issue #5 golden fixtures through their dedicated contract:

```sh
flutter test --update-goldens test/golden_fixture_render_test.dart
grep -v '^#' test/goldens/issue5-approved-sha256.txt | sha256sum --check -
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
- Flutter Web/PWA has a verified clean-clone compile path, but browser/device capability parity with native desktop is not implied.
- The generated macOS debug runner is sandboxed; audio-input and loopback permission/capture work belongs to Issue #3.
- The native C++ engine is still a prototype; this baseline verifies build/load/host startup, not device-backed PCM correctness.
- Recording, fingerprinting, and broadcast-metadata modules have source/contract tests, but real service/device E2E remains outside this baseline.
- Signing/notarization/distribution are not part of Issue #2.

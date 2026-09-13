# LiveMixMaster Development

## Supported development baseline

The first verified desktop host is macOS. Windows and Linux remain planned targets and are not implied as runnable by this document.

Flutter Web/PWA is a separate release target tracked by Issue #16. Its compile boundary is intentionally independent from the native FFI loader: Web builds select the browser audio backend through conditional exports and must not require the native C++ engine or `dart:io` / `dart:ffi` at compile time.

Issue #2 validates the macOS debug-development baseline. Issue #3 owns real Core Audio capture, loopback routing, negotiated-format PCM delivery, native mix-control safety, and the real physical/BlackHole acceptance gate. The canonical device-backed procedure is [`docs/audio/macos-device-e2e.md`](docs/audio/macos-device-e2e.md).

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

The GitHub Actions **Web Release Compile Contract** is the authoritative clean-checkout reproduction of this path and uploads the resulting `build/web` artifact. Browser capture, AudioWorklet DSP, recording, installability, browser E2E, and Vercel promotion are separate release gates.

### macOS desktop — Issues #2 and #3

From the repository root:

```sh
bash tool/bootstrap_fonts.sh
flutter pub get
cmake -S native -B build/native -DBUILD_TESTING=ON -DCMAKE_BUILD_TYPE=Debug
cmake --build build/native --config Debug --parallel
ctest --test-dir build/native --output-on-failure
test -f build/native/liblive_mixer_engine.dylib
flutter analyze --no-fatal-warnings --no-fatal-infos
TEST_FILES=$(find test -maxdepth 1 -name '*_test.dart' ! -name 'golden_fixture_render_test.dart' -print | sort)
flutter test --reporter expanded $TEST_FILES
flutter run -d macos
```

The committed `macos/` host was generated with Flutter 3.47.2. A clean checkout must not require uncommitted generated Xcode files before `flutter run -d macos`.

The Issue #5 golden renderer is intentionally excluded from the generic clean-clone test command because its PNGs are generated during the dedicated Golden Fixture Contract workflow and validated against `test/goldens/issue5-approved-sha256.txt`; the PNG files themselves are not repository inputs.

For Issue #3, hosted CI is preflight only. After all automated contracts are green, execute [`docs/audio/macos-device-e2e.md`](docs/audio/macos-device-e2e.md) on a real macOS host and write only non-secret results into [`docs/audio/issue3-device-acceptance-record.md`](docs/audio/issue3-device-acceptance-record.md). Do not substitute the hosted/null device probe for physical or BlackHole acceptance.

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
cmake -S native -B build/native -DBUILD_TESTING=ON -DCMAKE_BUILD_TYPE=Debug
cmake --build build/native --config Debug --parallel
ctest --test-dir build/native --output-on-failure
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

Focused desktop contracts include:

```sh
flutter test test/native_library_loader_test.dart
flutter test test/native_startup_gate_test.dart
flutter test test/native_audio_route_selection_test.dart
flutter test test/native_audio_control_contract_test.dart
flutter test test/native_pcm_service_coordinator_test.dart
flutter test test/native_acceptance_evidence_copy_test.dart
flutter test test/macos_device_acceptance_contract_test.dart
```

Native build verification:

```sh
cmake -S native -B build/native -DBUILD_TESTING=ON -DCMAKE_BUILD_TYPE=Debug
cmake --build build/native --config Debug --parallel
ctest --test-dir build/native --output-on-failure
test -f build/native/liblive_mixer_engine.dylib
```

The native callback safety rationale and claim boundary are documented in [`docs/audio/dsp-safety-evidence.md`](docs/audio/dsp-safety-evidence.md).

## Known limits

- macOS is the only desktop runner currently verified.
- The automated native/Core Audio contracts do not by themselves prove a physical input or BlackHole route; Issue #3 remains pending until the real-device record passes.
- The macOS host supports exactly one active Core Audio capture route in this forward-port; a second route is rejected explicitly rather than silently rebinding capture.
- Recording and fingerprint consumers use the negotiated capture sample rate and stereo host representation; no resampling layer is introduced here.
- Current native master `true_peak_left/right` ABI values are post-limiter sample peaks, not standards-based dBTP/True Peak, and no LUFS claim is made.
- Flutter Web/PWA has a separate verified release path; browser/device capability parity with native desktop is not implied.
- Signing/notarization/distribution remain separate from the Issue #3 live-audio acceptance gate.
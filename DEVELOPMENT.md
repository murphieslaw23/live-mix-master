# LiveMixMaster Development

## Supported development baseline

The first verified desktop host is macOS. Windows and Linux remain planned targets and are not implied as runnable by this document.

Issue #2 validates the clean-clone desktop baseline. Issue #3 adds Core Audio source/capture and native PCM-path contracts, but physical/BlackHole device acceptance remains a separate real-host gate.

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

The permanent macOS CI workflow copies the native debug engine into the app bundle and then launches the executable as a process-level smoke test.

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
ctest --test-dir build/native --output-on-failure
```

## Issue #3 macOS device acceptance

The exact physical/virtual endpoint procedure and evidence boundary are defined in [`docs/audio/macos-device-e2e.md`](docs/audio/macos-device-e2e.md).

After the native build, enumerate the Core Audio catalog without assuming a display name:

```sh
build/native/macos_device_probe --list
```

On a real host, an optional native diagnostic can drain the production recorder/fingerprint SPSC queues for 10 seconds:

```sh
build/native/macos_device_probe --capture '<stable-uid>' 10
```

For a physical microphone/interface, the canonical permission and route acceptance must use the Flutter macOS application (`flutter run -d macos`) because TCC authorization for a terminal process is not equivalent to the sandboxed app. The final run must cover visible meters, fader/mute/solo, at least 10 seconds of recording, callback/xrun/overflow telemetry, independent WAV inspection, device disconnect, rediscovery by stable UID, and reconnect. Fill only non-secret results into `docs/audio/issue3-device-acceptance-record.md`.

The current limiter is a deterministic sample limiter with a 0.98 linear ceiling. The existing ABI names `true_peak_left/right` do not prove oversampled True Peak/dBTP; do not cite them as such in acceptance evidence.

## Known limits

- macOS is the only desktop runner verified by Issue #2.
- Issue #3 Core Audio and PCM-path code is CI-backed, but no physical-input or BlackHole real-device acceptance is claimed until the record is completed.
- Windows and Linux device capture remain unverified.
- Standards-based True Peak/dBTP and LUFS conformance are not provided by the current sample-peak limiter/meter fields.
- Recording, fingerprinting, and broadcast-metadata modules have source/contract tests, but provider/device E2E remains outside the current hosted-CI evidence.
- Signing/notarization/distribution are not part of this gate.

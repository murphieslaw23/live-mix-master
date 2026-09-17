# LiveMixMaster Native Audio Engine & Build Instructions

## Requirements

- CMake 3.20+
- C++17-capable compiler
  - macOS: Apple Clang
  - Linux: Clang or GCC
  - Windows: MSVC 2019+
- OS audio subsystems referenced by the current prototype:
  - macOS: CoreAudio, AudioToolbox
  - Windows: Windows Media Foundation / platform audio APIs
  - Linux: ALSA plus planned PipeWire-first capture work

## CMake build

The repository CMake target is `live_mixer_engine`.

### macOS

```sh
cmake -S native -B build/native -DCMAKE_BUILD_TYPE=Debug
cmake --build build/native --config Debug --parallel
test -f build/native/liblive_mixer_engine.dylib
```

Issue #2 verifies this debug output path:

```text
build/native/liblive_mixer_engine.dylib
```

Dart startup checks that repo-local path for development and also supports the packaged fallback:

```text
<app>.app/Contents/Frameworks/liblive_mixer_engine.dylib
```

An explicit path can be supplied with `LMM_NATIVE_LIBRARY`.

### Linux

Linux capture is PipeWire-first. Install the development/runtime prerequisites:

```sh
sudo apt install libpipewire-0.3-dev libspa-0.2-dev clang ninja-build libgtk-3-dev
```

Then build the engine:

```sh
cmake -S native -B build/native -DBUILD_TESTING=ON -DCMAKE_BUILD_TYPE=Debug
cmake --build build/native --parallel
ctest --test-dir build/native --output-on-failure
test -f build/native/liblive_mixer_engine.so
```

The Linux backend enumerates PipeWire `Audio/Source` input nodes and `Audio/Sink` monitor nodes. PipeWire owns ALSA device policy and virtual-device/loopback routing; direct ALSA hardware capture is intentionally not a fallback. On ALSA-only installations, install and run PipeWire rather than bypassing the session manager.

The Flutter Linux bundle packages `liblive_mixer_engine.so` under `lib/` next to the executable. For an explicit development override, set `LMM_NATIVE_LIBRARY` to the Debug artifact. Device E2E is not satisfied until `docs/audio/linux-pipewire-device-e2e.md` is run on a real PipeWire desktop host.

### Windows

The current CMake target sets `PREFIX "lib"`, so the target basename is expected to be:

```text
liblive_mixer_engine.dll
```

The exact multi-config output directory depends on the CMake generator. Windows build/runtime support is not verified by Issue #2.

## Flutter contracts

Focused native-host contracts:

```sh
flutter test test/native_library_loader_test.dart
flutter test test/native_startup_gate_test.dart
```

Existing integration/service contracts include:

```sh
flutter test test/mixer_user_flow_test.dart
flutter test test/broadcast_pipeline_test.dart
```

These tests do not prove physical capture, loopback capture, recording conformance, or real provider delivery. Those require later device/service E2E gates.

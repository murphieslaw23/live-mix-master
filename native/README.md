# LiveMixMaster Native Audio Engine & Build Instructions

## Requirements
- CMake 3.20+
- Clang / GCC with C++17 support (macOS, Linux) or MSVC 2019+ (Windows)
- OS Audio Subsystems:
  - macOS: CoreAudio, AudioToolbox
  - Windows: WASAPI, Windows Media Foundation
  - Linux: ALSA, PipeWire or PulseAudio

## Compiling Shared Library for Dart FFI

### macOS (Generating liblive_mixer_engine.dylib)
```bash
clang++ -O3 -shared -std=c++17 -fPIC \
  -framework CoreAudio -framework AudioToolbox \
  native/live_mixer_engine.cpp -o native/liblive_mixer_engine.dylib
```

### Linux (Generating liblive_mixer_engine.so)
```bash
g++ -O3 -shared -std=c++17 -fPIC -pthread \
  -lasound \
  native/live_mixer_engine.cpp -o native/liblive_mixer_engine.so
```

### Windows (Generating live_mixer_engine.dll)
```powershell
cl /O2 /LD /std:c++17 native/live_mixer_engine.cpp /Fe:native/live_mixer_engine.dll
```

## Running Flutter Integration Tests
```bash
flutter test test/mixer_user_flow_test.dart
flutter test test/broadcast_pipeline_test.dart
```

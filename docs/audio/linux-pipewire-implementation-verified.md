# Linux PipeWire desktop path — verified state (2026-09-17)

Per `docs/superpowers/plans/2026-09-17-linux-pipewire-desktop-path.md`.

Task 1 (prerequisites/build): VERIFIED. `native/CMakeLists.txt` uses pkg-config `libpipewire-0.3` (not implicit ALSA); `linux/CMakeLists.txt` builds `live_mixer_engine.so` and installs it next to the executable; docs (`DEVELOPMENT.md`, `native/README.md`) state required packages (`libpipewire-0.3-dev`, `libspa-0.2-dev`, `clang`, `ninja-build`, `libgtk-3-dev`). Host still lacks installed dev packages and a global `flutter` PATH — expected, documented.

Task 2 (device catalog): VERIFIED. `native/linux/pipewire_device_catalog.cpp` present; uses `node.name` identity with `pipewire:source:` / `pipewire:sink:` prefixes; bounded output; non-zero defaults. `device_catalog_contract_tests` registered in CMake and runs on Linux + macOS.

Task 3 (capture + lifecycle): VERIFIED. `pipewire_capture.cpp` implements full `lmm_capture_*` ABI; uses `PW_DIRECTION_INPUT`, `PW_KEY_TARGET_OBJECT`, required flags (`AUTOCONNECT`, `MAP_BUFFERS`, `RT_PROCESS`, `DONT_RECONNECT`), `PW_KEY_STREAM_CAPTURE_SINK` for sinks, bounded `process` with `lmm_process_bound_capture_stereo`, atomics for telemetry/xrun/state; removal maps to `device_removed`/`failed`. `audio_input_permissions.cpp` returns `granted`/`unavailable` from session reachability (no macOS-style prompt). `linux_pipewire_capture_contract_tests` registered.

Task 4 (Flutter Linux runner/package): VERIFIED. `linux/` present (`CMakeLists.txt` includes native engine + `.so` install); `native_library_loader.dart` resolves `.so` from override/repo/debug bundle; `test/native_library_loader_test.dart` covers Linux path; `flutter build linux --debug` passes (bundle at `build/linux/x64/debug/bundle/live_mix_master`).

Task 5 (platform-aware recovery): VERIFIED + FIXED. `audio_settings_launcher.dart` branches Linux (`LinuxAudioSettingsLauncher` -> `xdg-open sound`, fail-closed) / macOS (`MacosAudioSettingsLauncher`). `audio_settings_launcher_linux.dart` and `audio_settings_launcher_macos.dart` present. `test/linux_audio_settings_launcher_test.dart` fixed (`xdg-open`, not `gnome-control-center`). `test/desktop_audio_settings_wiring_test.dart` confirms wiring.

Task 6 (acceptance evidence): STRUCTURAL VERIFIED; INTERACTIVE PENDING. `tool/linux_device_acceptance.sh`, `docs/audio/linux-pipewire-device-e2e.md`, `docs/audio/linux-pipewire-device-acceptance-record.md` present; record stays `PENDING REAL DEVICE RUN`; interactive steps 2-9 (physical source + sink-monitor capture, 10s WAV, removal/recovery, telemetry) require a real Zorin OS 18 session with physical endpoints (`wpctl`, `pipewire:source:`, `pipewire:sink:`) — blocked on this headless host.

Commit: will be included in the push on user's authorization.

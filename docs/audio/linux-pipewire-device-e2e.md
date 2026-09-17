# Linux PipeWire device E2E acceptance

This is the only procedure that can mark the Linux native audio path as device-E2E verified. Native CTest, ABI loading, device enumeration, and a Flutter bundle build are necessary preflight only.

## Required host

- A real Linux desktop session running PipeWire and WirePlumber (Zorin OS 18 is the reference host).
- Flutter `3.47.2`, CMake, Clang, Ninja, GTK 3 development headers, `libpipewire-0.3-dev`, and `libspa-0.2-dev`.
- A physical input and an output sink. The output sink is required for the PipeWire sink-monitor/loopback scenario.
- A clean tracked checkout and no CI environment.

## Preflight

From the repository root:

```sh
FLUTTER_BIN=/path/to/flutter tool/linux_device_acceptance.sh
```

The helper refuses CI, dirty tracked files, an unavailable PipeWire session, a missing native artifact, or a Flutter version other than 3.47.2. It writes only non-secret local diagnostics under `build/linux-device-acceptance/`.

## Interactive procedure

1. Launch the Debug Linux desktop bundle with the built native engine.
2. In Patchbay, refresh devices. Confirm one physical `pipewire:source:` endpoint and one system-output `pipewire:sink:` monitor endpoint are available. Their display names are informational; selection relies on the PipeWire node-name UID.
3. Attach the physical source to the single active route and select a valid channel pair. Confirm the published capture state is `running`, negotiated sample rate/channels are positive, and channel/master meters respond to a known test signal.
4. Verify fader, mute, solo, trim, master limiter, and clip indication while a known signal is active.
5. Start a 24-bit WAV recording. Run for at least 10 seconds, stop/finalize, then inspect the file externally for RIFF/WAVE validity, channels, negotiated sample rate, duration, and non-silent content.
6. Remove/disable the active PipeWire source while recording. Confirm the app reports a disconnected/recovery state, stops forwarding stale PCM, preserves the session log, and does not crash.
7. Re-enable the same source, refresh, reselect by its PipeWire UID, and confirm capture/meter/recording recovery.
8. Repeat steps 3–5 against the `pipewire:sink:` system-output monitor while authorized program audio is playing.
9. Record the capture callback count, xrun count, maximum/average callback duration, and recorder/fingerprint rejected-block counters from the in-app telemetry panel.

## Pass criteria

- Both physical-source and sink-monitor routes produce visible meter movement and valid non-silent WAV output for at least 10 seconds.
- WAV sample rate equals the runtime-negotiated sample rate for each run.
- The clean run has zero recorder/fingerprint rejected blocks, no crash, and no stale PCM after source removal.
- Device removal is surfaced distinctly and manual UID-based recovery works.
- Post-limiter sample peak remains `<= 0.98`.
- The acceptance record includes exact revision, OS/session/PipeWire versions, Flutter version, route identifiers, commands, and only non-secret evidence.

Do not mark `docs/audio/linux-pipewire-device-acceptance-record.md` PASS based on source review, CI, screenshots, an empty or non-empty device catalog, or a library load.

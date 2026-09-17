# Linux PipeWire device acceptance record
|
Status: `PENDING REAL DEVICE RUN`

## Verified this session (2026-09-17)

- `flutter build linux --debug` -> PASS (bundle produced at `build/linux/x64/debug/bundle/live_mix_master`; `/tmp/flutter-3.47.2/bin/flutter`; `pipewire_device_catalog.cpp` C99-designator warnings only).
- Host missing interactive prerequisites: `flutter` not on default PATH (used `/tmp/flutter-3.47.2`); `wpctl` unavailable; no reachable PipeWire session; no physical input sink or output sink-monitor available.
- Helper `tool/linux_device_acceptance.sh` refuses CI/non-clean; this host is clean tracked (`8d0addb`) but still fails `wpctl` and physical-device checks.

## Gate remains: interactive physical procedure (docs/audio/linux-pipewire-device-e2e.md:22-32)

Steps 1-9 must be performed on a real Linux desktop session (reference: Zorin OS 18) with `libpipewire-0.3-dev`, `libspa-0.2-dev`, physical source endpoint (`pipewire:source:` UID) and sink-monitor (`pipewire:sink:`) endpoint.

Specifically PENDING:
- Step 2: refresh devices, confirm `pipewire:source:` + `pipewire:sink:` monitor endpoints visible.
- Step 3-5: physical-source capture, 10s+ 24-bit WAV, external WAV inspection (RIFF valid, non-silent, negotiated rate), meters respond.
- Step 6: removal/recovery - disable source during recording; confirm disconnected state surfaced, stale PCM stops, session log preserved, no crash.
- Step 7: re-enable same source by UID, refresh/reselect, confirm capture/meter/recovery.
- Step 8: repeat 3-5 against `pipewire:sink:` system-output monitor with authorized audio playing.
- Step 9: telemetry (callback count, xrun, max/avg callback duration, recorder/fingerprint rejected-block counters).

Pass criteria unverified:
- Both routes produce valid non-silent WAV for >=10s.
- WAV sample rate equals negotiated rate.
- Zero rejected blocks on clean run; no crash; no stale PCM after removal.
- Removal surfaced distinctly; manual UID-based recovery works.
- Post-limiter peak <= 0.98.
- Record includes exact revision, OS/session/PipeWire versions, Flutter version, route identifiers, commands, non-secret evidence only.

Status: `PENDING REAL DEVICE RUN` - structural tasks 1-5 verified this session (native engine build, device catalog, capture ABI, Linux runner/package, platform-aware launcher); interactive steps 2-9 remain pending real-device run.
Status: `PENDING REAL DEVICE RUN` - intentional; must NOT change to PASS until interactive procedure completes on real device.

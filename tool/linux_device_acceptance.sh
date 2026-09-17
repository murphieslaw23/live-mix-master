#!/usr/bin/env bash
set -euo pipefail
# Interactive Linux PipeWire device acceptance: physical-source + sink-monitor
# recording, removal/recovery, evidence capture. Must run interactively on a
# real Linux desktop (Zorin OS 18 reference) with a reachable PipeWire session,
# physical `pipewire:source:` endpoint and `pipewire:sink:` monitor endpoint.
# Never run in CI (`CI=true` is refused); never change PASS status without
# a real device run.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
BUILD_DIR="$ROOT_DIR/build/linux-device-acceptance"
NATIVE_BUILD_DIR="$ROOT_DIR/build/native"
NATIVE_LIBRARY="$NATIVE_BUILD_DIR/liblive_mixer_engine.so"
RECORD_DIR="$BUILD_DIR/record"
EVIDENCE="$BUILD_DIR/evidence.txt"

echo_step() { printf '\n>>> STEP %s: %s\n' "$1" "$2"; }
echo_sub()  { printf '    %s\n' "$1"; }

fail() {
  printf 'Linux PipeWire acceptance failed: %s\n' "$*" >&2
  exit 1
}

record_evidence() {
  local label="$1"
  shift
  printf '%s: %s\n' "$label" "$*" >> "$EVIDENCE"
}

# --- preflight (same gate as before) ---
[[ "${CI:-}" != "true" ]] || fail 'CI cannot satisfy real-device acceptance; run interactively on a Linux desktop session with real devices.'
[[ -z "$(git -C "$ROOT_DIR" status --porcelain --untracked-files=no)" ]] || \
  fail 'tracked checkout is dirty; record evidence only from a clean tracked revision.'
command -v "$FLUTTER_BIN" >/dev/null 2>&1 || fail "Flutter executable not found: $FLUTTER_BIN"
"$FLUTTER_BIN" --version | grep -q 'Flutter 3.47.2' || \
  fail 'Flutter 3.47.2 is required for this repository acceptance path.'
command -v wpctl >/dev/null 2>&1 || fail 'wpctl is required to verify the PipeWire session.'
wpctl status >/dev/null 2>&1 || fail 'no reachable PipeWire session.'

mkdir -p "$BUILD_DIR" "$RECORD_DIR"

printf 'revision=%s\n' "$(git -C "$ROOT_DIR" rev-parse HEAD)" > "$EVIDENCE"
printf 'os_session=%s\n' "$(grep PRETTY_NAME /etc/os-release 2>/dev/null || echo 'unknown')" >> "$EVIDENCE"
printf 'pipewire_version=%s\n' "$(wpctl --version 2>/dev/null || echo 'unknown')" >> "$EVIDENCE"
printf 'flutter_version=%s\n' "$($FLUTTER_BIN --version | head -n1)" >> "$EVIDENCE"

# --- interactive procedure (docs/audio/linux-pipewire-device-e2e.md:1-33) ---
echo_step 1 "Launch Debug Linux desktop bundle (preflight only verifies bundle can build; interactive capture requires manual device selection in the app)"

cmake -S "$ROOT_DIR/native" -B "$NATIVE_BUILD_DIR" -DBUILD_TESTING=ON -DCMAKE_BUILD_TYPE=Debug
cmake --build "$NATIVE_BUILD_DIR" --parallel
ctest --test-dir "$NATIVE_BUILD_DIR" --output-on-failure
[[ -f "$NATIVE_LIBRARY" ]] || fail "expected native library was not produced: $NATIVE_LIBRARY"

echo_sub "Preflight complete (revision $(git rev-parse --short HEAD)). Interactive steps 2-9 must be performed manually by the operator with real physical and sink-monitor endpoints."

# Step 2: refresh devices; confirm endpoints visible.
echo_step 2 "In Patchbay, refresh devices. Confirm one physical 'pipewire:source:' (node.name UID) and one system-output 'pipewire:sink:' monitor endpoint. Record endpoint UIDs below (manual)."
echo_sub "Example: source UID=pipewire:source:alsa_input.pci-...  sink-monitor UID=pipewire:sink:..."
read -rp "Enter source node UID (or press Enter to skip recording): " SOURCE_UID
if [[ -n "${SOURCE_UID:-}" ]]; then
  printf 'source_uid=%s\n' "$SOURCE_UID" >> "$EVIDENCE"
fi
read -rp "Enter sink-monitor node UID (or press Enter to skip): " SINK_UID
if [[ -n "${SINK_UID:-}" ]]; then
  printf 'sink_monitor_uid=%s\n' "$SINK_UID" >> "$EVIDENCE"
fi

# Step 3-5: physical-source capture + WAV recording.
echo_step 3 "Attach the physical source to the active route; select a valid channel pair. Confirm published capture state=running and meters respond."
echo_sub "Manual verification required: meters move on a known test signal."

# Step 4: fader, mute, solo, trim, limiter, clip.
echo_step 4 "Verify fader, mute, solo, trim, master limiter, and clip indication with a known active signal."
echo_sub "Manual verification required before recording."

# Step 5: 24-bit WAV recording >= 10s; external WAV inspection (RIFF, non-silent, negotiated rate).
echo_step 5 "Start a 24-bit WAV recording (physical-source route). Run >= 10s, stop/finalize, then inspect externally (e.g., ffprobe/file/waveinfo) for RIFF/WAVE, channels, rate, duration, non-silent content."
echo_sub "Output path: $RECORD_DIR/ (save WAV files there)"
read -rp "WAV file produced (relative or absolute path) [enter when inspected]: " WAV_FILE
if [[ -n "${WAV_FILE:-}" && -f "$WAV_FILE" ]]; then
  printf 'recording_wav_path=%s\n' "$WAV_FILE" >> "$EVIDENCE"
  printf 'recording_duration_sec=%s\n' "$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$WAV_FILE" 2>/dev/null || echo 'unknown')" >> "$EVIDENCE"
  printf 'recording_sample_rate=%s\n' "$(ffprobe -v error -show_entries stream=sample_rate -of csv=p=0 "$WAV_FILE" 2>/dev/null | head -n1 || echo 'unknown')" >> "$EVIDENCE"
  printf 'recording_channels=%s\n' "$(ffprobe -v error -show_entries stream=channels -of csv=p=0 "$WAV_FILE" 2>/dev/null | head -n1 || echo 'unknown')" >> "$EVIDENCE"
  printf 'recording_non_silent=manual-inspection-required\n' >> "$EVIDENCE"
else
  printf 'recording_wav_path=none-recorded\n' >> "$EVIDENCE"
fi

# Step 6: removal/recovery - disable source during recording; confirm disconnected.
echo_step 6 "REMOVAL/RECOVERY: disable/remove the active PipeWire source WHILE recording. Confirm the app surfaces a disconnected/recovery state, stops stale PCM forwarding, preserves session log, and does NOT crash."
echo_sub "Perform manually: disable source (e.g., suspend node / unplug / mute at session level) during an active recording."
read -rp "Removal performed? Confirm disconnected state surfaced, no crash, no stale PCM (y/n): " REMOVED_OK
if [[ "${REMOVED_OK:-}" == "y" ]]; then
  printf 'removal_disconnected_surfaced=yes\n' >> "$EVIDENCE"
  printf 'removal_no_crash=yes\n' >> "$EVIDENCE"
  printf 'removal_no_stale_pcm=yes\n' >> "$EVIDENCE"
  printf 'removal_session_log_preserved=yes\n' >> "$EVIDENCE"
else
  printf 'removal_disconnected_surfaced=no-or-not-tested\n' >> "$EVIDENCE"
fi

# Step 7: re-enable same source by UID; confirm recovery.
echo_step 7 "RECOVERY: re-enable the same source by its PipeWire UID; refresh/reselect; confirm capture/meter/recording recovery."
echo_sub "Re-enable via session manager (e.g., wpctl set-state / restart node / reconnect) and select by UID in Patchbay."
read -rp "Re-enabled by UID and recovery confirmed (meters/capture running) (y/n): " RECOVERY_OK
if [[ "${RECOVERY_OK:-}" == "y" ]]; then
  printf 'recovery_by_uid=yes\n' >> "$EVIDENCE"
  printf 'recovery_capture_running=yes\n' >> "$EVIDENCE"
else
  printf 'recovery_by_uid=no-or-not-tested\n' >> "$EVIDENCE"
fi

# Step 8: repeat 3-5 against sink-monitor with authorized audio.
echo_step 8 "Repeat steps 3-5 against 'pipewire:sink:' system-output monitor with authorized program audio playing (sink-monitor loopback route). Confirm meters, limiter, and non-silent WAV >= 10s."
read -rp "Sink-monitor WAV produced and inspected (path or 'none'): " SINK_WAV
if [[ -n "${SINK_WAV:-}" && -f "$SINK_WAV" ]]; then
  printf 'sink_monitor_wav_path=%s\n' "$SINK_WAV" >> "$EVIDENCE"
else
  printf 'sink_monitor_wav_path=none-recorded\n' >> "$EVIDENCE"
fi

# Step 9: telemetry (callback count, xrun, max/avg duration, rejected-block counters).
echo_step 9 "Record telemetry from the in-app telemetry panel: capture callback count, xrun count, max/avg callback duration, recorder/fingerprint rejected-block counters."
read -rp "Callback count (integer): " CB_COUNT
[[ -n "${CB_COUNT:-}" ]] && printf 'telemetry_callback_count=%s\n' "$CB_COUNT" >> "$EVIDENCE" || printf 'telemetry_callback_count=not-recorded\n' >> "$EVIDENCE"
read -rp "Xrun count (integer): " XRUN_COUNT
[[ -n "${XRUN_COUNT:-}" ]] && printf 'telemetry_xrun_count=%s\n' "$XRUN_COUNT" >> "$EVIDENCE" || printf 'telemetry_xrun_count=not-recorded\n' >> "$EVIDENCE"
read -rp "Max callback duration (us): " CB_MAX
[[ -n "${CB_MAX:-}" ]] && printf 'telemetry_callback_max_us=%s\n' "$CB_MAX" >> "$EVIDENCE" || printf 'telemetry_callback_max_us=not-recorded\n' >> "$EVIDENCE"
read -rp "Avg callback duration (us): " CB_AVG
[[ -n "${CB_AVG:-}" ]] && printf 'telemetry_callback_avg_us=%s\n' "$CB_AVG" >> "$EVIDENCE" || printf 'telemetry_callback_avg_us=not-recorded\n' >> "$EVIDENCE"
read -rp "Recorder rejected blocks: " REC_REJ
[[ -n "${REC_REJ:-}" ]] && printf 'telemetry_recorder_rejected=%s\n' "$REC_REJ" >> "$EVIDENCE" || printf 'telemetry_recorder_rejected=not-recorded\n' >> "$EVIDENCE"
read -rp "Fingerprint rejected blocks: " FP_REJ
[[ -n "${FP_REJ:-}" ]] && printf 'telemetry_fingerprint_rejected=%s\n' "$FP_REJ" >> "$EVIDENCE" || printf 'telemetry_fingerprint_rejected=not-recorded\n' >> "$EVIDENCE"

# --- evidence summary + pass criteria reminder ---
echo ""
echo "=== EVIDENCE SUMMARY ($EVIDENCE) ==="
cat "$EVIDENCE"
echo "=== PROCEDURE COMPLETE (interactive) ==="
echo_sub "Pass criteria (docs/audio/linux-pipewire-device-e2e.md:34-44):"
echo_sub "  - Both routes produce valid non-silent WAV >= 10s."
echo_sub "  - WAV sample rate equals negotiated rate."
echo_sub "  - Zero rejected blocks on clean run; no crash; no stale PCM after removal."
echo_sub "  - Device removal surfaced distinctly; manual UID-based recovery works."
echo_sub "  - Post-limiter peak <= 0.98."
echo_sub "  - Evidence includes exact revision, OS/session/PipeWire versions, route identifiers, commands, non-secret evidence only."
echo_sub "Status of docs/audio/linux-pipewire-device-acceptance-record.md must remain PENDING REAL DEVICE RUN until an operator verifies the above manually."
echo_sub "This helper writes only non-secret diagnostics; it does NOT mark PASS."

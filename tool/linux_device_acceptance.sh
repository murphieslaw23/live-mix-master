#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
BUILD_DIR="$ROOT_DIR/build/linux-device-acceptance"
NATIVE_BUILD_DIR="$ROOT_DIR/build/native"
NATIVE_LIBRARY="$NATIVE_BUILD_DIR/liblive_mixer_engine.so"

fail() {
  printf 'Linux PipeWire acceptance preflight failed: %s\n' "$*" >&2
  exit 1
}

[[ "${CI:-}" != "true" ]] || fail 'CI cannot satisfy real-device acceptance.'
[[ -z "$(git -C "$ROOT_DIR" status --porcelain --untracked-files=no)" ]] || \
  fail 'tracked checkout is dirty; record evidence only from a clean tracked revision.'
command -v "$FLUTTER_BIN" >/dev/null 2>&1 || fail "Flutter executable not found: $FLUTTER_BIN"
"$FLUTTER_BIN" --version | grep -q 'Flutter 3.47.2' || \
  fail 'Flutter 3.47.2 is required for this repository acceptance path.'
command -v wpctl >/dev/null 2>&1 || fail 'wpctl is required to verify the PipeWire session.'
wpctl status >/dev/null 2>&1 || fail 'no reachable PipeWire session.'

mkdir -p "$BUILD_DIR"
printf 'revision=%s\n' "$(git -C "$ROOT_DIR" rev-parse HEAD)" > "$BUILD_DIR/preflight.txt"
printf 'pipewire_status:\n' >> "$BUILD_DIR/preflight.txt"
wpctl status >> "$BUILD_DIR/preflight.txt"
printf 'flutter:\n' >> "$BUILD_DIR/preflight.txt"
"$FLUTTER_BIN" --version >> "$BUILD_DIR/preflight.txt"

cmake -S "$ROOT_DIR/native" -B "$NATIVE_BUILD_DIR" -DBUILD_TESTING=ON -DCMAKE_BUILD_TYPE=Debug
cmake --build "$NATIVE_BUILD_DIR" --parallel
ctest --test-dir "$NATIVE_BUILD_DIR" --output-on-failure
[[ -f "$NATIVE_LIBRARY" ]] || fail "expected native library was not produced: $NATIVE_LIBRARY"

printf 'preflight passed; launching the interactive Linux desktop path.\n'
LMM_NATIVE_LIBRARY="$NATIVE_LIBRARY" "$FLUTTER_BIN" run -d linux

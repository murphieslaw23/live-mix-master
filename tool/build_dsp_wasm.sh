#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXPECTED_EMSCRIPTEN_VERSION="6.0.9"
OUTPUT_DIR="$ROOT_DIR/build/dsp-wasm"
OUTPUT_WASM="$OUTPUT_DIR/livemixmaster-dsp.wasm"
WEB_OUTPUT="$ROOT_DIR/web/audio/livemixmaster-dsp.wasm"
CHECKSUM_FILE="$OUTPUT_DIR/livemixmaster-dsp.wasm.sha256"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "required command is unavailable: $1" >&2
    exit 2
  fi
}

require_command emcc
require_command em++
require_command sha256sum

EMSCRIPTEN_VERSION="$(emcc --version | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
if [[ "$EMSCRIPTEN_VERSION" != "$EXPECTED_EMSCRIPTEN_VERSION" ]]; then
  echo "expected Emscripten $EXPECTED_EMSCRIPTEN_VERSION, got ${EMSCRIPTEN_VERSION:-unknown}" >&2
  exit 2
fi

mkdir -p "$OUTPUT_DIR" "$(dirname "$WEB_OUTPUT")"
rm -f "$OUTPUT_WASM" "$WEB_OUTPUT" "$CHECKSUM_FILE"

em++ \
  -O3 \
  -std=c++17 \
  -I"$ROOT_DIR/native" \
  "$ROOT_DIR/native/dsp_wasm_abi.cpp" \
  -sSTANDALONE_WASM=1 \
  -sALLOW_MEMORY_GROWTH=0 \
  -sFILESYSTEM=0 \
  -sUSE_PTHREADS=0 \
  -sEXPORTED_FUNCTIONS='["_lmm_dsp_abi_version","_lmm_dsp_max_channels","_lmm_dsp_process_stereo","_malloc","_free"]' \
  -Wl,--no-entry \
  -o "$OUTPUT_WASM"

if [[ ! -s "$OUTPUT_WASM" ]]; then
  echo "DSP Wasm output is missing or empty" >&2
  exit 3
fi

cp "$OUTPUT_WASM" "$WEB_OUTPUT"
sha256sum "$WEB_OUTPUT" > "$CHECKSUM_FILE"

echo "DSP Wasm ready: $WEB_OUTPUT"
echo "DSP Wasm checksum: $CHECKSUM_FILE"

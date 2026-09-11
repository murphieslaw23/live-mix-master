#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHROMAPRINT_VERSION="1.6.1"
CHROMAPRINT_SHA256="3368805af0ee47b9df74df10b5001a44569e01df2844dab520031720dde9ad23"
CHROMAPRINT_URL="https://github.com/acoustid/chromaprint/releases/download/v${CHROMAPRINT_VERSION}/chromaprint-${CHROMAPRINT_VERSION}.tar.gz"
EXPECTED_EMSCRIPTEN_VERSION="6.0.9"

VENDOR_DIR="$ROOT_DIR/build/vendor"
ARCHIVE="$VENDOR_DIR/chromaprint-${CHROMAPRINT_VERSION}.tar.gz"
SOURCE_DIR="$VENDOR_DIR/chromaprint-${CHROMAPRINT_VERSION}"
CMAKE_BUILD_DIR="$ROOT_DIR/build/chromaprint-cmake"
OUTPUT_DIR="$ROOT_DIR/build/chromaprint-wasm"
WRAPPER="$ROOT_DIR/web/fingerprint/chromaprint/lmm_chromaprint_wrapper.cpp"
CORE_MODULE="$OUTPUT_DIR/livemixmaster-chromaprint-core.mjs"
ADAPTER_MODULE="$OUTPUT_DIR/livemixmaster-chromaprint.mjs"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "required command is unavailable: $1" >&2
    exit 2
  fi
}

require_command emcmake
require_command em++
require_command cmake
require_command tar
require_command sha256sum

EMSCRIPTEN_VERSION="$(emcc --version | sed -n '1s/.*emcc (Emscripten gcc\/clang-like replacement + emulating GNU ld) \([0-9.]*\).*/\1/p')"
if [[ -z "$EMSCRIPTEN_VERSION" ]]; then
  EMSCRIPTEN_VERSION="$(emcc --version | sed -n '1s/.*version \([0-9.]*\).*/\1/p')"
fi
if [[ "$EMSCRIPTEN_VERSION" != "$EXPECTED_EMSCRIPTEN_VERSION" ]]; then
  echo "expected Emscripten $EXPECTED_EMSCRIPTEN_VERSION, got ${EMSCRIPTEN_VERSION:-unknown}" >&2
  exit 2
fi

mkdir -p "$VENDOR_DIR" "$OUTPUT_DIR"

if [[ ! -f "$ARCHIVE" ]]; then
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$CHROMAPRINT_URL" -o "$ARCHIVE"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$ARCHIVE" "$CHROMAPRINT_URL"
  else
    require_command python3
    python3 - "$CHROMAPRINT_URL" "$ARCHIVE" <<'PY'
import pathlib
import sys
import urllib.request

url, output = sys.argv[1], pathlib.Path(sys.argv[2])
with urllib.request.urlopen(url) as source, output.open('wb') as target:
    target.write(source.read())
PY
  fi
fi

echo "$CHROMAPRINT_SHA256  $ARCHIVE" | sha256sum --check -

rm -rf "$SOURCE_DIR" "$CMAKE_BUILD_DIR"
mkdir -p "$SOURCE_DIR" "$CMAKE_BUILD_DIR"
tar -xzf "$ARCHIVE" --strip-components=1 -C "$SOURCE_DIR"

emcmake cmake \
  -S "$SOURCE_DIR" \
  -B "$CMAKE_BUILD_DIR" \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=OFF \
  -DBUILD_TOOLS=OFF \
  -DBUILD_TESTS=OFF \
  -DUSE_INTERNAL_AVRESAMPLE=ON \
  -DFFT_LIB=kissfft \
  -DKISSFFT_ROOT="$SOURCE_DIR/src/3rdparty/kissfft"

cmake --build "$CMAKE_BUILD_DIR" --target chromaprint --parallel

CHROMAPRINT_LIBRARY="$(find "$CMAKE_BUILD_DIR" -type f -name 'libchromaprint.a' -print -quit)"
if [[ -z "$CHROMAPRINT_LIBRARY" ]]; then
  echo "Chromaprint static library was not produced" >&2
  exit 3
fi

rm -f "$OUTPUT_DIR"/*.mjs "$OUTPUT_DIR"/*.wasm

em++ \
  -O3 \
  -std=c++14 \
  -I"$SOURCE_DIR/src" \
  -I"$CMAKE_BUILD_DIR" \
  "$WRAPPER" \
  "$CHROMAPRINT_LIBRARY" \
  -sMODULARIZE=1 \
  -sEXPORT_ES6=1 \
  -sEXPORT_NAME=createLiveMixMasterChromaprintCore \
  -sENVIRONMENT=web,worker,node \
  -sALLOW_MEMORY_GROWTH=1 \
  -sFILESYSTEM=0 \
  -sDYNAMIC_EXECUTION=0 \
  -sEXPORTED_FUNCTIONS='["_lmm_chromaprint_version","_lmm_chromaprint_fingerprint","_lmm_chromaprint_free","_malloc","_free"]' \
  -sEXPORTED_RUNTIME_METHODS='["UTF8ToString"]' \
  -o "$CORE_MODULE"

cat > "$ADAPTER_MODULE" <<'JS'
import createCore from './livemixmaster-chromaprint-core.mjs';

export async function createChromaprint({wasmUrl} = {}) {
  const module = await createCore({
    locateFile(fileName) {
      if (fileName.endsWith('.wasm') && wasmUrl) {
        return wasmUrl;
      }
      return new URL(fileName, import.meta.url).href;
    },
  });

  return Object.freeze({
    version() {
      const pointer = module._lmm_chromaprint_version();
      if (!pointer) {
        throw new Error('Chromaprint version is unavailable');
      }
      return module.UTF8ToString(pointer);
    },

    fingerprintPcm16(pcm, sampleRate, channels) {
      if (!(pcm instanceof Int16Array)) {
        throw new TypeError('pcm must be an Int16Array');
      }
      if (!Number.isInteger(sampleRate) || sampleRate <= 0) {
        throw new RangeError('sampleRate must be a positive integer');
      }
      if (channels !== 1 && channels !== 2) {
        throw new RangeError('channels must be 1 or 2');
      }
      if (pcm.length === 0) {
        throw new RangeError('pcm must not be empty');
      }

      const pcmPointer = module._malloc(pcm.byteLength);
      if (!pcmPointer) {
        throw new Error('Chromaprint PCM allocation failed');
      }

      try {
        module.HEAP16.set(pcm, pcmPointer >> 1);
        const fingerprintPointer = module._lmm_chromaprint_fingerprint(
          pcmPointer,
          pcm.length,
          sampleRate,
          channels,
        );
        if (!fingerprintPointer) {
          throw new Error('Chromaprint fingerprint generation failed');
        }
        try {
          return module.UTF8ToString(fingerprintPointer);
        } finally {
          module._lmm_chromaprint_free(fingerprintPointer);
        }
      } finally {
        module._free(pcmPointer);
      }
    },
  });
}
JS

CORE_WASM="$OUTPUT_DIR/livemixmaster-chromaprint-core.wasm"
if [[ ! -s "$CORE_MODULE" || ! -s "$CORE_WASM" || ! -s "$ADAPTER_MODULE" ]]; then
  echo "Chromaprint Wasm build output is incomplete" >&2
  exit 4
fi

printf 'Chromaprint Wasm ready: %s\n' "$OUTPUT_DIR"

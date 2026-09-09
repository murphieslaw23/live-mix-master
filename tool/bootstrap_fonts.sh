#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FONT_DIR="$ROOT_DIR/assets/fonts"
GOOGLE_FONTS_COMMIT="0cf764bb712367b6079cbb4fd2353e6f54ec6850"
BASE_URL="https://raw.githubusercontent.com/google/fonts/${GOOGLE_FONTS_COMMIT}"

mkdir -p "$FONT_DIR"

download_verified() {
  local relative_url="$1"
  local destination="$2"
  local expected_blob_sha="$3"

  if [[ -f "$destination" ]]; then
    local existing_sha
    existing_sha="$(git hash-object "$destination")"
    if [[ "$existing_sha" == "$expected_blob_sha" ]]; then
      printf 'font ok: %s (%s)\n' "$(basename "$destination")" "$existing_sha"
      return 0
    fi
  fi

  local tmp="${destination}.tmp"
  rm -f "$tmp"
  curl --fail --location --retry 3 --silent --show-error \
    "${BASE_URL}/${relative_url}" \
    --output "$tmp"

  local actual_sha
  actual_sha="$(git hash-object "$tmp")"
  if [[ "$actual_sha" != "$expected_blob_sha" ]]; then
    rm -f "$tmp"
    printf 'font hash mismatch for %s: expected %s, got %s\n' \
      "$(basename "$destination")" "$expected_blob_sha" "$actual_sha" >&2
    exit 1
  fi

  mv "$tmp" "$destination"
  printf 'font installed: %s (%s)\n' "$(basename "$destination")" "$actual_sha"
}

download_verified \
  'ofl/robotocondensed/RobotoCondensed%5Bwght%5D.ttf' \
  "$FONT_DIR/RobotoCondensed-Variable.ttf" \
  '221055572bc92e324d26337dee7b43b435e39fc8'

download_verified \
  'ofl/inter/Inter%5Bopsz%2Cwght%5D.ttf' \
  "$FONT_DIR/Inter-Variable.ttf" \
  '047c92f6e2212473dc436020afed689527076d44'

download_verified \
  'ofl/robotomono/RobotoMono%5Bwght%5D.ttf' \
  "$FONT_DIR/RobotoMono-Variable.ttf" \
  'f21d1d716bce3cc756bc618d32be71ce6f733f81'

if [[ -z "${FLUTTER_ROOT:-}" ]]; then
  printf 'FLUTTER_ROOT is required to bootstrap Material Icons\n' >&2
  exit 1
fi

MATERIAL_ICONS_SOURCE="$FLUTTER_ROOT/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf"
MATERIAL_ICONS_DEST="$FONT_DIR/MaterialIcons-Regular.otf"

if [[ ! -f "$MATERIAL_ICONS_SOURCE" ]]; then
  printf 'Material Icons font missing from pinned Flutter SDK: %s\n' "$MATERIAL_ICONS_SOURCE" >&2
  exit 1
fi

cp "$MATERIAL_ICONS_SOURCE" "$MATERIAL_ICONS_DEST"
printf 'font installed: %s (%s)\n' \
  "$(basename "$MATERIAL_ICONS_DEST")" \
  "$(git hash-object "$MATERIAL_ICONS_DEST")"

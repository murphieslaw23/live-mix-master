#!/usr/bin/env bash
set -euo pipefail

readonly ACCEPTANCE_RECORD="docs/audio/issue3-device-acceptance-record.md"
readonly EVIDENCE_DIR="build/issue3-device-acceptance"
readonly REQUIRED_FLUTTER="3.47.2"

usage() {
  cat <<'EOF'
Usage: bash tool/macos_device_acceptance.sh <command>

Commands:
  --preflight  Verify the exact checkout/toolchain, build and test native code,
               and enumerate Core Audio inputs on a real macOS host.
  --launch     Run the same preflight, then launch LiveMixMaster with
               `flutter run -d macos` for the interactive Issue #3 device E2E.
  --help       Show this help.

This helper is intentionally local-only. A real macOS physical input or a
user-installed BlackHole-compatible endpoint is still required for PASS.
The helper never edits the acceptance record or substitutes hosted CI evidence.
EOF
}

fail_gate() {
  printf 'Issue #3 acceptance helper: %s\n' "$1" >&2
  exit 64
}

case "${1:-}" in
  --help|-h)
    usage
    exit 0
    ;;
  --preflight|--launch)
    readonly MODE="$1"
    ;;
  *)
    usage >&2
    exit 64
    ;;
esac

if [[ -n "${CI:-}" && "${CI:-}" != "false" && "${CI:-}" != "0" ]]; then
  fail_gate "real-device acceptance requires an interactive local macOS host; CI cannot satisfy this gate."
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  fail_gate "real-device acceptance requires macOS."
fi

command -v git >/dev/null 2>&1 || fail_gate "git is required."
command -v flutter >/dev/null 2>&1 || fail_gate "Flutter ${REQUIRED_FLUTTER} is required."
command -v cmake >/dev/null 2>&1 || fail_gate "CMake is required."
command -v xcodebuild >/dev/null 2>&1 || fail_gate "Xcode command-line tools are required."

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || fail_gate "run this helper from a LiveMixMaster Git checkout."
cd "$REPO_ROOT"

if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
  fail_gate "tracked files are modified; start acceptance from an exact clean PR checkout."
fi

HEAD_SHA="$(git rev-parse HEAD)"
FLUTTER_LINE="$(flutter --version | head -n 1)"
if [[ "$FLUTTER_LINE" != *"Flutter ${REQUIRED_FLUTTER}"* ]]; then
  fail_gate "expected Flutter ${REQUIRED_FLUTTER}; found: ${FLUTTER_LINE}"
fi

mkdir -p "$EVIDENCE_DIR"

{
  printf 'LiveMixMaster Issue #3 local preflight\n'
  printf 'head_sha=%s\n' "$HEAD_SHA"
  printf 'timestamp_utc=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  sw_vers
  printf 'architecture=%s\n' "$(uname -m)"
  printf '%s\n' "$FLUTTER_LINE"
  xcodebuild -version
  cmake --version | head -n 1
} | tee "$EVIDENCE_DIR/preflight.txt"

printf '\n== Bootstrap dependencies ==\n'
bash tool/bootstrap_fonts.sh
flutter pub get

printf '\n== Build and test native engine ==\n'
cmake -S native -B build/native -DBUILD_TESTING=ON -DCMAKE_BUILD_TYPE=Debug
cmake --build build/native --config Debug --parallel
ctest --test-dir build/native --output-on-failure

printf '\n== Enumerate Core Audio inputs ==\n'
test -x build/native/macos_device_probe
build/native/macos_device_probe --list | tee "$EVIDENCE_DIR/coreaudio-inputs.txt"

cat <<EOF

Preflight complete for HEAD ${HEAD_SHA}.
Local diagnostic files are under ${EVIDENCE_DIR}/ and are not acceptance PASS.
Canonical record: ${ACCEPTANCE_RECORD}
EOF

if [[ "$MODE" == "--preflight" ]]; then
  cat <<'EOF'
Next: rerun with --launch on the same checkout, then execute every interactive
step in docs/audio/macos-device-e2e.md with a physical or BlackHole input.
EOF
  exit 0
fi

cat <<'EOF'

Launching the real Flutter macOS app. In the app:
  1. grant microphone/audio-input permission;
  2. attach the intended stable-UID route and channel pair;
  3. verify live meters plus fader/MUTE/SOLO/trim/master behavior;
  4. record continuous program audio for at least 10 seconds;
  5. use E2E TELEMETRY -> COPY EVIDENCE;
  6. disconnect/reconnect the endpoint and verify stable-UID recovery.

After the app exits, paste only non-secret observed evidence into
`docs/audio/issue3-device-acceptance-record.md`. Do not mark acceptance PASS
unless every canonical requirement is actually observed.
EOF

flutter run -d macos

cat <<EOF

App session ended. Complete ${ACCEPTANCE_RECORD} from observed real-device
results and independently inspect the finalized WAV before requesting merge.
EOF

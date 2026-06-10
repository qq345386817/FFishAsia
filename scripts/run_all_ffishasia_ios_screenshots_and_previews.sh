#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SNAPSHOT_SCRIPT="$SCRIPT_DIR/run_ffishasia_snapshots.sh"
PREVIEW_SCRIPT="$SCRIPT_DIR/render_all_ffishasia_previews_local.sh"
DEVICE_SCREENSHOT_TIMEOUT_SECONDS="${FFISH_DEVICE_SCREENSHOT_TIMEOUT_SECONDS:-1800}"
PREVIEW_RENDER_TIMEOUT_SECONDS="${FFISH_PREVIEW_RENDER_TIMEOUT_SECONDS:-900}"
IPHONE_DEVICE="${FFISH_IPHONE_DEVICE:-iPhone 17 Pro Max}"
IPAD_DEVICE="${FFISH_IPAD_DEVICE:-iPad Pro 13-inch (M5)}"
LOCALES="${LOCALES:-zh-Hans zh-Hant en-US ja ko de-DE}"
MODES="${MODES:-light}"

run_with_timeout() {
  local timeout_seconds="$1"
  local label="$2"
  shift 2

  python3 - "$timeout_seconds" "$label" "$@" <<'PY'
import os, signal, subprocess, sys

timeout_seconds = int(sys.argv[1])
label = sys.argv[2]
cmd = sys.argv[3:]
proc = subprocess.Popen(cmd, preexec_fn=os.setsid)
try:
    sys.exit(proc.wait(timeout=timeout_seconds))
except KeyboardInterrupt:
    print(f"🛑 Interrupted: {label}", file=sys.stderr)
    try: os.killpg(proc.pid, signal.SIGTERM)
    except ProcessLookupError: pass
    sys.exit(130)
except subprocess.TimeoutExpired:
    print(f"❌ Timed out after {timeout_seconds}s: {label}", file=sys.stderr)
    try: os.killpg(proc.pid, signal.SIGTERM)
    except ProcessLookupError: pass
    try: proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        try: os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError: pass
        proc.wait()
    sys.exit(124)
PY
}

if [[ ! -f "$SNAPSHOT_SCRIPT" || ! -f "$PREVIEW_SCRIPT" ]]; then
  echo "Error: FFishAsia snapshot/render scripts are missing." >&2
  exit 1
fi

cd "$ROOT_DIR"

if [[ "${FFISH_SKIP_IPHONE_SCREENSHOTS:-0}" != "1" ]]; then
  echo "========== Step 1/3: Generate raw FFishAsia iPhone screenshots ($LOCALES / $MODES) =========="
  run_with_timeout "$DEVICE_SCREENSHOT_TIMEOUT_SECONDS" "FFishAsia iPhone raw screenshots" \
    /bin/zsh -lc "SCREENSHOT_DEVICE_PREFIX=iphone17promax LOCALES='$LOCALES' MODES='$MODES' bash '$SNAPSHOT_SCRIPT' '$IPHONE_DEVICE'"
fi

if [[ "${FFISH_SKIP_IPAD_SCREENSHOTS:-0}" != "1" ]]; then
  echo
  echo "========== Step 2/3: Generate raw FFishAsia 13-inch iPad screenshots ($LOCALES / $MODES) =========="
  run_with_timeout "$DEVICE_SCREENSHOT_TIMEOUT_SECONDS" "FFishAsia iPad raw screenshots" \
    /bin/zsh -lc "SCREENSHOT_DEVICE_PREFIX=ipad13 LOCALES='$LOCALES' MODES='$MODES' bash '$SNAPSHOT_SCRIPT' '$IPAD_DEVICE'"
fi

echo
echo "========== Step 3/3: Render App Store preview images and sync Fastlane =========="
run_with_timeout "$PREVIEW_RENDER_TIMEOUT_SECONDS" "FFishAsia preview render" \
  /bin/zsh -lc "LOCALES='$LOCALES' MODES='$MODES' bash '$PREVIEW_SCRIPT'"

echo
echo "✅ Done. FFishAsia iPhone/iPad raw screenshots, AppStorePreview outputs, and Fastlane screenshots are updated."

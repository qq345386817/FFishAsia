#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SNAPSHOT_SCRIPT="$SCRIPT_DIR/run_ffishasia_macos_snapshots.sh"
PREVIEW_SCRIPT="$SCRIPT_DIR/render_all_ffishasia_macos_previews_local.sh"
SNAPSHOT_TIMEOUT_SECONDS="${FFISHASIA_MACOS_SNAPSHOT_TIMEOUT_SECONDS:-1800}"
PREVIEW_TIMEOUT_SECONDS="${FFISHASIA_MACOS_PREVIEW_TIMEOUT_SECONDS:-900}"
OUTPUT_ROOT="${FFISHASIA_MACOS_OUTPUT_ROOT:-$ROOT_DIR/macos_screenshots}"
RAW_DIR="${FFISHASIA_MACOS_RAW_DIR:-$OUTPUT_ROOT/raw}"
PREVIEW_OUTPUT_DIR="${FFISHASIA_MACOS_PREVIEW_OUTPUT_DIR:-$OUTPUT_ROOT/output}"
KEEP_INTERMEDIATES="${FFISHASIA_KEEP_MACOS_INTERMEDIATES:-0}"
APP_BUNDLE_ID="${FFISHASIA_MACOS_APP_BUNDLE_ID:-com.luopeike.FFishAsia}"
APP_NAME="${FFISHASIA_MACOS_APP_NAME:-Little Nature}"
BUILD_LOG_PATH="${FFISHASIA_MACOS_BUILD_LOG_PATH:-/tmp/ffishasia_macos_snapshot_build.log}"
PLAN_PATH="${FFISHASIA_MACOS_PLAN_PATH:-/tmp/ffishasia_macos_snapshot_plan.tsv}"
DERIVED_DATA_PATH="${FFISHASIA_MACOS_DERIVED_DATA_PATH:-$ROOT_DIR/build-macos-snapshots}"

run_with_timeout() {
  local timeout_seconds="$1"
  local label="$2"
  shift 2

  python3 - "$timeout_seconds" "$label" "$@" <<'PY'
import os
import signal
import subprocess
import sys

timeout_seconds = int(sys.argv[1])
label = sys.argv[2]
cmd = sys.argv[3:]

proc = subprocess.Popen(cmd, preexec_fn=os.setsid)
try:
    sys.exit(proc.wait(timeout=timeout_seconds))
except KeyboardInterrupt:
    print(f"Interrupted: {label}", file=sys.stderr)
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        proc.wait()
    sys.exit(130)
except subprocess.TimeoutExpired:
    print(f"Timed out after {timeout_seconds}s: {label}", file=sys.stderr)
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        proc.wait()
    sys.exit(124)
PY
}

stop_app_processes() {
  osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
  for _ in {1..20}; do
    if ! pgrep -x "$APP_NAME" >/dev/null 2>&1; then
      return
    fi
    sleep 0.25
  done
  pkill -TERM -x "$APP_NAME" >/dev/null 2>&1 || true
  for _ in {1..20}; do
    if ! pgrep -x "$APP_NAME" >/dev/null 2>&1; then
      return
    fi
    sleep 0.25
  done
  pkill -KILL -x "$APP_NAME" >/dev/null 2>&1 || true
}

cleanup_historical_intermediates() {
  if [ "$KEEP_INTERMEDIATES" = "1" ]; then
    echo "Keeping existing macOS screenshot intermediates because FFISHASIA_KEEP_MACOS_INTERMEDIATES=1."
    return
  fi

  echo
  echo "========== Cleanup: Remove historical macOS screenshot intermediates =========="
  rm -rf "$RAW_DIR" "$PREVIEW_OUTPUT_DIR"
  rm -f "$BUILD_LOG_PATH" "$PLAN_PATH"

  if [ -d "$OUTPUT_ROOT" ]; then
    find "$OUTPUT_ROOT" -mindepth 1 -maxdepth 1 -type d \
      ! -name "$(basename "$RAW_DIR")" \
      ! -name "$(basename "$PREVIEW_OUTPUT_DIR")" \
      -exec rm -rf {} +
  fi

  rm -rf "$HOME/Library/Containers/$APP_BUNDLE_ID/Data/tmp/ffishasia_macos_snapshots"
  rm -rf "$DERIVED_DATA_PATH"
  echo "Historical macOS screenshot intermediates cleaned. This run's intermediates will be kept."
}

finish_run() {
  local status=$?
  stop_app_processes
  rm -rf "$DERIVED_DATA_PATH"
  echo
  echo "========== Cleanup: Preserve current macOS screenshot intermediates =========="
  echo "Current run intermediates are kept for inspection:"
  echo "  raw screenshots: $RAW_DIR"
  echo "  rendered previews: $PREVIEW_OUTPUT_DIR"
  echo "  timestamped run dirs: $OUTPUT_ROOT/<run-id>"
  echo "  build log: $BUILD_LOG_PATH"
  echo "  capture plan: $PLAN_PATH"
  echo "Temporary build artifacts removed: $DERIVED_DATA_PATH"
  echo "Old intermediates are removed at the start of the next run."
  return "$status"
}

handle_interrupt() {
  local exit_code="$1"
  echo
  echo "Interrupted. Stopping macOS preview processes and preserving current intermediates." >&2
  stop_app_processes
  exit "$exit_code"
}

if [[ ! -f "$SNAPSHOT_SCRIPT" || ! -f "$PREVIEW_SCRIPT" ]]; then
  echo "Error: FFishAsia macOS snapshot/render scripts are missing." >&2
  exit 1
fi

cd "$ROOT_DIR"
trap finish_run EXIT
trap 'handle_interrupt 130' INT
trap 'handle_interrupt 143' TERM

cleanup_historical_intermediates

echo "========== Step 1/2: Generate macOS raw screenshots =========="
run_with_timeout "$SNAPSHOT_TIMEOUT_SECONDS" "FFishAsia macOS raw screenshots" \
  bash "$SNAPSHOT_SCRIPT"

echo
echo "========== Step 2/2: Render macOS preview images and sync Fastlane =========="
run_with_timeout "$PREVIEW_TIMEOUT_SECONDS" "FFishAsia macOS preview render and Fastlane sync" \
  bash "$PREVIEW_SCRIPT"

echo
echo "Done. Fresh FFishAsia macOS raw screenshots, preview intermediates, and Fastlane macOS previews are updated."

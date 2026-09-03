#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_ROOT="${FFISHASIA_MACOS_OUTPUT_ROOT:-$ROOT_DIR/macos_screenshots}"
RAW_DIR="$OUTPUT_ROOT/raw"
RUN_ID="$(date +%Y-%m-%d_%H%M%S)"
RUN_DIR="$OUTPUT_ROOT/$RUN_ID"
REPORT_DIR="$RUN_DIR/report"
DERIVED_DATA_PATH="${FFISHASIA_MACOS_DERIVED_DATA_PATH:-$ROOT_DIR/build-macos-snapshots}"
SCHEME="${FFISHASIA_MACOS_SCHEME:-FFishAsia}"
APP_BUNDLE_ID="com.luopeike.FFishAsia"
APP_NAME="${FFISHASIA_MACOS_APP_NAME:-Little Nature}"
WINDOW_WIDTH="${FFISHASIA_MACOS_WINDOW_WIDTH:-1120}"
WINDOW_HEIGHT="${FFISHASIA_MACOS_WINDOW_HEIGHT:-840}"
LOCALES_FILTER="${LOCALES:-}"
SCENES_FILTER="${SCENES:-}"
MODES_FILTER="${MODES:-light dark}"
BUILD_LOG_PATH="${FFISHASIA_MACOS_BUILD_LOG_PATH:-/tmp/ffishasia_macos_snapshot_build.log}"
PLAN_PATH="${FFISHASIA_MACOS_PLAN_PATH:-/tmp/ffishasia_macos_snapshot_plan.tsv}"
MODEL_ID="${FFISHASIA_SNAPSHOT_MODEL_ID:-35559c2236d04c1a80ccbe08cae863c6}"

mkdir -p "$RAW_DIR" "$RUN_DIR" "$REPORT_DIR"

cleanup() {
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

handle_signal() {
  local exit_code="$1"
  cleanup
  exit "$exit_code"
}

trap cleanup EXIT
trap 'handle_signal 130' INT
trap 'handle_signal 143' TERM

echo "Building macOS app..."
xcodebuild \
  -project "$ROOT_DIR/FFishAsia.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build >"$BUILD_LOG_PATH"

APP_PATH="$(xcodebuild -project "$ROOT_DIR/FFishAsia.xcodeproj" -scheme "$SCHEME" -configuration Debug -destination 'platform=macOS' -derivedDataPath "$DERIVED_DATA_PATH" -showBuildSettings 2>/dev/null | awk -F= '/ TARGET_BUILD_DIR =/{gsub(/^ +| +$/, "", $2); print $2; exit}')/$APP_NAME.app"
if [ ! -d "$APP_PATH" ]; then
  echo "App not found at $APP_PATH" >&2
  exit 1
fi

python3 - "$LOCALES_FILTER" "$SCENES_FILTER" "$MODES_FILTER" <<'PY' > "$PLAN_PATH"
import sys

locales_filter, scenes_filter, modes_filter = sys.argv[1:4]
locales = locales_filter.split() if locales_filter.strip() else ["zh-Hans", "zh-Hant", "en-US", "ja", "ko", "de-DE"]
requested_scenes = set(scenes_filter.split()) if scenes_filter.strip() else None
modes = modes_filter.split() if modes_filter.strip() else ["light"]
base_scenes = [
    {"id": "01-preview", "screen": "preview", "category": "all", "search": ""},
    {"id": "02-catalog", "screen": "catalog", "category": "all", "search": ""},
    {"id": "03-detail", "screen": "detail", "category": "all", "search": ""},
]
dark_scenes = [
    {"id": "01-preview", "screen": "preview", "category": "all", "search": ""},
]
for locale in locales:
    for mode in modes:
        scenes = dark_scenes if mode == "dark" else base_scenes
        for scene in scenes:
            scene_id = scene["id"] if mode == "light" else f"{scene['id']}-dark"
            if requested_scenes and scene_id not in requested_scenes and scene["id"] not in requested_scenes:
                continue
            print("\t".join([
                locale,
                scene_id,
                mode,
                scene["screen"],
                scene["category"],
                scene["search"],
            ]))
PY

set_appearance() {
  local mode="$1"
  if [ "$mode" = "dark" ]; then
    osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to true' >/dev/null
  else
    osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to false' >/dev/null
  fi
}

apple_language_for() {
  case "$1" in
    zh-Hans) echo "zh-Hans" ;;
    zh-Hant|zh-TW|zh_TW) echo "zh-Hant" ;;
    en|en-US|en_US) echo "en-US" ;;
    ja|ja-JP|ja_JP) echo "ja" ;;
    ko|ko-KR|ko_KR) echo "ko" ;;
    de|de-DE|de_DE) echo "de-DE" ;;
    *) echo "$1" ;;
  esac
}

apple_locale_for() {
  case "$1" in
    zh-Hans) echo "zh_CN" ;;
    zh-Hant|zh-TW|zh_TW) echo "zh_TW" ;;
    en|en-US|en_US) echo "en_US" ;;
    ja|ja-JP|ja_JP) echo "ja_JP" ;;
    ko|ko-KR|ko_KR) echo "ko_KR" ;;
    de|de-DE|de_DE) echo "de_DE" ;;
    *) echo "$1" ;;
  esac
}

app_language_for() {
  case "$1" in
    zh-Hans) echo "zh-Hans" ;;
    zh-Hant|zh-TW|zh_TW) echo "zh-Hant" ;;
    en|en-US|en_US) echo "en" ;;
    ja|ja-JP|ja_JP) echo "ja" ;;
    ko|ko-KR|ko_KR) echo "ko" ;;
    de|de-DE|de_DE) echo "de" ;;
    *) echo "en" ;;
  esac
}

slug_for() {
  case "$1" in
    zh-Hans) echo "zh_Hans" ;;
    zh-Hant|zh-TW|zh_TW) echo "zh_Hant" ;;
    en|en-US|en_US) echo "en_US" ;;
    ja|ja-JP|ja_JP) echo "ja" ;;
    ko|ko-KR|ko_KR) echo "ko" ;;
    de|de-DE|de_DE) echo "de_DE" ;;
    *) echo "$1" | tr '-' '_' ;;
  esac
}

category_arg_for() {
  case "$1" in
    plant|animal|special) echo "FFISH_SNAPSHOT_CATEGORY=$1" ;;
    *) echo "" ;;
  esac
}

launch_scene() {
  local locale="$1"
  local scene="$2"
  local mode="$3"
  local screen="$4"
  local category="$5"
  local search="$6"
  local language locale_id app_language appearance_arg category_arg
  language="$(apple_language_for "$locale")"
  locale_id="$(apple_locale_for "$locale")"
  app_language="$(app_language_for "$locale")"
  appearance_arg="-forceLightMode"
  if [ "$mode" = "dark" ]; then
    appearance_arg="-forceDarkMode"
  fi
  category_arg="$(category_arg_for "$category")"

  cleanup
  set_appearance "$mode"
  defaults write "$APP_BUNDLE_ID" hasSeenOnboarding -bool YES
  defaults write "$APP_BUNDLE_ID" appLanguage "$app_language"
  local snapshot_args=(
    -AppleLanguages "($language)" \
    -AppleLocale "$locale_id" \
    -ApplePersistenceIgnoreState YES \
    "$appearance_arg" \
    "FFISH_SNAPSHOT_SCREEN=$screen" \
    "FFISH_SNAPSHOT_MODEL_ID=$MODEL_ID" \
    "FFISH_SNAPSHOT_APP_LANGUAGE=$app_language"
  )
  if [ -n "$search" ]; then
    snapshot_args+=("FFISH_SNAPSHOT_SEARCH=$search")
  fi
  if [ -n "$category_arg" ]; then
    snapshot_args+=("$category_arg")
  fi
  if [ "$screen" = "downloads" ]; then
    snapshot_args+=("FFISH_SNAPSHOT_SEEDED_DOWNLOADS=true")
  fi

  "$APP_PATH/Contents/MacOS/$APP_NAME" "${snapshot_args[@]}" >/dev/null 2>&1 &
  sleep "${FFISHASIA_MACOS_LAUNCH_DELAY:-1}"
}

capture_front_window() {
  local output="$1"
  local helper="$RUN_DIR/capture_window.swift"
  cat > "$helper" <<'SWIFT'
import CoreGraphics
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    fputs("usage: capture_window.swift <app-name> <output>\n", stderr)
    exit(2)
}

let appName = arguments[1]
let output = arguments[2]
let ownerNames = Set([appName, "Little Nature", "小小自然", "小さな自然"])

func candidateWindows() -> [[String: Any]] {
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
        return []
    }
    return windows.filter { window in
        let owner = window[kCGWindowOwnerName as String] as? String ?? ""
        let layer = window[kCGWindowLayer as String] as? Int ?? 0
        let bounds = window[kCGWindowBounds as String] as? [String: Any] ?? [:]
        let width = bounds["Width"] as? CGFloat ?? 0
        let height = bounds["Height"] as? CGFloat ?? 0
        return ownerNames.contains(owner) && layer == 0 && width > 700 && height > 500
    }
}

for _ in 0..<60 {
    let windows = candidateWindows()
    if let window = windows.first,
       let windowID = window[kCGWindowNumber as String] as? UInt32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-l", String(windowID), output]
        do {
            try process.run()
            process.waitUntilExit()
            exit(process.terminationStatus)
        } catch {
            fputs("screencapture failed: \(error)\n", stderr)
            exit(1)
        }
    }
    Thread.sleep(forTimeInterval: 0.4)
}

exit(3)
SWIFT

  if swift "$helper" "$APP_NAME" "$output" >/dev/null 2>&1; then
    return
  fi

  python3 - "$APP_NAME" "$output" <<'PY'
import pathlib
import subprocess
import sys

app_name, output = sys.argv[1:3]
script = f'''
tell application "System Events"
  tell process "{app_name}"
    repeat 60 times
      if exists window 1 then
        set windowPosition to position of window 1
        set windowSize to size of window 1
        return (item 1 of windowPosition as text) & "," & (item 2 of windowPosition as text) & "," & (item 1 of windowSize as text) & "," & (item 2 of windowSize as text)
      end if
      delay 0.4
    end repeat
  end tell
end tell
'''
pathlib.Path(output).parent.mkdir(parents=True, exist_ok=True)
result = subprocess.run(["osascript", "-e", script], check=True, text=True, capture_output=True)
rect = result.stdout.strip()
if not rect:
    raise SystemExit(f"Could not find a {app_name} macOS window to capture")
subprocess.run(["screencapture", "-x", "-R", rect, output], check=True)
PY
}

while IFS=$'\t' read -r locale scene mode screen category search; do
  [ -n "$locale" ] || continue
  slug="$(slug_for "$locale")"
  output="$RAW_DIR/macos_${slug}_${scene}.png"
  debug="$RAW_DIR/macos_${slug}_${scene}.debug.txt"

  echo "Capturing macOS $locale / $scene / $mode..."
  launch_scene "$locale" "$scene" "$mode" "$screen" "$category" "$search"
  sleep "${FFISHASIA_MACOS_SCENE_DELAY:-4}"
  capture_front_window "$output"
  {
    echo "locale=$locale"
    echo "scene=$scene"
    echo "mode=$mode"
    echo "screen=$screen"
    echo "category=$category"
    echo "search=$search"
    echo "output=$output"
  } > "$debug"
  cp "$output" "$RUN_DIR/"
  cp "$debug" "$RUN_DIR/"
done < "$PLAN_PATH"

python3 - "$RUN_DIR" "$REPORT_DIR" <<'PY'
import hashlib
import json
import pathlib
import sys

run_dir = pathlib.Path(sys.argv[1])
report_dir = pathlib.Path(sys.argv[2])
images = []
for path in sorted(run_dir.glob("*.png")):
    images.append({
        "file": path.name,
        "bytes": path.stat().st_size,
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest()[:16],
    })
report_dir.mkdir(parents=True, exist_ok=True)
(report_dir / "manifest.json").write_text(json.dumps({
    "flow_name": "ffishasia_macos_snapshots",
    "run_dir": str(run_dir),
    "images": images,
}, indent=2), encoding="utf-8")
PY

echo "RUN_DIR=$RUN_DIR"

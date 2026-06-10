#!/bin/bash
set -euo pipefail

INPUT_DEVICE="${1:-iPhone 17 Pro Max}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_BASE_DIR="$PROJECT_DIR/maestro_screenshots"
APP_BUNDLE_ID="com.luopeike.FFishAsia"
SCHEME="FFishAsia"
DERIVED_DATA_PATH="$PROJECT_DIR/build"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug-iphonesimulator/FFishAsia.app"
SCREENSHOT_DELAY="${FFISH_STATIC_SCREENSHOT_DELAY:-4}"
MODEL_ID="${FFISH_SNAPSHOT_MODEL_ID:-f5e6f5a985ea4fc2a14ee0b4b37572b5}"

resolve_device_id() {
  if [[ "$INPUT_DEVICE" =~ ^[0-9A-F-]{36}$ ]]; then
    echo "$INPUT_DEVICE"
    return
  fi

  python3 - "$INPUT_DEVICE" <<'PY'
import re, subprocess, sys
name = sys.argv[1]
out = subprocess.check_output(["xcrun", "simctl", "list", "devices", "available"], text=True)
current_runtime = None
matches = []
for line in out.splitlines():
    header = re.match(r'^-- iOS ([0-9]+(?:\.[0-9]+)?) --$', line.strip())
    if header:
        current_runtime = tuple(int(x) for x in header.group(1).split('.'))
        continue
    if line.startswith("    " + name + " ("):
        m = re.search(r'[0-9A-F]{8}(?:-[0-9A-F]{4}){3}-[0-9A-F]{12}', line)
        if m:
            matches.append((current_runtime or (0,), m.group(0)))
if matches:
    matches.sort()
    print(matches[-1][1])
PY
}

locale_to_apple_language() {
  case "$1" in
    zh-Hans) echo "zh-Hans" ;;
    zh-Hant|zh-TW|zh_TW) echo "zh-Hant" ;;
    ja|ja-JP|ja_JP) echo "ja" ;;
    ko|ko-KR|ko_KR) echo "ko" ;;
    de|de-DE|de_DE) echo "de-DE" ;;
    en|en-US|en_US) echo "en-US" ;;
    *) echo "$1" ;;
  esac
}

locale_to_apple_locale() {
  case "$1" in
    zh-Hans) echo "zh_CN" ;;
    zh-Hant|zh-TW|zh_TW) echo "zh_TW" ;;
    ja|ja-JP|ja_JP) echo "ja_JP" ;;
    ko|ko-KR|ko_KR) echo "ko_KR" ;;
    de|de-DE|de_DE) echo "de_DE" ;;
    en|en-US|en_US) echo "en_US" ;;
    *) echo "$1" ;;
  esac
}

locale_to_slug() {
  case "$1" in
    zh-Hans) echo "zh_Hans" ;;
    zh-Hant|zh-TW|zh_TW) echo "zh_Hant" ;;
    ja|ja-JP|ja_JP) echo "ja" ;;
    ko|ko-KR|ko_KR) echo "ko" ;;
    de|de-DE|de_DE) echo "de_DE" ;;
    en|en-US|en_US) echo "en_US" ;;
    *) echo "${1//-/_}" ;;
  esac
}

locale_to_app_language() {
  case "$1" in
    zh-Hans) echo "zh-Hans" ;;
    zh-Hant|zh-TW|zh_TW) echo "zh-Hant" ;;
    ja|ja-JP|ja_JP) echo "ja" ;;
    ko|ko-KR|ko_KR) echo "ko" ;;
    de|de-DE|de_DE) echo "de" ;;
    en|en-US|en_US) echo "en" ;;
    *) echo "en" ;;
  esac
}

DEVICE_ID="$(resolve_device_id)"
if [ -z "$DEVICE_ID" ]; then
  echo "❌ Error: Could not find device matching '$INPUT_DEVICE'" >&2
  exit 1
fi

SHORT_NAME="${SCREENSHOT_DEVICE_PREFIX:-$(echo "$INPUT_DEVICE" | sed -e 's/iPhone //g' -e 's/iPad //g' -e 's/ Pro Max/pm/g' -e 's/ Pro/p/g' -e 's/ Air/air/g' -e 's/13-inch/13/g' -e 's/11-inch/11/g' -e 's/ //g' | tr '[:upper:]' '[:lower:]' | tr -d '()')}"
LOCALES="${LOCALES:-en-US}"
MODES="${MODES:-light}"
SCREENS="${SCREENS:-catalog detail downloads}"

cd "$PROJECT_DIR"

echo "🛠️ Building latest FFishAsia for simulator..."
xcodebuild \
  -workspace "$PROJECT_DIR/FFishAsia.xcworkspace" \
  -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,id=$DEVICE_ID" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build >/tmp/ffishasia_snapshot_build.log && tail -n 20 /tmp/ffishasia_snapshot_build.log

if [ ! -d "$APP_PATH" ]; then
  echo "❌ App not found at $APP_PATH after build" >&2
  exit 1
fi

echo "📍 Using Device: $INPUT_DEVICE ($DEVICE_ID)"
xcrun simctl bootstatus "$DEVICE_ID" -b
xcrun simctl terminate "$DEVICE_ID" "$APP_BUNDLE_ID" >/dev/null 2>&1 || true
if xcrun simctl get_app_container "$DEVICE_ID" "$APP_BUNDLE_ID" >/dev/null 2>&1; then
  xcrun simctl uninstall "$DEVICE_ID" "$APP_BUNDLE_ID" || true
fi
xcrun simctl install "$DEVICE_ID" "$APP_PATH"

mkdir -p "$OUTPUT_BASE_DIR"

capture_screen() {
  local locale="$1"
  local mode="$2"
  local screen="$3"
  local locale_slug apple_language apple_locale app_language prefix out
  locale_slug="$(locale_to_slug "$locale")"
  apple_language="$(locale_to_apple_language "$locale")"
  apple_locale="$(locale_to_apple_locale "$locale")"
  app_language="$(locale_to_app_language "$locale")"
  prefix="${SHORT_NAME}_${locale_slug}_${mode}"
  out="$OUTPUT_BASE_DIR/${prefix}_${screen}.png"
  local snapshot_args=(
    "FFISH_SNAPSHOT_SCREEN=$screen"
    "FFISH_SNAPSHOT_MODEL_ID=$MODEL_ID"
  )
  if [ "$screen" = "downloads" ]; then
    snapshot_args+=("FFISH_SNAPSHOT_SEEDED_DOWNLOADS=true")
  fi

  echo "🎬 Capturing $locale / $mode / $screen -> $out"
  xcrun simctl ui "$DEVICE_ID" appearance "$mode"
  xcrun simctl spawn "$DEVICE_ID" defaults write "$APP_BUNDLE_ID" hasSeenOnboarding -bool YES
  xcrun simctl spawn "$DEVICE_ID" defaults write "$APP_BUNDLE_ID" appLanguage "$app_language"
  xcrun simctl spawn "$DEVICE_ID" defaults write NSGlobalDomain AppleLanguages -array "$apple_language"
  xcrun simctl spawn "$DEVICE_ID" defaults write NSGlobalDomain AppleLocale "$apple_locale"
  xcrun simctl terminate "$DEVICE_ID" "$APP_BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl launch \
    --terminate-running-process \
    "$DEVICE_ID" \
    "$APP_BUNDLE_ID" \
    -AppleLanguages "($apple_language)" \
    -AppleLocale "$apple_locale" \
    "${snapshot_args[@]}" >/dev/null
  sleep "$SCREENSHOT_DELAY"
  xcrun simctl io "$DEVICE_ID" screenshot "$out" >/dev/null
}

for locale in $LOCALES; do
  for mode in $MODES; do
    for screen in $SCREENS; do
      capture_screen "$locale" "$mode" "$screen"
    done
  done
done

xcrun simctl terminate "$DEVICE_ID" "$APP_BUNDLE_ID" >/dev/null 2>&1 || true

echo "✅ Screenshots generated in $OUTPUT_BASE_DIR"
ls -1 "$OUTPUT_BASE_DIR" | sed 's/^/  - /'

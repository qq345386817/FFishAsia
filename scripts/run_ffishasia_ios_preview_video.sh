#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FASTLANE_DIR="${FFISHASIA_IOS_FASTLANE_SCREENSHOTS_DIR:-$ROOT_DIR/fastlane/screenshots}"
DERIVED_DATA_PATH="${FFISHASIA_IOS_VIDEO_DERIVED_DATA_PATH:-$ROOT_DIR/build-ios-preview-video}"
WORK_DIR="${FFISHASIA_IOS_VIDEO_WORK_DIR:-$ROOT_DIR/ios_preview_video}"
APP_BUNDLE_ID="${FFISHASIA_IOS_APP_BUNDLE_ID:-com.luopeike.FFishAsia}"
SCHEME="${FFISHASIA_IOS_SCHEME:-FFishAsia}"
CONFIGURATION="${FFISHASIA_IOS_CONFIGURATION:-Debug}"
DEVICE_NAME="${1:-${FFISHASIA_IOS_VIDEO_DEVICE:-iPhone 17 Pro Max}}"
LOCALES_FILTER="${LOCALES:-en-US}"
USE_TEMP_SIMULATOR="${FFISHASIA_IOS_VIDEO_USE_TEMP_SIMULATOR:-1}"
TEMP_DEVICE_ID=""
if [[ "$DEVICE_NAME" == *iPad* ]]; then
  DEVICE_LABEL="${FFISHASIA_IOS_VIDEO_DEVICE_LABEL:-iPad}"
  FASTLANE_DEVICE_PREFIX="${FFISHASIA_IOS_VIDEO_FASTLANE_PREFIX:-IPAD_PRO_3GEN_129-}"
  DEFAULT_OUTPUT_WIDTH=1200
  DEFAULT_OUTPUT_HEIGHT=1600
else
  DEVICE_LABEL="${FFISHASIA_IOS_VIDEO_DEVICE_LABEL:-iPhone}"
  FASTLANE_DEVICE_PREFIX="${FFISHASIA_IOS_VIDEO_FASTLANE_PREFIX:-IPHONE_67-}"
  DEFAULT_OUTPUT_WIDTH=886
  DEFAULT_OUTPUT_HEIGHT=1920
fi
MODEL_ID="${FFISHASIA_IOS_VIDEO_MODEL_ID:-35559c2236d04c1a80ccbe08cae863c6}"
MODEL_FILE="${FFISHASIA_IOS_VIDEO_MODEL_FILE:-japanese_freshwater_crab_lowpoly.usdz}"
MODEL_SOURCE="${FFISHASIA_IOS_VIDEO_MODEL_SOURCE:-$ROOT_DIR/usdz_resources/02/$MODEL_FILE}"
INTRO_SECONDS="${FFISHASIA_IOS_VIDEO_INTRO_SECONDS:-4}"
CATALOG_SECONDS="${FFISHASIA_IOS_VIDEO_CATALOG_SECONDS:-12}"
MODEL_SECONDS="${FFISHASIA_IOS_VIDEO_MODEL_SECONDS:-10}"
MODEL_LOAD_SECONDS="${FFISHASIA_IOS_VIDEO_MODEL_LOAD_SECONDS:-10}"
MODEL_PREROLL_SECONDS="${FFISHASIA_IOS_VIDEO_MODEL_PREROLL_SECONDS:-3}"
OUTRO_SECONDS="${FFISHASIA_IOS_VIDEO_OUTRO_SECONDS:-4}"
FFMPEG_PATH="$(command -v ffmpeg 2>/dev/null || true)"
FFPROBE_PATH="$(command -v ffprobe 2>/dev/null || true)"
MAGICK_PATH="$(command -v magick 2>/dev/null || true)"

if [ -z "$FFMPEG_PATH" ] || [ -z "$FFPROBE_PATH" ]; then
  echo "ffmpeg and ffprobe are required to generate the iOS preview video." >&2
  exit 1
fi

if [ -z "$MAGICK_PATH" ]; then
  echo "ImageMagick 'magick' is required to render localized video captions." >&2
  exit 1
fi

if [ ! -f "$MODEL_SOURCE" ]; then
  echo "Missing local USDZ model for preview video: $MODEL_SOURCE" >&2
  exit 1
fi

resolve_device_id() {
  if [[ "$DEVICE_NAME" =~ ^[0-9A-F-]{36}$ ]]; then
    echo "$DEVICE_NAME"
    return
  fi

  python3 - "$DEVICE_NAME" <<'PY'
import re
import subprocess
import sys

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
        match = re.search(r'[0-9A-F]{8}(?:-[0-9A-F]{4}){3}-[0-9A-F]{12}', line)
        if match:
            matches.append((current_runtime or (0,), match.group(0)))
if matches:
    matches.sort()
    print(matches[-1][1])
PY
}

device_metadata() {
  python3 - "$1" <<'PY'
import json
import subprocess
import sys

target = sys.argv[1]
devices = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"], text=True))
for runtime, items in devices.get("devices", {}).items():
    for device in items:
        if device.get("udid") == target:
            device_type = device.get("deviceTypeIdentifier")
            if not device_type:
                raise SystemExit(f"Missing deviceTypeIdentifier for simulator {target}")
            print(f"{runtime} {device_type}")
            raise SystemExit(0)
raise SystemExit(f"Could not find simulator metadata for {target}")
PY
}

create_temporary_simulator() {
  local source_device_id="$1"
  local runtime device_type temp_name
  read -r runtime device_type < <(device_metadata "$source_device_id")
  temp_name="FFishAsia Preview ${DEVICE_LABEL} $$"
  TEMP_DEVICE_ID="$(xcrun simctl create "$temp_name" "$device_type" "$runtime")"
  DEVICE_ID="$TEMP_DEVICE_ID"
  echo "Created temporary simulator: $temp_name ($TEMP_DEVICE_ID)"
}

locale_to_apple_language() {
  case "$1" in
    zh-Hans) echo "zh-Hans" ;;
    zh-Hant) echo "zh-Hant" ;;
    ja) echo "ja" ;;
    ko) echo "ko" ;;
    de-DE) echo "de-DE" ;;
    en-US) echo "en-US" ;;
    *) echo "$1" ;;
  esac
}

locale_to_apple_locale() {
  case "$1" in
    zh-Hans) echo "zh_CN" ;;
    zh-Hant) echo "zh_TW" ;;
    ja) echo "ja_JP" ;;
    ko) echo "ko_KR" ;;
    de-DE) echo "de_DE" ;;
    en-US) echo "en_US" ;;
    *) echo "$1" ;;
  esac
}

locale_to_app_language() {
  case "$1" in
    zh-Hans) echo "zh-Hans" ;;
    zh-Hant) echo "zh-Hant" ;;
    ja) echo "ja" ;;
    ko) echo "ko" ;;
    de-DE) echo "de" ;;
    en-US) echo "en" ;;
    *) echo "en" ;;
  esac
}

font_for_locale() {
  case "$1" in
    ko)
      for font in \
        "/System/Library/Fonts/AppleSDGothicNeo.ttc" \
        "/System/Library/Fonts/Supplemental/AppleGothic.ttf"; do
        [ -f "$font" ] && echo "$font" && return
      done
      ;;
    zh-Hans|zh-Hant|ja)
      for font in \
        "/System/Library/Fonts/PingFang.ttc" \
        "/System/Library/Fonts/STHeiti Light.ttc" \
        "/System/Library/Fonts/Supplemental/Arial Unicode.ttf"; do
        [ -f "$font" ] && echo "$font" && return
      done
      ;;
  esac

  for font in \
    "/System/Library/Fonts/Supplemental/Arial Bold.ttf" \
    "/Library/Fonts/Arial Bold.ttf" \
    "/System/Library/Fonts/Supplemental/Arial.ttf"; do
    [ -f "$font" ] && echo "$font" && return
  done
  echo "Arial"
}

localized_text() {
  local locale="$1"
  local key="$2"
  case "$locale:$key" in
    zh-Hans:intro_title) echo "Little Nature" ;;
    zh-Hans:intro_caption) echo "用 3D 模型探索亚洲动植物与自然。" ;;
    zh-Hans:catalog_caption) echo "在 ${DEVICE_LABEL} 上浏览亚洲动植物的 3D 模型。" ;;
    zh-Hans:model_caption) echo "打开 3D 预览，查看会动的模型细节。" ;;
    zh-Hans:outro_title) echo "用 3D 重新认识自然" ;;
    zh-Hans:outro_caption) echo "按需下载模型，离线查看，并继续发现更多物种。" ;;

    zh-Hant:intro_title) echo "Little Nature" ;;
    zh-Hant:intro_caption) echo "用 3D 模型探索亞洲動植物與自然。" ;;
    zh-Hant:catalog_caption) echo "在 ${DEVICE_LABEL} 上瀏覽亞洲動植物的 3D 模型。" ;;
    zh-Hant:model_caption) echo "開啟 3D 預覽，查看會動的模型細節。" ;;
    zh-Hant:outro_title) echo "用 3D 重新認識自然" ;;
    zh-Hant:outro_caption) echo "按需下載模型，離線查看，並繼續發現更多物種。" ;;

    ja:intro_title) echo "Little Nature" ;;
    ja:intro_caption) echo "3Dモデルでアジアの動植物と自然を探索。" ;;
    ja:catalog_caption) echo "${DEVICE_LABEL}でアジアの動植物の3Dモデルを閲覧。" ;;
    ja:model_caption) echo "3Dプレビューで動きのあるモデルを確認。" ;;
    ja:outro_title) echo "自然を3Dで再発見" ;;
    ja:outro_caption) echo "モデルをダウンロードしてオフラインでも閲覧し、さらに多くの種を探索できます。" ;;

    ko:intro_title) echo "Little Nature" ;;
    ko:intro_caption) echo "3D 모델로 아시아 동식물과 자연을 탐색하세요." ;;
    ko:catalog_caption) echo "${DEVICE_LABEL}에서 아시아 동식물 3D 모델을 둘러보세요." ;;
    ko:model_caption) echo "3D 미리보기로 움직이는 모델의 세부 모습을 확인하세요." ;;
    ko:outro_title) echo "자연을 3D로 다시 보기" ;;
    ko:outro_caption) echo "모델을 다운로드해 오프라인으로 보고, 더 많은 종을 계속 탐색하세요." ;;

    de-DE:intro_title) echo "Little Nature" ;;
    de-DE:intro_caption) echo "Asiatische Tiere, Pflanzen und Natur in 3D entdecken." ;;
    de-DE:catalog_caption) echo "3D-Modelle asiatischer Tiere und Pflanzen auf dem ${DEVICE_LABEL} ansehen." ;;
    de-DE:model_caption) echo "Die 3D-Vorschau zeigt animierte Modelldetails." ;;
    de-DE:outro_title) echo "Natur in 3D entdecken" ;;
    de-DE:outro_caption) echo "Modelle laden, offline ansehen und weitere Arten entdecken." ;;

    en-US:intro_title|*:intro_title) echo "Little Nature" ;;
    en-US:intro_caption|*:intro_caption) echo "Explore Asian animals, plants, and nature in detailed 3D." ;;
    en-US:catalog_caption|*:catalog_caption) echo "Browse 3D models of Asian plants and animals on ${DEVICE_LABEL}." ;;
    en-US:model_caption|*:model_caption) echo "Open the 3D preview to watch animated model details." ;;
    en-US:outro_title|*:outro_title) echo "Explore nature in 3D" ;;
    en-US:outro_caption|*:outro_caption) echo "Download models for offline viewing, then keep discovering more species." ;;
  esac
}

detect_output_size() {
  local sample="$1"
  if [ -f "$sample" ]; then
    local width height
    width="$(sips -g pixelWidth "$sample" 2>/dev/null | awk '/pixelWidth/ {print $2; exit}')"
    height="$(sips -g pixelHeight "$sample" 2>/dev/null | awk '/pixelHeight/ {print $2; exit}')"
    if [ -n "$width" ] && [ -n "$height" ]; then
      echo "$width $height"
      return
    fi
  fi
  echo "${FFISHASIA_IOS_VIDEO_WIDTH:-1320} ${FFISHASIA_IOS_VIDEO_HEIGHT:-2868}"
}

cleanup() {
  local status=$?
  if [ -n "${DEVICE_ID:-}" ]; then
    xcrun simctl terminate "$DEVICE_ID" "$APP_BUNDLE_ID" >/dev/null 2>&1 || true
  fi
  if [ -n "${TEMP_DEVICE_ID:-}" ]; then
    xcrun simctl shutdown "$TEMP_DEVICE_ID" >/dev/null 2>&1 || true
    xcrun simctl delete "$TEMP_DEVICE_ID" >/dev/null 2>&1 || true
    echo "Deleted temporary simulator: $TEMP_DEVICE_ID"
  fi
  rm -rf "$DERIVED_DATA_PATH" "$WORK_DIR"
  if [ "$status" -eq 0 ]; then
    echo "Cleaned temporary iOS preview video files."
  else
    echo "Cleaned temporary iOS preview video files after failure." >&2
  fi
  return "$status"
}

launch_snapshot_screen() {
  local locale="$1"
  local screen="$2"
  local auto_scroll="${3:-0}"
  local apple_language apple_locale app_language
  apple_language="$(locale_to_apple_language "$locale")"
  apple_locale="$(locale_to_apple_locale "$locale")"
  app_language="$(locale_to_app_language "$locale")"

  xcrun simctl ui "$DEVICE_ID" appearance light
  xcrun simctl spawn "$DEVICE_ID" defaults write "$APP_BUNDLE_ID" hasSeenOnboarding -bool YES
  xcrun simctl spawn "$DEVICE_ID" defaults write "$APP_BUNDLE_ID" appLanguage "$app_language"
  xcrun simctl spawn "$DEVICE_ID" defaults write NSGlobalDomain AppleLanguages -array "$apple_language"
  xcrun simctl spawn "$DEVICE_ID" defaults write NSGlobalDomain AppleLocale "$apple_locale"
  xcrun simctl terminate "$DEVICE_ID" "$APP_BUNDLE_ID" >/dev/null 2>&1 || true

  local snapshot_args=(
    "FFISH_SNAPSHOT_SCREEN=$screen"
    "FFISH_SNAPSHOT_MODEL_ID=$MODEL_ID"
    "FFISH_SNAPSHOT_APP_LANGUAGE=$app_language"
  )
  if [ "$auto_scroll" = "1" ]; then
    snapshot_args+=("FFISH_SNAPSHOT_AUTOSCROLL=1")
    snapshot_args+=("FFISH_SNAPSHOT_AUTOSCROLL_STYLE=slow")
  fi

  xcrun simctl launch \
    --terminate-running-process \
    "$DEVICE_ID" \
    "$APP_BUNDLE_ID" \
    -AppleLanguages "($apple_language)" \
    -AppleLocale "$apple_locale" \
    "${snapshot_args[@]}" >/dev/null
}

record_simulator_video() {
  local output="$1"
  local seconds="$2"
  local status_file="$WORK_DIR/raw/$(basename "$output").record.log"
  local waited=0

  rm -f "$output"
  rm -f "$status_file"
  xcrun simctl io "$DEVICE_ID" recordVideo --codec=h264 --force "$output" 2>"$status_file" &
  local record_pid=$!
  until grep -q "Recording started" "$status_file" 2>/dev/null; do
    if ! kill -0 "$record_pid" >/dev/null 2>&1; then
      cat "$status_file" >&2 || true
      echo "Failed to start simulator video recording: $output" >&2
      exit 1
    fi
    if [ "$waited" -ge 30 ]; then
      cat "$status_file" >&2 || true
      echo "Timed out waiting for simulator video recording to start: $output" >&2
      kill -INT "$record_pid" >/dev/null 2>&1 || true
      wait "$record_pid" >/dev/null 2>&1 || true
      exit 1
    fi
    sleep 1
    waited=$((waited + 1))
  done

  sleep "$seconds"
  kill -INT "$record_pid" >/dev/null 2>&1 || true
  wait "$record_pid" >/dev/null 2>&1 || true
  cat "$status_file" || true

  if [ ! -s "$output" ]; then
    echo "Failed to record simulator video: $output" >&2
    exit 1
  fi
}

seed_preview_model() {
  local data_container
  data_container="$(xcrun simctl get_app_container "$DEVICE_ID" "$APP_BUNDLE_ID" data 2>/dev/null || true)"
  if [ -z "$data_container" ]; then
    xcrun simctl launch --terminate-running-process "$DEVICE_ID" "$APP_BUNDLE_ID" >/dev/null
    sleep 1
    xcrun simctl terminate "$DEVICE_ID" "$APP_BUNDLE_ID" >/dev/null 2>&1 || true
    data_container="$(xcrun simctl get_app_container "$DEVICE_ID" "$APP_BUNDLE_ID" data)"
  fi

  local models_dir="$data_container/Library/Application Support/FFishAsia/Models"
  mkdir -p "$models_dir"
  cp "$MODEL_SOURCE" "$models_dir/$MODEL_FILE"
}

render_caption_overlay() {
  local locale="$1"
  local text="$2"
  local output="$3"
  local font caption_width caption_height point_size bottom_offset
  font="$(font_for_locale "$locale")"
  caption_width=$((OUTPUT_WIDTH - 180))
  caption_height=$((OUTPUT_HEIGHT / 14))
  point_size=$((OUTPUT_WIDTH / 26))
  bottom_offset=$((OUTPUT_HEIGHT / 36))

  "$MAGICK_PATH" \
    -size "${OUTPUT_WIDTH}x${OUTPUT_HEIGHT}" xc:none \
    \( -size "${caption_width}x${caption_height}" -background "#0B1512E6" -fill "#F6FBF8" -font "$font" -pointsize "$point_size" -gravity center caption:"$text" \) \
    -gravity south -geometry "+0+${bottom_offset}" -composite \
    "png32:$output"
}

render_title_card() {
  local locale="$1"
  local title="$2"
  local caption="$3"
  local source_image="$4"
  local output="$5"
  local font title_width caption_width title_height caption_height title_size caption_size
  font="$(font_for_locale "$locale")"
  title_width=$((OUTPUT_WIDTH - 180))
  caption_width=$((OUTPUT_WIDTH - 210))
  title_height=$((OUTPUT_HEIGHT / 9))
  caption_height=$((OUTPUT_HEIGHT / 11))
  title_size=$((OUTPUT_WIDTH / 13))
  caption_size=$((OUTPUT_WIDTH / 27))

  if [ -f "$source_image" ]; then
    "$MAGICK_PATH" "$source_image" \
      -resize "${OUTPUT_WIDTH}x${OUTPUT_HEIGHT}^" \
      -gravity center \
      -extent "${OUTPUT_WIDTH}x${OUTPUT_HEIGHT}" \
      -blur 0x8 \
      -fill "#081410B8" -colorize 62% \
      \( -size "${title_width}x${title_height}" -background none -fill "#F6FBF8" -font "$font" -pointsize "$title_size" -gravity center caption:"$title" \) \
      -gravity center -geometry +0-$((OUTPUT_HEIGHT / 18)) -composite \
      \( -size "${caption_width}x${caption_height}" -background none -fill "#D2E1DC" -font "$font" -pointsize "$caption_size" -gravity center caption:"$caption" \) \
      -gravity center -geometry +0+$((OUTPUT_HEIGHT / 24)) -composite \
      "png32:$output"
  else
    "$MAGICK_PATH" -size "${OUTPUT_WIDTH}x${OUTPUT_HEIGHT}" "gradient:#10211D-#2F574D" \
      \( -size "${title_width}x${title_height}" -background none -fill "#F6FBF8" -font "$font" -pointsize "$title_size" -gravity center caption:"$title" \) \
      -gravity center -geometry +0-$((OUTPUT_HEIGHT / 18)) -composite \
      \( -size "${caption_width}x${caption_height}" -background none -fill "#D2E1DC" -font "$font" -pointsize "$caption_size" -gravity center caption:"$caption" \) \
      -gravity center -geometry +0+$((OUTPUT_HEIGHT / 24)) -composite \
      "png32:$output"
  fi
}

encode_static_segment() {
  local image="$1"
  local seconds="$2"
  local output="$3"
  "$FFMPEG_PATH" -y \
    -loop 1 \
    -t "$seconds" \
    -i "$image" \
    -vf "format=yuv420p,fps=30" \
    -c:v libx264 \
    -profile:v high \
    -level 5.1 \
    -preset slow \
    -crf 18 \
    -movflags +faststart \
    -an \
    "$output"
}

encode_recorded_segment() {
  local raw="$1"
  local caption_overlay="$2"
  local seconds="$3"
  local output="$4"
  local trim_start="${5:-0}"
  local ffmpeg_args=()
  if [ "$trim_start" != "0" ] && [ "$trim_start" != "0.0" ]; then
    ffmpeg_args=(-ss "$trim_start")
  fi

  "$FFMPEG_PATH" -y \
    "${ffmpeg_args[@]+"${ffmpeg_args[@]}"}" \
    -i "$raw" \
    -i "$caption_overlay" \
    -t "$seconds" \
    -filter_complex "[0:v]scale=${OUTPUT_WIDTH}:${OUTPUT_HEIGHT}:force_original_aspect_ratio=decrease:flags=lanczos,pad=${OUTPUT_WIDTH}:${OUTPUT_HEIGHT}:(ow-iw)/2:(oh-ih)/2:color=0x101816[base];[base][1:v]overlay=0:0,format=yuv420p,fps=30[v]" \
    -map "[v]" \
    -c:v libx264 \
    -profile:v high \
    -level 5.1 \
    -preset slow \
    -crf 18 \
    -movflags +faststart \
    -an \
    "$output"
}

concat_segments() {
  local list="$1"
  local output="$2"
  "$FFMPEG_PATH" -y \
    -f concat \
    -safe 0 \
    -i "$list" \
    -c copy \
    -movflags +faststart \
    "$output"
}

add_music_track() {
  local video_input="$1"
  local output="$2"
  local duration fade_out_start
  duration="$("$FFPROBE_PATH" -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$video_input")"
  fade_out_start="$(python3 - "$duration" <<'PY'
import sys

duration = float(sys.argv[1])
print(max(duration - 2.0, 0.0))
PY
)"

  "$FFMPEG_PATH" -y \
    -i "$video_input" \
    -f lavfi -i "sine=frequency=220:sample_rate=44100:duration=$duration" \
    -f lavfi -i "sine=frequency=277.18:sample_rate=44100:duration=$duration" \
    -f lavfi -i "sine=frequency=329.63:sample_rate=44100:duration=$duration" \
    -filter_complex "[1:a][2:a][3:a]amix=inputs=3:duration=longest,volume=0.05,afade=t=in:st=0:d=1,afade=t=out:st=$fade_out_start:d=2,pan=stereo|c0=c0|c1=c0[a]" \
    -map 0:v \
    -map "[a]" \
    -c:v copy \
    -c:a aac_at \
    -b:a 256k \
    -ar 44100 \
    -ac 2 \
    -shortest \
    -movflags +faststart \
    "$output"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

DEVICE_ID="$(resolve_device_id)"
if [ -z "$DEVICE_ID" ]; then
  echo "Could not find an available simulator named '$DEVICE_NAME'." >&2
  exit 1
fi
if [ "$USE_TEMP_SIMULATOR" = "1" ]; then
  create_temporary_simulator "$DEVICE_ID"
fi

cd "$ROOT_DIR"
mkdir -p "$WORK_DIR/raw" "$WORK_DIR/overlays" "$WORK_DIR/segments"

echo "========== Build iOS app for preview video =========="
xcodebuild \
  -workspace "$ROOT_DIR/FFishAsia.xcworkspace" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "platform=iOS Simulator,id=$DEVICE_ID" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build

APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION-iphonesimulator/FFishAsia.app"
if [ ! -d "$APP_PATH" ]; then
  echo "Built app not found: $APP_PATH" >&2
  exit 1
fi

echo "========== Install app on $DEVICE_NAME ($DEVICE_ID) =========="
xcrun simctl bootstatus "$DEVICE_ID" -b
xcrun simctl terminate "$DEVICE_ID" "$APP_BUNDLE_ID" >/dev/null 2>&1 || true
if xcrun simctl get_app_container "$DEVICE_ID" "$APP_BUNDLE_ID" >/dev/null 2>&1; then
  xcrun simctl uninstall "$DEVICE_ID" "$APP_BUNDLE_ID" || true
fi
xcrun simctl install "$DEVICE_ID" "$APP_PATH"
xcrun simctl privacy "$DEVICE_ID" grant camera "$APP_BUNDLE_ID" >/dev/null 2>&1 || true
seed_preview_model

for locale in $LOCALES_FILTER; do
  fastlane_locale_dir="$FASTLANE_DIR/$locale"
  catalog_image="$fastlane_locale_dir/${FASTLANE_DEVICE_PREFIX}01-catalog.png"
  output_path="$fastlane_locale_dir/${FASTLANE_DEVICE_PREFIX}00-preview.mov"
  OUTPUT_WIDTH="${FFISHASIA_IOS_VIDEO_WIDTH:-$DEFAULT_OUTPUT_WIDTH}"
  OUTPUT_HEIGHT="${FFISHASIA_IOS_VIDEO_HEIGHT:-$DEFAULT_OUTPUT_HEIGHT}"

  intro_image="$WORK_DIR/segments/$locale-intro.png"
  outro_image="$WORK_DIR/segments/$locale-outro.png"
  intro_video="$WORK_DIR/segments/$locale-01-intro.mov"
  catalog_video="$WORK_DIR/segments/$locale-02-catalog.mov"
  model_video="$WORK_DIR/segments/$locale-03-model.mov"
  outro_video="$WORK_DIR/segments/$locale-04-outro.mov"
  silent_video="$WORK_DIR/segments/$locale-silent.mov"
  concat_list="$WORK_DIR/segments/$locale-concat.txt"
  catalog_raw="$WORK_DIR/raw/$locale-catalog.mp4"
  model_raw="$WORK_DIR/raw/$locale-model.mp4"
  catalog_caption_overlay="$WORK_DIR/overlays/$locale-catalog-caption.png"
  model_caption_overlay="$WORK_DIR/overlays/$locale-model-caption.png"

  mkdir -p "$fastlane_locale_dir"

  echo
  echo "========== Render iOS App Preview video: $locale (${OUTPUT_WIDTH}x${OUTPUT_HEIGHT}) =========="
  render_title_card "$locale" \
    "$(localized_text "$locale" intro_title)" \
    "$(localized_text "$locale" intro_caption)" \
    "$catalog_image" \
    "$intro_image"
  render_title_card "$locale" \
    "$(localized_text "$locale" outro_title)" \
    "$(localized_text "$locale" outro_caption)" \
    "$catalog_image" \
    "$outro_image"
  render_caption_overlay "$locale" "$(localized_text "$locale" catalog_caption)" "$catalog_caption_overlay"
  render_caption_overlay "$locale" "$(localized_text "$locale" model_caption)" "$model_caption_overlay"

  encode_static_segment "$intro_image" "$INTRO_SECONDS" "$intro_video"

  launch_snapshot_screen "$locale" catalog 1
  sleep 1
  record_simulator_video "$catalog_raw" "$CATALOG_SECONDS"
  encode_recorded_segment "$catalog_raw" "$catalog_caption_overlay" "$CATALOG_SECONDS" "$catalog_video"

  launch_snapshot_screen "$locale" preview 0
  sleep "$MODEL_LOAD_SECONDS"
  model_record_seconds="$(python3 - "$MODEL_SECONDS" "$MODEL_PREROLL_SECONDS" <<'PY'
import sys

print(float(sys.argv[1]) + float(sys.argv[2]))
PY
)"
  record_simulator_video "$model_raw" "$model_record_seconds"
  encode_recorded_segment "$model_raw" "$model_caption_overlay" "$MODEL_SECONDS" "$model_video" "$MODEL_PREROLL_SECONDS"

  encode_static_segment "$outro_image" "$OUTRO_SECONDS" "$outro_video"

  {
    printf "file '%s'\n" "$intro_video"
    printf "file '%s'\n" "$catalog_video"
    printf "file '%s'\n" "$model_video"
    printf "file '%s'\n" "$outro_video"
  } > "$concat_list"

  concat_segments "$concat_list" "$silent_video"
  add_music_track "$silent_video" "$output_path"

  "$FFPROBE_PATH" -v error \
    -select_streams v:0 \
    -show_entries stream=width,height,duration \
    -show_entries format=duration,size \
    -of default=noprint_wrappers=1 \
    "$output_path"
  echo "Generated: $output_path"
done

echo
echo "iOS preview video generation complete."

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FASTLANE_DIR="${FFISHASIA_MACOS_FASTLANE_SCREENSHOTS_DIR:-$ROOT_DIR/fastlane/screenshots_macos}"
DERIVED_DATA_PATH="${FFISHASIA_MACOS_VIDEO_DERIVED_DATA_PATH:-$ROOT_DIR/build-macos-preview-video}"
WORK_DIR="${FFISHASIA_MACOS_VIDEO_WORK_DIR:-$ROOT_DIR/macos_preview_video}"
APP_NAME="${FFISHASIA_MACOS_APP_NAME:-Little Nature}"
APP_BUNDLE_ID="${FFISHASIA_MACOS_APP_BUNDLE_ID:-com.luopeike.FFishAsia}"
SCHEME="${FFISHASIA_MACOS_SCHEME:-FFishAsia}"
CONFIGURATION="${FFISHASIA_MACOS_CONFIGURATION:-Debug}"
LOCALES_FILTER="${LOCALES:-zh-Hans}"
MODEL_ID="${FFISHASIA_MACOS_VIDEO_MODEL_ID:-35559c2236d04c1a80ccbe08cae863c6}"
MODEL_FILE="${FFISHASIA_MACOS_VIDEO_MODEL_FILE:-japanese_freshwater_crab_lowpoly.usdz}"
MODEL_SOURCE="${FFISHASIA_MACOS_VIDEO_MODEL_SOURCE:-$ROOT_DIR/usdz_resources/02/$MODEL_FILE}"
INTRO_SECONDS="${FFISHASIA_MACOS_VIDEO_INTRO_SECONDS:-4}"
CATALOG_SECONDS="${FFISHASIA_MACOS_VIDEO_CATALOG_SECONDS:-12}"
MODEL_SECONDS="${FFISHASIA_MACOS_VIDEO_MODEL_SECONDS:-8}"
OUTRO_SECONDS="${FFISHASIA_MACOS_VIDEO_OUTRO_SECONDS:-4}"
REUSE_EXISTING_MODEL_SEGMENT="${FFISHASIA_MACOS_VIDEO_REUSE_EXISTING_MODEL_SEGMENT:-0}"
REUSE_MODEL_START="${FFISHASIA_MACOS_VIDEO_REUSE_MODEL_START:-13.5}"
REUSE_MODEL_SECONDS="${FFISHASIA_MACOS_VIDEO_REUSE_MODEL_SECONDS:-8}"
OUTPUT_WIDTH="${FFISHASIA_MACOS_VIDEO_WIDTH:-1920}"
OUTPUT_HEIGHT="${FFISHASIA_MACOS_VIDEO_HEIGHT:-1080}"
RECORD_WINDOW_WIDTH="${FFISHASIA_MACOS_VIDEO_WINDOW_WIDTH:-1280}"
RECORD_WINDOW_HEIGHT="${FFISHASIA_MACOS_VIDEO_WINDOW_HEIGHT:-900}"
WINDOW_X="${FFISHASIA_MACOS_VIDEO_WINDOW_X:-80}"
WINDOW_Y="${FFISHASIA_MACOS_VIDEO_WINDOW_Y:-120}"
CATALOG_SCROLL_START_DELAY_MS="${FFISHASIA_MACOS_VIDEO_CATALOG_SCROLL_START_DELAY_MS:-900}"
CATALOG_SCROLL_STEPS="${FFISHASIA_MACOS_VIDEO_CATALOG_SCROLL_STEPS:-48}"
CATALOG_SCROLL_DELTA="${FFISHASIA_MACOS_VIDEO_CATALOG_SCROLL_DELTA:--55}"
CATALOG_SCROLL_INTERVAL_MS="${FFISHASIA_MACOS_VIDEO_CATALOG_SCROLL_INTERVAL_MS:-220}"
FFMPEG_PATH="$(command -v ffmpeg 2>/dev/null || true)"
FFPROBE_PATH="$(command -v ffprobe 2>/dev/null || true)"
MAGICK_PATH="$(command -v magick 2>/dev/null || true)"

if [ -z "$FFMPEG_PATH" ] || [ -z "$FFPROBE_PATH" ]; then
  echo "ffmpeg and ffprobe are required to generate the macOS preview video." >&2
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

locale_to_apple_language() {
  case "$1" in
    zh-Hans) echo "zh-Hans" ;;
    zh-Hant) echo "zh-Hant" ;;
    en-US) echo "en-US" ;;
    de-DE) echo "de-DE" ;;
    ja) echo "ja" ;;
    ko) echo "ko" ;;
    *) echo "$1" ;;
  esac
}

locale_to_apple_locale() {
  case "$1" in
    zh-Hans) echo "zh_CN" ;;
    zh-Hant) echo "zh_TW" ;;
    en-US) echo "en_US" ;;
    de-DE) echo "de_DE" ;;
    ja) echo "ja_JP" ;;
    ko) echo "ko_KR" ;;
    *) echo "$1" ;;
  esac
}

locale_to_app_language() {
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
    zh-Hans:intro_caption) echo "用 3D 模型重新认识亚洲自然物种。" ;;
    zh-Hans:catalog_caption) echo "在 Mac 上浏览动物、植物和特别模型，快速找到感兴趣的物种。" ;;
    zh-Hans:model_caption) echo "打开非 AR 3D 预览，查看会动的模型细节。" ;;
    zh-Hans:outro_title) echo "把自然模型带到桌面上" ;;
    zh-Hans:outro_caption) echo "下载模型，离线查看，也可以继续探索更多物种。" ;;

    zh-Hant:intro_title) echo "Little Nature" ;;
    zh-Hant:intro_caption) echo "用 3D 模型重新認識亞洲自然物種。" ;;
    zh-Hant:catalog_caption) echo "在 Mac 上瀏覽動物、植物和特別模型，快速找到感興趣的物種。" ;;
    zh-Hant:model_caption) echo "開啟非 AR 3D 預覽，查看會動的模型細節。" ;;
    zh-Hant:outro_title) echo "把自然模型帶到桌面上" ;;
    zh-Hant:outro_caption) echo "下載模型，離線查看，也可以繼續探索更多物種。" ;;

    ja:intro_title) echo "Little Nature" ;;
    ja:intro_caption) echo "3Dモデルでアジアの自然種を見直しましょう。" ;;
    ja:catalog_caption) echo "Macで動物、植物、特別なモデルを一覧し、気になる種をすばやく探せます。" ;;
    ja:model_caption) echo "非ARの3Dプレビューで、動きのあるモデルを細部まで確認できます。" ;;
    ja:outro_title) echo "自然モデルをデスクトップへ" ;;
    ja:outro_caption) echo "モデルをダウンロードしてオフラインでも閲覧し、さらに多くの種を探索できます。" ;;

    ko:intro_title) echo "Little Nature" ;;
    ko:intro_caption) echo "3D 모델로 아시아 자연종을 새롭게 살펴보세요." ;;
    ko:catalog_caption) echo "Mac에서 동물, 식물, 특별 모델을 둘러보고 관심 있는 종을 빠르게 찾을 수 있습니다." ;;
    ko:model_caption) echo "비 AR 3D 미리보기로 움직이는 모델의 세부 모습을 확인하세요." ;;
    ko:outro_title) echo "자연 모델을 데스크톱으로" ;;
    ko:outro_caption) echo "모델을 다운로드해 오프라인으로 보고, 더 많은 종을 계속 탐색하세요." ;;

    de-DE:intro_title) echo "Little Nature" ;;
    de-DE:intro_caption) echo "Asiatische Naturarten mit 3D-Modellen neu entdecken." ;;
    de-DE:catalog_caption) echo "Tiere, Pflanzen und besondere Modelle auf dem Mac durchsuchen und Arten schnell finden." ;;
    de-DE:model_caption) echo "Die 3D-Vorschau ohne AR zeigt animierte Modelle im Detail." ;;
    de-DE:outro_title) echo "Naturmodelle auf dem Desktop" ;;
    de-DE:outro_caption) echo "Modelle laden, offline ansehen und weitere Arten entdecken." ;;

    en-US:intro_title|*:intro_title) echo "Little Nature" ;;
    en-US:intro_caption|*:intro_caption) echo "Rediscover Asian nature through detailed 3D models." ;;
    en-US:catalog_caption|*:catalog_caption) echo "Browse animals, plants, and special models on the Mac, then find species quickly." ;;
    en-US:model_caption|*:model_caption) echo "Use the non-AR 3D preview to inspect animated model details." ;;
    en-US:outro_title|*:outro_title) echo "Bring nature models to your desktop" ;;
    en-US:outro_caption|*:outro_caption) echo "Download models for offline viewing and keep exploring more species." ;;
  esac
}

stop_app_processes() {
  osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
  for _ in {1..24}; do
    if ! pgrep -x "$APP_NAME" >/dev/null 2>&1; then
      return
    fi
    sleep 0.25
  done
  pkill -TERM -x "$APP_NAME" >/dev/null 2>&1 || true
  for _ in {1..16}; do
    if ! pgrep -x "$APP_NAME" >/dev/null 2>&1; then
      return
    fi
    sleep 0.25
  done
  pkill -KILL -x "$APP_NAME" >/dev/null 2>&1 || true
}

cleanup() {
  local status=$?
  stop_app_processes
  rm -rf "$DERIVED_DATA_PATH" "$WORK_DIR"
  if [ "$status" -eq 0 ]; then
    echo "Cleaned temporary macOS preview video files."
  else
    echo "Cleaned temporary macOS preview video files after failure." >&2
  fi
  return "$status"
}

wait_for_window() {
  local tries=240
  for _ in $(seq 1 "$tries"); do
    if osascript <<OSA >/dev/null 2>&1
tell application "System Events"
  tell process "$APP_NAME"
    if exists window 1 then return
  end tell
end tell
error "window not ready"
OSA
    then
      return 0
    fi
    sleep 0.25
  done
  echo "Timed out waiting for $APP_NAME window." >&2
  return 1
}

set_window_frame() {
  osascript <<OSA >/dev/null
tell application "System Events"
  tell process "$APP_NAME"
    set frontmost to true
    set position of window 1 to {$WINDOW_X, $WINDOW_Y}
    set size of window 1 to {$RECORD_WINDOW_WIDTH, $RECORD_WINDOW_HEIGHT}
  end tell
end tell
OSA
}

move_cursor_outside_recording() {
  swift -e "import CoreGraphics; CGWarpMouseCursorPosition(CGPoint(x: 20, y: 20)); CGAssociateMouseAndMouseCursorPosition(boolean_t(1))" >/dev/null 2>&1 || true
}

activate_app_for_recording() {
  osascript <<OSA >/dev/null 2>&1 || true
tell application "$APP_NAME" to activate
tell application "System Events"
  tell process "$APP_NAME"
    set frontmost to true
  end tell
end tell
OSA
}

scroll_catalog_window() {
  local region="$1"
  local x y width height
  IFS=',' read -r x y width height <<< "$region"

  swift - "$x" "$y" "$width" "$height" "$CATALOG_SCROLL_STEPS" "$CATALOG_SCROLL_DELTA" "$CATALOG_SCROLL_INTERVAL_MS" <<'SWIFT' >/dev/null 2>&1 || true
import CoreGraphics
import Foundation

let x = Double(CommandLine.arguments[1]) ?? 0
let y = Double(CommandLine.arguments[2]) ?? 0
let width = Double(CommandLine.arguments[3]) ?? 1280
let height = Double(CommandLine.arguments[4]) ?? 900
let steps = max(Int(CommandLine.arguments[5]) ?? 48, 1)
let delta = Int32(CommandLine.arguments[6]) ?? -80
let intervalMS = max(Int(CommandLine.arguments[7]) ?? 200, 16)
let point = CGPoint(x: x + width * 0.5, y: y + height * 0.45)

usleep(200_000)

for _ in 0..<steps {
    if let event = CGEvent(
        scrollWheelEvent2Source: nil,
        units: .pixel,
        wheelCount: 1,
        wheel1: delta,
        wheel2: 0,
        wheel3: 0
    ) {
        event.location = point
        event.post(tap: .cghidEventTap)
    }
    usleep(useconds_t(intervalMS * 1_000))
}
SWIFT
}

scroll_catalog_to_top() {
  osascript <<OSA >/dev/null 2>&1 || true
tell application "System Events"
  tell process "$APP_NAME"
    set frontmost to true
    key code 115
    delay 0.2
    key code 115
  end tell
end tell
OSA
}

read_window_region() {
  osascript <<OSA
tell application "System Events"
  tell process "$APP_NAME"
    set windowPosition to position of window 1
    set windowSize to size of window 1
    return (item 1 of windowPosition as text) & "," & (item 2 of windowPosition as text) & "," & (item 1 of windowSize as text) & "," & (item 2 of windowSize as text)
  end tell
end tell
OSA
}

launch_snapshot_screen() {
  local locale="$1"
  local screen="$2"
  local apple_language="$3"
  local apple_locale="$4"
  local auto_scroll="${5:-0}"
  local app_language
  app_language="$(locale_to_app_language "$locale")"
  stop_app_processes
  defaults write "$APP_BUNDLE_ID" hasSeenOnboarding -bool YES
  defaults write "$APP_BUNDLE_ID" appLanguage "$app_language"
  open -n "$APP_PATH" --args \
    -AppleLanguages "($apple_language)" \
    -AppleLocale "$apple_locale" \
    -ApplePersistenceIgnoreState YES \
    FFISH_SNAPSHOT_SCREEN="$screen" \
    FFISH_SNAPSHOT_MODEL_ID="$MODEL_ID" \
    FFISH_SNAPSHOT_APP_LANGUAGE="$app_language" \
    FFISH_SNAPSHOT_AUTOSCROLL="$auto_scroll"
  wait_for_window
  set_window_frame
  if [ "$auto_scroll" = "1" ]; then
    sleep 1.5
  else
    sleep 4
  fi
}

record_app_segment() {
  local output="$1"
  local seconds="$2"
  local should_scroll="$3"
  local region
  activate_app_for_recording
  region="$(read_window_region)"
  echo "Recording region: $region"
  move_cursor_outside_recording
  activate_app_for_recording

  if [ "$should_scroll" = "1" ]; then
    screencapture -x -v -V "$seconds" -R "$region" "$output" &
    local capture_pid=$!
    python3 - "$CATALOG_SCROLL_START_DELAY_MS" <<'PY'
import sys
import time

time.sleep(max(int(sys.argv[1]), 0) / 1000)
PY
    scroll_catalog_window "$region"
    move_cursor_outside_recording
    wait "$capture_pid"
  else
    screencapture -x -v -V "$seconds" -R "$region" "$output"
  fi
}

render_caption_overlay() {
  local locale="$1"
  local text="$2"
  local output="$3"
  local font
  font="$(font_for_locale "$locale")"

  "$MAGICK_PATH" \
    -size "${OUTPUT_WIDTH}x${OUTPUT_HEIGHT}" xc:none \
    \( -size 1540x118 -background "#0B1512D9" -fill "#F6FBF8" -font "$font" -pointsize 42 -gravity center caption:"$text" \) \
    -gravity south -geometry +0+58 -composite \
    "png32:$output"
}

render_title_card() {
  local locale="$1"
  local title="$2"
  local caption="$3"
  local source_image="$4"
  local output="$5"
  local font
  font="$(font_for_locale "$locale")"

  if [ -f "$source_image" ]; then
    "$MAGICK_PATH" "$source_image" \
      -resize "${OUTPUT_WIDTH}x${OUTPUT_HEIGHT}^" \
      -gravity center \
      -extent "${OUTPUT_WIDTH}x${OUTPUT_HEIGHT}" \
      -blur 0x6 \
      -fill "#081410B8" -colorize 58% \
      \( -size 1500x170 -background none -fill "#F6FBF8" -font "$font" -pointsize 76 -gravity center caption:"$title" \) \
      -gravity center -geometry +0-80 -composite \
      \( -size 1500x120 -background none -fill "#CFE0DA" -font "$font" -pointsize 42 -gravity center caption:"$caption" \) \
      -gravity center -geometry +0+40 -composite \
      "png32:$output"
  else
    "$MAGICK_PATH" -size "${OUTPUT_WIDTH}x${OUTPUT_HEIGHT}" "gradient:#10211D-#2F574D" \
      \( -size 1500x170 -background none -fill "#F6FBF8" -font "$font" -pointsize 76 -gravity center caption:"$title" \) \
      -gravity center -geometry +0-80 -composite \
      \( -size 1500x120 -background none -fill "#CFE0DA" -font "$font" -pointsize 42 -gravity center caption:"$caption" \) \
      -gravity center -geometry +0+40 -composite \
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
    -level 4.0 \
    -preset slow \
    -crf 18 \
    -movflags +faststart \
    -an \
    "$output"
}

encode_recorded_segment() {
  local raw="$1"
  local caption_overlay="$2"
  local output="$3"
  "$FFMPEG_PATH" -y \
    -i "$raw" \
    -i "$caption_overlay" \
    -filter_complex "[0:v]scale='min(${OUTPUT_WIDTH},iw*min(${OUTPUT_WIDTH}/iw,${OUTPUT_HEIGHT}/ih))':'min(${OUTPUT_HEIGHT},ih*min(${OUTPUT_WIDTH}/iw,${OUTPUT_HEIGHT}/ih))':force_original_aspect_ratio=decrease:flags=lanczos,pad=${OUTPUT_WIDTH}:${OUTPUT_HEIGHT}:(ow-iw)/2:(oh-ih)/2:color=0x101816[base];[base][1:v]overlay=0:0,format=yuv420p,fps=30[v]" \
    -map "[v]" \
    -c:v libx264 \
    -profile:v high \
    -level 4.0 \
    -preset slow \
    -crf 18 \
    -movflags +faststart \
    -an \
    "$output"
}

extract_existing_video_segment() {
  local source="$1"
  local start="$2"
  local seconds="$3"
  local output="$4"
  "$FFMPEG_PATH" -y \
    -ss "$start" \
    -t "$seconds" \
    -i "$source" \
    -vf "fps=30,format=yuv420p" \
    -c:v libx264 \
    -profile:v high \
    -level 4.0 \
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
  local duration
  duration="$("$FFPROBE_PATH" -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$video_input")"
  local fade_out_start
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
    -filter_complex "[1:a][2:a][3:a]amix=inputs=3:duration=longest,volume=0.055,afade=t=in:st=0:d=1,afade=t=out:st=$fade_out_start:d=2,pan=stereo|c0=c0|c1=c0[a]" \
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

cd "$ROOT_DIR"
mkdir -p "$WORK_DIR/raw" "$WORK_DIR/overlays" "$WORK_DIR/segments"

echo "========== Build macOS app for preview video =========="
xcodebuild \
  -project "$ROOT_DIR/FFishAsia.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build

APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME.app"
if [ ! -d "$APP_PATH" ]; then
  echo "Built app not found: $APP_PATH" >&2
  exit 1
fi

SANDBOX_MODELS_DIR="$HOME/Library/Containers/$APP_BUNDLE_ID/Data/Library/Application Support/FFishAsia/Models"
mkdir -p "$SANDBOX_MODELS_DIR"
cp "$MODEL_SOURCE" "$SANDBOX_MODELS_DIR/$MODEL_FILE"

for locale in $LOCALES_FILTER; do
  apple_language="$(locale_to_apple_language "$locale")"
  apple_locale="$(locale_to_apple_locale "$locale")"
  fastlane_locale_dir="$FASTLANE_DIR/$locale"
  output_path="$fastlane_locale_dir/00-preview.mov"
  existing_output="$WORK_DIR/raw/$locale-existing-preview.mov"
  catalog_image="$fastlane_locale_dir/01-catalog.png"

  intro_image="$WORK_DIR/segments/$locale-intro.png"
  outro_image="$WORK_DIR/segments/$locale-outro.png"
  intro_video="$WORK_DIR/segments/$locale-01-intro.mov"
  catalog_video="$WORK_DIR/segments/$locale-02-catalog.mov"
  model_video="$WORK_DIR/segments/$locale-03-model.mov"
  outro_video="$WORK_DIR/segments/$locale-04-outro.mov"
  silent_video="$WORK_DIR/segments/$locale-silent.mov"
  concat_list="$WORK_DIR/segments/$locale-concat.txt"
  catalog_raw="$WORK_DIR/raw/$locale-catalog.mov"
  model_raw="$WORK_DIR/raw/$locale-model.mov"
  catalog_caption_overlay="$WORK_DIR/overlays/$locale-catalog-caption.png"
  model_caption_overlay="$WORK_DIR/overlays/$locale-model-caption.png"

  mkdir -p "$fastlane_locale_dir"
  if [ "$REUSE_EXISTING_MODEL_SEGMENT" = "1" ] && [ -f "$output_path" ]; then
    cp "$output_path" "$existing_output"
  fi

  echo
  echo "========== Render macOS App Preview video: $locale =========="
  render_title_card "$locale" \
    "$(localized_text "$locale" intro_title)" \
    "$(localized_text "$locale" intro_caption)" \
    "$catalog_image" \
    "$intro_image"
  encode_static_segment "$intro_image" "$INTRO_SECONDS" "$intro_video"

  echo "Recording scrolling catalog segment"
  launch_snapshot_screen "$locale" "catalog" "$apple_language" "$apple_locale" "0"
  scroll_catalog_to_top
  record_app_segment "$catalog_raw" "$CATALOG_SECONDS" "1"
  stop_app_processes
  render_caption_overlay "$locale" "$(localized_text "$locale" catalog_caption)" "$catalog_caption_overlay"
  encode_recorded_segment "$catalog_raw" "$catalog_caption_overlay" "$catalog_video"

  if [ "$REUSE_EXISTING_MODEL_SEGMENT" = "1" ] && [ -f "$existing_output" ]; then
    echo "Reusing animated model segment from existing preview video"
    extract_existing_video_segment "$existing_output" "$REUSE_MODEL_START" "$REUSE_MODEL_SECONDS" "$model_video"
  else
    echo "Recording animated model segment"
    launch_snapshot_screen "$locale" "preview" "$apple_language" "$apple_locale" "0"
    record_app_segment "$model_raw" "$MODEL_SECONDS" "0"
    stop_app_processes
    render_caption_overlay "$locale" "$(localized_text "$locale" model_caption)" "$model_caption_overlay"
    encode_recorded_segment "$model_raw" "$model_caption_overlay" "$model_video"
  fi

  render_title_card "$locale" \
    "$(localized_text "$locale" outro_title)" \
    "$(localized_text "$locale" outro_caption)" \
    "$catalog_image" \
    "$outro_image"
  encode_static_segment "$outro_image" "$OUTRO_SECONDS" "$outro_video"

  printf "file '%s'\nfile '%s'\nfile '%s'\nfile '%s'\n" \
    "$intro_video" "$catalog_video" "$model_video" "$outro_video" > "$concat_list"

  echo "Combining four video sections"
  concat_segments "$concat_list" "$silent_video"

  echo "Adding simple music track"
  add_music_track "$silent_video" "$output_path"

  "$FFPROBE_PATH" -v error -select_streams v:0 \
    -show_entries stream=codec_name,width,height,avg_frame_rate:format=duration,size \
    -of default=noprint_wrappers=1 "$output_path"
done

echo
echo "Done. macOS App Preview video files are in $FASTLANE_DIR/<locale>/00-preview.mov."

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RAW_DIR="${FFISHASIA_MACOS_RAW_DIR:-$ROOT_DIR/macos_screenshots/raw}"
OUTPUT_DIR="${FFISHASIA_MACOS_PREVIEW_OUTPUT_DIR:-$ROOT_DIR/macos_screenshots/output}"
FASTLANE_DIR="${FFISHASIA_MACOS_FASTLANE_SCREENSHOTS_DIR:-$ROOT_DIR/fastlane/screenshots_macos}"
LOCALES_FILTER="${LOCALES:-}"
SCENES_FILTER="${SCENES:-}"
MODES_FILTER="${MODES:-light dark}"
OPTIMIZE_SCREENSHOTS="${FFISH_OPTIMIZE_SCREENSHOTS:-1}"
MAGICK_PATH="$(command -v magick 2>/dev/null || true)"

if [ -z "$MAGICK_PATH" ]; then
  echo "ImageMagick 'magick' is required to render macOS preview images." >&2
  exit 1
fi

LOCALES_FILTER="$LOCALES_FILTER" SCENES_FILTER="$SCENES_FILTER" MODES_FILTER="$MODES_FILTER" OPTIMIZE_SCREENSHOTS="$OPTIMIZE_SCREENSHOTS" RAW_DIR="$RAW_DIR" OUTPUT_DIR="$OUTPUT_DIR" FASTLANE_DIR="$FASTLANE_DIR" MAGICK_PATH="$MAGICK_PATH" python3 - <<'PY'
import os
import pathlib
import shutil
import subprocess
import tempfile

raw_dir = pathlib.Path(os.environ["RAW_DIR"])
output_dir = pathlib.Path(os.environ["OUTPUT_DIR"])
fastlane_dir = pathlib.Path(os.environ["FASTLANE_DIR"])
magick = os.environ["MAGICK_PATH"]
optimize_screenshots = os.environ.get("OPTIMIZE_SCREENSHOTS", "1") != "0"

locale_specs = {
    "zh-Hans": {"prefix": "zh_Hans", "fastlane_dir": "zh-Hans"},
    "zh-Hant": {"prefix": "zh_Hant", "fastlane_dir": "zh-Hant"},
    "en-US": {"prefix": "en_US", "fastlane_dir": "en-US"},
    "ja": {"prefix": "ja", "fastlane_dir": "ja"},
    "ko": {"prefix": "ko", "fastlane_dir": "ko"},
    "de-DE": {"prefix": "de_DE", "fastlane_dir": "de-DE"},
}

scene_specs = {
    "01-preview": "01-preview.png",
    "02-catalog": "02-catalog.png",
    "03-detail": "03-detail.png",
    "01-preview-dark": "04-preview-dark.png",
}

translations = {
    "en-US": {
        "01-preview": ("Asian Wildlife, Alive in 3D", "Rotate, zoom, and watch animated species on your Mac."),
        "02-catalog": ("Explore Animals & Plants", "Browse a curated field guide to Asian nature."),
        "03-detail": ("Learn the Species", "Names, scientific classification, and sources stay together."),
        "01-preview-dark": ("Asian Wildlife, Alive in 3D", "Animated nature, beautifully presented in Dark Mode."),
    },
    "zh-Hans": {
        "01-preview": ("鲜活呈现的亚洲物种", "在 Mac 上旋转、缩放并观看模型动画。"),
        "02-catalog": ("探索动物与植物", "浏览精心整理的亚洲自然图鉴。"),
        "03-detail": ("了解每一个物种", "名称、科学分类和模型来源集中呈现。"),
        "01-preview-dark": ("鲜活呈现的亚洲物种", "在深色模式中欣赏生动的自然模型。"),
    },
    "zh-Hant": {
        "01-preview": ("鮮活呈現的亞洲物種", "在 Mac 上旋轉、縮放並觀看模型動畫。"),
        "02-catalog": ("探索動物與植物", "瀏覽精心整理的亞洲自然圖鑑。"),
        "03-detail": ("了解每一個物種", "名稱、科學分類和模型來源集中呈現。"),
        "01-preview-dark": ("鮮活呈現的亞洲物種", "在深色模式中欣賞生動的自然模型。"),
    },
    "ja": {
        "01-preview": ("アジアの生きものを3Dで", "Macで回転・拡大し、モデルの動きを観察。"),
        "02-catalog": ("動物と植物を探索", "厳選されたアジアの自然図鑑を閲覧。"),
        "03-detail": ("生きものを詳しく知る", "名称、科学分類、出典を一か所で確認。"),
        "01-preview-dark": ("アジアの生きものを3Dで", "ダークモードで動く自然モデルを観察。"),
    },
    "ko": {
        "01-preview": ("아시아 생물을 생생한 3D로", "Mac에서 회전하고 확대하며 모델의 움직임을 관찰하세요."),
        "02-catalog": ("동물과 식물 탐색", "엄선된 아시아 자연 도감을 둘러보세요."),
        "03-detail": ("각 생물을 더 깊이 이해", "이름, 과학적 분류와 출처를 한곳에서 확인하세요."),
        "01-preview-dark": ("아시아 생물을 생생한 3D로", "다크 모드에서 움직이는 자연 모델을 감상하세요."),
    },
    "de-DE": {
        "01-preview": ("Asiens Artenwelt in lebendigem 3D", "Drehen, zoomen und animierte Arten auf dem Mac beobachten."),
        "02-catalog": ("Tiere und Pflanzen entdecken", "Ein kuratierter Naturführer zu asiatischen Arten."),
        "03-detail": ("Arten besser kennenlernen", "Namen, wissenschaftliche Einordnung und Quellen an einem Ort."),
        "01-preview-dark": ("Asiens Artenwelt in lebendigem 3D", "Animierte Naturmodelle im Dark Mode erleben."),
    },
}

def first_existing_font(candidates):
    for candidate in candidates:
        path = pathlib.Path(candidate)
        if path.exists():
            return str(path)
    return None

latin_title_font = first_existing_font([
    "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
    "/Library/Fonts/Arial Bold.ttf",
    "/System/Library/Fonts/Supplemental/Arial.ttf",
])
cjk_title_font = first_existing_font([
    "/System/Library/Fonts/PingFang.ttc",
    "/System/Library/Fonts/STHeiti Light.ttc",
    "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
])
korean_title_font = first_existing_font([
    "/System/Library/Fonts/AppleSDGothicNeo.ttc",
    "/System/Library/Fonts/Supplemental/AppleGothic.ttf",
    "/System/Library/Fonts/Supplemental/NotoSansCJKkr-Regular.otf",
])
fallback_title_font = latin_title_font or cjk_title_font
if not fallback_title_font:
    raise SystemExit("Could not find a usable system font for macOS preview rendering.")

def title_font_for(locale):
    if locale == "ko" and korean_title_font:
        return korean_title_font
    if locale in {"zh-Hans", "zh-Hant", "ja", "ko"} and cjk_title_font:
        return cjk_title_font
    return latin_title_font or fallback_title_font

mode_order = [item for item in os.environ.get("MODES_FILTER", "").split() if item] or ["light"]
invalid_modes = [mode for mode in mode_order if mode not in {"light", "dark"}]
if invalid_modes:
    raise SystemExit(f"Unsupported modes in MODES: {', '.join(invalid_modes)}")

base_scene_ids = ["01-preview", "02-catalog", "03-detail"]
scene_ids = []
for mode in mode_order:
    mode_scene_ids = ["01-preview"] if mode == "dark" else base_scene_ids
    for scene in mode_scene_ids:
        scene_ids.append(scene if mode == "light" else f"{scene}-dark")
scenes = [(scene, scene_specs[scene]) for scene in scene_ids]
requested = [item for item in os.environ.get("LOCALES_FILTER", "").split() if item]
locale_order = requested or list(locale_specs)
for locale in locale_order:
    if locale not in locale_specs:
        raise SystemExit(f"Unsupported locale: {locale}")

requested_scenes = [item for item in os.environ.get("SCENES_FILTER", "").split() if item]
if requested_scenes:
    known_scenes = {scene for scene, _ in scenes}
    invalid_scenes = [scene for scene in requested_scenes if scene not in known_scenes]
    if invalid_scenes:
        raise SystemExit(f"Unsupported scenes in SCENES: {', '.join(invalid_scenes)}")
    scenes = [item for item in scenes if item[0] in requested_scenes]

for locale in locale_order:
    spec = locale_specs[locale]
    locale_output = output_dir / spec["fastlane_dir"]
    locale_fastlane = fastlane_dir / spec["fastlane_dir"]
    locale_output.mkdir(parents=True, exist_ok=True)
    locale_fastlane.mkdir(parents=True, exist_ok=True)

    if not requested_scenes:
        for old_png in locale_fastlane.glob("*.png"):
            old_png.unlink()
        for old in locale_fastlane.glob(".DS_Store"):
            old.unlink()

    for scene, output_name in scenes:
        raw = raw_dir / f"macos_{spec['prefix']}_{scene}.png"
        if not raw.exists():
            raise FileNotFoundError(f"Missing macOS raw screenshot: {raw}")

        rendered = locale_output / output_name
        window_layer = locale_output / f".{scene}-window.png"
        window_trimmed = locale_output / f".{scene}-window-trimmed.png"
        window_shadow = locale_output / f".{scene}-shadow.png"
        title, subtitle = translations[locale][scene]
        is_dark_preview = scene.endswith("-dark")
        preview_background = "gradient:#111827-#19322f" if is_dark_preview else "gradient:#f4f7f3-#d8e8e1"
        title_color = "#f4fbf8" if is_dark_preview else "#10211d"
        subtitle_color = "#c4d8d1" if is_dark_preview else "#49645d"
        shadow_color = "#040807" if is_dark_preview else "#10211d"

        subprocess.run([
            magick,
            str(raw),
            "-alpha", "set",
            "-background", "none",
            "-virtual-pixel", "transparent",
            "-trim",
            "+repage",
            f"png32:{window_trimmed}",
        ], check=True)
        subprocess.run([
            magick,
            str(window_trimmed),
            "-alpha", "set",
            "-background", "none",
            "-virtual-pixel", "transparent",
            "-filter", "Lanczos",
            "-resize", "2360x1400",
            f"png32:{window_layer}",
        ], check=True)
        subprocess.run([
            magick,
            str(window_layer),
            "(",
            "+clone",
            "-background", shadow_color,
            "-shadow", "34x24+0+30",
            ")",
            "+swap",
            "-background", "none",
            "-layers", "merge",
            "+repage",
            f"png32:{window_shadow}",
        ], check=True)
        subprocess.run([
            magick,
            "-size", "2880x1800",
            preview_background,
            "(",
            str(window_shadow),
            ")",
            "-gravity", "center",
            "-geometry", "+0+170",
            "-composite",
            "-gravity", "northwest",
            "-fill", title_color,
            "-font", title_font_for(locale),
            "-pointsize", "76",
            "-annotate", "+190+110", title,
            "-fill", subtitle_color,
            "-pointsize", "46",
            "-annotate", "+190+205", subtitle,
            str(rendered),
        ], check=True)
        window_layer.unlink(missing_ok=True)
        window_trimmed.unlink(missing_ok=True)
        window_shadow.unlink(missing_ok=True)
        shutil.copy2(rendered, locale_fastlane / output_name)

    print(f"SYNC macOS preview set -> {locale_fastlane}")

def optimize_pngs(paths):
    paths = [path for path in paths if path.exists()]
    if not paths:
        return
    if not optimize_screenshots:
        print("PNG optimization skipped because FFISH_OPTIMIZE_SCREENSHOTS=0.")
        return

    oxipng = shutil.which("oxipng")
    if oxipng:
        print(f"Optimizing {len(paths)} PNG files with oxipng...")
        subprocess.run([oxipng, "-o", "4", "--strip", "safe", *map(str, paths)], check=True)
        return

    print(f"Optimizing {len(paths)} PNG files with ImageMagick...")
    for path in paths:
        before = path.stat().st_size
        with tempfile.NamedTemporaryFile(prefix=path.stem + ".", suffix=".png", delete=False) as temp:
            temp_path = pathlib.Path(temp.name)
        try:
            subprocess.run([
                magick,
                str(path),
                "-define", "png:compression-level=9",
                "-define", "png:compression-strategy=1",
                str(temp_path),
            ], check=True)
            if temp_path.stat().st_size < before:
                shutil.move(str(temp_path), str(path))
            else:
                temp_path.unlink(missing_ok=True)
        except Exception:
            temp_path.unlink(missing_ok=True)
            raise

final_pngs = []
for locale in locale_order:
    spec = locale_specs[locale]
    final_pngs.extend(sorted((fastlane_dir / spec["fastlane_dir"]).glob("*.png")))
optimize_pngs(final_pngs)

print("Done. FFishAsia macOS preview screenshots regenerated and synced.")
PY

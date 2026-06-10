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
    "01-catalog": "01-catalog.png",
    "02-detail": "02-detail.png",
    "03-downloads": "03-downloads.png",
    "01-catalog-dark": "04-catalog-dark.png",
}

translations = {
    "en-US": {
        "01-catalog": ("Browse 3D Animals & Plants", "A calm model catalog for nature and biology."),
        "02-detail": ("See each species up close", "Names, taxonomy, size, and source stay together on the Mac."),
        "03-downloads": ("Keep models offline", "Download only what you need and manage local storage clearly."),
        "01-catalog-dark": ("Browse 3D Animals & Plants", "A calm model catalog for nature and biology."),
    },
    "zh-Hans": {
        "01-catalog": ("精选 3D 自然模型", "在原生 Mac 目录中浏览动物与植物。"),
        "02-detail": ("近距离查看物种细节", "名称、分类、大小和来源信息集中呈现。"),
        "03-downloads": ("离线保留所需模型", "按需下载模型，并清晰管理本地存储。"),
        "01-catalog-dark": ("精选 3D 自然模型", "在深色模式下浏览完整 Mac 模型目录。"),
    },
    "zh-Hant": {
        "01-catalog": ("精選 3D 自然模型", "在原生 Mac 目錄中瀏覽動物與植物。"),
        "02-detail": ("近距離查看物種細節", "名稱、分類、大小和來源資訊集中呈現。"),
        "03-downloads": ("離線保留所需模型", "按需下載模型，並清晰管理本地儲存。"),
        "01-catalog-dark": ("精選 3D 自然模型", "在深色模式下瀏覽完整 Mac 模型目錄。"),
    },
    "ja": {
        "01-catalog": ("厳選された3D自然モデル", "Macのネイティブな一覧で動物と植物を閲覧。"),
        "02-detail": ("種の詳細を近くで確認", "名称、分類、サイズ、出典を一か所で確認できます。"),
        "03-downloads": ("モデルをオフライン保存", "必要なモデルだけを保存し、容量も管理できます。"),
        "01-catalog-dark": ("厳選された3D自然モデル", "ダークモードでMacのモデル一覧を閲覧。"),
    },
    "ko": {
        "01-catalog": ("엄선된 3D 자연 모델", "Mac 카탈로그에서 동물과 식물을 둘러보세요."),
        "02-detail": ("종의 세부 정보를 가까이서", "이름, 분류, 크기, 출처 정보를 한곳에 모았습니다."),
        "03-downloads": ("필요한 모델을 오프라인으로 보관", "필요할 때 다운로드하고 로컬 저장 공간을 명확하게 관리하세요."),
        "01-catalog-dark": ("엄선된 3D 자연 모델", "다크 모드에서 전체 Mac 카탈로그를 둘러보세요."),
    },
    "de-DE": {
        "01-catalog": ("Kuratierte 3D-Naturmodelle", "Tiere und Pflanzen im nativen Mac-Katalog durchsuchen."),
        "02-detail": ("Arten aus der Nähe ansehen", "Namen, Taxonomie, Größe und Quelle bleiben zusammen."),
        "03-downloads": ("Modelle offline behalten", "Nur bei Bedarf laden und lokalen Speicher klar verwalten."),
        "01-catalog-dark": ("Kuratierte 3D-Naturmodelle", "Den vollständigen Mac-Katalog im Dark Mode durchsuchen."),
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

base_scene_ids = ["01-catalog", "02-detail", "03-downloads"]
scene_ids = []
for mode in mode_order:
    mode_scene_ids = ["01-catalog"] if mode == "dark" else base_scene_ids
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

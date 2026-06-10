#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOCALES_FILTER="${LOCALES:-en-US}"
MODES_FILTER="${MODES:-light}"
OPTIMIZE_SCREENSHOTS="${FFISH_OPTIMIZE_SCREENSHOTS:-1}"

PROJECT_DIR="$ROOT_DIR" LOCALES_FILTER="$LOCALES_FILTER" MODES_FILTER="$MODES_FILTER" OPTIMIZE_SCREENSHOTS="$OPTIMIZE_SCREENSHOTS" python3 - <<'PY'
import copy
import json
import os
import pathlib
import shutil
import subprocess
import tempfile

project = pathlib.Path(os.environ['PROJECT_DIR'])
base = pathlib.Path('/Users/mac/Documents/Projects/AppStorePreview/ffishasia-assets')
fastlane = project / 'fastlane' / 'screenshots'
raw_root = project / 'maestro_screenshots'
app_preview_project = pathlib.Path('/Users/mac/Documents/Projects/AppStorePreview')
optimize_screenshots = os.environ.get('OPTIMIZE_SCREENSHOTS', '1') != '0'

app = next(pathlib.Path('/Users/mac/Library/Developer/Xcode/DerivedData').glob('*/Build/Products/Debug/AppStorePreview.app'), None)
if app is None:
    print('AppStorePreview.app not found in DerivedData. Building it now...')
    subprocess.run([
        'xcodebuild',
        '-workspace', str(app_preview_project / 'AppStorePreview.xcworkspace'),
        '-scheme', 'AppStorePreview',
        '-configuration', 'Debug',
        'build',
    ], check=True)
    app = next(pathlib.Path('/Users/mac/Library/Developer/Xcode/DerivedData').glob('*/Build/Products/Debug/AppStorePreview.app'), None)
if app is None:
    raise SystemExit('Error: AppStorePreview.app not found after build.')
bin_path = app / 'Contents' / 'MacOS' / 'AppStorePreview'

locale_specs = {
    'zh-Hans': {'prefix': 'zh_Hans', 'fastlane_dir': 'zh-Hans'},
    'zh-Hant': {'prefix': 'zh_Hant', 'fastlane_dir': 'zh-Hant'},
    'ja': {'prefix': 'ja', 'fastlane_dir': 'ja'},
    'ko': {'prefix': 'ko', 'fastlane_dir': 'ko'},
    'de-DE': {'prefix': 'de_DE', 'fastlane_dir': 'de-DE'},
    'en-US': {'prefix': 'en_US', 'fastlane_dir': 'en-US'},
}

requested_locales = [item for item in os.environ.get('LOCALES_FILTER', '').split() if item]
if requested_locales:
    locale_order = requested_locales
else:
    locale_order = ['en-US']
invalid = [locale for locale in locale_order if locale not in locale_specs]
if invalid:
    raise SystemExit(f'Unsupported locales in LOCALES: {", ".join(invalid)}')

mode_order = [item for item in os.environ.get('MODES_FILTER', '').split() if item] or ['light']
invalid_modes = [mode for mode in mode_order if mode not in ('light', 'dark')]
if invalid_modes:
    raise SystemExit(f'Unsupported modes in MODES: {", ".join(invalid_modes)}')

device_specs = {
    'iphone': {
        'raw_prefix': 'iphone17promax',
        'input_root': base / 'input-iphone',
        'output_root': base / 'output',
        'bezel': '16pm',
        'dest': None,
        'fastlane_prefix': '',
    },
    'ipad13': {
        'raw_prefix': 'ipad13',
        'input_root': base / 'input-ipad13',
        'output_root': base / 'output-ipad13',
        'bezel': 'ipadP',
        'dest': (2048, 2732),
        'fastlane_prefix': 'ipad13-',
    },
}

translations = {
    'en-US': [
        'Explore Animals & Plants in AR\n3D nature models you can place in your space.',
        'See each species up close\nNames, taxonomy, size, and source in one place.',
        'Download only what you need\nKeep models available offline and manage storage.',
    ],
    'zh-Hans': [
        '精选 3D 生物模型\n动物、植物、AR 查看与离线下载。',
        '近距离查看物种细节\n名称、分类、大小和来源集中呈现。',
        '按需下载，更省空间\n离线保留模型，并随时管理缓存。',
    ],
    'zh-Hant': [
        '精選 3D 生物模型\n動物、植物、AR 查看與離線下載。',
        '近距離查看物種細節\n名稱、分類、大小和來源集中呈現。',
        '按需下載，更省空間\n離線保留模型，並隨時管理快取。',
    ],
    'ja': [
        '厳選された3D生物モデル\n動物、植物、AR表示、オフライン閲覧に対応。',
        '種の詳細を近くで確認\n名称、分類、サイズ、出典を一か所に。',
        '必要なモデルだけ保存\nオフライン閲覧と容量管理に対応。',
    ],
    'ko': [
        '엄선된 3D 생물 모델\n동물, 식물, AR 보기, 오프라인 저장.',
        '종의 세부 정보를 가까이서\n이름, 분류, 크기, 출처를 한곳에.',
        '필요한 모델만 다운로드\n오프라인으로 보관하고 저장 공간을 관리하세요.',
    ],
    'de-DE': [
        'Kuratierte biologische 3D-Modelle\nTiere, Pflanzen, AR-Ansicht und Offlinezugriff.',
        'Arten aus der Nähe ansehen\nNamen, Taxonomie, Größe und Quelle an einem Ort.',
        'Nur laden, was du brauchst\nModelle offline behalten und Speicher verwalten.',
    ],
}

shots = [
    ('catalog', 'catalog.png', '01-catalog-light.png', '#0F766E'),
    ('detail', 'detail.png', '02-detail-light.png', '#166534'),
    ('downloads', 'downloads.png', '03-downloads-light.png', '#2563EB'),
]

def raw_candidate(device, locale, mode, slug):
    spec = locale_specs[locale]
    return raw_root / f"{device['raw_prefix']}_{spec['prefix']}_{mode}_{slug}.png"

for device_name, device in device_specs.items():
    for locale in locale_order:
        for mode in mode_order:
            dest_dir = device['input_root'] / locale / mode
            dest_dir.mkdir(parents=True, exist_ok=True)
            for slug, logical_name, _, _ in shots:
                src = raw_candidate(device, locale, mode, slug)
                if not src.exists():
                    raise FileNotFoundError(f'MISSING RAW SCREENSHOT: {src}. Run scripts/run_ffishasia_snapshots.sh first.')
                dest = dest_dir / logical_name
                shutil.copy2(src, dest)
                print(f'INPUT SYNC [{device_name}] {src} -> {dest}')

def build_config(device_name, locale, mode):
    device = device_specs[device_name]
    spec = locale_specs[locale]
    items = []
    for index, (slug, logical_name, output_name, background) in enumerate(shots):
        out_name = output_name if mode == 'light' else output_name.replace('-light', '-dark')
        item = {
            'input': str(device['input_root'] / locale / mode / logical_name),
            'output': str(device['output_root'] / spec['fastlane_dir'] / out_name),
            'text': translations[locale][index],
            'background': background,
            'language': spec['fastlane_dir'],
            'bezel': device['bezel'],
        }
        if device['dest']:
            item['destWidth'], item['destHeight'] = device['dest']
        items.append(item)
    return {
        'outputDirectory': str(device['output_root'] / spec['fastlane_dir']),
        'defaultBezel': device['bezel'],
        'items': items,
    }

with tempfile.TemporaryDirectory(prefix='ffishasia-preview-configs-') as tmp:
    tmp_dir = pathlib.Path(tmp)
    for device_name in ('iphone', 'ipad13'):
        for locale in locale_order:
            for mode in mode_order:
                config = build_config(device_name, locale, mode)
                config_path = tmp_dir / f'{device_name}.{locale}.{mode}.json'
                config_path.write_text(json.dumps(config, ensure_ascii=False, indent=2) + '\n')
                print(f'RUN [{device_name}] {config_path}')
                subprocess.run([str(bin_path), '--config', str(config_path)], check=True)

for locale in locale_order:
    spec = locale_specs[locale]
    fastlane_locale_root = fastlane / spec['fastlane_dir']
    fastlane_locale_root.mkdir(parents=True, exist_ok=True)
    for old_png in fastlane_locale_root.glob('*.png'):
        old_png.unlink()
    for device_name in ('iphone', 'ipad13'):
        device = device_specs[device_name]
        src_dir = device['output_root'] / spec['fastlane_dir']
        for _, _, output_name, _ in shots:
            for mode in mode_order:
                source_name = output_name if mode == 'light' else output_name.replace('-light', '-dark')
                target_name = output_name.replace('-light', '') if mode == 'light' else source_name.replace('-dark', '-dark')
                source_path = src_dir / source_name
                if not source_path.exists():
                    raise FileNotFoundError(f'MISSING OUTPUT {source_path}')
                shutil.copy2(source_path, fastlane_locale_root / f"{device['fastlane_prefix']}{target_name}")
    print(f'SYNC final upload set -> {fastlane_locale_root}')

def optimize_pngs(paths):
    paths = [path for path in paths if path.exists()]
    if not paths:
        return
    if not optimize_screenshots:
        print('PNG optimization skipped because FFISH_OPTIMIZE_SCREENSHOTS=0.')
        return

    oxipng = shutil.which('oxipng')
    if oxipng:
        print(f'Optimizing {len(paths)} PNG files with oxipng...')
        subprocess.run([oxipng, '-o', '4', '--strip', 'safe', *map(str, paths)], check=True)
        return

    magick = shutil.which('magick')
    if not magick:
        print('PNG optimization skipped: install oxipng or ImageMagick magick.')
        return

    print(f'Optimizing {len(paths)} PNG files with ImageMagick...')
    for path in paths:
        before = path.stat().st_size
        with tempfile.NamedTemporaryFile(prefix=path.stem + '.', suffix='.png', delete=False) as temp:
            temp_path = pathlib.Path(temp.name)
        try:
            subprocess.run([
                magick,
                str(path),
                '-define', 'png:compression-level=9',
                '-define', 'png:compression-strategy=1',
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
    final_pngs.extend(sorted((fastlane / spec['fastlane_dir']).glob('*.png')))
optimize_pngs(final_pngs)

print('Done. FFishAsia iPhone + 13-inch iPad preview outputs regenerated and synced into Fastlane screenshots.')
PY

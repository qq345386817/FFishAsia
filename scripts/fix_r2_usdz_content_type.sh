#!/usr/bin/env bash
# fix_r2_usdz_content_type.sh — 修正 R2 上现有 USDZ 对象的 Content-Type
#
# 用法：
#   R2_ENDPOINT="https://<account_id>.r2.cloudflarestorage.com" \
#   BUCKET_NAME="ffishasia-models" \
#   AWS_PROFILE="r2" \
#   scripts/fix_r2_usdz_content_type.sh
#
# 说明：
# - 需要 AWS CLI 和有 R2 写权限的凭证。
# - 脚本不会重新上传本地文件，只会对远端对象执行 copy-to-self，替换 metadata。

set -euo pipefail

R2_ENDPOINT="${R2_ENDPOINT:-}"
BUCKET_NAME="${BUCKET_NAME:-ffishasia-models}"
AWS_PROFILE="${AWS_PROFILE:-r2}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST_PATH="${MANIFEST_PATH:-$ROOT_DIR/FFishAsia/Resources/manifest.json}"
CONTENT_TYPE="model/vnd.usdz+zip"
CACHE_CONTROL="public, max-age=31536000, immutable"

if [[ -z "$R2_ENDPOINT" ]]; then
  echo "❌ 请设置 R2_ENDPOINT，例如：https://<account_id>.r2.cloudflarestorage.com" >&2
  exit 1
fi

if ! command -v aws >/dev/null 2>&1; then
  echo "❌ 未找到 aws CLI。请先安装 AWS CLI。" >&2
  exit 1
fi

if [[ ! -f "$MANIFEST_PATH" ]]; then
  echo "❌ 找不到 manifest: $MANIFEST_PATH" >&2
  exit 1
fi

export MANIFEST_PATH

FILES=()
while IFS= read -r filename; do
  FILES+=("$filename")
done < <(python3 - <<'PY'
import json
import os
manifest_path = os.environ['MANIFEST_PATH']
with open(manifest_path, 'r', encoding='utf-8') as f:
    data = json.load(f)
for m in data.get('models', []):
    filename = m.get('filename', '')
    if filename:
        print(filename)
PY
)

if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "❌ manifest 中没有模型文件。" >&2
  exit 1
fi

echo "=== 修正 R2 USDZ Content-Type ==="
echo "Bucket: $BUCKET_NAME"
echo "Endpoint: $R2_ENDPOINT"
echo "Profile: $AWS_PROFILE"
echo "Content-Type: $CONTENT_TYPE"
echo "对象数量: ${#FILES[@]}"
echo

for filename in "${FILES[@]}"; do
  key="models/$filename"
  echo "🔧 $key"
  aws s3api copy-object \
    --bucket "$BUCKET_NAME" \
    --copy-source "$BUCKET_NAME/$key" \
    --key "$key" \
    --metadata-directive REPLACE \
    --content-type "$CONTENT_TYPE" \
    --cache-control "$CACHE_CONTROL" \
    --endpoint-url "$R2_ENDPOINT" \
    --profile "$AWS_PROFILE" \
    >/dev/null
done

echo
echo "✅ 已提交 Content-Type 修正。建议等待几秒后用 scripts/check_r2_content_type.py 验证。"

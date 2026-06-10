#!/bin/bash
# upload_to_r2.sh — 上传 FFishAsia manifest 和 USDZ 模型到 Cloudflare R2
# 
# 使用前：
#   1. 安装 AWS CLI: brew install awscli
#   2. 配置 R2 profile: aws configure --profile r2
#   3. 设置 R2_ENDPOINT，例如：
#      R2_ENDPOINT="https://<account_id>.r2.cloudflarestorage.com" scripts/upload_to_r2.sh

set -euo pipefail

R2_ENDPOINT="${R2_ENDPOINT:-}"
BUCKET_NAME="${BUCKET_NAME:-ffishasia-models}"
AWS_PROFILE="${AWS_PROFILE:-r2}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST_PATH="${MANIFEST_PATH:-$ROOT_DIR/FFishAsia/Resources/manifest.json}"
USDZ_DIR="${USDZ_DIR:-$ROOT_DIR/usdz_resources}"

if [[ -z "$R2_ENDPOINT" ]]; then
    echo "❌ 请设置 R2_ENDPOINT，例如：https://<account_id>.r2.cloudflarestorage.com" >&2
    exit 1
fi

echo "=== FFishAsia R2 上传工具 ==="
echo "存储桶: $BUCKET_NAME"
echo "端点: $R2_ENDPOINT"
echo "Profile: $AWS_PROFILE"
echo "manifest: $MANIFEST_PATH"
echo "USDZ 目录: $USDZ_DIR"
echo ""

# 检查 AWS CLI
if ! command -v aws &> /dev/null; then
    echo "❌ 未安装 AWS CLI。请运行: brew install awscli"
    exit 1
fi

# 检查凭证
if ! aws sts get-caller-identity --profile "$AWS_PROFILE" --endpoint-url "$R2_ENDPOINT" &> /dev/null; then
    echo "❌ R2 凭证无效。请运行: aws configure --profile r2"
    exit 1
fi

if [[ ! -f "$MANIFEST_PATH" ]]; then
    echo "❌ 找不到 manifest: $MANIFEST_PATH" >&2
    exit 1
fi

echo "📤 上传 manifest.json..."
aws s3 cp "$MANIFEST_PATH" "s3://$BUCKET_NAME/manifest.json" \
    --endpoint-url "$R2_ENDPOINT" \
    --profile "$AWS_PROFILE" \
    --content-type "application/json; charset=utf-8" \
    --cache-control "public, max-age=300"

# 上传 USDZ 文件
echo "📤 上传 USDZ 模型..."
count=0
total_size=0

while IFS= read -r f; do
    if [ -f "$f" ]; then
        filename=$(basename "$f")
        size_mb=$(echo "scale=1; $(stat -f%z "$f") / 1048576" | bc)
        
        echo -n "  ⬆️  $filename ($size_mb MB)... "
        aws s3 cp "$f" "s3://$BUCKET_NAME/models/$filename" \
            --endpoint-url "$R2_ENDPOINT" \
            --profile "$AWS_PROFILE" \
            --content-type "model/vnd.usdz+zip" \
            --cache-control "public, max-age=31536000, immutable" \
            2>&1 | grep -v "upload:" || true
        
        echo "✅"
        count=$((count + 1))
    fi
done < <(find "$USDZ_DIR" -type f -name '*.usdz' | sort)

echo ""
echo "=== 上传完成 ==="
echo "已上传: $count 个文件"
echo ""

# FFishAsia — Cloudflare R2 部署指南

## 概述

将 22 个 USDZ 模型文件（共 838MB）托管到 Cloudflare R2，供 App 按需下载。
缩略图已打包进 App 本体（约 2MB），无需从服务器下载。

## 一、创建 Cloudflare R2 存储桶

### 1. 注册 Cloudflare 账号
- 访问 https://dash.cloudflare.com/sign-up
- 免费套餐即可

### 2. 创建 R2 存储桶
- 登录 Cloudflare Dashboard
- 左侧菜单 → **R2 对象存储** → **创建存储桶**
- 存储桶名称：`ffishasia-models`
- 区域：**亚太 (APAC)**（离目标用户最近）

### 3. 获取 API 令牌
- R2 → **管理 R2 API 令牌** → **创建 API 令牌**
- 权限：**对象读和写**
- 指定存储桶：`ffishasia-models`
- 记下：
  - `Access Key ID`
  - `Secret Access Key`
  - `Endpoint`（类似 `https://<account_id>.r2.cloudflarestorage.com`）

## 二、上传模型文件

### 方法 A：使用 AWS CLI（推荐）

```bash
# 安装 AWS CLI
brew install awscli

# 配置 R2 凭证
aws configure --profile r2
# AWS Access Key ID: <your_access_key>
# AWS Secret Access Key: <your_secret_key>
# Default region: auto
# Default output format: json

# 上传所有 USDZ 文件
cd ~/Documents/Projects/FFishAsia/FFishAsia/Resources
for f in *.usdz; do
    aws s3 cp "$f" s3://ffishasia-models/models/ \
        --endpoint-url https://<account_id>.r2.cloudflarestorage.com \
        --profile r2
    echo "✅ Uploaded: $f"
done
```

### 方法 B：使用项目自带脚本

```bash
# 先在 ~/.aws/credentials 中配置 r2 profile
# 然后运行：
cd ~/Documents/Projects/FFishAsia
chmod +x scripts/upload_to_r2.sh
./scripts/upload_to_r2.sh
```

### 方法 C：Cloudflare Dashboard 手动上传
- R2 → `ffishasia-models` → **上传** → 拖拽文件
- 创建 `models/` 文件夹，将 22 个 USDZ 放入

## 三、配置公开访问

### 选项 A：R2 公开访问（最简单）
- R2 → `ffishasia-models` → **设置** → **公开访问**
- 开启 → 绑定自定义域名或使用 R2.dev 子域名
- 开启后会生成公开 URL，类似：
  ```
  https://pub-xxxxx.r2.dev/models/CC0_オオスズメバチ__Japanese_Giant_Hornet.usdz
  ```

### 选项 B：自定义域名（推荐）
- Cloudflare → **网站** → 添加域名
- 配置 DNS → R2 存储桶绑定自定义域名
- 例如：`cdn.ffishasia.com`
- 最终 URL：`https://cdn.ffishasia.com/models/CC0_xxx.usdz`

### 选项 C：Cloudflare Worker（最灵活）
- 创建 Worker 作为 API 网关
- 可添加：下载计数、CORS 头、缓存控制、速率限制
- 参考 `scripts/worker.js`

## 四、生成 manifest.json

上传完成后，在存储桶根目录放置 `manifest.json`。项目唯一的模型清单是 `FFishAsia/Resources/manifest.json`，App 内置 fallback 和 R2 上传都使用这一份文件：

```json
{
  "version": "1.0",
  "updated_at": "2026-04-13",
  "base_url": "https://cdn.ffishasia.com",
  "models": [
    {
      "id": "hornet",
      "filename": "CC0_オオスズメバチ__Japanese_Giant_Hornet.usdz",
      "download_url": "https://cdn.ffishasia.com/models/CC0_オオスズメバチ__Japanese_Giant_Hornet.usdz",
      "file_size_mb": 24.0,
      "category": "animal",
      "name_zh_hans": "日本大黄蜂",
      "name_ja": "オオスズメバチ",
      "name_en": "Japanese Giant Hornet",
      "sketchfab_url": "https://sketchfab.com/3d-models/f9c1f7e3f373491fbf01adf94ec8169e"
    }
  ]
}
```

项目提供了生成脚本：
```bash
cd ~/Documents/Projects/FFishAsia
python3 scripts/generate_manifest.py --base-url https://cdn.ffishasia.com
```

同步到 R2：
```bash
R2_ENDPOINT="https://<account_id>.r2.cloudflarestorage.com" scripts/upload_to_r2.sh
```

## 五、App 下载流程

```
┌─────────────┐
│ App 启动     │
└──────┬──────┘
       ▼
┌─────────────────────┐
│ 读取本地 manifest    │ ← 内置 manifest.json（打包进 App）
│ 展示模型列表         │ ← 缩略图：本地 Assets（打包进 App）
└──────┬──────────────┘
       ▼ 用户点击模型
┌─────────────────────┐
│ 检查本地缓存         │ ← Documents/FFishAsia/cache/
│ ├─ 已缓存 → 直接加载  │
│ └─ 未缓存 → 下载     │ ← URLSession + 进度条
└──────┬──────────────┘
       ▼
┌─────────────────────┐
│ 下载到本地缓存        │ ← 支持后台下载、断点续传
│ 下载完成 → 加载到 AR  │
└─────────────────────┘
```

## 六、费用估算

| 项目 | 免费额度 | 实际用量 | 费用 |
|:-----|:---------|:---------|:-----|
| 存储 | 10GB/月 | 838MB (8%) | $0 |
| A 类操作（写入） | 100万次/月 | 22次（一次性） | $0 |
| B 类操作（读取） | 1000万次/月 | 取决于下载量 | $0 |
| 出站流量 | **免费（零出站费）** | — | **$0** |

**总费用：$0/月**（在免费额度内）

## 七、注意事项

1. **中国大陆访问**：R2 裸域名可能被墙。解决方案：
   - 绑定自定义域名 + 开启 Cloudflare CDN 代理（橙色云图标）
   - 或使用 Worker 代理
   
2. **CORS 配置**：如果从 App 的 WKWebView 访问，需要在 R2 存储桶配置 CORS

3. **缓存策略**：USDZ 文件不会变，设置长缓存头（Cache-Control: max-age=31536000）

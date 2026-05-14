# FFishAsia README_SPEC

## 1. 项目定位
FFishAsia 是一个基于 **SwiftUI + RealityKit + ARKit** 的 iOS AR 生物图鉴应用。

目标不是做通用 3D 查看器，而是做一个：
- 以 **自然教育 / 生物图鉴** 为核心
- 使用 **CC0 公开 3D 生物模型**
- 支持 **按需下载 + 本地缓存 + AR 展示**
- 可继续向 **App Store 上架版本**演进的小型产品

当前模型来源主要是 Sketchfab 作者：
- **ffish.asia / floraZia.com**
- 一般社団法人九州オープンユニバーシティ（QOU）
- 九州大学流域システム工学研究室

模型许可：**CC0 Public Domain**

---

## 2. 当前产品能力
截至当前版本，项目已经具备：

### 已完成功能
1. **模型列表浏览**
   - 分类筛选：全部 / 动物 / 植物 / 特别
   - 搜索：支持按日文名 / 英文名 / 学名搜索
   - 本地缩略图展示

2. **模型详情查看**
   - 名称（主名 / 英文名 / 学名）
   - 分类信息
   - 面数 / 顶点数 / 文件大小
   - Sketchfab 来源链接

3. **远程模型下载**
   - 远程拉取 manifest.json
   - 按需下载 USDZ
   - 下载状态：未下载 / 下载中 / 已下载 / 失败
   - 下载失败可重试

4. **本地缓存管理**
   - 本地缓存目录：`Application Support/FFishAsia/Models/`
   - 删除单个模型
   - 删除全部已下载模型
   - 显示已下载数量与缓存占用

5. **AR 展示**
   - 加载本地缓存后的 USDZ 文件
   - 支持基础交互（缩放 / 旋转）
   - 对静态模型附加轻量悬浮 + 自转效果
   - 对带内嵌动画模型优先播放内嵌动画

6. **产品化基础设施**
   - onboarding 首次引导
   - toast 反馈
   - About 页面
   - 隐私政策草稿
   - 支持页草稿
   - fastlane 元数据骨架

---

## 3. 当前技术架构

### 技术栈
- **UI**: SwiftUI
- **AR/3D**: RealityKit + ARKit
- **下载管理**: URLSessionDownloadTask
- **数据来源**: 远程 `manifest.json` + 内置 `FFishAsia/Resources/manifest.json`
- **构建工具**: Xcode / xcodebuild
- **App Store 元数据**: fastlane

### 主要模块

#### 3.1 `FFishAsiaApp.swift`
- App 入口
- 使用 `NavigationStack`
- 承载全局导航和根视图

#### 3.2 `ContentView.swift`
- 主列表页
- 分类筛选 UI
- 搜索框
- 模型卡片列表
- 模型详情 sheet
- AR 全屏展示入口
- onboarding / toast 容器

#### 3.3 `ModelCatalog.swift`
- 模型数据层
- 负责：
  - 解码内置 `FFishAsia/Resources/manifest.json`
  - 解码远程 `manifest.json`
  - `ModelItem` 结构定义
  - 分类推断（动物 / 植物 / 特别）
  - 缩略图命名映射

#### 3.4 `DownloadManager.swift`
- 下载核心
- 共享状态管理
- 负责：
  - 拉取远程 manifest
  - 下载模型文件
  - 本地缓存路径管理
  - 下载状态映射
  - 删除 / 重试 / 清空下载
  - 统计缓存大小

#### 3.5 `DownloadManagerView.swift`
- 下载管理页
- 展示已下载模型和下载中任务
- 提供删除能力

#### 3.6 `ARViewContainer.swift`
- RealityKit/ARKit 包装层
- 接收 `modelURL`
- 加载本地 USDZ
- 管理 AR Session
- 管理静态模型附加动画

#### 3.7 `AboutView.swift`
- 致谢
- 数据来源说明
- 许可说明
- App 用途说明

---

## 4. 数据架构

### 4.1 内置 manifest
路径：
- `FFishAsia/Resources/manifest.json`

作用：
- 作为本地 fallback
- 保存模型静态信息、三语名称、下载 URL、分类、面数、顶点数、动画状态和分类学信息

### 4.2 远程 manifest
当前远程地址：
- `https://pub-0154a542ca38442c855387e2736c8f19.r2.dev/manifest.json`

作用：
- App 启动时拉取
- 决定当前可见和可下载的模型列表
- 提供每个模型的下载 URL

### 4.3 缩略图
本地路径：
- `FFishAsia/Resources/thumbnails/`

设计原则：
- 缩略图打包进 App，本体体积可接受
- 大模型 USDZ 不打包，由 CDN 按需下载

### 4.4 本地缓存目录
- `Application Support/FFishAsia/Models/`

作用：
- 保存下载完成的 USDZ 模型
- 离线可继续查看已下载模型

---

## 5. 远程分发方案

### 当前方案
- 模型托管：**Cloudflare R2**
- 公网域名：
  - `https://pub-0154a542ca38442c855387e2736c8f19.r2.dev`
- 模型目录：
  - `/models/*.usdz`

### 已解决问题
- 原始 Sketchfab 下载链接需要登录，不能直接用于 App
- 通过自建静态托管解决了可分发问题
- 文件名已经统一改成 ASCII 英文，避免 URL 编码问题

### 当前模型文件命名策略
使用纯 ASCII 文件名，例如：
- `japanese_giant_hornet.usdz`
- `forest_green_tree_frog.usdz`
- `indian_lotus.usdz`
- `luna_lionfish.usdz`

这是一个重要的架构决策，**不要再退回中文/日文文件名**。

---

## 6. 项目中的关键决策

### 6.1 为什么不用本地打包全部 USDZ
原因：
- 22 个模型总大小约 **838MB**
- 不适合直接打包进 App Store 版本
- 会显著拖慢安装与更新

因此改为：
- metadata + thumbnails 本地打包
- USDZ 远程下载

### 6.2 为什么保留本地 metadata fallback
因为：
- 远程 manifest 主要服务于分发和下载
- 本地 metadata 保存了更完整的原始描述信息
- 可用于断网 fallback 和未来数据修复

### 6.3 为什么保留 Resources 里的 USDZ
虽然 App 已不依赖本地 `.usdz` 运行，但暂时保留是为了：
- 继续开发时方便调试
- 未来重新生成 manifest 或迁移 CDN 时有源文件可用

后续如果进入正式发布流程，可以把这些大文件从 App target 中彻底移除。

---

## 7. 当前已知问题 / 缺口

### 产品层面
1. **正式 App Icon 仍缺失**
   - 当前不是完整可上架图标资源
   - 需要补 1024×1024 主图并生成完整 icon set

2. **截图还没做**
   - App Store 截图尚未正式生成
   - 需要根据当前 UI 补充多语言截图方案

3. **Launch / Branding 仍偏工程化**
   - 还缺更精致的品牌统一感

### 技术层面
1. **批量下载还没做**
2. **自动重试策略还比较基础**
3. **下载任务持久化不够强**
   - 当前更偏轻量实现
4. **manifest 字段未来可能需要扩展**
   - 如更多文案、分类标签、推荐权重、更新时间等

### 上架层面
1. **Apple Developer 后台还未接入**
2. **fastlane 只是骨架，未实配账号**
3. **隐私政策 URL 还未部署到公网**
4. **支持页 URL 还未部署到公网**

---

## 8. Roadmap

### Phase 1：当前已完成（MVP / 可测试版）
- [x] 本地模型查看 Demo
- [x] 模型列表 + 分类 + 搜索
- [x] 远程 manifest
- [x] 按需下载 USDZ
- [x] 本地缓存
- [x] 下载管理
- [x] About / 隐私政策 / 支持页草稿
- [x] fastlane metadata 骨架

### Phase 2：可上架版本
- [ ] 正式 App Icon
- [ ] App Store 截图
- [ ] App Store 中英文最终文案校对
- [ ] 公网隐私政策页面部署
- [ ] 公网支持页部署
- [ ] fastlane 接入真实 Apple 开发者账号
- [ ] TestFlight 内测包

### Phase 3：体验增强
- [ ] 批量下载
- [ ] 收藏模型
- [ ] 最近查看
- [ ] 更细粒度分类（两栖类 / 鱼类 / 昆虫 / 花卉 / 树木 等）
- [ ] 下载失败自动重试策略优化
- [ ] 模型详情页信息排版优化
- [ ] 多语言 UI（当前只是 metadata 双语）

### Phase 4：内容平台化
- [ ] 后台管理 manifest
- [ ] 新模型增量发布流程
- [ ] 模型推荐 / 专题策展
- [ ] 云端版本控制
- [ ] CDN 监控与资源统计

### Phase 5：教育产品化
- [ ] 课堂模式
- [ ] 展馆模式
- [ ] 扫码进入指定模型
- [ ] 多模型场景组合展示
- [ ] 讲解音频 / 文本注释

---

## 9. 以后继续开发时的优先建议
如果下次继续做，我建议优先顺序如下：

1. **补正式 App Icon**
2. **做 App Store 截图与提审文案**
3. **把本地大 USDZ 从 target 中移除，彻底验证远程下载模式**
4. **做 TestFlight 内测**
5. **根据测试反馈再决定是否加“收藏 / 最近查看 / 批量下载”**

---

## 10. 关键路径 / 文件索引

### 核心代码
- `FFishAsia/FFishAsiaApp.swift`
- `FFishAsia/ContentView.swift`
- `FFishAsia/ModelCatalog.swift`
- `FFishAsia/DownloadManager.swift`
- `FFishAsia/DownloadManagerView.swift`
- `FFishAsia/ARViewContainer.swift`
- `FFishAsia/AboutView.swift`

### 本地数据
- `FFishAsia/Resources/manifest.json`
- `FFishAsia/Resources/thumbnails/`

### 分发与部署
- `FFishAsia/Resources/manifest.json`
- `R2_DEPLOYMENT.md`
- `scripts/upload_to_r2.sh`
- `scripts/generate_manifest.py`
- `scripts/rename_models_ascii.py`

### 上架准备
- `fastlane/`
- `PRIVACY_POLICY.md`
- `SUPPORT.md`
- `APPSTORE_PREP.md`

---

## 11. 一句话总结
FFishAsia 当前已经不是一个简单 AR Demo，而是一个：

> **基于 CC0 3D 生物模型、支持远程分发与本地缓存、具备初步上架基础的 AR 生物图鉴 App 原型。**

它的下一步，不再是“能不能做”，而是“要不要继续把它打磨成真正可发布的产品”。

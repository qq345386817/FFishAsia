# 🌱 小小自然 (Little Nature)

> **3D 生物模型图鉴** | **3D Biological Model Field Guide**

一款基于 AR（增强现实）技术的跨平台应用，支持在真实环境中浏览高精度的生物 3D 模型。模型数据源自 [ffishAsia-and-floraZia](https://sketchfab.com/ffishAsia-and-floraZia) 项目，通过数字化方式展示亚洲动植物的多样性。

App Store: [小小自然 / Little Nature](https://apps.apple.com/app/id6766551832)

---

## 🛠️ 功能特点 (Features)

- **AR 展示**: 结合 ARKit 与 RealityKit，支持在 iOS 设备上通过增强现实技术查看生物模型。
- **跨平台浏览**: 支持 iOS 与 macOS (Apple Silicon)，适配不同设备的使用习惯。
- **按需下载**: 模型资源通过远程加载，减小应用初始包体积，并支持本地缓存管理。
- **交互支持**: 具备基础的平面检测、手势平移、旋转及缩放功能。
- **多语言支持**: 提供 简体中文、日本語、English 三种界面语言。

## ⚙️ 技术规格 (Technical Specs)

- **框架**: SwiftUI, RealityKit, ARKit
- **系统要求**: iOS 17.5+ / macOS 14.5+
- **模型格式**: USDZ

## 🚢 App Store / Fastlane

- iOS 元数据: `fastlane/metadata_ios`
- macOS 元数据: `fastlane/metadata_osx`
- 上传元数据: `fastlane ios upload_metadata` / `fastlane mac upload_metadata`

## 📂 项目说明 (Project Context)

本项目的 3D 模型资源均来自九州大学 ffishAsia-and-floraZia 团队提供的数字化存档。所有模型以 **CC0 1.0 Universal** 协议发布，本项目旨在为这些公开资源提供便捷的移动端/桌面端交互体验。

## 📜 许可 (License)

- 代码部分采用 [MIT License](LICENSE)。
- 3D 模型资源遵循原作者发布的 [CC0 许可](https://creativecommons.org/publicdomain/zero/1.0/)。

---

### 推荐仓库标签 (Repository Topics)
`swiftui`, `arkit`, `realitykit`, `ios`, `macos`, `ar-experience`, `3d-models`, `nature-encyclopedia`, `usdz`

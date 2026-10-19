# ASO 维护约定

## 定位与平台边界

- 保留现有品牌名，商店名称与安装名称保持一致。
- 首先呈现可交互的 3D 动植物观察；介绍中明确模型以亚洲物种为主。
- 不在元数据中写死模型总数，目录可以通过接口扩展。
- 六种语言在 iOS/macOS 中使用相同的 name 和 subtitle。
- iOS 可描述支持设备上的相机 AR；macOS 仅描述桌面 3D 预览。
- 离线能力指内置和已下载模型；不是所有远程模型都无需网络。
- 不承诺拍照识别、完整物种百科、原生打印、模型创作或未实现的收藏功能。

## 关键词证据

参考项目 `AppStoreKeywordPool` 的真实数据库，而不是演示数据。
读取 `latest_records`，使用 App ID `6766551832` 并过滤 `synthetic = 0`。
词表是候选清单，不是排名；官方建议词热度与市场热度也不是自然排名。
未出现在有限类别列表中的词不能填成零，受隐私限制的下载数据同样不能填零。
搜索来源下载可能包含广告，没有词级和用户界面语言归因。

本轮以功能相关性为主，不把跨类别热词直接当作高价值机会；没有自然排名
和足够完整的获取数据之前，不承诺增长幅度，也不凭几个下载判断国家优先级。

## 发布前校验

```sh
ruby fastlane/tests/metadata_test.rb
ruby fastlane/tests/preview_assets_test.rb
```

校验六语言双平台的字段长度、关键词分隔、重复词、name/subtitle 一致性，
并防止 Mac 文案误写相机 AR。关键词保守满足 Apple 两份文档中分别描述的
100 字符和 100 UTF-8 字节限制；副标题最多 30 字符，推广文案最多 170 字符。
不为了填满额度堆砌低相关词或竞品品牌。

介绍和推广文案中的筛选功能必须随对应 App 二进制一起发布，不能把仅存在于
本地开发版的功能提前写到线上。元数据本地修改不会自动上传 ASC。

发布后按国家和设备观察完整窗口内的搜索曝光、产品页访问和首次下载；
数据稀疏时延长窗口。更换关键词与预览素材应分轮验证，避免无法解释变化。

## 官方参考

- [创建产品页](https://developer.apple.com/app-store/product-page/)
- [平台版本字段](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information)
- [App 信息字段](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/)

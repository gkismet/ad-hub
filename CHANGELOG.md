# Changelog

## 0.1.0 — 2026-11-20
- 首版：Unity / Flutter 双端 AdHub 模块，支持 MAX / AdMob、插屏 / 激励 / 横幅
- 远程配置（远程 → 缓存 → 包内默认）、全局和广告位频控、统一事件（含收益）
- 配置校验脚本、Unity 同步脚本、skill 安装脚本

## 0.2.0 — 2026-11-20
- 去掉远程配置：配置只从包内读取（Unity `Assets/Resources/adhub_config.json`，Flutter `assets/adhub_config.json`）
- `AdHub.Init(appId)` / `AdHub.init(appId:)` 不再需要配置地址参数（**接口变更**）
- 新增 `tools/sync_config.ps1`：校验并把配置拷进 Unity / Flutter 项目；删除 `publish_config.ps1`

## 0.3.0 — 2026-11-20
- 新增开屏广告（app_open），MAX / AdMob 两端都支持：
  - 配置：`units.<平台>.app_open`、广告位 `format: "app_open"`、可选 `global.appOpenMinBackgroundSec`；旧配置不用改，照常可用
  - Flutter：`AdHub.showAppOpen(placement, waitLoad:)`、`AdHub.enableAppOpenOnResume(placement)`
  - Unity：`AdHub.ShowAppOpen(placement, onDone, waitLoadSec)`、`AdHub.EnableAppOpenOnResume(placement)`
  - 看广告/点广告引起的切后台，回来不会再弹开屏
- `IAdProvider` / `AdProvider` 接口加了 `ShowAppOpen` / `showAppOpen`（只影响自己写适配层的人）

## 0.3.1 — 2026-11-20
- 修复：Flutter 用 git 依赖时，中文 Windows 上 `flutter pub get` 解析 ad_hub 的 pubspec 失败（description 改成纯英文）。v0.3.0 的 Flutter git 依赖不可用，请直接用 v0.3.1

## 0.4.0 — 2026-11-20
- 新增去广告开关：Unity `AdHub.SetAdsRemoved(bool)` / `AdHub.AdsRemoved`，Flutter `AdHub.setAdsRemoved(bool)` / `AdHub.adsRemoved`（ValueNotifier）
  - true 时插屏、横幅、开屏都被拦下（blocked 原因"已购买去广告"），**激励照常**；已显示的横幅立刻隐藏（Flutter 的 AdHubBanner 自动消失）
  - 记在本地（PlayerPrefs / SharedPreferences `adhub.ads_removed`），下次启动在内购初始化前就生效
  - 新事件 `ads_removed`（message = true/false）
  - IapHub（iap-hub 仓库）买了/恢复/收回去广告时会自动调用，项目不用自己接
- Flutter 加单元测试 `test/ads_removed_test.dart`

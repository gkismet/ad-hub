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

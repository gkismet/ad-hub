# 上线前广告检查

逐条检查，能自己查的（读文件、跑脚本）自己查，需要真机的列给用户。

## 配置
- [ ] `config/apps/<app>.json`：`testMode: false`，`enabled: true`
- [ ] units 全是正式 ID（`validate_config.py` 无 FAIL；testMode=false 时它会拦测试 ID）
- [ ] 出包前重跑一次 `tools\sync_config.ps1`，项目里的 `adhub_config.json`（Unity `Assets/Resources/` / Flutter `assets/`）和 ad-hub 正本一致
- [ ] 配置改动已提交 ad-hub 仓库

## 代码
- [ ] 项目里搜 `ca-app-pub-` 和 MAX 广告单元 ID：除 Manifest/Info.plist 的 App ID 外不应出现
- [ ] 项目里搜 `MaxSdk.` / `MobileAds.` / `AppLovinMAX.` / `InterstitialAd.load`：只能在 AdHub 内
- [ ] Unity：`Assets/AdHub/VERSION` 与 ad-hub 仓库一致；Flutter：`ad_hub` 的 `ref` 是最新 tag
- [ ] 每个配置里的 placement 在代码里都有调用；代码里的每个 placement 名字配置里都有
- [ ] `revenue` 事件已转发到统计

## 平台
- [ ] AdMob App ID 是正式的（不是 `3940256099942544`）
- [ ] iOS：SKAdNetworkItems、ATT 文案、隐私标签
- [ ] 隐私同意流程（有欧洲用户时）
- [ ] app-ads.txt 已上线

## 真机（给用户）
- [ ] Release 包里每个广告位触发一次：插屏关闭后流程继续、激励看完才给奖励、中途关闭不给
- [ ] 断网启动：游戏不卡、不崩
- [ ] 删掉/改坏项目里的 adhub_config.json 跑一次：游戏不崩，只是没广告（验证完恢复）

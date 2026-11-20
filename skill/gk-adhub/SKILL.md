---
name: gk-adhub
description: 团队统一广告接入（AdHub）。在 Unity 或 Flutter 项目里接 AdMob / AppLovin MAX 的插屏、激励视频、横幅、开屏，统一用团队的 AdHub 模块 + ad-hub 仓库里统一维护的配置（广告位 ID、开关、频控都在配置里，不写死在代码里）。当用户说"接广告""加个激励视频/插屏/横幅/banner/开屏""复活看广告""双倍奖励""AdMob""MAX""AppLovin""广告位""广告 ID""广告频率/频控""广告不出来""广告配置""上线前检查广告"，或在 Unity/Flutter 项目里提到任何和广告变现有关的事，都用这个 skill，即使没说"AdHub"。
---

# 团队统一广告接入（AdHub）

本 skill 同时给 Claude Code 和 Codex 用（同一份文件，`tools/install_skill.ps1` 装到两边）。

团队几个人各做各的项目，但广告模块统一管理：**一份共享代码 + 一个配置仓库**。
业务代码只认"广告位名字"（如 `revive`、`level_complete`），广告 ID、开关、频率全部在
`ad-hub` 仓库的 `config/apps/<app>.json` 里统一维护，再用脚本拷进项目随包发布（不走服务器）。
所以**改配置要重新出包**才对玩家生效。

## 团队设置（第一次用前由负责人填好）

| 项 | 值 |
|---|---|
| ad-hub 仓库地址 | `https://github.com/gkismet/ad-hub.git`（公开仓库） |
| 本地 ad-hub 路径 | 各人 `git clone https://github.com/gkismet/ad-hub.git` 的位置，找不到就问用户；没 clone 过就先 clone。路径里不要有中文（Flutter 打包会失败） |
| 配置进项目 | `powershell -ExecutionPolicy Bypass -File <ad-hub>\tools\sync_config.ps1 -App <app> -Project <项目根目录>`：先校验，再拷到 Unity `Assets/Resources/adhub_config.json` 或 Flutter `assets/adhub_config.json` |
| 默认聚合 | `max`（AdMob 作为 MAX 下的一个网络接入）；个别项目可用 `admob` 直连 |

Flutter 正式用 git 依赖锁 tag（见 `references/flutter.md`）；只有在改 ad-hub 本身、要本地联调时才临时用 `path:` 依赖，提交项目前改回 git。
## 铁律（每次都要遵守）

1. **业务代码里不出现任何广告 ID**，也不直接调用 `MaxSdk` / `MobileAds` / `AppLovinMAX` / `google_mobile_ads`。一律走 `AdHub`。
2. **新增广告位 = 先改配置**：在 ad-hub 仓库 `config/apps/<app>.json` 加 placement，跑 `python tools/validate_config.py`，再写调用代码。
3. **不在项目里改 AdHub 源码**（Unity 的 `Assets/AdHub/`、Flutter 的 `ad_hub` 包）。发现 bug 或缺功能，改 ad-hub 仓库本身、升版本号，再同步到项目，并告诉用户这会影响所有同事的项目。
4. 广告位命名：小写 + 下划线，`<场景>_<目的>`，如 `level_complete`、`revive`、`shop_free_coins`、`home_bottom`。名字一旦上线不要改（统计按名字聚合）。
5. 插屏、开屏的回调/await **一定接游戏流程**（没广告也要继续）；激励**只在返回 true 时发奖励**。
6. 开发阶段 `testMode: true`；上线前改 `false` 并跑上线检查（`references/release-checklist.md`）。绝不让开发者点真实广告。
7. **广告放哪由用户拍板**：新增广告位前先列建议表等用户确认（见第 1 步），不自己决定。激励给什么奖励、给多少、插屏频率，一定要用户明确答复。

## 工作流程

### 第 0 步：判断项目类型和接入状态
- Unity：有 `ProjectSettings/ProjectVersion.txt`。看 `Assets/AdHub/VERSION` 是否存在、版本是否落后于 ad-hub 仓库的 `unity/Assets/AdHub/VERSION`。
- Flutter：有 `pubspec.yaml`。看 dependencies 里有没有 `ad_hub`。
- 确认 app id：配置文件名 = app id（小写下划线）。问用户或沿用项目已有的 `AdHub.Init` 参数。

### 第 1 步：定广告位（先列建议，等用户确认）
读 `references/placement-guide.md`，然后：
- 用户只说了大概（"过关出插屏、死了能复活"）→ 按他说的去代码里找具体位置。
- 用户什么都没说 → 先读项目，按指南里的默认做法出建议。
- 两种情况都给出**建议表**（广告位名 / 格式 / 什么时候出 / 代码位置 `文件:行` / 频控），再单独问必须用户定的事：激励奖励内容和数量、插屏频率、哪些人或时机不出广告。
- **用户确认之前不改配置、不写代码。** 用户只是改单个广告位（比如"把复活换成看两次"）不用重新列整张表，确认改动即可。

### 第 2 步：配置（ad-hub 仓库）
- 新项目：复制 `config/apps/_template.json` 为 `config/apps/<app>.json`，填 `app`、`owner`、`mediation`、units、placements。
- 广告单元 ID 用户还没申请好时：`mediation: admob` + Google 测试 ID 先跑通（见 `config/apps/demo_puzzle.json`），或 units 留空串。
- 跑 `python tools/validate_config.py`，必须全部 OK。
- 详细字段和频控含义见 `references/config.md`。
- 用 `tools\sync_config.ps1` 拷进项目（**不要直接手改项目里的 adhub_config.json**，那是拷贝；改 ad-hub 里的正本再同步）。配置改动也要提交 ad-hub 仓库。

### 第 3 步：把模块接进项目
- Unity → 读 `references/unity.md`
- Flutter → 读 `references/flutter.md`
- 原生平台配置（App ID、Info.plist、SKAdNetwork、ATT、隐私同意、app-ads.txt）→ 读 `references/platform-setup.md`

### 第 4 步：写调用代码
按第 1 步确认的表，一个广告位一个广告位地接到对应代码位置。
只用这些接口：

| | Unity (`using AdHubKit;`) | Flutter (`import 'package:ad_hub/ad_hub.dart';`) |
|---|---|---|
| 初始化（启动一次） | `AdHub.Init(appId)` | `await AdHub.init(appId: ...)` |
| 插屏 | `AdHub.ShowInterstitial("p", () => Next())` | `await AdHub.showInterstitial('p'); next();` |
| 激励 | `AdHub.ShowRewarded("p", ok => { if (ok) Give(); })` | `if (await AdHub.showRewarded('p')) give();` |
| 激励按钮显隐 | `AdHub.IsRewardedReady("p")` | `await AdHub.isRewardedReady('p')` |
| 横幅 | `AdHub.ShowBanner("p")` / `AdHub.HideBanner()` | `AdHubBanner(placement: 'p')` |
| 开屏（冷启动） | `AdHub.ShowAppOpen("p", shown => EnterGame(), waitLoadSec: 3)` | `await AdHub.showAppOpen('p', waitLoad: Duration(seconds: 3)); enterGame();` |
| 开屏（回前台） | `AdHub.EnableAppOpenOnResume("p")` | `AdHub.enableAppOpenOnResume('p')` |
| 统一埋点 | `AdHub.OnEvent += e => ...` | `AdHub.events.listen((e) => ...)` |
| 去广告（买了去广告/VIP） | `AdHub.SetAdsRemoved(true)` | `AdHub.setAdsRemoved(true)` |

埋点：把 `revenue` 事件（value + currency + network + placement）转发到项目的统计（Firebase `ad_impression` 等），其余事件按需。团队收益汇总依赖这个，**每个项目都要接**。

去广告：项目接了 IapHub（iap-hub 仓库）就**不用自己调**，买了 no_ads 会自动关插屏/横幅/开屏、激励照常；没接 IapHub 的项目在自己的内购成功回调里调 `SetAdsRemoved(true)`。不要在业务代码里自己写"买了去广告就不调 ShowInterstitial"的判断。

### 第 5 步：验证
- 跑起来看日志 `[AdHub]`：配置有没有读到、每个广告位 show/closed/reward/revenue。
- 被拦截时会有 `blocked` 事件和原因（频控、未加载、配置里没有这个广告位……）。
- 你没法在真机上看广告，告诉用户需要他们在真机/模拟器上点一遍，列出要点的广告位（按第 1 步的表逐个列）。
- MAX 没有公共测试 ID：真机/模拟器测试前，先让用户在 MAX 后台 → Test Mode 把设备加成测试设备，否则出的是真实广告。

## 排查"广告不出来"
按顺序看：`AdHub` 日志里的 `blocked` 原因 → 有没有"找不到/读不到 adhub_config.json"或"app 不是 xxx"的警告 → 项目里的配置是不是 ad-hub 最新版（重跑 sync_config）→ `enabled` / placement `enabled` → 频控（首次插屏延迟默认 60 秒！）→ `load_failed` 的错误码 → 平台配置（App ID、SDK Key）→ 新广告单元刚建好通常要几小时才有填充。

## 什么时候改 ad-hub 本身
多个项目都需要的能力（新格式如开屏/原生、新频控规则、新聚合平台）才改共享模块。改完：更新两端代码 + `VERSION` + `references/` 文档 + `CHANGELOG.md`，提醒用户发 PR 让同事知道。只有一个项目需要的特殊逻辑，写在那个项目里、包在 AdHub 调用外面。

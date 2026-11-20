# 配置说明（config/apps/<app>.json）

一个项目一个文件，文件名 = `app`。正本在 ad-hub 仓库，用 `tools\sync_config.ps1` 拷进项目，随包发布：
- Unity：`Assets/Resources/adhub_config.json`
- Flutter：`assets/adhub_config.json`（pubspec 的 `flutter.assets` 里要声明）

启动时只读这一份。读不到、`schemaVersion` 不等于 1、或 `app` 和代码里传的不一致 → 所有广告不展示，游戏照常，日志有警告。

## 字段

| 字段 | 说明 |
|---|---|
| `schemaVersion` | 固定 1 |
| `app` | app id，等于文件名 |
| `owner` | 负责同事 |
| `enabled` | 总开关。false = 全部广告关闭（紧急止血用） |
| `mediation` | `max` 或 `admob` |
| `maxSdkKey` | MAX 账号的 SDK Key（团队共用一个账号时所有项目相同）。Flutter 必填；Unity 在 Integration Manager 里填，这里可空 |
| `testMode` | true：AdMob 强制用 Google 测试 ID、MAX 打开详细日志、打印所有事件。上线必须 false |
| `units.android/ios.{interstitial,rewarded,banner,app_open}` | 广告单元 ID。mediation=max 填 MAX 的 Ad Unit ID；admob 填 `ca-app-pub-...`。没有就填 `""`，该平台该格式不出。`app_open`（开屏）0.3.0 新增，可省略 |
| `global.firstInterstitialDelaySec` | 启动后多少秒内不出插屏 |
| `global.interstitialMinIntervalSec` | 任意两次插屏的最小间隔 |
| `global.interstitialMaxPerSession` / `MaxPerDay` | 插屏总次数上限（每次启动 / 每自然日） |
| `global.appOpenMinBackgroundSec` | 回前台开屏：在后台待满多少秒才出（可省略，建议 30）。只管"回前台"，不管冷启动 |
| `placements[]` | 广告位列表 |
| `placements[].name` | 代码里用的名字 |
| `placements[].format` | `interstitial` / `rewarded` / `banner` / `app_open` |
| `placements[].enabled` | 单个广告位开关 |
| `placements[].minIntervalSec` / `maxPerSession` / `maxPerDay` | 该广告位自己的频控 |

所有数值 0 = 不限制。全局频控只作用于插屏；激励、开屏只受它自己广告位的频控。
开屏建议分两个广告位：`cold_start`（冷启动）和 `app_resume`（回前台，给 `minIntervalSec` 比如 120，避免切出切回就弹）。
Debug 包（Unity Development Build / Flutter debug）在 admob 模式下也强制用测试 ID。

## 改配置的流程
改 ad-hub 里的 `config/apps/<app>.json` → `powershell -ExecutionPolicy Bypass -File tools\sync_config.ps1 -App <app> -Project <项目根目录>`（先校验，不通过不拷）→ 提交 ad-hub 仓库和项目 → 出新包。

配置随包走：已经装在玩家手机上的版本不会变，关广告、调频率都要发新版本。

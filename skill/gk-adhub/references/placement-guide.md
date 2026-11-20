# 广告位怎么定：先看项目、列建议、等确认

广告放哪是产品决定：放多了玩家流失，放少了没收入。所以 **AI（Claude Code / Codex）不自己拍板**，流程固定是：

1. 用户说了大概（"过关出插屏、死了能复活"）→ 按用户说的找代码位置，补齐命名和频控，照样列表确认。
2. 用户什么都没说（"给这个项目接广告"）→ 先读项目，按下面的默认做法列建议表，等确认。
3. 用户确认（或改完）之后，才去改 ad-hub 配置、写调用代码。

## 第一步：读项目，找能放广告的时机

先弄清楚游戏的主循环（进游戏 → 玩一局/一关 → 结算 → 下一局），再找这些点：

| 找什么 | Unity 常见线索 | Flutter 常见线索 |
|---|---|---|
| 冷启动/启动页 | 第一个场景（Build Settings 第 0 个）、`Splash`/`Loading`/`Boot` 场景 | `main()`、`SplashPage`、首个路由 |
| 关卡/回合结束 | `LevelComplete`、`Win`、`OnGameOver`、`ShowResult`、`SceneManager.LoadScene` 下一关 | `levelComplete`、`gameOver`、结算页 `ResultPage`、`Navigator.push` 下一关 |
| 失败/死亡 | `Die`、`Lose`、`GameOver`、`Continue`/`Revive` 弹窗 | 同左 |
| 发奖励的地方 | `AddCoins`、`GiveReward`、宝箱、每日奖励、离线收益 | 同左 |
| 静态页面 | 主菜单、关卡选择、商店、结算页 | `HomePage`、`MenuPage`、`ShopPage` |
| 会切出 App 的流程 | 内购、分享、登录第三方、选图片 | 同左（这些前后要关回前台开屏） |

在项目里全文搜索这些关键词；找不到明确的点就在建议表里写"没找到 XX，需要你告诉我在哪"，不要猜。

## 第二步：按默认做法出建议

| 格式 | 默认放哪 | 不要放哪 | 建议频控（起步值） |
|---|---|---|---|
| 开屏 `app_open` | `cold_start`：冷启动启动页（`waitLoad` 3 秒）；`app_resume`：回前台 | 首次安装第一次打开可以考虑不出（新手体验） | `app_resume.minIntervalSec` 120；`global.appOpenMinBackgroundSec` 30 |
| 插屏 `interstitial` | 关卡/回合之间的自然停顿：结算页关闭 → 下一关之前 | 操作中途、玩家刚点按钮等反馈时、新手教程里 | `firstInterstitialDelaySec` 60、`interstitialMinIntervalSec` 45、每次启动 ≤ 20 |
| 激励 `rewarded` | 玩家主动选的：复活、双倍奖励、免费道具、跳过等待 | 不能强制弹；不能"看了也不给" | 一般不限；同一奖励可设 `maxPerDay` |
| 横幅 `banner` | 主菜单、关卡选择、结算页等静态页面底部 | 游戏操作区（误点）、全屏玩法画面 | 不需要 |

休闲小游戏可以全上；重度/剧情向游戏插屏要少，主要靠激励。看不出类型就问。

## 第三步：给用户的建议表（照这个格式）

```
| # | 广告位名 | 格式 | 什么时候出 | 代码位置 | 频控 |
|---|---|---|---|---|---|
| 1 | cold_start | 开屏 | 启动时，最多等 3 秒 | Boot 场景 / SplashPage | 不限 |
| 2 | level_complete | 插屏 | 过关结算点"下一关"后 | GameManager.cs:212 OnLevelComplete | 全局：启动 60 秒后、间隔 45 秒 |
| 3 | revive | 激励 | 死亡弹窗"看广告复活"按钮 | UI/ReviveDialog.cs:40 | 不限 |
| 4 | home_bottom | 横幅 | 主菜单底部 | MainMenu 场景 | — |
```

表后面**单独列出必须用户定的事**，不给默认值也行，但要明确问：
- 每个激励给什么奖励、给多少（影响游戏数值）。
- 插屏频率（首次延迟、间隔、每次启动上限）可以接受吗。
- 有没有不想出广告的人群/时机（付费用户去广告？新手前 N 关不出？）——"付费去广告"需要项目自己的判断包在 AdHub 调用外面。

用户回复"可以"或改完之后，再进入 SKILL.md 的配置和写代码步骤。

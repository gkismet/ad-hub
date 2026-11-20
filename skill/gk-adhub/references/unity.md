# Unity 接入

AdHub 以源码形式放在项目 `Assets/AdHub/`（编进 Assembly-CSharp，能直接看到 MAX / AdMob 插件，不用折腾 asmdef）。
用同步脚本从 ad-hub 仓库更新，**不要手改**。

## 1. 装 SDK（二选一，和配置里的 `mediation` 对应）

**MAX（默认）**
1. 导入 AppLovin MAX Unity Plugin（.unitypackage，从 AppLovin 后台下载）。
2. 菜单 AppLovin → Integration Manager：填 SDK Key；Mediated Networks 里安装 **Google bidding and Google AdMob** 适配器（以及要用的其他网络），填 AdMob App ID（Android / iOS 各一个）。
3. Player Settings → Other Settings → Scripting Define Symbols（Android 和 iOS 两个平台都要）加 `ADHUB_MAX`。

**AdMob 直连**
1. 导入 Google Mobile Ads Unity Plugin v9 以上。
2. Assets → Google Mobile Ads → Settings：填 Android / iOS App ID。
3. Scripting Define Symbols 加 `ADHUB_ADMOB`。

都要：Assets → External Dependency Manager → Android Resolver → Force Resolve。

两个宏都没加时模块用空实现：不出广告，编辑器里激励直接返回成功，方便先接流程。

## 2. 拷模块
```powershell
powershell -ExecutionPolicy Bypass -File <ad-hub>\tools\sync_unity.ps1 -Project <Unity项目根目录>
```
会覆盖 `Assets/AdHub/`。然后拷配置：
```powershell
powershell -ExecutionPolicy Bypass -File <ad-hub>\tools\sync_config.ps1 -App <app> -Project <Unity项目根目录>
```
得到 `Assets/Resources/adhub_config.json`（出包前再同步一次最新的）。

## 3. 初始化
在第一个场景的启动脚本里：
```csharp
using AdHubKit;

void Awake()
{
    AdHub.OnEvent += e =>
    {
        if (e.type == "revenue")
        {
            // 例：Firebase
            // FirebaseAnalytics.LogEvent("ad_impression",
            //     new Parameter("ad_platform", "applovin_max" 或 "admob"),
            //     new Parameter("ad_source", e.network), new Parameter("ad_format", e.format.ToString()),
            //     new Parameter("ad_unit_name", e.placement),
            //     new Parameter("value", e.value), new Parameter("currency", e.currency));
        }
    };
    AdHub.Init("my_app_id");   // 读 Assets/Resources/adhub_config.json
}
```
iOS：如果要出个性化广告，在 Init 之前完成 ATT 弹窗（见 platform-setup.md）。MAX 自带 Terms & Privacy Policy Flow，可在 Integration Manager 打开。

## 4. 调用
```csharp
// 关卡结束
AdHub.ShowInterstitial("level_complete", () => LoadNextLevel());

// 复活
reviveButton.gameObject.SetActive(AdHub.IsRewardedReady("revive"));
reviveButton.onClick.AddListener(() =>
    AdHub.ShowRewarded("revive", ok => { if (ok) Revive(); else ShowGameOver(); }));

// 横幅
AdHub.ShowBanner("home_bottom");
AdHub.HideBanner();

// 开屏（冷启动）：启动场景里调，最多等 3 秒加载，没广告/超时 shown=false，照样进游戏
AdHub.ShowAppOpen("cold_start", shown => SceneManager.LoadScene("Home"), waitLoadSec: 3f);

// 开屏（回前台）：Init 之后调一次
AdHub.EnableAppOpenOnResume("app_resume");
```
开屏：回前台的判断用 `OnApplicationPause`；因为看广告/点广告进的后台、或后台不足 `appOpenMinBackgroundSec` 秒不出。
付费、登录第三方等会切出 App 的流程前先 `AdHub.EnableAppOpenOnResume(null)`，回来再打开。
全屏广告期间如需暂停音乐，监听 `AdHub.OnEvent` 的 `show` / `closed`。
`IsRewardedReady` 是即时状态，按钮显隐最好在界面打开时 + 每秒刷一次。

## 已知注意
- MAX 插件 8.x 起横幅推荐 `CreateBanner(id, AdViewConfiguration)`；模块里用的旧签名仍可用，出现弃用警告属正常。
- AdMob 回调已设 `MobileAds.RaiseAdEventsOnUnityMainThread = true`，回调都在主线程。
- 首次插屏默认启动 60 秒后才出（`firstInterstitialDelaySec`），测试时别以为坏了。

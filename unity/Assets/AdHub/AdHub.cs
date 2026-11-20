// AdHub —— 团队统一广告模块（Unity）。不要在项目里直接改这个目录，改动提到 ad-hub 仓库。
//
// 用法：
//   AdHub.Init("my_app_id");     // 启动时一次；配置读 Assets/Resources/adhub_config.json（由 ad-hub 的 sync_config.ps1 拷入）
//   AdHub.ShowInterstitial("level_complete", () => NextLevel());    // 回调一定会被调用
//   AdHub.ShowRewarded("revive", ok => { if (ok) Revive(); });
//   reviveButton.SetActive(AdHub.IsRewardedReady("revive"));
//   AdHub.ShowAppOpen("cold_start", shown => EnterGame(), waitLoadSec: 3);   // 冷启动开屏
//   AdHub.EnableAppOpenOnResume("app_resume");                               // 回前台开屏
//   AdHub.OnEvent += e => MyAnalytics.Log(e);
using System;
using UnityEngine;

namespace AdHubKit
{
    public static class AdHub
    {
        public const string Version = "0.3.0";
        const string ConfigResource = "adhub_config"; // Assets/Resources/adhub_config.json

        public static event Action<AdEvent> OnEvent;
        public static event Action OnReady;
        public static bool IsReady { get; private set; }
        public static AdHubConfig Config { get; private set; }

        static IAdProvider provider;
        static FrequencyCapper capper;
        static Runner runner;
        static string appId;

        // 全屏广告进行中/刚点过广告时进后台，回来不出开屏（否则插屏一关又弹开屏）
        static int fullscreen;
        static float lastClick = -100f;
        static string resumePlacement;
        static float pausedAt = -1f;
        static bool pausedByAd;

        public static void Init(string appId, Action onReady = null)
        {
            if (runner != null) { if (onReady != null) { if (IsReady) onReady(); else OnReady += onReady; } return; }
            AdHub.appId = appId;
            if (onReady != null) OnReady += onReady;
            var go = new GameObject("[AdHub]");
            UnityEngine.Object.DontDestroyOnLoad(go);
            runner = go.AddComponent<Runner>();

            var ta = Resources.Load<TextAsset>(ConfigResource);
            var cfg = ta != null ? Parse(ta.text) : null;
            if (ta == null) Debug.LogWarning("[AdHub] 找不到 Assets/Resources/adhub_config.json（用 ad-hub 的 tools/sync_config.ps1 拷入）");

            Config = cfg;
            capper = new FrequencyCapper(cfg);
            if (cfg == null || !cfg.enabled)
            {
                Debug.LogWarning("[AdHub] 没有可用配置或广告总开关关闭，所有广告不展示");
                Ready();
                return;
            }

            provider = CreateProvider(cfg.mediation);
            provider.OnEvent += Emit;
            provider.Initialize(cfg, cfg.CurrentUnits ?? new AdUnits(), Ready);
        }

        static AdHubConfig Parse(string json)
        {
            try
            {
                var c = JsonUtility.FromJson<AdHubConfig>(json);
                if (c == null || c.schemaVersion != 1 || c.app != appId)
                {
                    Debug.LogWarning($"[AdHub] 配置无效（schemaVersion 不是 1，或 app 不是 {appId}）");
                    return null;
                }
                return c;
            }
            catch (Exception e)
            {
                Debug.LogWarning($"[AdHub] 配置解析失败: {e.Message}");
                return null;
            }
        }

        static IAdProvider CreateProvider(string mediation)
        {
#if ADHUB_MAX
            if (mediation == "max") return new MaxProvider(runner);
#endif
#if ADHUB_ADMOB
            if (mediation == "admob") return new AdMobProvider(runner);
#endif
            Debug.LogWarning($"[AdHub] mediation={mediation} 对应的 SDK 未启用");
            return new NullProvider();
        }

        static void Ready()
        {
            IsReady = true;
            var cb = OnReady; OnReady = null;
            cb?.Invoke();
        }

        static void Emit(AdEvent e)
        {
            if (e.type == "click") lastClick = Time.realtimeSinceStartup;
            if (Config != null && Config.testMode) Debug.Log(e.ToString());
            OnEvent?.Invoke(e);
        }

        // ---------- 业务接口 ----------

        /// <summary>按配置和频控判断这个广告位现在能不能出（不管广告是否已加载）。</summary>
        public static bool CanShow(string placement) => Check(placement, out _, out _) == null;

        /// <summary>激励按钮要不要显示：频控允许 + 广告已加载。</summary>
        public static bool IsRewardedReady(string placement) =>
            CanShow(placement) && provider != null && provider.IsReady(AdFormat.Rewarded);

        /// <summary>插屏。onDone 无论出没出广告都会回调，游戏流程接在 onDone 后面。</summary>
        public static void ShowInterstitial(string placement, Action onDone = null)
        {
            var reason = Check(placement, out var p, out _);
            if (reason == null && p.Format != AdFormat.Interstitial) reason = "广告位格式不是 interstitial";
            if (reason == null && !provider.IsReady(AdFormat.Interstitial)) reason = "广告未加载";
            if (reason != null) { Blocked(placement, AdFormat.Interstitial, reason); onDone?.Invoke(); return; }

            fullscreen++;
            provider.ShowInterstitial(placement, shown =>
            {
                fullscreen--;
                if (shown) capper.Record(p);
                onDone?.Invoke();
            });
        }

        /// <summary>激励。onResult(true) 才发奖励。</summary>
        public static void ShowRewarded(string placement, Action<bool> onResult)
        {
            var reason = Check(placement, out var p, out _);
            if (reason == null && p.Format != AdFormat.Rewarded) reason = "广告位格式不是 rewarded";
            if (reason == null && !provider.IsReady(AdFormat.Rewarded)) reason = "广告未加载";
            if (reason != null) { Blocked(placement, AdFormat.Rewarded, reason); onResult?.Invoke(false); return; }

            capper.Record(p);
            fullscreen++;
            provider.ShowRewarded(placement, ok => { fullscreen--; onResult?.Invoke(ok); });
        }

        /// <summary>
        /// 开屏。onDone(true) = 真的展示过（已关闭）；没广告/被拦截回调 false。无论如何 onDone 之后进游戏。
        /// waitLoadSec：冷启动时广告多半还没加载好，最多等这么久（等 Init + 等加载），超时就跳过。
        /// </summary>
        public static void ShowAppOpen(string placement, Action<bool> onDone = null, float waitLoadSec = 0f)
        {
            if (runner == null) { Blocked(placement, AdFormat.AppOpen, "AdHub 未初始化完成"); onDone?.Invoke(false); return; }
            runner.StartCoroutine(AppOpenRoutine(placement, onDone, waitLoadSec));
        }

        static System.Collections.IEnumerator AppOpenRoutine(string placement, Action<bool> onDone, float waitLoadSec)
        {
            float deadline = Time.realtimeSinceStartup + waitLoadSec;
            while (!IsReady && Time.realtimeSinceStartup < deadline) yield return null;
            var reason = Check(placement, out var p, out _);
            if (reason == null && p.Format != AdFormat.AppOpen) reason = "广告位格式不是 app_open";
            if (reason == null)
            {
                while (!provider.IsReady(AdFormat.AppOpen) && Time.realtimeSinceStartup < deadline)
                    yield return new WaitForSecondsRealtime(0.2f);
                if (!provider.IsReady(AdFormat.AppOpen)) reason = "广告未加载";
            }
            if (reason == null && fullscreen > 0) reason = "已有全屏广告在展示";
            if (reason != null) { Blocked(placement, AdFormat.AppOpen, reason); onDone?.Invoke(false); yield break; }

            fullscreen++;
            provider.ShowAppOpen(placement, shown =>
            {
                fullscreen--;
                if (shown) capper.Record(p);
                onDone?.Invoke(shown);
            });
        }

        /// <summary>
        /// 打开"回前台出开屏"：App 从后台回来时自动展示这个广告位。
        /// 在后台不足 global.appOpenMinBackgroundSec 秒、或是因为看广告/点广告才进的后台，都不出。传 null 关闭。
        /// </summary>
        public static void EnableAppOpenOnResume(string placement) => resumePlacement = placement;

        static void OnPause(bool paused)
        {
            float now = Time.realtimeSinceStartup;
            if (paused)
            {
                pausedAt = now;
                pausedByAd = fullscreen > 0 || now - lastClick < 5f;
                return;
            }
            if (pausedAt < 0f || string.IsNullOrEmpty(resumePlacement)) return;
            float bg = now - pausedAt;
            pausedAt = -1f;
            if (pausedByAd || fullscreen > 0) return;
            int min = Config != null && Config.global != null ? Config.global.appOpenMinBackgroundSec : 0;
            if (min > 0 && bg < min) { Blocked(resumePlacement, AdFormat.AppOpen, $"后台时间不足 {min} 秒"); return; }
            ShowAppOpen(resumePlacement);
        }

        public static void ShowBanner(string placement)
        {
            var reason = Check(placement, out var p, out _);
            if (reason == null && p.Format != AdFormat.Banner) reason = "广告位格式不是 banner";
            if (reason != null) { Blocked(placement, AdFormat.Banner, reason); return; }
            provider.ShowBanner(placement);
        }

        public static void HideBanner() => provider?.HideBanner();

        static string Check(string placement, out Placement p, out AdFormat fmt)
        {
            p = null; fmt = AdFormat.Interstitial;
            if (!IsReady || Config == null) return "AdHub 未初始化完成";
            if (!Config.enabled) return "总开关关闭";
            if (provider == null) return "没有广告 SDK";
            p = Config.Find(placement);
            if (p == null) return "配置里没有这个广告位（先在 ad-hub 仓库 config 里加）";
            fmt = p.Format;
            if (!p.enabled) return "广告位已关闭";
            return capper.Check(p);
        }

        static void Blocked(string placement, AdFormat f, string reason) =>
            Emit(new AdEvent { type = "blocked", placement = placement, format = f, network = provider?.Name, message = reason });

        internal class Runner : MonoBehaviour
        {
            void OnApplicationPause(bool paused) => OnPause(paused);
        }
    }
}

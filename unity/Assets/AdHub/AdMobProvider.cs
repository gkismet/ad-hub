// Google AdMob 直连适配（不经过 MAX）。需要：Google Mobile Ads Unity Plugin v9+，
// Assets → Google Mobile Ads → Settings 里填 App ID，Scripting Define Symbols 加 ADHUB_ADMOB。
#if ADHUB_ADMOB
using System;
using GoogleMobileAds.Api;
using UnityEngine;

namespace AdHubKit
{
    internal class AdMobProvider : IAdProvider
    {
        public event Action<AdEvent> OnEvent;
        public string Name => "admob";

        // Google 官方测试 ID：testMode=true 或 Development Build 时强制使用，防止自点被封号
#if UNITY_IOS
        static readonly AdUnits TestUnits = new AdUnits {
            interstitial = "ca-app-pub-3940256099942544/4411468910",
            rewarded = "ca-app-pub-3940256099942544/1712485313",
            banner = "ca-app-pub-3940256099942544/2934735716",
            app_open = "ca-app-pub-3940256099942544/5575463023" };
#else
        static readonly AdUnits TestUnits = new AdUnits {
            interstitial = "ca-app-pub-3940256099942544/1033173712",
            rewarded = "ca-app-pub-3940256099942544/5224354917",
            banner = "ca-app-pub-3940256099942544/6300978111",
            app_open = "ca-app-pub-3940256099942544/9257395921" };
#endif

        readonly MonoBehaviour runner;
        AdUnits units;
        InterstitialAd inter;
        RewardedAd rewarded;
        BannerView banner;
        AppOpenAd appOpen;
        DateTime appOpenLoadedAt;
        static readonly TimeSpan AppOpenTtl = TimeSpan.FromHours(4); // AdMob 开屏加载后 4 小时过期
        bool loadingInter, loadingRew, loadingOpen;
        int interRetry, rewRetry, openRetry;
        Action<bool> interDone, rewDone, openDone;
        string interPlacement, rewPlacement, bannerPlacement, openPlacement;
        bool rewEarned;

        public AdMobProvider(MonoBehaviour runner) { this.runner = runner; }

        public void Initialize(AdHubConfig cfg, AdUnits real, Action onReady)
        {
            bool test = cfg.testMode || Debug.isDebugBuild;
            units = test ? Mask(real) : real;
            MobileAds.RaiseAdEventsOnUnityMainThread = true;
            MobileAds.Initialize(_ =>
            {
                LoadInter();
                LoadRewarded();
                LoadAppOpen();
                onReady?.Invoke();
            });
        }

        // 测试时只替换配置里非空的格式，保持"该平台没配就不出"的语义
        static AdUnits Mask(AdUnits r) => new AdUnits
        {
            interstitial = string.IsNullOrEmpty(r.interstitial) ? "" : TestUnits.interstitial,
            rewarded = string.IsNullOrEmpty(r.rewarded) ? "" : TestUnits.rewarded,
            banner = string.IsNullOrEmpty(r.banner) ? "" : TestUnits.banner,
            app_open = string.IsNullOrEmpty(r.app_open) ? "" : TestUnits.app_open,
        };

        public bool IsReady(AdFormat f)
        {
            switch (f)
            {
                case AdFormat.Interstitial: return inter != null && inter.CanShowAd();
                case AdFormat.Rewarded: return rewarded != null && rewarded.CanShowAd();
                case AdFormat.AppOpen:
                    if (appOpen != null && DateTime.UtcNow - appOpenLoadedAt > AppOpenTtl) { appOpen.Destroy(); appOpen = null; LoadAppOpen(); }
                    return appOpen != null && appOpen.CanShowAd();
                default: return !string.IsNullOrEmpty(units.banner);
            }
        }

        public void ShowInterstitial(string placement, Action<bool> onClosed)
        {
            interPlacement = placement; interDone = onClosed;
            inter.Show();
        }

        public void ShowRewarded(string placement, Action<bool> onFinished)
        {
            rewPlacement = placement; rewDone = onFinished; rewEarned = false;
            rewarded.Show(reward =>
            {
                rewEarned = true;
                Emit("reward", rewPlacement, AdFormat.Rewarded);
            });
        }

        public void ShowAppOpen(string placement, Action<bool> onClosed)
        {
            openPlacement = placement; openDone = onClosed;
            appOpen.Show();
        }

        public void ShowBanner(string placement)
        {
            if (string.IsNullOrEmpty(units.banner)) return;
            bannerPlacement = placement;
            if (banner == null)
            {
                var size = AdSize.GetCurrentOrientationAnchoredAdaptiveBannerAdSizeWithWidth(AdSize.FullWidth);
                banner = new BannerView(units.banner, size, AdPosition.Bottom);
                banner.OnBannerAdLoadFailed += e => Emit("load_failed", bannerPlacement, AdFormat.Banner, e.GetMessage());
                banner.OnAdPaid += v => Revenue(bannerPlacement, AdFormat.Banner, v);
                banner.LoadAd(new AdRequest());
            }
            banner.Show();
        }

        public void HideBanner() => banner?.Hide();

        void LoadInter()
        {
            if (string.IsNullOrEmpty(units.interstitial) || loadingInter) return;
            loadingInter = true;
            inter?.Destroy(); inter = null;
            InterstitialAd.Load(units.interstitial, new AdRequest(), (ad, err) =>
            {
                loadingInter = false;
                if (err != null || ad == null)
                {
                    Emit("load_failed", null, AdFormat.Interstitial, err?.GetMessage());
                    runner.StartCoroutine(Retry.After(Retry.DelaySec(++interRetry), LoadInter));
                    return;
                }
                interRetry = 0;
                inter = ad;
                var I = AdFormat.Interstitial;
                ad.OnAdFullScreenContentOpened += () => Emit("show", interPlacement, I);
                ad.OnAdClicked += () => Emit("click", interPlacement, I);
                ad.OnAdPaid += v => Revenue(interPlacement, I, v);
                ad.OnAdFullScreenContentFailed += e =>
                {
                    Emit("show_failed", interPlacement, I, e.GetMessage());
                    LoadInter();
                    Finish(ref interDone, false);
                };
                ad.OnAdFullScreenContentClosed += () =>
                {
                    Emit("closed", interPlacement, I);
                    LoadInter();
                    Finish(ref interDone, true);
                };
            });
        }

        void LoadRewarded()
        {
            if (string.IsNullOrEmpty(units.rewarded) || loadingRew) return;
            loadingRew = true;
            rewarded?.Destroy(); rewarded = null;
            RewardedAd.Load(units.rewarded, new AdRequest(), (ad, err) =>
            {
                loadingRew = false;
                if (err != null || ad == null)
                {
                    Emit("load_failed", null, AdFormat.Rewarded, err?.GetMessage());
                    runner.StartCoroutine(Retry.After(Retry.DelaySec(++rewRetry), LoadRewarded));
                    return;
                }
                rewRetry = 0;
                rewarded = ad;
                var R = AdFormat.Rewarded;
                ad.OnAdFullScreenContentOpened += () => Emit("show", rewPlacement, R);
                ad.OnAdClicked += () => Emit("click", rewPlacement, R);
                ad.OnAdPaid += v => Revenue(rewPlacement, R, v);
                ad.OnAdFullScreenContentFailed += e =>
                {
                    Emit("show_failed", rewPlacement, R, e.GetMessage());
                    LoadRewarded();
                    Finish(ref rewDone, false);
                };
                ad.OnAdFullScreenContentClosed += () =>
                {
                    Emit("closed", rewPlacement, R);
                    LoadRewarded();
                    Finish(ref rewDone, rewEarned);
                };
            });
        }

        void LoadAppOpen()
        {
            if (string.IsNullOrEmpty(units.app_open) || loadingOpen) return;
            loadingOpen = true;
            appOpen?.Destroy(); appOpen = null;
            AppOpenAd.Load(units.app_open, new AdRequest(), (ad, err) =>
            {
                loadingOpen = false;
                if (err != null || ad == null)
                {
                    Emit("load_failed", null, AdFormat.AppOpen, err?.GetMessage());
                    runner.StartCoroutine(Retry.After(Retry.DelaySec(++openRetry), LoadAppOpen));
                    return;
                }
                openRetry = 0;
                appOpen = ad;
                appOpenLoadedAt = DateTime.UtcNow;
                var O = AdFormat.AppOpen;
                ad.OnAdFullScreenContentOpened += () => Emit("show", openPlacement, O);
                ad.OnAdClicked += () => Emit("click", openPlacement, O);
                ad.OnAdPaid += v => Revenue(openPlacement, O, v);
                ad.OnAdFullScreenContentFailed += e =>
                {
                    Emit("show_failed", openPlacement, O, e.GetMessage());
                    LoadAppOpen();
                    Finish(ref openDone, false);
                };
                ad.OnAdFullScreenContentClosed += () =>
                {
                    Emit("closed", openPlacement, O);
                    LoadAppOpen();
                    Finish(ref openDone, true);
                };
            });
        }

        void Emit(string type, string placement, AdFormat f, string msg = null) =>
            OnEvent?.Invoke(new AdEvent { type = type, placement = placement, format = f, network = Name, message = msg });

        void Revenue(string placement, AdFormat f, AdValue v) =>
            OnEvent?.Invoke(new AdEvent
            {
                type = "revenue", placement = placement, format = f, network = Name,
                value = v.Value / 1_000_000.0, currency = v.CurrencyCode,
            });

        static void Finish(ref Action<bool> cb, bool result)
        {
            var c = cb; cb = null;
            c?.Invoke(result);
        }
    }
}
#endif

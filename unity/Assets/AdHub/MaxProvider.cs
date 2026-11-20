// AppLovin MAX 适配。需要：导入 AppLovin MAX Unity Plugin，SDK Key 在 Integration Manager 里填，
// Player Settings → Scripting Define Symbols 加 ADHUB_MAX。AdMob 作为 MAX 下的一个网络（Google bidding）接入。
#if ADHUB_MAX
using System;
using UnityEngine;

namespace AdHubKit
{
    internal class MaxProvider : IAdProvider
    {
        public event Action<AdEvent> OnEvent;
        public string Name => "max";

        readonly MonoBehaviour runner;
        AdUnits units;
        int interRetry, rewRetry, openRetry;
        Action<bool> interDone, rewDone, openDone;
        string interPlacement, rewPlacement, openPlacement;
        bool rewEarned, bannerCreated;

        public MaxProvider(MonoBehaviour runner) { this.runner = runner; }

        public void Initialize(AdHubConfig cfg, AdUnits units, Action onReady)
        {
            this.units = units;
            if (cfg.testMode) MaxSdk.SetVerboseLogging(true);
            MaxSdkCallbacks.OnSdkInitializedEvent += _ =>
            {
                Hook();
                LoadInter();
                LoadRewarded();
                LoadAppOpen();
                onReady?.Invoke();
            };
            MaxSdk.InitializeSdk();
        }

        public bool IsReady(AdFormat f)
        {
            switch (f)
            {
                case AdFormat.Interstitial: return !string.IsNullOrEmpty(units.interstitial) && MaxSdk.IsInterstitialReady(units.interstitial);
                case AdFormat.Rewarded: return !string.IsNullOrEmpty(units.rewarded) && MaxSdk.IsRewardedAdReady(units.rewarded);
                case AdFormat.AppOpen: return !string.IsNullOrEmpty(units.app_open) && MaxSdk.IsAppOpenAdReady(units.app_open);
                default: return !string.IsNullOrEmpty(units.banner);
            }
        }

        public void ShowInterstitial(string placement, Action<bool> onClosed)
        {
            interPlacement = placement; interDone = onClosed;
            MaxSdk.ShowInterstitial(units.interstitial, placement);
        }

        public void ShowRewarded(string placement, Action<bool> onFinished)
        {
            rewPlacement = placement; rewDone = onFinished; rewEarned = false;
            MaxSdk.ShowRewardedAd(units.rewarded, placement);
        }

        public void ShowAppOpen(string placement, Action<bool> onClosed)
        {
            openPlacement = placement; openDone = onClosed;
            MaxSdk.ShowAppOpenAd(units.app_open, placement);
        }

        public void ShowBanner(string placement)
        {
            if (string.IsNullOrEmpty(units.banner)) return;
            if (!bannerCreated)
            {
                // 插件 8.x 起推荐 CreateBanner(id, new MaxSdkBase.AdViewConfiguration(...))，旧签名仍可用
                MaxSdk.CreateBanner(units.banner, MaxSdkBase.BannerPosition.BottomCenter);
                MaxSdk.SetBannerPlacement(units.banner, placement);
                bannerCreated = true;
            }
            MaxSdk.ShowBanner(units.banner);
        }

        public void HideBanner()
        {
            if (bannerCreated) MaxSdk.HideBanner(units.banner);
        }

        void LoadInter() { if (!string.IsNullOrEmpty(units.interstitial)) MaxSdk.LoadInterstitial(units.interstitial); }
        void LoadRewarded() { if (!string.IsNullOrEmpty(units.rewarded)) MaxSdk.LoadRewardedAd(units.rewarded); }
        void LoadAppOpen() { if (!string.IsNullOrEmpty(units.app_open)) MaxSdk.LoadAppOpenAd(units.app_open); }

        void Emit(string type, string placement, AdFormat f, MaxSdkBase.AdInfo info = null, string msg = null, double value = 0)
        {
            OnEvent?.Invoke(new AdEvent
            {
                type = type, placement = placement, format = f,
                network = info != null ? info.NetworkName : Name,
                value = value, currency = value > 0 ? "USD" : null, message = msg,
            });
        }

        void Hook()
        {
            var I = AdFormat.Interstitial;
            MaxSdkCallbacks.Interstitial.OnAdLoadedEvent += (id, info) => interRetry = 0;
            MaxSdkCallbacks.Interstitial.OnAdLoadFailedEvent += (id, err) =>
            {
                Emit("load_failed", null, I, null, err.Code + " " + err.Message);
                runner.StartCoroutine(Retry.After(Retry.DelaySec(++interRetry), LoadInter));
            };
            MaxSdkCallbacks.Interstitial.OnAdDisplayedEvent += (id, info) => Emit("show", interPlacement, I, info);
            MaxSdkCallbacks.Interstitial.OnAdClickedEvent += (id, info) => Emit("click", interPlacement, I, info);
            MaxSdkCallbacks.Interstitial.OnAdRevenuePaidEvent += (id, info) => Emit("revenue", interPlacement, I, info, null, info.Revenue);
            MaxSdkCallbacks.Interstitial.OnAdDisplayFailedEvent += (id, err, info) =>
            {
                Emit("show_failed", interPlacement, I, info, err.Code + " " + err.Message);
                LoadInter();
                Finish(ref interDone, false);
            };
            MaxSdkCallbacks.Interstitial.OnAdHiddenEvent += (id, info) =>
            {
                Emit("closed", interPlacement, I, info);
                LoadInter();
                Finish(ref interDone, true);
            };

            var R = AdFormat.Rewarded;
            MaxSdkCallbacks.Rewarded.OnAdLoadedEvent += (id, info) => rewRetry = 0;
            MaxSdkCallbacks.Rewarded.OnAdLoadFailedEvent += (id, err) =>
            {
                Emit("load_failed", null, R, null, err.Code + " " + err.Message);
                runner.StartCoroutine(Retry.After(Retry.DelaySec(++rewRetry), LoadRewarded));
            };
            MaxSdkCallbacks.Rewarded.OnAdDisplayedEvent += (id, info) => Emit("show", rewPlacement, R, info);
            MaxSdkCallbacks.Rewarded.OnAdClickedEvent += (id, info) => Emit("click", rewPlacement, R, info);
            MaxSdkCallbacks.Rewarded.OnAdRevenuePaidEvent += (id, info) => Emit("revenue", rewPlacement, R, info, null, info.Revenue);
            MaxSdkCallbacks.Rewarded.OnAdReceivedRewardEvent += (id, reward, info) =>
            {
                rewEarned = true;
                Emit("reward", rewPlacement, R, info);
            };
            MaxSdkCallbacks.Rewarded.OnAdDisplayFailedEvent += (id, err, info) =>
            {
                Emit("show_failed", rewPlacement, R, info, err.Code + " " + err.Message);
                LoadRewarded();
                Finish(ref rewDone, false);
            };
            MaxSdkCallbacks.Rewarded.OnAdHiddenEvent += (id, info) =>
            {
                Emit("closed", rewPlacement, R, info);
                LoadRewarded();
                Finish(ref rewDone, rewEarned);
            };

            var O = AdFormat.AppOpen;
            MaxSdkCallbacks.AppOpen.OnAdLoadedEvent += (id, info) => openRetry = 0;
            MaxSdkCallbacks.AppOpen.OnAdLoadFailedEvent += (id, err) =>
            {
                Emit("load_failed", null, O, null, err.Code + " " + err.Message);
                runner.StartCoroutine(Retry.After(Retry.DelaySec(++openRetry), LoadAppOpen));
            };
            MaxSdkCallbacks.AppOpen.OnAdDisplayedEvent += (id, info) => Emit("show", openPlacement, O, info);
            MaxSdkCallbacks.AppOpen.OnAdClickedEvent += (id, info) => Emit("click", openPlacement, O, info);
            MaxSdkCallbacks.AppOpen.OnAdRevenuePaidEvent += (id, info) => Emit("revenue", openPlacement, O, info, null, info.Revenue);
            MaxSdkCallbacks.AppOpen.OnAdDisplayFailedEvent += (id, err, info) =>
            {
                Emit("show_failed", openPlacement, O, info, err.Code + " " + err.Message);
                LoadAppOpen();
                Finish(ref openDone, false);
            };
            MaxSdkCallbacks.AppOpen.OnAdHiddenEvent += (id, info) =>
            {
                Emit("closed", openPlacement, O, info);
                LoadAppOpen();
                Finish(ref openDone, true);
            };

            MaxSdkCallbacks.Banner.OnAdLoadFailedEvent += (id, err) => Emit("load_failed", null, AdFormat.Banner, null, err.Code + " " + err.Message);
            MaxSdkCallbacks.Banner.OnAdRevenuePaidEvent += (id, info) => Emit("revenue", info.Placement, AdFormat.Banner, info, null, info.Revenue);
        }

        static void Finish(ref Action<bool> cb, bool result)
        {
            var c = cb; cb = null;
            c?.Invoke(result);
        }
    }
}
#endif

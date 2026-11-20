using System;
using System.Collections;
using UnityEngine;

namespace AdHubKit
{
    /// <summary>聚合平台适配层。业务代码不直接用，统一走 AdHub。</summary>
    internal interface IAdProvider
    {
        event Action<AdEvent> OnEvent;
        string Name { get; }
        void Initialize(AdHubConfig cfg, AdUnits units, Action onReady);
        bool IsReady(AdFormat format);
        /// <param name="onClosed">true = 广告真的展示过</param>
        void ShowInterstitial(string placement, Action<bool> onClosed);
        /// <param name="onFinished">true = 用户拿到奖励</param>
        void ShowRewarded(string placement, Action<bool> onFinished);
        /// <param name="onClosed">true = 开屏真的展示过</param>
        void ShowAppOpen(string placement, Action<bool> onClosed);
        void ShowBanner(string placement);
        void HideBanner();
    }

    internal static class Retry
    {
        // 加载失败指数退避：2,4,8...最多 64 秒
        public static float DelaySec(int attempt) => Mathf.Pow(2, Mathf.Clamp(attempt, 1, 6));

        public static IEnumerator After(float sec, Action a)
        {
            yield return new WaitForSecondsRealtime(sec);
            a();
        }
    }

    /// <summary>没装任何 SDK / 没定义宏时用：不出广告，流程照走。编辑器里激励直接给奖励方便测流程。</summary>
    internal class NullProvider : IAdProvider
    {
        public event Action<AdEvent> OnEvent;
        public string Name => "null";

        public void Initialize(AdHubConfig cfg, AdUnits units, Action onReady)
        {
            Debug.LogWarning("[AdHub] 没有可用的广告 SDK（Player Settings 里需定义 ADHUB_MAX 或 ADHUB_ADMOB）");
            onReady?.Invoke();
        }

        public bool IsReady(AdFormat format) => Application.isEditor;

        public void ShowInterstitial(string placement, Action<bool> onClosed)
        {
            OnEvent?.Invoke(new AdEvent { type = "show", placement = placement, format = AdFormat.Interstitial, network = Name });
            onClosed?.Invoke(Application.isEditor);
        }

        public void ShowRewarded(string placement, Action<bool> onFinished)
        {
            OnEvent?.Invoke(new AdEvent { type = "show", placement = placement, format = AdFormat.Rewarded, network = Name });
            onFinished?.Invoke(Application.isEditor);
        }

        public void ShowAppOpen(string placement, Action<bool> onClosed)
        {
            OnEvent?.Invoke(new AdEvent { type = "show", placement = placement, format = AdFormat.AppOpen, network = Name });
            onClosed?.Invoke(Application.isEditor);
        }

        public void ShowBanner(string placement) { }
        public void HideBanner() { }
    }
}

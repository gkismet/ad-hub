// AdHub —— 团队统一广告模块（Unity）。不要在项目里直接改这个目录，改动提到 ad-hub 仓库。
using System;
using System.Collections.Generic;

namespace AdHubKit
{
    public enum AdFormat { Interstitial, Rewarded, Banner, AppOpen }

    // 字段名必须和 config/apps/*.json 一致（JsonUtility 不支持字典，所以 placements 用数组）
    [Serializable]
    public class AdHubConfig
    {
        public int schemaVersion;
        public string app;
        public string owner;
        public bool enabled;
        public string mediation;   // "max" | "admob"
        public string maxSdkKey;   // Unity 端不用（在 Integration Manager 里填），Flutter 端用
        public bool testMode;
        public AdUnitsByPlatform units;
        public GlobalCaps global;
        public List<Placement> placements = new List<Placement>();

        public AdUnits CurrentUnits
        {
            get
            {
#if UNITY_IOS
                return units != null ? units.ios : null;
#else
                return units != null ? units.android : null;
#endif
            }
        }

        public Placement Find(string name)
        {
            if (placements == null) return null;
            foreach (var p in placements) if (p.name == name) return p;
            return null;
        }
    }

    [Serializable] public class AdUnitsByPlatform { public AdUnits android; public AdUnits ios; }

    [Serializable]
    public class AdUnits
    {
        public string interstitial;
        public string rewarded;
        public string banner;
        public string app_open;    // 0.3.0 新增，旧配置没有 = 不出开屏

        public string Get(AdFormat f)
        {
            switch (f)
            {
                case AdFormat.Interstitial: return interstitial;
                case AdFormat.Rewarded: return rewarded;
                case AdFormat.AppOpen: return app_open;
                default: return banner;
            }
        }
    }

    [Serializable]
    public class GlobalCaps
    {
        public int firstInterstitialDelaySec;
        public int interstitialMinIntervalSec;
        public int interstitialMaxPerSession;
        public int interstitialMaxPerDay;
        public int appOpenMinBackgroundSec; // 回前台开屏：后台待满这么多秒才出，0 = 不限（0.3.0 新增）
    }

    [Serializable]
    public class Placement
    {
        public string name;
        public string format;      // "interstitial" | "rewarded" | "banner" | "app_open"
        public bool enabled;
        public int minIntervalSec; // 0 = 不限
        public int maxPerSession;
        public int maxPerDay;

        public AdFormat Format
        {
            get
            {
                switch (format)
                {
                    case "rewarded": return AdFormat.Rewarded;
                    case "banner": return AdFormat.Banner;
                    case "app_open": return AdFormat.AppOpen;
                    default: return AdFormat.Interstitial;
                }
            }
        }
    }

    /// <summary>统一埋点事件。项目在 AdHub.OnEvent 里转发给自己的统计（Firebase 等）。</summary>
    public struct AdEvent
    {
        // load_failed / blocked / show / show_failed / click / closed / reward / revenue
        public string type;
        public string placement;
        public AdFormat format;
        public string network;
        public double value;     // revenue 事件：金额（已是货币单位，不是 micros）
        public string currency;
        public string message;   // 失败原因 / 被拦截原因

        public override string ToString() =>
            $"[AdHub] {type} placement={placement} format={format} network={network} value={value} {currency} {message}";
    }
}

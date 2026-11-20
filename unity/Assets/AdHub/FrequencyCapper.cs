using System;
using System.Collections.Generic;
using UnityEngine;

namespace AdHubKit
{
    /// <summary>频控：全局插屏首次延迟/间隔/会话上限/每日上限 + 每个广告位自己的上限。0 = 不限。</summary>
    internal class FrequencyCapper
    {
        const string GlobalKey = "__interstitial";
        readonly AdHubConfig cfg;
        readonly float startTime;
        readonly Dictionary<string, int> sessionCount = new Dictionary<string, int>();
        readonly Dictionary<string, float> lastShown = new Dictionary<string, float>();

        public FrequencyCapper(AdHubConfig cfg)
        {
            this.cfg = cfg;
            startTime = Time.realtimeSinceStartup;
        }

        public string Check(Placement p)
        {
            float now = Time.realtimeSinceStartup;
            if (p.Format == AdFormat.Interstitial && cfg.global != null)
            {
                var g = cfg.global;
                if (g.firstInterstitialDelaySec > 0 && now - startTime < g.firstInterstitialDelaySec) return "启动后首次插屏延迟中";
                if (g.interstitialMinIntervalSec > 0 && Since(GlobalKey, now) < g.interstitialMinIntervalSec) return "插屏全局间隔未到";
                if (g.interstitialMaxPerSession > 0 && Session(GlobalKey) >= g.interstitialMaxPerSession) return "插屏本次会话已达上限";
                if (g.interstitialMaxPerDay > 0 && Daily(GlobalKey) >= g.interstitialMaxPerDay) return "插屏今日已达上限";
            }
            if (p.minIntervalSec > 0 && Since(p.name, now) < p.minIntervalSec) return "广告位间隔未到";
            if (p.maxPerSession > 0 && Session(p.name) >= p.maxPerSession) return "广告位本次会话已达上限";
            if (p.maxPerDay > 0 && Daily(p.name) >= p.maxPerDay) return "广告位今日已达上限";
            return null;
        }

        public void Record(Placement p)
        {
            Bump(p.name);
            if (p.Format == AdFormat.Interstitial) Bump(GlobalKey);
        }

        void Bump(string key)
        {
            lastShown[key] = Time.realtimeSinceStartup;
            sessionCount[key] = Session(key) + 1;
            PlayerPrefs.SetInt(DayKey(key), Daily(key) + 1);
            PlayerPrefs.Save();
        }

        float Since(string key, float now) => lastShown.TryGetValue(key, out var t) ? now - t : float.MaxValue;
        int Session(string key) => sessionCount.TryGetValue(key, out var n) ? n : 0;
        int Daily(string key) => PlayerPrefs.GetInt(DayKey(key), 0);
        static string DayKey(string key) => "adhub." + DateTime.Now.ToString("yyyyMMdd") + "." + key;
    }
}

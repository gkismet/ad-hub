import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';

/// 频控：全局插屏首次延迟/间隔/会话上限/每日上限 + 每个广告位自己的上限。0 = 不限。
class FrequencyCapper {
  static const _global = '__interstitial';
  final AdHubConfig cfg;
  final SharedPreferences prefs;
  final DateTime _start = DateTime.now();
  final _session = <String, int>{};
  final _last = <String, DateTime>{};

  FrequencyCapper(this.cfg, this.prefs);

  /// 返回 null = 可以出；否则是被拦截原因
  String? check(Placement p) {
    final now = DateTime.now();
    if (p.format == AdHubFormat.interstitial) {
      final g = cfg.global;
      if (g.firstInterstitialDelaySec > 0 && now.difference(_start).inSeconds < g.firstInterstitialDelaySec) {
        return '启动后首次插屏延迟中';
      }
      if (g.interstitialMinIntervalSec > 0 && _since(_global, now) < g.interstitialMinIntervalSec) return '插屏全局间隔未到';
      if (g.interstitialMaxPerSession > 0 && _sess(_global) >= g.interstitialMaxPerSession) return '插屏本次会话已达上限';
      if (g.interstitialMaxPerDay > 0 && _daily(_global) >= g.interstitialMaxPerDay) return '插屏今日已达上限';
    }
    if (p.minIntervalSec > 0 && _since(p.name, now) < p.minIntervalSec) return '广告位间隔未到';
    if (p.maxPerSession > 0 && _sess(p.name) >= p.maxPerSession) return '广告位本次会话已达上限';
    if (p.maxPerDay > 0 && _daily(p.name) >= p.maxPerDay) return '广告位今日已达上限';
    return null;
  }

  void record(Placement p) {
    _bump(p.name);
    if (p.format == AdHubFormat.interstitial) _bump(_global);
  }

  void _bump(String k) {
    _last[k] = DateTime.now();
    _session[k] = _sess(k) + 1;
    prefs.setInt(_dayKey(k), _daily(k) + 1);
  }

  int _since(String k, DateTime now) {
    final t = _last[k];
    return t == null ? 1 << 30 : now.difference(t).inSeconds;
  }

  int _sess(String k) => _session[k] ?? 0;
  int _daily(String k) => prefs.getInt(_dayKey(k)) ?? 0;

  static String _dayKey(String k) {
    final d = DateTime.now();
    final ymd = '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
    return 'adhub.$ymd.$k';
  }
}

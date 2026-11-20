// 字段和 config/apps/*.json 一一对应。
import 'dart:io' show Platform;

enum AdHubFormat { interstitial, rewarded, banner, appOpen }

AdHubFormat _fmt(String? s) => switch (s) {
      'rewarded' => AdHubFormat.rewarded,
      'banner' => AdHubFormat.banner,
      'app_open' => AdHubFormat.appOpen,
      _ => AdHubFormat.interstitial,
    };

class AdUnits {
  final String interstitial, rewarded, banner, appOpen;
  const AdUnits({this.interstitial = '', this.rewarded = '', this.banner = '', this.appOpen = ''});

  factory AdUnits.fromJson(Map<String, dynamic>? j) => AdUnits(
        interstitial: (j?['interstitial'] as String?) ?? '',
        rewarded: (j?['rewarded'] as String?) ?? '',
        banner: (j?['banner'] as String?) ?? '',
        appOpen: (j?['app_open'] as String?) ?? '', // 0.3.0 新增，旧配置没有这个键 = 不出开屏
      );

  String of(AdHubFormat f) => switch (f) {
        AdHubFormat.interstitial => interstitial,
        AdHubFormat.rewarded => rewarded,
        AdHubFormat.banner => banner,
        AdHubFormat.appOpen => appOpen,
      };
}

class GlobalCaps {
  final int firstInterstitialDelaySec, interstitialMinIntervalSec, interstitialMaxPerSession, interstitialMaxPerDay;

  /// 回前台开屏：在后台待满这么多秒才出（0 = 不限）。0.3.0 新增，可省略
  final int appOpenMinBackgroundSec;
  const GlobalCaps({
    this.appOpenMinBackgroundSec = 0,
    this.firstInterstitialDelaySec = 0,
    this.interstitialMinIntervalSec = 0,
    this.interstitialMaxPerSession = 0,
    this.interstitialMaxPerDay = 0,
  });

  factory GlobalCaps.fromJson(Map<String, dynamic>? j) => GlobalCaps(
        firstInterstitialDelaySec: (j?['firstInterstitialDelaySec'] as int?) ?? 0,
        interstitialMinIntervalSec: (j?['interstitialMinIntervalSec'] as int?) ?? 0,
        interstitialMaxPerSession: (j?['interstitialMaxPerSession'] as int?) ?? 0,
        interstitialMaxPerDay: (j?['interstitialMaxPerDay'] as int?) ?? 0,
        appOpenMinBackgroundSec: (j?['appOpenMinBackgroundSec'] as int?) ?? 0,
      );
}

class Placement {
  final String name;
  final AdHubFormat format;
  final bool enabled;
  final int minIntervalSec, maxPerSession, maxPerDay; // 0 = 不限

  const Placement(this.name, this.format, this.enabled, this.minIntervalSec, this.maxPerSession, this.maxPerDay);

  factory Placement.fromJson(Map<String, dynamic> j) => Placement(
        j['name'] as String,
        _fmt(j['format'] as String?),
        (j['enabled'] as bool?) ?? false,
        (j['minIntervalSec'] as int?) ?? 0,
        (j['maxPerSession'] as int?) ?? 0,
        (j['maxPerDay'] as int?) ?? 0,
      );
}

class AdHubConfig {
  final String app;
  final bool enabled;
  final String mediation; // max | admob
  final String maxSdkKey;
  final bool testMode;
  final AdUnits android, ios;
  final GlobalCaps global;
  final Map<String, Placement> placements;

  AdHubConfig._(this.app, this.enabled, this.mediation, this.maxSdkKey, this.testMode, this.android, this.ios,
      this.global, this.placements);

  /// 不合法返回 null
  static AdHubConfig? tryParse(Map<String, dynamic> j, String expectedApp) {
    if (j['schemaVersion'] != 1 || j['app'] != expectedApp) return null;
    final units = (j['units'] as Map?)?.cast<String, dynamic>();
    final pls = <String, Placement>{};
    for (final p in (j['placements'] as List? ?? const [])) {
      final pl = Placement.fromJson((p as Map).cast<String, dynamic>());
      pls[pl.name] = pl;
    }
    return AdHubConfig._(
      expectedApp,
      (j['enabled'] as bool?) ?? false,
      (j['mediation'] as String?) ?? 'max',
      (j['maxSdkKey'] as String?) ?? '',
      (j['testMode'] as bool?) ?? false,
      AdUnits.fromJson((units?['android'] as Map?)?.cast<String, dynamic>()),
      AdUnits.fromJson((units?['ios'] as Map?)?.cast<String, dynamic>()),
      GlobalCaps.fromJson((j['global'] as Map?)?.cast<String, dynamic>()),
      pls,
    );
  }

  AdUnits get currentUnits => Platform.isIOS ? ios : android;
}

/// 统一埋点事件。type: load_failed / blocked / show / show_failed / click / closed / reward / revenue
class AdEvent {
  final String type;
  final String? placement;
  final AdHubFormat format;
  final String network;
  final double value; // revenue：货币单位（不是 micros）
  final String? currency;
  final String? message;

  const AdEvent(this.type, this.format,
      {this.placement, this.network = '', this.value = 0, this.currency, this.message});

  @override
  String toString() => '[AdHub] $type placement=$placement format=${format.name} network=$network '
      'value=$value ${currency ?? ''} ${message ?? ''}';
}

// 用法：
//   await AdHub.init(appId: 'my_app');   // 配置读 assets/adhub_config.json（由 ad-hub 的 sync_config.ps1 拷入）
//   await AdHub.showInterstitial('level_complete'); nextLevel();
//   if (await AdHub.showRewarded('revive')) revive();
//   AdHubBanner(placement: 'home_bottom')
//   await AdHub.showAppOpen('cold_start', waitLoad: const Duration(seconds: 3)); goHome();  // 冷启动开屏
//   AdHub.enableAppOpenOnResume('app_resume');                                             // 回前台开屏
//   AdHub.events.listen((e) => analytics.log(e));
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'admob_provider.dart';
import 'capper.dart';
import 'config.dart';
import 'max_provider.dart';
import 'provider.dart';

class AdHub {
  AdHub._();
  static const version = '0.3.1';
  static const defaultAsset = 'assets/adhub_config.json';

  static final _events = StreamController<AdEvent>.broadcast();

  /// 统一埋点事件流，项目自己转发到 Firebase/友盟/自建统计
  static Stream<AdEvent> get events => _events.stream;

  static AdHubConfig? config;
  static bool get isReady => _ready.isCompleted;

  /// init 完成（无论成功与否）时完成
  static Future<void> get whenReady => _ready.future;

  static final _ready = Completer<void>();
  static AdProvider? _provider;
  static FrequencyCapper? _capper;
  static bool _started = false;

  // 全屏广告进行中/刚点过广告时进后台，回来不出开屏（否则插屏一关又弹开屏）
  static int _fullscreen = 0;
  static DateTime? _lastClick;
  static AppLifecycleListener? _lifecycle;
  static String? _resumePlacement;
  static DateTime? _hiddenAt;
  static bool _hiddenByAd = false;

  static Future<void> init({required String appId, String asset = defaultAsset}) async {
    if (_started) return _ready.future;
    _started = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      AdHubConfig? cfg;
      try {
        cfg = _parse(await rootBundle.loadString(asset), appId);
      } catch (e) {
        debugPrint('[AdHub] 读不到 $asset（用 ad-hub 的 tools/sync_config.ps1 拷入，并在 pubspec 的 assets 里声明）: $e');
      }

      config = cfg;
      if (cfg == null || !cfg.enabled) {
        debugPrint('[AdHub] 没有可用配置或广告总开关关闭，所有广告不展示');
        return;
      }
      _capper = FrequencyCapper(cfg, prefs);
      final AdProvider p = cfg.mediation == 'admob' ? AdMobProvider() : MaxProvider();
      await p.initialize(cfg, cfg.currentUnits, _emit);
      _provider = p;
    } catch (e) {
      debugPrint('[AdHub] 初始化失败: $e');
    } finally {
      if (!_ready.isCompleted) _ready.complete();
    }
  }

  static AdHubConfig? _parse(String text, String appId) {
    try {
      final c = AdHubConfig.tryParse(jsonDecode(text) as Map<String, dynamic>, appId);
      if (c == null) debugPrint('[AdHub] 配置无效（schemaVersion 不是 1，或 app 不是 $appId）');
      return c;
    } catch (e) {
      debugPrint('[AdHub] 配置解析失败: $e');
      return null;
    }
  }

  static void _emit(AdEvent e) {
    if (e.type == 'click') _lastClick = DateTime.now();
    if (config?.testMode == true || kDebugMode) debugPrint(e.toString());
    _events.add(e);
  }

  // ---------- 业务接口 ----------

  /// 按配置和频控判断这个广告位现在能不能出（不管广告是否已加载）
  static bool canShow(String placement) => _check(placement, null) == null;

  /// 激励按钮要不要显示：频控允许 + 广告已加载
  static Future<bool> isRewardedReady(String placement) async =>
      _check(placement, AdHubFormat.rewarded) == null && await _provider!.isReady(AdHubFormat.rewarded);

  /// 插屏。无论出没出广告都会返回，游戏流程 await 之后继续
  static Future<void> showInterstitial(String placement) async {
    const f = AdHubFormat.interstitial;
    var reason = _check(placement, f);
    if (reason == null && !await _provider!.isReady(f)) reason = '广告未加载';
    if (reason != null) return _blocked(placement, f, reason);
    final p = config!.placements[placement]!;
    if (await _fullscreenWhile(() => _provider!.showInterstitial(placement))) _capper!.record(p);
  }

  /// 激励。返回 true 才发奖励
  static Future<bool> showRewarded(String placement) async {
    const f = AdHubFormat.rewarded;
    var reason = _check(placement, f);
    if (reason == null && !await _provider!.isReady(f)) reason = '广告未加载';
    if (reason != null) {
      _blocked(placement, f, reason);
      return false;
    }
    _capper!.record(config!.placements[placement]!);
    return _fullscreenWhile(() => _provider!.showRewarded(placement));
  }

  /// 开屏。返回 true = 真的展示过（已关闭）；没广告/被拦截返回 false。无论如何 await 之后继续进游戏。
  /// [waitLoad]：冷启动时广告多半还没加载好，最多等这么久（等 init + 等加载），超时就跳过。
  static Future<bool> showAppOpen(String placement, {Duration waitLoad = Duration.zero}) async {
    const f = AdHubFormat.appOpen;
    final deadline = DateTime.now().add(waitLoad);
    Duration left() {
      final d = deadline.difference(DateTime.now());
      return d.isNegative ? Duration.zero : d;
    }

    if (!isReady && left() > Duration.zero) {
      await whenReady.timeout(left(), onTimeout: () {});
    }
    var reason = _check(placement, f);
    if (reason == null) {
      var ready = await _provider!.isReady(f);
      while (!ready && left() > Duration.zero) {
        await Future.delayed(const Duration(milliseconds: 200));
        ready = await _provider!.isReady(f);
      }
      if (!ready) reason = '广告未加载';
    }
    if (reason == null && _fullscreen > 0) reason = '已有全屏广告在展示';
    if (reason != null) {
      _blocked(placement, f, reason);
      return false;
    }
    final shown = await _fullscreenWhile(() => _provider!.showAppOpen(placement));
    if (shown) _capper!.record(config!.placements[placement]!);
    return shown;
  }

  /// 打开"回前台出开屏"：App 从后台回来时自动展示这个广告位。
  /// 在后台不足 global.appOpenMinBackgroundSec 秒、或是因为看广告/点广告才进的后台，都不出。
  /// 传 null 关闭。调用一次即可（通常在 main 里，和 init 一起）。
  static void enableAppOpenOnResume(String? placement) {
    _resumePlacement = placement;
    if (placement == null) {
      _lifecycle?.dispose();
      _lifecycle = null;
      return;
    }
    _lifecycle ??= AppLifecycleListener(
      onHide: () {
        _hiddenAt = DateTime.now();
        final click = _lastClick;
        _hiddenByAd = _fullscreen > 0 || (click != null && DateTime.now().difference(click).inSeconds < 5);
      },
      onResume: () {
        final at = _hiddenAt, byAd = _hiddenByAd, pl = _resumePlacement;
        _hiddenAt = null;
        if (at == null || pl == null) return;
        if (byAd || _fullscreen > 0) return;
        final min = config?.global.appOpenMinBackgroundSec ?? 0;
        if (min > 0 && DateTime.now().difference(at).inSeconds < min) {
          _blocked(pl, AdHubFormat.appOpen, '后台时间不足 $min 秒');
          return;
        }
        showAppOpen(pl);
      },
    );
  }

  static Future<bool> _fullscreenWhile(Future<bool> Function() show) async {
    _fullscreen++;
    try {
      return await show();
    } finally {
      _fullscreen--;
    }
  }

  /// AdHubBanner 内部用
  static Widget buildBanner(String placement) {
    final reason = _check(placement, AdHubFormat.banner);
    if (reason != null) {
      _blocked(placement, AdHubFormat.banner, reason);
      return const SizedBox.shrink();
    }
    return _provider!.buildBanner(placement);
  }

  static String? _check(String placement, AdHubFormat? expect) {
    if (!isReady) return 'AdHub 未初始化完成';
    final c = config;
    if (c == null || !c.enabled) return '总开关关闭';
    if (_provider == null) return '没有广告 SDK';
    final p = c.placements[placement];
    if (p == null) return '配置里没有这个广告位（先在 ad-hub 仓库 config 里加）';
    if (expect != null && p.format != expect) return '广告位格式是 ${p.format.name}，不是 ${expect.name}';
    if (!p.enabled) return '广告位已关闭';
    return _capper!.check(p);
  }

  static void _blocked(String placement, AdHubFormat f, String reason) =>
      _emit(AdEvent('blocked', f, placement: placement, network: _provider?.name ?? '', message: reason));
}

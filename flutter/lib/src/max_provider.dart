import 'dart:async';

import 'package:applovin_max/applovin_max.dart' as max;
import 'package:flutter/widgets.dart';

import 'config.dart';
import 'provider.dart';

/// AppLovin MAX。AdMob 作为 MAX 下的一个网络（Google bidding）接入。
class MaxProvider implements AdProvider {
  @override
  String get name => 'max';

  late AdUnits _u;
  late Emit _emit;
  int _interRetry = 0, _rewRetry = 0, _openRetry = 0;
  String? _interPl, _rewPl, _openPl;
  Completer<bool>? _interDone, _rewDone, _openDone;
  bool _earned = false;

  @override
  Future<void> initialize(AdHubConfig cfg, AdUnits units, Emit emit) async {
    _u = units;
    _emit = emit;
    if (cfg.maxSdkKey.isEmpty) throw StateError('mediation=max 但配置缺少 maxSdkKey');
    if (cfg.testMode) max.AppLovinMAX.setVerboseLogging(true);
    _hook();
    _hookAppOpen();
    await max.AppLovinMAX.initialize(cfg.maxSdkKey);
    _loadInter();
    _loadRew();
    _loadOpen();
  }

  void _loadInter() {
    if (_u.interstitial.isNotEmpty) max.AppLovinMAX.loadInterstitial(_u.interstitial);
  }

  void _loadRew() {
    if (_u.rewarded.isNotEmpty) max.AppLovinMAX.loadRewardedAd(_u.rewarded);
  }

  void _loadOpen() {
    if (_u.appOpen.isNotEmpty) max.AppLovinMAX.loadAppOpenAd(_u.appOpen);
  }

  AdEvent _ev(String type, AdHubFormat f, String? pl, {max.MaxAd? ad, String? msg}) => AdEvent(type, f,
      placement: pl,
      network: ad?.networkName ?? name,
      value: type == 'revenue' ? (ad?.revenue ?? 0) : 0,
      currency: type == 'revenue' ? 'USD' : null,
      message: msg);

  void _hook() {
    const i = AdHubFormat.interstitial;
    max.AppLovinMAX.setInterstitialListener(max.InterstitialListener(
      onAdLoadedCallback: (_) => _interRetry = 0,
      onAdLoadFailedCallback: (id, e) {
        _emit(_ev('load_failed', i, null, msg: '${e.code} ${e.message}'));
        Future.delayed(retryDelay(++_interRetry), _loadInter);
      },
      onAdDisplayedCallback: (ad) => _emit(_ev('show', i, _interPl, ad: ad)),
      onAdClickedCallback: (ad) => _emit(_ev('click', i, _interPl, ad: ad)),
      onAdRevenuePaidCallback: (ad) => _emit(_ev('revenue', i, _interPl, ad: ad)),
      onAdDisplayFailedCallback: (ad, e) {
        _emit(_ev('show_failed', i, _interPl, ad: ad, msg: '${e.code} ${e.message}'));
        _loadInter();
        _finish(_interDone, false);
        _interDone = null;
      },
      onAdHiddenCallback: (ad) {
        _emit(_ev('closed', i, _interPl, ad: ad));
        _loadInter();
        _finish(_interDone, true);
        _interDone = null;
      },
    ));

    const r = AdHubFormat.rewarded;
    max.AppLovinMAX.setRewardedAdListener(max.RewardedAdListener(
      onAdLoadedCallback: (_) => _rewRetry = 0,
      onAdLoadFailedCallback: (id, e) {
        _emit(_ev('load_failed', r, null, msg: '${e.code} ${e.message}'));
        Future.delayed(retryDelay(++_rewRetry), _loadRew);
      },
      onAdDisplayedCallback: (ad) => _emit(_ev('show', r, _rewPl, ad: ad)),
      onAdClickedCallback: (ad) => _emit(_ev('click', r, _rewPl, ad: ad)),
      onAdRevenuePaidCallback: (ad) => _emit(_ev('revenue', r, _rewPl, ad: ad)),
      onAdReceivedRewardCallback: (ad, reward) {
        _earned = true;
        _emit(_ev('reward', r, _rewPl, ad: ad));
      },
      onAdDisplayFailedCallback: (ad, e) {
        _emit(_ev('show_failed', r, _rewPl, ad: ad, msg: '${e.code} ${e.message}'));
        _loadRew();
        _finish(_rewDone, false);
        _rewDone = null;
      },
      onAdHiddenCallback: (ad) {
        _emit(_ev('closed', r, _rewPl, ad: ad));
        _loadRew();
        _finish(_rewDone, _earned);
        _rewDone = null;
      },
    ));
  }

  void _hookAppOpen() {
    const o = AdHubFormat.appOpen;
    max.AppLovinMAX.setAppOpenAdListener(max.AppOpenAdListener(
      onAdLoadedCallback: (_) => _openRetry = 0,
      onAdLoadFailedCallback: (id, e) {
        _emit(_ev('load_failed', o, null, msg: '${e.code} ${e.message}'));
        Future.delayed(retryDelay(++_openRetry), _loadOpen);
      },
      onAdDisplayedCallback: (ad) => _emit(_ev('show', o, _openPl, ad: ad)),
      onAdClickedCallback: (ad) => _emit(_ev('click', o, _openPl, ad: ad)),
      onAdRevenuePaidCallback: (ad) => _emit(_ev('revenue', o, _openPl, ad: ad)),
      onAdDisplayFailedCallback: (ad, e) {
        _emit(_ev('show_failed', o, _openPl, ad: ad, msg: '${e.code} ${e.message}'));
        _loadOpen();
        _finish(_openDone, false);
        _openDone = null;
      },
      onAdHiddenCallback: (ad) {
        _emit(_ev('closed', o, _openPl, ad: ad));
        _loadOpen();
        _finish(_openDone, true);
        _openDone = null;
      },
    ));
  }

  static void _finish(Completer<bool>? c, bool v) {
    if (c != null && !c.isCompleted) c.complete(v);
  }

  @override
  Future<bool> isReady(AdHubFormat f) async => switch (f) {
        AdHubFormat.interstitial =>
          _u.interstitial.isNotEmpty && (await max.AppLovinMAX.isInterstitialReady(_u.interstitial) ?? false),
        AdHubFormat.rewarded => _u.rewarded.isNotEmpty && (await max.AppLovinMAX.isRewardedAdReady(_u.rewarded) ?? false),
        AdHubFormat.banner => _u.banner.isNotEmpty,
        AdHubFormat.appOpen => _u.appOpen.isNotEmpty && (await max.AppLovinMAX.isAppOpenAdReady(_u.appOpen) ?? false),
      };

  @override
  Future<bool> showInterstitial(String placement) {
    _interPl = placement;
    final c = _interDone = Completer<bool>();
    max.AppLovinMAX.showInterstitial(_u.interstitial, placement: placement);
    return c.future;
  }

  @override
  Future<bool> showRewarded(String placement) {
    _rewPl = placement;
    _earned = false;
    final c = _rewDone = Completer<bool>();
    max.AppLovinMAX.showRewardedAd(_u.rewarded, placement: placement);
    return c.future;
  }

  @override
  Future<bool> showAppOpen(String placement) {
    _openPl = placement;
    final c = _openDone = Completer<bool>();
    max.AppLovinMAX.showAppOpenAd(_u.appOpen, placement: placement);
    return c.future;
  }

  @override
  Widget buildBanner(String placement) {
    if (_u.banner.isEmpty) return const SizedBox.shrink();
    const b = AdHubFormat.banner;
    return max.MaxAdView(
      adUnitId: _u.banner,
      adFormat: max.AdFormat.banner,
      placement: placement,
      listener: max.AdViewAdListener(
        onAdLoadedCallback: (_) {},
        onAdLoadFailedCallback: (id, e) => _emit(_ev('load_failed', b, placement, msg: '${e.code} ${e.message}')),
        onAdClickedCallback: (ad) => _emit(_ev('click', b, placement, ad: ad)),
        onAdExpandedCallback: (_) {},
        onAdCollapsedCallback: (_) {},
        onAdRevenuePaidCallback: (ad) => _emit(_ev('revenue', b, placement, ad: ad)),
      ),
    );
  }
}

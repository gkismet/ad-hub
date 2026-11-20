import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart' as gma;

import 'config.dart';
import 'provider.dart';

/// Google AdMob 直连（不经过 MAX）。testMode=true 或 debug 包强制用 Google 测试 ID。
class AdMobProvider implements AdProvider {
  @override
  String get name => 'admob';

  static AdUnits get _testUnits => Platform.isIOS
      ? const AdUnits(
          interstitial: 'ca-app-pub-3940256099942544/4411468910',
          rewarded: 'ca-app-pub-3940256099942544/1712485313',
          banner: 'ca-app-pub-3940256099942544/2934735716',
          appOpen: 'ca-app-pub-3940256099942544/5575463023')
      : const AdUnits(
          interstitial: 'ca-app-pub-3940256099942544/1033173712',
          rewarded: 'ca-app-pub-3940256099942544/5224354917',
          banner: 'ca-app-pub-3940256099942544/6300978111',
          appOpen: 'ca-app-pub-3940256099942544/9257395921');

  late AdUnits _u;
  late Emit _emit;
  gma.InterstitialAd? _inter;
  gma.RewardedAd? _rew;
  gma.AppOpenAd? _open;
  DateTime? _openLoadedAt;
  bool _loadingInter = false, _loadingRew = false, _loadingOpen = false;
  int _interRetry = 0, _rewRetry = 0, _openRetry = 0;

  /// AdMob 开屏广告加载后 4 小时过期
  static const _openTtl = Duration(hours: 4);

  @override
  Future<void> initialize(AdHubConfig cfg, AdUnits units, Emit emit) async {
    _emit = emit;
    final t = _testUnits;
    _u = (cfg.testMode || kDebugMode)
        ? AdUnits(
            interstitial: units.interstitial.isEmpty ? '' : t.interstitial,
            rewarded: units.rewarded.isEmpty ? '' : t.rewarded,
            banner: units.banner.isEmpty ? '' : t.banner,
            appOpen: units.appOpen.isEmpty ? '' : t.appOpen)
        : units;
    await gma.MobileAds.instance.initialize();
    _loadInter();
    _loadRew();
    _loadOpen();
  }

  gma.OnPaidEventCallback _onPaid(String? Function() placement, AdHubFormat f) =>
      (gma.Ad ad, double micros, gma.PrecisionType p, String currency) => _emit(AdEvent('revenue', f,
          placement: placement(), network: name, value: micros / 1e6, currency: currency));

  void _loadInter() {
    if (_u.interstitial.isEmpty || _loadingInter) return;
    _loadingInter = true;
    gma.InterstitialAd.load(
      adUnitId: _u.interstitial,
      request: const gma.AdRequest(),
      adLoadCallback: gma.InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _loadingInter = false;
          _interRetry = 0;
          _inter = ad;
        },
        onAdFailedToLoad: (e) {
          _loadingInter = false;
          _emit(AdEvent('load_failed', AdHubFormat.interstitial, network: name, message: e.message));
          Future.delayed(retryDelay(++_interRetry), _loadInter);
        },
      ),
    );
  }

  void _loadRew() {
    if (_u.rewarded.isEmpty || _loadingRew) return;
    _loadingRew = true;
    gma.RewardedAd.load(
      adUnitId: _u.rewarded,
      request: const gma.AdRequest(),
      rewardedAdLoadCallback: gma.RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _loadingRew = false;
          _rewRetry = 0;
          _rew = ad;
        },
        onAdFailedToLoad: (e) {
          _loadingRew = false;
          _emit(AdEvent('load_failed', AdHubFormat.rewarded, network: name, message: e.message));
          Future.delayed(retryDelay(++_rewRetry), _loadRew);
        },
      ),
    );
  }

  void _loadOpen() {
    if (_u.appOpen.isEmpty || _loadingOpen) return;
    _loadingOpen = true;
    gma.AppOpenAd.load(
      adUnitId: _u.appOpen,
      request: const gma.AdRequest(),
      adLoadCallback: gma.AppOpenAdLoadCallback(
        onAdLoaded: (ad) {
          _loadingOpen = false;
          _openRetry = 0;
          _open = ad;
          _openLoadedAt = DateTime.now();
        },
        onAdFailedToLoad: (e) {
          _loadingOpen = false;
          _emit(AdEvent('load_failed', AdHubFormat.appOpen, network: name, message: e.message));
          Future.delayed(retryDelay(++_openRetry), _loadOpen);
        },
      ),
    );
  }

  bool get _openFresh {
    if (_open == null) return false;
    if (DateTime.now().difference(_openLoadedAt!) < _openTtl) return true;
    _open!.dispose(); // 过期了，扔掉重新拉
    _open = null;
    _loadOpen();
    return false;
  }

  @override
  Future<bool> isReady(AdHubFormat f) async => switch (f) {
        AdHubFormat.interstitial => _inter != null,
        AdHubFormat.rewarded => _rew != null,
        AdHubFormat.banner => _u.banner.isNotEmpty,
        AdHubFormat.appOpen => _openFresh,
      };

  @override
  Future<bool> showInterstitial(String placement) {
    final ad = _inter!;
    _inter = null;
    final done = Completer<bool>();
    const f = AdHubFormat.interstitial;
    ad.onPaidEvent = _onPaid(() => placement, f);
    ad.fullScreenContentCallback = gma.FullScreenContentCallback(
      onAdShowedFullScreenContent: (_) => _emit(AdEvent('show', f, placement: placement, network: name)),
      onAdClicked: (_) => _emit(AdEvent('click', f, placement: placement, network: name)),
      onAdFailedToShowFullScreenContent: (ad, e) {
        _emit(AdEvent('show_failed', f, placement: placement, network: name, message: e.message));
        ad.dispose();
        _loadInter();
        if (!done.isCompleted) done.complete(false);
      },
      onAdDismissedFullScreenContent: (ad) {
        _emit(AdEvent('closed', f, placement: placement, network: name));
        ad.dispose();
        _loadInter();
        if (!done.isCompleted) done.complete(true);
      },
    );
    ad.show();
    return done.future;
  }

  @override
  Future<bool> showRewarded(String placement) {
    final ad = _rew!;
    _rew = null;
    final done = Completer<bool>();
    var earned = false;
    const f = AdHubFormat.rewarded;
    ad.onPaidEvent = _onPaid(() => placement, f);
    ad.fullScreenContentCallback = gma.FullScreenContentCallback(
      onAdShowedFullScreenContent: (_) => _emit(AdEvent('show', f, placement: placement, network: name)),
      onAdClicked: (_) => _emit(AdEvent('click', f, placement: placement, network: name)),
      onAdFailedToShowFullScreenContent: (ad, e) {
        _emit(AdEvent('show_failed', f, placement: placement, network: name, message: e.message));
        ad.dispose();
        _loadRew();
        if (!done.isCompleted) done.complete(false);
      },
      onAdDismissedFullScreenContent: (ad) {
        _emit(AdEvent('closed', f, placement: placement, network: name));
        ad.dispose();
        _loadRew();
        if (!done.isCompleted) done.complete(earned);
      },
    );
    ad.show(onUserEarnedReward: (_, __) {
      earned = true;
      _emit(AdEvent('reward', f, placement: placement, network: name));
    });
    return done.future;
  }

  @override
  Future<bool> showAppOpen(String placement) {
    final ad = _open!;
    _open = null;
    final done = Completer<bool>();
    const f = AdHubFormat.appOpen;
    ad.onPaidEvent = _onPaid(() => placement, f);
    ad.fullScreenContentCallback = gma.FullScreenContentCallback(
      onAdShowedFullScreenContent: (_) => _emit(AdEvent('show', f, placement: placement, network: name)),
      onAdClicked: (_) => _emit(AdEvent('click', f, placement: placement, network: name)),
      onAdFailedToShowFullScreenContent: (ad, e) {
        _emit(AdEvent('show_failed', f, placement: placement, network: name, message: e.message));
        ad.dispose();
        _loadOpen();
        if (!done.isCompleted) done.complete(false);
      },
      onAdDismissedFullScreenContent: (ad) {
        _emit(AdEvent('closed', f, placement: placement, network: name));
        ad.dispose();
        _loadOpen();
        if (!done.isCompleted) done.complete(true);
      },
    );
    ad.show();
    return done.future;
  }

  @override
  Widget buildBanner(String placement) =>
      _u.banner.isEmpty ? const SizedBox.shrink() : _AdMobBanner(_u.banner, placement, _emit, _onPaid);
}

class _AdMobBanner extends StatefulWidget {
  final String unit, placement;
  final Emit emit;
  final gma.OnPaidEventCallback Function(String? Function(), AdHubFormat) onPaid;
  const _AdMobBanner(this.unit, this.placement, this.emit, this.onPaid);

  @override
  State<_AdMobBanner> createState() => _AdMobBannerState();
}

class _AdMobBannerState extends State<_AdMobBanner> {
  gma.BannerAd? _ad;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ad == null) _load();
  }

  Future<void> _load() async {
    final width = MediaQuery.sizeOf(context).width.truncate();
    final size = await gma.AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(width) ?? gma.AdSize.banner;
    if (!mounted) return;
    const f = AdHubFormat.banner;
    final ad = gma.BannerAd(
      adUnitId: widget.unit,
      size: size,
      request: const gma.AdRequest(),
      listener: gma.BannerAdListener(
        onAdLoaded: (_) => setState(() => _loaded = true),
        onAdFailedToLoad: (ad, e) {
          widget.emit(AdEvent('load_failed', f, placement: widget.placement, network: 'admob', message: e.message));
          ad.dispose();
        },
        onAdClicked: (_) => widget.emit(AdEvent('click', f, placement: widget.placement, network: 'admob')),
        onPaidEvent: widget.onPaid(() => widget.placement, f),
      ),
    );
    _ad = ad;
    ad.load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (!_loaded || ad == null) return const SizedBox.shrink();
    return SizedBox(width: ad.size.width.toDouble(), height: ad.size.height.toDouble(), child: gma.AdWidget(ad: ad));
  }
}

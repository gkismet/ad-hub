import 'package:flutter/widgets.dart';

import 'config.dart';

typedef Emit = void Function(AdEvent e);

/// 聚合平台适配层。业务代码不直接用，统一走 AdHub。
abstract class AdProvider {
  String get name;
  Future<void> initialize(AdHubConfig cfg, AdUnits units, Emit emit);
  Future<bool> isReady(AdHubFormat f);

  /// true = 广告真的展示过
  Future<bool> showInterstitial(String placement);

  /// true = 用户拿到奖励
  Future<bool> showRewarded(String placement);

  /// true = 开屏真的展示过（关闭后才返回）
  Future<bool> showAppOpen(String placement);
  Widget buildBanner(String placement);
}

/// 加载失败指数退避：2,4,8...最多 64 秒
Duration retryDelay(int attempt) => Duration(seconds: 1 << attempt.clamp(1, 6));

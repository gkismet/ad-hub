import 'package:flutter/widgets.dart';

import 'ad_hub.dart';

/// 横幅广告。放在页面底部即可，配置关闭/未初始化时不占空间。
class AdHubBanner extends StatefulWidget {
  final String placement;
  const AdHubBanner({super.key, required this.placement});

  @override
  State<AdHubBanner> createState() => _AdHubBannerState();
}

class _AdHubBannerState extends State<AdHubBanner> {
  Widget? _child;

  @override
  void initState() {
    super.initState();
    // 等 AdHub 初始化完成再建（init 已在 main 里调用）
    AdHub.whenReady.then((_) {
      if (mounted) setState(() => _child = AdHub.buildBanner(widget.placement));
    });
  }

  @override
  Widget build(BuildContext context) => _child ?? const SizedBox.shrink();
}

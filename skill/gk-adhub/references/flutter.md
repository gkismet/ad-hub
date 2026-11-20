# Flutter 接入

`ad_hub` 是一个 Dart 包，放在 ad-hub 仓库的 `flutter/` 目录，项目用 git 依赖引用（锁 tag，不跟 main）。
它同时依赖 `google_mobile_ads` 和 `applovin_max`，两种 mediation 都能用。

## 1. 依赖
`pubspec.yaml`：
```yaml
dependencies:
  ad_hub:
    git:
      url: https://github.com/gkismet/ad-hub.git
      path: flutter
      ref: v0.3.1        # 用 ad-hub 仓库的 tag
flutter:
  assets:
    - assets/adhub_config.json
```
本地联调 ad-hub 本身时可临时改成 `path: <ad-hub>/flutter`，提交前改回 git。
拷配置（出包前再同步一次）：
```powershell
powershell -ExecutionPolicy Bypass -File <ad-hub>\tools\sync_config.ps1 -App <app> -Project <Flutter项目根目录>
```

## 2. 原生配置
`google_mobile_ads` 要求 Android Manifest 和 iOS Info.plist 里**必须**有 AdMob App ID，否则启动即崩——
即使 mediation=max 也要填（MAX 下的 Google 适配器同样需要）。见 platform-setup.md。
MAX 的 SDK Key 来自配置的 `maxSdkKey`。

## 3. 初始化
```dart
import 'package:ad_hub/ad_hub.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AdHub.events.listen((e) {
    if (e.type == 'revenue') {
      // 例：FirebaseAnalytics.instance.logAdImpression(adPlatform: ..., adSource: e.network,
      //   adFormat: e.format.name, adUnitName: e.placement, value: e.value, currency: e.currency);
    }
  });
  // 不 await 也行：不阻塞首屏，广告在 init 完成前调用会被拦截（blocked）
  AdHub.init(appId: 'my_app_id');   // 读 assets/adhub_config.json
  runApp(const MyApp());
}
```

## 4. 调用
```dart
await AdHub.showInterstitial('level_complete');
goNextLevel();

if (await AdHub.showRewarded('revive')) revive(); else showGameOver();

// 激励按钮
FutureBuilder<bool>(future: AdHub.isRewardedReady('revive'), builder: ...)

// 横幅：放 Scaffold.bottomNavigationBar 或 Column 底部
const AdHubBanner(placement: 'home_bottom')

// 开屏（冷启动）：启动页里调，最多等 3 秒加载，没广告/超时就直接进
await AdHub.showAppOpen('cold_start', waitLoad: const Duration(seconds: 3));
goHome();

// 开屏（回前台）：main 里和 init 一起调一次
AdHub.enableAppOpenOnResume('app_resume');
```
开屏注意：
- 冷启动 `waitLoad` 别太长（2～4 秒），玩家等不住；超时会有 `blocked: 广告未加载` 事件，属正常。
- 回前台开屏会自动跳过：因为看插屏/激励/开屏或点广告而进的后台、在后台不足 `appOpenMinBackgroundSec` 秒。
- 玩家正在付费、选图片、登录第三方等会切出 App 的流程时，先 `AdHub.enableAppOpenOnResume(null)` 关掉，回来再打开。
- AdMob 直连的开屏广告加载后 4 小时过期，模块会自动丢弃重拉。

## 已知注意
- 当前锁定验证过的版本：google_mobile_ads 6.0.0、applovin_max 4.6.x（`flutter analyze` 通过）。升级大版本先在 ad-hub 里改、跑 analyze。
- 只支持 Android / iOS（用了 dart:io）。
- Flutter 游戏（Flame 等）同样适用。
- 项目路径里有中文时 `flutter build apk` 会失败（着色器编译器 impellerc 写不了文件，`android.overridePathCheck` 也绕不过去），项目要放在纯英文路径。
- 个别 Windows 机器上 Gradle 报 `Unable to establish loopback connection`（JDK 21）：打包前设 `$env:_JAVA_OPTIONS="-Xss8m -Djdk.net.unixdomain.tmpdir=C:/Users/Public"`。
- 改 ad-hub 的 `flutter/pubspec.yaml` 时只能写英文：项目用 git 依赖时 pub 在中文 Windows 上按 GBK 读它，有中文就解析失败。

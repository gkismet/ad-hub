# 原生平台配置

## AdMob App ID（两种 mediation 都要）
- AdMob 后台每个 App 一个 App ID：`ca-app-pub-XXXX~YYYY`（注意是 `~`，不是广告单元的 `/`）。
- 开发期可用 Google 测试 App ID：Android `ca-app-pub-3940256099942544~3347511713`，iOS `ca-app-pub-3940256099942544~1458002511`。

**Android** `AndroidManifest.xml` 的 `<application>` 里：
```xml
<meta-data android:name="com.google.android.gms.ads.APPLICATION_ID"
           android:value="ca-app-pub-XXXX~YYYY"/>
```
（Unity 由插件设置页自动写入；Flutter 手动加。）

**iOS** `Info.plist`：
```xml
<key>GADApplicationIdentifier</key><string>ca-app-pub-XXXX~YYYY</string>
```

## iOS
- **SKAdNetworkItems**：Info.plist 里要加各广告网络的 SKAdNetwork ID。MAX 用户用 AppLovin 提供的完整列表（Integration Manager / 官网 SKAdNetwork 页生成）；AdMob 直连用 Google 文档里的列表。缺了会影响 iOS 收益。
- **ATT**：要个性化广告需要 `NSUserTrackingUsageDescription` 并在初始化广告前请求授权。MAX 的 Terms & Privacy Policy Flow 可自动处理；AdMob 直连用 UMP 的 IDFA 说明或 `app_tracking_transparency` 插件。
- 审核：App Store Connect 的隐私标签要申报广告数据收集。

## 隐私同意（GDPR / 美国州法）
- 面向欧洲/英国用户必须用经 Google 认证的 CMP。MAX：开启 Terms & Privacy Policy Flow（内含 Google UMP）。AdMob 直连：用 UMP SDK（Unity 插件内置 `GoogleMobileAds.Ump`；Flutter 是 `google_mobile_ads` 里的 `ConsentInformation`）在 `AdHub.Init` 之前收集同意。
- 这一步各项目暂时自己做，等需求一致后再收进 AdHub。

## app-ads.txt
每个开发者网站根目录放 `app-ads.txt`，包含 AdMob 和 MAX（以及 MAX 下各网络）给的行；商店后台填的开发者网站必须是这个域名。缺失会导致部分需求方不投放。团队共用一个网站时维护一份即可。

## 儿童 / 家庭类应用
目标用户含 13 岁以下：必须设置 tag-for-child-directed，且很多网络不能用。这种项目先停下和负责人确认，不要按默认流程接。

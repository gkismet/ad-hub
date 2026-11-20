import 'package:ad_hub/ad_hub.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('setAdsRemoved：通知 + 本地记住 + 发事件', () async {
    SharedPreferences.setMockInitialValues({});
    final events = <String>[];
    final sub = AdHub.events.listen((e) => events.add('${e.type}:${e.message}'));
    var notified = 0;
    AdHub.adsRemoved.addListener(() => notified++);

    AdHub.setAdsRemoved(true);
    AdHub.setAdsRemoved(true); // 重复调用不重复通知
    await Future<void>.delayed(Duration.zero);
    expect(AdHub.adsRemoved.value, isTrue);
    expect(notified, 1);
    expect((await SharedPreferences.getInstance()).getBool('adhub.ads_removed'), isTrue);
    expect(events, contains('ads_removed:true'));

    AdHub.setAdsRemoved(false);
    await Future<void>.delayed(Duration.zero);
    expect((await SharedPreferences.getInstance()).getBool('adhub.ads_removed'), isFalse);
    await sub.cancel();
  });

  testWidgets('买了去广告后横幅立刻消失', (tester) async {
    AdHub.setAdsRemoved(false);
    await tester.pumpWidget(const Directionality(
        textDirection: TextDirection.ltr, child: AdHubBanner(placement: 'home_bottom')));
    expect(find.byType(AdHubBanner), findsOneWidget);
    AdHub.setAdsRemoved(true);
    await tester.pump();
    expect(find.byType(SizedBox), findsOneWidget);
  });
}

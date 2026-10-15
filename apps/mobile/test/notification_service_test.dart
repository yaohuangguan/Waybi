import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waybi_mobile/services/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });
  test('iOS denied reminders are retryable and granted reminders request foreground banners and sound', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    FlutterLocalNotificationsPlatform.instance =
        IOSFlutterLocalNotificationsPlugin();
    var allowed = false;
    final shown = <Map<dynamic, dynamic>>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'initialize') return true;
      if (call.method == 'checkPermissions') {
        return {
          'isEnabled': allowed,
          'isAlertEnabled': allowed,
          'isSoundEnabled': allowed,
        };
      }
      if (call.method == 'requestPermissions') return allowed;
      if (call.method == 'show') {
        shown.add(call.arguments as Map<dynamic, dynamic>);
      }
      return null;
    });
    final service = WaybiNotificationService();
    expect(await service.requestPermission(), false);
    expect(
      await service.showRoadAlert(
        id: 'camera:test',
        title: 'Red-light camera ahead',
        body: '476 m · Green Lane East',
      ),
      false,
    );
    expect(shown, isEmpty);
    allowed = true;
    expect(await service.requestPermission(), true);
    expect(
      await service.showRoadAlert(
        id: 'camera:test',
        title: 'Red-light camera ahead',
        body: '476 m · Green Lane East',
      ),
      true,
    );
    final details = shown.single['platformSpecifics'] as Map;
    expect(details['presentBanner'], true);
    expect(details['presentList'], true);
    expect(details['presentSound'], true);
    expect(shown.single['payload'], 'camera:test');
  });
  test('Android permissions control road alerts and commute notifications keep their destination payload', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    FlutterLocalNotificationsPlatform.instance =
        AndroidFlutterLocalNotificationsPlugin();
    var allowed = false;
    final shown = <Map>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'initialize') return true;
      if (call.method == 'areNotificationsEnabled' ||
          call.method == 'requestNotificationsPermission') {
        return allowed;
      }
      if (call.method == 'show') shown.add(call.arguments as Map);
      return null;
    });
    final service = WaybiNotificationService();
    expect(await service.requestPermission(), isFalse);
    expect(
      await service.showRoadAlert(
        id: 'closure',
        title: 'Closure',
        body: 'Ramp closed',
      ),
      isFalse,
    );
    expect(shown, isEmpty);
    allowed = true;
    expect(await service.requestPermission(), isTrue);
    expect(
      await service.showRoadAlert(
        id: 'closure',
        title: 'Closure',
        body: 'Ramp closed',
      ),
      isTrue,
    );
    await service.showPlusCommuteAlert(
      id: 'work',
      title: 'Work route',
      body: 'Road works',
    );
    expect(shown.map((value) => value['payload']), [
      'closure',
      'route-watch:work',
    ]);
    expect(
      (shown.first['platformSpecifics'] as Map)['channelId'],
      'waybi_road_alerts',
    );
  });
}

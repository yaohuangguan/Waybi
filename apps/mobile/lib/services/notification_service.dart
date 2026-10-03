import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class WaybiNotificationService {
  WaybiNotificationService._();

  static final WaybiNotificationService instance = WaybiNotificationService._();
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized || kIsWeb) return;
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _plugin.initialize(settings);
    _initialized = true;
  }

  Future<void> requestPermission() async {
    await initialize();
    await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: false, sound: true);
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
  }

  Future<void> showPlusCommuteAlert({
    required String id,
    required String title,
    required String body,
  }) async {
    await initialize();
    await _plugin.show(
      id.hashCode & 0x7fffffff,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'kiwi_plus_commute_alerts',
          'Waybi Plus commute alerts',
          channelDescription:
              'Proactive Route Watch alerts for Waybi Plus commutes',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
      ),
      payload: 'route-watch:$id',
    );
  }

  Future<void> showRoadAlert({
    required String id,
    required String title,
    required String body,
  }) async {
    await initialize();
    await _plugin.show(
      id.hashCode & 0x7fffffff,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'waybi_road_alerts',
          'Road alerts',
          channelDescription:
              'Safety cameras, closures and important road events',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
      ),
      payload: id,
    );
  }
}

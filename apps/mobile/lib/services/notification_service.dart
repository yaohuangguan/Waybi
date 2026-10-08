import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class WaybiNotificationService {
  WaybiNotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static final WaybiNotificationService instance = WaybiNotificationService();
  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized || kIsWeb) return;
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _plugin.initialize(settings);
    _initialized = true;
  }

  Future<bool> requestPermission() async {
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
    return canShowAlerts();
  }

  Future<bool> canShowAlerts() async {
    await initialize();
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final permissions = await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.checkPermissions();
      return permissions?.isAlertEnabled == true;
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.areNotificationsEnabled() ??
          false;
    }
    return !kIsWeb;
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

  Future<bool> showRoadAlert({
    required String id,
    required String title,
    required String body,
  }) async {
    if (!await canShowAlerts()) return false;
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
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBanner: true,
          presentList: true,
          presentSound: true,
        ),
      ),
      payload: id,
    );
    return true;
  }
}

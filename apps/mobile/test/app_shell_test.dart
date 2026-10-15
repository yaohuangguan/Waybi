import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:waybi_mobile/main.dart';
import 'package:waybi_mobile/widgets/trips_page.dart';
import 'package:waybi_mobile/widgets/discover_page.dart';
import 'package:waybi_mobile/widgets/profile_page.dart';

import 'support/recording_map_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'real app onboarding, saved appearance and page navigation stay usable without GPS',
    (tester) async {
      FlutterLocalNotificationsPlatform.instance =
          AndroidFlutterLocalNotificationsPlugin();
      SharedPreferences.setMockInitialValues({
        'waybi.onboarding.core.v1': false,
        'waybi.app.language': 'en',
        'waybi.appearance': 'dark',
      });
      FlutterSecureStorage.setMockInitialValues({});
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final channels = <MethodChannel>[
        const MethodChannel('flutter.baseflow.com/permissions/methods'),
        const MethodChannel('dexterous.com/flutter/local_notifications'),
        const MethodChannel('flutter_tts'),
        const MethodChannel('waybi/device_heading'),
        const MethodChannel('waybi/external_navigation'),
        const MethodChannel('waybi/map_language'),
      ];
      for (final channel in channels) {
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'checkPermissionStatus') return 4;
          if (call.method == 'requestPermissions') {
            return <int, int>{3: 4, 5: 4};
          }
          if (call.method == 'takePending') return null;
          if (call.method == 'initialize' || call.method == 'setLanguage') {
            return true;
          }
          return 1;
        });
      }
      const wakeChannel =
          'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle';
      messenger.setMockMessageHandler(
        wakeChannel,
        (_) async => const StandardMessageCodec().encodeMessage([null]),
      );
      addTearDown(() => messenger.setMockMessageHandler(wakeChannel, null));
      final original = ml.MapLibrePlatform.createInstance;
      ml.MapLibrePlatform.createInstance = () => RecordingMapPlatform();
      addTearDown(() {
        ml.MapLibrePlatform.createInstance = original;
        for (final channel in channels) {
          messenger.setMockMethodCallHandler(channel, null);
        }
      });
      await tester.pumpWidget(const WaybiApp());
      await tester.pump(const Duration(milliseconds: 1100));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      // Periodic data refresh is intentionally live; settle only bounded frames.
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark,
      );
      expect(find.text('Start exploring'), findsOneWidget);
      await tester.tap(find.text('Start exploring'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(
        (await SharedPreferences.getInstance()).getBool(
          'waybi.onboarding.core.v1',
        ),
        isTrue,
      );
      expect(find.byKey(const Key('companionSearchInput')), findsOneWidget);
      expect(find.byTooltip('Map layers'), findsOneWidget);
      expect(find.text('Open settings'), findsOneWidget);
      await tester.tap(find.byTooltip('Map layers'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Live traffic'), findsOneWidget);
      Navigator.of(tester.element(find.text('Live traffic'))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      for (final entry in [
        ('Trips', find.byType(TripsPage)),
        ('Discover', find.byType(DiscoverPage)),
      ]) {
        await tester.tap(find.text(entry.$1));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 200));
        expect(entry.$2, findsOneWidget);
        Navigator.of(tester.element(entry.$2)).pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
      }
      await tester.tap(find.text('Me'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(ProfilePage), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Appearance'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.byType(DropdownButton<ThemeMode>));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byType(DropdownButton<ThemeMode>));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Light').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.light,
      );
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('waybi.appearance'), 'light');
      Navigator.of(tester.element(find.byType(ProfilePage))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    },
  );
}

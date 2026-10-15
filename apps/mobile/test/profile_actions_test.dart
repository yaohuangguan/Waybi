import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waybi_mobile/data/account_repository.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/widgets/profile_page.dart';

Widget screen(
  AccountRepository account, {
  ValueChanged<ThemeMode>? theme,
  ValueChanged<String>? language,
  ValueChanged<LocationMarkerStyle>? marker,
}) => MaterialApp(
  home: ProfilePage(
    account: account,
    voiceEnabled: true,
    lanesEnabled: true,
    appLanguage: 'en',
    voiceLanguage: 'en-NZ',
    onThemeModeChanged: theme,
    onVoiceChanged: (_) {},
    onLanesChanged: (_) {},
    onAppLanguageChanged: language ?? (_) {},
    onLanguageChanged: (_) {},
    onMapLayers: () {},
    mapProvider: MapProvider.independent,
    locationMarker: LocationMarkerStyle.kiwi,
    onMapProviderChanged: (p) async => p,
    onLocationMarkerChanged: marker ?? (_) {},
    notifySafetyCameras: false,
    notifyRoadIncidents: false,
    notifyCommunityReports: false,
    notifySavedRouteDisruptions: false,
    onNotifySafetyCamerasChanged: (_) {},
    onNotifyRoadIncidentsChanged: (_) {},
    onNotifyCommunityReportsChanged: (_) {},
    onNotifySavedRouteDisruptionsChanged: (_) {},
    onSyncCameraData: () async => null,
  ),
);
Future<void> reveal(
  WidgetTester tester,
  Finder finder, {
  double delta = 250,
}) async {
  await tester.scrollUntilVisible(
    finder,
    delta,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 40,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'profile appearance, marker and app-language controls deliver the chosen values',
    (tester) async {
      final account = AccountRepository();
      addTearDown(account.dispose);
      ThemeMode? theme;
      String? language;
      LocationMarkerStyle? marker;
      await tester.pumpWidget(
        screen(
          account,
          theme: (v) => theme = v,
          language: (v) => language = v,
          marker: (v) => marker = v,
        ),
      );
      await reveal(tester, find.text('Appearance'));
      await tester.ensureVisible(find.byType(DropdownButton<ThemeMode>));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButton<ThemeMode>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dark').last);
      await tester.pumpAndSettle();
      expect(theme, ThemeMode.dark);
      await reveal(tester, find.text('Location marker'));
      await tester.ensureVisible(
        find.byType(DropdownButton<LocationMarkerStyle>),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButton<LocationMarkerStyle>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Arrow').last);
      await tester.pumpAndSettle();
      expect(marker, LocationMarkerStyle.arrow);
      await reveal(tester, find.text('App language'), delta: -250);
      await tester.ensureVisible(find.byType(DropdownButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('中文').last);
      await tester.pumpAndSettle();
      expect(language, 'zh');
      expect(find.text('应用语言'), findsOneWidget);
    },
  );
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets(
      '$platform account deletion is reachable with keyboard, requires confirmation and preserves failed sessions',
      (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        var deleteStatus = 503, requests = 0;
        FlutterSecureStorage.setMockInitialValues({
          'waybi_session': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        });
        final account = AccountRepository(
          client: MockClient((r) async {
            if (r.url.path == '/api/auth/delete') {
              requests++;
              return http.Response('{"error":"Try again"}', deleteStatus);
            }
            return http.Response(
              jsonEncode({
                'user': {
                  'id': 'driver',
                  'email': 'driver@example.test',
                  'displayName': 'Driver',
                  'providers': ['google', 'apple'],
                },
                'subscription': {'plan': 'free'},
              }),
              200,
            );
          }),
        );
        addTearDown(account.dispose);
        try {
          await account.restore();
          await tester.pumpWidget(screen(account));
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('Edit profile'));
          await tester.pumpAndSettle();
          await tester.enterText(
            find.widgetWithText(TextFormField, 'Name'),
            'New Driver',
          );
          await tester.tap(find.text('Save'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await reveal(tester, find.text('Delete account'));
          await tester.tap(find.text('Delete account'));
          await tester.pumpAndSettle();
          tester.view.viewInsets = const FakeViewPadding(bottom: 300);
          await tester.pump();
          expect(
            tester.takeException(),
            isNull,
            reason: 'Deletion must remain usable above the keyboard',
          );
          final button = find.widgetWithText(
            FilledButton,
            'Delete permanently',
          );
          expect(tester.widget<FilledButton>(button).onPressed, isNull);
          await tester.enterText(
            find.widgetWithText(TextField, 'Account email'),
            'driver@example.test',
          );
          await tester.pump();
          await tester.ensureVisible(button);
          await tester.tap(button);
          await tester.pumpAndSettle();
          expect(account.signedIn, isTrue);
          expect(requests, 1);
          tester.view.resetViewInsets();
          await tester.pump();
          await reveal(tester, find.text('Delete account'));
          await tester.tap(find.text('Delete account'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Keep account'));
          await tester.pumpAndSettle();
          expect(requests, 1);
          deleteStatus = 200;
          await tester.tap(find.text('Delete account'));
          await tester.pumpAndSettle();
          await tester.enterText(
            find.widgetWithText(TextField, 'Account email'),
            'driver@example.test',
          );
          await tester.pump();
          await tester.tap(find.text('Delete permanently'));
          await tester.pumpAndSettle();
          expect(account.signedIn, isFalse);
          expect(requests, 2);
          expect(find.text('Waybi account deleted.'), findsOneWidget);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox());
          tester.view.resetViewInsets();
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  }
}

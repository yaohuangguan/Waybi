import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waybi_mobile/widgets/profile_page.dart';

import 'support/app_harness.dart';

void flow(String name, Future<void> Function(WidgetTester, AppHarness) body) {
  testWidgets(name, (t) async {
    final h = AppHarness(t);
    await http.runWithClient(() async {
      await body(t, h);
      await h.dispose();
    }, () => h.client);
  });
}

Future<void> reveal(
  WidgetTester t,
  AppHarness h,
  Finder f, {
  double delta = 300,
}) async {
  await t.scrollUntilVisible(
    f,
    delta,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 50,
  );
  await t.ensureVisible(f);
  await h.frames();
}

void main() {
  flow(
    'profile navigation and all notification switches persist to the running app',
    (t, h) async {
      await h.boot(signedIn: true, plus: true);
      await h.tapText('Me');
      for (final label in [
        'Keep screen awake',
        'Voice guidance & camera alerts',
        'Lane guidance',
        'Safety cameras',
        'Road incidents',
        'Community reports',
        'Proactive saved-route alerts',
      ]) {
        final tile = find.widgetWithText(SwitchListTile, label);
        await reveal(t, h, tile);
        final before = t.widget<SwitchListTile>(tile).value;
        await h.act(() => t.widget<SwitchListTile>(tile).onChanged!(!before));
        expect(t.widget<SwitchListTile>(tile).value, !before);
      }
      final language = find.widgetWithText(ListTile, 'Camera alert language');
      await reveal(t, h, language, delta: -300);
      final dropdown = find.descendant(
        of: language,
        matching: find.byType(DropdownButton<String>),
      );
      await t.tap(dropdown);
      await h.frames();
      await h.tapText('中文');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('waybi.nav.keep_screen_awake'), false);
      expect(prefs.getBool('waybi.voice.enabled'), true);
      expect(prefs.getBool('waybi.nav.lanes'), false);
      expect(prefs.getString('waybi.voice.language'), 'zh-CN');
      for (final key in [
        'safety_cameras',
        'road_incidents',
        'community_reports',
        'saved_route_disruptions',
      ]) {
        expect(prefs.getBool('waybi.notifications.$key'), true);
      }
      expect(
        h.requests.any((r) => r.url.path == '/api/route-watch-alerts'),
        isTrue,
      );
      Navigator.of(t.element(find.byType(ProfilePage))).pop();
      await h.frames();
      expect(h.map.navigating, isFalse);
    },
  );
  flow('camera refresh remains usable when an upstream Plus sync fails', (
    t,
    h,
  ) async {
    h.endpointFailures['/api/cameras/sync'] = 503;
    await h.boot(signedIn: true, plus: true);
    await h.tapText('Me');
    final button = find.text('Check for camera updates');
    await reveal(t, h, button);
    await t.tap(button);
    await h.until(
      () =>
          find.textContaining('Temporarily unavailable').evaluate().isNotEmpty,
      reason: 'Camera sync failure should be visible',
    );
    expect(find.byType(ProfilePage), findsOneWidget);
    final refresh = find.text('Refresh saved camera list');
    await reveal(t, h, refresh, delta: -200);
    await t.tap(refresh);
    await h.frames();
    expect(
      h.requests.where((r) => r.url.path == '/api/cameras').length,
      greaterThan(1),
    );
    expect(find.text('Check for camera updates'), findsOneWidget);
  });
  for (final language in ['en', 'zh']) {
    flow(
      '$language profile shows saved and recent data, licence details and sign-out',
      (t, h) async {
        h.recentDestinations.addAll([
          {'label': 'Recent harbour', 'createdAt': '2026-10-15'},
          {'latitude': -37.2},
        ]);
        for (var i = 0; i < 5; i++) {
          h.savedPlaces.add({
            'placeId': 'osm:$i',
            'name': 'Saved $i',
            'isFavorite': true,
          });
          h.reviews.add({
            'placeId': 'osm:$i',
            'placeName': 'Review $i',
            'text': 'Private note',
          });
          h.routeHistory.add({'destinationName': 'Trip $i'});
        }
        await h.boot(
          signedIn: true,
          preferences: {'waybi.app.language': language},
        );
        await h.tapText(language == 'zh' ? '我的' : 'Me');
        await reveal(
          t,
          h,
          find.text(language == 'zh' ? '最近目的地' : 'Recent destinations'),
        );
        final recent = find.text('Recent harbour');
        expect(recent, findsOneWidget);
        expect(
          find.text(language == 'zh' ? '最近目的地' : 'Recent destinations'),
          findsOneWidget,
        );
        expect(find.text('2026-10-15'), findsOneWidget);
        final licences = find.text(
          language == 'zh' ? '地图数据与许可' : 'Map data & licences',
        );
        await reveal(t, h, licences);
        expect(
          find.textContaining(
            language == 'zh' ? '地图数据与许可' : 'Map data & licences',
          ),
          findsWidgets,
        );
        await t.tap(licences);
        await h.frames();
        expect(find.text('OpenStreetMap'), findsOneWidget);
        expect(find.textContaining('Waybi'), findsWidgets);
        Navigator.of(t.element(find.byType(DraggableScrollableSheet))).pop();
        await h.frames();
        final signout = find.text(language == 'zh' ? '退出登录' : 'Sign out');
        await reveal(t, h, signout, delta: -250);
        await t.tap(signout);
        await h.frames();
        await reveal(
          t,
          h,
          find.text(language == 'zh' ? '使用 Google 继续' : 'Continue with Google'),
          delta: -300,
        );
        expect(
          find.text(language == 'zh' ? '使用 Google 继续' : 'Continue with Google'),
          findsOneWidget,
        );
        expect(h.requests.any((r) => r.url.path == '/api/auth/logout'), isTrue);
      },
    );
  }
  flow(
    'failed email sign-in keeps credentials editable and registration can be selected',
    (t, h) async {
      await h.boot();
      await h.tapText('Me');
      await reveal(t, h, find.text('Email'));
      await t.enterText(find.byType(TextField).first, 'driver@example.test');
      await t.enterText(find.byType(TextField).last, 'long-test-password');
      final signIn = find.widgetWithText(FilledButton, 'Sign in');
      await reveal(t, h, signIn);
      await t.tap(signIn);
      await h.frames();
      await reveal(
        t,
        h,
        find.textContaining('Fixture unavailable'),
        delta: -250,
      );
      expect(find.textContaining('Fixture unavailable'), findsOneWidget);
      expect(find.byType(ProfilePage), findsOneWidget);
      final create = find.text('New here? Create an account');
      await reveal(t, h, create);
      await t.tap(create);
      await h.frames();
      await reveal(t, h, find.text('Password (12+ characters)'), delta: -200);
      expect(find.text('Password (12+ characters)'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Create account'),
        findsOneWidget,
      );
      final request = h.requests.lastWhere(
        (r) => r.url.path == '/api/auth/login',
      );
      expect(jsonDecode(request.body)['email'], 'driver@example.test');
    },
  );
}

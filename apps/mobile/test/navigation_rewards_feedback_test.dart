import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waybi_friends/waybi_friends.dart';
import 'package:waybi_mobile/data/navigation_feedback_repository.dart';
import 'package:waybi_mobile/data/navigation_reward_repository.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/drive/journey_tracker.dart';
import 'package:waybi_mobile/widgets/navigation_feedback_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'country resolution uses real reverse metadata; cancellation gets no gift',
    () async {
      final controller = GameController(saveKey: 'real-trip');
      final repository = NavigationRewardRepository(
        controller: controller,
        client: MockClient(
          (request) async => http.Response('{"countryCode":"jp"}', 200),
        ),
      );
      addTearDown(controller.dispose);
      addTearDown(repository.dispose);
      final country = repository.countryAt(const GeoPoint(35.68, 139.76));
      expect(await country, 'JP');
      final now = DateTime(2026, 10, 5);
      JourneySummary summary(bool arrived) => JourneySummary(
        destination: 'Tokyo',
        startedAt: now,
        finishedAt: now.add(const Duration(minutes: 15)),
        distanceMeters: 2000,
        points: const [],
        cameraCount: 0,
        arrived: arrived,
      );
      expect(
        await repository.complete(summary(false), country: country),
        isNull,
      );
      expect(controller.state.memories, isEmpty);
      final reward = await repository.complete(summary(true), country: country);
      expect(reward?.countryCode, 'JP');
      expect(reward?.destinationName, 'Tokyo');
      expect(
        await repository.complete(summary(true), country: country),
        isNull,
      );
    },
  );
  test(
    'GPS-independent gift fallback handles missing reverse country',
    () async {
      final controller = GameController(saveKey: 'fallback');
      final repository = NavigationRewardRepository(
        controller: controller,
        client: MockClient((request) async => http.Response('{}', 200)),
      );
      addTearDown(controller.dispose);
      addTearDown(repository.dispose);
      expect(await repository.countryAt(const GeoPoint(48.85, 2.29)), isNull);
    },
  );
  test('offline vote persists and retries one anonymous receipt', () async {
    var online = false;
    final bodies = <Map<String, dynamic>>[];
    final repository = NavigationFeedbackRepository(
      client: MockClient((request) async {
        bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response('{}', online ? 202 : 503);
      }),
    );
    addTearDown(repository.dispose);
    await repository.vote('local-trip', -1);
    expect(await repository.voteFor('local-trip'), -1);
    online = true;
    await repository.flush();
    await repository.flush();
    expect(bodies, hasLength(2));
    expect(bodies[0], bodies[1]);
    expect(bodies[1].keys.toSet(), {'id', 'vote'});
    await repository.vote('local-trip', 1);
    expect(await repository.voteFor('local-trip'), -1);
    expect(bodies, hasLength(2));
  });
  testWidgets(
    'feedback needs one tap and no text reply, remembered on reopen',
    (tester) async {
      final repository = NavigationFeedbackRepository(
        client: MockClient((request) async => http.Response('{}', 202)),
      );
      addTearDown(repository.dispose);
      Widget page() => MaterialApp(
        home: Scaffold(
          body: NavigationFeedbackCard(
            tripId: 'tap',
            language: 'zh',
            repository: repository,
          ),
        ),
      );
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.byKey(const ValueKey('navigation-like')));
      await tester.pumpAndSettle();
      expect(find.text('谢谢你的评价！'), findsOneWidget);
      expect(await tester.runAsync(() => repository.voteFor('tap')), 1);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('navigation-like')))
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
}

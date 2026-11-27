import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waybi_mobile/app/journey_store.dart';
import 'package:waybi_mobile/data/account_repository.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/drive/journey_tracker.dart';

Map<String, Object> profile({bool totals = true}) => {
  'user': {
    'id': 'driver',
    'email': 'driver@example.test',
    'displayName': 'Driver',
    'providers': ['password'],
  },
  'subscription': {'plan': 'free'},
  'savedPlaces': [],
  'routeHistory': [],
  'reviews': [],
  if (totals)
    'companionTotals': {
      'distanceMeters': 0,
      'tripCount': 0,
      'durationSeconds': 0,
    },
};

JourneySummary summary(double metres) => JourneySummary(
  destination: 'Harbour',
  startedAt: DateTime(2026, 11, 1, 8),
  finishedAt: DateTime(2026, 11, 1, 8, 20),
  distanceMeters: metres,
  points: const [GeoPoint(-37.2, 174.9)],
  cameraCount: 0,
  arrived: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(AccountRepository, List<http.Request>)> account({
    bool signedIn = true,
    bool totals = true,
    int routeStatus = 200,
    int importStatus = 200,
  }) async {
    FlutterSecureStorage.setMockInitialValues({
      if (signedIn) 'waybi_session': 'f' * 64,
    });
    final requests = <http.Request>[];
    final repository = AccountRepository(
      client: MockClient((request) async {
        requests.add(request);
        final status = switch (request.url.path) {
          '/api/profile/routes' => routeStatus,
          '/api/profile/companion/import' => importStatus,
          _ => 200,
        };
        return http.Response(
          jsonEncode(status == 200 ? profile(totals: totals) : {'error': 'x'}),
          status,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(repository.dispose);
    await repository.restore();
    return (repository, requests);
  }

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('signed-in trips are kept until the account confirms them', () async {
    final (repository, requests) = await account(routeStatus: 503);
    final store = JourneyStore(repository);
    await store.queueAccountJourney(
      destinationName: 'Harbour',
      latitude: -37.2,
      longitude: 174.9,
      mode: 'drive',
      distanceMeters: 1200,
      durationSeconds: 600,
    );
    await store.syncPendingAccountJourneys();
    final prefs = await SharedPreferences.getInstance();
    final outbox = prefs
        .getKeys()
        .where((key) => key.startsWith('waybi.companion.outbox.v1.driver.'))
        .toList();
    expect(outbox, hasLength(1), reason: 'a failed upload stays queued');
    final queued = jsonDecode(prefs.getString(outbox.single)!) as Map;
    expect(queued['destinationName'], 'Harbour');

    // The same idempotent payload is sent again once the account answers.
    final (online, sent) = await account();
    await JourneyStore(online).syncPendingAccountJourneys();
    final upload = sent.lastWhere((r) => r.url.path == '/api/profile/routes');
    expect((jsonDecode(upload.body) as Map)['journeyId'], queued['journeyId']);
    expect(
      prefs.getKeys().where((k) => k.startsWith('waybi.companion.outbox')),
      isEmpty,
    );
    expect(
      requests.where((r) => r.url.path == '/api/profile/routes'),
      isNotEmpty,
    );
  });

  test('concurrent flushes share one upload pass', () async {
    final (repository, requests) = await account();
    final store = JourneyStore(repository);
    await store.queueAccountJourney(
      destinationName: 'A',
      latitude: -37.2,
      longitude: 174.9,
      mode: 'walk',
      distanceMeters: 100,
      durationSeconds: 60,
    );
    final first = store.syncPendingAccountJourneys();
    final second = store.syncPendingAccountJourneys();
    await Future.wait([first, second]);
    expect(
      requests.where((r) => r.url.path == '/api/profile/routes').length,
      1,
    );
  });

  test(
    'nothing uploads without an account that keeps lifetime totals',
    () async {
      final (repository, requests) = await account(totals: false);
      final store = JourneyStore(repository);
      await store.queueAccountJourney(
        destinationName: 'A',
        latitude: -37.2,
        longitude: 174.9,
        mode: 'drive',
        distanceMeters: 100,
        durationSeconds: 60,
      );
      await store.syncPendingAccountJourneys();
      await store.syncGuestCompanionJourneys();
      expect(
        requests.where((r) => r.url.path.startsWith('/api/profile/')),
        isEmpty,
      );
      final (guest, _) = await account(signedIn: false);
      await JourneyStore(guest).queueAccountJourney(
        destinationName: 'A',
        latitude: -37.2,
        longitude: 174.9,
        mode: 'drive',
        distanceMeters: 100,
        durationSeconds: 60,
      );
    },
  );

  test('guest totals accumulate and import once with a stable id', () async {
    final (guest, _) = await account(signedIn: false);
    final store = JourneyStore(guest);
    await store.recordGuestJourney(summary(1000));
    await store.recordGuestJourney(summary(500));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('${JourneyStore.guestPrefix}distance'), 1500);
    expect(prefs.getInt('${JourneyStore.guestPrefix}trips'), 2);
    expect(prefs.getInt('${JourneyStore.guestPrefix}duration'), 2400);

    final (failing, _) = await account(importStatus: 503);
    await JourneyStore(failing).syncGuestCompanionJourneys();
    final importId = prefs.getString('${JourneyStore.guestPrefix}import_id');
    expect(importId, isNotNull, reason: 'the id survives a failed import');
    expect(prefs.getInt('${JourneyStore.guestPrefix}trips'), 2);

    final (online, sent) = await account();
    await JourneyStore(online).syncGuestCompanionJourneys();
    final upload = sent.lastWhere(
      (r) => r.url.path == '/api/profile/companion/import',
    );
    expect((jsonDecode(upload.body) as Map)['importId'], importId);
    expect(prefs.getInt('${JourneyStore.guestPrefix}trips'), isNull);
    await JourneyStore(online).syncGuestCompanionJourneys();
    expect(
      sent.where((r) => r.url.path == '/api/profile/companion/import').length,
      1,
    );
  });

  test('journey ids are unique and prefixed', () {
    final ids = {for (var i = 0; i < 20; i++) JourneyStore.newJourneyId()};
    expect(ids, hasLength(20));
    expect(ids.every((id) => id.startsWith('wb_')), isTrue);
  });
}

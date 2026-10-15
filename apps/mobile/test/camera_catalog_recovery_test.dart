import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waybi_mobile/data/camera_repository.dart';

Map<String, Object> catalog() => {
  'syncStatus': 'live',
  'checkedAt': '2026-10-14T03:00:00Z',
  'sourceUpdatedAt': '2026-10-01',
  'cameras': [
    {
      'id': 'verified-1',
      'name': 'Queen Street',
      'region': 'Auckland',
      'suburb': 'CBD',
      'location': 'Queen Street',
      'type': 'Red light',
      'latitude': -36.85,
      'longitude': 174.76,
    },
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'invalid successful HTTP responses cannot erase a validated camera catalog',
    () async {
      for (final broken in [
        <String, Object>{},
        {'cameras': <Object>[]},
        {
          'cameras': ['not a camera'],
        },
        {
          ...catalog(),
          'cameras': [
            {
              'id': 'invalid',
              'name': 'Wrong location',
              'type': 'Spot speed',
              'latitude': 0,
              'longitude': 0,
            },
          ],
        },
      ]) {
        SharedPreferences.setMockInitialValues({});
        var calls = 0;
        final repository = CameraRepository(
          client: MockClient(
            (_) async => http.Response(
              jsonEncode(++calls == 1 ? catalog() : broken),
              200,
            ),
          ),
        );
        await repository.fetchSnapshot();
        final kept = await repository.fetchSnapshot();
        expect(kept.cameras.single.id, 'verified-1');
        expect(kept.fromCache, isTrue);
        expect(kept.syncStatus, 'stale');
        expect(kept.lastVerifiedAt, DateTime.utc(2026, 10, 14, 3));
        final prefs = await SharedPreferences.getInstance();
        final persisted = jsonDecode(
          prefs.getString('waybi.cache.cameras.v1')!,
        );
        expect(persisted['cameras'][0]['id'], 'verified-1');
      }
    },
  );

  test('an empty catalog without a saved copy is an error, not zero camera coverage', () async {
    final repository = CameraRepository(
      client: MockClient((_) async => http.Response('{"cameras":[]}', 200)),
    );
    await expectLater(repository.fetchSnapshot(), throwsFormatException);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('waybi.cache.cameras.v1'), isFalse);
  });

  test(
    'failed source attempts never become successful verification dates',
    () async {
      final repository = CameraRepository(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              ...catalog(),
              'syncStatus': 'stale',
              'checkedAt': '2026-10-15T03:00:00Z',
              'lastSuccessfulAt': '2026-10-12T03:00:00Z',
            }),
            200,
          ),
        ),
      );
      final snapshot = await repository.fetchSnapshot();
      expect(snapshot.fromCache, isFalse);
      expect(snapshot.checkedAt, DateTime.utc(2026, 10, 15, 3));
      expect(snapshot.lastVerifiedAt, DateTime.utc(2026, 10, 12, 3));
    },
  );

  test('legacy failed snapshots do not invent a verification date', () async {
    final repository = CameraRepository(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({...catalog(), 'syncStatus': 'stale'}),
          200,
        ),
      ),
    );
    expect((await repository.fetchSnapshot()).lastVerifiedAt, isNull);
  });

  test('offline copies retain the last verified date after restart', () async {
    SharedPreferences.setMockInitialValues({
      'waybi.cache.cameras.v1': jsonEncode(catalog()),
    });
    final repository = CameraRepository(
      client: MockClient((_) async => throw http.ClientException('offline')),
    );
    final snapshot = await repository.fetchSnapshot();
    expect(snapshot.fromCache, isTrue);
    expect(snapshot.lastVerifiedAt, DateTime.utc(2026, 10, 14, 3));
    expect(snapshot.cameras.single.id, 'verified-1');
  });
}

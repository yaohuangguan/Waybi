import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kiwi_lens_mobile/data/camera_repository.dart';
import 'package:kiwi_lens_mobile/data/nzta_traffic_road_event_provider.dart';
import 'package:kiwi_lens_mobile/domain/road_event.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'camera repository falls back to the persisted snapshot offline',
    () async {
      SharedPreferences.setMockInitialValues({
        'kiwi.cache.cameras.v1': jsonEncode({
          'syncStatus': 'live',
          'sourceUpdatedAt': '2026-10-01T00:00:00Z',
          'checkedAt': '2026-10-01T00:05:00Z',
          'cameras': [
            {
              'id': 'camera-1',
              'name': 'Queen Street',
              'region': 'Auckland',
              'suburb': 'City Centre',
              'location': 'Queen Street',
              'type': 'Spot speed',
              'latitude': -36.8485,
              'longitude': 174.7633,
            },
          ],
        }),
      });
      final repository = CameraRepository(
        baseUrl: 'https://offline.test',
        client: MockClient((_) async => throw http.ClientException('offline')),
      );

      final snapshot = await repository.fetchSnapshot();

      expect(snapshot.syncStatus, 'stale');
      expect(snapshot.cameras, hasLength(1));
      expect(snapshot.cameras.single.id, 'camera-1');
    },
  );

  test(
    'road-event provider falls back to persisted NZTA events offline',
    () async {
      SharedPreferences.setMockInitialValues({
        'kiwi.cache.road_events.v1': jsonEncode({
          'syncStatus': 'live',
          'checkedAt': '2026-10-01T00:05:00Z',
          'events': [
            {
              'id': 'roadworks-1',
              'type': 'roadworks',
              'location': {'latitude': -36.85, 'longitude': 174.76},
              'roadName': 'SH 1',
              'severity': 'warning',
              'source': {
                'provider': 'NZTA Traffic and Travel',
                'country': 'NZ',
                'sourceId': 'roadworks-1',
              },
            },
          ],
        }),
      });
      final provider = NztaTrafficRoadEventProvider(
        baseUrl: 'https://offline.test',
        client: MockClient((_) async => throw http.ClientException('offline')),
      );

      final events = await provider.load();

      expect(provider.lastSyncStatus, 'stale');
      expect(events, hasLength(1));
      expect(events.single.type, RoadEventType.roadworks);
      expect(events.single.roadName, 'SH 1');
    },
  );
}

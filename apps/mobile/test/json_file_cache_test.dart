import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waybi_mobile/data/camera_repository.dart';
import 'package:waybi_mobile/data/json_file_cache.dart';
import 'package:waybi_mobile/data/nzta_traffic_road_event_provider.dart';
import 'package:waybi_mobile/data/transit_lane_repository.dart';

class CountingCache extends JsonFileCache {
  CountingCache(super.fileName, {super.directory});
  int writes = 0;
  @override
  Future<bool> write(String raw) async {
    final written = await super.write(raw);
    if (written) writes++;
    return written;
  }
}

String lanes(String checkedAt) => jsonEncode({
  'schemaVersion': 1,
  'source': 'test',
  'checkedAt': checkedAt,
  'lanes': [
    for (var i = 0; i < 200; i++)
      {
        'id': 'lane-$i',
        'kind': 'Bus',
        'schedule': {'known': false},
        'coordinates': [
          [174.76, -36.85],
          [174.761, -36.85],
        ],
      },
  ],
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    directory = Directory.systemTemp.createTempSync('waybi-cache-test');
  });
  tearDown(() => directory.deleteSync(recursive: true));

  test(
    'large caches live in files, skip unchanged writes and migrate prefs once',
    () async {
      SharedPreferences.setMockInitialValues({'legacy.key': '{"old":true}'});
      final cache = JsonFileCache(
        'catalog.json',
        legacyPrefsKey: 'legacy.key',
        directory: () async => directory,
      );
      expect(await cache.read(), '{"old":true}');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('legacy.key'), isNull, reason: 'Migrated once');
      expect(
        File('${directory.path}/catalog.json').readAsStringSync(),
        '{"old":true}',
      );
      expect(await cache.write('{"old":true}'), isFalse);
      expect(await cache.write('{"new":true}'), isTrue);
      final reopened = JsonFileCache(
        'catalog.json',
        legacyPrefsKey: 'legacy.key',
        directory: () async => directory,
      );
      expect(await reopened.read(), '{"new":true}');
      expect(
        await JsonFileCache(
          'missing.json',
          directory: () async => directory,
        ).read(),
        isNull,
      );
      // An unwritable location is not fatal.
      final broken = JsonFileCache(
        'x.json',
        directory: () async => Directory('${directory.path}/missing/dir'),
      );
      expect(await broken.write('{}'), isFalse);
    },
  );

  test(
    'without an app directory the cache falls back to preferences',
    () async {
      final cache = JsonFileCache('fallback.json');
      expect(await cache.read(), isNull);
      expect(await cache.write('{"a":1}'), isTrue);
      expect(await JsonFileCache('fallback.json').read(), '{"a":1}');
    },
  );

  test('large JSON decodes on a background isolate', () async {
    final previous = decodeLargeJsonInIsolate;
    decodeLargeJsonInIsolate = true;
    addTearDown(() => decodeLargeJsonInIsolate = previous);
    expect(await decodeJsonOffMain('{"a":[1,2]}', threshold: 4), {
      'a': [1, 2],
    });
    expect(await decodeJsonOffMain('[1]'), [1]);
  });

  test(
    'a newer cached lane snapshot is used without decoding the bundled seed',
    () async {
      final cache = JsonFileCache(
        'lanes.json',
        directory: () async => directory,
      );
      await cache.write(lanes('2026-11-01T00:00:00Z'));
      final repository = TransitLaneRepository(
        cache: cache,
        // Deliberately undecodable: only its checkedAt may be read.
        seedLoader: () async =>
            '{"checkedAt":"2026-10-09T05:41:35Z","lanes":[BROKEN',
      );
      final snapshot = await repository.loadLocal();
      expect(snapshot.lanes, hasLength(200));
      expect(snapshot.checkedAt, DateTime.parse('2026-11-01T00:00:00Z'));
      final seeded = TransitLaneRepository(
        cache: JsonFileCache('none.json', directory: () async => directory),
        seedLoader: () async => lanes('2026-10-09T05:41:35Z'),
      );
      expect((await seeded.loadLocal()).checkedAt.month, 10);
    },
  );

  test('camera catalogue and road events use file caches', () async {
    var cameraStatus = 200;
    final cameraCache = CountingCache(
      'cameras.json',
      directory: () async => directory,
    );
    final cameras = CameraRepository(
      cache: cameraCache,
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'syncStatus': 'live',
            'cameras': [
              {
                'id': 'cam',
                'name': 'SH1',
                'type': 'Fixed speed camera',
                'latitude': -36.85,
                'longitude': 174.76,
              },
            ],
          }),
          cameraStatus,
        ),
      ),
    );
    await cameras.fetchSnapshot();
    await cameras.fetchSnapshot();
    expect(
      cameraCache.writes,
      1,
      reason: 'An unchanged catalogue is not rewritten',
    );
    cameraStatus = 503;
    final offline = await CameraRepository(
      cache: CountingCache('cameras.json', directory: () async => directory),
      client: MockClient((_) async => http.Response('', 503)),
    ).fetchSnapshot();
    expect(offline.fromCache, isTrue);
    expect(offline.cameras.single.id, 'cam');

    var checked = 0;
    final caches = <CountingCache>[];
    final events = NztaTrafficRoadEventProvider(
      cache: (key) {
        final cache = CountingCache(
          '$key.json',
          directory: () async => directory,
        );
        caches.add(cache);
        return cache;
      },
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'syncStatus': 'live',
            // Changes on every poll; the events do not.
            'checkedAt': DateTime.utc(
              2026,
              11,
              26,
              9,
              checked++,
            ).toIso8601String(),
            'retrievedAt': DateTime.now().toUtc().toIso8601String(),
            'events': [
              {
                'id': 'e1',
                'type': 'roadworks',
                'location': {'latitude': -36.85, 'longitude': 174.76},
                'source': {
                  'provider': 'NZTA',
                  'country': 'NZ',
                  'sourceId': 'e1',
                },
              },
            ],
          }),
          200,
        ),
      ),
    );
    await events.load();
    await events.load();
    await events.load();
    expect(caches.single.writes, 1);
  });
}

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:waybi_mobile/data/account_repository.dart';

const token =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const profile = {
  'user': {
    'id': 'driver',
    'email': 'driver@example.test',
    'displayName': 'Driver',
    'providers': ['password'],
  },
  'subscription': {'plan': 'plus'},
  'savedPlaces': [],
  'routeHistory': [],
  'reviews': [],
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test('password sign-in only persists a server-issued session and releases loading on failure', () async {
    var headers = <String, String>{};
    final requests = <http.Request>[];
    final account = AccountRepository(
      client: MockClient((r) async {
        requests.add(r);
        return http.Response(jsonEncode(profile), 200, headers: headers);
      }),
    );
    addTearDown(account.dispose);
    await expectLater(
      account.authenticate(' driver@example.test ', 'password', register: true),
      throwsStateError,
    );
    expect(account.signedIn, isFalse);
    expect(account.loading, isFalse);
    expect(
      await const FlutterSecureStorage().read(key: 'waybi_session'),
      isNull,
    );
    headers = {'set-cookie': 'waybi_session=$token; Path=/; HttpOnly'};
    await account.authenticate(
      ' driver@example.test ',
      'password',
      register: false,
    );
    expect(account.signedIn, isTrue);
    expect(
      (jsonDecode(requests.last.body) as Map)['email'],
      'driver@example.test',
    );
    expect(requests.last.url.path, '/api/auth/login');
    expect(
      await const FlutterSecureStorage().read(key: 'waybi_session'),
      token,
    );
  });
  test('expired sessions are removed while temporary offline errors preserve credentials for retry', () async {
    for (final status in [503, 401]) {
      FlutterSecureStorage.setMockInitialValues({'waybi_session': token});
      final account = AccountRepository(
        client: MockClient((_) async => http.Response('{}', status)),
      );
      await account.restore();
      expect(account.signedIn, status != 401);
      expect(
        await const FlutterSecureStorage().read(key: 'waybi_session'),
        status == 401 ? null : token,
      );
      account.dispose();
    }
  });
  test('profile, favorites, reviews and journeys use authenticated requests with complete payloads', () async {
    FlutterSecureStorage.setMockInitialValues({'waybi_session': token});
    final requests = <http.Request>[];
    final account = AccountRepository(
      client: MockClient((r) async {
        requests.add(r);
        return http.Response(jsonEncode(profile), 200);
      }),
    );
    addTearDown(account.dispose);
    await account.restore();
    await account.updateDisplayName('  New Driver  ');
    expect(jsonDecode(requests.last.body), {'displayName': 'New Driver'});
    await account.updatePreferences(language: 'zh-CN', voiceEnabled: false);
    expect(jsonDecode(requests.last.body), {
      'language': 'zh',
      'voiceEnabled': false,
    });
    await account.recordDestination(
      label: 'Home',
      latitude: -37,
      longitude: 174,
    );
    await account.recordRoute(
      journeyId: 'journey',
      destinationName: 'Home',
      latitude: -37,
      longitude: 174,
      mode: 'drive',
      distanceMeters: 1200,
      durationSeconds: 90,
    );
    expect((jsonDecode(requests.last.body) as Map)['journeyId'], 'journey');
    await account.importGuestJourneys(
      importId: 'once-only',
      distanceMeters: 1200,
      tripCount: 2,
      durationSeconds: 90,
    );
    expect((jsonDecode(requests.last.body) as Map)['importId'], 'once-only');
    await account.saveFavorite(
      placeId: 'home',
      name: 'Home',
      latitude: -37,
      longitude: 174,
      favorite: true,
    );
    expect((jsonDecode(requests.last.body) as Map)['isFavorite'], isTrue);
    await account.saveReview(
      placeId: 'home',
      placeName: 'Home',
      rating: 4,
      comment: 'Quiet',
    );
    expect((jsonDecode(requests.last.body) as Map)['rating'], 4);
    await account.refresh();
    expect(
      requests.every((r) => r.headers['cookie'] == 'waybi_session=$token'),
      isTrue,
    );
    expect(account.profile?.email, 'driver@example.test');
  });
  test('Route Watch preserves route geometry, filters malformed records, bounds acknowledgements and encodes IDs', () async {
    FlutterSecureStorage.setMockInitialValues({'waybi_session': token});
    final requests = <http.Request>[];
    final account = AccountRepository(
      client: MockClient((r) async {
        requests.add(r);
        return http.Response(
          jsonEncode(
            r.url.path == '/api/auth/me'
                ? profile
                : {
                    'alerts': [
                      {'id': 'alert'},
                      null,
                    ],
                    'watches': [
                      {'id': 'watch'},
                      false,
                    ],
                  },
          ),
          200,
        );
      }),
    );
    addTearDown(account.dispose);
    await account.restore();
    expect(await account.routeWatchAlerts(), [
      {'id': 'alert'},
    ]);
    expect(await account.routeWatches(), [
      {'id': 'watch'},
    ]);
    await account.markRouteWatchAlertsRead(List.generate(75, (i) => '$i'));
    expect((jsonDecode(requests.last.body) as Map)['ids'], hasLength(50));
    await account.saveRouteWatch(
      label: 'Work',
      originName: 'Home',
      originLatitude: -37,
      originLongitude: 174,
      destinationName: 'Office',
      latitude: -37.1,
      longitude: 174.1,
      routeProvider: 'waybi',
      routePoints: [
        {'latitude': -37, 'longitude': 174},
        {'latitude': -37.1, 'longitude': 174.1},
      ],
      durationSeconds: 600,
      distanceMeters: 1000,
    );
    expect(
      (jsonDecode(requests.last.body) as Map)['routePoints'],
      hasLength(2),
    );
    await account.deleteRouteWatch('watch/with spaces');
    expect(requests.last.method, 'DELETE');
    expect(requests.last.url.toString(), contains('watch%2Fwith%20spaces'));
  });
  test('road report failure is visible and an accepted report retains heading and description', () async {
    var status = 503;
    final account = AccountRepository(
      client: MockClient((r) async {
        expect(jsonDecode(r.body), {
          'type': 'roadClosure',
          'latitude': -37.0,
          'longitude': 174.0,
          'headingDegrees': 90.0,
          'description': 'Ramp closed',
        });
        return http.Response('{}', status);
      }),
    );
    addTearDown(account.dispose);
    Future<void> report() => account.submitRoadReport(
      type: 'roadClosure',
      latitude: -37,
      longitude: 174,
      headingDegrees: 90,
      description: 'Ramp closed',
    );
    await expectLater(report(), throwsStateError);
    status = 201;
    await report();
  });
  test('failed account deletion keeps session and a confirmed success clears both current and legacy credentials', () async {
    FlutterSecureStorage.setMockInitialValues({
      'waybi_session': token,
      'kiwi_lens_session': token,
    });
    var deleteStatus = 503;
    final account = AccountRepository(
      client: MockClient((r) async {
        if (r.url.path == '/api/auth/delete') {
          expect(jsonDecode(r.body), {
            'email': 'driver@example.test',
            'confirmation': 'DELETE',
          });
          return http.Response('{}', deleteStatus);
        }
        if (r.url.path == '/api/auth/logout') {
          throw http.ClientException('offline');
        }
        return http.Response(jsonEncode(profile), 200);
      }),
    );
    addTearDown(account.dispose);
    await account.restore();
    await expectLater(
      account.deleteAccount(email: 'other@example.test'),
      throwsStateError,
    );
    await expectLater(
      account.deleteAccount(email: 'driver@example.test'),
      throwsStateError,
    );
    expect(account.signedIn, isTrue);
    deleteStatus = 200;
    await account.deleteAccount(email: 'driver@example.test');
    expect(account.signedIn, isFalse);
    expect(account.profile, isNull);
    expect(
      await const FlutterSecureStorage().read(key: 'waybi_session'),
      isNull,
    );
    expect(
      await const FlutterSecureStorage().read(key: 'kiwi_lens_session'),
      isNull,
    );
  });
}

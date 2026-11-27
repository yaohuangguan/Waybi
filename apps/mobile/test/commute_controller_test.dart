import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waybi_mobile/app/commute_controller.dart';
import 'package:waybi_mobile/data/account_repository.dart';
import 'package:waybi_mobile/data/quick_location_store.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/domain/route_option.dart';
import 'package:waybi_mobile/widgets/trips_page.dart' show RouteWatchItem;

const home = PlaceSummary(
  name: 'Home',
  address: 'Home road',
  location: GeoPoint(-37.2, 174.91),
);
const work = PlaceSummary(
  name: 'Work',
  address: 'Work road',
  location: GeoPoint(-37.2, 174.92),
);

RouteOption route(String id, {int points = 3}) => RouteOption(
  id: id,
  mode: WaybiTravelMode.drive,
  durationSeconds: 600,
  distanceMeters: 1000,
  description: id,
  provider: 'independent',
  traffic: const TrafficSummary(normal: 0, slow: 0, trafficJam: 0),
  trafficIntervals: const [],
  points: [for (var i = 0; i < points; i++) GeoPoint(-37.2, 174.9 + i * .0001)],
);

/// A fake account server: profile, quick locations, Route Watch.
class Server {
  Server({this.plus = true});
  bool plus;
  final quickLocations = <Map<String, Object>>[];
  final alerts = <Map<String, Object>>[];
  final requests = <http.Request>[];
  Completer<void>? holdQuickLocations;
  int quickLocationStatus = 200;

  Map<String, Object> get profile => {
    'user': {
      'id': 'driver',
      'email': 'driver@example.test',
      'displayName': 'Driver',
      'providers': ['password'],
    },
    'subscription': {'plan': plus ? 'plus' : 'free'},
    'savedPlaces': [],
    'routeHistory': [],
    'reviews': [],
    'quickLocations': quickLocations,
  };

  late final client = MockClient((request) async {
    requests.add(request);
    final path = request.url.path;
    Object body = profile;
    var status = 200;
    if (path == '/api/profile/quick-locations') {
      await holdQuickLocations?.future;
      status = quickLocationStatus;
      if (status == 200) {
        final item = jsonDecode(request.body) as Map<String, dynamic>;
        quickLocations
          ..removeWhere((row) => row['label'] == item['label'])
          ..add(item.cast<String, Object>());
      }
    } else if (path == '/api/route-watch-alerts') {
      body = {'alerts': alerts};
    } else if (path == '/api/route-watch-alerts/read' ||
        path.startsWith('/api/route-watches')) {
      body = {'ok': true, 'watches': []};
    } else if (path == '/api/auth/logout') {
      body = {'ok': true};
    }
    return http.Response(
      jsonEncode(status == 200 ? body : {'error': 'offline'}),
      status,
      headers: {'content-type': 'application/json'},
    );
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Server server;
  late AccountRepository account;
  late List<(GeoPoint, GeoPoint)> lookups;
  late Object? routeError;
  late GeoPoint? origin;
  late bool paused;
  late DateTime now;
  late bool alertsEnabled;
  late List<({String id, String title, String body})> shown;

  Future<CommuteController> controller({
    bool signedIn = true,
    bool plus = true,
    String language = 'en',
    Map<String, Object> prefs = const {},
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    FlutterSecureStorage.setMockInitialValues({
      if (signedIn) 'waybi_session': 'f' * 64,
    });
    server = Server(plus: plus);
    account = AccountRepository(client: server.client);
    addTearDown(account.dispose);
    await account.restore();
    final commute = CommuteController(
      account: account,
      bestDriveRoute: (from, to) async {
        lookups.add((from, to));
        if (routeError != null) throw routeError!;
        return route('${from.longitude}->${to.longitude}');
      },
      origin: () => origin,
      paused: () => paused,
      language: () => language,
      routeWatchAlertsEnabled: () => alertsEnabled,
      clock: () => now,
      showAlert: ({required id, required title, required body}) async =>
          shown.add((id: id, title: title, body: body)),
    );
    addTearDown(commute.dispose);
    return commute;
  }

  setUp(() {
    lookups = [];
    routeError = null;
    origin = const GeoPoint(-37.2, 174.9);
    paused = false;
    now = DateTime(2026, 11, 27, 8);
    alertsEnabled = true;
    shown = [];
  });

  String guestShortcut(PlaceSummary place) => jsonEncode({
    'name': place.name,
    'address': place.address,
    'latitude': place.location.latitude,
    'longitude': place.location.longitude,
    'provider': 'independent',
  });

  group('commute ETAs', () {
    test('drive times are shared, fresh for 10 minutes and re-run after '
        'moving 800 m', () async {
      final commute = await controller(
        signedIn: false,
        prefs: {
          'waybi.quick_location.Home': guestShortcut(home),
          'waybi.quick_location.Work': guestShortcut(work),
        },
      );
      await commute.loadSaved();
      expect(commute.places.keys, containsAll(['Home', 'Work']));
      expect(commute.providerOf('Home'), MapProvider.independent);
      await commute.refreshQuick();
      expect(lookups, isEmpty, reason: 'nothing runs before settings load');
      commute.ready = true;
      var notified = 0;
      commute.addListener(() => notified++);
      final first = commute.refreshQuick();
      expect(identical(commute.refreshQuick(), first), isTrue);
      await first;
      expect(commute.quickRoutes.keys, containsAll(['Home', 'Work']));
      expect(lookups, hasLength(2));
      expect(notified, 1);

      await commute.refreshQuick();
      expect(lookups, hasLength(2), reason: 'still fresh');
      origin = const GeoPoint(-37.2, 174.8);
      await commute.refreshQuick();
      expect(lookups, hasLength(4), reason: 'moved more than 800 m');
      now = now.add(const Duration(minutes: 11));
      await commute.refreshQuick();
      expect(lookups, hasLength(6), reason: 'stale after 10 minutes');
      await commute.refreshQuick(force: true);
      expect(lookups, hasLength(8));
    });

    test('driving, no location, no shortcuts or failed routing keep the '
        'shortcuts usable', () async {
      final commute = await controller(
        signedIn: false,
        prefs: {'waybi.quick_location.Home': guestShortcut(home)},
      );
      commute.ready = true;
      paused = true;
      await commute.refreshQuick(force: true);
      origin = null;
      paused = false;
      await commute.refreshQuick(force: true);
      expect(lookups, isEmpty);
      origin = const GeoPoint(-37.2, 174.9);
      routeError = StateError('offline');
      await commute.loadSaved();
      await commute.refreshQuick(force: true);
      expect(commute.quickRoutes, isEmpty);
      expect(commute.places['Home'], isNotNull);
      routeError = null;
      await commute.refreshQuick(force: true);
      expect(commute.quickRoutes.keys, ['Home']);
      // Signing out a guest with no shortcuts clears the badges.
      SharedPreferences.setMockInitialValues({});
      await commute.restoreGuest();
      await commute.refreshQuick(force: true);
      expect(commute.places, isEmpty);
      expect(commute.quickRoutes, isEmpty);
    });

    test('Smart Commute needs Plus and both shortcuts', () async {
      final commute = await controller(plus: false);
      await commute.refreshSmart();
      expect(lookups, isEmpty);
      server.quickLocations.addAll([
        {...shortcutRow('Home', home)},
        {...shortcutRow('Work', work)},
      ]);
      final plus = await controller();
      server.quickLocations.addAll([
        shortcutRow('Home', home),
        shortcutRow('Work', work),
      ]);
      await account.refresh();
      plus.ready = true;
      await plus.syncWithAccount();
      await plus.refreshSmart();
      expect(plus.smartRoutes.keys, containsAll(['home-work', 'work-home']));
      final count = lookups.length;
      await plus.refreshSmart();
      expect(lookups.length, count, reason: 'fresh for 10 minutes');
      routeError = StateError('offline');
      await plus.refreshSmart(force: true);
      expect(plus.smartRoutes, isEmpty);
      plus.clearSmart();
      paused = true;
      await plus.refreshSmart(force: true);
      expect(plus.smartRoutes, isEmpty);
    });
  });

  group('account shortcuts', () {
    test(
      'remote Home and Work replace the cache once; repeats are no-ops',
      () async {
        final commute = await controller();
        server.quickLocations.addAll([
          shortcutRow('Home', home),
          shortcutRow('Work', work),
        ]);
        await account.refresh();
        commute.ready = true;
        var notified = 0;
        commute.addListener(() => notified++);
        await commute.syncWithAccount();
        expect(commute.places['Home']!.name, 'Home');
        expect(await QuickLocationStore().ownerUserId(), 'driver');
        await pumpEventQueue();
        final afterFirst = (notified, lookups.length);
        expect(afterFirst.$1, greaterThan(0));
        await commute.syncWithAccount();
        commute.onAccountChanged();
        await pumpEventQueue();
        expect((notified, lookups.length), afterFirst);
      },
    );

    test(
      'a device shortcut uploads to the account and survives going offline',
      () async {
        final commute = await controller(
          prefs: {
            'waybi.quick_location.owner_user_id': 'driver',
            'waybi.quick_location.Home': guestShortcut(home),
          },
        );
        commute.ready = true;
        server.quickLocationStatus = 503;
        await commute.syncWithAccount();
        expect(commute.places['Home'], isNotNull);
        server.quickLocationStatus = 200;
        await commute.syncWithAccount();
        expect(server.quickLocations.single['label'], 'Home');
      },
    );

    test('another owner\'s cached shortcuts are dropped', () async {
      final commute = await controller(
        prefs: {
          'waybi.quick_location.owner_user_id': 'someone-else',
          'waybi.quick_location.Home': guestShortcut(home),
        },
      );
      await commute.loadSaved();
      expect(commute.places, isEmpty, reason: 'the store hides them');
      commute.ready = true;
      await commute.syncWithAccount();
      expect(commute.places, isEmpty);
    });

    test('signing out mid-sync never writes the old account back', () async {
      final commute = await controller(
        prefs: {
          'waybi.quick_location.owner_user_id': 'driver',
          'waybi.quick_location.Home': guestShortcut(home),
        },
      );
      server.quickLocations.add(shortcutRow('Work', work));
      await account.refresh();
      commute.ready = true;
      server.holdQuickLocations = Completer<void>();
      final sync = commute.syncWithAccount();
      await pumpEventQueue();
      // A second account notification while syncing queues one more pass.
      unawaited(commute.syncWithAccount());
      await account.signOut();
      await commute.restoreGuest();
      server.holdQuickLocations!.complete();
      await sync;
      await pumpEventQueue();
      expect(commute.places, isEmpty);
    });

    test('setPlace saves on the device and the account', () async {
      final guest = await controller(signedIn: false);
      guest.ready = true;
      await guest.setPlace('Work', work, MapProvider.independent);
      expect(guest.places['Work'], work);
      expect((await QuickLocationStore().load())['Work']?.place.name, 'Work');
      expect(server.requests.where((r) => r.method == 'POST'), isEmpty);

      final signedIn = await controller();
      server.quickLocationStatus = 503;
      await signedIn.setPlace('Home', home, MapProvider.independent);
      expect(signedIn.places['Home'], home);
      expect(await QuickLocationStore().ownerUserId(), 'driver');
      expect(
        server.requests.where(
          (r) => r.url.path == '/api/profile/quick-locations',
        ),
        hasLength(1),
      );
    });
  });

  group('Route Watch', () {
    test(
      'alerts: newest per watch, at most four, marked read, throttled',
      () async {
        final commute = await controller(language: 'zh');
        server.alerts.addAll([
          for (var i = 0; i < 6; i++)
            {
              'id': 'a$i',
              'routeWatchId': 'w$i',
              'label': i == 1 ? '' : 'Commute $i',
              'status': i == 0 ? 'disrupted' : 'warning',
              'events': i == 2
                  ? []
                  : [
                      {
                        'roadName': 'Fixture road',
                        'impact': i == 3 ? '' : 'Closed',
                      },
                    ],
            },
          {'id': 'duplicate', 'routeWatchId': 'w0', 'events': []},
        ]);
        await commute.deliverRouteWatchAlerts();
        expect(shown, hasLength(4));
        expect(shown.any((s) => s.title.contains('严重影响')), isTrue);
        expect(shown.any((s) => s.title.startsWith('已保存通勤')), isTrue);
        expect(shown.any((s) => s.body.contains('个道路事件')), isTrue);
        final read = server.requests.lastWhere(
          (r) => r.url.path == '/api/route-watch-alerts/read',
        );
        expect((jsonDecode(read.body) as Map)['ids'], contains('duplicate'));
        await commute.deliverRouteWatchAlerts();
        expect(shown, hasLength(4), reason: 'throttled for two minutes');
        await commute.deliverRouteWatchAlerts(force: true);
        expect(shown, hasLength(8));
        now = now.add(const Duration(minutes: 3));
        server.alerts.clear();
        await commute.deliverRouteWatchAlerts();
        expect(shown, hasLength(8));
      },
    );

    test('alerts need an enabled setting, an account and Plus', () async {
      alertsEnabled = false;
      final commute = await controller();
      server.alerts.add({'id': 'a', 'routeWatchId': 'w', 'events': []});
      await commute.deliverRouteWatchAlerts(force: true);
      final free = await controller(plus: false);
      alertsEnabled = true;
      await free.deliverRouteWatchAlerts(force: true);
      final guest = await controller(signedIn: false);
      await guest.deliverRouteWatchAlerts(force: true);
      expect(shown, isEmpty);
    });

    test(
      'turning a watch on stores a sampled live route; off deletes it',
      () async {
        final commute = await controller();
        await expectLater(
          commute.setRouteWatch('home-work', null, true),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('Home and Work'),
            ),
          ),
        );
        server.quickLocations.addAll([
          shortcutRow('Home', home),
          shortcutRow('Work', work),
        ]);
        await account.refresh();
        commute.ready = true;
        await commute.syncWithAccount();
        await expectLater(
          commute.setRouteWatch('nowhere', null, true),
          throwsStateError,
        );
        routeError = StateError('offline');
        await expectLater(
          commute.setRouteWatch('home-work', null, true),
          throwsStateError,
        );
        routeError = null;
        await commute.setRouteWatch('work-home', null, true);
        final saved = server.requests.lastWhere(
          (r) => r.url.path == '/api/route-watches' && r.method == 'POST',
        );
        final body = jsonDecode(saved.body) as Map;
        expect(body['label'], 'work-home');
        expect(body['originName'], 'Work');
        await commute.setRouteWatch(
          'home-work',
          RouteWatchItem.fromJson({'id': 'watch-1', 'label': 'home-work'}),
          false,
        );
        expect(
          server.requests.last.url.path,
          endsWith('/route-watches/watch-1'),
        );
        await commute.setRouteWatch('home-work', null, false);
      },
    );

    test('watches need an account with Plus', () async {
      final guest = await controller(signedIn: false);
      await expectLater(
        guest.setRouteWatch('home-work', null, true),
        throwsStateError,
      );
      final free = await controller(plus: false, language: 'zh');
      await expectLater(
        free.setRouteWatch('home-work', null, true),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Plus'),
          ),
        ),
      );
    });

    test('long routes are sampled to 220 points', () {
      expect(CommuteController.watchPoints(const [GeoPoint(0, 0)]), isEmpty);
      final long = route('long', points: 1000).points;
      final sampled = CommuteController.watchPoints(long);
      expect(sampled, hasLength(220));
      expect(sampled.first['longitude'], long.first.longitude);
      expect(sampled.last['longitude'], long.last.longitude);
      expect(
        CommuteController.watchPoints(route('short').points),
        hasLength(3),
      );
    });
  });
}

Map<String, Object> shortcutRow(String label, PlaceSummary place) => {
  'label': label,
  'name': place.name,
  'address': place.address,
  'latitude': place.location.latitude,
  'longitude': place.location.longitude,
  'provider': 'independent',
};

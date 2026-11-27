import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:waybi_mobile/app/location_controller.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/drive/location_permission_gate.dart';
import 'package:waybi_mobile/drive/navigation_location_filter.dart';
import 'package:waybi_mobile/drive/reliable_location_feed.dart';

Position fix({
  double latitude = -37.2,
  double longitude = 174.9,
  double accuracy = 4,
  double speed = 0,
  double heading = 90,
  DateTime? time,
}) => Position(
  latitude: latitude,
  longitude: longitude,
  timestamp: time ?? DateTime.now(),
  accuracy: accuracy,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: heading,
  headingAccuracy: 5,
  speed: speed,
  speedAccuracy: 1,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StreamController<Position> positions;
  late StreamController<double> headings;
  late PermissionStatus permission;
  late bool driveActive;
  late double driveSpeed;
  late List<String> opened;
  late List<(NavigationLocationFix?, Position)> fixes;
  late List<String?> issues;
  late int feeds;
  late void Function(Object?) feedIssue;

  LocationController controller({String language = 'en'}) {
    final location = LocationController(
      driveActive: () => driveActive,
      driveSpeedKph: () => driveSpeed,
      language: () => language,
      permission: LocationPermissionGate(
        read: () async => permission,
        request: () async => permission,
      ),
      feedFactory: (onPosition, onIssue) {
        feeds++;
        feedIssue = onIssue;
        return ReliableLocationFeed(
          settings: const LocationSettings(),
          onPosition: onPosition,
          onIssue: onIssue,
          stream: (_) => positions.stream,
          request: (_) async => fix(),
        );
      },
      headings: () => headings.stream,
      appSettings: () async {
        opened.add('app');
        return true;
      },
      locationSettings: () async {
        opened.add('location');
        return true;
      },
    );
    location.onFix = (accepted, raw) {
      fixes.add((accepted, raw));
    };
    location.onIssue = issues.add;
    addTearDown(location.dispose);
    return location;
  }

  setUp(() {
    positions = StreamController<Position>.broadcast();
    headings = StreamController<double>.broadcast();
    permission = PermissionStatus.granted;
    driveActive = false;
    driveSpeed = 0;
    opened = [];
    fixes = [];
    issues = [];
    feeds = 0;
  });
  tearDown(() async {
    await positions.close();
    await headings.close();
  });

  test('accepted fixes move the location and notify listeners', () async {
    final location = controller();
    var heard = 0;
    location.locationListenable.addListener(() => heard++);
    // A first stationary fix waits for a consistent second one.
    final now = DateTime.now();
    expect(
      location.handlePosition(
        fix(time: now.subtract(const Duration(seconds: 1))),
      ),
      isFalse,
    );
    expect(fixes.single.$1, isNull);
    fixes.clear();
    expect(location.handlePosition(fix(time: now)), isTrue);
    expect(location.location, const GeoPoint(-37.2, 174.9));
    expect(location.accuracy, 4);
    expect(location.lastReliablePosition, isNotNull);
    expect(location.routeOrigin, const GeoPoint(-37.2, 174.9));
    expect(fixes.single.$1, isNotNull);
    expect(heard, 1);
    // A wildly inaccurate fix is held back.
    final jump = fix(longitude: 174.95, accuracy: 900);
    location.handlePosition(jump);
    expect(location.location, const GeoPoint(-37.2, 174.9));
    expect(fixes.last.$1, isNull);
    expect(location.accuracy, 900);
    expect(heard, 1);
  });

  test('moving fixes give a travel heading; Drive speed is trusted', () async {
    final location = controller();
    final start = DateTime.now().subtract(const Duration(seconds: 10));
    for (var i = 0; i < 8; i++) {
      location.handlePosition(
        fix(
          longitude: 174.9 + i * .0001,
          speed: 9,
          time: start.add(Duration(seconds: i)),
        ),
      );
    }
    expect(location.travelHeading, isNotNull);
    location.handlePosition(fix(longitude: 174.9008, time: DateTime.now()));
    expect(location.travelHeading, isNull, reason: 'standing still');
    driveActive = true;
    driveSpeed = 50;
    expect(
      location.handlePosition(fix(longitude: 174.9009, time: DateTime.now())),
      isTrue,
    );
  });

  test('start runs the feed and compass once, not while driving', () async {
    final location = controller();
    driveActive = true;
    await location.start();
    expect(feeds, 0);
    driveActive = false;
    await location.start();
    await location.start();
    expect(feeds, 1);
    expect(location.running, isTrue);
    headings.add(42);
    headings.addError(StateError('no compass'));
    await pumpEventQueue();
    expect(location.deviceHeading, 42);
    positions.add(fix());
    await pumpEventQueue();
    expect(location.location, isNotNull);

    await location.pauseInBackground();
    await location.resume();
    expect(location.running, isTrue);
    await location.pauseForDrive();
    expect(location.running, isFalse);
    await location.recover();
    expect(feeds, 2);
  });

  test('permission problems are explained with the right action', () async {
    final location = controller(language: 'zh');
    permission = PermissionStatus.denied;
    expect(await location.ensurePermission(), isFalse);
    expect(location.issueAction, LocationNoticeAction.retry);
    expect(issues.last, contains('允许定位权限'));
    permission = PermissionStatus.permanentlyDenied;
    await location.start(requestPermission: true);
    expect(feeds, 0);
    expect(location.issueAction, LocationNoticeAction.appSettings);

    final failing = LocationController(
      driveActive: () => false,
      driveSpeedKph: () => 0,
      language: () => 'en',
      permission: LocationPermissionGate(
        read: () async => throw StateError('plugin'),
        request: () async => throw StateError('plugin'),
      ),
    );
    addTearDown(failing.dispose);
    expect(await failing.ensurePermission(), isFalse);
    expect(failing.issueMessage, contains('temporarily unavailable'));
  });

  test('feed issues: settings problems always, GPS trouble only when it '
      'blocks a route', () async {
    final location = controller();
    await location.start();
    feedIssue(const LocationServiceDisabledException());
    expect(location.issueAction, LocationNoticeAction.locationSettings);
    feedIssue(const PermissionDeniedException('denied'));
    expect(location.issueAction, LocationNoticeAction.appSettings);
    feedIssue(null);
    expect(location.issueMessage, isNull);
    expect(issues.last, isNull);
    feedIssue(null);
    expect(issues.whereType<Null>(), hasLength(1), reason: 'cleared once');

    // Without a route origin, waiting for GPS is worth saying.
    feedIssue(TimeoutException('quiet'));
    expect(location.issueMessage, contains('Waiting for a reliable location'));
    feedIssue(null);
    location.handlePosition(fix());
    final before = issues.length;
    feedIssue(TimeoutException('quiet'));
    expect(issues.length, before, reason: 'a known origin hides it');
    location.reportTransientIssues = () => true;
    feedIssue(TimeoutException('quiet'));
    expect(issues.length, before + 1);
    driveActive = true;
    feedIssue(const LocationServiceDisabledException());
    expect(issues.length, before + 1, reason: 'Drive owns location');
  });

  test('the banner action opens settings or retries', () async {
    final location = controller();
    var browse = 0, drive = 0;
    Future<void> recoverBrowse() async => browse++;
    Future<void> recoverDrive() async => drive++;
    location.reportIssue('x', LocationNoticeAction.appSettings);
    await location.resolveIssue(
      recoverDrive: recoverDrive,
      recoverBrowse: recoverBrowse,
    );
    location.reportIssue('x', LocationNoticeAction.locationSettings);
    await location.resolveIssue(
      recoverDrive: recoverDrive,
      recoverBrowse: recoverBrowse,
    );
    expect(opened, ['app', 'location']);
    location.reportIssue('x', LocationNoticeAction.retry);
    await location.resolveIssue(
      recoverDrive: recoverDrive,
      recoverBrowse: recoverBrowse,
    );
    driveActive = true;
    await location.resolveIssue(
      recoverDrive: recoverDrive,
      recoverBrowse: recoverBrowse,
    );
    expect((browse, drive), (1, 1));
    await location.resolveIssue(
      recoverDrive: () async => throw StateError('gps'),
      recoverBrowse: recoverBrowse,
    );
    expect(location.issueAction, LocationNoticeAction.appSettings);
    expect(location.issueMessage, contains('Could not recover location'));
  });

  test('a disposed controller ignores late fixes and issues', () async {
    final location = LocationController(
      driveActive: () => false,
      driveSpeedKph: () => 0,
      language: () => 'en',
    );
    location.dispose();
    expect(location.handlePosition(fix()), isFalse);
    location.reportIssue('late', LocationNoticeAction.retry);
    expect(location.issueMessage, isNull);
  });
}

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:waybi_mobile/drive/reliable_location_feed.dart';

Position fix(DateTime at) => Position(
  latitude: -36.8485,
  longitude: 174.7633,
  timestamp: at,
  accuracy: 6,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

void main() {
  test('profiles ask for less GPS when browsing or saving power', () {
    final browseIos = ReliableLocationFeed.settingsFor(
      LocationFeedProfile.browse,
      platform: TargetPlatform.iOS,
    ) as AppleSettings;
    expect(browseIos.accuracy, LocationAccuracy.high);
    expect(browseIos.distanceFilter, 5);
    expect(browseIos.allowBackgroundLocationUpdates, isFalse);
    expect(browseIos.pauseLocationUpdatesAutomatically, isTrue);
    final navigationIos = ReliableLocationFeed.settingsFor(
      LocationFeedProfile.navigation,
      platform: TargetPlatform.iOS,
    ) as AppleSettings;
    expect(navigationIos.accuracy, LocationAccuracy.bestForNavigation);
    expect(navigationIos.allowBackgroundLocationUpdates, isTrue);
    expect(navigationIos.activityType, ActivityType.automotiveNavigation);
    final lowAndroid = ReliableLocationFeed.settingsFor(
      LocationFeedProfile.lowPower,
      platform: TargetPlatform.android,
    ) as AndroidSettings;
    expect(lowAndroid.accuracy, LocationAccuracy.medium);
    expect(lowAndroid.distanceFilter, 50);
    expect(lowAndroid.intervalDuration, const Duration(seconds: 15));
    final desktop = ReliableLocationFeed.settingsFor(
      LocationFeedProfile.browse,
      platform: TargetPlatform.linux,
    );
    expect(desktop.distanceFilter, 5);
    expect(
      ReliableLocationFeed.staleAfterFor(LocationFeedProfile.navigation),
      const Duration(seconds: 10),
    );
    expect(
      ReliableLocationFeed.staleAfterFor(LocationFeedProfile.browse),
      const Duration(seconds: 30),
    );
    expect(
      ReliableLocationFeed.staleAfterFor(LocationFeedProfile.lowPower),
      const Duration(minutes: 2),
    );
  });

  test('recovery in a tunnel backs off instead of polling every 6 s', () {
    fakeAsync((time) {
      var now = DateTime(2026);
      final attemptTimes = <int>[];
      final streams = <StreamController<Position>>[];
      final feed = ReliableLocationFeed(
        settings: const LocationSettings(),
        clock: () => now,
        stream: (_) {
          final stream = StreamController<Position>(onCancel: () async {});
          streams.add(stream);
          return stream.stream;
        },
        request: (_) async {
          attemptTimes.add(now.difference(DateTime(2026)).inSeconds);
          throw TimeoutException('No fix underground');
        },
        onPosition: (_) => true,
        onIssue: (_) {},
      );
      feed.start();
      time.flushMicrotasks();
      for (var i = 0; i < 150; i++) {
        now = now.add(const Duration(seconds: 2));
        time.elapse(const Duration(seconds: 2));
      }
      // Was 51 one-shot requests in five minutes at a fixed 6 s.
      expect(attemptTimes.length, lessThanOrEqualTo(10));
      final gaps = [
        for (var i = 1; i < attemptTimes.length; i++)
          attemptTimes[i] - attemptTimes[i - 1],
      ];
      expect(gaps.take(2), everyElement(lessThanOrEqualTo(8)));
      expect(gaps.last, greaterThanOrEqualTo(60));
      expect(feed.recoveryInterval, const Duration(seconds: 60));
      // A real fix resets the back-off.
      streams.last.add(fix(now));
      time.flushMicrotasks();
      expect(feed.recoveryInterval, const Duration(seconds: 6));
      feed.stop();
      time.flushMicrotasks();
      for (final stream in streams) {
        stream.close();
      }
    });
  });

  test('pause releases the stream and resume asks for a fresh fix', () {
    fakeAsync((time) {
      var now = DateTime(2026);
      var subscriptions = 0, cancellations = 0, requests = 0;
      final seen = <Position>[];
      final feed = ReliableLocationFeed.profile(
        LocationFeedProfile.browse,
        clock: () => now,
        stream: (_) {
          subscriptions++;
          final controller = StreamController<Position>(
            onCancel: () async => cancellations++,
          );
          return controller.stream;
        },
        request: (_) async {
          requests++;
          return fix(now);
        },
        onPosition: (p) {
          seen.add(p);
          return true;
        },
        onIssue: (_) {},
      );
      expect(feed.profile, LocationFeedProfile.browse);
      expect(feed.staleAfter, const Duration(seconds: 30));
      feed.resume(); // Not running: no effect.
      feed.start();
      time.flushMicrotasks();
      expect(subscriptions, 1);
      expect(seen, hasLength(1));
      unawaited(feed.pause());
      time.flushMicrotasks();
      expect(feed.paused, isTrue);
      expect(feed.running, isTrue, reason: 'Still owned, so no second feed');
      expect(cancellations, 1);
      // Background: no watchdog recovery while paused.
      for (var i = 0; i < 30; i++) {
        now = now.add(const Duration(seconds: 2));
        time.elapse(const Duration(seconds: 2));
      }
      unawaited(feed.recover(force: true));
      time.flushMicrotasks();
      expect(requests, 1);
      unawaited(feed.pause()); // Already paused.
      feed.resume();
      time.flushMicrotasks();
      expect(feed.paused, isFalse);
      expect(subscriptions, 2);
      expect(requests, 2);
      expect(seen, hasLength(2));
      unawaited(feed.updateProfile(LocationFeedProfile.lowPower));
      time.elapse(const Duration(milliseconds: 1));
      expect(feed.profile, LocationFeedProfile.lowPower);
      expect(feed.settings.distanceFilter, 50);
      expect(subscriptions, 3, reason: 'Restarted with the new settings');
      unawaited(feed.updateProfile(LocationFeedProfile.lowPower));
      time.flushMicrotasks();
      expect(subscriptions, 3);
      unawaited(feed.stop());
      time.flushMicrotasks();
      unawaited(feed.updateProfile(LocationFeedProfile.navigation));
      time.flushMicrotasks();
      expect(subscriptions, 3, reason: 'A stopped feed only records settings');
      expect(feed.paused, isFalse);
    });
  });
}

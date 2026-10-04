import 'dart:async';

import 'package:fake_async/fake_async.dart';
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
  test('permission errors remain actionable during recovery timeouts', () {
    fakeAsync((time) {
      final stream = StreamController<Position>(onCancel: () async {});
      var now = DateTime(2026);
      final issues = <Object?>[];
      final feed = ReliableLocationFeed(
        settings: const LocationSettings(),
        clock: () => now,
        stream: (_) => stream.stream,
        request: (_) async {
          throw PermissionDeniedException('Denied');
        },
        onPosition: (_) => true,
        onIssue: issues.add,
      );
      feed.start();
      time.flushMicrotasks();
      now = now.add(const Duration(seconds: 2));
      time.elapse(const Duration(seconds: 2));
      expect(issues.length, 1);
      expect(issues.single, isA<PermissionDeniedException>());
      stream.add(fix(now));
      time.flushMicrotasks();
      expect(issues.last, isNull);
      feed.stop();
      time.flushMicrotasks();
      stream.close();
    });
  });
  test('startup requests a second real stationary fix without waiting for movement', () {
    fakeAsync((time) {
      final stream = StreamController<Position>(onCancel: () async {});
      final now = DateTime(2026);
      final seen = <Position>[];
      final feed = ReliableLocationFeed(
        settings: const LocationSettings(),
        clock: () => now,
        stream: (_) => stream.stream,
        request: (settings) async {
          expect(settings.timeLimit, const Duration(seconds: 5));
          return fix(now.add(const Duration(seconds: 1)));
        },
        onPosition: (p) {
          seen.add(p);
          return seen.length > 1;
        },
        onIssue: (_) {},
      );
      feed.start();
      stream.add(fix(now));
      time.flushMicrotasks();
      expect(seen.length, 2);
      feed.stop();
      time.flushMicrotasks();
      stream.close();
    });
  });
  test('missing initial GPS restarts a silent stream and recovers', () {
    fakeAsync((time) {
      var now = DateTime(2026);
      final streams = <StreamController<Position>>[];
      var attempts = 0;
      var accepted = 0;
      final feed = ReliableLocationFeed(
        settings: const LocationSettings(),
        clock: () => now,
        stream: (_) {
          final s = StreamController<Position>(onCancel: () async {});
          streams.add(s);
          return s.stream;
        },
        request: (_) async {
          attempts++;
          if (attempts < 3) throw TimeoutException('No fix');
          return fix(now);
        },
        onPosition: (_) {
          accepted++;
          return true;
        },
        onIssue: (_) {},
      );
      feed.start();
      time.flushMicrotasks();
      for (var i = 0; i < 6; i++) {
        now = now.add(const Duration(seconds: 2));
        time.elapse(const Duration(seconds: 2));
        time.elapse(const Duration(milliseconds: 1));
      }
      expect(attempts, 3);
      expect(streams.length, 2);
      expect(accepted, 1);
      feed.stop();
      time.flushMicrotasks();
      for (final stream in streams) {
        stream.close();
      }
    });
  });
  test('stream errors recover and late one-shot results cannot update a stopped trip', () {
    fakeAsync((time) {
      var now = DateTime(2026);
      final streams = <StreamController<Position>>[];
      final requests = <Completer<Position>>[];
      var seen = 0;
      final feed = ReliableLocationFeed(
        settings: const LocationSettings(),
        clock: () => now,
        stream: (_) {
          final s = StreamController<Position>(onCancel: () async {});
          streams.add(s);
          return s.stream;
        },
        request: (_) {
          final c = Completer<Position>();
          requests.add(c);
          return c.future;
        },
        onPosition: (_) {
          seen++;
          return true;
        },
        onIssue: (_) {},
      );
      feed.start();
      requests.first.complete(fix(now));
      time.flushMicrotasks();
      now = now.add(const Duration(seconds: 6));
      streams.first.addError(StateError('Stream disconnected'));
      time.flushMicrotasks();
      time.elapse(const Duration(milliseconds: 1));
      expect(streams.length, 2);
      expect(requests.length, 2);
      feed.stop();
      time.flushMicrotasks();
      requests.last.complete(fix(now));
      time.flushMicrotasks();
      expect(seen, 1);
      for (final stream in streams) {
        stream.close();
      }
    });
  });
  test(
    'a hanging request has a bounded timeout and permits another attempt',
    () {
      fakeAsync((time) {
        var now = DateTime(2026);
        final stream = StreamController<Position>(onCancel: () async {});
        var attempts = 0;
        final feed = ReliableLocationFeed(
          settings: const LocationSettings(),
          clock: () => now,
          stream: (_) => stream.stream,
          request: (_) {
            attempts++;
            return Completer<Position>().future;
          },
          onPosition: (_) => true,
          onIssue: (_) {},
        );
        feed.start();
        time.elapse(const Duration(seconds: 5));
        now = now.add(const Duration(seconds: 6));
        time.elapse(const Duration(seconds: 1));
        expect(attempts, 2);
        feed.stop();
        time.flushMicrotasks();
        stream.close();
      });
    },
  );
}

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/drive/reroute_scheduler.dart';

class FixedRandom implements math.Random {
  FixedRandom(this.value);
  final double value;
  @override
  double nextDouble() => value;
  @override
  bool nextBool() => false;
  @override
  int nextInt(int max) => 0;
}

const here = GeoPoint(-36.85, 174.76);
const moved = GeoPoint(-36.8496, 174.76); // ~44 m north

void main() {
  test('deviation reroutes back off 5, 10, 20, 40, 60 s from completion', () {
    final scheduler = RerouteScheduler(random: FixedRandom(0));
    var now = DateTime(2026);
    final gaps = <int>[];
    for (var attempt = 0; attempt < 6; attempt++) {
      final token = scheduler.start(now, here);
      expect(scheduler.inFlightAt(now), isTrue);
      expect(
        scheduler.canRerouteForDeviation(now, at: here, speedKph: 60),
        isFalse,
        reason: 'Never two requests at once',
      );
      // The request takes 3 s; back-off is measured from its completion.
      now = now.add(const Duration(seconds: 3));
      scheduler
        ..settled(token)
        ..finish(now);
      final completed = now;
      while (!scheduler.canRerouteForDeviation(now, at: here, speedKph: 60)) {
        now = now.add(const Duration(seconds: 1));
      }
      gaps.add(now.difference(completed).inSeconds);
    }
    expect(gaps, [5, 10, 20, 40, 60, 60]);
    expect(scheduler.streak, 6);
  });

  test('jitter only lengthens the delay, by at most 20 %', () {
    final scheduler = RerouteScheduler(random: FixedRandom(.999));
    final now = DateTime(2026);
    scheduler.settled(scheduler.start(now, here));
    scheduler.finish(now);
    expect(
      scheduler.deviationNotBefore!.difference(now).inMilliseconds,
      inInclusiveRange(5000, 6000),
    );
    expect(RerouteScheduler().deviationNotBefore, isNull);
  });

  test('a stationary car must move 40 m or drive faster than 10 km/h', () {
    final scheduler = RerouteScheduler(random: FixedRandom(0))
      ..anchorIfUnset(here)
      ..anchorIfUnset(moved);
    final now = DateTime(2026);
    expect(
      scheduler.canRerouteForDeviation(now, at: here, speedKph: 4),
      isFalse,
    );
    expect(
      scheduler.canRerouteForDeviation(now, at: moved, speedKph: 4),
      isTrue,
    );
    expect(
      scheduler.canRerouteForDeviation(now, at: here, speedKph: 11),
      isTrue,
    );
  });

  test('a request that never settles stops blocking after a minute', () {
    final scheduler = RerouteScheduler(random: FixedRandom(0));
    final now = DateTime(2026);
    scheduler.start(now, here);
    scheduler.finish(now.add(const Duration(seconds: 12)));
    expect(
      scheduler.canRerouteForDeviation(
        now.add(const Duration(seconds: 30)),
        at: moved,
        speedKph: 50,
      ),
      isFalse,
    );
    expect(
      scheduler.canRerouteForDeviation(
        now.add(const Duration(seconds: 61)),
        at: moved,
        speedKph: 50,
      ),
      isTrue,
    );
    // A stale token cannot release a newer request.
    final newer = scheduler.start(now.add(const Duration(seconds: 61)), here);
    scheduler.settled(Object());
    expect(scheduler.inFlightAt(now.add(const Duration(seconds: 62))), isTrue);
    scheduler.settled(newer);
    expect(scheduler.inFlightAt(now.add(const Duration(seconds: 62))), isFalse);
  });

  test('a server Retry-After holds every kind of reroute', () {
    final scheduler = RerouteScheduler(random: FixedRandom(0));
    final now = DateTime(2026);
    scheduler.settled(scheduler.start(now, here));
    scheduler.finish(now, retryAfter: const Duration(seconds: 90));
    final later = now.add(const Duration(seconds: 80));
    expect(
      scheduler.canRerouteForDeviation(later, at: moved, speedKph: 50),
      isFalse,
    );
    expect(scheduler.canRerouteForClosure(later, 'closure'), isFalse);
    final after = now.add(const Duration(seconds: 91));
    expect(
      scheduler.canRerouteForDeviation(after, at: moved, speedKph: 50),
      isTrue,
    );
    expect(scheduler.canRerouteForClosure(after, 'closure'), isTrue);
    scheduler.reset();
    expect(
      scheduler.canRerouteForClosure(now, 'closure'),
      isFalse,
      reason: 'A new trip still honours the server rate limit',
    );
  });

  test('closure retries back off and stop after five attempts', () {
    final scheduler = RerouteScheduler(random: FixedRandom(0));
    var now = DateTime(2026);
    final gaps = <int>[];
    for (var attempt = 0; attempt < 5; attempt++) {
      expect(scheduler.canRerouteForClosure(now, 'sh1'), isTrue);
      final token = scheduler.start(now, here, closureFingerprint: 'sh1');
      scheduler
        ..settled(token)
        ..finish(now, closure: true);
      final completed = now;
      var waited = 0;
      while (!scheduler.canRerouteForClosure(now, 'sh1') && waited < 600) {
        now = now.add(const Duration(seconds: 1));
        waited++;
      }
      gaps.add(now.difference(completed).inSeconds);
    }
    expect(gaps, [60, 120, 240, 300, 600]);
    expect(scheduler.canRerouteForClosure(now, 'sh1'), isFalse);
    expect(
      scheduler.canRerouteForClosure(now, 'sh1|sh2'),
      isTrue,
      reason: 'A different set of closures starts again',
    );
    scheduler.clearClosure();
    expect(scheduler.canRerouteForClosure(now, 'sh1'), isTrue);
    expect(scheduler.streak, 0, reason: 'Closure retries are separate');
  });

  test('thirty seconds on route resets the deviation back-off', () {
    final scheduler = RerouteScheduler(random: FixedRandom(0));
    final now = DateTime(2026);
    for (var i = 0; i < 3; i++) {
      scheduler.settled(scheduler.start(now, here));
    }
    scheduler.finish(now);
    scheduler.confirmOnRoute(now.add(const Duration(seconds: 10)));
    expect(scheduler.streak, 3);
    scheduler.confirmOnRoute(now.add(const Duration(seconds: 30)));
    expect(scheduler.streak, 0);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/drive/speed_limit_pacer.dart';

GeoPoint north(double metres) => GeoPoint(-36.85 + metres / 111320, 174.76);

void main() {
  test('one lookup every ~20 s at motorway speed, not every 75 m', () {
    final pacer = SpeedLimitPacer();
    var now = DateTime(2026);
    var travelled = 0.0;
    var lookups = 0;
    // An hour at 100 km/h with one fix per second.
    for (var second = 0; second < 3600; second++) {
      final at = north(travelled);
      if (pacer.shouldLookUp(now, at, 100)) {
        lookups++;
        pacer.started(now, at);
        pacer.finished(
          now.add(const Duration(milliseconds: 300)),
          success: true,
        );
      }
      travelled += 100 / 3.6;
      now = now.add(const Duration(seconds: 1));
    }
    expect(lookups, inInclusiveRange(150, 185)); // was ~1300
    expect(SpeedLimitPacer.distanceFor(100), closeTo(556, 1));
    expect(SpeedLimitPacer.distanceFor(10), 150);
  });

  test('a parked car does not poll, a slow one checks every 30 s', () {
    final pacer = SpeedLimitPacer();
    final start = DateTime(2026);
    expect(pacer.shouldLookUp(start, north(0), 0), isTrue);
    pacer
      ..started(start, north(0))
      ..finished(start, success: true);
    expect(
      pacer.shouldLookUp(start.add(const Duration(minutes: 10)), north(5), 0),
      isFalse,
    );
    expect(
      pacer.shouldLookUp(start.add(const Duration(seconds: 31)), north(40), 5),
      isTrue,
    );
    expect(
      pacer.shouldLookUp(start.add(const Duration(seconds: 3)), north(400), 60),
      isFalse,
      reason: 'Never more than one lookup per 5 s',
    );
  });

  test('a stalled request is abandoned and a Retry-After is honoured', () {
    final pacer = SpeedLimitPacer();
    final start = DateTime(2026);
    pacer.started(start, north(0));
    expect(
      pacer.shouldLookUp(
        start.add(const Duration(seconds: 9)),
        north(900),
        100,
      ),
      isFalse,
    );
    expect(
      pacer.shouldLookUp(
        start.add(const Duration(seconds: 11)),
        north(900),
        100,
      ),
      isTrue,
    );
    pacer.finished(
      start.add(const Duration(seconds: 11)),
      retryAfter: const Duration(minutes: 2),
    );
    expect(
      pacer.shouldLookUp(
        start.add(const Duration(seconds: 60)),
        north(3000),
        100,
      ),
      isFalse,
    );
    pacer.reset();
    expect(
      pacer.shouldLookUp(start.add(const Duration(seconds: 100)), north(0), 0),
      isFalse,
      reason: 'The server rate limit outlives a trip',
    );
    expect(
      pacer.shouldLookUp(start.add(const Duration(seconds: 132)), north(0), 0),
      isTrue,
    );
  });

  test('a limit is stale once the car has left its road', () {
    final pacer = SpeedLimitPacer();
    final start = DateTime(2026);
    expect(pacer.isStale(start, north(0)), isFalse);
    pacer
      ..started(start, north(0))
      ..finished(start, success: true);
    expect(
      pacer.isStale(start.add(const Duration(seconds: 50)), north(1000)),
      isFalse,
    );
    expect(
      pacer.isStale(start.add(const Duration(seconds: 60)), north(1600)),
      isTrue,
    );
    expect(
      pacer.isStale(start.add(const Duration(minutes: 4)), north(100)),
      isFalse,
    );
    expect(
      pacer.isStale(start.add(const Duration(minutes: 4)), north(300)),
      isTrue,
    );
    expect(SpeedLimitPacer.stillApplies(north(0), north(90), 30), isTrue);
    expect(SpeedLimitPacer.stillApplies(north(0), north(200), 30), isFalse);
    expect(SpeedLimitPacer.stillApplies(north(0), north(200), 100), isTrue);
  });
}

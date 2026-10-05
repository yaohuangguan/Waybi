import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waybi_friends/waybi_friends.dart';
import 'package:waybi_friends/src/journey_engine.dart';
import 'package:waybi_friends/src/souvenirs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final start = DateTime(2026, 10, 5, 8);
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('outings cover minutes and hours for all three travellers', () {
    final engine = JourneyEngine(Random(24));
    final durations = <int>{};
    for (var i = 0; i < 300; i++) {
      final kind = FriendKind.values[i % 3];
      final trip = engine.start([], at: start, traveller: kind);
      expect(trip.traveller, kind);
      durations.add(trip.returnAt.difference(trip.departedAt).inMinutes);
      expect(ActiveJourney.fromJson(trip.toJson()).traveller, kind);
    }
    expect(durations, containsAll([20, 50, 60, 300, 600, 720]));
  });
  test(
    'Clover can leave, remain away across restart and return once',
    () async {
      var now = start;
      final first = GameController(clock: () => now, saveKey: 'clover');
      await first.load();
      await first.startJourney(traveller: FriendKind.clover);
      final returnAt = first.state.activeJourney!.returnAt;
      first.dispose();
      now = start.add(const Duration(minutes: 10));
      final reopened = GameController(clock: () => now, saveKey: 'clover');
      addTearDown(reopened.dispose);
      await reopened.load();
      expect(reopened.isAway(FriendKind.clover), isTrue);
      expect(
        reopened.roomLife
            .sample(now, waybiAway: true)
            .friend(FriendKind.clover)
            .opacity,
        0,
      );
      expect(
        reopened.roomLife
            .sample(now, waybiAway: true)
            .friend(FriendKind.waybi)
            .opacity,
        1,
      );
      now = returnAt.add(const Duration(hours: 2));
      await Future.wait([reopened.tick(), reopened.tick()]);
      expect(reopened.state.memories.single.traveller, FriendKind.clover);
      expect(reopened.state.memories.single.storyZh, isNotEmpty);
    },
  );
  test('paths stay continuous at activity and cycle boundaries; facing follows motion', () {
    final life = RoomLife(startedAt: start);
    for (var i = 1; i < 6000; i++) {
      final before = life.sample(
        start.add(Duration(milliseconds: (i - 1) * 200)),
        waybiAway: false,
      );
      final after = life.sample(
        start.add(Duration(milliseconds: i * 200)),
        waybiAway: false,
      );
      for (final kind in FriendKind.values) {
        final a = before.friend(kind), b = after.friend(kind);
        final dx = b.position.x - a.position.x;
        expect(dx.abs(), lessThan(.03), reason: '$kind at ${i * .2}s');
        expect((b.position.y - a.position.y).abs(), lessThan(.03));
        if (b.moving && dx.abs() > .00001) expect(b.facingRight, dx > 0);
      }
    }
  });
  test('interacting with Sett preserves Clover activity and saved garden', () {
    var life = RoomLife(startedAt: start).changeScene(HomeScene.garden);
    life = life.interact(FriendKind.clover, start, away: false);
    final now = start.add(const Duration(seconds: 6));
    life = life.interact(FriendKind.sett, now, away: false);
    life = RoomLife.fromJson(life.toJson());
    expect(life.scene, HomeScene.garden);
    expect(
      life.sample(now, waybiAway: false).friend(FriendKind.clover).activity,
      FriendActivity.watching,
    );
    expect(
      life
          .sample(now.add(const Duration(seconds: 5)), waybiAway: false)
          .friend(FriendKind.sett)
          .activity,
      FriendActivity.playing,
    );
  });
  test(
    'real arrival gifts use the country collection and deduplicate on restart',
    () async {
      final controller = GameController(
        clock: () => start,
        saveKey: 'rewards',
        engine: JourneyEngine(Random(5)),
      );
      await controller.load();
      final rewards = await Future.wait([
        controller.rememberArrival(
          tripId: 'paris-trip',
          destinationName: 'Paris',
          countryCode: 'fr',
        ),
        controller.rememberArrival(
          tripId: 'paris-trip',
          destinationName: 'Paris',
          countryCode: 'FR',
        ),
      ]);
      expect(rewards.whereType<JourneyMemory>(), hasLength(1));
      expect(
        souvenirForMemory(controller.state.memories.single).destinationId,
        'FR',
      );
      controller.dispose();
      final reopened = GameController(clock: () => start, saveKey: 'rewards');
      addTearDown(reopened.dispose);
      await reopened.load();
      expect(
        await reopened.rememberArrival(
          tripId: 'paris-trip',
          destinationName: 'Paris',
          countryCode: 'FR',
        ),
        isNull,
      );
      for (final country in ['JP', 'FR', 'GB', 'US', 'NZ', 'AU', 'CN']) {
        expect(souvenirsForCountry(country), isNotEmpty);
        expect(
          souvenirsForCountry(country)
              .every((item) => item.destinationId == country),
          isTrue,
        );
      }
      expect(
        souvenirsForCountry('DE').every((item) => item.destinationId.isEmpty),
        isTrue,
      );
    },
  );
}

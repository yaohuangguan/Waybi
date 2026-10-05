import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waybi_friends/waybi_friends.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final start = DateTime(2026, 10, 4, 10);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'older saves keep their journey and items when the room is added',
    () async {
      final original = SavedGame(
        activeJourney: ActiveJourney(
          destinationId: 'mission_bay',
          departedAt: start,
          returnAt: start.add(const Duration(minutes: 5)),
          itemIds: const ['camera'],
        ),
        selectedItemIds: const ['camera'],
      );
      SharedPreferences.setMockInitialValues({'legacy': original.encode()});
      final controller = GameController(clock: () => start, saveKey: 'legacy');
      addTearDown(controller.dispose);
      await controller.load();
      expect(controller.state.activeJourney?.destinationId, 'mission_bay');
      expect(controller.state.selectedItemIds, ['camera']);
      expect(controller.state.roomLife?.startedAt, start);
    },
  );

  test('reopening after a walk finds Clover at the window', () async {
    var now = start;
    final first = GameController(clock: () => now, saveKey: 'room');
    await first.load();
    first.dispose();
    now = now.add(const Duration(seconds: 13));
    final reopened = GameController(clock: () => now, saveKey: 'room');
    addTearDown(reopened.dispose);
    await reopened.load();
    final frame = reopened.roomLife.sample(now, waybiAway: false);
    expect(reopened.roomLife.startedAt, start);
    expect(frame.friend(FriendKind.clover).activity, FriendActivity.watching);
    expect(frame.friend(FriendKind.clover).position.x, RoomLife.window.x);
    expect(frame.friend(FriendKind.sett).position.y, RoomLife.besideWindow.y);
  });

  test(
    'departure walks to the door and stays absent after reopening',
    () async {
      var now = start;
      final controller = GameController(clock: () => now, saveKey: 'departure');
      await controller.load();
      await controller.startJourney();
      now = now.add(const Duration(seconds: 2));
      final leaving = controller.roomLife
          .sample(now, waybiAway: true)
          .friend(FriendKind.waybi);
      expect(leaving.backpack, isTrue);
      expect(leaving.activity, FriendActivity.walking);
      expect(leaving.position.x, greaterThan(RoomLife.waybiHome.x));
      controller.dispose();
      now = now.add(const Duration(seconds: 8));
      final reopened = GameController(clock: () => now, saveKey: 'departure');
      addTearDown(reopened.dispose);
      await reopened.load();
      expect(reopened.waybiAway, isTrue);
      expect(
        reopened.roomLife
            .sample(now, waybiAway: true)
            .friend(FriendKind.waybi)
            .opacity,
        0,
      );
    },
  );

  test(
    'overdue trips complete once even with concurrent resume checks',
    () async {
      var now = start;
      final controller = GameController(clock: () => now, saveKey: 'return');
      addTearDown(controller.dispose);
      await controller.load();
      await controller.startJourney();
      final expectedAt = controller.state.activeJourney!.returnAt;
      now = expectedAt.add(const Duration(hours: 1));
      await Future.wait([
        controller.tick(),
        controller.tick(),
        controller.bringWaybiHomeForPrototype(),
      ]);
      expect(controller.state.memories, hasLength(1));
      expect(controller.state.memories.single.returnedAt, expectedAt);
      expect(controller.waybiAway, isFalse);
      expect(
        controller.roomLife
            .sample(now, waybiAway: false)
            .friend(FriendKind.waybi)
            .activity,
        isNot(FriendActivity.away),
      );
      final prefs = await SharedPreferences.getInstance();
      expect(
        SavedGame.decode(prefs.getString('return')!).memories,
        hasLength(1),
      );
    },
  );

  test('room activities remain bounded after a long offline interval', () {
    final life = RoomLife(startedAt: start);
    final future = start.add(const Duration(days: 365, seconds: 7));
    final frame = RoomLife.fromJson(life.toJson())
        .sample(future, waybiAway: false);
    for (final friend in frame.friends) {
      expect(friend.position.x, inInclusiveRange(0, 1));
      expect(friend.position.y, inInclusiveRange(0, 1));
    }
    expect(frame.friend(FriendKind.clover).activity, FriendActivity.walking);
  });
}

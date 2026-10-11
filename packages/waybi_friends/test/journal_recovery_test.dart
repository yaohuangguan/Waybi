import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waybi_friends/waybi_friends.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 10, 8, 10);
  const key = 'journal';
  JourneyMemory memory(String id, {String? trip}) => JourneyMemory(
    id: id,
    destinationId: 'harbour',
    returnedAt: now,
    itemIds: const [],
    title: id,
    story: 'A trip',
    souvenir: 'A postcard',
    sourceTripId: trip,
  );

  test(
    'bundle migration merges old memories and preserves the current outing',
    () async {
      final active = ActiveJourney(
        destinationId: 'harbour',
        departedAt: now,
        returnAt: now.add(const Duration(hours: 5)),
        itemIds: const ['map'],
        traveller: FriendKind.clover,
      );
      final current = SavedGame(
        activeJourney: active,
        roomLife: RoomLife(startedAt: now).changeScene(HomeScene.garden),
        memories: [memory('new', trip: 'trip-1')],
      );
      final archive = SavedGame(
        memories: [
          memory('old'),
          memory('new'),
          memory('other-id', trip: 'trip-1'),
        ],
      );
      SharedPreferences.setMockInitialValues({
        key: current.encode(),
        '$key.pending_restore': archive.encode(),
      });
      final controller = GameController(saveKey: key, clock: () => now);
      await controller.load();
      expect(
        controller.state.memories.map((m) => m.id),
        containsAll(['new', 'old']),
      );
      expect(controller.state.memories, hasLength(2));
      expect(controller.state.activeJourney!.traveller, FriendKind.clover);
      expect(controller.state.roomLife!.scene, HomeScene.garden);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('$key.pending_restore'), isNull);
      expect(
        SavedGame.decode(prefs.getString('$key.backup')!).memories,
        hasLength(2),
      );
      controller.dispose();
      final reopened = GameController(saveKey: key, clock: () => now);
      addTearDown(reopened.dispose);
      await reopened.load();
      expect(reopened.state.memories, hasLength(2));
    },
  );

  test(
    'a damaged or missing primary journal recovers from its backup',
    () async {
      for (final primary in ['{broken', null]) {
        SharedPreferences.setMockInitialValues({
        key: ?primary,
          '$key.backup': SavedGame(memories: [memory('kept')]).encode(),
        });
        final controller = GameController(saveKey: key, clock: () => now);
        await controller.load();
        expect(controller.state.memories.single.id, 'kept');
        controller.dispose();
      }
    },
  );

  test('unrecoverable and invalid imported saves remain untouched', () async {
    for (final values in [
      {key: '{broken'},
      {
        key: SavedGame(memories: [memory('kept')]).encode(),
        '$key.pending_restore': '{broken',
      },
    ]) {
      SharedPreferences.setMockInitialValues(values);
      final controller = GameController(saveKey: key, clock: () => now);
      await expectLater(controller.load(), throwsA(anything));
      final prefs = await SharedPreferences.getInstance();
      for (final entry in values.entries) {
        expect(prefs.getString(entry.key), entry.value);
      }
      controller.dispose();
    }
  });
}

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waybi_friends/waybi_friends.dart';
import 'package:waybi_friends/src/journey_engine.dart';
import 'package:waybi_friends/src/souvenir_collection.dart';
import 'package:waybi_friends/src/souvenirs.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final now = DateTime(2026, 10, 4, 10);
  JourneyMemory memory(String gift, {String? id}) => JourneyMemory(
    id: 'test-$gift',
    destinationId: 'devonport',
    returnedAt: now,
    itemIds: const [],
    title: 'A little trip',
    story: 'Waybi watched the ferry come home.',
    souvenir: gift,
    souvenirId: id,
  );
  test('all older souvenir text gets an illustration without changing its saved story', () {
    for (final destination in destinations) {
      for (final gift in destination.souvenirs) {
        final legacy = memory(gift),
            restored = SavedGame.decode(SavedGame(memories: [legacy]).encode())
                .memories
                .single;
        expect(restored.souvenir, gift);
        expect(souvenirForMemory(restored).kind, isNot(SouvenirKind.keepsake));
      }
    }
    expect(
      souvenirForMemory(memory('an unexpected little keepsake')).kind,
      SouvenirKind.keepsake,
    );
  });
  test('returning journeys save a catalogued item and can bring letters, maps, scrolls and food', () {
    final engine = JourneyEngine(Random(42));
    final kinds = <SouvenirKind>{};
    for (var i = 0; i < 500; i++) {
      final active = engine.start(const ['camera', 'snack'], at: now);
      final returned = engine.finish(active, at: active.returnAt);
      final restored = SavedGame.decode(
        SavedGame(memories: [returned]).encode(),
      ).memories.single;
      expect(restored.souvenirId, isNotNull);
      final item = souvenirForMemory(restored);
      expect(item.id, restored.souvenirId);
      kinds.add(item.kind);
    }
    expect(
      kinds,
      containsAll([
        SouvenirKind.letter,
        SouvenirKind.map,
        SouvenirKind.scroll,
        SouvenirKind.cookie,
        SouvenirKind.bun,
      ]),
    );
  });
  testWidgets(
    'a saved letter has a local picture and opens its contents from the collection',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final letter = memory('A letter from Waybi', id: 'waybi-letter');
      SharedPreferences.setMockInitialValues({
        'souvenirs': SavedGame(memories: [letter, letter]).encode(),
      });
      final controller = GameController(saveKey: 'souvenirs');
      addTearDown(controller.dispose);
      await controller.load();
      await tester.pumpWidget(
        MaterialApp(home: SouvenirCollectionPage(controller: controller)),
      );
      await tester.pumpAndSettle();
      expect(find.text('2 collected'), findsOneWidget);
      final art = tester.widget<Image>(find.byType(Image).first);
      expect((art.image as AssetImage).assetName, endsWith('/letter.png'));
      await tester.tap(find.byKey(const ValueKey('souvenir-waybi-letter')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Dear Clover and Sett'), findsOneWidget);
      await tester.ensureVisible(find.text('Keep it safe'));
      await tester.tap(find.text('Keep it safe'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Dear Clover and Sett'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

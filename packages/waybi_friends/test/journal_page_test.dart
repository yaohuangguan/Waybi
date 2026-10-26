import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waybi_friends/src/journal_page.dart';
import 'package:waybi_friends/src/souvenir_collection.dart';
import 'package:waybi_friends/waybi_friends.dart';

void main() {
  testWidgets('saved journal opens its postcards and returns from souvenirs', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = GameController();
    addTearDown(controller.dispose);
    final destinations = ['mission_bay', 'piha', 'waiheke', 'unknown'];
    controller.state = SavedGame(
      memories: [
        for (final destination in destinations)
          JourneyMemory(
            id: 'saved-$destination',
            destinationId: destination,
            returnedAt: DateTime(2026, 10, 16),
            itemIds: const ['water'],
            title: 'A saved journey',
            story: 'A happy memory from $destination.',
            souvenir: 'A keepsake',
          ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: JournalPage(controller: controller)),
      ),
    );
    expect(find.text('4 journeys so far.'), findsOneWidget);
    expect(find.text('Nothing here yet.'), findsNothing);
    for (final destination in destinations) {
      expect(find.text('A happy memory from $destination.'), findsOneWidget);
    }

    await tester.tap(find.text('Souvenirs'));
    await tester.pumpAndSettle();
    expect(find.byType(SouvenirCollectionPage), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(JournalPage), findsOneWidget);
    expect(find.text('4 journeys so far.'), findsOneWidget);

    final card = find
        .descendant(of: find.byType(ListView), matching: find.byType(InkWell))
        .first;
    await tester.tap(card);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Postcard stamp'), findsOneWidget);
    expect(find.text('Put it in the journal'), findsOneWidget);
    await tester.tap(find.text('Put it in the journal'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Postcard stamp'), findsNothing);
    expect(controller.state.memories, hasLength(4));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

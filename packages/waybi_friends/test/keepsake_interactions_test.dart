import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waybi_friends/waybi_friends.dart';
import 'package:waybi_friends/src/postcard_dialog.dart';

JourneyMemory memory(String destination, {bool chinese = false}) =>
    JourneyMemory(
      id: 'trip-$destination',
      destinationId: destination,
      returnedAt: DateTime(2026, 10, 16),
      itemIds: const ['water'],
      title: 'A quiet journey',
      story: 'A memory of a happy journey.',
      souvenir: 'A keepsake',
      titleZh: chinese ? '安静的旅程' : null,
      storyZh: chinese ? '旅途中留下的快乐回忆。' : null,
    );
Future<void> frames(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 450));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final chinese in [false, true]) {
    testWidgets(
      'postcards and souvenirs retain content, locale and navigation ($chinese)',
      (t) async {
        t.view.physicalSize = const Size(390, 844);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        late BuildContext context;
        await t.pumpWidget(
          MaterialApp(
            locale: Locale(chinese ? 'zh' : 'en'),
            supportedLocales: const [Locale('en'), Locale('zh')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: Builder(
              builder: (c) {
                context = c;
                return const Scaffold(body: Text('Journal home'));
              },
            ),
          ),
        );
        for (final destination in [
          'mission_bay',
          'waiheke',
          'piha',
          'mt_eden',
          'unknown',
        ]) {
          final m = memory(destination, chinese: chinese);
          final shown = showPostcardDialog(context, m);
          await frames(t);
          expect(
            find.text(chinese ? '安静的旅程' : 'A quiet journey'),
            findsOneWidget,
          );
          expect(find.bySemanticsLabel('Postcard stamp'), findsOneWidget);
          expect(find.byType(SouvenirReward), findsOneWidget);
          await t.ensureVisible(find.byType(SouvenirReward));
          await t.tap(find.byType(SouvenirReward));
          await frames(t);
          expect(
            find.text(chinese ? '收藏一点旅途的惊喜' : 'A LITTLE SOMETHING TO KEEP'),
            findsOneWidget,
          );
          final close = find.text(chinese ? '好好收起来' : 'Keep it safe');
          await t.ensureVisible(close);
          await t.tap(close);
          await frames(t);
          final journal = find.text(
            chinese ? '放进旅行册' : 'Put it in the journal',
          );
          await t.ensureVisible(journal);
          await t.tap(journal);
          await frames(t);
          await shown;
          expect(find.text('Journal home'), findsOneWidget);
          expect(
            find.text(chinese ? '安静的旅程' : 'A quiet journey'),
            findsNothing,
          );
          expect(t.takeException(), isNull);
        }
        await t.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'room friend actions update persistent life and show localized thoughts',
    (t) async {
      final clock = DateTime(2026, 10, 16, 10);
      final controller = GameController(
        clock: () => clock,
        saveKey: 'friend-actions',
      );
      await t.pumpWidget(
        MaterialApp(home: GameShell(controller: controller, embedded: true)),
      );
      await frames(t);
      await frames(t);
      for (final kind in FriendKind.values) {
        await t.tap(find.byKey(ValueKey('friend-action-${kind.name}')));
        await frames(t);
        expect(find.byKey(ValueKey('interact-${kind.name}')), findsOneWidget);
        await t.tap(find.byKey(ValueKey('interact-${kind.name}')));
        await frames(t);
        expect(find.byKey(ValueKey('interact-${kind.name}')), findsNothing);
        expect(t.takeException(), isNull);
      }
      await t.tap(find.text('Garden'));
      await frames(t);
      expect(controller.roomLife.scene, HomeScene.garden);
      await t.tap(find.text('Room'));
      await frames(t);
      expect(controller.roomLife.scene, HomeScene.room);
      expect(
        (await SharedPreferences.getInstance()).getString('friend-actions'),
        isNotNull,
      );
      await t.pumpWidget(const SizedBox());
    },
  );
}

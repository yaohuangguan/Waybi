import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waybi_friends/waybi_friends.dart';
import 'package:waybi_friends/src/friend_strings.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'Chinese room keeps its language in journal, bag and packing routes',
    (tester) async {
      final now = DateTime(2026, 10, 5);
      final controller = GameController(saveKey: 'localized', clock: () => now);
      addTearDown(controller.dispose);
      await controller.load();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          supportedLocales: const [Locale('en'), Locale('zh')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Builder(
            builder: (context) => Localizations.override(
              context: context,
              locale: const Locale('zh'),
              child: GameShell(embedded: true, controller: controller),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byTooltip('旅行册'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('还没有旅行记忆。'), findsOneWidget);
      expect(find.text('Nothing here yet.'), findsNothing);
      await tester.tap(find.byTooltip('返回').hitTestable());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.byTooltip('背包'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('小相机'), findsOneWidget);
      expect(find.text('Tiny camera'), findsNothing);
      await tester.tap(find.byTooltip('返回').hitTestable());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.text('打包'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('准备一次小旅行'), findsOneWidget);
      expect(find.textContaining('已装 0 / 2 件'), findsOneWidget);
      expect(find.textContaining('packed'), findsNothing);
      final sheetChoice = find.descendant(
        of: find.byType(SegmentedButton<FriendKind>),
        matching: find.text('Sett'),
      );
      await tester.tap(sheetChoice);
      await tester.pump();
      await tester.ensureVisible(find.byKey(const ValueKey('send-friend-out')));
      await tester.tap(find.byKey(const ValueKey('send-friend-out')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(controller.isAway(FriendKind.sett), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'hours are readable and legacy stories follow the current language',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [Locale('zh')],
          locale: const Locale('zh'),
          home: Builder(
            builder: (context) {
              final memory = JourneyMemory(
                id: 'old',
                destinationId: 'mission_bay',
                returnedAt: DateTime(2026),
                itemIds: const [],
                title: 'A little trip',
                story: 'Old English story',
                souvenir: 'a tiny shell',
              );
              return Text(
                '${remainingJourneyTime(context, const Duration(hours: 5, minutes: 50))}\n${memoryStory(context, memory)}',
              );
            },
          ),
        ),
      );
      expect(find.textContaining('5 小时 50 分钟'), findsOneWidget);
      expect(find.textContaining('Old English story'), findsNothing);
    },
  );
}

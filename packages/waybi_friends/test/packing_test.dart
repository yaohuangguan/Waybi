import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waybi_friends/waybi_friends.dart';
import 'package:waybi_friends/src/room_page.dart';
import 'package:waybi_friends/src/travel_item_art.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'a full bag keeps chosen items; one item and an empty bag can travel',
    () async {
      final controller = GameController(saveKey: 'packing');
      addTearDown(controller.dispose);
      await controller.load();
      expect(controller.state.selectedItemIds, isEmpty);
      expect(await controller.toggleItem('camera'), isTrue);
      expect(await controller.toggleItem('snack'), isTrue);
      expect(await controller.toggleItem('umbrella'), isFalse);
      expect(controller.state.selectedItemIds, ['camera', 'snack']);
      await controller.toggleItem('snack');
      await controller.startJourney();
      expect(controller.state.activeJourney!.itemIds, ['camera']);
      expect(await controller.toggleItem('toy'), isFalse);
      await controller.bringWaybiHomeForPrototype();
      await controller.toggleItem('camera');
      await controller.startJourney();
      expect(controller.state.activeJourney!.itemIds, isEmpty);
      await controller.bringWaybiHomeForPrototype();
      expect(controller.state.memories.first.story, contains('almost nothing'));
      final reopened = GameController(saveKey: 'packing');
      addTearDown(reopened.dispose);
      await reopened.load();
      expect(reopened.state.selectedItemIds, isEmpty);
    },
  );

  testWidgets(
    'packing sheet paints all items and explains capacity without replacing selections',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fontPath = Platform.environment['PACKING_PREVIEW_FONT'];
      if (fontPath != null) {
        final font = FontLoader('Roboto')
          ..addFont(
            Future.value(
              ByteData.sublistView(File(fontPath).readAsBytesSync()),
            ),
          );
        await font.load();
      }
      final controller = GameController(saveKey: 'sheet');
      await controller.load();
      addTearDown(controller.dispose);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            home: Scaffold(body: RoomPage(controller: controller)),
          ),
        ),
      );
      await tester.tap(find.text('Pack'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(TravelItemArt), findsNWidgets(4));
      expect(find.textContaining('0 / 2 packed'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pack-item-camera')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('pack-item-snack')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('pack-item-umbrella')));
      await tester.pump();
      expect(controller.state.selectedItemIds, ['camera', 'snack']);
      expect(
        find.text('The bag is full. Remove an item first.'),
        findsOneWidget,
      );
      expect(find.textContaining('2 / 2 packed'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      final preview = Platform.environment['PACKING_PREVIEW_PATH'];
      if (preview != null) {
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 2);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(preview).writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waybi_friends/waybi_friends.dart';
import 'package:waybi_friends/src/living_room_scene.dart';

void main() {
  final start = DateTime(2026, 10, 4, 10);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final screen in [const Size(320, 568), const Size(390, 844)]) {
    testWidgets('room fits $screen and its friends are tappable', (
      tester,
    ) async {
      tester.view.physicalSize = screen;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LivingRoomScene(
              life: RoomLife(startedAt: start),
              waybiAway: false,
              animate: false,
              clock: () => start.add(const Duration(seconds: 13)),
              onWaybiTap: () => taps++,
              onCloverTap: () => taps++,
              onSettTap: () => taps++,
            ),
          ),
        ),
      );
      expect(find.text('Clover'), findsOneWidget);
      expect(find.text('Sett'), findsOneWidget);
      expect(find.text('Waybi'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('friend-rig-clover')));
      expect(taps, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('Me entry opens a room with journal and bag, then returns', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('en'), Locale('zh')],
        home: const Scaffold(body: Center(child: FriendsEntry())),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('waybi-friends-entry')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byTooltip('Journal'), findsOneWidget);
    expect(find.byTooltip('Bag'), findsOneWidget);
    expect(find.text('Clover'), findsOneWidget);
    await tester.tap(find.byTooltip('Journal'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Clover').hitTestable(), findsNothing);
    expect(find.text('Journal'), findsWidgets);
    await tester.tap(find.byTooltip('Back').hitTestable());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Clover'), findsOneWidget);
    await tester.tap(find.byTooltip('Back').hitTestable());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Visit Waybi, Clover & Sett'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'resuming the app reconciles a journey without restarting the room',
    (tester) async {
      var now = start;
      final controller = GameController(clock: () => now, saveKey: 'resume');
      await tester.pumpWidget(
        MaterialApp(home: GameShell(controller: controller)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await controller.startJourney();
      await tester.pump();
      final returnAt = controller.state.activeJourney!.returnAt;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      now = returnAt.add(const Duration(hours: 2));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(controller.waybiAway, isFalse);
      expect(controller.state.memories, hasLength(1));
      expect(controller.roomLife.startedAt, start);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('packing on a small phone starts a visible departure', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var now = start;
    final controller = GameController(clock: () => now, saveKey: 'packing');
    await tester.pumpWidget(
      MaterialApp(home: GameShell(embedded: true, controller: controller)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Pack'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Send Waybi out'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Send Waybi out'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(controller.waybiAway, isTrue);
    now = start.add(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.byKey(const ValueKey('friend-rig-waybi')), findsOneWidget);
    now = start.add(const Duration(seconds: 6));
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.byKey(const ValueKey('friend-rig-waybi')), findsNothing);
    expect(find.text('Clover'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Chinese profile entry opens localized room controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('en'), Locale('zh')],
        home: const Scaffold(body: Center(child: FriendsEntry(chinese: true))),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('waybi-friends-entry')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byTooltip('旅行册'), findsOneWidget);
    expect(find.byTooltip('背包'), findsOneWidget);
    expect(find.text('打包'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  if (Platform.environment['ROOM_PREVIEW_DIRECTORY'] != null) {
    testWidgets('render the room demonstration', (tester) async {
      final fontPath = Platform.environment['ROOM_PREVIEW_FONT'];
      if (fontPath != null) {
        final font = FontLoader('Roboto')
          ..addFont(
            Future.value(
              ByteData.sublistView(File(fontPath).readAsBytesSync()),
            ),
          );
        await font.load();
      }
      tester.view.physicalSize = const Size(360, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final dir = Directory(Platform.environment['ROOM_PREVIEW_DIRECTORY']!);
      await tester.runAsync(() => dir.create(recursive: true));
      final boundary = GlobalKey();
      for (var i = 0; i <= 144; i++) {
        final now = start.add(Duration(milliseconds: i * 125));
        final life = i < 96
            ? RoomLife(startedAt: start)
            : RoomLife(
                startedAt: start,
                departedAt: start.add(const Duration(seconds: 12)),
              );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(8),
                child: RepaintBoundary(
                  key: boundary,
                  child: LivingRoomScene(
                    life: life,
                    waybiAway: i >= 96,
                    animate: false,
                    clock: () => now,
                    onWaybiTap: () {},
                    onCloverTap: () {},
                    onSettTap: () {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 1.5);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('${dir.path}/room-${i.toString().padLeft(3, '0')}.png')
              .writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}

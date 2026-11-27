import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waybi_mobile/domain/navigation_lanes.dart';
import 'package:waybi_mobile/drive/drive_engine.dart';
import 'package:waybi_mobile/widgets/navigation_overlay.dart';

NavigationGuidance guidance(num step, {String? then}) => NavigationGuidance(
  instruction: 'Turn right onto Symonds Street',
  maneuverIcon: Icons.turn_right_rounded,
  stepMeters: step,
  remainingMeters: 5200,
  remainingSeconds: 720,
  thenInstruction: then,
);

void main() {
  test('guidance and lanes compare by value', () {
    const lane = NavigationLane({LaneArrowDirection.left}, true);
    expect(const NavigationLane({LaneArrowDirection.left}, true), lane);
    expect(
      lane.hashCode,
      const NavigationLane({LaneArrowDirection.left}, true).hashCode,
    );
    expect(guidance(200), guidance(200));
    expect(guidance(200).hashCode, guidance(200).hashCode);
    expect(guidance(200) == guidance(180), isFalse);
    final notifier = ValueNotifier(guidance(200));
    var notified = 0;
    notifier.addListener(() => notified++);
    notifier.value = guidance(200);
    expect(notified, 0, reason: 'equal guidance must not rebuild the HUD');
    notifier.value = guidance(150);
    expect(notified, 1);
    notifier.dispose();
  });

  testWidgets('engine ticks and guidance updates do not rebuild the deck or '
      'report insets per frame', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final engine = DriveEngine();
    addTearDown(engine.dispose);
    final live = ValueNotifier(guidance(300));
    addTearDown(live.dispose);
    var deckBuilds = 0;
    final top = <double>[];
    final bottom = <double>[];
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NavigationOverlay(
            engine: engine,
            guidanceListenable: live,
            onTopInsetChanged: top.add,
            onBottomInsetChanged: bottom.add,
            destinationTitle: 'University of Auckland',
            gpsAccuracy: 5,
            voiceEnabled: true,
            lanesEnabled: true,
            onEnd: () {},
            onRecenter: () {},
            onOverview: () {},
            northUp: false,
            onCompassToggle: () {},
            onReport: () {},
            onSearchAlongRoute: () {},
            onDirections: () {},
            onShare: () {},
            onSettings: () {},
            onLayers: () {},
            onVoiceToggle: () {},
            onLanesToggle: () {},
            arrivalPanel: Builder(
              builder: (context) {
                deckBuilds++;
                return const SizedBox(height: 40, child: Text('arrival'));
              },
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('arrivalSummary')));
    await t.pumpAndSettle();
    expect(find.text('arrival'), findsOneWidget);
    final reportsBefore = (top.length, bottom.length);
    final buildsBefore = deckBuilds;

    for (var metres = 290; metres > 200; metres -= 10) {
      live.value = guidance(metres);
      engine.notifyListeners();
      await t.pump(const Duration(milliseconds: 16));
    }
    await t.pumpAndSettle();
    expect(find.text('210 m'), findsOneWidget);
    expect(deckBuilds, buildsBefore, reason: 'ticks rebuild only the HUD');
    expect((top.length, bottom.length), reportsBefore);

    // A taller banner animates over ~13 frames but reports once, settled.
    live.value = guidance(200, then: 'Keep left onto Grafton Bridge');
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 16));
    }
    await t.pumpAndSettle();
    expect(top.length, reportsBefore.$1 + 1);
    expect(top.last, greaterThan(top[top.length - 2]));
    expect(deckBuilds, buildsBefore);
  });
}

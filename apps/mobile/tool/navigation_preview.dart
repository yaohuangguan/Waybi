// Visual harness for the production HUD and summary. No native map or GPS is
// simulated here: only explicit sample guidance and a recorded route sketch.
// flutter run -d web-server --target tool/navigation_preview.dart --web-port 5180
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:kiwi_lens_mobile/domain/map_provider.dart';
import 'package:kiwi_lens_mobile/domain/safety_camera.dart';
import 'package:kiwi_lens_mobile/drive/drive_engine.dart';
import 'package:kiwi_lens_mobile/drive/journey_tracker.dart';
import 'package:kiwi_lens_mobile/theme/kiwi_lens_theme.dart';
import 'package:kiwi_lens_mobile/widgets/journey_summary_sheet.dart';
import 'package:kiwi_lens_mobile/widgets/navigation_overlay.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SemanticsBinding.instance.ensureSemantics();
  runApp(const NavigationPreview());
}

class NavigationPreview extends StatefulWidget {
  const NavigationPreview({super.key});
  @override
  State<NavigationPreview> createState() => _NavigationPreviewState();
}

class _NavigationPreviewState extends State<NavigationPreview> {
  final engine = DriveEngine()
    ..upcomingCamera = const SafetyCamera(
      id: 'preview-camera',
      name: 'Queen St camera',
      region: 'Auckland',
      suburb: 'City',
      location: 'Queen Street',
      type: 'Spot speed',
      latitude: -36.845,
      longitude: 174.76,
    )
    ..upcomingCameraDistanceMeters = 300
    ..speedKph = 38
    ..speedLimitKph = 50;
  String language = 'zh';
  bool lanes = true, voice = true, dark = false;
  static const points = [
    GeoPoint(-36.862, 174.754),
    GeoPoint(-36.858, 174.754),
    GeoPoint(-36.858, 174.760),
    GeoPoint(-36.853, 174.760),
    GeoPoint(-36.853, 174.765),
    GeoPoint(-36.849, 174.765),
  ];
  @override
  void dispose() {
    engine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Kiwi Lens navigation preview',
    theme: dark
        ? KiwiLensTheme.darkFor(language)
        : KiwiLensTheme.lightFor(language),
    locale: Locale(language),
    supportedLocales: const [Locale('en'), Locale('zh')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: Builder(
      builder: (context) => Scaffold(
        appBar: AppBar(
          title: const Text(
            'Kiwi Lens · UI preview',
            style: TextStyle(fontSize: 15),
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  setState(() => language = language == 'zh' ? 'en' : 'zh'),
              child: Text(language == 'zh' ? 'EN' : '中文'),
            ),
            IconButton(
              tooltip: 'Camera alert',
              onPressed: () => setState(() {
                engine.upcomingCameraDistanceMeters =
                    engine.upcomingCameraDistanceMeters == null ? 300 : null;
              }),
              icon: const Icon(Icons.speed_rounded),
            ),
            IconButton(
              tooltip: 'Theme',
              onPressed: () => setState(() => dark = !dark),
              icon: const Icon(Icons.brightness_6),
            ),
          ],
        ),
        body: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(painter: JourneyOverviewPainter(points)),
            ),
            Positioned.fill(
              child: NavigationOverlay(
                engine: engine,
                language: language,
                guidance: NavigationGuidance(
                  instruction: language == 'zh'
                      ? '左转，驶向 Queen Street'
                      : 'Turn left onto Queen Street',
                  maneuverIcon: Icons.turn_left_rounded,
                  stepMeters: 180,
                  remainingMeters: 2400,
                  remainingSeconds: 360,
                  lanes: const [
                    NavigationLane('←', true),
                    NavigationLane('↑', false),
                    NavigationLane('↑→', false),
                  ],
                ),
                destinationTitle: 'Kiwi Cafe · Auckland',
                gpsAccuracy: 5,
                voiceEnabled: voice,
                lanesEnabled: lanes,
                northUp: false,
                onEnd: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => JourneySummarySheet(
                    language: language,
                    summary: JourneySummary(
                      destination: 'Kiwi Cafe · Auckland',
                      startedAt: DateTime.now().subtract(
                        const Duration(minutes: 18),
                      ),
                      finishedAt: DateTime.now(),
                      distanceMeters: 8200,
                      points: points,
                      cameraCount: 3,
                      arrived: true,
                    ),
                  ),
                ),
                onRecenter: () {},
                onOverview: () {},
                onCompassToggle: () {},
                onReport: () {},
                onSearchAlongRoute: () {},
                onDirections: () {},
                onShare: () {},
                onSettings: () {},
                onLayers: () {},
                onVoiceToggle: () => setState(() => voice = !voice),
                onLanesToggle: () => setState(() => lanes = !lanes),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

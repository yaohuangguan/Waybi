import 'package:flutter/material.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart'
    show SpeedAlertSeverity;
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../drive/camera_alert_lifecycle.dart';
import '../drive/drive_engine.dart';
import '../drive/navigation_language.dart';
import '../domain/navigation_lanes.dart';
import '../theme/waybi_theme.dart';
import 'road_event_timeline.dart';
import 'lane_arrow.dart';
import 'navigation_maneuver_icon.dart';

class DriveHud extends StatelessWidget {
  const DriveHud({super.key, required this.engine, required this.onStop});

  final DriveEngine engine;
  final VoidCallback onStop;

  String _formatDistance(double? meters, [String language = 'en']) =>
      meters == null ? '—' : navigationMetres(meters, language);

  @override
  Widget build(BuildContext context) {
    final language = Localizations.localeOf(context).languageCode;
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final nav = engine.navInfo;
    final step = nav?.currentStep;
    final camera = engine.upcomingCamera;
    final cameraDistance = engine.upcomingCameraDistanceMeters;
    final passedCamera = engine.passedCamera;
    final intelligenceLabel = switch (engine.roadIntelligenceStatus) {
      'live' || 'seed' => 'NZ safety camera alerts active',
      'stale' => 'Camera data may be out of date',
      'unsupported' => 'Road Intelligence unavailable here',
      _ => 'Camera data unavailable',
    };
    final speeding =
        engine.speedSeverity == SpeedAlertSeverity.minor ||
        engine.speedSeverity == SpeedAlertSeverity.major ||
        (engine.speedLimitKph != null &&
            engine.speedKph > engine.speedLimitKph!);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
        child: Column(
          children: [
            if (step == null)
              PointerInterceptor(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: WaybiColors.midnightOcean.withValues(alpha: .95),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.directions_car_filled_rounded,
                        color: WaybiColors.sky,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              engine.routed ? 'Navigation' : 'Just Drive',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              intelligenceLabel,
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: onStop,
                        icon: const Icon(Icons.close_rounded),
                        color: Colors.white,
                        tooltip: 'End drive',
                      ),
                    ],
                  ),
                ),
              ),
            if (step != null)
              PointerInterceptor(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
                  decoration: BoxDecoration(
                    color: WaybiColors.midnightOcean.withValues(alpha: .95),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        navigationManeuverIcon(step.maneuver.name),
                        color: WaybiColors.sky,
                        size: 34,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _formatDistance(
                                nav?.distanceToCurrentStepMeters?.toDouble(),
                              ),
                              style: const TextStyle(
                                color: WaybiColors.sky,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              step.fullInstructions ??
                                  step.fullRoadName ??
                                  'Continue',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (step.lanes?.isNotEmpty ?? false) ...[
                              const SizedBox(height: 9),
                              Wrap(
                                spacing: 5,
                                children: step.lanes!.map((lane) {
                                  final recommended = lane.laneDirections.any(
                                    (direction) => direction.isRecommended,
                                  );
                                  final directions = laneDirections(
                                    lane.laneDirections.map(
                                      (d) => d.laneShape.name,
                                    ),
                                  );
                                  return Container(
                                    constraints: const BoxConstraints(
                                      minWidth: 31,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: recommended
                                          ? WaybiColors.sky
                                          : WaybiColors.darkSurface,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: LaneArrow(
                                      directions: directions,
                                      size: 28,
                                      language: language,
                                      color: recommended
                                          ? WaybiColors.midnightOcean
                                          : Colors.white70,
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: onStop,
                        icon: const Icon(Icons.close_rounded),
                        color: Colors.white70,
                        tooltip: 'End drive',
                      ),
                    ],
                  ),
                ),
              ),
            if (passedCamera != null &&
                engine.cameraAlertState.phase == CameraAlertPhase.passed)
              PointerInterceptor(
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: WaybiSpacing.x2),
                  padding: const EdgeInsets.symmetric(
                    horizontal: WaybiSpacing.x4,
                    vertical: WaybiSpacing.x3,
                  ),
                  decoration: BoxDecoration(
                    color: WaybiColors.success,
                    borderRadius: BorderRadius.circular(WaybiRadius.panel),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.check_circle_rounded,
                        color: Colors.white,
                      ),
                      const SizedBox(width: WaybiSpacing.x3),
                      Expanded(
                        child: Text(
                          'Camera passed - ${passedCamera.location}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (camera != null && cameraDistance != null)
              PointerInterceptor(
                child: Container(
                  key: const ValueKey('driveCameraAlert'),
                  width: double.infinity,
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: WaybiColors.sky,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [
                      BoxShadow(
                        blurRadius: 20,
                        color: Color(0x26000000),
                        offset: Offset(0, 7),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.speed_rounded,
                        color: WaybiColors.ocean,
                        size: 30,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${language == 'zh' ? '摄像头' : 'Safety camera'} · ${_formatDistance(cameraDistance, language)}',
                              style: const TextStyle(
                                color: WaybiColors.deepOcean,
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${camera.type} · ${camera.location}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: WaybiColors.deepOcean,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const Spacer(),
            if (engine.upcomingRoadEvents.isNotEmpty && camera == null) ...[
              RoadEventTimeline(events: engine.upcomingRoadEvents, dark: dark),
              const SizedBox(height: WaybiSpacing.x2),
            ],
            PointerInterceptor(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: WaybiColors.midnightOcean.withValues(alpha: .95),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    _SpeedMetric(
                      speedKph: engine.speedKph,
                      speedLimitKph: engine.speedLimitKph,
                      warning: speeding,
                    ),
                    Container(width: 1, height: 34, color: Colors.white12),
                    _Metric(
                      label: 'CAMERA',
                      value: cameraDistance == null
                          ? '—'
                          : _formatDistance(cameraDistance),
                    ),
                    if (nav?.distanceToFinalDestinationMeters != null) ...[
                      Container(width: 1, height: 34, color: Colors.white12),
                      _Metric(
                        label: 'REMAIN',
                        value: _formatDistance(
                          nav!.distanceToFinalDestinationMeters!.toDouble(),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpeedMetric extends StatelessWidget {
  const _SpeedMetric({
    required this.speedKph,
    required this.speedLimitKph,
    required this.warning,
  });

  final double speedKph;
  final int? speedLimitKph;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final accent = warning ? const Color(0xFFFF6868) : WaybiColors.sky;

    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 5),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: warning ? const Color(0xFFFF5757) : Colors.white24,
            width: warning ? 2.2 : 1,
          ),
          boxShadow: warning
              ? const [
                  BoxShadow(
                    color: Color(0x40FF5757),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'SPEED',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 9,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  speedKph.round().toString(),
                  style: TextStyle(
                    color: accent,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 3),
                const Padding(
                  padding: EdgeInsets.only(bottom: 2),
                  child: Text(
                    'km/h',
                    style: TextStyle(color: Colors.white54, fontSize: 8),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 1),
            Text(
              speedLimitKph == null ? 'LIMIT —' : 'LIMIT $speedLimitKph',
              style: TextStyle(
                color: warning ? accent : Colors.white60,
                fontSize: 8,
                fontWeight: FontWeight.w700,
                letterSpacing: .4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 9,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    color: WaybiColors.sky,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

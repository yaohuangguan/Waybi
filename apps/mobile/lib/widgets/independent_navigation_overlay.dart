import 'package:flutter/material.dart';

import '../domain/route_option.dart';
import '../drive/drive_engine.dart';
import '../drive/navigation_language.dart';
import '../providers/independent_navigation_engine.dart';
import 'navigation_overlay.dart';

IconData independentManeuverIcon(RouteStepInfo? step) {
  final type = step?.maneuverType ?? '';
  final modifier = step?.maneuverModifier ?? '';
  if (type == 'arrive') return Icons.flag_rounded;
  if (modifier == 'uturn') return Icons.u_turn_left_rounded;
  if (type.contains('roundabout') || type == 'rotary') {
    return Icons.roundabout_left_rounded;
  }
  if (modifier.contains('right')) return Icons.turn_right_rounded;
  if (modifier.contains('left')) return Icons.turn_left_rounded;
  return Icons.straight_rounded;
}

class IndependentNavigationOverlay extends StatelessWidget {
  const IndependentNavigationOverlay({
    super.key,
    required this.engine,
    required this.drive,
    required this.destination,
    required this.language,
    required this.onEnd,
    required this.onRecenter,
    required this.onOverview,
    this.following = true,
    this.overviewMode = false,
    required this.northUp,
    this.perspectiveTilted = false,
    required this.onCompassToggle,
    required this.onReport,
    required this.onSearchAlongRoute,
    required this.onDirections,
    required this.onShare,
    required this.onSettings,
    required this.onLayers,
    required this.onVoiceToggle,
    required this.onLanesToggle,
    required this.voiceEnabled,
    required this.lanesEnabled,
    this.gpsAccuracy,
    this.arrivalPanel,
    this.offlineReady = false,
    this.offlineCachedAt,
    this.onTopInsetChanged,
    this.onBottomInsetChanged,
  });
  final IndependentNavigationEngine engine;
  final DriveEngine drive;
  final String destination;
  final String language;
  final double? gpsAccuracy;
  final bool following;
  final bool overviewMode;
  final bool northUp;
  final bool perspectiveTilted;
  final bool voiceEnabled;
  final bool lanesEnabled;
  final Widget? arrivalPanel;
  final bool offlineReady;
  final DateTime? offlineCachedAt;
  final ValueChanged<double>? onTopInsetChanged, onBottomInsetChanged;
  final VoidCallback onEnd,
      onRecenter,
      onOverview,
      onCompassToggle,
      onReport,
      onSearchAlongRoute,
      onDirections,
      onShare,
      onSettings,
      onLayers,
      onVoiceToggle,
      onLanesToggle;

  String _text(String en, String zh) => language == 'zh' ? zh : en;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([engine, drive]),
    builder: (context, _) {
      final next = engine.nextStep;
      final status = engine.arrived
          ? _text('Arrived at $destination', '已抵达 $destination')
          : engine.rerouting
          ? _text('Updating route…', '正在重新规划路线…')
          : engine.offRoute
          ? _text('Off route · finding your way', '已偏离路线，正在更新')
          : engine.error != null
          ? _text('Route update unavailable · retrying', '路线更新暂不可用，正在重试')
          : drive.error != null
          ? _text('Waiting for accurate GPS', '正在等待准确定位')
          : null;
      return NavigationOverlay(
        onTopInsetChanged: onTopInsetChanged,
        onBottomInsetChanged: onBottomInsetChanged,
        engine: drive,
        language: language,
        guidance: NavigationGuidance(
          instruction: status ?? routeStepInstruction(next, language),
          maneuverIcon: engine.arrived
              ? Icons.flag_rounded
              : engine.rerouting || engine.offRoute
              ? Icons.alt_route_rounded
              : independentManeuverIcon(next),
          stepMeters: engine.offRoute ? null : engine.distanceToStepMeters,
          remainingMeters: engine.remainingDistanceMeters,
          remainingSeconds: engine.remainingSeconds,
          lanes:
              engine.distanceToStepMeters <= 300 &&
                  !engine.offRoute &&
                  !engine.arrived
              ? [
                  for (final lane in next?.lanes ?? <RouteLane>[])
                    NavigationLane(
                      lane.indications
                          .map(
                            (name) => name.contains('left')
                                ? '←'
                                : name.contains('right')
                                ? '→'
                                : name == 'uturn'
                                ? '↶'
                                : '↑',
                          )
                          .toSet()
                          .join(),
                      lane.recommended,
                    ),
                ]
              : const [],
        ),
        destinationTitle: destination,
        gpsAccuracy: gpsAccuracy,
        voiceEnabled: voiceEnabled,
        lanesEnabled: lanesEnabled,
        onEnd: onEnd,
        onRecenter: onRecenter,
        onOverview: onOverview,
        following: following,
        overviewMode: overviewMode,
        northUp: northUp,
        perspectiveTilted: perspectiveTilted,
        perspectiveAvailable: false,
        onCompassToggle: onCompassToggle,
        onReport: onReport,
        onSearchAlongRoute: onSearchAlongRoute,
        onDirections: onDirections,
        onShare: onShare,
        onSettings: onSettings,
        onLayers: onLayers,
        onVoiceToggle: onVoiceToggle,
        onLanesToggle: onLanesToggle,
        arrivalPanel: arrivalPanel,
        offlineReady: offlineReady,
        usingOfflineGuidance: engine.error != null,
        offlineCachedAt: offlineCachedAt,
      );
    },
  );
}
